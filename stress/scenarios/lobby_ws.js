/**
 * A lobby state transition with a client listening on `lobby:<id>`.
 *
 * lobbies_http.js already prices the write. What it cannot see is the half of
 * the operation a player actually experiences: the fan-out from the writing
 * process, through PubSub, into every joined channel process. `t_lobby_event`
 * spans the POST *and* the delivery on purpose — what a player waits for is the
 * gap between the host pressing start and their own screen changing, and
 * neither half of that is meaningful alone.
 *
 * The event on the wire is `state_changed`. `lobby_state_changed` is the
 * internal PubSub message that produces it (lobby_channel.ex) and never reaches
 * a client; assuming the internal name is the wire name is exactly the mistake
 * this scenario exists to catch.
 */

import { check } from 'k6';
import { constantVus, summaryHandler, RUN_TAG, SLO } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import { createLobby, lobbyState, leaveLobby, data } from '../lib/api.js';
import { session, eventMetric } from '../lib/phx.js';
import { ok, okOr } from '../lib/checks.js';

const EVENT_TIMEOUT = Number.parseInt(__ENV.EVENT_TIMEOUT_MS || '5000', 10);

eventMetric('lobby_event');

export const options = constantVus({
  thresholds: { t_lobby_event: [`p(95)<${SLO.event_p95}`] },
});
export const handleSummary = summaryHandler('lobby_ws');

export default function () {
  const s = deviceLogin();
  if (!s) return;

  const created = createLobby(s.token, { title: `${RUN_TAG}-${__VU}-${__ITER}`, max_users: 8 });

  // The player is still in a lobby from an iteration that failed to leave:
  // 409 `already_in_lobby`, a leave and a retry next iteration, not a failure
  // of this scenario.
  if (!okOr(created, 'lobby create', [409])) return;
  if (created.status !== 201) {
    leaveLobby(s.token);
    return;
  }

  const lobby = data(created);
  if (!lobby || !lobby.id) return;
  const topic = `lobby:${lobby.id}`;

  session(
    s.token,
    (c, done) => {
      c.join(topic, {}, (joined) => {
        if (!joined) return done();

        c.once(
          topic,
          'state_changed',
          'lobby_event',
          (p) => {
            check(p, { 'state_changed carries the new state': (x) => !!x && x.to === 'playing' });
            done();
          },
          { timeout: EVENT_TIMEOUT },
        );

        ok(lobbyState(s.token, 'playing'), 'lobby state');
      });
    },
    // Close shortly after a no-show rather than holding the VU for the full
    // safety timeout: one lost event should cost one iteration, not thirty.
    { timeout: EVENT_TIMEOUT + 2000 },
  );

  ok(leaveLobby(s.token), 'lobby leave');
}
