// The IXWebSocket transport (CMake option `GAMEND_WITH_IXWEBSOCKET`, on by
// default). IXWebSocket runs the socket on its own thread; its automatic
// reconnect is off, since reconnecting (with a fresh token, and rejoining
// the topics) is the realtime layer's job.
#pragma once

#include <memory>

#include "gamend/export.hpp"
#include "gamend/transport.hpp"

namespace gamend {

GAMEND_EXPORT std::unique_ptr<WebSocketTransport> make_ix_websocket_transport();

}  // namespace gamend
