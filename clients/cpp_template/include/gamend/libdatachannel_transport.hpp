// The libdatachannel WebRTC peer (CMake option `GAMEND_WITH_WEBRTC`, off by
// default: it brings OpenSSL, usrsctp and libjuice). libdatachannel runs the
// connection on its own threads.
#pragma once

#include <memory>

#include "gamend/export.hpp"
#include "gamend/transport.hpp"

namespace gamend {

GAMEND_EXPORT std::unique_ptr<PeerTransport> make_libdatachannel_transport();

}  // namespace gamend
