// Reading and building the JSON the Gamend nodes pass around, from Blueprints.
//
// A path walks objects by key and arrays by index, dot-separated:
// "members.0.username" in a lobby, "meta.total_count" in a page's Body. An
// empty path is the value itself.
#pragma once

#include "CoreMinimal.h"
#include "Kismet/BlueprintFunctionLibrary.h"

#include "GamendJsonLibrary.generated.h"

UCLASS()
class GAMEND_API UGamendJsonLibrary : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()

public:
	/** The string at Path. False when there is none, or it is not a string. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Json", meta = (DisplayName = "Gamend Json Get String"))
	static bool GetString(const FString& Json, const FString& Path, FString& Value);

	/** The number at Path. False when there is none, or it is not a number. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Json", meta = (DisplayName = "Gamend Json Get Number"))
	static bool GetNumber(const FString& Json, const FString& Path, double& Value);

	/** The integer at Path (ids, counts, scores). False when there is none, or it is not a number. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Json", meta = (DisplayName = "Gamend Json Get Integer"))
	static bool GetInteger(const FString& Json, const FString& Path, int64& Value);

	/** The boolean at Path. False when there is none, or it is not a boolean. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Json", meta = (DisplayName = "Gamend Json Get Bool"))
	static bool GetBool(const FString& Json, const FString& Path, bool& Value);

	/** The value at Path, whatever it is, as JSON: an object or a list to read further. False when there is none. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Json", meta = (DisplayName = "Gamend Json Get Value"))
	static bool GetJson(const FString& Json, const FString& Path, FString& Value);

	/** The items of the list at Path, each as JSON. Empty when there is no list. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Json", meta = (DisplayName = "Gamend Json Get Items"))
	static TArray<FString> GetItems(const FString& Json, const FString& Path);

	/** The keys of the object at Path. Empty when there is no object. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Json", meta = (DisplayName = "Gamend Json Get Keys"))
	static TArray<FString> GetKeys(const FString& Json, const FString& Path);

	/** Json (an object; empty for a new one) with Key set to a string. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Json", meta = (DisplayName = "Gamend Json Set String"))
	static FString SetString(const FString& Json, const FString& Key, const FString& Value);

	/** Json (an object; empty for a new one) with Key set to a number. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Json", meta = (DisplayName = "Gamend Json Set Number"))
	static FString SetNumber(const FString& Json, const FString& Key, double Value);

	/** Json (an object; empty for a new one) with Key set to an integer. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Json", meta = (DisplayName = "Gamend Json Set Integer"))
	static FString SetInteger(const FString& Json, const FString& Key, int64 Value);

	/** Json (an object; empty for a new one) with Key set to a boolean. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Json", meta = (DisplayName = "Gamend Json Set Bool"))
	static FString SetBool(const FString& Json, const FString& Key, bool Value);

	/** Json (an object; empty for a new one) with Key set to another JSON value: an object, a list, null. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Json", meta = (DisplayName = "Gamend Json Set Value"))
	static FString SetJson(const FString& Json, const FString& Key, const FString& Value);

	/** A list of the given JSON values, for a hook's arguments. */
	UFUNCTION(BlueprintPure, Category = "Gamend|Json", meta = (DisplayName = "Gamend Json Make List"))
	static FString MakeList(const TArray<FString>& Items);
};
