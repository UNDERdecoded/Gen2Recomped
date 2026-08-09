-- #254: the launcher's native file pickers must not open while a mouse button
-- is still held.  All three (ROM, mod .zip, .sav) block the LOVE loop in
-- io.popen straight out of mousepressed, so SDL never processes the button-up
-- and never drops its pointer capture; on X11 the chooser then draws but
-- ignores the mouse.  The X11 half needs a human on a Linux box; the fake
-- mouse here only stays down until pump() is called.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("launcher picker pointer grab")
local check, eq = S.check, S.eq

local RomImporter = require("src.import.RomImporter")

-- ---------------------------------------------------------------- the funnel
-- The release lives in commandOutput because all three pickers reach popen
-- through it; a fourth picker calling io.popen directly would bring #254 back.
do
  local f = io.open("src/import/RomImporter.lua", "rb")
  check(f ~= nil, "RomImporter source is readable")
  if f then
    local src = f:read("*a")
    f:close()
    local calls = 0
    for _ in src:gmatch("io%.popen%(") do calls = calls + 1 end
    eq(calls, 1, "every desktop picker still funnels through the one io.popen"
      .. " call, which is where the pointer grab is released (#254)")
  end
end

-- ---------------------------------------------------------------- instrumentation
-- The love stub is shared with every later suite in run_tests.lua, so the getOS
-- FIELD is saved as well as the table: restoring only the reference would hand
-- the next suite this file's Linux answer.
local saved = {
  mouse = love.mouse,
  event = love.event,
  timer = love.timer,
  system = love.system,
  getOS = love.system and love.system.getOS,
  popen = io.popen,
}

local W  -- the world one scenario runs in

-- releaseAfterPumps: how many pumps SDL needs before it reports the button
-- up.  math.huge models a physically stuck button.
local function newWorld(releaseAfterPumps)
  W = {
    held = true,          -- a button is down, the way it is during a click
    polls = 0,            -- love.mouse.isDown calls
    pumps = 0,            -- love.event.pump calls
    clock = 0,            -- fake monotonic seconds, advanced only by sleep
    popens = {},          -- one entry per picker launch
    releaseAfterPumps = releaseAfterPumps or 3,
    overran = false,
  }
end

love.mouse = {
  isDown = function()
    W.polls = W.polls + 1
    return W.held
  end,
}
love.event = {
  pump = function()
    W.pumps = W.pumps + 1
    -- SDL learns about the release here and nowhere else
    if W.pumps >= W.releaseAfterPumps then W.held = false end
    -- runaway guard: an unbounded wait would take the whole suite with it
    if W.pumps > 20000 then
      W.overran = true
      W.held = false
    end
  end,
}
love.timer = {
  getTime = function() return W.clock end,
  sleep = function(seconds) W.clock = W.clock + (seconds or 0) end,
}
love.system = love.system or {}
love.system.getOS = function() return "Linux" end

io.popen = function(command)
  W.popens[#W.popens + 1] = {
    command = command,
    heldAtLaunch = W.held,
    pumps = W.pumps,
    clock = W.clock,
  }
  -- an empty answer = the player cancelled, so nothing downstream runs
  return {
    read = function() return "" end,
    close = function() return true end,
  }
end

local function fakeImporter()
  return setmetatable({
    android = false,
    workState = nil,
    ready = { red = false, blue = false },
    chooseVersion = nil,
    saveNotice = {},
    startPath = function(self, path) self._startedPath = path end,
    setError = function(self, msg) self._error = msg end,
    _installMod = function(self, path) self._installed = path end,
    _importSave = function(self, version, path) self._imported = path end,
  }, RomImporter)
end

-- every picker launch in this scenario found the pointer already released
local function assertReleasedBeforeEveryPicker(label)
  check(#W.popens >= 1, label .. ": the picker actually opened")
  for i, call in ipairs(W.popens) do
    check(call.heldAtLaunch == false,
      ("%s: picker %d blocked in io.popen with no mouse button still held"
        .. " -- SDL got to drop its pointer capture first (#254)"):format(label, i))
  end
  check(W.pumps >= 1,
    label .. ": the event queue was pumped before blocking, which is what lets"
    .. " SDL see the button-up at all")
end

local function run()
  -- ---- a normal click: the release lands a few pumps in ------------------
  newWorld(3)
  local ri = fakeImporter()
  ri:choose("red")
  assertReleasedBeforeEveryPicker("ROM picker")
  eq(ri._error, nil, "a cancelled Linux pick reports no error")
  check(W.clock < 1,
    "the wait costs nothing a player can perceive on a normal click (waited "
    .. tostring(W.clock) .. "s)")

  -- ---- the same for the mod .zip picker ----------------------------------
  newWorld(2)
  ri = fakeImporter()
  ri:chooseMod()
  assertReleasedBeforeEveryPicker("mod .zip picker")

  -- ---- and the .sav picker ------------------------------------------------
  newWorld(2)
  ri = fakeImporter()
  ri:chooseSaveImport("red")
  assertReleasedBeforeEveryPicker(".sav picker")

  -- ---- a button that never comes up must not hang the launcher -----------
  newWorld(math.huge)
  ri = fakeImporter()
  ri:choose("red")
  check(#W.popens >= 1,
    "a stuck button still opens the picker rather than hanging the launcher")
  check(not W.overran, "the wait ends on its own instead of spinning forever")
  local previous = 0
  for i, call in ipairs(W.popens) do
    local waited = call.clock - previous
    previous = call.clock
    check(waited <= 1.05,
      ("picker %d waited %.3fs for a stuck button, bounded at one second")
        :format(i, waited))
  end

  -- ---- no mouse module at all (headless): the guard bails out ------------
  newWorld(3)
  local mouseModule = love.mouse
  love.mouse = nil
  ri = fakeImporter()
  local ok, err = pcall(function() ri:choose("red") end)
  love.mouse = mouseModule
  check(ok, "a build with no love.mouse still opens the picker instead of"
    .. " erroring (" .. tostring(err) .. ")")
  check(#W.popens >= 1, "and the picker still ran")
end

local ok, err = pcall(run)

love.mouse, love.event, love.timer = saved.mouse, saved.event, saved.timer
if love.system then love.system.getOS = saved.getOS end
love.system = saved.system
io.popen = saved.popen

if not ok then check(false, "suite raised: " .. tostring(err)) end

S.finish()
