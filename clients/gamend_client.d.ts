// The hand-written half of the package's types: what realtime.js, session.js
// and webrtc.js export, and the generated ApiClient. `clients/sdkgen ts` puts
// this at the top of dist/index.d.ts. `clients/sdkgen lint` fails when one of
// those files gains a public method that is not declared here.

/** A reply being waited for. Chain `receive` for each status. */
export interface PhoenixPush {
  receive(status: 'ok' | 'error' | 'timeout', callback: (response: any) => void): PhoenixPush;
}

/** A joined Phoenix channel. `E` names the events its topic sends. */
export interface PhoenixChannel<E extends string = string> {
  readonly topic: string;
  readonly state: string;
  on(event: E | (string & {}), callback: (payload: any) => void): number;
  off(event: string, ref?: number): void;
  push(event: string, payload?: object, timeout?: number): PhoenixPush;
  leave(timeout?: number): PhoenixPush;
}

/** Phoenix.Socket options, and `format: 'protobuf'` for binary event frames. */
export interface SocketOptions {
  format?: 'json' | 'protobuf';
  [phoenixOption: string]: unknown;
}

/** A protobufjs class, or a function that reads the bytes. */
export type ProtoSchema = object | ((bytes: Uint8Array) => unknown);

/** Whose key-value row a key names: the caller's own when left out. */
export interface KvScope {
  user_id?: string;
  lobby_id?: string;
}

export class GameRealtime {
  constructor(
    serverUrl: string,
    getToken: () => string | null | Promise<string | null>,
    socketOpts?: SocketOptions,
  );
  /** The underlying Phoenix.Socket. */
  readonly socket: any;
  registerMetaSchema(entity: 'user' | 'lobby' | 'group' | 'party', schema: ProtoSchema): void;
  registerKvSchema(pattern: string, schema: ProtoSchema): void;
  joinUserChannel(userId: string, params?: object): PhoenixChannel<UserChannelEvent>;
  joinLobbyChannel(lobbyId: string, params?: object): PhoenixChannel<LobbyChannelEvent>;
  joinLobbiesChannel(params?: object): PhoenixChannel<LobbiesChannelEvent>;
  joinGroupChannel(groupId: string, params?: object): PhoenixChannel<GroupChannelEvent>;
  joinGroupsChannel(params?: object): PhoenixChannel<GroupsChannelEvent>;
  joinPartyChannel(partyId: string, params?: object): PhoenixChannel<PartyChannelEvent>;
  joinSignalingChannel(lobbyId: string, params?: object): PhoenixChannel<SignalingChannelEvent>;
  joinChannel(topic: string, params?: object): PhoenixChannel;
  leaveChannel(topic: string): void;
  channel(topic: string): PhoenixChannel | undefined;
  push(event: string, payload?: object, topic?: string): PhoenixPush;
  callHook(plugin: string, fn: string, args?: unknown[]): Promise<any>;
  kvSubscribe(key: string, scope?: KvScope): Promise<any>;
  kvUnsubscribe(key: string, scope?: KvScope): Promise<any>;
  resultsList(params?: {
    kind?: string;
    status?: string;
    page?: number;
    page_size?: number;
  }): Promise<any>;
  resultsGet(id: string): Promise<any>;
  resultsEvents(id: string, params?: { after?: string; limit?: number }): Promise<any>;
  lobbyGetServerTime(lobbyId: string): Promise<{ server_now: number }>;
  signalingOffer(lobbyId: string, target: string, sdp: string): Promise<any>;
  signalingAnswer(lobbyId: string, target: string, sdp: string): Promise<any>;
  signalingIce(lobbyId: string, target: string, candidate: object): Promise<any>;
  signalingBroadcastOffer(lobbyId: string, sdp: string): Promise<any>;
  signalingListUsers(lobbyId: string): Promise<any>;
  disconnect(): void;
}

/** What `GamendSession.session` answers and `restore` takes. */
export interface SavedSession {
  access_token: string | null;
  refresh_token: string;
  /** Unix milliseconds. */
  expires_at: number;
  user_id: string | null;
}

export class GamendSession {
  constructor(serverUrl: string);
  /** Hand this to every generated API class: `new LobbiesApi(gamend.client)`. */
  readonly client: ApiClient;
  readonly signedIn: boolean;
  readonly userId: string | null;
  readonly session: SavedSession | null;
  restore(saved: SavedSession | null): void;
  on(event: 'session', listener: (session: SavedSession | null) => void): () => void;
  on(event: 'authFailed', listener: () => void): () => void;
  getAccessToken(): Promise<string | null>;
  refresh(): Promise<boolean>;
  realtime(socketOpts?: SocketOptions): GameRealtime;
  signOut(): Promise<void>;
}

export interface DataChannelDefinition {
  label: string;
  ordered?: boolean;
  maxRetransmits?: number;
  maxPacketLifeTime?: number;
}

export interface GameWebRTCOptions {
  dataChannels?: DataChannelDefinition[];
  iceServers?: object[];
  format?: 'json' | 'protobuf';
  onData?: (label: string, data: ArrayBuffer | string) => void;
  onChannelOpen?: (label: string) => void;
  onChannelClose?: (label: string) => void;
  onStateChange?: (state: string) => void;
  onError?: (error: Error) => void;
}

export class GameWebRTC {
  constructor(channel: PhoenixChannel, opts?: GameWebRTCOptions);
  connectionState: string;
  connect(): Promise<void>;
  send(label: string, data: string | ArrayBuffer | Blob): boolean;
  callHook(plugin: string, fn: string, args?: unknown[], timeoutMs?: number): Promise<any>;
  callHookRaw(plugin: string, fn: string, bytes: Uint8Array, timeoutMs?: number): Promise<Uint8Array>;
  isChannelOpen(label: string): boolean;
  isConnected(): boolean;
  close(): void;
}

export class ApiClient {
  constructor(basePath?: string);
  static instance: ApiClient;
  basePath: string;
  authentications: { authorization: { type: string; accessToken: string | null } };
  defaultHeaders: Record<string, string>;
  timeout: number;
  cache: boolean;
  enableCookies: boolean;
  callApi(...args: any[]): Promise<{ data: any; response: any }>;
}

export { GameRealtime as default_GameRealtime };
export { GameWebRTC as default_GameWebRTC };
export { GamendSession as default_GamendSession };
