-- tools/gen4_field_sweep_harness/main.lua
--
-- A deterministic, headless SWEEP of the Gen 4 overworld: for every map in the
-- imported cache it enters the map the way a warp does, then walks it, takes
-- its warps, talks to its people and reads its signs -- and, once per run, opens
-- every start-menu screen and the Pokétch's apps -- catching Lua errors with a
-- traceback, logged errors, and softlocks (input that never comes back, a
-- script parked on one row, a screen that B does not close).
--
-- Run it through the version wrapper so the cache is mounted (see
-- tools/gen4_field_sweep.py for the batching driver, which restarts after a hard
-- crash and merges the per-batch reports):
--
--   POKEPORT_IDENTITY=pl_field INSTALL=<cache>/platinum VERSION=platinum \
--   HARNESS=gen4_field_sweep_harness MAPS=T01,R201 \
--     lovec tools/gen4_hgss_overworld_harness
--
-- Environment (all optional):
--   MAPS=T01,R201|all     which maps (default all, in sorted order)
--   MAP_PREFIX=D          only maps whose id starts with this
--   DEDUPE=0              keep the second id the cache gives every header (C_01 for C01)
--   SHARD=i/n             every n-th map starting at i (1-based) of the list
--   SKIP=n  LIMIT=n       skip the first n / stop after n maps of the list
--   SEED=n                the random seed (walks, menu fuzz); default 1
--   PHASES=load,walk,warp,npc,sign,menu   which phases run per map (default all)
--   MENUS=once|map|off    the full menu pass: once in the run (default), on
--                         every map, or never
--   PROFILE=new|rich      the save every map starts from (rich: six Pokémon,
--                         a stocked bag, badges, the Pokédex and the Pokétch)
--   STATE=none|flags|chaos  the story state laid over it: none (a new game's),
--                         flags (every event flag and trainer flag set: the
--                         post-game world), chaos (each flag, trainer flag and
--                         the low story vars random, seeded per map -- reaches
--                         script branches a straight playthrough meets late
--                         or never; some states it makes cannot occur in play)
--   LOAD_FRAMES=n WALK_FRAMES=n WARP_FRAMES=n TALK_BUDGET=n  frame budgets
--   MAX_NPCS=n MAX_SIGNS=n MAX_WARPS=n  per-map caps on what is exercised
--   DRAW_EVERY=n          draw the frame every n ticks in load/walk (0 = never)
--   ENTRIES=n             how many arrival cells per map (default 1)
--   MAP_SECS=n            wall-clock allowance per map before it is failed as a
--                         hang (default 120)
--   ENCOUNTERS=1          leave wild encounters on (every grass step may roll one)
--   CAM=off|n             camera rung for the walk phase (default: one per map,
--                         by hash, over the whole ladder; off keeps the player's)
--   TRACE=1               print each phase as it starts
--   OUT=<file>            also append the SWEEP_* lines to this file
--
-- Output: one line per finding, `SWEEP_FAIL|<map>|<phase>|<kind>|<detail>`, and
-- one per map, `SWEEP_MAP|<map>|<ok|fail>|...`, and a final `SWEEP_DONE|...`.

io.stdout:setvbuf("line")
local getenv = os.getenv

local function envn(k, d) return tonumber(getenv(k) or "") or d end
local SEED = envn("SEED", 1)
local LOAD_FRAMES = envn("LOAD_FRAMES", 90)
local WALK_FRAMES = envn("WALK_FRAMES", 240)
local WARP_FRAMES = envn("WARP_FRAMES", 240)
local TALK_BUDGET = envn("TALK_BUDGET", 5000)
local MAX_NPCS = envn("MAX_NPCS", 14)
local MAX_SIGNS = envn("MAX_SIGNS", 10)
local MAX_WARPS = envn("MAX_WARPS", 8)
local DRAW_EVERY = envn("DRAW_EVERY", 45)
local ENTRIES = envn("ENTRIES", 1)
local MENUS = getenv("MENUS") or "once"
local PROFILE = getenv("PROFILE") or "new"
local STATE = getenv("STATE") or "none"
local TRACE = getenv("TRACE")
local OUT = getenv("OUT")

local PHASES = {}
for p in (getenv("PHASES") or "load,walk,warp,npc,sign,menu"):gmatch("[%w_]+") do PHASES[p] = true end

local outFile = OUT and io.open(OUT, "a")
local function emit(line)
  print(line)
  if outFile then outFile:write(line, "\n"); outFile:flush() end
end

local function oneLine(s, n)
  s = tostring(s):gsub("[\r\n]+", " | "):gsub("|%s*|", "|"):gsub("%s+", " ")
  if #s > (n or 900) then s = s:sub(1, n or 900) .. "..." end
  return (s:gsub("%|", "/"))
end

-- --------------------------------------------------------------- the cursor --

local cur = { map = "-", phase = "-" }
local mapFails, mapFailKinds = {}, {}
local totals = { fails = 0 }
local warnShapes = {}

local function fail(kind, detail)
  local line = oneLine(detail)
  local key = kind .. "|" .. line:sub(1, 120)
  if mapFails[key] then return end
  mapFailKinds[kind] = (mapFailKinds[kind] or 0) + 1
  if mapFailKinds[kind] > 6 then return end
  mapFails[key] = true
  totals.fails = totals.fails + 1
  emit(("SWEEP_FAIL|%s|%s|%s|%s"):format(cur.map, cur.phase, kind, line))
end

-- ---------------------------------------------------------------- the logger --

local WARN_FLAGGED = { "parked", "putting it down", "raised", "failed", "stranded",
  "stack overflow", "attempt to", "traceback", "could not", "did not decode" }

local function hookLogger()
  local Logger = require("src.core.Logger")
  for _, level in ipairs({ "error", "warn" }) do
    local orig = Logger[level]
    Logger[level] = function(fmt, ...)
      local ok, msg = pcall(string.format, tostring(fmt), ...)
      if not ok then msg = tostring(fmt) end
      if level == "error" then
        fail("log_error", msg)
      else
        local low = msg:lower()
        local hit
        for _, w in ipairs(WARN_FLAGGED) do if low:find(w, 1, true) then hit = true break end end
        if hit then
          fail("log_warn", msg)
        else
          local shape = msg:gsub("%d+", "#"):sub(1, 110)
          if not shape:find("emptied the stack", 1, true) then warnShapes[shape] = (warnShapes[shape] or 0) + 1 end
        end
      end
      return orig(fmt, ...)
    end
  end
end

-- ------------------------------------------------------------------ the rng --

local rngState = SEED
local function rnd(n)            -- 1..n, a small LCG so a run is the same everywhere
  rngState = (rngState * 1103515245 + 12345) % 2147483648
  return math.floor(rngState / 65536) % n + 1
end

-- ----------------------------------------------------------------- the game --

local Game, OW, Data, StateStack, Collision, Music
local keysDown, keysPressed = {}, {}
local frames = 0
local canvas

local function describeTop()
  local top = Game.stack and Game.stack.states and Game.stack.states[#Game.stack.states]
  if not top then return "empty" end
  if top == OW then return "overworld" end
  local ok, d = pcall(StateStack.describe, top)
  return ok and tostring(d) or tostring(top.screenId or top.name or top.kind or "?")
end

local function stackDepth() return #Game.stack.states end
local function top() return Game.stack.states[#Game.stack.states] end

local function drawFrame()
  local w, h = love.graphics.getDimensions()
  canvas = canvas or love.graphics.newCanvas(w, h)
  love.graphics.push("all")
  local setCanvas = love.graphics.setCanvas
  local target = { canvas, depth = true }
  love.graphics.setCanvas = function(c, ...)
    if c == nil then return setCanvas(target) end
    return setCanvas(c, ...)
  end
  setCanvas(target)
  love.graphics.clear(0, 0, 0, 1)
  local ok, err = xpcall(Game.draw, debug.traceback, Game)
  love.graphics.setCanvas = setCanvas
  setCanvas()
  love.graphics.pop()
  if not ok then fail("draw_error", err) end
  return ok
end

-- One logic tick. Returns false when the update raised (the state is then
-- suspect, and the caller recovers).
-- the last stack changes and the keys pressed with them: what a failure needs
-- to be replayed by hand
local ring, ringAt, lastStack = {}, 0, ""
local function ringNote(line)
  ringAt = ringAt % 40 + 1
  ring[ringAt] = line
end
local function ringDump(n)
  local out = {}
  for i = 1, math.min(n or 14, #ring) do
    local at = (ringAt - i) % 40 + 1
    if ring[at] then table.insert(out, 1, ring[at]) end
  end
  return table.concat(out, " ;; ")
end

local deadline = math.huge
local function tick()
  frames = frames + 1
  -- a map that has run past its wall-clock allowance is a hang of some kind
  -- (a frame loop that never ends); the error unwinds to sweepMap's xpcall
  if os.clock() > deadline then error("MAP_TIMEOUT", 0) end
  local keys = next(keysPressed) and (function()
    local k = {}
    for name in pairs(keysPressed) do k[#k + 1] = name end
    table.sort(k)
    return table.concat(k, "+")
  end)() or nil
  local ok, err = xpcall(Game.stack.update, debug.traceback, Game.stack, 1 / 60)
  keysPressed = {}
  do
    local okS, now = pcall(Game.stack.describeAll, Game.stack)
    now = okS and now or "?"
    if now ~= lastStack then
      lastStack = now
      ringNote(("f%d%s %s"):format(frames, keys and (" [" .. keys .. "]") or "", now))
    elseif keys then
      ringNote(("f%d [%s]"):format(frames, keys))
    end
  end
  -- Game:update advances the music clock on its own accumulator; scripts wait
  -- on its fades (fadeoutbgm), so it has to run here or they never finish
  if ok then pcall(Music.update, Game.data) end
  -- a battle that came onto the stack (a trainer's sight, a wild encounter, a
  -- script's) is the battle agent's: take it off and let the field finish the
  -- way a win would, which is the field's half of every battle
  local t = ok and top()
  if t and t ~= OW and BattleStateClass and getmetatable(t) == BattleStateClass then
    battles = battles + 1
    Game.stack:pop()
    local okB, errB = xpcall(OW.afterBattle, debug.traceback, OW, "win", t)
    if not okB then fail("after_battle_error", errB) end
    OW.engaging = false
  end
  if not ok then
    fail("update_error", err)
    return false
  end
  return true
end

local function press(k) keysPressed[k] = true end

-- run n ticks with `each(i)` called before each (it may press/hold keys);
-- stops early when `stopWhen()` is true. Returns ok, ticksRun.
local function run(n, each, stopWhen, drawEvery)
  for i = 1, n do
    if each then each(i) end
    if not tick() then return false, i end
    if drawEvery and drawEvery > 0 and i % drawEvery == 0 then drawFrame() end
    if stopWhen then
      local stop = stopWhen(i)
      if stop then return true, i end
    end
  end
  return true, n
end

local function fieldHolds()
  -- what keeps the overworld from reading the pad (the conditions in
  -- OverworldState:update's `scripted`), by name
  local why = {}
  if OW.transitioning then why[#why + 1] = "transitioning" end
  if OW.runner and OW.runner:isRunning() then why[#why + 1] = "script" end
  if OW.pendingScripts and OW.pendingScripts[1] then why[#why + 1] = "pendingScripts" end
  if #(OW.scriptMoves or {}) > 0 then why[#why + 1] = "scriptMoves" end
  if OW.engaging then why[#why + 1] = "engaging" end
  if OW.emote then why[#why + 1] = "emote" end
  if OW.teleportOut then why[#why + 1] = "teleportOut" end
  if OW.whirlSpin then why[#why + 1] = "whirlSpin" end
  if OW.gen4Waterfall then why[#why + 1] = "waterfall" end
  if OW.player and OW.player.stairExit then why[#why + 1] = "stairExit" end
  if OW.player and OW.player.moving then why[#why + 1] = "moving" end
  return why
end

local function idle()
  return top() == OW and #fieldHolds() == 0
end

-- --------------------------------------------------------------- the stubs ---

local battles = 0
local BattleStateClass
local pushCount = 0          -- every state push: a script that re-asks its question is cycling, not hung

local function installStubs()
  BattleStateClass = require("src.battle.BattleState")
  -- ENCOUNTERS=1: wild encounters stay on and every grass step may roll one, so
  -- the field's side of a battle (the wipe, the battle on the stack, the way
  -- back) is walked; the sweep pops the battle itself and calls afterBattle
  if getenv("ENCOUNTERS") then
    require("src.world.Encounter").gen4StepAllowed = function() return true end
  end
  -- the LINK row is the port's online "Play Together" screen: a network client,
  -- not the field -- the start menu is built without it
  pcall(function() require("src.ui.Gen4StartMenu").linkRow = function() return nil end end)
  -- TEXT_TRACE=1: every text box and menu the field opens, as it opens
  if getenv("TEXT_TRACE") then
    local TextBox = require("src.render.TextBox")
    local tbNew = TextBox.new
    TextBox.new = function(game, text, ...)
      print("[text] " .. (tostring(text):sub(1, 100):gsub("%c", " / ")))
      return tbNew(game, text, ...)
    end
    local Menu = require("src.ui.Menu")
    local mNew = Menu.new
    Menu.new = function(game, rows, ...)
      local labels = {}
      for i, r in ipairs(rows or {}) do labels[i] = tostring(r.label) end
      print("[menu] " .. table.concat(labels, " | "))
      return mNew(game, rows, ...)
    end
  end
  -- nothing the sweep does may write a save
  local SaveData = require("src.core.SaveData")
  SaveData.save = function() return true end
  SaveData.writeSlot = function() return true end
  SaveData.saveOptions = function() return true end
  -- a script's battle is cut short: counted, and answered as a win
  local Commands = require("src.script.Commands")
  Commands.start_battle = function(ctx, kind, a)
    battles = battles + 1
    ctx.lastBattleResult = "win"
    ctx.lastBattleCanLose = false
    ctx.lastCheck = true
    pcall(function()
      require("src.script.Gen4Commands").setVar(ctx.save, 0x4013, 1)
    end)
  end
end

local function resetKeys()
  keysDown, keysPressed = {}, {}
end

-- ------------------------------------------------------------ the save ------

local function richSave(save)
  local Pokemon = require("src.pokemon.Pokemon")
  local party = {}
  for i, sp in ipairs({ 387, 390, 393, 25, 448, 445 }) do
    local ok, mon = pcall(Pokemon.new, Data, sp, 30 + i)
    if ok and mon then party[#party + 1] = mon end
  end
  -- the field moves, spread over the party so the party menu offers them all
  -- (three each and a plain Tackle, so a move-learn prompt has a move to forget)
  local hm = { { 15, 19, 57, 33 }, { 70, 249, 127, 33 }, { 431, 432, 148, 33 }, { 100, 91, 230, 33 },
    { 208, 156, 29, 33 } }
  for i, ids in ipairs(hm) do
    if party[i] then
      party[i].moves = {}
      for _, id in ipairs(ids) do
        local d = Data.moves and Data.moves[id]
        party[i].moves[#party[i].moves + 1] = { id = id, pp = d and d.pp or 10, maxPP = d and d.pp or 10 }
      end
    end
  end
  if #party > 0 then save.party = party end
  save.money = 99999
  save.coins = 500
  save.badges = save.badges or {}
  for i, entry in ipairs(require("src.inventory.Badges").list(Data) or {}) do
    if i <= 8 then save.badges[entry.id] = true end
  end
  save.poketch = save.poketch or {}
  save.poketch.enabled = true
  save.pokedex = save.pokedex or {}
  save.pokedex.seen, save.pokedex.owned = save.pokedex.seen or {}, save.pokedex.owned or {}
  for id = 1, 493 do save.pokedex.seen[id] = true; save.pokedex.owned[id] = (id % 3 ~= 0) end
  local Bag = require("src.inventory.Bag")
  local n = 0
  for id, it in pairs(Data.items or {}) do
    if type(id) == "string" and type(it) == "table" and n < 160 then
      local ok = pcall(Bag.add, save, id, 3, Data)
      if ok then n = n + 1 end
    end
  end
end

local function storyState(save)
  if STATE == "none" then return end
  save.flags = save.flags or {}
  save.gen4Vars = save.gen4Vars or {}
  save.gen4TrainerFlags = save.gen4TrainerFlags or {}
  if STATE == "flags" then
    for id = 0, 0x7FF do save.flags[("FLAG_G4_%04X"):format(id)] = true end
    for id = 0, 1200 do save.gen4TrainerFlags[id] = true end
    return
  end
  -- chaos: the same state every time this map is entered, whatever happened
  -- in between, so it is its own random stream
  local keep = rngState
  rngState = (cur.hash or SEED) + 17
  for id = 0, 0x7FF do
    if rnd(2) == 1 then save.flags[("FLAG_G4_%04X"):format(id)] = true end
  end
  for id = 0, 1200 do
    if rnd(5) <= 2 then save.gen4TrainerFlags[id] = true end
  end
  for id = 0x4000, 0x40FF do
    local r = rnd(10)
    save.gen4Vars[id] = r <= 4 and 0 or r <= 6 and 1 or r <= 8 and 2 or r - 6
  end
  rngState = keep
end

local function newSave()
  local SaveData = require("src.core.SaveData")
  local save = SaveData.newGame(Game:bootConfig())
  Game.save = save
  if Game.adoptSave then pcall(Game.adoptSave, Game, save, true) end
  if not getenv("ENCOUNTERS") then
    save.repelSteps = 99999        -- wild battles are the battle agent's, not this sweep's
  end
  local okS, errS = pcall(storyState, save)
  if not okS then fail("profile_error", errS) end
  if PROFILE == "rich" then
    local ok, err = pcall(richSave, save)
    if not ok then fail("profile_error", err) end
  end
  return save
end

-- ------------------------------------------------------------- map entry -----

local function popAll()
  local guard = 0
  while Game.stack:top() and guard < 64 do Game.stack:pop(); guard = guard + 1 end
  -- the overworld outlives the stack (Game:returnToTitle clears this too): a
  -- fade overlay it still names would be reused by the next script's fade
  OW.fadeOverlay = nil
end

-- Enter `id` the way a continue does (a fresh stack and a fresh save), so each
-- map starts from the same state whatever the one before it did.
local function enterMap(id, x, y, facing)
  popAll()
  resetKeys()
  newSave()
  Game.stack:push(OW, id, x, y, facing or "down")
end

local function settle(budget, mashA)
  local ok, n = run(budget or 600, function(i)
    if mashA and i % 7 == 0 then press("a") end
  end, idle)
  return ok, n
end

-- every walkable cell of the current map, found by flooding out from (x, y)
-- with the engine's own collision question
local DIRS = { { "up", 0, -1 }, { "down", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 } }

local function reachable(map, sx, sy, limit)
  local ents = OW.cast or OW.entities or OW.npcs or {}
  local p = OW.player
  local seen, order, head = { [sy * 4096 + sx] = true }, { { sx, sy } }, 1
  while head <= #order and #order < (limit or 4000) do
    local c = order[head]; head = head + 1
    for _, d in ipairs(DIRS) do
      local nx, ny = c[1] + d[2], c[2] + d[3]
      local k = ny * 4096 + nx
      if not seen[k] then
        local mover = { cellX = c[1], cellY = c[2], facing = d[1], elevation = p and p.elevation,
          surfing = p and p.surfing }
        local ok, allowed = pcall(Collision.canMove, map, ents, mover, d[1])
        if ok and allowed then seen[k] = true; order[#order + 1] = { nx, ny } end
      end
    end
  end
  return order, seen
end

local function placePlayer(x, y, facing)
  local p = OW.player
  p.cellX, p.cellY = x, y
  p.px, p.py = x * 16, y * 16
  p.targetX, p.targetY = nil, nil
  p.moving = false
  p.facing = facing or p.facing
  OW.player.gen4Height = nil
end

-- ------------------------------------------------------------- the phases ----

local function shallow(t)
  local parts = {}
  if type(t) ~= "table" then return tostring(t) end
  local keys = {}
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == "number" or tv == "boolean" or (tv == "string" and #v < 40) then keys[#keys + 1] = tostring(k) end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    if #parts < 24 then parts[#parts + 1] = k .. "=" .. tostring(t[k]) end
  end
  -- ...and the NAMES of the table fields that are set: a screen's sub-state
  -- (menu, trash, moving, message, dial) is usually one of those
  local sets = {}
  for k, v in pairs(t) do
    if type(v) == "table" and type(k) == "string" and not k:find("^_") and k ~= "game" and k ~= "data"
       and k ~= "opts" and k ~= "images" and next(v) ~= nil then sets[#sets + 1] = k end
  end
  table.sort(sets)
  if #sets > 0 then parts[#parts + 1] = "{" .. table.concat(sets, ",", 1, math.min(#sets, 30)) .. "}" end
  return table.concat(parts, ",")
end

local function stuckDetail(extra)
  local runner = OW.runner
  if getenv("DEBUG_STUCK") then
    local t = Game.stack.states[#Game.stack.states]
    print("[stuck] top fields: " .. shallow(t))
    print(("[stuck] runner waitingFrames=%s waitingCheck=%s moves=%d pending=%s stuckFrames=%s"):format(
      tostring(runner.waitingFrames), tostring(runner.waitingCheck ~= nil), #(OW.scriptMoves or {}),
      tostring(OW.pendingScripts and #OW.pendingScripts), tostring(OW.stuckFrames)))
  end
  local row = runner and runner.lastRow
  local src = runner and runner.ctx and runner.ctx.source
  return ("%s | top=%s depth=%d runner=%s row=%s src=%s holds=%s"):format(
    extra or "", describeTop(), stackDepth(), tostring(runner and runner:isRunning()),
    tostring(row), src and (tostring(src.mapId) .. "." .. tostring(src.hook)) or "?",
    table.concat(fieldHolds(), "+"))
end

-- After a failure the world may be half-torn-down; put the player back on a
-- clean overworld of the same map without touching the save.
local function recover(mapId, x, y)
  local guard = 0
  while Game.stack:top() and Game.stack:top() ~= OW and guard < 64 do
    Game.stack:pop(); guard = guard + 1
  end
  if OW.runner then OW.runner.co = nil; OW.runner.waitingFrames = nil; OW.runner.waitingCheck = nil end
  OW.transitioning = false
  OW.fadeOverlay = nil
  OW.scriptMoves = {}
  OW.pendingScripts = {}
  resetKeys()
  if Game.stack:top() ~= OW then
    Game.stack:push(OW, mapId, x or 1, y or 1, "down")
  end
end

-- Clear a state the sweep caused: a text box or choice left up, a battle that
-- came onto the stack, ... by mashing A/B. Reports a softlock when it does not clear.
local function fingerprint()
  local t = top()
  local p = OW.player
  local parts = { tostring(pushCount), tostring(stackDepth()), describeTop(), tostring(OW.runner and OW.runner.lastRow),
    tostring(OW.map and OW.map.id), p and (p.cellX .. "," .. p.cellY) or "-",
    tostring(OW.transitioning), tostring(OW.runner and OW.runner.waitingFrames ~= nil) }
  if t and t ~= OW then
    -- a timed screen (the credits, a cutscene scene) shows its progress in a
    -- frame counter; a text box's own counters only blink
    if not t.pages then parts[#parts + 1] = tostring(t.frame) .. "/" .. tostring(t.tick) end
    -- a scene with a script of its own (the Frontier's)
    if type(t.runner) == "table" and t.runner ~= OW.runner then
      parts[#parts + 1] = tostring(t.runner.lastRow) .. tostring(t.runner.waitingFrames)
    end
    parts[#parts + 1] = table.concat({ tostring(t.pageIndex), tostring(t.lineIndex), tostring(t.charIndex),
      tostring(t.index), tostring(t.row), tostring(t.cursor), tostring(t.page), tostring(t.phase),
      tostring(t.state), tostring(t.step), tostring(t.alpha), tostring(t.mode) }, ":")
  end
  return table.concat(parts, "|")
end

-- Clear a state the sweep caused: a text box or choice left up, a battle that
-- came onto the stack, ... by mashing A/B.
--   softlock  nothing about the game changed for STALL frames of mashing
--   loop      it kept changing but never came back (an NPC that asks again
--             while A keeps answering yes, ...) -- reported separately, it
--             is what the mashing does, not a hang
local STALL = envn("STALL", 1500)
local STALL_WAIT = envn("STALL_WAIT", 2400)
local loops = 0
local function drain(kind, budget)
  budget = budget or TALK_BUDGET
  local lastFp, sameFor = nil, 0
  local rows = {}
  local ok, n = run(budget, function(i)
    -- A alone first (text, menus and quantity pickers advance), then B alone
    -- (every menu backs out), then a mix; a plain A/B alternation can cycle
    -- a shop between BUY and its list forever
    if i <= 360 then
      if i % 7 == 0 then press("a") end
    elseif i <= 1000 then
      if i % 7 == 0 then press("b") end
    else
      local m = i % 11
      if m == 0 then press("a") elseif m == 5 then press("b") end
      if i % 97 == 0 then press("start") end
      if i % 13 == 0 then press(({ "down", "right", "up", "left", "down", "right" })[rnd(6)]) end
    end
  end, function(i)
    local t = top()
    if i % 6 == 0 then
      local fp = fingerprint()
      if fp == lastFp then sameFor = sameFor + 6 else sameFor = 0; lastFp = fp end
      if OW.runner and OW.runner.lastRow then rows[OW.runner.lastRow] = true end
      -- a script waiting on a frame count or a condition may be a long cutscene
      -- (the boat's sail is ten seconds); one with nothing waiting is parked
      local r = OW.runner
      local waiting = (r and r:isRunning() and (r.waitingFrames or r.waitingCheck))
        or (t and t ~= OW and type(t.co) == "thread" and coroutine.status(t.co) ~= "dead")
      if sameFor >= (waiting and STALL_WAIT or STALL) then return "stalled" end
    end
    return idle()
  end)
  if not ok then return false end
  if idle() then return true end
  local r, t = OW.runner, top()
  local waiting = (r and r:isRunning() and (r.waitingFrames or r.waitingCheck))
    or (t and t ~= OW and type(t.co) == "thread" and coroutine.status(t.co) ~= "dead")
  if sameFor >= (waiting and STALL_WAIT or STALL) then
    fail(waiting and "softlock_waiting" or "softlock",
      stuckDetail(("%s: nothing changed for %d frames of A/B"):format(kind, sameFor)))
    return false
  end
  local n, names = 0, {}
  for row in pairs(rows) do n = n + 1; names[#names + 1] = row end
  table.sort(names)
  loops = loops + 1
  emit(("SWEEP_LOOP|%s|%s|%s|%d distinct rows in %d frames | %s | rows: %s"):format(cur.map, cur.phase, kind, n, budget,
    oneLine(stuckDetail(""), 300), oneLine(table.concat(names, "; "), 400)))
  return "loop"
end

local function phaseLoad(mapDef)
  cur.phase = "load"
  local ok = run(LOAD_FRAMES, nil, nil, DRAW_EVERY)
  if not ok then return false end
  local r = settle(300)
  return r ~= false
end

local function randomWalk(mapId, ox, oy)
  cur.phase = "walk"
  if (cur.hash or 0) % 3 == 0 and Game.save then Game.save.onBike = true end
  -- every map's walk uses one rung of the camera ladder (cartridge, fixed
  -- angles, third and first person -- the last two walk OFF the grid)
  if getenv("CAM") ~= "off" then
    pcall(function()
      local Gen4Camera = require("src.render.Gen4Camera")
      local want = tonumber(getenv("CAM") or "") or ((cur.hash or 0) % #Gen4Camera.TILTS + 1)
      local _, index = Gen4Camera.setTilt(want)
      Game.save.options = Game.save.options or {}
      Game.save.options.gen4CameraTilt = index
      cur.camera = index
    end)
  end
  local dir, hold = nil, 0
  local lastCell, still = nil, 0
  local moved = {}
  local ok = run(WALK_FRAMES, function(i)
    local p = OW.player
    if not idle() and top() == OW and not OW.player.moving and OW.runner:isRunning() then
      -- a script took over: mash through it
      if i % 9 == 0 then press("a") end
      keysDown = {}
      return
    end
    local cell = p.cellX .. "," .. p.cellY
    if cell == lastCell and not p.moving then still = still + 1 else still = 0 end
    lastCell = cell
    moved[cell] = true
    if hold <= 0 or still > 8 then
      dir = DIRS[rnd(4)][1]
      hold = 6 + rnd(30)
      still = 0
    end
    hold = hold - 1
    -- hold B (run) a third of the time, and ride the bicycle on a third of maps
    keysDown = { [dir] = true, b = (math.floor(i / 40) % 3 == 0) or nil }
    if top() ~= OW then keysDown = {}; if i % 9 == 0 then press("b") end end
  end, nil, DRAW_EVERY)
  keysDown = {}
  local n = 0
  for _ in pairs(moved) do n = n + 1 end
  return ok, n
end

-- take each warp of the map: stand next to it, face it, walk in
local function phaseWarps(mapId, def, landing)
  cur.phase = "warp"
  local taken, tried = 0, 0
  local warps = def.warps or {}
  for wi, w in ipairs(warps) do
    if tried >= MAX_WARPS then break end
    if w.destMap and w.x and w.y then
      tried = tried + 1
      enterMap(mapId, landing[1], landing[2], "down")
      local okL = run(30)
      if not okL then recover(mapId, landing[1], landing[2]); goto continue end
      settle(200)
      if not idle() or OW.map.id ~= mapId then goto continue end
      do
        local p, map = OW.player, OW.map
        local ents = OW.cast or OW.entities or OW.npcs or {}
        local placed
        for _, d in ipairs(DIRS) do
          -- a stand cell next to the warp from which stepping `toward` enters it
          local toward = ({ up = "down", down = "up", left = "right", right = "left" })[d[1]]
          local sx, sy = w.x + d[2], w.y + d[3]
          if map:inBounds(sx, sy) then
            local mover = { cellX = sx, cellY = sy, facing = toward, elevation = p.elevation }
            local ok, allowed = pcall(Collision.canMove, map, ents, mover, toward)
            if ok and allowed and map:isWalkableCell(sx, sy) then placed = { sx, sy, toward } break end
          end
        end
        if not placed then
          -- edge/mat warps: step onto the warp cell from a side the map allows is
          -- not decidable here; count it as untested rather than failing
          goto continue
        end
        placePlayer(placed[1], placed[2], placed[3])
        local before = OW.map.id
        local changed = false
        local ok = run(WARP_FRAMES, function(i)
          if top() == OW and not OW.transitioning and not OW.player.moving then
            keysDown = { [placed[3]] = true }
          else
            keysDown = {}
          end
        end, function()
          if OW.map.id ~= before and idle() then changed = true return true end
        end, 0)
        keysDown = {}
        if not ok then recover(mapId, landing[1], landing[2]); goto continue end
        if changed then
          taken = taken + 1
          -- the far side is alive: a few frames, a draw, and out of any script
          local okA = run(60, nil, nil, 30)
          if okA then drain("warp arrival") end
        else
          -- the walk-in did not take (a locked door, a script-held tile or
          -- an arrival that needs a flag) is not a failure by itself; only a
          -- stuck state is
          if not idle() then drain("warp walk-in") end
        end
      end
      ::continue::
    end
  end
  return taken, tried
end

-- neighbours of (cx, cy) the player can stand on and step toward it from
local function standCells(map, cx, cy, skipEnt)
  local ents = {}
  for _, e in ipairs(OW.cast or OW.entities or OW.npcs or {}) do
    if e ~= skipEnt then ents[#ents + 1] = e end
  end
  local out = {}
  local p = OW.player
  for _, d in ipairs(DIRS) do
    local toward = ({ up = "down", down = "up", left = "right", right = "left" })[d[1]]
    local sx, sy = cx + d[2], cy + d[3]
    if map:inBounds(sx, sy) and not map:warpAtCell(sx, sy) then
      local mover = { cellX = sx, cellY = sy, facing = toward, elevation = p.elevation }
      local ok, allowed = pcall(Collision.canMove, map, ents, mover, toward)
      if ok and allowed then out[#out + 1] = { sx, sy, toward } end
    end
  end
  return out
end

local function talkAt(mapId, landing, label, getTarget)
  -- the world is idle and on the right map; put the player on a stand cell
  -- next to the target, face it, press A, and mash through whatever answers
  local map = OW.map
  local cx, cy, skip = getTarget()
  if not cx then return "skipped" end
  local cells = standCells(map, cx, cy, skip)
  if #cells == 0 then return "unreachable" end
  local c = cells[rnd(#cells)]
  placePlayer(c[1], c[2], c[3])
  local ok = run(3)
  if not ok then return "error" end
  press("a")
  local ok2 = run(2)
  if not ok2 then return "error" end
  local busy = not idle()
  if busy then
    local r = drain(label)
    if r == "loop" then return "loop" end
    if not r then return "stuck" end
  end
  return busy and "talked" or "silent"
end

local function phaseTalk(mapId, def, landing, signsToo)
  local talked, silent, stuck, errs = 0, 0, 0, 0
  cur.phase = "npc"
  -- NPCs: indexes by their def so a script that moves them cannot reorder the walk
  local list = {}
  enterMap(mapId, landing[1], landing[2], "down")
  run(30)
  settle(300)
  for _, npc in ipairs(OW.npcs or {}) do
    if npc.def and not npc.hidden and not npc.pikachuFollower then list[#list + 1] = npc.def.index end
  end
  local count = 0
  local only = tonumber(getenv("ONLY_NPC") or "")
  for _, index in ipairs(list) do
    if count >= MAX_NPCS then break end
    if only and index ~= only then goto skipnpc end
    count = count + 1
    if OW.map.id ~= mapId or top() ~= OW then
      enterMap(mapId, landing[1], landing[2], "down")
      run(20); settle(300)
    end
    local label = "npc#" .. tostring(index)
    local res = talkAt(mapId, landing, label, function()
      for _, npc in ipairs(OW.npcs or {}) do
        if npc.def and npc.def.index == index and not npc.hidden then return npc.cellX, npc.cellY, npc end
      end
    end)
    if res == "talked" then talked = talked + 1 elseif res == "silent" then silent = silent + 1
    elseif res == "stuck" then stuck = stuck + 1 elseif res == "error" then errs = errs + 1 end
    if res == "loop" then recover(mapId, landing[1], landing[2]) end
    if TRACE then print(("[sweep] %s %s -> %s"):format(mapId, label, res)) end
    if res == "stuck" or res == "error" or res == "loop" or OW.map.id ~= mapId then
      recover(mapId, landing[1], landing[2])
      enterMap(mapId, landing[1], landing[2], "down")
      run(20); settle(300)
    end
    ::skipnpc::
  end
  if signsToo then
    cur.phase = "sign"
    local n = 0
    for _, s in ipairs(def.signs or {}) do
      if n >= MAX_SIGNS then break end
      n = n + 1
      if OW.map.id ~= mapId or top() ~= OW then
        enterMap(mapId, landing[1], landing[2], "down")
        run(20); settle(300)
      end
      local res = talkAt(mapId, landing, "sign@" .. s.x .. "," .. s.y, function() return s.x, s.y end)
      if res == "talked" then talked = talked + 1 elseif res == "silent" then silent = silent + 1
      elseif res == "stuck" then stuck = stuck + 1 end
      if res == "stuck" or res == "error" or res == "loop" or OW.map.id ~= mapId then
        recover(mapId, landing[1], landing[2])
        enterMap(mapId, landing[1], landing[2], "down")
        run(20); settle(300)
      end
    end
  end
  return talked, silent, stuck
end

-- ----------------------------------------------------------- the menu pass ---

-- Every key the pad has; the fuzz leans on A and the d-pad so screens go
-- DEEP (a submenu, a pocket, a page) before B backs them out
local KEYS = { "a", "a", "down", "down", "up", "left", "right", "a", "b", "down", "right", "l", "r",
  "start", "select", "left", "a" }

local visited = {}
local tally = { party = 0, bag = 0 }
local function noteScreen()
  visited[describeTop()] = true
end

-- Close what is above `floorDepth` with B (and START, which closes the pause
-- menu) -- a screen the pad cannot leave is a softlock.
local function closeScreens(label, floorDepth)
  -- B alone (every screen should back out), then A alone (a "really?" that
  -- defaults to NO has to be answered), then a random mix with the d-pad (a
  -- cursor parked on the wrong row of a yes/no)
  local ok = run(1000, function(i)
    if i <= 150 then
      if i % 4 == 0 then press("b") end
      if i % 40 == 0 then press("start") end
    elseif i <= 300 then
      if i % 5 == 0 then press("a") end
    else
      local m = i % 6
      if m == 0 then press("b") elseif m == 2 then press("a")
      elseif m == 4 then press(({ "up", "down", "left", "right" })[rnd(4)]) end
    end
  end, function() return stackDepth() <= floorDepth end)
  if not ok then return false end
  if stackDepth() > floorDepth then
    local names = {}
    for _, st in ipairs(Game.stack.states) do
      local okD, d = pcall(StateStack.describe, st)
      names[#names + 1] = okD and tostring(d) or "?"
    end
    fail("softlock", ("%s: B did not close the screens | top=%s depth=%d | stack=%s | top fields: %s | recent: %s"):format(label,
      describeTop(), stackDepth(), table.concat(names, " > "), shallow(top()), ringDump(16)))
    while stackDepth() > floorDepth do Game.stack:pop() end
    return false
  end
  return true
end

-- Press random keys at whatever is on top for `n` ticks, recording each screen
-- seen; stops when everything above `floor` has closed or the map changed.
local function fuzzStack(label, n, floor, keys)
  keys = keys or KEYS
  local mapNow = OW.map and OW.map.id
  local ok = run(n, function(i)
    if i % 4 == 0 then press(keys[rnd(#keys)]) end
  end, function(i)
    if i % 8 == 0 then noteScreen() end
    return stackDepth() <= floor or (OW.map and OW.map.id) ~= mapNow
  end, 30)
  return ok
end

local function openMenu(label)
  local floor = stackDepth()
  press("start")
  local ok = run(20)
  if not ok then return nil end
  if stackDepth() <= floor then
    fail("menu_unopened", label .. ": START did not open a menu | " .. stuckDetail(
      ("map=%s moving=%s locked=%s cell=%s,%s surf=%s emote=%s engaging=%s"):format(tostring(OW.map and OW.map.id),
        tostring(OW.player.moving), tostring(OW.lockedFrames), tostring(OW.player.cellX), tostring(OW.player.cellY),
        tostring(OW.player.surfing), tostring(OW.emote ~= nil), tostring(OW.engaging))))
    return nil
  end
  return floor
end

local MENU_SKIP = {}
for id in (getenv("MENU_SKIP") or "link,mods"):gmatch("[^,%s]+") do MENU_SKIP[id] = true end

local MENU_ROUNDS = envn("MENU_ROUNDS", 4)
local MENU_FUZZ = envn("MENU_FUZZ", 700)

local function menuPass()
  cur.phase = "menu"
  -- a map that opens on a scene: read it out (A / B) before the menu is asked for
  if not idle() then
    local r = drain("menu arrival scene")
    if r ~= true then recover(OW.map.id, OW.player.cellX, OW.player.cellY) end
  end
  local floor = openMenu("start menu")
  if not floor then return end
  local menu = top()
  local rows = (menu and (menu.rows or menu.items)) or {}
  local ids = {}
  for i, r in ipairs(rows) do ids[i] = tostring(r.id or r.label or r.key or i) end
  if #ids == 0 then ids = { "?", "?", "?", "?", "?", "?", "?" } end
  if not closeScreens("start menu close", floor) then return end
  local mapId = OW.map.id
  local lx, ly = OW.player.cellX, OW.player.cellY
  for i, rowId in ipairs(ids) do
    if MENU_SKIP[rowId] then goto skiprow end
    for round = 1, MENU_ROUNDS do
      local label = ("start row %s #%d"):format(rowId, round)
      visited = {}
      if not idle() then
        if not drain(label .. " settle") then recover(mapId, lx, ly) end
      end
      local f = openMenu(label)
      if not f then recover(mapId, lx, ly); goto next end
      do
        local m = top()
        if m and m.index then m.index = i end
        press("a")
        local ok = run(25, nil, nil, 10)
        if not ok then recover(mapId, lx, ly); goto next end
        noteScreen()
        if stackDepth() > f then
          -- a sub-screen (or the confirmation of one) is up: poke at it
          drawFrame()
          fuzzStack(label, MENU_FUZZ, f)
        end
        local okC = closeScreens(label, f)
        if not okC then recover(mapId, lx, ly) end
        -- the field may have a script/prompt of its own after (save, ...)
        if OW.map.id ~= mapId then
          enterMap(mapId, lx, ly, "down"); run(20); settle(300)
        elseif not idle() then drain(label) end
      end
      if round == 1 then
        local names = {}
        for name in pairs(visited) do names[#names + 1] = name end
        table.sort(names)
        emit(("SWEEP_INFO|%s|menu_row|%s -> %s"):format(cur.map, rowId, oneLine(table.concat(names, " ; "), 300)))
      end
      ::next::
    end
    ::skiprow::
  end
end

local function poketchPass()
  cur.phase = "poketch"
  local Screens = require("src.ui.Screens")
  Game.save.poketch = Game.save.poketch or {}
  Game.save.poketch.enabled = true
  local okN, pk = pcall(Screens.push, Game, "Gen4Poketch", { onCancel = function() end })
  if not okN then fail("poketch_open", pk) return end
  local menu = top()
  if not (menu and menu.apps) then
    fail("poketch_open", "no apps list on " .. describeTop())
    closeScreens("poketch", 1)
    return
  end
  -- every cartridge app registered
  local st = menu:store()
  st.registered = {}
  for i = 0, 40 do st.registered[i] = true end
  local count = #menu.apps
  for idx = 1, count do
    menu.index = idx
    menu.appState = nil
    local label = "poketch app " .. idx
    local ok = run(40, nil, nil, 20)
    if not ok then break end
    -- taps over the touch area, then keys
    for _, pt in ipairs({ { 128, 96 }, { 40, 40 }, { 200, 150 }, { 128, 170 } }) do
      if menu.touchpressed then
        local okT, errT = xpcall(menu.touchpressed, debug.traceback, menu, 1, pt[1], pt[2])
        if not okT then fail("poketch_touch", label .. ": " .. tostring(errT)) end
        if menu.touchreleased then pcall(menu.touchreleased, menu, 1, pt[1], pt[2]) end
      end
      if not run(8) then break end
    end
    fuzzStack(label, 80, stackDepth() - 1, { "a", "down", "up", "left", "right" })
    if top() ~= menu then
      fail("poketch_closed", label .. ": the watch closed under input")
      return
    end
  end
  -- cycle with the bezel
  for _ = 1, count do
    press("right")
    if not run(12, nil, nil, 6) then break end
  end
  closeScreens("poketch", 1)
end

-- bring the world back to an idle field on `mapId` with only the overworld on
-- the stack: B out of whatever is open, re-enter the map when a field move or
-- an item took the player elsewhere, put down anything the world is still doing
local function ensureField(mapId, lx, ly, label)
  if stackDepth() > 1 then closeScreens(label, 1) end
  if OW.map.id ~= mapId or top() ~= OW then
    enterMap(mapId, lx, ly, "down"); run(20); settle(300)
  elseif not idle() then
    if not drain(label) then recover(mapId, lx, ly) end
  end
  if OW.map.id ~= mapId or top() ~= OW then
    enterMap(mapId, lx, ly, "down"); run(20); settle(300)
  end
end

-- Open the party menu and take EVERY action it offers on every member (the
-- summary, switch, give / take, and each field move the HM-loaded rich party
-- knows), drawing and fuzzing whatever comes up. Each action starts from a
-- freshly opened menu on a fresh field, so one that ends the visit (Fly,
-- Teleport, Dig) costs nothing.
local function partyPass()
  cur.phase = "party"
  local mapId = OW.map.id
  local lx, ly = OW.player.cellX, OW.player.cellY
  local Screens = require("src.ui.Screens")
  local slot, k, guard = 1, 1, 0
  while guard < 90 do
    guard = guard + 1
    ensureField(mapId, lx, ly, "party")
    if slot > #(Game.save.party or {}) then break end
    local base = stackDepth()
    local okP, errP = pcall(Screens.push, Game, "PartyMenu", { onCancel = function() end })
    if not okP then fail("party_open", errP) return end
    run(8, nil, nil, 8)
    local menu = top()
    if not (menu and menu.actions and menu.runAction) then closeScreens("party", base) return end
    menu.index = slot
    menu.submenu, menu.itemMenu, menu.mailMenu, menu.switchFrom = 1, nil, nil, nil
    local acts = menu:actions()
    local action = acts[k]
    if not action or action == "cancel" then
      slot, k = slot + 1, 1
    else
      local label = ("party slot %d action %s"):format(slot, tostring(action))
      tally.party = tally.party + 1
      if TRACE then print("[sweep] " .. label) end
      visited = {}
      local okA, errA = xpcall(menu.runAction, debug.traceback, menu, action)
      if not okA then fail("party_action", label .. ": " .. tostring(errA)) end
      if not run(40, nil, nil, 20) then recover(mapId, lx, ly) return end
      noteScreen()
      if stackDepth() > base + 1 or (top() ~= menu and stackDepth() > base) then
        fuzzStack(label, 220, base + 1)
      end
      k = k + 1
    end
  end
  ensureField(mapId, lx, ly, "party")
end

-- Open the bag, walk every pocket, and use / give / toss / register every item
-- in it (A on the item, then each action in the item's menu), backing out of
-- whatever each one opens. Same shape as the party pass: one fresh bag per action.
local MAX_BAG_ITEMS = envn("MAX_BAG_ITEMS", 14)
local function bagPass()
  cur.phase = "bag"
  local mapId = OW.map.id
  local lx, ly = OW.player.cellX, OW.player.cellY
  local Screens = require("src.ui.Screens")
  local pocket, item, k, guard = 1, 1, 1, 0
  local pockets
  while guard < 600 do
    guard = guard + 1
    ensureField(mapId, lx, ly, "bag")
    local base = stackDepth()
    local okP, errP = pcall(Screens.push, Game, "BagMenu", { onCancel = function() end })
    if not okP then fail("bag_open", errP) return end
    run(8, nil, nil, 8)
    local bag = top()
    if not (bag and bag.rows and bag.runAction) then closeScreens("bag", base) return end
    pockets = pockets or (bag.pockets and #bag.pockets or 8)
    if pocket > pockets then break end
    for _ = 2, pocket do press("right"); run(3) end
    run(4)
    local count = math.min(#(bag.rows or {}), MAX_BAG_ITEMS)
    if item > count then
      pocket, item, k = pocket + 1, 1, 1
    else
      for _ = 2, item do press("down"); run(2) end
      press("a"); run(6)
      local m = bag.menu
      local action = m and m.rows and m.rows[k]
      if not action or action == "cancel" then
        item, k = item + 1, 1
      else
        local label = ("bag pocket %d item %d action %s"):format(pocket, item, tostring(action))
        tally.bag = tally.bag + 1
        if TRACE then print("[sweep] " .. label) end
        visited = {}
        bag.menu.index = k
        press("a")
        if not run(30, nil, nil, 15) then recover(mapId, lx, ly) return end
        noteScreen()
        if stackDepth() > base + 1 or (top() ~= bag and stackDepth() > base) then
          fuzzStack(label, 180, base + 1)
        end
        k = k + 1
      end
    end
  end
  ensureField(mapId, lx, ly, "bag")
end

local function menusFull()
  tally = { party = 0, bag = 0 }
  menuPass()
  if not idle() then drain("menus") end
  if idle() then partyPass() end
  if idle() then bagPass() end
  if idle() then poketchPass() end
  emit(("SWEEP_INFO|%s|menus|party actions %d, bag actions %d"):format(cur.map, tally.party, tally.bag))
end

-- -------------------------------------------------------------- the driver ---

local function pickMaps()
  local ids = {}
  for k, v in pairs(Data.maps) do
    if type(k) == "string" and type(v) == "table" and v.id == k then ids[#ids + 1] = k end
  end
  table.sort(ids)
  local want = getenv("MAPS")
  if want and want ~= "all" then
    local out = {}
    for id in want:gmatch("[^,%s]+") do out[#out + 1] = id end
    ids = out
  end
  -- the cache carries every Sinnoh map under two ids (C01 and C_01: the same
  -- header twice); sweeping both doubles the run and finds nothing new.
  -- DEDUPE=0 keeps the aliases.
  if getenv("DEDUPE") ~= "0" and not (want and want ~= "all") then
    local seen, out = {}, {}
    for _, id in ipairs(ids) do
      local h = Data.maps[id] and Data.maps[id].header
      if h == nil or not seen[h] then out[#out + 1] = id; if h ~= nil then seen[h] = true end end
    end
    ids = out
  end
  local prefix = getenv("MAP_PREFIX")
  if prefix then
    local out = {}
    for _, id in ipairs(ids) do if id:sub(1, #prefix) == prefix then out[#out + 1] = id end end
    ids = out
  end
  local shard, of = (getenv("SHARD") or ""):match("^(%d+)/(%d+)$")
  if shard then
    local out = {}
    for i, id in ipairs(ids) do if (i - 1) % tonumber(of) == tonumber(shard) - 1 then out[#out + 1] = id end end
    ids = out
  end
  local skip, limit = envn("SKIP", 0), envn("LIMIT", math.huge)
  local out = {}
  for i, id in ipairs(ids) do
    if i > skip and #out < limit then out[#out + 1] = id end
  end
  return out
end

-- where a warp INTO each map lands (the destination warp's own cell, which is
-- what Warp.destination hands the player), found by reading every map's warps
local incoming
local function buildIncoming()
  incoming = {}
  for fromId, def in pairs(Data.maps) do
    if type(fromId) == "string" and type(def) == "table" and def.id == fromId then
      for _, w in ipairs(def.warps or {}) do
        local dest = w.destMap and Data.maps[w.destMap]
        local dw = dest and dest.warps and dest.warps[w.destWarp]
        if dw and dw.x and dw.y then
          local list = incoming[w.destMap]
          if not list then list = {}; incoming[w.destMap] = list end
          list[#list + 1] = { dw.x, dw.y, from = fromId }
        end
      end
    end
  end
  for _, list in pairs(incoming) do
    table.sort(list, function(a, b)
      if a.from ~= b.from then return a.from < b.from end
      if a[1] ~= b[1] then return a[1] < b[1] end
      return a[2] < b[2]
    end)
  end
end

-- an arrival cell for the map: where a real warp lands (a map nothing warps to
-- gets one of its own warps' cells), else the middle of it
local function landings(id, def)
  if not incoming then buildIncoming() end
  local out, seen = {}, {}
  for _, l in ipairs(incoming[id] or {}) do
    local key = l[1] * 4096 + l[2]
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = { l[1], l[2], via = l.from }
    end
    if #out >= ENTRIES then break end
  end
  if #out == 0 then
    for _, w in ipairs(def.warps or {}) do
      if w.x and w.y then out[#out + 1] = { w.x, w.y } end
      if #out >= ENTRIES then break end
    end
  end
  if #out == 0 then
    -- no warps at all: the middle of the map, nudged until the engine agrees it is floor
    local cx, cy = math.floor((def.width or 2) / 2), math.floor((def.height or 2) / 2)
    out[1] = { cx, cy, probe = true }
  end
  return out
end

local function sweepMap(id, menusHere)
  cur.map, cur.phase = id, "load"
  mapFails, mapFailKinds = {}, {}
  -- each map's randomness is its own, so a restart or a shard replays it exactly
  local h = SEED * 7919
  for i = 1, #id do h = (h * 31 + id:byte(i)) % 2147483647 end
  rngState = h
  cur.hash = h
  local def = Data.maps[id]
  if not def then
    fail("unknown_map", "no such map in the cache")
    emit(("SWEEP_MAP|%s|fail|unknown"):format(id))
    return
  end
  local t0 = os.clock()
  deadline = t0 + envn("MAP_SECS", 120)
  local f0 = frames
  local failsBefore = totals.fails
  local info = { taken = 0, tried = 0, walked = 0, talked = 0, silent = 0, stuck = 0 }
  local lands = landings(id, def)
  local landing = lands[1]
  local ok, err = xpcall(function()
    if TRACE then print("[sweep] " .. id .. " load") end
    enterMap(id, landing[1], landing[2], "down")
    if OW.map == nil or OW.map.id ~= id then
      fail("load_mismatch", ("asked for %s, got %s"):format(id, tostring(OW.map and OW.map.id)))
    end
    if landing.probe and OW.map then
      local order = reachable(OW.map, landing[1], landing[2])
      if #order <= 1 then
        -- a seed that is a wall: scan for any reachable cell
        for y = 0, (def.height or 0) - 1 do
          for x = 0, (def.width or 0) - 1 do
            local o = reachable(OW.map, x, y, 12)
            if #o > 6 then landing[1], landing[2] = x, y; goto found end
          end
        end
        ::found::
        enterMap(id, landing[1], landing[2], "down")
      end
    end
    if PHASES.load and not phaseLoad(def) then return end
    if PHASES.walk and OW.map and OW.map.id == id then
      if TRACE then print("[sweep] " .. id .. " walk") end
      local okW, n = randomWalk(id, landing[1], landing[2])
      info.walked = n or 0
      if okW and not idle() then drain("walk") end
      if not okW then recover(id, landing[1], landing[2]) end
    end
    if PHASES.warp then
      if TRACE then print("[sweep] " .. id .. " warp") end
      info.taken, info.tried = phaseWarps(id, def, landing)
    end
    if PHASES.npc or PHASES.sign then
      if TRACE then print("[sweep] " .. id .. " talk") end
      info.talked, info.silent, info.stuck = phaseTalk(id, def, landing, PHASES.sign)
    end
    if PHASES.menu and menusHere then
      if TRACE then print("[sweep] " .. id .. " menus") end
      if OW.map.id ~= id or top() ~= OW or not idle() then
        enterMap(id, landing[1], landing[2], "down")
        run(20); settle(300)
      end
      menusFull()
    end
  end, debug.traceback)
  if not ok then
    if tostring(err):find("MAP_TIMEOUT", 1, true) then
      fail("map_timeout", ("the map ran past %ds of wall clock | top=%s depth=%d"):format(envn("MAP_SECS", 120),
        describeTop(), stackDepth()))
    else
      fail("harness_error", err)
    end
  end
  deadline = math.huge
  -- an arrival the player cannot walk away from (a cutscene room, or a map
  -- whose spawn is boxed in): informational, the scripted ones are legitimate
  if PHASES.walk and info.walked <= 2 and #(def.warps or {}) > 0 then
    emit(("SWEEP_INFO|%s|boxed_arrival|walked %d cell(s) from %d,%d (arrival of a warp from %s)"):format(id, info.walked,
      landing[1], landing[2], tostring(landing.via or "none -- own warp cell")))
  end
  local failed = totals.fails - failsBefore
  emit(("SWEEP_MAP|%s|%s|frames=%d secs=%.1f npcs=%d signs=%d warps=%d/%d talked=%d silent=%d stuck=%d walked=%d"):format(
    id, failed == 0 and "ok" or "fail", frames - f0, os.clock() - t0, #(def.objects or {}), #(def.signs or {}),
    info.taken, info.tried, info.talked, info.silent, info.stuck, info.walked))
  cur.phase = "-"
end

function love.load()
  local ok, err = xpcall(function()
    require("src.core.GameVersion").set(getenv("VERSION") or "platinum")
    local assetRoot = getenv("POKEPORT_ASSET_ROOT")
    if assetRoot then
      local Assets = require("src.render.Assets")
      local realImage, held = Assets.image, {}
      Assets.image = function(path, ...)
        if type(path) == "string" and not held[path] then
          local f = io.open(assetRoot .. "/" .. path, "rb")
          if f then
            local bytes = f:read("*a"); f:close()
            local okI, img = pcall(love.graphics.newImage, love.filesystem.newFileData(bytes, path))
            if okI then img:setFilter("nearest", "nearest"); held[path] = img end
          end
        end
        return held[path] or realImage(path, ...)
      end
    end
    -- the services Game:boot boots, in its order
    Data = require("src.core.Data")
    Data:load()
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
    StateStack = require("src.core.StateStack")
    StateStack:init()
    Game.stack = StateStack
    Collision = require("src.world.Collision")
    Music = require("src.core.Music")
    OW = require("src.world.OverworldController")

    Game.input = setmetatable({
      state = keysDown, pressed = keysPressed,
      wasPressed = function(_, k) return keysPressed[k] == true end,
      isDown = function(_, k) return keysDown[k] == true or keysPressed[k] == true end,
      wasReleased = function() return false end,
      isTouchDown = function() return false end,
      step = function() end,
      softResetStep = function() return false end,
    }, { __index = function() return function() return false end end })

    hookLogger()
    installStubs()
    do
      local push = StateStack.push
      StateStack.push = function(self, ...)
        pushCount = pushCount + 1
        return push(self, ...)
      end
    end
    newSave()

    _G.__sweep = { Game = Game, OW = OW, Data = Data, enterMap = enterMap, run = run, press = press,
      idle = idle, top = top, drain = drain, settle = settle, placePlayer = placePlayer,
      standCells = standCells, stackDepth = stackDepth, describeTop = describeTop,
      fails = function() return totals.fails end }
    -- PROBE=<file.lua>: run a scratch script against the booted game and quit
    if getenv("PROBE") then
      local okP, errP = xpcall(dofile, debug.traceback, getenv("PROBE"))
      if not okP then print("PROBE FAILED: " .. tostring(errP)) end
      love.event.quit(0)
      return
    end
    local ids = pickMaps()
    if getenv("LIST") then
      for _, id in ipairs(ids) do print("SWEEP_LIST|" .. id) end
      love.event.quit(0)
      return
    end
    emit(("SWEEP_START|maps=%d profile=%s state=%s seed=%d phases=%s menus=%s"):format(#ids, PROFILE, STATE, SEED,
      getenv("PHASES") or "all", MENUS))
    local menusDone = false
    local t0 = os.clock()
    local failedMaps = 0
    for i, id in ipairs(ids) do
      local menusHere = (MENUS == "map") or (MENUS == "once" and (not menusDone or id == "UG"))
      local fb = totals.fails
      sweepMap(id, menusHere)
      if menusHere then menusDone = true end
      if totals.fails > fb then failedMaps = failedMaps + 1 end
      collectgarbage("collect")
    end
    -- the warnings that were not flagged, by shape, most frequent first
    local shapes = {}
    for s, n in pairs(warnShapes) do shapes[#shapes + 1] = { s, n } end
    table.sort(shapes, function(a, b) return a[2] > b[2] or (a[2] == b[2] and a[1] < b[1]) end)
    for i = 1, math.min(25, #shapes) do emit(("SWEEP_WARN|%d|%s"):format(shapes[i][2], oneLine(shapes[i][1], 200))) end
    emit(("SWEEP_DONE|maps=%d failed_maps=%d fails=%d battles_cut=%d frames=%d secs=%.0f"):format(
      #ids, failedMaps, totals.fails, battles, frames, os.clock() - t0))
  end, debug.traceback)
  if not ok then
    emit("SWEEP_CRASH|" .. oneLine(err, 2000))
  end
  if outFile then outFile:close() end
  love.event.quit(0)
end
