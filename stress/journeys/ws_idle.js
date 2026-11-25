/**
 * How many idle players fit in RAM.
 *
 * A connected player who is doing nothing still costs: a transport process, a
 * `user:*` channel process, a Presence entry and a ConnectionTracker
 * registration. That per-socket cost, multiplied by the player count, is the
 * ceiling nothing else in the suite measures — every other scenario opens and
 * closes sockets too quickly for the cost to accumulate.
 *
 * So this opens `SOCKETS` sockets, joins the user topic on each, and holds
 * them for `DWELL` doing nothing but heartbeating.
 *
 *   SOCKETS=5000 DWELL=5m k6 run journeys/ws_idle.js
 *
 * `USERS` is how many device accounts those sockets are spread across, and it
 * exists because the obvious version of this test measures the wrong thing.
 * One account per socket is realistic, but it makes every socket cost a
 * *registration* first — and registration is a write, so the ramp saturates on
 * account creation long before it saturates on sockets. Measured on one core:
 * ~589 registrations/s against a socket cost of ~57 KB, so filling 3 GB of RAM
 * would take ten minutes of signups and never reach the memory ceiling at all.
 * Four load generators produced *fewer* sockets than one, because they were
 * competing for the same write path.
 *
 * With `USERS` well below `SOCKETS` the accounts are created once and shared,
 * and the ramp measures what it is named after. The server must have
 * `GAMEND_LIMITS_MAX_SOCKETS_PER_USER=0` (or a value above `SOCKETS / USERS`),
 * since the default of 20 is a real limit that will otherwise reject the
 * surplus — correctly, and confusingly if you have forgotten it is there.
 *
 *   SOCKETS=20000 USERS=100 DWELL=3m k6 run journeys/ws_idle.js
 *
 * The number to read is not in this summary: it is the server's RSS on the
 * metrics dashboard, divided by SOCKETS. Watch it while this runs. What k6
 * reports here is only whether the connections were accepted and stayed up —
 * a failed join or a dropped socket is the other thing worth knowing.
 */

import { sleep } from 'k6';
import { summaryHandler, RUN_TAG } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import { me, data } from '../lib/api.js';
import { callHook } from '../lib/hooks.js';
import { session } from '../lib/phx.js';

const SOCKETS = Number.parseInt(__ENV.SOCKETS || '200', 10);
// Friends are a memory variable, not decoration: `UserChannel`'s join memoises
// the caller's friend list on the socket's heap and keeps it for the socket's
// whole life, so per-socket memory scales with it. Run the same SOCKETS at
// FRIENDS=0 and FRIENDS=200 and the difference is that memo.
const FRIENDS = Number.parseInt(__ENV.FRIENDS || '0', 10);
// Accounts to spread the sockets over. Defaults to one each, which keeps the
// old behaviour for small runs; set it low for a memory-ceiling run.
const USERS = Math.max(1, Number.parseInt(__ENV.USERS || String(SOCKETS), 10));
const DWELL = __ENV.DWELL || '60s';
const RAMP = __ENV.RAMP || '30s';

export const options = {
  scenarios: {
    hold: {
      // `per-vu-iterations` with one iteration: each VU opens exactly one
      // socket and holds it, so VUs and open sockets are the same number.
      // Anything rate-based would churn connections instead of accumulating
      // them, which measures the opposite of what this is for.
      executor: 'per-vu-iterations',
      vus: SOCKETS,
      iterations: 1,
      maxDuration: `${parseSeconds(RAMP) + parseSeconds(DWELL) + 60}s`,
      gracefulStop: '30s',
    },
  },
  thresholds: {
    checks: ['rate>0.99'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
};

export const handleSummary = summaryHandler('ws_idle');

/**
 * Create the shared accounts once, before any VU starts.
 *
 * Without this, every VU assigned to an account races every other VU on that
 * account to *create* it: `/login/device` is find-or-create, so fifty
 * simultaneous first-logins for one device id all miss the lookup, all insert,
 * and all but one lose to the unique constraint. Measured at 500 sockets over
 * 10 accounts: 98% of logins failed. The sockets themselves were fine — the
 * joins that got through took 3.5ms — which is exactly the kind of failure
 * that reads as "the server cannot take it".
 *
 * Serial on purpose. It is `USERS` requests, not `SOCKETS`, so it costs a
 * second or two and it happens before the clock that matters starts.
 */
export function setup() {
  const ids = [];

  for (let i = 0; i < USERS; i++) {
    const id = `${RUN_TAG}-idle-${i}`;
    if (deviceLogin({ fresh: true, id })) ids.push(id);
  }

  return { ids };
}

export default function (state) {
  // Spread the CONNECTS across the ramp, not just the joins.
  //
  // Delaying only the channel join, with `setTimeout` inside the socket
  // callback, is too late: the socket is already open, and
  // `per-vu-iterations` starts all VUs immediately, so 24,000 sockets arrive
  // in about 21 seconds against a configured 130-second ramp, and what gets
  // measured is a connect storm rather than a steady population. That
  // distinction matters: an OOM above ~15,000 on both 3 GB and 4 GB is the
  // signature of an arrival-rate problem rather than a capacity one.
  //
  // `sleep` blocks the VU before anything is opened, which is the only way to
  // pace admission with this executor.
  const stagger = (parseSeconds(RAMP) * ((__VU - 1) % SOCKETS)) / SOCKETS;
  if (stagger > 0) sleep(stagger);

  // Sockets share accounts round-robin. Two VUs on the same account log in
  // separately and hold separate sockets, which is what a player with a phone
  // and a desktop open does — and what makes the socket count independent of
  // how fast the server can create accounts.
  //
  // `setup()` has already created these, so this login finds an existing user
  // rather than racing to insert one. The server needs
  // `GAMEND_LIMITS_MAX_SOCKETS_PER_USER=0` for the surplus to be accepted.
  const ids = (state && state.ids) || [];
  const id = ids.length ? ids[(__VU - 1) % ids.length] : `${RUN_TAG}-idle-${(__VU - 1) % USERS}`;

  const auth = deviceLogin({ fresh: true, id });
  if (!auth) return;

  const userId = auth.userId || idFromMe(auth.token);
  if (!userId) return;

  if (FRIENDS > 0) callHook(auth.token, 'stress_seed_friends', [FRIENDS]);

  session(
    auth.token,
    (client, done) => {
      client.join(`user:${userId}`, {}, () => {
        client.socket.setTimeout(done, parseSeconds(DWELL) * 1000);
      });
    },
    { timeout: (parseSeconds(RAMP) + parseSeconds(DWELL) + 30) * 1000 },
  );
}

function idFromMe(token) {
  const user = data(me(token));
  return user && user.id;
}

function parseSeconds(d) {
  const m = String(d).match(/^(\d+)(s|m|h)?$/);
  if (!m) return 60;
  const n = Number.parseInt(m[1], 10);
  return m[2] === 'm' ? n * 60 : m[2] === 'h' ? n * 3600 : n;
}
