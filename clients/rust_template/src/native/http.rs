//! HTTP over ureq. ureq blocks, so calls run on a few worker threads, started as
//! they are needed; the reply crosses back through the inbox like any other.

use std::collections::VecDeque;
use std::sync::{Arc, Condvar, Mutex, MutexGuard, PoisonError};
use std::thread;

use ureq::{Agent, Body, RequestBuilder};

use crate::transport::{HttpDone, HttpRequest, HttpResponse, HttpTransport};

// Enough that a slow call does not hold up the frame's others; a game makes few
// at a time.
const MAX_WORKERS: usize = 4;

type Job = (HttpRequest, HttpDone);

#[derive(Default)]
struct Queue {
    jobs: VecDeque<Job>,
    idle: usize,
    workers: usize,
    closed: bool,
}

struct Pool {
    agent: Agent,
    queue: Mutex<Queue>,
    ready: Condvar,
}

impl Pool {
    fn lock(&self) -> MutexGuard<'_, Queue> {
        self.queue.lock().unwrap_or_else(PoisonError::into_inner)
    }

    fn work(&self) {
        loop {
            let mut queue = self.lock();
            while queue.jobs.is_empty() && !queue.closed {
                queue.idle += 1;
                queue = self
                    .ready
                    .wait(queue)
                    .unwrap_or_else(PoisonError::into_inner);
                queue.idle -= 1;
            }
            let Some((request, done)) = queue.jobs.pop_front() else {
                return;
            };
            drop(queue);
            done(run(&self.agent, &request));
        }
    }
}

/// `HttpTransport` over ureq, with rustls for TLS.
pub struct UreqTransport {
    pool: Arc<Pool>,
}

impl Default for UreqTransport {
    fn default() -> Self {
        Self::new()
    }
}

impl UreqTransport {
    pub fn new() -> Self {
        let agent = Agent::config_builder()
            // A 4xx or 5xx is a reply the caller must see, not a transport
            // failure.
            .http_status_as_error(false)
            .build()
            .into();
        Self {
            pool: Arc::new(Pool {
                agent,
                queue: Mutex::new(Queue::default()),
                ready: Condvar::new(),
            }),
        }
    }
}

impl HttpTransport for UreqTransport {
    fn send(&self, request: HttpRequest, done: HttpDone) {
        let mut queue = self.pool.lock();
        queue.jobs.push_back((request, done));
        if queue.jobs.len() > queue.idle && queue.workers < MAX_WORKERS {
            let pool = self.pool.clone();
            let spawned = thread::Builder::new()
                .name("gamend-http".to_string())
                .spawn(move || pool.work());
            if spawned.is_ok() {
                queue.workers += 1;
            } else if queue.workers == 0 {
                // No thread will ever take this job: say so instead of leaving
                // its ticket waiting.
                if let Some((_, done)) = queue.jobs.pop_back() {
                    drop(queue);
                    done(HttpResponse {
                        error: "could not start an HTTP worker".to_string(),
                        ..HttpResponse::default()
                    });
                    return;
                }
            }
        }
        drop(queue);
        self.pool.ready.notify_one();
    }
}

impl Drop for UreqTransport {
    fn drop(&mut self) {
        // Workers finish the call they are on and leave; nothing waits for them,
        // so dropping a client never blocks the game on a slow server.
        let mut queue = self.pool.lock();
        queue.closed = true;
        queue.jobs.clear();
        drop(queue);
        self.pool.ready.notify_all();
    }
}

fn prepared<B>(mut builder: RequestBuilder<B>, request: &HttpRequest) -> RequestBuilder<B> {
    for (name, value) in &request.headers {
        builder = builder.header(name, value);
    }
    builder
        .config()
        .timeout_global(Some(request.timeout))
        .build()
}

fn perform(
    agent: &Agent,
    request: &HttpRequest,
) -> Result<ureq::http::Response<Body>, ureq::Error> {
    let url = request.url.as_str();
    let body = request.body.as_slice();
    match request.method.as_str() {
        "GET" => prepared(agent.get(url), request).call(),
        "DELETE" if body.is_empty() => prepared(agent.delete(url), request).call(),
        // A body only when given one: deleting an account that has a password
        // sends its `current_password`.
        "DELETE" => prepared(agent.delete(url).force_send_body(), request).send(body),
        "POST" => prepared(agent.post(url), request).send(body),
        "PUT" => prepared(agent.put(url), request).send(body),
        "PATCH" => prepared(agent.patch(url), request).send(body),
        other => Err(ureq::Error::BadUri(format!("unsupported method {other}"))),
    }
}

fn run(agent: &Agent, request: &HttpRequest) -> HttpResponse {
    let answered = perform(agent, request).and_then(|mut response| {
        let status = response.status().as_u16();
        // Downloads can be any size; the default limit is meant for JSON.
        let body = response
            .body_mut()
            .with_config()
            .limit(u64::MAX)
            .read_to_vec()?;
        Ok((status, body))
    });
    match answered {
        Ok((status, body)) => HttpResponse {
            status,
            body,
            error: String::new(),
        },
        Err(error) => HttpResponse {
            error: error.to_string(),
            ..HttpResponse::default()
        },
    }
}
