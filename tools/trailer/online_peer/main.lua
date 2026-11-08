-- tools/trailer/online_peer/main.lua -- one "other player" for the online
-- trailer shots. The recording client is the real game running
-- tools/trailer/capture_online.lua; these are the friends around it: plain
-- LOVE processes on 127.0.0.1 with a game booted headless (no drawing),
-- driven by a small script per shot. Started by capture_online.py.
--
-- Env: SHOT (world|room|trade|battle|gts|multi), PEER_NAME, PEER_IDX (1..3),
--      RUN (the shot's run folder: flags, saves), INSTALL, VERSION,
--      MAXT (tick limit, default 60*240).
--
-- Talks to the recorder through flag files in RUN:
--   recorder writes  spot ("MAP X Y"), code (world code), go, stop,
--                    multi_invite.json (multi)
--   peer writes      <name>_in, <name>_done
-- Never shows an error window: love.errorhandler prints and exits 1.
local REPO = (os.getenv("REPO") or "G:/Github Desktop/0.7.0/Gen2Recomped"):gsub("\\", "/") .. "/"
package.path = REPO .. "?.lua;" .. REPO .. "?/init.lua;" .. package.path
io.stdout:setvbuf("line")

function love.errorhandler(msg)
  print("PEER ERROR: " .. tostring(msg))
  print(debug.traceback())
  os.exit(1)
end
love.errhand = love.errorhandler

local SHOT = os.getenv("SHOT") or "world"
local NAME = os.getenv("PEER_NAME") or "ALICE"
local IDX = tonumber(os.getenv("PEER_IDX") or "1") or 1
local RUN = assert(os.getenv("RUN"), "RUN"):gsub("\\", "/") .. "/"
local INSTALL = assert(os.getenv("INSTALL"), "INSTALL")
local VERSION = os.getenv("VERSION") or "platinum"
local MAXT = tonumber(os.getenv("MAXT") or "") or 60 * 240

local function log(fmt, ...) print(("[peer %s] " .. fmt):format(NAME, ...)) end

-- PhysFS: the install at the root (the Gen 4 ground opens its chunks through
-- love.filesystem), every write into the run folder
local ffi = require("ffi")
pcall(ffi.cdef, [[
int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);
int PHYSFS_setWriteDir(const char *newDir);
]])
local PFS
for _, lib in ipairs({ function() return ffi.C end, function() return ffi.load("love") end }) do
  local ok, l = pcall(lib)
  if ok and l and pcall(function() return l.PHYSFS_mount end) then PFS = l break end
end
local saveDir = RUN .. "save_" .. NAME
os.execute(('mkdir "%s" 2>nul'):format(saveDir:gsub("/", "\\")))
assert(PFS and PFS.PHYSFS_mount(INSTALL, "", 1) ~= 0, "mount install")
assert(PFS.PHYSFS_mount(REPO, "", 1) ~= 0, "mount repo")
assert(PFS.PHYSFS_setWriteDir(saveDir) ~= 0, "set write dir")
assert(PFS.PHYSFS_mount(saveDir, "", 0) ~= 0, "mount save dir")
love.filesystem.getSaveDirectory = function() return saveDir end

local env = { POKEPORT_DATA_DIR = INSTALL .. "/data/generated", POKEPORT_ASSET_ROOT = INSTALL }
local getenv = os.getenv
os.getenv = function(k) return env[k] or getenv(k) end

local function flagPath(name) return RUN .. name end
local function mark(name, text)
  local tmp = flagPath(name) .. ".tmp"
  local f = assert(io.open(tmp, "w")) f:write(text or "1") f:close()
  os.remove(flagPath(name))
  os.rename(tmp, flagPath(name))
end
local function readFlag(name)
  local f = io.open(flagPath(name), "r")
  if not f then return nil end
  local s = f:read("*a") f:close()
  return s
end

local Game, OnlineWorld, Data
local held, pressed = nil, {}
local tick = 0
local script

-- ------------------------------------------------------------ boot

local Pokemon
local function speciesId(name)
  for id, def in pairs(Data.pokemon or {}) do
    if type(def) == "table" and type(def.name) == "string" and def.name:upper() == name then return id end
  end
  return nil
