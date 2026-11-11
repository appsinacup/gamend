#include "GamendSubsystem.h"

#include "Engine/Engine.h"
#include "Engine/GameInstance.h"
#include "GamendLog.h"
#include "GamendSDK.h"
#include "GamendSaveGame.h"
#include "GamendSettings.h"
#include "HAL/PlatformProcess.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/Guid.h"

namespace
{
	EGamendRealtimeState ToBlueprint(gamend::RealtimeState State)
	{
		switch (State)
		{
		case gamend::RealtimeState::Connecting:
			return EGamendRealtimeState::Connecting;
		case gamend::RealtimeState::Connected:
			return EGamendRealtimeState::Connected;
		case gamend::RealtimeState::Reconnecting:
			return EGamendRealtimeState::Reconnecting;
		case gamend::RealtimeState::Disconnected:
		default:
			return EGamendRealtimeState::Disconnected;
		}
	}

	void WriteLog(gamend::LogLevel Level, const std::string& Line)
	{
		const FString Text = GamendUnreal::ToFString(Line);
		switch (Level)
		{
		case gamend::LogLevel::Debug:
			UE_LOG(LogGamend, Verbose, TEXT("%s"), *Text);
			break;
		case gamend::LogLevel::Info:
			UE_LOG(LogGamend, Log, TEXT("%s"), *Text);
			break;
		case gamend::LogLevel::Warning:
			UE_LOG(LogGamend, Warning, TEXT("%s"), *Text);
			break;
		case gamend::LogLevel::Error:
			UE_LOG(LogGamend, Error, TEXT("%s"), *Text);
			break;
		}
	}
}

UGamendSubsystem* UGamendSubsystem::Get(const UObject* WorldContextObject)
{
	const UGameInstance* GameInstance = UGameplayStatics::GetGameInstance(WorldContextObject);
	return GameInstance ? GameInstance->GetSubsystem<UGamendSubsystem>() : nullptr;
}

void UGamendSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);

	const UGamendSettings* Settings = GetDefault<UGamendSettings>();

	gamend::Config Config;
	Config.base_url = GamendUnreal::ToStd(Settings->BaseUrl);
	Config.http = GamendUnreal::MakeHttpTransport();
	Config.websocket = GamendUnreal::MakeWebSocketTransport();
	Config.http_timeout = std::chrono::milliseconds(FMath::Max(1, FMath::RoundToInt(Settings->HttpTimeoutSeconds * 1000.f)));
	Config.realtime_format = Settings->RealtimeFormat == EGamendRealtimeFormat::Protobuf
		? gamend::RealtimeFormat::Protobuf
		: gamend::RealtimeFormat::Json;
	// A provider's sign-in page ("Gamend Sign In"), in the system browser.
	Config.open_url = [](const std::string& Url)
	{
		FPlatformProcess::LaunchURL(*GamendUnreal::ToFString(Url), nullptr, nullptr);
	};
	Config.log = &WriteLog;
	Client = MakeShared<gamend::Client>(std::move(Config));

	// The client lives and dies with this subsystem, so its callbacks, which
	// run in poll() below, may hold `this`.
	Client->auth().on_session_changed([this](const std::optional<gamend::Session>& Session)
	{
		SessionChanged(Session ? &*Session : nullptr);
	});
	Client->realtime().on_event([this](const gamend::Event& Event)
	{
		FGamendEvent Out;
		Out.Topic = GamendUnreal::ToFString(Event.topic);
		Out.Name = GamendUnreal::ToFString(Event.event);
		Out.Kind = GamendUnreal::ToFString(Event.kind);
		Out.Payload = GamendUnreal::ToJsonString(Event.payload);
		OnEvent.Broadcast(Out);
	});
	Client->realtime().on_state([this](gamend::RealtimeState State)
	{
		OnRealtimeStateChanged.Broadcast(ToBlueprint(State));
	});

	// Each extra player of a multiplayer PIE session keeps its own slot, and
	// so its own device and session.
	SlotName = Settings->SaveSlot;
	const FWorldContext* Context = GetGameInstance()->GetWorldContext();
	if (!SlotName.IsEmpty() && Context && Context->WorldType == EWorldType::PIE && Context->PIEInstance > 0)
	{
		SlotName += FString::Printf(TEXT("_PIE%d"), Context->PIEInstance);
	}
	LoadSaveSlot();
	if (Settings->bKeepSession && !SavedSession.IsEmpty())
	{
		RestoreSession(SavedSession);
	}

	// The core ticker runs every frame, paused or not, in the editor's PIE
	// too: poll() is where replies, events and timers (token refresh,
	// heartbeats, reconnects) reach the game thread.
	TickHandle = FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateUObject(this, &UGamendSubsystem::TickClient));
}

void UGamendSubsystem::Deinitialize()
{
	FTSTicker::GetCoreTicker().RemoveTicker(TickHandle);
	TickHandle.Reset();
	// Closes the socket. Replies still in flight complete into nothing.
	Client.Reset();
	Super::Deinitialize();
}

bool UGamendSubsystem::TickClient(float DeltaTime)
{
	if (Client.IsValid())
	{
		Client->poll();
	}
	return true;
}

gamend::Client& UGamendSubsystem::GetClient() const
{
	check(Client.IsValid());
	return *Client;
}

bool UGamendSubsystem::IsSignedIn() const
{
	return Client.IsValid() && Client->auth().signed_in();
}

