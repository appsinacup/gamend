// One Gamend client per game instance, ticked on the game thread.
//
// The subsystem builds a gamend::Client from Project Settings > Plugins >
// Gamend, with transports over Unreal's HTTP and WebSocket modules, and calls
// its poll() every frame, so every callback and every event below arrives on
// the game thread. It keeps the session between runs (bKeepSession) and opens
// the realtime connection once a player is signed in (bConnectOnSignIn).
//
// Blueprints: the "Gamend ..." async nodes (UGamendAsyncAction) sign in and
// call the server; OnEvent hears the realtime connection.
//
// C++: GetClient() is the whole SDK, every REST operation included.
//
//     #include "GamendSubsystem.h"
//     #include "GamendSDK.h"
//
//     UGamendSubsystem* Gamend = UGamendSubsystem::Get(this);
//     Gamend->GetClient().api().lobbies_quick_join({{"max_users", 2}},
//       [](const gamend::Response& r) { ... });
#pragma once

#include "CoreMinimal.h"
#include "Containers/Ticker.h"
#include "GamendTypes.h"
#include "Subsystems/GameInstanceSubsystem.h"

#include "GamendSubsystem.generated.h"

namespace gamend
{
	class Client;
	struct Session;
}

UCLASS()
class GAMEND_API UGamendSubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	/** The subsystem of the game instance WorldContextObject belongs to, or null. */
	static UGamendSubsystem* Get(const UObject* WorldContextObject);

	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;

	/**
	 * The C++ client, for everything the Blueprint nodes leave out. Valid between Initialize and Deinitialize; include
	 * GamendSDK.h to use it, and call it on the game thread. The subsystem holds auth().on_session_changed, which takes
	 * one listener, to keep the session: listen to OnSessionChanged instead. on_event and on_state take any number.
	 */
	gamend::Client& GetClient() const;

	// --- Session -------------------------------------------------------------

	UFUNCTION(BlueprintPure, Category = "Gamend|Session")
	bool IsSignedIn() const;

	/** The signed-in player's id, or empty. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Session")
	FString GetUserId() const;

	/** The signed-in player's username; empty when the sign-in did not say (a provider's). */
	UFUNCTION(BlueprintPure, Category = "Gamend|Session")
	FString GetUsername() const;

	UFUNCTION(BlueprintPure, Category = "Gamend|Session")
	FString GetDisplayName() const;

	/** A random id made on first use and kept in the save slot: what "Gamend Login Device" signs in with when given none. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Session")
	FString GetDeviceId();

	/** Revoke the session on the server, then forget it here and in the save slot, whatever the server answered. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Session")
	void Logout();

	/** Forget the session here and in the save slot, without telling the server. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Session")
	void ForgetSession();

	/** The session as JSON, to keep where your platform keeps secrets; empty when signed out. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Session")
	FString GetSessionJson() const;

	/** Adopt a session GetSessionJson() gave. A lapsed token is refreshed on the next frame. False when the JSON holds no session. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Session")
	bool RestoreSession(const FString& SessionJson);

	/** A player signed in, signed out, or another one signed in. Not called for a token refresh. */
	UPROPERTY(BlueprintAssignable, Category = "Gamend|Session")
	FGamendSessionDelegate OnSessionChanged;

	// --- Realtime ------------------------------------------------------------

	/** Open the realtime connection as the signed-in player and join user:<id>. It reconnects on its own until Disconnect or a sign-out. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Realtime")
	void Connect();

	/** Close the realtime connection and forget every channel. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Realtime")
	void Disconnect();

	UFUNCTION(BlueprintPure, Category = "Gamend|Realtime")
	EGamendRealtimeState GetRealtimeState() const;

	/** Join a channel by topic (lobby:<id>, lobbies, group:<id>, groups, party:<id>), now or once connected, and again after every reconnect until LeaveChannel. */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Realtime")
	void JoinChannel(const FString& Topic);

	/** Join lobby:<LobbyId>, whose events tell who joins, leaves and what changes. Joining the lobby itself is "Gamend Join Lobby" or "Gamend Quick Join Lobby". */
	UFUNCTION(BlueprintCallable, Category = "Gamend|Realtime")
	void JoinLobbyChannel(const FString& LobbyId);

	UFUNCTION(BlueprintCallable, Category = "Gamend|Realtime")
	void LeaveChannel(const FString& Topic);

	UFUNCTION(BlueprintPure, Category = "Gamend|Realtime")
	bool IsChannelJoined(const FString& Topic) const;

	/** Every event the server pushes, on every channel. */
	UPROPERTY(BlueprintAssignable, Category = "Gamend|Realtime")
	FGamendEventDelegate OnEvent;

	/** Every change of GetRealtimeState(). */
	UPROPERTY(BlueprintAssignable, Category = "Gamend|Realtime")
	FGamendRealtimeStateDelegate OnRealtimeStateChanged;

private:
	bool TickClient(float DeltaTime);
	void SessionChanged(const gamend::Session* Session);
	void LoadSaveSlot();
	void WriteSaveSlot();

	/** Shared, not unique: its deleter is fixed where gamend::Client is complete, so this header can leave it incomplete. */
	TSharedPtr<gamend::Client> Client;
	FTSTicker::FDelegateHandle TickHandle;

	/** The save game slot: SaveSlot, with a suffix for each extra player of a multiplayer PIE session. */
	FString SlotName;
	FString DeviceId;
	FString SavedSession;
	FString LastUserId;
};
