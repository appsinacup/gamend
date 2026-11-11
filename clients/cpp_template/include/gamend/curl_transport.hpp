// The libcurl HTTP transport (CMake option `GAMEND_WITH_CURL`, on by
// default): one worker thread per transport drives a multi handle, so calls
// run side by side and none of them blocks the game thread.
#pragma once

#include <memory>

#include "gamend/export.hpp"
#include "gamend/transport.hpp"

namespace gamend {

GAMEND_EXPORT std::unique_ptr<HttpTransport> make_curl_transport();

}  // namespace gamend
