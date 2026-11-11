//! The inbox, the timers and the state every part of the SDK shares.
//!
//! There is no thread in here. A transport posts from wherever it completes,
//! and everything else happens in `drain`, on the thread that calls
//! `Client::poll()`. That is what lets the core run where there are no threads
//! at all.
//!
//! All state sits behind one mutex, as `Core`. A task, a timer and a reply
//! continuation are each handed `&mut Core`, so none of them captures anything
//! that points back at the client: a transport thread holds only a `Poster`,
//! which does nothing once the client is gone. What the game supplied (the log
//! line, the page opener, a ticket's waker) runs after the mutex is released,
//! so it may call straight back into the client.

use std::collections::hash_map::RandomState;
use std::collections::VecDeque;
use std::hash::{BuildHasher, Hasher};
use std::mem;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError, Weak};
use std::time::Duration;

use crate::client::{Clock, Config, LogLevel};
use crate::ticket::{Completer, Ticket};
use crate::{auth, kv, presence, realtime, webrtc};

pub(crate) type Task = Box<dyn FnOnce(&mut Core) + Send>;
type Effect = Box<dyn FnOnce() + Send>;

/// Where a completion waits for the next `poll()`.
pub(crate) struct Inbox {
    tasks: Mutex<Vec<Task>>,
}

impl Inbox {
    fn new() -> Self {
        Self {
            tasks: Mutex::new(Vec::new()),
        }
    }

    fn lock(&self) -> MutexGuard<'_, Vec<Task>> {
        self.tasks.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// What a transport's thread holds instead of the client: posting through it
/// after the client is gone does nothing.
#[derive(Clone)]
pub(crate) struct Poster(Weak<Inbox>);

impl Poster {
    pub(crate) fn post(&self, task: impl FnOnce(&mut Core) + Send + 'static) {
        if let Some(inbox) = self.0.upgrade() {
            inbox.lock().push(Box::new(task));
        }
    }
}

/// What the game drains, kept until it does. A game that never reads a kind of
/// news must not grow without bound, so past the limit the oldest goes first.
pub(crate) struct Queue<T> {
    items: VecDeque<T>,
    limit: usize,
    dropped: usize,
}

impl<T> Queue<T> {
    pub(crate) fn new(limit: usize) -> Self {
        Self {
            items: VecDeque::new(),
            limit,
            dropped: 0,
        }
    }

    pub(crate) fn push(&mut self, item: T) {
        if self.items.len() >= self.limit {
            self.items.pop_front();
            self.dropped += 1;
        }
        self.items.push_back(item);
    }

    pub(crate) fn take(&mut self) -> (Vec<T>, usize) {
        let items = self.items.drain(..).collect();
        (items, mem::take(&mut self.dropped))
    }
}

struct Timer {
    due: u64,
    id: u64,
    task: Task,
}

pub(crate) struct Core {
    pub(crate) config: Config,
    pub(crate) base_url: String,
    pub(crate) run_id: String,
    clock: Clock,
    inbox: Arc<Inbox>,
    timers: Vec<Timer>,
    firing: VecDeque<Timer>,
    next_timer: u64,
    draining: bool,
    effects: Vec<Effect>,
    pub(crate) auth: auth::State,
    pub(crate) realtime: realtime::State,
    pub(crate) kv: kv::State,
    pub(crate) presence: presence::State,
    pub(crate) webrtc: webrtc::State,
}

impl Core {
    /// Run `task` in the next drain. Never inside the call that asked.
    pub(crate) fn post(&self, task: impl FnOnce(&mut Core) + Send + 'static) {
        self.inbox.lock().push(Box::new(task));
    }

    pub(crate) fn poster(&self) -> Poster {
        Poster(Arc::downgrade(&self.inbox))
    }

    /// Fill a ticket in: in this drain if one is under way, or in the next one,
    /// so a ticket completes inside `poll()` whatever happened to finish it.
    pub(crate) fn complete<T: Send + 'static>(&mut self, done: Completer<T>, value: T) {
        if self.draining {
            self.effects.push(Box::new(move || done.complete(value)));
        } else {
            self.post(move |core| core.complete(done, value));
        }
    }

    /// Run `task` in the first drain at least `delay` from now. Answers an id
    /// for `cancel`, never 0.
    pub(crate) fn after(
        &mut self,
        delay: Duration,
        task: impl FnOnce(&mut Core) + Send + 'static,
    ) -> u64 {
        let id = self.next_timer;
        self.next_timer += 1;
        self.timers.push(Timer {
            due: self.now() + delay.as_millis() as u64,
            id,
            task: Box::new(task),
        });
        id
    }

    pub(crate) fn cancel(&mut self, id: u64) {
        if id == 0 {
            return;
        }
        self.timers.retain(|timer| timer.id != id);
        // A timer due in this same drain, cancelled by one that ran before it.
        self.firing.retain(|timer| timer.id != id);
    }

    /// Monotonic milliseconds.
    pub(crate) fn now(&self) -> u64 {
        (self.clock)()
    }

    /// Unix seconds; 0 when the build has no wall clock to ask.
    pub(crate) fn unix_now(&self) -> i64 {
        self.config.unix_clock.as_ref().map_or(0, |clock| clock())
    }

    pub(crate) fn log(&mut self, level: LogLevel, line: impl Into<String>) {
        if let Some(log) = self.config.log.clone() {
            let line = line.into();
            self.effects.push(Box::new(move || log(level, &line)));
        }
    }

