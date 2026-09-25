defmodule GamendWeb.Realtime do
  @moduledoc """
  Tuning for outbound realtime state updates.
  """

  use Gamend.Settings.Provider,
    app: :gamend_web,
    group: :realtime,
    label: "Realtime"

  # Each message costs ~76 bytes of WebSocket/TLS/TCP/IP headers before any
  # payload, so coalescing a burst saves more than shrinking payloads does.
  setting(:debounce_ms, :integer,
    default: 0,
    doc:
      "Hold outbound state updates this long and push only the latest per object. 0 pushes immediately."
  )

  # Both pools shard by topic. The defaults keep a single-node deployment
  # exactly as it was; raising them spreads PubSub dispatch and presence
  # replication across schedulers, which is what a five-figure socket count
  # needs. `presence_pool_size` must be identical on every node in a cluster
  # (Phoenix.Tracker syncs shard-to-shard), so change it with a full restart,
  # never a rolling one.
  setting(:pubsub_pool_size, :integer,
    default: 1,
    doc: "Phoenix.PubSub shards. Raise on nodes holding many thousands of sockets."
  )

  setting(:presence_pool_size, :integer,
    default: 1,
    doc:
      "Phoenix.Presence tracker shards. Must match on every node in a cluster; needs a full restart to change."
  )

  # The dominant per-connection memory cost, and it belongs to the operating
  # system rather than to anything this app chose. Left alone, the kernel sizes
  # a connection's receive buffer for bulk transfer — measured at ~400 KB on
  # macOS — and the Erlang inet driver sizes its own read buffer to match, which
  # showed up as ~105 KB of binary memory per idle socket: two thirds of what a
  # connected player costs.
  #
  # Off by default, for two reasons.
  #
  # It is unverified. Setting it caps `buffer`, the driver's userspace buffer,
  # on the listening socket — but an accepted socket's buffer is recomputed from
  # whatever `recbuf` the kernel negotiated, so on macOS the value is discarded
  # and connections still report ~400 KB. Linux does not auto-tune the same way
  # and is expected to honour it; nobody has watched that happen yet.
  #
  # And the neighbouring knobs are a trap. Capping `recbuf`/`sndbuf` instead
  # *would* bound the memory, by shrinking the TCP window — which caps a
  # connection's throughput at window/RTT. At 32 KB over a 100 ms link that is
  # ~2.6 Mbit/s: ample for game messages, and ruinous for the same listener
  # serving a multi-megabyte Godot web export. This setting deliberately does
  # not touch them.
  #
  # So: leave it alone unless a node is holding tens of thousands of sockets and
  # memory is the binding constraint, and measure per-socket memory before and
  # after rather than assuming it worked.
  # The default timeout exists for background tabs: the game client runs on
  # requestAnimationFrame, which browsers stop for a hidden tab, so heartbeats
  # pause and Phoenix's own 60s would drop every alt-tabbed player. Hard
  # disconnects still end at once; this only defers reaping half-open sockets.
  setting(:socket_timeout_ms, :integer,
    default: 300_000,
    doc:
      "How long a game socket may stay silent before it is closed, in ms. Longer keeps " <>
        "alt-tabbed players; shorter frees half-open sockets (and their seats) sooner."
  )

  setting(:socket_max_frame_bytes, :integer,
    default: 131_072,
    doc: "Largest single WebSocket frame a game client may send, in bytes."
  )

  setting(:socket_buffer_kb, :integer,
    default: 0,
    doc:
      "Cap the per-connection socket read buffer, in KB. 0 leaves the OS default. " <>
        "Only lowers memory on platforms that honour it; does not change the TCP window."
  )
end