end
local function makeParty(list, level)
  local party = {}
  for _, sp in ipairs(list) do
    local id = type(sp) == "number" and sp or speciesId(sp)
    if id then
      local m = Pokemon.new(Data, id, level)
      party[#party + 1] = m
    else
      log("no species %s", tostring(sp))
    end
  end
  return party
end

local PARTIES = {
  ALICE = { "LUCARIO", "TOGEKISS", "ROSERADE" },
  BOB = { "GARCHOMP", "STARAPTOR", "GYARADOS" },
  CAROL = { "PACHIRISU", "GLACEON", "MAMOSWINE" },
}
local BW_PARTIES = {
  ALICE = { "ZOROARK", "SCOLIPEDE", "CHANDELURE" },
  BOB = { "HAXORUS", "EXCADRILL", "BRAVIARY" },
  CAROL = { "VOLCARONA", "GALVANTULA", "HYDREIGON" },
}

local function boot()
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(VERSION)
  local Assets = require("src.render.Assets")
  local realImage, heldImg = Assets.image, {}
  Assets.image = function(path, ...)
    if type(path) == "string" and not heldImg[path] then
      local f = io.open(INSTALL .. "/" .. path, "rb")
      if f then
        local bytes = f:read("*a"); f:close()
        local okI, img = pcall(love.graphics.newImage, love.filesystem.newFileData(bytes, path))
        if okI then img:setFilter("nearest", "nearest"); heldImg[path] = img end
      end
    end
    return heldImg[path] or realImage(path, ...)
  end
  Data = require("src.core.Data")
  Data:load()
  local SaveData = require("src.core.SaveData")
  Game = require("src.core.Game")
  Game.data = Data
  local ModLoader = require("src.mods.Loader")
  Game.mods = ModLoader.new()
  Game.mods:load(Data)
  Game.modStatus = Game.mods:status()
  require("src.render.Pipelines").install(Data)
  local Renderer = require("src.render.Renderer")
  Game.renderer = Renderer
  Renderer:init()
  require("src.render.Font").load(Data)
  require("src.ui.Theme").load(Data)
  require("src.core.Strings").load(Data)
  local StateStack = require("src.core.StateStack")
  StateStack:init()
  Game.stack = StateStack
  Game.save = SaveData.newGame(Game.bootConfig and Game:bootConfig() or {})
  if Game.adoptSave then pcall(Game.adoptSave, Game, Game.save, true) end
  Game.writeSave = function() end
  Game.writeOptions = function() end
  Game.save.player.name = NAME
  Game.save.player.id = 20000 + IDX * 1111
  Game.save.player.gender = (NAME == "BOB") and "boy" or "girl"
  Game.save.options = Game.save.options or {}
  Game.save.options.online = { portMap = false, stun = false, lanBeacon = false, allowRelay = false,
                               bind = "127.0.0.1", lanIp = "127.0.0.1", port = 0,
                               timeouts = { lan = 4 } }
  Pokemon = require("src.pokemon.Pokemon")
  local bw = VERSION == "black" or VERSION == "white"
  Game.save.party = makeParty((bw and BW_PARTIES or PARTIES)[NAME] or { "PIKACHU" }, 50)
  Game.input = {
    wasPressed = function(_, k) return pressed[k] == true end,
    isDown = function(_, k) return held ~= nil and k == held end,
    wasReleased = function() return false end,
    keypressed = function() end,
    step = function() end,
    pressQueue = {}, state = {},
  }
  OnlineWorld = require("src.online.world.OnlineWorld")
  log("booted %s", VERSION)
end

-- ------------------------------------------------------------ helpers

local function yield() coroutine.yield() end
local function wait(n) for _ = 1, n do yield() end end
local function waitUntil(fn, n, what)
  for _ = 1, n or 1800 do
    if fn() then return true end
    yield()
  end
  error("timed out waiting for " .. tostring(what))
end
local function press(k) pressed[k] = true yield() end
local function player() return Game.overworld and Game.overworld.player end
local function top() return Game.stack:top() end
local function stopped() return readFlag("stop") ~= nil end

local function step(dir)
  local p = player()
  local x0, y0 = p.cellX, p.cellY
  held = dir
  local moved = false
  for _ = 1, 40 do
    yield()
    local q = player()
    if q.cellX ~= x0 or q.cellY ~= y0 or q.moving then moved = true break end
  end
  held = nil
  for _ = 1, 60 do if not player().moving then break end yield() end
  return moved
end

local function face(dir)
  if player().facing == dir then return end
  held = dir
  wait(2)
  held = nil
  wait(6)
end

local function client() return OnlineWorld.client() end

local function bootMap()
  local spot
  waitUntil(function() spot = readFlag("spot") return spot ~= nil end, 60 * 120, "spot")
  local map, sx, sy = spot:match("^(%S+)%s+(%-?%d+)%s+(%-?%d+)")
  sx, sy = tonumber(sx), tonumber(sy)
  local OW = require("src.world.OverworldController")
  local offs = readFlag("offsets")
  local ox, oy, f = 0, 0, "down"
  if offs then
    for line in offs:gmatch("[^\n]+") do
      local n, a, b, fc = line:match("^(%S+)%s+(%-?%d+)%s+(%-?%d+)%s*(%a*)")
      if n == NAME then ox, oy, f = tonumber(a), tonumber(b), (fc ~= "" and fc or "down") end
    end
  end
  Game.stack:push(OW, map, sx + ox, sy + oy, f)
  log("on %s at (%d,%d)", map, sx + ox, sy + oy)
  return map, sx, sy
end

local function joinWorld()
  local code
  waitUntil(function() code = readFlag("code") return code ~= nil end, 60 * 120, "code")
  local s, why = OnlineWorld.joinWorld(Game, code)
  assert(s, why)
  waitUntil(function() local c = client() return c and c.state == "in" end, 60 * 30, "welcome")
  log("in the world as pid %s", tostring(client().you))
  mark(NAME .. "_in")
end

-- a bot for the link screens and battles: A every few frames, a damaging
-- move in a battle's move menu
local function battleBot(b)
  if b.phase == "menu" then
    b.menuIndex = 1
    pressed.a = true
  elseif b.phase == "moveSelect" then
    local who = b.menuBattler and b:menuBattler()
    if who and who.curMoves then
      local ok = {}
      for i, mv in ipairs(who.curMoves) do
        local d = Data.moves[mv.id]
        if (mv.pp or 0) > 0 and d and (d.power or 0) > 0 then ok[#ok + 1] = i end
      end
      if #ok > 0 then b.moveIndex = ok[math.random(#ok)] end
    end
    pressed.a = true
  elseif b.phase ~= "waitRemote" then
    pressed.a = true
  end
end

local function findBattle()
  local states = Game.stack.states or {}
  for i = #states, 1, -1 do
    local st = states[i]
    if type(st) == "table" and st.phase and st.activeBattlers then return st end
  end
  return nil
end

-- ------------------------------------------------------------ scripts

-- WORLD / ROOM: wander in a lane next to the recorder, chat and emote on a
-- timeline the recorder starts with the "go" flag
local LINES = {
  world = {
    ALICE = { { 40, "say", "Hi all!" }, { 230, "emote", "!" }, { 400, "say", "Race you!" } },
    BOB = { { 120, "emote", "heart" }, { 190, "say", "Battle?" }, { 470, "emote", "note" } },
    CAROL = { { 20, "emote", "note" }, { 300, "say", "Nice hat!" } },
  },
  room = {
    ALICE = { { 50, "say", "Hey!" }, { 330, "emote", "!" } },
    BOB = { { 140, "emote", "heart" }, { 230, "say", "Trade?" } },
    CAROL = { { 30, "emote", "note" }, { 380, "say", "GG!" } },
  },
}

local function wanderScript()
  boot()
  local map, sx, sy = bootMap()
  joinWorld()
  waitUntil(function() return readFlag("go") end, 60 * 120, "go")
  local lane = readFlag("lanes")
  local box = { x0 = sx - 3, x1 = sx + 3, y0 = sy - 2, y1 = sy + 2 }
  if lane then
    for line in lane:gmatch("[^\n]+") do
      local n, a, b, c, d = line:match("^(%S+)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)")
      if n == NAME then box = { x0 = sx + tonumber(a), x1 = sx + tonumber(b), y0 = sy + tonumber(c), y1 = sy + tonumber(d) } end
    end
  end
  math.randomseed(1000 + IDX * 77)
  local events = (LINES[SHOT] or LINES.world)[NAME] or {}
  local t0 = tick
  local ei = 1
  local nextMove = tick + 10 + IDX * 13
  local lastDir
  while not stopped() do
    local t = tick - t0
    while events[ei] and t >= events[ei][1] do
      local e = events[ei]
      if e[2] == "say" then client():say(e[3]) else client():emote(e[3]) end
      log("%s %s at %d", e[2], e[3], t)
      ei = ei + 1
    end
    if tick >= nextMove then
      local p = player()
      local dirs = {}
      if p.cellX > box.x0 then dirs[#dirs + 1] = "left" end
      if p.cellX < box.x1 then dirs[#dirs + 1] = "right" end
      if p.cellY > box.y0 then dirs[#dirs + 1] = "up" end
      if p.cellY < box.y1 then dirs[#dirs + 1] = "down" end
      -- keep going the same way now and then: it reads as walking somewhere
      local dir = dirs[math.random(#dirs)]
      if lastDir and math.random() < 0.5 then
        for _, d in ipairs(dirs) do if d == lastDir then dir = d end end
      end
      local n = math.random(1, 2)
      for _ = 1, n do
        if not step(dir) then break end
      end
      lastDir = dir
      if math.random() < 0.3 then face(({ "down", "left", "right" })[math.random(3)]) end
      nextMove = tick + math.random(20, 70)
    end
    yield()
  end
  mark(NAME .. "_done")
  OnlineWorld.leave()
end

-- TRADE / BATTLE: stand next to the recorder and take its invite; then the
-- link screens and the battle by bot
local function linkScript()
  boot()
  bootMap()
  joinWorld()
  local accepted = false
  local battleSeen = false
  while not stopped() do
    local c = client()
    if c and not accepted then
      for iid in pairs(c.incoming or {}) do
        c:answer(iid, true)
        accepted = true
        log("accepted invite %s", tostring(iid))
        -- drop the invite window if one came up
        local t = top()
        if t and t.kind == "invite" then Game.stack:pop() end
        break
      end
    end
    local b = findBattle()
    if b and top() == b and tick % 3 == 0 then battleSeen = true battleBot(b)
    elseif b and b.linkPickReplacement and b.linkRoundOpen and tick % 30 == 0 then
      for i = 1, #Game.save.party do
        local m = Game.save.party[i]
        if m.hp > 0 then b.linkPickReplacement(m) break end
      end
    elseif top() ~= Game.overworld and tick % 14 == 0 then
      pressed.a = true
    end
    yield()
  end
  log("battle seen %s", tostring(battleSeen))
  mark(NAME .. "_done")
  OnlineWorld.leave()
end

-- GTS: deposit one Pokemon on the world GTS (a GtsClient over the world's
-- service channel), so the recorder's search finds friends' offers
local function gtsScript()
  boot()
  bootMap()
  joinWorld()
  local GtsClient = require("src.online.gts.GtsClient")
  local gc = GtsClient.new({ channel = OnlineWorld.gtsChannel(), data = Game.data, save = Game.save,
                             persist = function() return true end, name = NAME,
                             player = GtsClient.identity(), game = VERSION, tid = Game.save.player.id })
  waitUntil(function() gc:update(1 / 60) return gc.state == "ready" end, 60 * 20, "gts ready")
  local GtsRules = require("src.online.gts.GtsRules")
  local wantName = ({ ALICE = "PIPLUP", BOB = "TURTWIG", CAROL = "CHIMCHAR" })[NAME] or "PIPLUP"
  local key = speciesId(wantName)
  local dex = GtsRules.dexOf(Data, key)
  Game.save.pokedex = Game.save.pokedex or {}
  Game.save.pokedex.seen = Game.save.pokedex.seen or {}
  Game.save.pokedex.seen[key] = true
  local pool = gc:poolInfo()
  local g = GtsRules.genderOptions(Data, dex, pool and pool.gen)[1]
  local result
  local okD, err = pcall(function()
    gc:deposit({ where = "party", index = 1 }, { dex = dex, gender = g, band = 0 },
      function(ok, reply) result = ok and "ok" or ("fail " .. tostring(reply and reply.text)) end)
  end)
  if not okD then log("deposit call failed: %s", tostring(err)) end
  for _ = 1, 60 * 10 do
    gc:update(1 / 60)
    if result then break end
    yield()
  end
  log("deposit %s (want dex %s)", tostring(result), tostring(dex))
  mark(NAME .. "_in_gts")
  while not stopped() do gc:update(1 / 60) yield() end
  gc:close()
  mark(NAME .. "_done")
  OnlineWorld.leave()
end

-- MULTI: the fourproc join bot (tools: scratch online/multi/fourproc)
local function multiScript()
  boot()
  local Json = require("src.link.Json")
  local InviteCode = require("src.online.InviteCode")
  local MultiBattle = require("src.online.MultiBattle")
  local Input = require("src.core.Input")
  Input:init()
  Game.input = Input
  MultiBattle.defaults = {
    autoTeam = true, autoStart = true,
    connector = { port = 0, bind = "127.0.0.1", portMap = false, lanIp = "127.0.0.1", lanBeacon = false, stun = false },
    joinOptions = { timeouts = { lan = 3 } },
  }
  local battles = {}
  MultiBattle.defaults.onBattle = function(b) battles[#battles + 1] = b end
  local inv
  waitUntil(function()
    local s = readFlag("multi_invite.json")
    if s then inv = Json.decode(s) end
    return inv ~= nil
  end, 60 * 120, "multi invite")
  local invite = assert(InviteCode.decode(inv.code, "127.0.0.1"))
  local result
  MultiBattle.open(Game, { role = "join", invite = invite }, { role = "join" },
    function(r, why) result = r log("lobby done %s %s", tostring(r), tostring(why)) end)
  mark(NAME .. "_in")
  math.randomseed(100 + IDX)
  local frame = 0
  while result == nil and not stopped() do
    frame = frame + 1
    Input.pressed = {}
    local t = Game.stack:top()
    local b = battles[#battles]
    if b and frame % 2 == 0 and b.linkRoundOpen and b.linkPickReplacement and t ~= b then
      if frame % 40 == 0 then
        local taken = {}
        for _, x in b:activeBattlers() do if x and x.mon and x.mon.hp > 0 then taken[x.mon] = true end end
        for i = #Game.save.party, 1, -1 do
          local m = Game.save.party[i]
          if m.hp > 0 and not taken[m] then b.linkPickReplacement(m) break end
        end
      end
    elseif b and t == b and frame % 2 == 0 then
      if b.phase == "menu" then b.menuIndex = 1 Input.pressed.a = true
      elseif b.phase == "targetSelect" then Input.pressed.a = true
      elseif b.phase == "moveSelect" then
        local who = b:menuBattler()
        local ok = {}
        for i, mv in ipairs(who.curMoves) do
          local d = Data.moves[mv.id]
          if (mv.pp or 0) > 0 and d and (d.power or 0) > 0 then ok[#ok + 1] = i end
        end
        if #ok > 0 then b.moveIndex = ok[math.random(#ok)] end
        Input.pressed.a = true
      elseif b.phase ~= "waitRemote" then Input.pressed.a = true end
    elseif frame % 2 == 0 and t and t.stage ~= "gather" then
      Input.pressed.a = true
    end
    Game.stack:update(1 / 60)
    coroutine.yield("noupdate")
  end
  mark(NAME .. "_done")
end

-- ------------------------------------------------------------ loop

function love.load()
  local fn = (SHOT == "world" or SHOT == "room") and wanderScript
    or ((SHOT == "trade" or SHOT == "battle") and linkScript)
    or (SHOT == "gts" and gtsScript) or (SHOT == "multi" and multiScript)
  assert(fn, "unknown SHOT " .. tostring(SHOT))
  script = coroutine.create(fn)
end

local clockBase
local function readClock()
  local fh = io.open(RUN .. "clock", "r")
  if not fh then return nil end
  local v = tonumber(fh:read("*a") or "")
  fh:close()
  return v
end
local last = love.timer.getTime()
function love.update()
  tick = tick + 1
  local skipUpdate = false
  if script and coroutine.status(script) ~= "dead" then
    local ok, res = coroutine.resume(script)
    if not ok then
      print("PEER ERROR: " .. tostring(res))
      print(debug.traceback(script))
      os.exit(1)
    end
    skipUpdate = res == "noupdate"
  end
  if Game and Game.stack and not skipUpdate then
    local okU, errU = xpcall(function()
      Game.stack:update(1 / 60)
      if OnlineWorld then OnlineWorld.tick(1 / 60) end
    end, debug.traceback)
    if not okU then print("PEER ERROR (update): " .. tostring(errU)) os.exit(1) end
  end
  pressed = {}
  if script and coroutine.status(script) == "dead" then
    log("done")
    os.exit(0)
  end
  if tick > MAXT then log("tick limit") os.exit(3) end
  -- LOCKSTEP WITH THE RECORDER: it renders 1080p and captures, so it runs
  -- slower than the wall; a peer never gets ahead of its frame count
  -- (RUN/clock), so in the footage everyone walks at the same speed
  if not clockBase then
    local rc = readClock()
    if rc then clockBase = rc - tick end
  end
  if clockBase then
    for _ = 1, 500 do
      local rc = readClock()
      if not rc or tick + clockBase <= rc + 1 then break end
      love.timer.sleep(0.002)
    end
  end
  -- real-time pacing: the world runs on the wall clock
  local now = love.timer.getTime()
  local spare = 1 / (tonumber(os.getenv("PEER_FPS") or "") or 60) - (now - last)
  if spare > 0 then love.timer.sleep(spare) end
  last = love.timer.getTime()
end

function love.draw() end
