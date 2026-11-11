// The "Gamend ..." Blueprint nodes: one call each, with On Success and On
// Failure pins that fire on the game thread once the server answers. Each
// pin carries an FGamendResult; its Data is the answer as JSON.
//
// These cover signing in and the calls most games make first. Every other
// operation is "Gamend Call API" with its path, or GetClient().api() in C++.
#pragma once

#include "CoreMinimal.h"
#include "GamendTypes.h"
#include "Kismet/BlueprintAsyncActionBase.h"

#include "GamendAsyncAction.generated.h"

class UGamendSubsystem;

UCLASS()
class GAMEND_API UGamendAsyncAction : public UBlueprintAsyncActionBase
{
	GENERATED_BODY()

public:
	/** The call succeeded. */
	UPROPERTY(BlueprintAssignable, Category = "Gamend")
	FGamendResultDelegate OnSuccess;

	/** The call failed: Error says why. */
	UPROPERTY(BlueprintAssignable, Category = "Gamend")
	FGamendResultDelegate OnFailure;

	// --- Session -------------------------------------------------------------

	/** Sign in with a device id; an unknown one makes an anonymous account. Empty: the subsystem's own (GetDeviceId). Data: the session's user. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Session", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Login Device"))
	static UGamendAsyncAction* LoginDevice(UObject* WorldContextObject, const FString& DeviceId);

	/** Sign in with an email and a password. Error: invalid_credentials, ... */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Session", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Login Email"))
	static UGamendAsyncAction* LoginEmail(UObject* WorldContextObject, const FString& Email, const FString& Password);

	/** Sign in with a Steam session ticket (ISteamUser::GetAuthTicketForWebApi, hex). */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Session", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Login Steam"))
	static UGamendAsyncAction* LoginSteam(UObject* WorldContextObject, const FString& Ticket);

	/** Sign in through a provider (google, discord, apple, ...): opens its page in the browser and waits for the player to finish there. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Session", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Sign In"))
	static UGamendAsyncAction* SignIn(UObject* WorldContextObject, const FString& Provider);

	/** Make an account with an email, and no password yet; not a sign-in. The server emails a six-digit code for "Gamend Confirm Registration". Empty Username: the server picks one. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Session", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Register Email"))
	static UGamendAsyncAction* RegisterEmail(UObject* WorldContextObject, const FString& Email, const FString& Username);

	/** Confirm a registration with the code from its email, set its password, and sign in. Error: invalid_code, account_locked, validation_failed. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Session", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Confirm Registration"))
	static UGamendAsyncAction* ConfirmRegistration(UObject* WorldContextObject, const FString& Email, const FString& Code, const FString& Password);

	/** Revoke the session on the server, then forget it here, whatever the server answered. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Session", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Logout"))
	static UGamendAsyncAction* Logout(UObject* WorldContextObject);

	// --- REST ----------------------------------------------------------------

	/** Any operation: Method (GET, POST, PUT, PATCH, DELETE) on Path (/api/v1/..., query included), with BodyJson as the body (empty for none), as the signed-in player. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|API", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Call API"))
	static UGamendAsyncAction* CallApi(UObject* WorldContextObject, const FString& Method, const FString& Path, const FString& BodyJson);

	/** The signed-in player's account. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|API", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Get Me"))
	static UGamendAsyncAction* GetMe(UObject* WorldContextObject);

	/** Join an open lobby that fits, or make one. Empty Title, or MaxUsers 0: any. Data: the lobby; join its channel (JoinLobbyChannel) to hear it. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Lobbies", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Quick Join Lobby"))
	static UGamendAsyncAction* QuickJoinLobby(UObject* WorldContextObject, const FString& Title, int32 MaxUsers);

	/** Make a lobby. ParamsJson: {"title": ..., "max_users": ..., "is_hidden": ..., "password": ..., "metadata": {...}}. Data: the lobby. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Lobbies", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Create Lobby"))
	static UGamendAsyncAction* CreateLobby(UObject* WorldContextObject, const FString& ParamsJson);

	/** Public lobbies, a page at a time. Empty Title: all. Data: the lobbies; Body's meta: the page. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Lobbies", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend List Lobbies"))
	static UGamendAsyncAction* ListLobbies(UObject* WorldContextObject, const FString& Title, int32 Page = 1, int32 PageSize = 25);

	/** Join a lobby by id; Password only for a passworded one. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Lobbies", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Join Lobby"))
	static UGamendAsyncAction* JoinLobby(UObject* WorldContextObject, const FString& LobbyId, const FString& Password);

	/** Leave the player's lobby. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Lobbies", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Leave Lobby"))
	static UGamendAsyncAction* LeaveLobby(UObject* WorldContextObject);

	/** A leaderboard's records, best first, a page at a time. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Leaderboards", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend List Leaderboard Records"))
	static UGamendAsyncAction* ListLeaderboardRecords(UObject* WorldContextObject, const FString& LeaderboardId, int32 Page = 1, int32 PageSize = 25);

	/** A key-value row: global, or the player's own with UserId. Data: the row's data, null when there is none; Body: {"exists", "data", "metadata"}. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Storage", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Get Key Value"))
	static UGamendAsyncAction* GetKeyValue(UObject* WorldContextObject, const FString& Key, const FString& UserId);

	// --- Realtime ------------------------------------------------------------

	/** Call a server hook (a plugin's function) over the realtime connection; connect first. ArgsJson: a JSON array of arguments, empty for none. Data: what the hook returned. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Realtime", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Call Hook"))
	static UGamendAsyncAction* CallHook(UObject* WorldContextObject, const FString& Plugin, const FString& Function, const FString& ArgsJson);

	/** Send an event to a joined channel and wait for its reply. PayloadJson: a JSON object, empty for {}. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Realtime", meta = (BlueprintInternalUseOnly = "true", WorldContext = "WorldContextObject", DisplayName = "Gamend Push"))
	static UGamendAsyncAction* Push(UObject* WorldContextObject, const FString& Topic, const FString& Event, const FString& PayloadJson);

	virtual void Activate() override;

private:
	using FDone = TFunction<void(const FGamendResult&)>;
	using FStart = TFunction<void(UGamendSubsystem&, const FDone&)>;

	static UGamendAsyncAction* Make(UObject* WorldContextObject, FStart InStart);
	void Finish(const FGamendResult& Result);

	FStart Start;
	TWeakObjectPtr<UGamendSubsystem> Subsystem;
};
