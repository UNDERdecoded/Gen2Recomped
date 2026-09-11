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
-- The release lives in commandOutput because all three pickers reach the shell
-- through it; a fourth picker spawning a process of its own would bring #254
-- back.
--
-- THE POPEN ITSELF HAS MOVED.  It is HostShell.popen now -- one wrapper that
-- applies the AppImage environment fix and swallows the platforms where
-- io.popen raises rather than returning nil -- and RomImporter calls no shell
-- of its own at all.  This check used to count `io.popen(` in RomImporter and
-- demand exactly one; after the move that count is ZERO, and the check failed
-- while the invariant it exists to protect was in better shape than ever.  So
-- it is stated where it now lives: RomImporter opens no process directly,
-- every picker goes through commandOutput, commandOutput releases the grab
-- before it blocks, and the whole engine reaches io.popen through the single
-- call inside HostShell.
local function readSource(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local src = f:read("*a")
  f:close()
  return src
end

do
  local src = readSource("src/import/RomImporter.lua")
  check(src ~= nil, "RomImporter source is readable")
  if src then
    local direct = 0
    for _ in src:gmatch("io%.popen%(") do direct = direct + 1 end
    eq(direct, 0, "RomImporter spawns no process of its own -- a picker with "
      .. "its own popen would be the one that skips the release (#254)")

    -- ...and the ONE seam it does use is the one that releases the grab
    local funnel = 0
    for _ in src:gmatch("HostShell%.popen%(") do funnel = funnel + 1 end
    eq(funnel, 1, "and reaches the shell through exactly one call, which is "
      .. "commandOutput's")
    check(src:find("releasePointerGrab()", 1, true) ~= nil,
      "which releases the pointer grab before it blocks")

    -- every native picker really does route through commandOutput rather
    -- than round it -- the ROM, the mod .zip, the .sav and the by-extension
    -- one the map editor opens
    local through = 0
    for _ in src:gmatch("commandOutput%(") do through = through + 1 end
    check(through >= 4, ("%d picker paths go through it"):format(through))
  end
end

do
  local host = readSource("src/core/HostShell.lua")
  check(host ~= nil, "HostShell source is readable")
  if host then
    -- the punctuation is the point: `io.popen(` or `io.popen,` is a CALL,
    -- and the prose above it in that file mentions the name twice
    local calls = 0
    for _ in host:gmatch("io%.popen[,(]") do calls = calls + 1 end
    eq(calls, 1, "and the whole engine holds exactly one io.popen, in "
      .. "HostShell -- which is what makes 'every picker funnels through "
      .. "commandOutput' a statement about all of them")
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
