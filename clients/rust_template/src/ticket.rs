//! What every call answers: a handle that fills in during `Client::poll()`.
//!
//! A callback that captures game state fights the borrow checker in every Rust
//! engine, so nothing here takes one. A system holds the `Ticket` and reads it
//! with `try_take` once a frame; `async` code awaits it.

use std::fmt;
use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::task::{Context, Poll, Waker};

struct Slot<T> {
    value: Option<T>,
    done: bool,
    wakers: Vec<Waker>,
}

/// The answer to a call, once it has one. Cheap to clone; every clone reads the
/// same answer, and the first to take it has it.
///
/// A ticket completes only inside `Client::poll()`, never inside the call that
/// started it, so whoever awaits one needs something polling the client. One
/// whose client is gone never completes. Dropping a ticket does not cancel the
/// call: a call the game does not need the answer to can be left at that.
pub struct Ticket<T> {
    slot: Arc<Mutex<Slot<T>>>,
}

/// What fills a ticket in. The SDK's half of the pair.
pub(crate) struct Completer<T> {
    slot: Arc<Mutex<Slot<T>>>,
}

fn lock<T>(slot: &Mutex<Slot<T>>) -> MutexGuard<'_, Slot<T>> {
    slot.lock().unwrap_or_else(PoisonError::into_inner)
}

impl<T> Ticket<T> {
    pub(crate) fn pair() -> (Ticket<T>, Completer<T>) {
        let slot = Arc::new(Mutex::new(Slot {
            value: None,
            done: false,
            wakers: Vec::new(),
        }));
        (Ticket { slot: slot.clone() }, Completer { slot })
    }

    /// The answer, if it has come and no clone has taken it yet.
    pub fn try_take(&self) -> Option<T> {
        lock(&self.slot).value.take()
    }

    /// Whether the call has completed. Stays true after the answer is taken.
    pub fn is_ready(&self) -> bool {
        lock(&self.slot).done
    }
}

impl<T> Completer<T> {
    pub(crate) fn complete(self, value: T) {
        // Wake outside the lock: a waker may poll this very ticket.
        let wakers = {
            let mut slot = lock(&self.slot);
            slot.value = Some(value);
            slot.done = true;
            std::mem::take(&mut slot.wakers)
        };
        for waker in wakers {
            waker.wake();
        }
    }
}

impl<T> Clone for Ticket<T> {
    fn clone(&self) -> Self {
        Self {
            slot: self.slot.clone(),
        }
    }
}

impl<T> fmt::Debug for Ticket<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Ticket")
            .field("ready", &self.is_ready())
            .finish()
    }
}

impl<T> Future for Ticket<T> {
    type Output = T;

    /// # Panics
    /// When a clone already took the answer: this one would wait forever.
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<T> {
        let mut slot = lock(&self.slot);
        if let Some(value) = slot.value.take() {
            return Poll::Ready(value);
        }
        assert!(!slot.done, "a clone of this Ticket already took its answer");
        if !slot.wakers.iter().any(|known| known.will_wake(cx.waker())) {
            slot.wakers.push(cx.waker().clone());
        }
        Poll::Pending
    }
}
