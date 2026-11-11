#include "GamendAsyncAction.h"

#include "GamendSDK.h"
#include "GamendSubsystem.h"

namespace
{
	FGamendResult Refused(const FString& Error)
	{
		FGamendResult Result;
		Result.Error = Error;
		Result.Data = TEXT("null");
		Result.Body = TEXT("null");
		return Result;
	}

	FGamendResult FromResponse(const gamend::Response& Response)
	{
		FGamendResult Result;
		Result.bOk = Response.ok();
		Result.Status = Response.status;
		Result.Error = GamendUnreal::ToFString(Response.error);
		Result.Message = GamendUnreal::ToFString(Response.message());
		Result.Data = GamendUnreal::ToJsonString(Response.data());
		Result.Body = GamendUnreal::ToJsonString(Response.body);
		return Result;
	}

	FGamendResult FromAuth(const gamend::AuthResult& Auth)
	{
		FGamendResult Result = FromResponse(Auth.response);
		Result.bOk = Auth.ok;
		Result.Error = GamendUnreal::ToFString(Auth.error);
		return Result;
	}

	FGamendResult FromHook(const gamend::HookResult& Hook)
	{
		FGamendResult Result;
		Result.bOk = Hook.ok;
		Result.Error = GamendUnreal::ToFString(Hook.error);
		Result.Data = GamendUnreal::ToJsonString(Hook.data);
		Result.Body = Result.Data;
		return Result;
	}

	FGamendResult FromReply(const gamend::Reply& Reply)
	{
		FGamendResult Result;
		Result.bOk = Reply.ok;
		Result.Error = GamendUnreal::ToFString(Reply.error);
		Result.Data = GamendUnreal::ToJsonString(Reply.response);
		Result.Body = Result.Data;
		return Result;
	}

	/** Text a Blueprint passed as JSON; `Empty` when it passed nothing. False when it is not JSON. */
	bool ParseJson(const FString& Text, const gamend::json& Empty, gamend::json& Out)
	{
		if (Text.TrimStartAndEnd().IsEmpty())
		{
			Out = Empty;
			return true;
		}
		Out = gamend::parse(GamendUnreal::ToStd(Text));
		return !Out.is_discarded();
	}

	/** The query of a paged list: only what the Blueprint set. */
	gamend::json PageOptions(int32 Page, int32 PageSize)
	{
		gamend::json Options = gamend::json::object();
		if (Page > 0) Options["page"] = Page;
		if (PageSize > 0) Options["page_size"] = PageSize;
		return Options;
	}
}

UGamendAsyncAction* UGamendAsyncAction::Make(UObject* WorldContextObject, FStart InStart)
{
	UGamendAsyncAction* Action = NewObject<UGamendAsyncAction>();
	Action->Subsystem = UGamendSubsystem::Get(WorldContextObject);
	Action->Start = MoveTemp(InStart);
	Action->RegisterWithGameInstance(WorldContextObject);
	return Action;
}

void UGamendAsyncAction::Activate()
{
	UGamendSubsystem* Gamend = Subsystem.Get();
	if (!Gamend || !Start)
	{
		Finish(Refused(TEXT("no_game_instance")));
		return;
	}
	// The node may be gone by the time the server answers; the SDK runs the
	// callback in the subsystem's tick, on the game thread.
	TWeakObjectPtr<UGamendAsyncAction> WeakThis(this);
	Start(*Gamend, [WeakThis](const FGamendResult& Result)
	{
		if (UGamendAsyncAction* Self = WeakThis.Get())
		{
			Self->Finish(Result);
		}
	});
}

void UGamendAsyncAction::Finish(const FGamendResult& Result)
{
	if (Result.bOk)
	{
		OnSuccess.Broadcast(Result);
	}
	else
	{
		OnFailure.Broadcast(Result);
	}
	SetReadyToDestroy();
}

// --- Session -----------------------------------------------------------------

