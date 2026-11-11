// What the Blueprint side of the plugin passes around. JSON travels as text:
// read it with the Gamend|Json nodes (UGamendJsonLibrary).
#pragma once

#include "CoreMinimal.h"

#include "GamendTypes.generated.h"

/** The realtime connection, as gamend::RealtimeState. */
UENUM(BlueprintType)
enum class EGamendRealtimeState : uint8
{
	/** Not connected, and not trying. */
	Disconnected,
	/** Opening the first connection. */
	Connecting,
	/** Open; channels are joining or joined. */
	Connected,
	/** The connection dropped; the next attempt is scheduled or under way. */
	Reconnecting,
};

/** How the server sends realtime events. */
UENUM(BlueprintType)
enum class EGamendRealtimeFormat : uint8
{
	/** Every event as JSON text. */
	Json,
	/** Binary protobuf frames, decoded before they arrive: smaller on the wire, timestamps as unix milliseconds. */
	Protobuf,
};

/** What a call answered. */
USTRUCT(BlueprintType)
struct GAMEND_API FGamendResult
{
	GENERATED_BODY()

	/** The call succeeded. */
	UPROPERTY(BlueprintReadOnly, Category = "Gamend")
	bool bOk = false;

	/** The HTTP status of a REST call; 0 when no reply arrived, and for a realtime call. */
	UPROPERTY(BlueprintReadOnly, Category = "Gamend")
	int32 Status = 0;

	/** Empty on success. Otherwise the server's code (not_found, validation_failed, ...), timeout, or what went wrong before it answered. */
	UPROPERTY(BlueprintReadOnly, Category = "Gamend")
	FString Error;

	/** The server's human-readable message, when it sent one. */
	UPROPERTY(BlueprintReadOnly, Category = "Gamend")
	FString Message;

	/** What the call answered, as JSON: a REST reply's data, a hook's return value, a channel's reply. */
	UPROPERTY(BlueprintReadOnly, Category = "Gamend")
	FString Data;

	/** The whole REST reply, as JSON: data with the meta of a page, or the error with its field errors. */
	UPROPERTY(BlueprintReadOnly, Category = "Gamend")
	FString Body;
};

/** A message the server pushed on a channel. */
USTRUCT(BlueprintType)
struct GAMEND_API FGamendEvent
{
	GENERATED_BODY()

	/** The channel's topic: user:<id>, lobby:<id>, lobbies, ... */
	UPROPERTY(BlueprintReadOnly, Category = "Gamend")
	FString Topic;

	/** The event as the server named it: updated, user_joined, ... */
	UPROPERTY(BlueprintReadOnly, Category = "Gamend")
	FString Name;

	/** What every Gamend SDK calls it: lobby_updated, lobby_member_joined, kv_updated, ... or message for one it does not name. See https://gamend.org/docs/realtime. */
	UPROPERTY(BlueprintReadOnly, Category = "Gamend")
	FString Kind;

	/** The payload, as JSON. */
	UPROPERTY(BlueprintReadOnly, Category = "Gamend")
	FString Payload;
};

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FGamendEventDelegate, const FGamendEvent&, Event);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FGamendRealtimeStateDelegate, EGamendRealtimeState, State);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FGamendSessionDelegate, bool, bSignedIn);
DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FGamendResultDelegate, const FGamendResult&, Result);
