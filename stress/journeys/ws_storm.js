/**
 * The connect storm: how fast sockets can be established, and what a mass
 * reconnect costs.
 *
 * `ws_idle.js` answers "how many sockets fit". This answers the question that
 * actually bounds a live game, because holding a connection and establishing
 * one are different costs and only the second one spikes. A deploy, a
 * fly-proxy restart and a mobile carrier handover all produce the same shape:
 * every client coming back inside a few seconds.
 *
 * Three phases, in one run:
 *
 *   connect    open SOCKETS as fast as the generator can, all at once
 *   hold       keep them for HOLD, heartbeating
 *   reconnect  drop every one of them simultaneously, then bring them all back
 *
 * The headline is **connects/s** and the p95 of connect+join, not the
 * plateau — plus whether the reconnect phase is slower than the first connect,
 * which is what says the server degrades under exactly the event it is most
 * likely to meet.
 *
 *   SOCKETS=5000 HOLD=60s k6 run journeys/ws_storm.js
 *
 * Per connection the server does a JWT verify, a per-user socket-limit count,
 * a Presence track, a `users` read, a friends query, a notifications query and
 * five PubSub subscribes. Each is per-key, not O(all connections on the node),
 * so this shape is linear in the connections.
 */

import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import { summaryHandler, RUN_TAG } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import { callHook } from '../lib/hooks.js';
import { session } from '../lib/phx.js';

const SOCKETS = Number.parseInt(__ENV.SOCKETS || '200', 10);
const HOLD = seconds(__ENV.HOLD || '60s');
const FRIENDS = Number.parseInt(__ENV.FRIENDS || '0', 10);
// Logging in is a database write per new account, and account creation
// serializes badly (see the spec's open finding). Doing it in the same instant
// as the connect would make this scenario a measurement of signup rather than
// of connects, so every VU logs in inside this window and only then queues up
// for a common start.
const LOGIN_WINDOW = seconds(__ENV.LOGIN_WINDOW || '60s');

const tConnect = new Trend('t_storm_connect', true);
const tReconnect = new Trend('t_storm_reconnect', true);
const connects = new Counter('storm_connects');
const reconnects = new Counter('storm_reconnects');

export const options = {
  scenarios: {
    storm: {
      // One iteration per VU, no pacing: the point is the thundering herd, so
      // nothing here should smooth the arrival of connections.
      executor: 'per-vu-iterations',
      vus: SOCKETS,
      iterations: 1,
      maxDuration: `${HOLD * 2 + 180}s`,
      gracefulStop: '30s',
    },
  },
  thresholds: {
    checks: ['rate>0.99'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
};

export const handleSummary = summaryHandler('ws_storm');

export default function () {
  const startedAt = Date.now();

  // Spread the logins across the window rather than firing all of them at
  // once, so the accounts exist before the part that is being measured.
  sleep((LOGIN_WINDOW * ((__VU - 1) % SOCKETS)) / SOCKETS);

  const auth = deviceLogin({ fresh: true, id: `${RUN_TAG}-storm-${__VU}` });
  if (!auth || !auth.userId) return;

  // Friend count is a connect-cost variable, not decoration: the user channel
  // runs a friends query on every join, so a run with FRIENDS=200 prices the
  // connect of an established player rather than a brand-new account.
  if (FRIENDS > 0) callHook(auth.token, 'stress_seed_friends', [FRIENDS]);

  const topic = `user:${auth.userId}`;

  // The barrier: k6 has no cross-VU synchronisation, but every VU started the
  // iteration at roughly the same moment, so waiting out the remainder of the
  // login window converges them on one instant — which is the whole point of a
  // storm. A VU whose login overran the window simply joins late.
  const remaining = LOGIN_WINDOW * 1000 - (Date.now() - startedAt);
  if (remaining > 0) sleep(remaining / 1000);

  // First connect: every VU arrives here together.
  hold(auth.token, topic, HOLD, tConnect, connects, 'storm connect');

  // …and every VU's socket closed at once, which is the reconnect trigger. No
  // pause: recovery from a simultaneous drop is the thing being measured.
  hold(auth.token, topic, 5, tReconnect, reconnects, 'storm reconnect');
}

function hold(token, topic, dwellSeconds, trend, counter, label) {
  const started = Date.now();

  session(
    token,
    (client, done) => {
      client.join(topic, {}, (joined) => {
        // Timed at the join, not at the socket open: a connection that has not
        // joined its user topic has none of the per-channel state a real client
        // depends on, so counting it as established would flatter the number.
        if (!check(joined, { [label]: (j) => j })) return done();

        trend.add(Date.now() - started);
        counter.add(1);

        client.socket.setTimeout(done, Math.max(1, dwellSeconds * 1000));
      });
    },
    { timeout: (dwellSeconds + 60) * 1000 },
  );
}

function seconds(d) {
  const m = String(d).match(/^(\d+)(s|m|h)?$/);
  if (!m) return 60;
  const n = Number.parseInt(m[1], 10);
  return m[2] === 'm' ? n * 60 : m[2] === 'h' ? n * 3600 : n;
}
