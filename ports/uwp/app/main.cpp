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
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.Web.Http.h>
#include <winrt/Windows.Web.Http.Filters.h>
#include <winrt/Windows.Web.Http.Headers.h>
#include <cctype>
#include <filesystem>
#include <sstream>
#include <vector>

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

// THE HTTP BRIDGE, for cloud saves. A UWP app cannot start curl, and the
// bundled LOVE 11.5 has no lua-https, so src/cloud/XboxHttp.lua hands its
// requests to this thread through files in LocalState\gr_http:
//
//   gr_http_ready      written at startup: this package has the bridge
//   gr_http\<id>.req   one request, renamed into place when complete:
//                        GRHTTP1\n METHOD\n URL\n <header count>\n
//                        "Name: value\n" per header, <body bytes>\n <body>
//   gr_http\<id>.res   the answer, renamed into place when complete:
//                        <status>\n <body>   (status 0: body is the error)
//
// Windows.Web.Http does the TLS, redirects and proxy settings. Bodies are
// text (JSON, form data, Lua save files), as on every other platform.

std::string readWholeFile(const std::wstring &path)
{
    std::ifstream input(path, std::ios::binary);
    std::ostringstream text;
    text << input.rdbuf();
    return text.str();
}

bool takeLine(const std::string &text, size_t &at, std::string &line)
{
    size_t end = text.find('\n', at);
    if (end == std::string::npos)
        return false;
    line = text.substr(at, end - at);
    if (!line.empty() && line.back() == '\r')
        line.pop_back();
    at = end + 1;
    return true;
}

void answerHttp(const std::wstring &dir, const std::wstring &id, int status, const std::string &body)
{
    const std::wstring tmp = dir + L"\\" + id + L".res.tmp";
    const std::wstring done = dir + L"\\" + id + L".res";
    writeTextFile(tmp, std::to_string(status) + "\n" + body);
    std::error_code ignored;
    std::filesystem::rename(tmp, done, ignored);
}

void serveHttp(std::wstring dir, std::wstring id)
{
    namespace Http = winrt::Windows::Web::Http;
    namespace Filters = winrt::Windows::Web::Http::Filters;
    namespace Streams = winrt::Windows::Storage::Streams;
    try
    {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
    }
    catch (...)
    {
    }
    const std::wstring work = dir + L"\\" + id + L".work";
    try
    {
        const std::string text = readWholeFile(work);
        std::error_code ignored;
        std::filesystem::remove(work, ignored);
        size_t at = 0;
        std::string magic, method, url, countLine;
        if (!takeLine(text, at, magic) || magic != "GRHTTP1" || !takeLine(text, at, method) ||
            !takeLine(text, at, url) || !takeLine(text, at, countLine))
        {
            answerHttp(dir, id, 0, "bad request file");
            return;
        }
        const int count = std::stoi(countLine);
        std::vector<std::pair<std::string, std::string>> headers;
        std::string contentType = "application/octet-stream";
        for (int i = 0; i < count; ++i)
        {
            std::string line;
            if (!takeLine(text, at, line))
            {
                answerHttp(dir, id, 0, "bad request headers");
                return;
            }
            const size_t colon = line.find(':');
            if (colon == std::string::npos)
                continue;
            std::string name = line.substr(0, colon);
            std::string value = line.substr(colon + 1);
            while (!value.empty() && value.front() == ' ')
                value.erase(value.begin());
            std::string lower = name;
            for (auto &c : lower)
                c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
            if (lower == "content-type")
                contentType = value;
            else if (lower != "content-length")
                headers.emplace_back(name, value);
        }
        std::string lengthLine;
        if (!takeLine(text, at, lengthLine))
        {
            answerHttp(dir, id, 0, "bad request body length");
            return;
        }
        const size_t length = static_cast<size_t>(std::stoull(lengthLine));
        const std::string body = text.substr(at, length);

        Filters::HttpBaseProtocolFilter filter;
        filter.CacheControl().ReadBehavior(Filters::HttpCacheReadBehavior::NoCache);
        filter.CacheControl().WriteBehavior(Filters::HttpCacheWriteBehavior::NoCache);
        Http::HttpClient client(filter);
        Http::HttpRequestMessage request(Http::HttpMethod(winrt::to_hstring(method)),
            winrt::Windows::Foundation::Uri(winrt::to_hstring(url)));
        for (const auto &header : headers)
            request.Headers().TryAppendWithoutValidation(winrt::to_hstring(header.first),
                winrt::to_hstring(header.second));
        if (length > 0 || method == "POST" || method == "PUT" || method == "PATCH")
        {
            Http::HttpStringContent content(winrt::to_hstring(body), Streams::UnicodeEncoding::Utf8);
            content.Headers().ContentType(
                Http::Headers::HttpMediaTypeHeaderValue::Parse(winrt::to_hstring(contentType)));
            request.Content(content);
        }
        auto response = client.SendRequestAsync(request).get();
        const int status = static_cast<int>(response.StatusCode());
        const std::string reply = winrt::to_string(response.Content().ReadAsStringAsync().get());
        answerHttp(dir, id, status, reply);
    }
    catch (const winrt::hresult_error &e)
    {
        answerHttp(dir, id, 0, winrt::to_string(e.message()));
    }
    catch (const std::exception &e)
    {
        answerHttp(dir, id, 0, e.what());
    }
    catch (...)
    {
        answerHttp(dir, id, 0, "unknown network error");
    }
}

void watchHttpRequests(std::wstring root)
{
    try
    {
        namespace fs = std::filesystem;
        const std::wstring dir = root + L"\\gr_http";
        std::error_code ec;
        fs::create_directories(dir, ec);
        writeTextFile(root + L"\\gr_http_ready", "1\n");
        for (;;)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
            std::vector<std::wstring> ids;
            std::error_code listed;
            for (fs::directory_iterator it(dir, listed), end; !listed && it != end; it.increment(listed))
            {
                const fs::path path = it->path();
                if (path.extension() == L".req")
                    ids.push_back(path.stem().wstring());
            }
            for (const auto &id : ids)
            {
                // Claim it first, so the next scan does not serve it twice.
                std::error_code moved;
                fs::rename(dir + L"\\" + id + L".req", dir + L"\\" + id + L".work", moved);
                if (moved)
                    continue;
                std::thread(serveHttp, dir, id).detach();
            }
        }
    }
    catch (...)
    {
        // Without gr_http_ready, Lua reports cloud saves as unavailable.
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
    std::thread(watchHttpRequests, localState).detach();

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
