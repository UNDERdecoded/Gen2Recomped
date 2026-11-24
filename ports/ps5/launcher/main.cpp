// Gen2Recomped PS5 launcher: runs LOVE 11.5 on the bundled game.love inside a
// native PS5 title (eboot.bin started by the shell, registered by
// ShadowMountPlus).
//
// What it does before LOVE starts:
//   * picks the writable root, /data/gen2recomp (falls back to
//     /download0/gen2recomp when the title cannot write /data), and points
//     XDG_DATA_HOME and HOME there. LOVE runs the game fused (see
//     ports/ps5/love/0001-love-11.5-ps5.patch), so the save directory is
//     <root>/<identity>, i.e. /data/gen2recomp/Gen2Recomp;
//   * sends stdout/stderr (LOVE's print, errors) to <root>/love.log;
//   * decides whether LuaJIT may JIT: a title may or may not get executable
//     memory, and LuaJIT exits the process when mprotect(PROT_EXEC) fails, so
//     the launcher tries it first and turns the JIT engine off when it cannot.
//     <root>/jit-off or <root>/jit-on override the probe;
//   * hides the splash screen.
// Then it is LOVE's own love.cpp loop (restart included). A title must not
// exit(): when the game quits, the launcher asks the system to close it.
//
// Logged to the kernel log with the prefix "[gen2recomp]".

#define SDL_MAIN_HANDLED 1
#include <SDL.h>

#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
#include <luajit.h>
#include <lualib.h>
}

#include "common/runtime.h"
#include "common/version.h"
#include "modules/love/love.h"

extern "C" {
int sceKernelDebugOutText(int channel, const char *text);
int sceKernelUsleep(unsigned int microseconds);
int sceSystemServiceHideSplashScreen(void);
int sceSystemServiceLoadExec(const char *path, char *const argv[]);
}

// The title's direct-memory heap (ps5-opengl's native-app/app_heap.c, linked
// with --wrap=malloc and friends): every malloc, operator new and -- through
// LUAJIT_USE_SYSMALLOC -- the whole Lua heap. Flexible memory in a title is a
// few hundred MiB; 3 GiB of the title's direct memory leaves the rest of it
// to the GPU (ps5-opengl).
extern "C" const size_t ps5_opengl_heap_size = (size_t) 3 << 30;

