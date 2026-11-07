#include <Windows.h>
#include <SDL.h>
#include <chrono>
#include <exception>
#include <fstream>
#include <string>
#include <thread>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.ApplicationModel.Core.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Pickers.h>
#include <winrt/Windows.UI.Core.h>

extern "C" int SDL_main(int argc, char **argv);

namespace
{

// THE ROM PICKER. The picker inside the bundled love.dll only offers .gb and
// .gbc, so GBA and DS games could not be chosen. This one offers all four, and
// talks to src/import/XboxPicker.lua through three files in LocalState:
//
//   gr_picker_ready   written at startup: this package has the picker
//   gr_pick_request   Lua creates it to ask; deleted here when taken
//   gr_pick_result    one line, then a newline so a partial read is detectable:
//                     P<path>, C for a cancel, or E<message>
//
// The chosen file is copied into LocalState, as the love.dll picker does, since
// the package may not be able to open the original again later.

void writeTextFile(const std::wstring &path, const std::string &text)
{
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    output << text;
}

void finishPick(const std::wstring &root, const std::string &line)
{
    writeTextFile(root + L"\\gr_pick_result", line + "\n");
}

void openRomPicker(const std::wstring &root)
{
    namespace Foundation = winrt::Windows::Foundation;
    namespace Storage = winrt::Windows::Storage;
    namespace Pickers = winrt::Windows::Storage::Pickers;

    try
    {
        Pickers::FileOpenPicker picker;
        picker.SuggestedStartLocation(Pickers::PickerLocationId::ComputerFolder);
        auto filters = picker.FileTypeFilter();
        filters.Append(L".gb");
        filters.Append(L".gbc");
        filters.Append(L".gba");
        filters.Append(L".nds");

        auto operation = picker.PickSingleFileAsync();
        operation.Completed([root](auto const &pick, Foundation::AsyncStatus status)
        {
            try
            {
                if (status == Foundation::AsyncStatus::Canceled)
                {
                    finishPick(root, "C");
                    return;
                }
                if (status != Foundation::AsyncStatus::Completed)
                {
                    finishPick(root, "E" + winrt::to_string(winrt::hresult_error(pick.ErrorCode()).message()));
                    return;
                }
                Storage::StorageFile selected = pick.GetResults();
                if (!selected)
                {
                    finishPick(root, "C");
                    return;
                }

                std::wstring name = L"picked_rom";
                name += selected.FileType().c_str();
                auto copy = selected.CopyAsync(Storage::ApplicationData::Current().LocalFolder(),
                    winrt::hstring(name), Storage::NameCollisionOption::ReplaceExisting);
                copy.Completed([root](auto const &done, Foundation::AsyncStatus copyStatus)
                {
                    try
                    {
                        if (copyStatus == Foundation::AsyncStatus::Completed)
                        {
                            Storage::StorageFile local = done.GetResults();
                            finishPick(root, "P" + winrt::to_string(local.Path()));
                        }
                        else if (copyStatus == Foundation::AsyncStatus::Canceled)
                            finishPick(root, "C");
                        else
                            finishPick(root, "E" + winrt::to_string(winrt::hresult_error(done.ErrorCode()).message()));
                    }
                    catch (const winrt::hresult_error &e)
                    {
                        finishPick(root, "E" + winrt::to_string(e.message()));
                    }
                });
            }
            catch (const winrt::hresult_error &e)
            {
                finishPick(root, "E" + winrt::to_string(e.message()));
            }
        });
    }
    catch (const winrt::hresult_error &e)
    {
        finishPick(root, "E" + winrt::to_string(e.message()));
    }
}

void watchPickRequests(std::wstring root)
{
    try
    {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        const std::wstring request = root + L"\\gr_pick_request";
        DeleteFileW(request.c_str());
        writeTextFile(root + L"\\gr_picker_ready", "1\n");

        for (;;)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(250));
            if (!DeleteFileW(request.c_str()))
                continue;
            try
            {
                // A picker has to be opened on the app's view thread.
                winrt::Windows::ApplicationModel::Core::CoreApplication::MainView()
                    .CoreWindow().Dispatcher().RunAsync(
                        winrt::Windows::UI::Core::CoreDispatcherPriority::Normal,
                        [root]() { openRomPicker(root); });
            }
            catch (const winrt::hresult_error &e)
            {
                finishPick(root, "E" + winrt::to_string(e.message()));
            }
        }
    }
    catch (...)
    {
        // Without gr_picker_ready, Lua keeps using the love.dll picker.
    }
}

int runLove(int, char **)
{
    std::wstring packagePath = winrt::Windows::ApplicationModel::Package::Current()
        .InstalledLocation().Path().c_str();
    std::string gamePath = winrt::to_string(packagePath + L"\\gen2recomp.love");

    std::wstring localState = winrt::Windows::Storage::ApplicationData::Current()
        .LocalFolder().Path().c_str();
    std::thread(watchPickRequests, localState).detach();

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
