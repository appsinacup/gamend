#include "GamendLog.h"
#include "Modules/ModuleManager.h"

DEFINE_LOG_CATEGORY(LogGamend);

class FGamendModule final : public IModuleInterface
{
public:
	virtual void StartupModule() override
	{
		// The transports create requests and sockets from these. Load them here,
		// on the game thread, before the first client asks for one.
		FModuleManager::Get().LoadModuleChecked(TEXT("HTTP"));
		FModuleManager::Get().LoadModuleChecked(TEXT("WebSockets"));
	}
};

IMPLEMENT_MODULE(FGamendModule, Gamend)
