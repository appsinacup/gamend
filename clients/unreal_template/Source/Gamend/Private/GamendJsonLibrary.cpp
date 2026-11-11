#include "GamendJsonLibrary.h"

#include "GamendSDK.h"

namespace
{
	/** The value at Path in Json, or null when there is none. Never aborts, as the SDK's core is built without exceptions. */
	const gamend::json* Find(const gamend::json& Root, const FString& Path)
	{
		const gamend::json* At = &Root;
		TArray<FString> Steps;
		Path.ParseIntoArray(Steps, TEXT("."), true);
		for (const FString& Step : Steps)
		{
			if (At->is_object())
			{
				const auto It = At->find(GamendUnreal::ToStd(Step));
				if (It == At->end()) return nullptr;
				At = &*It;
			}
			else if (At->is_array())
			{
				if (!Step.IsNumeric()) return nullptr;
				const int32 Index = FCString::Atoi(*Step);
				if (Index < 0 || static_cast<size_t>(Index) >= At->size()) return nullptr;
				At = &(*At)[static_cast<size_t>(Index)];
			}
			else
			{
				return nullptr;
			}
		}
		return At;
	}

	gamend::json Parse(const FString& Json)
	{
		return gamend::parse(GamendUnreal::ToStd(Json));
	}

	/** Json as an object to add to: a new one when it is empty or not an object. */
	gamend::json ObjectOf(const FString& Json)
	{
		gamend::json Value = Parse(Json);
		return Value.is_object() ? Value : gamend::json::object();
	}

	FString With(const FString& Json, const FString& Key, gamend::json Value)
	{
		gamend::json Object = ObjectOf(Json);
		Object[GamendUnreal::ToStd(Key)] = std::move(Value);
		return GamendUnreal::ToJsonString(Object);
	}
}

bool UGamendJsonLibrary::GetString(const FString& Json, const FString& Path, FString& Value)
{
	const gamend::json Root = Parse(Json);
	const gamend::json* At = Find(Root, Path);
	if (!At || !At->is_string()) return false;
	Value = GamendUnreal::ToFString(At->get<std::string>());
	return true;
}

bool UGamendJsonLibrary::GetNumber(const FString& Json, const FString& Path, double& Value)
{
	const gamend::json Root = Parse(Json);
	const gamend::json* At = Find(Root, Path);
	if (!At || !At->is_number()) return false;
	Value = At->get<double>();
	return true;
}

bool UGamendJsonLibrary::GetInteger(const FString& Json, const FString& Path, int64& Value)
{
	const gamend::json Root = Parse(Json);
	const gamend::json* At = Find(Root, Path);
	if (!At || !At->is_number()) return false;
	Value = At->is_number_float() ? static_cast<int64>(At->get<double>()) : At->get<int64>();
	return true;
}

bool UGamendJsonLibrary::GetBool(const FString& Json, const FString& Path, bool& Value)
{
	const gamend::json Root = Parse(Json);
	const gamend::json* At = Find(Root, Path);
	if (!At || !At->is_boolean()) return false;
	Value = At->get<bool>();
	return true;
}

bool UGamendJsonLibrary::GetJson(const FString& Json, const FString& Path, FString& Value)
{
	const gamend::json Root = Parse(Json);
	const gamend::json* At = Find(Root, Path);
	if (!At || At->is_discarded()) return false;
	Value = GamendUnreal::ToJsonString(*At);
	return true;
}

TArray<FString> UGamendJsonLibrary::GetItems(const FString& Json, const FString& Path)
{
	TArray<FString> Items;
	const gamend::json Root = Parse(Json);
	const gamend::json* At = Find(Root, Path);
	if (At && At->is_array())
	{
		for (const gamend::json& Item : *At)
		{
			Items.Add(GamendUnreal::ToJsonString(Item));
		}
	}
	return Items;
}

TArray<FString> UGamendJsonLibrary::GetKeys(const FString& Json, const FString& Path)
{
	TArray<FString> Keys;
	const gamend::json Root = Parse(Json);
	const gamend::json* At = Find(Root, Path);
	if (At && At->is_object())
	{
		for (auto It = At->begin(); It != At->end(); ++It)
		{
			Keys.Add(GamendUnreal::ToFString(It.key()));
		}
	}
	return Keys;
}

FString UGamendJsonLibrary::SetString(const FString& Json, const FString& Key, const FString& Value)
{
	return With(Json, Key, GamendUnreal::ToStd(Value));
}

FString UGamendJsonLibrary::SetNumber(const FString& Json, const FString& Key, double Value)
{
	return With(Json, Key, Value);
}

FString UGamendJsonLibrary::SetInteger(const FString& Json, const FString& Key, int64 Value)
{
	return With(Json, Key, Value);
}

FString UGamendJsonLibrary::SetBool(const FString& Json, const FString& Key, bool Value)
{
	return With(Json, Key, Value);
}

FString UGamendJsonLibrary::SetJson(const FString& Json, const FString& Key, const FString& Value)
{
	gamend::json Parsed = Parse(Value);
	return With(Json, Key, Parsed.is_discarded() ? gamend::json(nullptr) : std::move(Parsed));
}

FString UGamendJsonLibrary::MakeList(const TArray<FString>& Items)
{
	gamend::json List = gamend::json::array();
	for (const FString& Item : Items)
	{
		gamend::json Parsed = Parse(Item);
		List.push_back(Parsed.is_discarded() ? gamend::json(nullptr) : std::move(Parsed));
	}
	return GamendUnreal::ToJsonString(List);
}
