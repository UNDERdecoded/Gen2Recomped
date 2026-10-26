package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local F = dofile("tests/quit_to_launcher/fixture.lua")
local Runtime = require("src.mods.Runtime")
love.event = love.event or {}
local Shell = require("src.core.HostShell")
local oldSet, launcher = Shell.setLauncherHook, nil
Shell.setLauncherHook = function(fn)
  launcher = fn
  return oldSet(fn)
end
dofile("main.lua")
Shell.setLauncherHook = oldSet
local quit = love.quit
local function upvalue(fn, name, replacement, write)
  for i = 1, 100 do
    local key, value = debug.getupvalue(fn, i)
    if not key then
      break
    end
    if key == name then
      if write then
        debug.setupvalue(fn, i, replacement)
      end
      return value, true
    end
  end
end
assert(launcher, "native host launcher callback was not installed")
local function set(name, value)
  local _, found = upvalue(quit, name, value, true)
  if not found then
    _, found = upvalue(launcher, name, value, true)
  end
  assert(found, "missing quit routing state: " .. name)
end
local counts = {}
local function count(name)
  return function()
    counts[name] = (counts[name] or 0) + 1
  end
end
set("walkerTick", count("walker"))
upvalue(launcher, "openLauncher", count("launcher"), true)
local Trace = require("src.core.BootTrace")
local oldFinish = Trace.finish
Trace.finish = count("trace")
local Save = require("src.core.SaveData")
local oldClose = Save.closeOpen
Save.closeOpen = count("saveMarkers")
local oldServices = {}
local services =
  { "src.core.DiscordPresence", "src.core.ChipAudio", "src.update.Check", "src.translation.Service" }
for _, name in ipairs(services) do
  oldServices[name] = package.loaded[name]
  package.loaded[name] = { shutdown = count(name) }
end
local function shutdowns(expected, label)
  for _, name in ipairs({ "walker", "trace", "saveMarkers", unpack(services) }) do
    T.eq(counts[name] or 0, expected, label .. ": " .. name)
  end
end
local function fresh(noMod)
  counts = {}
  local f = F.new(".", "red", 2, "native", noMod)
  set("Game", { mods = f.result.loader })
  set("Importer", nil)
  set("editorMode", false)
  return f
end
local bare = fresh(true)
T.eq(quit(), nil, "no-mod window close retains process exit")
T.eq(counts.launcher or 0, 0, "no-mod close does not open launcher")
shutdowns(1, "native exit")
bare.close()
for _, mode in ipairs({ "forward", "exit" }) do
  local f = fresh()
  f.exports.mode(mode)
  T.eq(quit(), nil, mode .. " permits native process exit")
  T.eq(f.exports.calls(), 1, mode .. " dispatches exactly once")
  T.eq(f.exports.cleanups(), 1, mode .. " runs consumer disposal")
  T.eq(counts.launcher or 0, 0, mode .. " does not open launcher")
  shutdowns(1, mode)
  f.close()
end
local f = fresh()
f.exports.mode("launcher")
T.eq(quit(), true, "mod launcher decision cancels LÖVE process exit")
T.eq(f.exports.calls(), 1, "launcher path dispatches exactly once")
T.eq(counts.launcher, 1, "actual native launcher-return function runs")
T.eq(Runtime.wantsHook("core.quit_to_launcher"), false, "native launcher return tears down mod buses")
T.check(Runtime.hooks ~= f.result.loader.hooks, "native teardown replaces the old hook bus")
T.eq(next(Runtime.hooks.chains), nil, "launcher starts with an empty live hook bus")
shutdowns(0, "launcher return retains process workers")
f.close()
for _, veto in ipairs({ true, false }) do
  f = fresh()
  set("editorMode", true)
  set("EditorApp", {
    quit = function()
      count("editor")()
      return veto
    end,
  })
  T.eq(quit(), veto and true or nil, "editor veto controls whether quit proceeds")
  T.eq(counts.editor, 1, "editor decision runs once")
  T.eq(f.exports.calls(), veto and 0 or 1, "accepted editor quit reaches hook; veto bypasses it")
  shutdowns(veto and 0 or 1, "editor exit")
  f.close()
end
f = fresh()
f.exports.mode("launcher")
set("editorMode", true)
set("EditorApp", {
  quit = function()
    return false
  end,
})
T.eq(quit(), true, "accepted editor quit may return to launcher")
T.eq(upvalue(quit, "editorMode"), false, "launcher return leaves editor routing")
T.eq(upvalue(quit, "EditorApp"), nil, "launcher return releases editor reference")
T.eq(counts.launcher, 1, "accepted editor opens launcher once")
shutdowns(0, "accepted editor launcher return")
f.close()
Trace.finish, Save.closeOpen = oldFinish, oldClose
for _, name in ipairs(services) do
  package.loaded[name] = oldServices[name]
end
T.finish("quit decision native routing")