namespace
{

const char *const kGame = "/app0/game.love";
char g_root[256] = "/data/gen2recomp";

void say(const char *fmt, ...)
{
	char line[512];
	int n = snprintf(line, sizeof(line), "[gen2recomp] ");
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(line + n, sizeof(line) - n - 1, fmt, ap);
	va_end(ap);
	size_t len = strlen(line);
	if (len == 0 || line[len - 1] != '\n')
	{
		line[len] = '\n';
		line[len + 1] = 0;
	}
	sceKernelDebugOutText(0, line);
	fputs(line, stdout);
	fflush(stdout);
}

bool exists(const char *path)
{
	struct stat st;
	return stat(path, &st) == 0;
}

bool writable_dir(const char *dir)
{
	mkdir(dir, 0777);
	char probe[300];
	snprintf(probe, sizeof(probe), "%s/.probe", dir);
	int fd = open(probe, O_CREAT | O_WRONLY | O_TRUNC, 0666);
	if (fd < 0)
		return false;
	bool ok = write(fd, "ok", 2) == 2;
	close(fd);
	unlink(probe);
	return ok;
}

void pick_root()
{
	const char *candidates[] = {"/data/gen2recomp", "/download0/gen2recomp"};
	for (const char *dir : candidates)
	{
		if (writable_dir(dir))
		{
			snprintf(g_root, sizeof(g_root), "%s", dir);
			return;
		}
		sceKernelDebugOutText(0, "[gen2recomp] cannot write a data root candidate\n");
	}
}

// Players reach the save directory over FTP (ROMs into imports/, saves out of
// exports/), and ftpsrv runs as a different user from the title. Builds before
// ports/ps5/love/0002-physfs-shared-modes.patch made these folders 0700, which
// ftpsrv cannot enter; open the ones that already exist. Folders made from now
// on are created 0777 by the patched PhysFS.
void open_shared_dirs()
{
	const char *subdirs[] = {"", "/Gen2Recomp", "/Gen2Recomp/imports", "/Gen2Recomp/imports/mods",
	                         "/Gen2Recomp/imports/saves", "/Gen2Recomp/exports"};
	for (const char *sub : subdirs)
	{
		char path[300];
		snprintf(path, sizeof(path), "%s%s", g_root, sub);
		struct stat st;
		if (stat(path, &st) == 0 && S_ISDIR(st.st_mode) && (st.st_mode & 0777) != 0777)
			chmod(path, 0777);
	}
}

void open_log()
{
	char path[300];
	snprintf(path, sizeof(path), "%s/love.log", g_root);
	if (freopen(path, "w", stdout) != nullptr)
		setvbuf(stdout, nullptr, _IOLBF, 0);
	if (freopen(path, "a", stderr) != nullptr)
		setvbuf(stderr, nullptr, _IONBF, 0);
}

// The same sequence LuaJIT's mcode allocator uses: map read/write, then flip
// to read/execute. Calls the page too, so a mapping that claims PROT_EXEC but
// faults shows up here, right after the "probing" line, not mid-game.
bool jit_memory_works()
{
	const size_t size = 4096;
	void *page = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
	if (page == MAP_FAILED)
	{
		say("JIT probe: mmap failed (errno %d)", errno);
		return false;
	}
	static const unsigned char code[] = {0xB8, 0x2A, 0x00, 0x00, 0x00, 0xC3}; // mov eax, 42; ret
	memcpy(page, code, sizeof(code));
	if (mprotect(page, size, PROT_READ | PROT_EXEC) != 0)
	{
		say("JIT probe: mprotect(PROT_EXEC) failed (errno %d)", errno);
		munmap(page, size);
		return false;
	}
	say("JIT probe: executing a test page");
	int result = ((int (*)(void)) page)();
	munmap(page, size);
	return result == 42;
}

bool decide_jit()
{
	char path[300];
	snprintf(path, sizeof(path), "%s/jit-off", g_root);
	if (exists(path))
	{
		say("JIT off (%s)", path);
		return false;
	}
	snprintf(path, sizeof(path), "%s/jit-on", g_root);
	if (exists(path))
	{
		say("JIT on (%s)", path);
		return true;
	}
	bool ok = jit_memory_works();
	say("JIT %s (probe)", ok ? "on" : "off: interpreter only");
	return ok;
}

int love_preload(lua_State *L, lua_CFunction f, const char *name)
{
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "preload");
	lua_pushcfunction(L, f);
	lua_setfield(L, -2, name);
	lua_pop(L, 2);
	return 0;
}

enum DoneAction
{
	DONE_QUIT,
	DONE_RESTART,
};

