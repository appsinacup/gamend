// The Gamend C++ SDK: everything a game includes.
//
// `Client` owns the configuration and the transports and runs callbacks in
// `poll()`; `Auth` signs in and keeps the session fresh; `Api` is every REST
// operation, generated from the OpenAPI document; `events` names the
// realtime signals and `commands` every event a channel answers. See README.md.
#pragma once

#include "gamend/api.hpp"
#include "gamend/auth.hpp"
#include "gamend/client.hpp"
#include "gamend/commands.hpp"
#include "gamend/events.hpp"
#include "gamend/json.hpp"
#include "gamend/kv.hpp"
#include "gamend/models.hpp"
#include "gamend/presence.hpp"
#include "gamend/realtime.hpp"
#include "gamend/response.hpp"
#include "gamend/rest.hpp"
#include "gamend/session.hpp"
#include "gamend/transport.hpp"
#include "gamend/version.hpp"
#include "gamend/webrtc.hpp"

#if defined(GAMEND_WITH_CURL)
#include "gamend/curl_transport.hpp"
#endif
#if defined(GAMEND_WITH_IXWEBSOCKET)
#include "gamend/ix_websocket_transport.hpp"
#endif
#if defined(GAMEND_WITH_WEBRTC)
#include "gamend/libdatachannel_transport.hpp"
#endif
