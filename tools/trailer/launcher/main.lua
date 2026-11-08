-- tools/trailer/launcher/main.lua -- TRAILER FOOTAGE of the launcher:
--
--   launcher_games   the Games section: the consoles, the Nintendo DS list
--                    (Platinum, HeartGold, SoulSilver, Black, White), then
--                    HeartGold's own page
--   walker_screen    the Monster Walker: a Pokemon out on a course, today's
--                    steps and the watts counting up, then a Poke Radar
--                    battle that ends in a catch
--
-- Built the way tools/launcher_shot builds the launcher; frames stream into
-- <OUT>/<shot>.mp4 through tools/trailer/recorder.lua. Run from the repo root
-- with the save folder on a scratch drive (APPDATA) and DATA = a game-data
-- folder holding the imported games (the scratch one capture_all.ps1
-- -Identity trailer2_cap -ImportRom fills):
--
--   $env:APPDATA = "G:\Gen2Recomped\scratch_claude\trailer2\appdata"
--   $env:DATA = "G:/Gen2Recomped/scratch_claude/trailer2/data"
--   $env:OUT = "G:/Gen2Recomped/trailer_footage"
--   $env:FFMPEG = "G:/Tools/ffmpeg-9.0.2-essentials_build/bin/ffmpeg.exe"
--   & "C:\Program Files\LOVE\love.exe" tools/trailer/launcher
--
-- ONLY=launcher_games|walker_screen picks one. The update check, the news
-- feed, box-art scraping and every curl are stubbed: nothing leaves this
-- machine, and the run refuses a save folder outside scratch_claude.
function love.errorhandler(msg)
  print("LAUNCHER ERROR: " .. tostring(msg))
  print(debug.traceback())
  io.stdout:flush()
  os.exit(1)
end
io.stdout:setvbuf("line")

local ROOT = (os.getenv("ROOT") or love.filesystem.getWorkingDirectory()):gsub("\\", "/")
do
  local ffi = require("ffi")
  pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
  for _, lib in ipairs({ function() return ffi.C end, function() return ffi.load("love") end }) do
    local ok, l = pcall(lib)
    if ok and l then
      local okf, fn = pcall(function() return l.PHYSFS_mount end)
      if okf and fn and fn(ROOT, "", 1) ~= 0 then break end
    end
  end
end

-- never the player's saves
do
  local sd = love.filesystem.getSaveDirectory():gsub("\\", "/")
  if not sd:find("scratch_claude", 1, true) then
    print("REFUSING: save dir is not under scratch_claude: " .. sd)
    os.exit(2)
  end
end

love.system.openURL = function() return true end
-- no external hosts
do
  local HS = require("src.core.HostShell")
  HS.canFetch = function() return false end
  HS.httpGet = function() error("offline trailer harness") end
  local okC, Check = pcall(require, "src.update.Check")
  if okC and type(Check) == "table" then Check.start = function() end end
  local popen = io.popen
  io.popen = function(cmd, ...)
    local c = tostring(cmd)
    if c:find("curl", 1, true) or c:find("http", 1, true) or c:find("wget", 1, true) then
      return nil, "blocked"
    end
    return popen(cmd, ...)
  end
  local okS, Sidebar = pcall(require, "src.import.LauncherSidebar")
  if okS and type(Sidebar) == "table" then Sidebar.fetchNews = function() return nil end end
end

-- the scratch identity's options: the game-data folder with the imports
do
  local SaveData = require("src.core.SaveData")
  local opts = SaveData.loadOptions() or {}
  if os.getenv("DATA") and opts.dataDir ~= os.getenv("DATA") then
    opts.dataDir = os.getenv("DATA")
    SaveData.saveOptions(opts)
  end
end

local Importer, Rec
local co
local ONLY = os.getenv("ONLY") or ""

local function wait(n) for _ = 1, n do coroutine.yield() end end

local function gamesShot()
  Importer:_sbGo("games")
  wait(20)
  Rec.start("launcher_games")
  wait(75)
  Importer.browseConsole, Importer.gamesView, Importer.pageScroll = "nds", "series", 0
  wait(60)
  Importer.browseSeries, Importer.gamesView, Importer.pageScroll = "pokemon", "list", 0
  wait(150)
  Importer:_sbOpenGame("heartgold")
  wait(150)
  Rec.stop()