// love.cpp's runlove(), with the JIT decision and the PS5 arguments.
DoneAction run_love(bool jit, int &retval)
{
	lua_State *L = luaL_newstate();
	if (L == nullptr)
	{
		say("luaL_newstate failed");
		retval = 1;
		return DONE_QUIT;
	}
	luaL_openlibs(L);

	if (!jit)
		luaJIT_setmode(L, 0, LUAJIT_MODE_ENGINE | LUAJIT_MODE_OFF);

	love_preload(L, luaopen_love_jitsetup, "love.jitsetup");
	lua_getglobal(L, "require");
	lua_pushstring(L, "love.jitsetup");
	lua_call(L, 1, 0);

	love_preload(L, luaopen_love, "love");

	// arg[-2] is the "executable"; the game itself comes from
	// Filesystem::getExecutablePath() (/app0/game.love, mounted fused).
	lua_newtable(L);
	lua_pushstring(L, "/app0/eboot.bin");
	lua_rawseti(L, -2, -2);
	lua_pushstring(L, "embedded boot.lua");
	lua_rawseti(L, -2, -1);
	lua_setglobal(L, "arg");

	lua_getglobal(L, "require");
	lua_pushstring(L, "love");
	lua_call(L, 1, 1);
	lua_pushboolean(L, 1);
	lua_setfield(L, -2, "_exe");
	lua_pop(L, 1);

	// Debug aid: with an (empty) <root>/screenshot file, every 600th frame
	// (10 s at 60 Hz) is saved to <root>/screenshot.png, read back by LOVE
	// itself. Screen captures of the console (Remote Play, the capture API)
	// do not always see a title's GL output.
	static const char *const kScreenshotHook =
		"local root = ...\n"
		"local f = io.open(root .. '/screenshot', 'r')\n"
		"if not f then return end\n"
		"f:close()\n"
		"local open = package.preload['love.graphics']\n"
		"package.preload['love.graphics'] = function(...)\n"
		"  local g = open(...)\n"
		"  local present, frames = g.present, 0\n"
		"  g.present = function(...)\n"
		"    frames = frames + 1\n"
		"    if frames % 600 == 0 then\n"
		"      g.captureScreenshot(function(img)\n"
		"        local out = io.open(root .. '/screenshot.png', 'wb')\n"
		"        if out then out:write(img:encode('png'):getString()); out:close() end\n"
		"      end)\n"
		"    end\n"
		"    return present(...)\n"
		"  end\n"
		"  return g\n"
		"end\n";
	if (luaL_loadstring(L, kScreenshotHook) == 0)
	{
		lua_pushstring(L, g_root);
		if (lua_pcall(L, 1, 0, 0) != 0)
		{
			say("screenshot hook: %s", lua_tostring(L, -1));
			lua_pop(L, 1);
		}
	}

	lua_getglobal(L, "require");
	lua_pushstring(L, "love.boot");
	lua_call(L, 1, 1);

	lua_newthread(L);
	lua_pushvalue(L, -2);
	int stackpos = lua_gettop(L);
	int nres;
	while (love::luax_resume(L, 0, &nres) == LUA_YIELD)
		lua_pop(L, lua_gettop(L) - stackpos);

	retval = 0;
	DoneAction done = DONE_QUIT;
	if (lua_type(L, -1) == LUA_TSTRING && strcmp(lua_tostring(L, -1), "restart") == 0)
		done = DONE_RESTART;
	if (lua_isnumber(L, -1))
		retval = (int) lua_tonumber(L, -1);

	lua_close(L);
	return done;
}

} // namespace

int main(int argc, char **argv)
{
	(void) argc;
	(void) argv;

	pick_root();
	open_shared_dirs();
	open_log();
	say("LOVE %s on PS5, data root %s", love_version(), g_root);

	setenv("XDG_DATA_HOME", g_root, 1);
	setenv("HOME", g_root, 1);
	if (getenv("LOVE_PS5_GAME") == nullptr)
		setenv("LOVE_PS5_GAME", kGame, 1);
	if (!exists(getenv("LOVE_PS5_GAME")))
		say("WARNING: %s is missing", getenv("LOVE_PS5_GAME"));

	const bool jit = decide_jit();

	sceSystemServiceHideSplashScreen();
	SDL_SetMainReady();
	// SDL's controller database only knows the DualSense under Linux GUIDs;
	// the PS5 joystick backend (ScePad) reports its own GUID and button
	// order (src/joystick/ps5/SDL_ps5joystick.c btn_map). The D-pad is mapped
	// to its buttons, not the hat, which that backend only half updates. The
	// touchpad click is "back" (the DualSense has no Select; Create is taken
	// by the system).
	SDL_SetHint(SDL_HINT_GAMECONTROLLERCONFIG,
	            "0300d0424c050000e60c000011810000,PS5 Controller,"
	            "a:b0,b:b1,x:b2,y:b3,back:b4,start:b6,leftstick:b7,rightstick:b8,"
	            "leftshoulder:b9,rightshoulder:b10,dpup:b11,dpdown:b12,dpleft:b13,dpright:b14,"
	            "leftx:a0,lefty:a1,rightx:a2,righty:a3,lefttrigger:a4,righttrigger:a5,");

	int retval = 0;
	DoneAction done;
	do
	{
		done = run_love(jit, retval);
		say("LOVE returned %d%s", retval, done == DONE_RESTART ? " (restart)" : "");
	} while (done == DONE_RESTART);

	SDL_Quit();
	fflush(nullptr);

	// A title that returns from main or calls exit() dies with SIGSYS; ask
	// the system to close it the way PS5SD and PS5LM do.
	say("closing the title");
	sceSystemServiceLoadExec("exit", nullptr);
	for (;;)
		sceKernelUsleep(100000);
}