UGamendAsyncAction* UGamendAsyncAction::LoginDevice(UObject* WorldContextObject, const FString& DeviceId)
{
	return Make(WorldContextObject, [DeviceId](UGamendSubsystem& Gamend, const FDone& Done)
	{
		const FString Id = DeviceId.IsEmpty() ? Gamend.GetDeviceId() : DeviceId;
		Gamend.GetClient().auth().login_device(GamendUnreal::ToStd(Id), [Done](const gamend::AuthResult& Auth) { Done(FromAuth(Auth)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::LoginEmail(UObject* WorldContextObject, const FString& Email, const FString& Password)
{
	return Make(WorldContextObject, [Email, Password](UGamendSubsystem& Gamend, const FDone& Done)
	{
		Gamend.GetClient().auth().login_email(GamendUnreal::ToStd(Email), GamendUnreal::ToStd(Password),
			[Done](const gamend::AuthResult& Auth) { Done(FromAuth(Auth)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::LoginSteam(UObject* WorldContextObject, const FString& Ticket)
{
	return Make(WorldContextObject, [Ticket](UGamendSubsystem& Gamend, const FDone& Done)
	{
		Gamend.GetClient().auth().login_steam(GamendUnreal::ToStd(Ticket), [Done](const gamend::AuthResult& Auth) { Done(FromAuth(Auth)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::SignIn(UObject* WorldContextObject, const FString& Provider)
{
	return Make(WorldContextObject, [Provider](UGamendSubsystem& Gamend, const FDone& Done)
	{
		Gamend.GetClient().auth().sign_in(GamendUnreal::ToStd(Provider), [Done](const gamend::AuthResult& Auth) { Done(FromAuth(Auth)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::RegisterEmail(UObject* WorldContextObject, const FString& Email, const FString& Username)
{
	return Make(WorldContextObject, [Email, Username](UGamendSubsystem& Gamend, const FDone& Done)
	{
		Gamend.GetClient().auth().register_email(GamendUnreal::ToStd(Email), GamendUnreal::ToStd(Username),
			[Done](const gamend::Response& Response) { Done(FromResponse(Response)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::ConfirmRegistration(UObject* WorldContextObject, const FString& Email, const FString& Code, const FString& Password)
{
	return Make(WorldContextObject, [Email, Code, Password](UGamendSubsystem& Gamend, const FDone& Done)
	{
		Gamend.GetClient().auth().confirm_registration(GamendUnreal::ToStd(Email), GamendUnreal::ToStd(Code), GamendUnreal::ToStd(Password),
			[Done](const gamend::AuthResult& Auth) { Done(FromAuth(Auth)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::Logout(UObject* WorldContextObject)
{
	return Make(WorldContextObject, [](UGamendSubsystem& Gamend, const FDone& Done)
	{
		Gamend.GetClient().auth().logout([Done](const gamend::AuthResult& Auth) { Done(FromAuth(Auth)); });
	});
}

// --- REST --------------------------------------------------------------------

UGamendAsyncAction* UGamendAsyncAction::CallApi(UObject* WorldContextObject, const FString& Method, const FString& Path, const FString& BodyJson)
{
	return Make(WorldContextObject, [Method, Path, BodyJson](UGamendSubsystem& Gamend, const FDone& Done)
	{
		gamend::json Value;
		if (!ParseJson(BodyJson, nullptr, Value))
		{
			Done(Refused(TEXT("invalid_json")));
			return;
		}
		gamend::Body Body = Value.is_null() ? gamend::Body::none() : gamend::Body::of(std::move(Value));
		Gamend.GetClient().rest().send(GamendUnreal::ToStd(Method.ToUpper()), GamendUnreal::ToStd(Path), std::move(Body),
			[Done](const gamend::Response& Response) { Done(FromResponse(Response)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::GetMe(UObject* WorldContextObject)
{
	return Make(WorldContextObject, [](UGamendSubsystem& Gamend, const FDone& Done)
	{
		Gamend.GetClient().api().users_get_current_user([Done](const gamend::Response& Response) { Done(FromResponse(Response)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::QuickJoinLobby(UObject* WorldContextObject, const FString& Title, int32 MaxUsers)
{
	return Make(WorldContextObject, [Title, MaxUsers](UGamendSubsystem& Gamend, const FDone& Done)
	{
		gamend::json Params = gamend::json::object();
		if (!Title.IsEmpty()) Params["title"] = GamendUnreal::ToStd(Title);
		if (MaxUsers > 0) Params["max_users"] = MaxUsers;
		Gamend.GetClient().api().lobbies_quick_join(Params, [Done](const gamend::Response& Response) { Done(FromResponse(Response)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::CreateLobby(UObject* WorldContextObject, const FString& ParamsJson)
{
	return Make(WorldContextObject, [ParamsJson](UGamendSubsystem& Gamend, const FDone& Done)
	{
		gamend::json Params;
		if (!ParseJson(ParamsJson, gamend::json::object(), Params) || !Params.is_object())
		{
			Done(Refused(TEXT("invalid_json")));
			return;
		}
		Gamend.GetClient().api().lobbies_create_lobby(Params, [Done](const gamend::Response& Response) { Done(FromResponse(Response)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::ListLobbies(UObject* WorldContextObject, const FString& Title, int32 Page, int32 PageSize)
{
	return Make(WorldContextObject, [Title, Page, PageSize](UGamendSubsystem& Gamend, const FDone& Done)
	{
		gamend::json Options = PageOptions(Page, PageSize);
		if (!Title.IsEmpty()) Options["title"] = GamendUnreal::ToStd(Title);
		Gamend.GetClient().api().lobbies_list_lobbies(Options, [Done](const gamend::Response& Response) { Done(FromResponse(Response)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::JoinLobby(UObject* WorldContextObject, const FString& LobbyId, const FString& Password)
{
	return Make(WorldContextObject, [LobbyId, Password](UGamendSubsystem& Gamend, const FDone& Done)
	{
		gamend::json Params = gamend::json::object();
		if (!Password.IsEmpty()) Params["password"] = GamendUnreal::ToStd(Password);
		Gamend.GetClient().api().lobbies_join_lobby(GamendUnreal::ToStd(LobbyId), Params,
			[Done](const gamend::Response& Response) { Done(FromResponse(Response)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::LeaveLobby(UObject* WorldContextObject)
{
	return Make(WorldContextObject, [](UGamendSubsystem& Gamend, const FDone& Done)
	{
		Gamend.GetClient().api().lobbies_leave_lobby([Done](const gamend::Response& Response) { Done(FromResponse(Response)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::ListLeaderboardRecords(UObject* WorldContextObject, const FString& LeaderboardId, int32 Page, int32 PageSize)
{
	return Make(WorldContextObject, [LeaderboardId, Page, PageSize](UGamendSubsystem& Gamend, const FDone& Done)
	{
		Gamend.GetClient().api().leaderboards_list_leaderboard_records(GamendUnreal::ToStd(LeaderboardId), PageOptions(Page, PageSize),
			[Done](const gamend::Response& Response) { Done(FromResponse(Response)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::GetKeyValue(UObject* WorldContextObject, const FString& Key, const FString& UserId)
{
	return Make(WorldContextObject, [Key, UserId](UGamendSubsystem& Gamend, const FDone& Done)
	{
		// Always from the server: a Blueprint asking wants the row as it is now.
		Gamend.GetClient().kv().fetch(gamend::KvKey(GamendUnreal::ToStd(Key), GamendUnreal::ToStd(UserId)), true,
			[Done](const gamend::KvResult& Kv)
			{
				FGamendResult Result;
				Result.bOk = Kv.ok;
				Result.Error = GamendUnreal::ToFString(Kv.error);
				Result.Data = GamendUnreal::ToJsonString(Kv.row.data);
				Result.Body = GamendUnreal::ToJsonString(
					gamend::json{{"exists", Kv.row.exists}, {"data", Kv.row.data}, {"metadata", Kv.row.metadata}});
				Done(Result);
			});
	});
}

// --- Realtime ----------------------------------------------------------------

UGamendAsyncAction* UGamendAsyncAction::CallHook(UObject* WorldContextObject, const FString& Plugin, const FString& Function, const FString& ArgsJson)
{
	return Make(WorldContextObject, [Plugin, Function, ArgsJson](UGamendSubsystem& Gamend, const FDone& Done)
	{
		gamend::json Args;
		if (!ParseJson(ArgsJson, gamend::json::array(), Args))
		{
			Done(Refused(TEXT("invalid_json")));
			return;
		}
		Gamend.GetClient().realtime().call_hook(GamendUnreal::ToStd(Plugin), GamendUnreal::ToStd(Function), std::move(Args),
			[Done](const gamend::HookResult& Hook) { Done(FromHook(Hook)); });
	});
}

UGamendAsyncAction* UGamendAsyncAction::Push(UObject* WorldContextObject, const FString& Topic, const FString& Event, const FString& PayloadJson)
{
	return Make(WorldContextObject, [Topic, Event, PayloadJson](UGamendSubsystem& Gamend, const FDone& Done)
	{
		gamend::json Payload;
		if (!ParseJson(PayloadJson, gamend::json::object(), Payload))
		{
			Done(Refused(TEXT("invalid_json")));
			return;
		}
		Gamend.GetClient().realtime().push(GamendUnreal::ToStd(Topic), GamendUnreal::ToStd(Event), std::move(Payload),
			[Done](const gamend::Reply& Reply) { Done(FromReply(Reply)); });
	});
}