end

local function walkerShot()
  local Wk = require("src.pokewalker.Walker")
  local Art = require("src.pokewalker.WalkerArt")
  if os.getenv("DATA") then Art._roots = { os.getenv("DATA") } end
  Wk.save = function() end                    -- in memory only
  Importer:_sbGo("walker")
  local P = Importer.walker
  local st = Wk.newState()
  local day = math.floor(os.time() / 86400)
  st.watts, st.lifetimeWatts, st.lifetimeSteps, st.days = 342, 2400, 48000, 9
  st.history = { { day = day, steps = 6420 }, { day = day - 1, steps = 9000 }, { day = day - 2, steps = 4000 } }
  st.course = tonumber(os.getenv("WALKER_COURSE") or "15")
  st.caught, st.items, st.finds = {}, {}, {}
  st.walking = { species = 25, name = "PIKACHU", level = 14, types = { "ELECTRIC" },
    friendship = 120, steps = 3200, friendSteps = 0, encounters = {},
    source = { version = "heartgold", slot = "slot1", box = 1, index = 1 } }
  P.st = st
  wait(30)
  Rec.start("walker_screen")
  -- a walk: the steps tick over, a watt every twenty
  for f = 1, 150 do
    if f % 3 == 0 then
      st.history[1].steps = st.history[1].steps + 1
      if st.history[1].steps % 20 == 0 then st.watts = st.watts + 1 end
    end
    coroutine.yield()
  end
  -- the Poke Radar's battle: a wild Hoothoot, two turns, then the ball. The
  -- turns are the Walker's own (Walker.battleTurn); the seed is picked so
  -- this take ends in a catch.
  local enc = { group = "B", species = 163, name = "HOOTHOOT", level = 9, radar = true }
  local plan = { "attack", "attack", "catch" }
  local seed
  for s = 1, 500 do
    love.math.setRandomSeed(s)
    local probe = { watts = 10, caught = {}, items = {}, log = {}, notices = {}, history = st.history }
    local b = Wk.newBattle(enc)
    for _, a in ipairs(plan) do pcall(Wk.battleTurn, probe, b, a) end
    if b.over == "caught" and b.me >= 3 then seed = s break end
  end
  love.math.setRandomSeed(seed or 1)
  -- the radar's bushes first, one of them rustling
  P.tab = "radar"
  P.radar = { bush = 2, timer = 1e9, marks = 2, encounter = enc }
  wait(60)
  P.radar = nil
  local b = Wk.newBattle(enc)
  b.text = ("A wild %s appeared!"):format(enc.name)
  P.battle = b
  wait(70)
  for _, a in ipairs(plan) do
    local _, text = Wk.battleTurn(st, b, a)
    b.text = text
    wait(a == "catch" and 110 or 60)
  end
  Rec.stop()
end

function love.load()
  Rec = dofile("tools/trailer/recorder.lua")({
    out = assert(os.getenv("OUT"), "OUT"), ffmpeg = os.getenv("FFMPEG") or "ffmpeg",
    crf = os.getenv("CRF") or "14", guard = false })
  local RomImporter = require("src.import.RomImporter")
  Importer = RomImporter.new(function() end, { launcher = true,
    onEditSave = function() end, onEditMaps = function() end, onEditTouchControls = function() end })
  co = coroutine.create(function()
    wait(30)
    if ONLY == "" or ONLY == "launcher_games" then gamesShot() end
    if ONLY == "" or ONLY == "walker_screen" then walkerShot() end
  end)
end

function love.update()
  Importer:update(1 / 60)
  if co and coroutine.status(co) ~= "dead" then
    local ok, err = coroutine.resume(co)
    if not ok then print("DRIVER ERROR " .. tostring(err)); os.exit(1) end
  elseif co then
    co = nil
    Rec.finish()
    print("[driver] done")
    love.event.quit()
  end
  Rec.frame()
end

function love.draw()
  Importer:draw()
end

function love.textinput(t) Importer:textinput(t) end
