#include <Windows.h>
#include <SDL.h>
#include <string>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Storage.h>

extern "C" int SDL_main(int argc, char **argv);

namespace
{

int runLove(int, char **)
{
    std::wstring packagePath = winrt::Windows::ApplicationModel::Package::Current()
        .InstalledLocation().Path().c_str();
    std::string gamePath = winrt::to_string(packagePath + L"\\gen2recomp.love");

    char executable[] = "Gen2RecompedUWP";
    char fused[] = "--fused";
    char *loveArgv[] = {executable, gamePath.data(), fused, nullptr};
    return SDL_main(3, loveArgv);
}

} // namespace

int CALLBACK WinMain(HINSTANCE, HINSTANCE, LPSTR, int)
{
    SDL_SetHint(SDL_HINT_WINRT_HANDLE_BACK_BUTTON, "1");
    return SDL_WinRTRunApp(runLove, nullptr);
}