    pub(crate) fn open_url(&mut self, url: String) {
        if let Some(open) = self.config.open_url.clone() {
            self.effects.push(Box::new(move || open(&url)));
        }
    }

    /// Hand a queue over to the game, saying so when it overflowed.
    pub(crate) fn drained<T>(&mut self, queue: impl FnOnce(&mut Core) -> &mut Queue<T>) -> Vec<T> {
        let (items, dropped) = queue(self).take();
        if dropped > 0 {
            self.log(
                LogLevel::Warning,
                format!("gamend: {dropped} queued items were dropped before anyone drained them"),
            );
        }
        items
    }

    fn run_timers(&mut self) {
        let now = self.now();
        if !self.timers.iter().any(|timer| timer.due <= now) {
            return;
        }
        let (mut due, waiting): (Vec<Timer>, Vec<Timer>) = mem::take(&mut self.timers)
            .into_iter()
            .partition(|timer| timer.due <= now);
        self.timers = waiting;
        due.sort_by_key(|timer| (timer.due, timer.id));
        self.firing = due.into();
        while let Some(timer) = self.firing.pop_front() {
            (timer.task)(self);
        }
    }
}

fn mix(mut x: u64) -> u64 {
    // splitmix64: spreads the entropy of the clocks across every bit.
    x = x.wrapping_add(0x9e37_79b9_7f4a_7c15);
    x = (x ^ (x >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    x = (x ^ (x >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    x ^ (x >> 31)
}

// A run id: unique enough to tell two runs apart in the server's logs, which is
// all it is for. The hasher's keys are the standard library's own entropy where
// the platform has one; the counter parts two clients made in one tick.
fn make_run_id(monotonic: u64, unix: i64) -> String {
    static RUNS: AtomicU64 = AtomicU64::new(1);
    let random = RandomState::new().build_hasher().finish();
    let high = mix(random ^ mix(unix as u64));
    let low = mix(monotonic ^ mix(RUNS.fetch_add(1, Ordering::Relaxed)) ^ high);
    format!("{high:016x}{low:016x}")
}

/// The client's one mutex. Lock order is state, then inbox; a transport thread
/// takes only the inbox.
pub(crate) struct Shared {
    core: Mutex<Core>,
}

impl Shared {
    pub(crate) fn new(config: Config, clock: Clock) -> Arc<Self> {
        let unix = config.unix_clock.as_ref().map_or(0, |clock| clock());
        let run_id = if config.run_id.is_empty() {
            make_run_id(clock(), unix)
        } else {
            config.run_id.clone()
        };
        let limit = config.queue_limit;
        let core = Core {
            base_url: config.base_url.trim_end_matches('/').to_string(),
            run_id,
            config,
            clock,
            inbox: Arc::new(Inbox::new()),
            timers: Vec::new(),
            firing: VecDeque::new(),
            next_timer: 1,
            draining: false,
            effects: Vec::new(),
            auth: auth::State::new(limit),
            realtime: realtime::State::new(limit),
            kv: kv::State::new(limit),
            presence: presence::State::new(limit),
            webrtc: webrtc::State::new(limit),
        };
        Arc::new(Self {
            core: Mutex::new(core),
        })
    }

    fn lock(&self) -> MutexGuard<'_, Core> {
        self.core.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// Run `work` holding the state, then what it left for after the lock.
    pub(crate) fn with<R>(&self, work: impl FnOnce(&mut Core) -> R) -> R {
        let mut core = self.lock();
        let out = work(&mut core);
        let effects = mem::take(&mut core.effects);
        drop(core);
        for effect in effects {
            effect();
        }
        out
    }

    /// A ticket, and `work` given what completes it.
    pub(crate) fn start<T: Send + 'static>(
        &self,
        work: impl FnOnce(&mut Core, Completer<T>),
    ) -> Ticket<T> {
        let (ticket, done) = Ticket::pair();
        self.with(|core| work(core, done));
        ticket
    }

    /// Run what was posted, in order, then the timers that are due. A task
    /// posted while these run waits for the next drain.
    pub(crate) fn drain(&self) {
        self.with(|core| {
            // Taken under the state's lock: two threads polling at once must
            // still run the inbox in the order it filled.
            let ready = mem::take(&mut *core.inbox.lock());
            core.draining = true;
            for task in ready {
                task(core);
            }
            core.run_timers();
            core.draining = false;
        });
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::AtomicBool;

    use super::*;

    #[test]
    fn a_timer_cancelled_by_an_earlier_timer_in_the_same_drain_does_not_run() {
        let shared = Shared::new(Config::new("http://test"), Arc::new(|| 10));
        let ran = Arc::new(AtomicBool::new(false));
        let seen = ran.clone();
        shared.with(|core| {
            let second = core.next_timer + 1;
            core.after(Duration::ZERO, move |core| core.cancel(second));
            core.after(Duration::ZERO, move |_| seen.store(true, Ordering::SeqCst));
        });
        shared.drain();
        assert!(!ran.load(Ordering::SeqCst));
    }

    #[test]
    fn a_task_posted_while_the_inbox_runs_waits_for_the_next_drain() {
        let shared = Shared::new(Config::new("http://test"), Arc::new(|| 10));
        let ran = Arc::new(AtomicBool::new(false));
        let seen = ran.clone();
        shared.with(|core| {
            core.post(move |core| core.post(move |_| seen.store(true, Ordering::SeqCst)));
        });
        shared.drain();
        assert!(!ran.load(Ordering::SeqCst));
        shared.drain();
        assert!(ran.load(Ordering::SeqCst));
    }
}
