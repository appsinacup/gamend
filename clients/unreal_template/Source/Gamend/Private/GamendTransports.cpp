// The SDK's HTTP and WebSocket transports over Unreal's own modules, in place
// of the curl and IXWebSocket ones the CMake build ships. Both may complete on
// any thread: the client hands every completion to the game thread through
// its inbox, and runs it in poll().
#include "GamendSDK.h"

#include "Containers/StringConv.h"
#include "HttpModule.h"
#include "IWebSocket.h"
#include "Interfaces/IHttpRequest.h"
#include "Interfaces/IHttpResponse.h"
#include "WebSocketsModule.h"

#include <atomic>

namespace GamendUnreal
{
	std::string ToStd(const FString& Text)
	{
		const auto Utf8 = StringCast<UTF8CHAR>(*Text, Text.Len());
		return std::string(reinterpret_cast<const char*>(Utf8.Get()), Utf8.Length());
	}

	FString ToFString(std::string_view Text)
	{
		const auto Wide = StringCast<TCHAR>(reinterpret_cast<const UTF8CHAR*>(Text.data()), static_cast<int32>(Text.size()));
		FString Out;
		Out.AppendChars(Wide.Get(), Wide.Length());
		return Out;
	}

	FString ToJsonString(const gamend::json& Value)
	{
		return ToFString(gamend::dump(Value));
	}
}

namespace
{
	class FGamendHttpTransport final : public gamend::HttpTransport
	{
	public:
		virtual void send(gamend::HttpRequest Request, std::function<void(gamend::HttpResponse)> Done) override
		{
			const TSharedRef<IHttpRequest, ESPMode::ThreadSafe> Http = FHttpModule::Get().CreateRequest();
			Http->SetVerb(GamendUnreal::ToFString(Request.method));
			Http->SetURL(GamendUnreal::ToFString(Request.url));
			for (const auto& Header : Request.headers)
			{
				Http->SetHeader(GamendUnreal::ToFString(Header.first), GamendUnreal::ToFString(Header.second));
			}
			if (!Request.body.empty())
			{
				TArray<uint8> Body;
				Body.Append(reinterpret_cast<const uint8*>(Request.body.data()), static_cast<int32>(Request.body.size()));
				Http->SetContent(MoveTemp(Body));
			}
			Http->SetTimeout(static_cast<float>(Request.timeout.count()) / 1000.f);

			// `Done` runs once. A request that cannot start may or may not
			// report it through the delegate as well, depending on the engine.
			const TSharedRef<std::atomic<bool>, ESPMode::ThreadSafe> Finished = MakeShared<std::atomic<bool>, ESPMode::ThreadSafe>(false);
			Http->OnProcessRequestComplete().BindLambda(
				[Done, Finished](FHttpRequestPtr Sent, FHttpResponsePtr Response, bool bConnectedSuccessfully)
				{
					if (Finished->exchange(true)) return;
					gamend::HttpResponse Reply;
					if (bConnectedSuccessfully && Response.IsValid())
					{
						// A 4xx or 5xx is a reply like any other.
						Reply.status = Response->GetResponseCode();
						const TArray<uint8>& Content = Response->GetContent();
						Reply.body.assign(reinterpret_cast<const char*>(Content.GetData()), static_cast<size_t>(Content.Num()));
					}
					else
					{
						const TCHAR* Status = Sent.IsValid() ? EHttpRequestStatus::ToString(Sent->GetStatus()) : TEXT("Failed");
						Reply.error = "no reply (" + GamendUnreal::ToStd(FString(Status)) + ")";
					}
					Done(std::move(Reply));
				});
			if (!Http->ProcessRequest() && !Finished->exchange(true))
			{
				gamend::HttpResponse Reply;
				Reply.error = "could not start the request";
				Done(std::move(Reply));
			}
		}
	};

	/** The handlers of one connection. Closing it silences them: the socket may still report after Close(). */
	struct FSocketHandlers
	{
		gamend::WebSocketHandlers Handlers;
		std::atomic<bool> bLive{true};
		/** A binary message arrives in fragments. */
		std::string Partial;
	};

	class FGamendWebSocketTransport final : public gamend::WebSocketTransport
	{
	public:
		virtual ~FGamendWebSocketTransport() override
		{
			Drop();
		}

		virtual void open(const std::string& Url, gamend::WebSocketHandlers Handlers) override
		{
			Drop();
			const TSharedRef<FSocketHandlers, ESPMode::ThreadSafe> Live = MakeShared<FSocketHandlers, ESPMode::ThreadSafe>();
			Live->Handlers = std::move(Handlers);
			Current = Live;

			// No subprotocol: Phoenix asks for none.
			Socket = FWebSocketsModule::Get().CreateWebSocket(GamendUnreal::ToFString(Url), FString());
			Socket->OnConnected().AddLambda([Live]()
			{
				if (Live->bLive && Live->Handlers.on_open) Live->Handlers.on_open();
			});
			Socket->OnConnectionError().AddLambda([Live](const FString& Error)
			{
				if (Live->bLive && Live->Handlers.on_error) Live->Handlers.on_error(GamendUnreal::ToStd(Error));
			});
			Socket->OnClosed().AddLambda([Live](int32 StatusCode, const FString& Reason, bool bWasClean)
			{
				if (Live->bLive && Live->Handlers.on_close) Live->Handlers.on_close(StatusCode, GamendUnreal::ToStd(Reason));
			});
			Socket->OnMessage().AddLambda([Live](const FString& Message)
			{
				if (Live->bLive && Live->Handlers.on_text) Live->Handlers.on_text(GamendUnreal::ToStd(Message));
			});
			Socket->OnBinaryMessage().AddLambda([Live](const void* Data, SIZE_T Size, bool bIsLastFragment)
			{
				if (!Live->bLive) return;
				Live->Partial.append(static_cast<const char*>(Data), Size);
				if (!bIsLastFragment) return;
				std::string Frame;
				Frame.swap(Live->Partial);
				if (Live->Handlers.on_binary) Live->Handlers.on_binary(std::move(Frame));
			});
			Socket->Connect();
		}

		virtual void send_text(std::string Frame) override
		{
			// As UTF-8 bytes in a text frame, without a round trip through FString.
			if (Socket.IsValid() && Socket->IsConnected())
			{
				Socket->Send(Frame.data(), Frame.size(), false);
			}
		}

		virtual void close() override
		{
			Drop();
		}

	private:
		void Drop()
		{
			if (Current.IsValid())
			{
				Current->bLive = false;
				Current.Reset();
			}
			if (Socket.IsValid())
			{
				Socket->Close();
				Socket.Reset();
			}
		}

		TSharedPtr<IWebSocket> Socket;
		TSharedPtr<FSocketHandlers, ESPMode::ThreadSafe> Current;
	};
}

namespace GamendUnreal
{
	std::unique_ptr<gamend::HttpTransport> MakeHttpTransport()
	{
		return std::make_unique<FGamendHttpTransport>();
	}

	std::unique_ptr<gamend::WebSocketTransport> MakeWebSocketTransport()
	{
		return std::make_unique<FGamendWebSocketTransport>();
	}
}