FString UGamendSubsystem::GetUserId() const
{
	if (!Client.IsValid()) return FString();
	const std::optional<gamend::Session> Session = Client->auth().session();
	return Session ? GamendUnreal::ToFString(Session->user_id) : FString();
}

FString UGamendSubsystem::GetUsername() const
{
	if (!Client.IsValid()) return FString();
	const std::optional<gamend::Session> Session = Client->auth().session();
	return Session ? GamendUnreal::ToFString(Session->username) : FString();
}

FString UGamendSubsystem::GetDisplayName() const
{
	if (!Client.IsValid()) return FString();
	const std::optional<gamend::Session> Session = Client->auth().session();
	return Session ? GamendUnreal::ToFString(Session->display_name) : FString();
}

FString UGamendSubsystem::GetDeviceId()
{
	if (DeviceId.IsEmpty())
	{
		DeviceId = FGuid::NewGuid().ToString(EGuidFormats::DigitsWithHyphens).ToLower();
		WriteSaveSlot();
	}
	return DeviceId;
}

void UGamendSubsystem::Logout()
{
	if (Client.IsValid())
	{
		Client->auth().logout();
	}
}

void UGamendSubsystem::ForgetSession()
{
	if (Client.IsValid())
	{
		Client->auth().forget();
	}
}

FString UGamendSubsystem::GetSessionJson() const
{
	if (!Client.IsValid()) return FString();
	const std::optional<gamend::Session> Session = Client->auth().session();
	return Session ? GamendUnreal::ToJsonString(Session->to_json()) : FString();
}

bool UGamendSubsystem::RestoreSession(const FString& SessionJson)
{
	if (!Client.IsValid()) return false;
	std::optional<gamend::Session> Session = gamend::Session::from_json(gamend::parse(GamendUnreal::ToStd(SessionJson)));
	if (!Session) return false;

	// restore() reports no change, so this does what SessionChanged would.
	Client->auth().restore(*Session);
	LastUserId = GamendUnreal::ToFString(Session->user_id);
	if (GetDefault<UGamendSettings>()->bConnectOnSignIn)
	{
		Connect();
	}
	OnSessionChanged.Broadcast(true);
	return true;
}

void UGamendSubsystem::SessionChanged(const gamend::Session* Session)
{
	const UGamendSettings* Settings = GetDefault<UGamendSettings>();
	if (Settings->bKeepSession)
	{
		SavedSession = Session ? GamendUnreal::ToJsonString(Session->to_json()) : FString();
		WriteSaveSlot();
	}
	if (Session && Settings->bConnectOnSignIn)
	{
		Connect();
	}

	// A refresh changes the tokens, not who is playing.
	const FString UserId = Session ? GamendUnreal::ToFString(Session->user_id) : FString();
	if (UserId != LastUserId)
	{
		LastUserId = UserId;
		OnSessionChanged.Broadcast(Session != nullptr);
	}
}

void UGamendSubsystem::Connect()
{
	if (Client.IsValid() && Client->realtime().state() == gamend::RealtimeState::Disconnected)
	{
		Client->realtime().connect();
	}
}

void UGamendSubsystem::Disconnect()
{
	if (Client.IsValid())
	{
		Client->realtime().disconnect();
	}
}

EGamendRealtimeState UGamendSubsystem::GetRealtimeState() const
{
	return Client.IsValid() ? ToBlueprint(Client->realtime().state()) : EGamendRealtimeState::Disconnected;
}

void UGamendSubsystem::JoinChannel(const FString& Topic)
{
	if (Client.IsValid())
	{
		Client->realtime().join(GamendUnreal::ToStd(Topic));
	}
}

void UGamendSubsystem::JoinLobbyChannel(const FString& LobbyId)
{
	if (Client.IsValid())
	{
		Client->realtime().join_lobby(GamendUnreal::ToStd(LobbyId));
	}
}

void UGamendSubsystem::LeaveChannel(const FString& Topic)
{
	if (Client.IsValid())
	{
		Client->realtime().leave(GamendUnreal::ToStd(Topic));
	}
}

bool UGamendSubsystem::IsChannelJoined(const FString& Topic) const
{
	return Client.IsValid() && Client->realtime().joined(GamendUnreal::ToStd(Topic));
}

void UGamendSubsystem::LoadSaveSlot()
{
	if (SlotName.IsEmpty() || !UGameplayStatics::DoesSaveGameExist(SlotName, 0)) return;
	if (const UGamendSaveGame* Saved = Cast<UGamendSaveGame>(UGameplayStatics::LoadGameFromSlot(SlotName, 0)))
	{
		DeviceId = Saved->DeviceId;
		SavedSession = Saved->Session;
	}
}

void UGamendSubsystem::WriteSaveSlot()
{
	if (SlotName.IsEmpty()) return;
	UGamendSaveGame* Saved = Cast<UGamendSaveGame>(UGameplayStatics::CreateSaveGameObject(UGamendSaveGame::StaticClass()));
	if (!Saved) return;
	Saved->DeviceId = DeviceId;
	Saved->Session = GetDefault<UGamendSettings>()->bKeepSession ? SavedSession : FString();
	if (!UGameplayStatics::SaveGameToSlot(Saved, SlotName, 0))
	{
		UE_LOG(LogGamend, Warning, TEXT("Could not write the save slot %s"), *SlotName);
	}
}
