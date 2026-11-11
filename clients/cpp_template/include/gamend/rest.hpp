// The REST layer: one authenticated JSON caller for the whole API.
//
// `Api` is generated over it, one method per operation; call it directly
// for a path `Api` does not know yet. An authenticated call that answers 401
// while a refresh token is in hand refreshes the session once and is sent
// again, so an expired access token heals without the caller seeing it.
#pragma once

#include <memory>
#include <string>
#include <string_view>

#include "gamend/export.hpp"
#include "gamend/json.hpp"
#include "gamend/response.hpp"
#include "gamend/transport.hpp"

namespace gamend {

namespace detail {
struct Core;
}

/// What a call sends: nothing, a JSON value, or raw bytes.
struct Body {
  enum class Kind { None, Json, Bytes };
  Kind kind = Kind::None;
  json value;
  std::string bytes;
  std::string content_type;

  static Body none() { return {}; }
  static Body of(json value) {
    Body body;
    body.kind = Kind::Json;
    body.value = std::move(value);
    return body;
  }
  static Body raw(std::string bytes, std::string content_type = "application/octet-stream") {
    Body body;
    body.kind = Kind::Bytes;
    body.bytes = std::move(bytes);
    body.content_type = std::move(content_type);
    return body;
  }
};

class GAMEND_EXPORT Rest {
 public:
  explicit Rest(detail::Core& core);
  ~Rest();
  Rest(const Rest&) = delete;
  Rest& operator=(const Rest&) = delete;

  /// `method` on `path` (`/api/v1/...`, query included) with the session's
  /// bearer token when there is one.
  void send(std::string_view method, std::string path, Body body, Callback done);
  /// The same without the bearer token and without the refresh on 401:
  /// sign-in and refresh themselves go this way.
  void send_anonymous(std::string_view method, std::string path, Body body, Callback done);
  /// Complete `done`, on the next `poll()`, with the error a call gets when
  /// the SDK will not send it: `<call> needs `<field>``.
  void refuse(std::string_view call, std::string_view field, Callback done);

 private:
  struct Call;
  void start(std::shared_ptr<Call> call);
  void finish(const std::shared_ptr<Call>& call, HttpResponse reply);

  detail::Core& core_;
};

}  // namespace gamend
