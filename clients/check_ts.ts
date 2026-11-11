// Type-checked against the generated declarations; never run. A line that
// should not compile says so with @ts-expect-error, so a type that turns into
// `any` fails here too.
//
//   npm run check:types     (from clients/, after npm run generate)

import {
  AuthenticationApi,
  GameRealtime,
  GameWebRTC,
  GamendSession,
  LobbiesApi,
  PlayResult,
  ResultsApi,
  ReportsApi,
} from './javascript/dist/index';

async function check(): Promise<void> {
  const gamend = new GamendSession('https://game.example.com');
  await new AuthenticationApi(gamend.client).login({
    loginRequest: { email: 'a@example.com', password: 'secret' },
  });

  const lobbies = new LobbiesApi(gamend.client);
  const created = await lobbies.quickJoin({ quickJoinRequest: { title: 'duel', max_users: 2 } });
  const id: string = created.data.id;
  const detail = await lobbies.getLobbyWithHttpInfo(id);
  const title: string = detail.data.data.title;
  console.log(title);

  // @ts-expect-error a lobby id is required
  await lobbies.getLobby();
  // @ts-expect-error `id` is a string
  await lobbies.getLobby(12);

  const page = await new ResultsApi(gamend.client).listResults({ kind: 'match', pageSize: 5 });
  const first: PlayResult = page.data[0];
  const started: Date = first.started_at;
  const status: 'open' | 'ended' = first.status;
  console.log(started, status, PlayResult.StatusEnum.open);

  // @ts-expect-error `visibility` is one of the schema's values
  const wrong: PlayResult['visibility'] = 'everyone';
  console.log(wrong);

  await new ReportsApi(gamend.client).createReport({ reportRequest: { kind: 'bug' } });

  const realtime: GameRealtime = gamend.realtime({ format: 'protobuf' });
  const user = realtime.joinUserChannel(gamend.userId ?? '');
  user.on('notification_created', (payload) => console.log(payload));
  user.push('kv:subscribe', { key: 'progress' }).receive('ok', (reply) => console.log(reply));

  const time = await realtime.lobbyGetServerTime(id);
  const now: number = time.server_now;
  console.log(now);

  const webrtc = new GameWebRTC(user, { format: 'protobuf' });
  const sent: boolean = webrtc.send('events', 'hello');
  console.log(sent);

  const stop = gamend.on('session', (session) => console.log(session?.expires_at));
  stop();
  // @ts-expect-error not an event a session has
  gamend.on('nope', () => {});
}

void check;
