// The Gamend C++ SDK, compiled as it is: clients/generate_unreal.sh copies its
// headers into Public/, its sources into Private/ and nlohmann/json into
// ThirdParty/, leaving out the curl, IXWebSocket and libdatachannel
// transports. The Gamend module gives the client Unreal's own.
using System.IO;
using UnrealBuildTool;

public class GamendSDK : ModuleRules
{
	public GamendSDK(ReadOnlyTargetRules Target) : base(Target)
	{
		// The SDK includes no engine header, and no engine header is forced on
		// it. Its sources keep helpers in anonymous namespaces, which a unity
		// build would merge into one translation unit.
		PCHUsage = PCHUsageMode.NoPCHs;
		bUseUnity = false;

		// What the SDK is built for: no exceptions, no RTTI, as the engine.
		bEnableExceptions = false;
		bUseRTTI = false;

		// GamendSDKModule.cpp's IMPLEMENT_MODULE.
		PrivateDependencyModuleNames.Add("Core");

		PublicSystemIncludePaths.Add(Path.Combine(ModuleDirectory, "ThirdParty"));

		// An editor build links every module as a library of its own, so the
		// SDK's classes (gamend/export.hpp) leave this one marked for export
		// and reach the Gamend module, and a game's, marked for import. A
		// packaged game links one executable and needs neither.
		if (Target.LinkType == TargetLinkType.Modular)
		{
			PublicDefinitions.Add("GAMEND_SHARED=1");
			PrivateDefinitions.Add("GAMEND_BUILDING=1");
		}
	}
}
