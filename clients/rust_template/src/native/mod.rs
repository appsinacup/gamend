//! What needs an operating system: the transports and the default clocks. The
//! core has no threads and no clock of its own, so this is the only part of the
//! crate that does not build for a target without them.

mod http;
mod websocket;

use std::sync::Arc;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

pub use http::UreqTransport;
pub use websocket::TungsteniteTransport;

use crate::client::{Clock, UnixClock};

/// Monotonic milliseconds since this was called.
pub fn monotonic_clock() -> Clock {
    let start = Instant::now();
    Arc::new(move || start.elapsed().as_millis() as u64)
}

/// The system clock, in Unix seconds.
pub fn unix_clock() -> UnixClock {
    Arc::new(|| {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |elapsed| elapsed.as_secs() as i64)
    })
}
