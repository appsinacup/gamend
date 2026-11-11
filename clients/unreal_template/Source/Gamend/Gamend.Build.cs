// The Unreal side of the Gamend plugin: UGamendSubsystem, the HTTP and
// WebSocket transports over Unreal's own modules, the project settings and the
// Blueprint nodes. The client itself is the GamendSDK module.
using UnrealBuildTool;

public class Gamend : ModuleRules
{
	public Gamend(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[]
		{
			"Core",
			"CoreUObject",
			"Engine",
			"DeveloperSettings",
			// Public: a game that includes GamendSubsystem.h may call the
			// gamend::Client it hands out.
			"GamendSDK",
		});

		PrivateDependencyModuleNames.AddRange(new string[]
		{
			"HTTP",
			"WebSockets",
		});
	}
}
