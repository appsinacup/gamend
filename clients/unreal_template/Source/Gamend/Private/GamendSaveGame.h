// What UGamendSubsystem keeps between runs, in the save slot of its settings.
#pragma once

#include "CoreMinimal.h"
#include "GameFramework/SaveGame.h"

#include "GamendSaveGame.generated.h"

UCLASS()
class UGamendSaveGame : public USaveGame
{
	GENERATED_BODY()

public:
	/** What "Gamend Login Device" signs in with when given no id. */
	UPROPERTY()
	FString DeviceId;

	/** gamend::Session::to_json(), when bKeepSession. */
	UPROPERTY()
	FString Session;
};
