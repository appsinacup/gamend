/**
 * The lobby write path: create → read back → transition state → leave.
 *
 * The heaviest ordinary player write in the product, and the one most likely
 * to be the first thing SQLite's single writer serializes. Each step is read
 * back rather than trusted, because a lobby that returns 201 and then cannot
 * be fetched — or whose state silently did not move — is a failure the latency
 * numbers would otherwise report as a success.
 *
 * State is deliberately moved through `POST /lobbies/state`: `state` is
 * server-owned and a `PATCH /lobbies` cannot touch it, so this is the only
 * path a real game uses to start a match.
 */

import { sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { constantVus, summaryHandler, RUN_TAG, THINK } from '../lib/config.js';
import { deviceLogin } from '../lib/auth.js';
import { createLobby, getLobby, lobbyState, leaveLobby, data } from '../lib/api.js';
import { ok, okOr, readsBack } from '../lib/checks.js';

const tCreate = new Trend('t_lobby_create', true);
const tState = new Trend('t_lobby_state', true);

export const options = constantVus();
export const handleSummary = summaryHandler('lobbies_http');

export default function () {
  const session = deviceLogin();
  if (!session) return;

  const title = `${RUN_TAG}-${__VU}-${__ITER}`;

  const created = createLobby(session.token, { title, max_users: 8 });
  tCreate.add(created.timings.duration);

  // Already-in-a-lobby is a real outcome, not an error: the player is still in
  // the lobby from a previous iteration that failed to leave, and counting it
  // as a failure would make a leave bug look like a create bug. It answers
  // 409 `already_in_lobby`.
  if (!okOr(created, 'lobby create', [409])) return;
  if (created.status !== 201) {
    leaveLobby(session.token);
    return;
  }

  const lobby = data(created);
  if (!lobby || !lobby.id) return;

  const fetched = getLobby(session.token, lobby.id);
  ok(fetched, 'lobby get');
  readsBack(fetched, (l) => l.title, title, 'lobby create');

  const moved = lobbyState(session.token, 'playing');
  tState.add(moved.timings.duration);
  ok(moved, 'lobby state');

  const after = getLobby(session.token, lobby.id);
  readsBack(after, (l) => l.state, 'playing', 'lobby state');

  ok(leaveLobby(session.token), 'lobby leave');

  sleep(THINK);
}
