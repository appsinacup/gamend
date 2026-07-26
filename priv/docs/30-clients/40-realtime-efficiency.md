---
icon: hero-arrow-trending-down
---

# Realtime Update Efficiency

State events re-send the current state of an object the subscriber already has: a lobby's fields, a user's profile, a member row. Two things keep that cheap — dropping updates that changed nothing, and optionally coalescing bursts into one message. Every payload is complete JSON; there is no diff format a client has to understand.

## Deduplication (always on)

Before pushing an update, the channel compares it to the last one it sent for that object on that connection. If they are identical, nothing is sent. A write that touches a field no subscriber can see, or a presence refresh that changes nothing, produces no traffic.

## Debouncing (opt-in)

Set GAMEND_REALTIME_DEBOUNCE_MS to hold outbound updates for that many milliseconds and then push only the latest state per object. A burst of ten writes to one lobby becomes one message. It is 0 by default, which pushes immediately and only deduplicates.

| Env var | Default | Effect |
|---|---|---|
| GAMEND_REALTIME_DEBOUNCE_MS | 0 | Milliseconds to coalesce state updates. 0 pushes immediately. A small value (50-100) collapses rapid bursts at the cost of that much added latency on updates. |

This is the lever that actually reduces bandwidth on a compressed connection, because each message costs about 76 bytes of framing and headers before any payload (see below). Removing a message saves more than shrinking one. The trade is latency: an update may wait up to the debounce window before the client sees it, so leave it at 0 for twitch-sensitive state and raise it only for chatty, non-urgent updates.

Debouncing applies to the state events only — updated, member_updated, user_updated, lobby_updated, group_updated, friend_updated. One-shot events (member_joined, notification, chat, invites) are never delayed.

## Which events are deduplicated

| Topic | Event |
|---|---|
| user:{user_id} | updated, friend_updated |
| lobby:{lobby_id} | updated, user_updated |
| party:{party_id} | updated, member_updated |
| group:{group_id} | updated, member_updated |
| lobbies | lobby_updated |
| groups | group_updated |

These are exactly the events that re-send an object's full state. Every other event either announces a one-time fact (member_joined, quest_completed, notification) or creates/deletes an object, none of which have a previous version to compare against.

## What the transport costs

Every message carries WebSocket, TLS, TCP and IP headers, and the server sets TCP_NODELAY, so each message is written as its own packet. This is why coalescing beats shrinking payloads.

| Layer | WebSocket (WSS) | WebRTC DataChannel |
|---|---|---|
| Framing | 2-4 B (WS frame) | 28 B (SCTP) |
| Encryption record | 22 B (TLS 1.3) | 37 B (DTLS 1.2) |
| Transport | 32 B (TCP + timestamps) | 8 B (UDP) |
| Network | 20 B (IPv4) | 20 B (IPv4) |
| Per message, before payload | ~76 B | ~93 B |

Add 20 B per message on IPv6. WebRTC is not the cheaper transport — it costs ~17 B more per message — and it carries hook RPC, not these state events. On a compressed connection a small update is roughly 50 B of payload against 76 B of headers, so 60% of the packet is protocol and no payload trick can move the total much. Fewer messages is the only real lever, which is what the debounce provides.

## Protobuf (opt-in)

Protobuf shrinks the payload itself, so it stacks with the debounce. Sockets connected with ?format=protobuf receive mapped events as binary frames per proto/gamend_realtime.proto (see the WebSocket Channels and WebRTC pages); JSON remains the default. Measured on the same payloads (metadata stays embedded JSON in both formats):

| Scenario | raw: JSON / PB | PB saves | deflate: JSON / PB | PB saves | on the wire |
|---|---|---|---|---|---|
| User presence flips | 902 / 552 | 39% | 200 / 155 | 23% | 9% |
| Lobby lock/hide toggles | 1340 / 784 | 41% | 258 / 200 | 22% | 11% |
| Lobby + 8 members: field toggle | 3299 / 1836 | 44% | 370 / 271 | 27% | 17% |

Protobuf keeps a real edge after compression — 22-27% on the payload, 9-17% once per-message headers are counted. Events without a protobuf mapping fall back to JSON on the same socket, so coverage can grow event by event without breaking clients.

Ranking the levers (compressed connection)

Coalescing bursts (GAMEND_REALTIME_DEBOUNCE_MS) — the largest win, roughly 30% on a 4-message burst. Protobuf (?format=protobuf) — 9-17%. They compose: a debounced protobuf socket gets both.

Reproducing these numbers

Payloads were encoded with the realtime serializers and run through zlib configured the way Bandit configures it (raw deflate, window 15, sync flush per message); protobuf sizes use the field numbers of the original realtime schema; header sizes are the standard values per protocol layer. These are representative payload shapes, not production telemetry — your own payloads, especially metadata size, will move the numbers.
