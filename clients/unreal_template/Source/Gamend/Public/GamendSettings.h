// Project Settings > Plugins > Gamend, kept in Config/DefaultGame.ini under
// [/Script/Gamend.GamendSettings].
#pragma once

#include "CoreMinimal.h"
#include "Engine/DeveloperSettings.h"
#include "GamendTypes.h"

#include "GamendSettings.generated.h"

UCLASS(Config = Game, DefaultConfig, meta = (DisplayName = "Gamend"))
class GAMEND_API UGamendSettings : public UDeveloperSettings
{
	GENERATED_BODY()

public:
	UGamendSettings();

	/** The server root, https://game.example.com. Paths are appended to it. */
	UPROPERTY(Config, EditAnywhere, Category = "Server")
	FString BaseUrl = TEXT("http://127.0.0.1:4000");

	/** How long a REST call waits for its reply. */
	UPROPERTY(Config, EditAnywhere, Category = "Server", meta = (ClampMin = "1", Units = "s"))
	float HttpTimeoutSeconds = 10.f;

	/** Keep the session between runs, in a save game slot, so the player stays signed in. The refresh token is stored as it is; turn this off and keep GetSessionJson() somewhere safer to do better. */
	UPROPERTY(Config, EditAnywhere, Category = "Session")
	bool bKeepSession = true;

	/** The save game slot that holds the session and the device id. */
	UPROPERTY(Config, EditAnywhere, Category = "Session")
	FString SaveSlot = TEXT("Gamend");

	/** Open the realtime connection as soon as a player is signed in, restored sessions included. */
	UPROPERTY(Config, EditAnywhere, Category = "Realtime")
	bool bConnectOnSignIn = true;

	/** How the server sends realtime events. */
	UPROPERTY(Config, EditAnywhere, Category = "Realtime")
	EGamendRealtimeFormat RealtimeFormat = EGamendRealtimeFormat::Json;
};
