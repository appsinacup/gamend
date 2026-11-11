// The C++ SDK, as an Unreal source includes it: everything `gamend::`, with
// nlohmann/json, behind the engine's guard for third-party headers.
//
//     #include "GamendSDK.h"
//
//     UGamendSubsystem::Get(this)->GetClient().api().lobbies_list_lobbies(
//       {{"page_size", 10}}, [](const gamend::Response& r) { ... });
//
// The SDK's own documentation is its README and REFERENCE.md, which list
// every call: https://gamend.org/docs/cpp-sdk.
#pragma once

#include "CoreMinimal.h"

THIRD_PARTY_INCLUDES_START
#include "gamend/gamend.hpp"
THIRD_PARTY_INCLUDES_END

namespace GamendUnreal
{
	/** UTF-8, as the SDK speaks it. */
	GAMEND_API std::string ToStd(const FString& Text);
	/** From the SDK's UTF-8. */
	GAMEND_API FString ToFString(std::string_view Text);
	/** A JSON value as text: `gamend::dump`, as an FString. */
	GAMEND_API FString ToJsonString(const gamend::json& Value);

	/** The HTTP transport over FHttpModule, for a gamend::Config of your own. */
	GAMEND_API std::unique_ptr<gamend::HttpTransport> MakeHttpTransport();
	/** The WebSocket transport over FWebSocketsModule, for a gamend::Config of your own. */
	GAMEND_API std::unique_ptr<gamend::WebSocketTransport> MakeWebSocketTransport();
}
