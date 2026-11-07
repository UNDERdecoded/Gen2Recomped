-- The Xbox ROM picker's Lua side, driven with stub hosts and real files in a
-- temp folder. Run: python tools/run_lua_check.py tools/xbox_picker_check.lua
package.path = "./?.lua;" .. package.path

local fails, checks = 0, 0
local function ok(c, what)
  checks = checks + 1
  if not c then
    fails = fails + 1
    print("FAIL: " .. what)
  end
end

local tmp = os.tmpname()
os.remove(tmp)
local root = tmp .. "_xboxpicker"
os.execute(('mkdir "%s" 2>NUL'):format(root:gsub("/", "\\")))

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local function write(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

local dllPicks = {}
local function host(osName)
  package.loaded["src.import.XboxPicker"] = nil
  dllPicks = {}
  _G.love = {
    system = {
      getOS = function() return osName end,
      pickFile = function(kind) dllPicks[#dllPicks + 1] = tostring(kind); return true end,
      getPickedFile = function() return nil end,
      getPickError = function() return nil end,
    },
    filesystem = { getSaveDirectory = function() return root .. "/pokemon-love2d" end },
  }
  return require("src.import.XboxPicker")
end

os.remove(root .. "/gr_picker_ready")
ok(host("Android").install() == false, "another OS was given the Xbox picker")
ok(host("UWP").install() == false, "a package with no gr_picker_ready was given the new picker")
love.system.pickFile("rom")
ok(dllPicks[1] == "rom", "an older package no longer reaches the love.dll picker")

write(root .. "/gr_picker_ready", "1\n")
write(root .. "/gr_pick_result", "Pstale\n")
local X = host("UWP")
ok(X.install() == true, "a package with gr_picker_ready did not get the new picker")
ok(read(root .. "/gr_pick_result") == nil, "a result left by the last run survived startup")
ok(love.system.getPickedFile() == nil, "a pick was reported before one was asked for")

ok(love.system.pickFile("rom") == true, "pickFile refused")
ok(read(root .. "/gr_pick_request") ~= nil, "no request file was written")
ok(#dllPicks == 0, "a ROM pick still went to the love.dll picker")
os.remove(root .. "/gr_pick_request")

ok(love.system.getPickedFile() == nil, "a pick was reported with no result yet")
write(root .. "/gr_pick_result", "PC:\\x\\picked_rom")
ok(love.system.getPickedFile() == nil, "a half-written result was read")
write(root .. "/gr_pick_result", "PC:\\x\\picked_rom.nds\n")
ok(love.system.getPickedFile() == "C:\\x\\picked_rom.nds", "the chosen path did not come through")
ok(read(root .. "/gr_pick_result") == nil, "the result file was not consumed")

love.system.pickFile()
os.remove(root .. "/gr_pick_request")
write(root .. "/gr_pick_result", "C\n")
ok(love.system.getPickedFile() == nil and love.system.getPickError() == nil,
   "a cancel was not a quiet nothing")

love.system.pickFile("rom")
os.remove(root .. "/gr_pick_request")
write(root .. "/gr_pick_result", "Enope\n")
ok(love.system.getPickedFile() == nil, "an error came through as a path")
ok(love.system.getPickError() == "nope", "the error message was lost")
ok(love.system.getPickError() == nil, "the error was reported twice")

ok(love.system.pickFile("mod") == true and dllPicks[1] == "mod", "a mod pick left the love.dll picker")
ok(love.system.pickFile("sav") == true and dllPicks[2] == "sav", "a save pick left the love.dll picker")
ok(read(root .. "/gr_pick_request") == nil, "a mod or save pick asked for the ROM picker")

os.remove(root .. "/gr_picker_ready")
os.execute(('rmdir "%s" 2>NUL'):format(root:gsub("/", "\\")))
print(("%d checks, %d failed"):format(checks, fails))
if fails > 0 then error("xbox picker check failed") end
