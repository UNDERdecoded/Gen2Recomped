-- Public intents exercised through real Loader, BattleState and native input.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local BattleState = require("src.battle.BattleState")
local GameVersion = require("src.core.GameVersion")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Font = require("src.render.Font")
local Runtime = require("src.mods.Runtime")
local Json = require("src.link.Json")
local Merge = require("src.mods.Merge")
local Commands = require("src.battle.BattleCommands")
local Intents = require("src.mods.BattleIntents")
local oldVersion = GameVersion.get()

local function boot(version, trainer, level)
  GameVersion.set(version)
  math.randomseed(12345)
  local data = T.fixtures.fresh()
  local files = {}
  for _, id in ipairs({ "probe", "other" }) do
    files["mods/" .. id .. "/manifest.json"] =
      Json.encode({ id = id, name = id, version = "1.0.0", api = level or 2, entry = "main.lua" })
    files["mods/" .. id .. "/main.lua"] = [[return function(mod)
      assert(type(mod.battle.submit)=="function")
      assert(mod.battle:snapshot()==nil)
    end]]
  end
  local fs = {
    read = function(p)
      return files[p]
    end,
    load = function(p)
      return loadstring(files[p], p)
    end,
    getDirectoryItems = function(p)
      return p == "mods" and { "probe", "other" } or {}
    end,
    getInfo = function(p)
      if p == "mods" or p == "mods/probe" or p == "mods/other" then
        return { type = "directory" }
      end
      if files[p] then
        return { type = "file" }
      end
    end,
  }
  local loader = Loader.new({ fs = fs, dev = false })
  local game = { data = data, stack = { states = {} }, save = SaveData.newGame() }
  loader.game = game
  assert(loader:load(data), table.concat(loader.errors, "; "))
  Font.load(data)
  game.save.party = { Pokemon.new(data, "FIXMON_A", 20), Pokemon.new(data, "FIXMON_B", 12) }
  game.input = {
    wasPressed = function()
      return false
    end,
    isDown = function()
      return false
    end,
  }
  game.stack.top = function(stack)
    return stack.states[#stack.states]
  end
  game.stack.push = function(stack, state)
    stack.states[#stack.states + 1] = state
  end
  game.stack.pop = function(stack)
    return table.remove(stack.states)
  end
  local b = trainer and BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
    or BattleState.newWild(game, "FIXMON_C", 10)
  b:syncSides()
  b.phase = "menu"
  b.gen4CursorActive = true
  b.frame = 0
  b.queue = {}
  b.menuIndex = 1
  b.moveIndex = 1
  local rolls = 0
  b.rng = function(lo, hi)
    rolls = rolls + 1
    return lo
  end
  game.stack.states = { b }
  return loader.apis.probe.battle,
    game,
    b,
    loader.apis.other.battle,
    loader,
    function()
      return rolls
    end
end
local function intent(api, id, kind, fields)
  local s = assert(api:snapshot())
  local out = { id = id, revision = s.revision, kind = kind }
  for k, v in pairs(fields or {}) do
    out[k] = v
  end
  return out
end
local function send(api, id, kind, fields)
  return api:submit(intent(api, id, kind, fields))
end
local function freeze(root)
  local graph = {}
  local function visit(value)
    if type(value) ~= "table" or graph[value] then
      return
    end
    local row = { values = {}, mt = getmetatable(value) }
    graph[value] = row
    for key, item in pairs(value) do
      row.values[key] = item
      visit(item)
    end
  end
  visit(root)
  return function()
    for tbl, row in pairs(graph) do
      if getmetatable(tbl) ~= row.mt then
        return false
      end
      for key, value in pairs(row.values) do
        if tbl[key] ~= value then
          return false
        end
      end
      for key in pairs(tbl) do
        if row.values[key] == nil then
          return false
        end
      end
    end
    return true
  end
end
local function forbidden()
  error("unexpected native side effect")
end
local function reject(api, game, raw, fragment, label)
  local battler = game.stack.states[1]
  local oldRng = battler and battler.rng
  if battler and battler.isBattleState then
    battler.rng = forbidden
  end
  local unchanged = freeze(game)
  local oldLua, oldLove, oldEmit, oldCall = math.random, love.math.random, Runtime.emit, Runtime.call
  math.random, love.math.random, Runtime.emit, Runtime.call = forbidden, forbidden, forbidden, forbidden
  local ok, reason = api:submit(raw)
  math.random, love.math.random, Runtime.emit, Runtime.call = oldLua, oldLove, oldEmit, oldCall
  T.eq(ok, nil, label .. ": rejected")
  T.check(
    type(reason) == "string" and reason:find(fragment, 1, true) ~= nil,
    label .. ": reason " .. tostring(reason)
  )
  T.check(unchanged(), label .. ": whole game graph unchanged")
  if battler and battler.isBattleState then
    battler.rng = oldRng
  end
end
local function view(api)
  local s = assert(api:snapshot())
  s.revision = nil
  return s
end
local function press(game, b, key)
  game.input.wasPressed = function(_, name)
    return name == key
  end
  b:update(1 / 60)
  game.input.wasPressed = function()
    return false
  end
end

for _, version in ipairs(GameVersion.ORDER) do
  local label = version .. ": "
  -- Identical native input and API commands, including actual turn planning.
  local api, game, b, other, loader, rolls = boot(version)
  local control, cgame, cb, _, _, crolls = boot(version)
  T.eq(send(api, 1, "menu", { choice = "fight" }), true, label .. "FIGHT accepted")
  press(cgame, cb, "a")
  T.same(view(api), view(control), label .. "FIGHT matches native A dispatch")
  T.eq(send(api, 2, "move", { slot = 1 }), true, label .. "move accepted")
  press(cgame, cb, "a")
  T.same(view(api), view(control), label .. "move matches native A dispatch")
  T.eq(rolls(), crolls(), label .. "native RNG consumption matches")
  T.eq(#b.queue, #cb.queue, label .. "native action queue matches")
  T.eq(b.turnCount, 1, label .. "exactly one native turn planned")
  local function drain(g, bb)
    g.input.wasPressed = function()
      return true
    end
    g.input.isDown = function()
      return true
    end
    for frame = 1, 5000 do
      if not bb:updateQueue() then
        return true
      end
    end
    return false
  end
  T.check(drain(game, b), label .. "API native turn queue completes")
  T.check(drain(cgame, cb), label .. "input native turn queue completes")
  T.eq(b.enemy.mon.hp, cb.enemy.mon.hp, label .. "native damage identical after queue")
  T.eq(b.player.mon.hp, cb.player.mon.hp, label .. "enemy retaliation identical after queue")
  T.eq(b.player.curMoves[1].pp, cb.player.curMoves[1].pp, label .. "PP consumption identical after queue")
  T.eq(rolls(), crolls(), label .. "full native turn RNG identical")
  if loader.apis.probe.supports then
    T.eq(loader.apis.probe:supports("battle", "submit"), true, label .. "submit capability")
  end
  -- Menu opening does not bypass the party/bag controller or consume items.
  for _, choice in ipairs({ "party", "item", "run" }) do
    local a, g, bb = boot(version)
    local c, cg, cc = boot(version)
    T.eq(send(a, 1, "menu", { choice = choice }), true, label .. choice .. " accepted")
    local indices = cc:menuActions()
    for i, value in ipairs(indices) do
      if value == choice or (choice == "party" and value == "pkmn") then
        cc.menuIndex = i
      end
    end
    press(cg, cc, "a")
    -- Native cursor is selected by the player; the public API addresses the
    -- action by name, so it need not move that display cursor.
    local sv, cv = view(a), view(c)
    sv.menuIndex = nil
    cv.menuIndex = nil
    T.same(sv, cv, label .. choice .. " matches native input")
    T.eq(#bb.queue, #cc.queue, label .. choice .. " native queue")
  end
  api, game, b = boot(version)
  local first = assert(api:snapshot())
  local bads = { false, {}, setmetatable({ id = 1, revision = first.revision, kind = "back" }, {}) }
  for _, raw in ipairs(bads) do
    reject(api, game, raw, "", label .. "malformed intent")
  end
  for _, value in ipairs({ 0, -1, 1.5, math.huge, -math.huge, 0 / 0, "1", true, 9007199254740992 }) do
    reject(
      api,
      game,
      { id = value, revision = first.revision, kind = "menu", choice = "fight" },
      "integer",
      label .. "unsafe ID"
    )
    reject(
      api,
      game,
      { id = 1, revision = value, kind = "menu", choice = "fight" },
      "revision",
      label .. "unsafe revision"
    )
  end
  local malformed = {
    { kind = "mystery" },
    { kind = "menu", choice = "catch" },
    { kind = "menu", choice = {} },
    { kind = "move", slot = "1" },
    { kind = "move", slot = 0 },
    { kind = "move", slot = 5 },
    { kind = "target", target = -1 },
    { kind = "target", target = 4 },
    { kind = "mimic", index = 0 },
    { kind = "mimic", index = 5 },
    { kind = "safari", action = "mud" },
    { kind = "safari", action = false },
    { kind = "back", extra = true },
    { kind = "move", slot = 1, idOverride = 3 },
  }
  for _, fields in ipairs(malformed) do
    local raw = { id = 1, revision = first.revision }
    for k, v in pairs(fields) do
      raw[k] = v
    end
    reject(api, game, raw, "", label .. "strict intent fields")
  end
  local current = intent(api, 1, "menu", { choice = "fight" })
  T.eq(api:submit(current), true, label .. "rejected IDs were not consumed")
  reject(api, game, current, "replayed", label .. "accepted ID cannot replay")
  current.id = 0
  reject(api, game, current, "integer", label .. "ID zero is invalid")
  current = intent(api, 3, "move", { slot = 1 })
  b.player.mon.hp = b.player.mon.hp - 1
  reject(api, game, current, "stale", label .. "changed HP invalidates revision")
  current = intent(api, 3, "move", { slot = 1 })
  b.player.curMoves[1] = Merge.deepCopy(b.player.curMoves[1])
  reject(api, game, current, "stale", label .. "identical replacement move invalidates revision")
  current = intent(api, 3, "move", { slot = 1 })
  b.player.mon = Merge.deepCopy(b.player.mon)
  reject(api, game, current, "stale", label .. "identical replacement Pokemon invalidates revision")
  current = intent(api, 3, "move", { slot = 1 })
  game.stack.states[2] = { battle = b }
  reject(api, game, current, "stale", label .. "new covering screen invalidates revision")
  reject(
    api,
    game,
    intent(api, 3, "move", { slot = 1 }),
    "covered",
    label .. "fresh covered snapshot still cannot act"
  )
  game.stack.states[2] = nil
  for _, phase in ipairs({ "intro", "messages", "waitRemote", "finished" }) do
    b.phase = phase
    reject(
      api,
      game,
      intent(api, 3, "menu", { choice = "fight" }),
      "active",
      label .. "wrong phase " .. phase
    )
  end
  b.phase = "menu"
  for _, flag in ipairs({ "demo", "dudeDemo", "pokedudeDemo", "spectating", "palace", "arena" }) do
    b[flag] = true
    reject(
      api,
      game,
      intent(api, 3, "menu", { choice = "fight" }),
      "controller",
      label .. "automatic controller " .. flag
    )
    b[flag] = nil
  end
  for _, flag in ipairs({ "result", "dead", "waitingUI" }) do
    b[flag] = true
    reject(api, game, intent(api, 3, "menu", { choice = "fight" }), "ready", label .. "not ready " .. flag)
    b[flag] = nil
  end
  b.kind = "link"
  reject(api, game, intent(api, 3, "menu", { choice = "fight" }), "controller", label .. "link refused")
  b.kind = "wild"
  for _, flag in ipairs({ "mustRecharge", "charging", "rageMove", "thrashTurns" }) do
    b.player[flag] = 1
    reject(
      api,
      game,
      intent(api, 3, "menu", { choice = "fight" }),
      "locked",
      label .. flag .. " automatic lock"
    )
    b.player[flag] = nil
  end
  b.player.ally = true
  reject(api, game, intent(api, 3, "menu", { choice = "fight" }), "ready", label .. "NPC ally refused")
  b.player.ally = nil
  b.player.mon.hp = 0
  reject(api, game, intent(api, 3, "menu", { choice = "fight" }), "ready", label .. "fainted chooser refused")
  b.player.mon.hp = 30
  b.phase = "moveSelect"
  for _, guard in ipairs({ "pp", "disable", "taunt", "torment", "swap" }) do
    local mv = b.player.curMoves[1]
    local def = game.data.moves[mv.id]
    local power = def.power
    if guard == "pp" then
      mv.pp = 0
    end
    if guard == "disable" then
      b.player.disabledSlot = 1
    end
    if guard == "taunt" then
      b.player.tauntTurns = 2
      def.power = 0
    end
    if guard == "torment" then
      b.player.tormented = true
      b.player.lastMove = mv.id
    end
    if guard == "swap" then
      b.moveSwapIndex = 1
    end
    reject(api, game, intent(api, 3, "move", { slot = 1 }), "", label .. guard .. " rejected before action")
    mv.pp = 20
    b.player.disabledSlot = nil
    b.player.tauntTurns = nil
    b.player.tormented = nil
    b.player.lastMove = nil
    b.moveSwapIndex = nil
    def.power = power
  end
  reject(api, game, intent(api, 3, "move", { slot = 4 }), "slot", label .. "missing slot refused")
  b.moveSwapIndex = 1
  T.eq(send(api, 3, "back"), true, label .. "back cancels reorder")
  T.eq(b.moveSwapIndex, nil, label .. "reorder marker cleared")
  T.eq(b.phase, "menu", label .. "back to menu")
  reject(api, game, intent(api, 4, "back"), "nothing", label .. "single menu has no back action")
  game.stack.states = {}
  reject(api, game, { id = 4, revision = 1, kind = "back" }, "no battle", label .. "outside battle refused")
end
local function doubles(api, game, b)
  math.randomseed(54321)
  b.double = true
  b:placeBattler(2, BattleState.makeBattler(game.data, game.save.party[2], true, game.save))
  local foe = Pokemon.new(game.data, "FIXMON_B", 10)
  b.enemyParty = b.enemyParty or { b.enemy.mon }
  b.enemyParty[2] = foe
  b:placeBattler(3, BattleState.makeBattler(game.data, foe, false))
  b:syncSides()
end
for _, version in ipairs(GameVersion.ORDER) do
  local label = version .. " doubles: "
  local api, game, b = boot(version)
  local control, cgame, cb = boot(version)
  doubles(api, game, b)
  doubles(control, cgame, cb)
  T.eq(send(api, 1, "menu", { choice = "fight" }), true, label .. "first FIGHT")
  press(cgame, cb, "a")
  T.eq(send(api, 2, "move", { slot = 1 }), true, label .. "first move enters targets")
  press(cgame, cb, "a")
  T.eq(b.phase, "targetSelect", label .. "native targeting phase")
  reject(api, game, intent(api, 3, "target", { target = 0 }), "selector", label .. "cannot target own slot")
  local offered = intent(api, 3, "target", { target = 3 })
  b.targetChoices = { unpack(b.targetChoices) }
  reject(api, game, offered, "stale", label .. "selector identity changed")
  T.eq(send(api, 3, "target", { target = 3 }), true, label .. "position 3 selected")
  cb.targetIndex = 2
  press(cgame, cb, "a")
  T.same(view(api), view(control), label .. "position maps to correct native cursor")
  T.eq(b.chosenTargets[0], b:battlerAt(3), label .. "chosen actual right foe")
  T.eq(b.choosingSlot, 2, label .. "second chooser")
  T.eq(send(api, 4, "back"), true, label .. "undo first selection from second menu")
  press(cgame, cb, "b")
  T.same(view(api), view(control), label .. "back matches native B")
  T.eq(b.pendingActions[0], nil, label .. "pending first action cleared")
  T.eq(b.chosenTargets[0], nil, label .. "pending target cleared")
  -- Native B from target returns to moves, then from moves to action menu.
  T.eq(send(api, 5, "menu", { choice = "fight" }), true, label .. "fight again")
  T.eq(send(api, 6, "move", { slot = 1 }), true, label .. "target again")
  T.eq(send(api, 7, "back"), true, label .. "cancel target")
  T.eq(b.pendingMove, nil, label .. "pending move cleared")
  T.eq(b.targetChoices, nil, label .. "target selector cleared")
  T.eq(b.phase, "moveSelect", label .. "back to moves")
  T.eq(send(api, 8, "back"), true, label .. "back to menu")
  T.eq(send(api, 9, "menu", { choice = "fight" }), true, label .. "choose first action")
  T.eq(send(api, 10, "move", { slot = 1 }), true, label .. "select first move")
  local stale = intent(api, 11, "target", { target = 1 })
  b.pendingMove = Merge.deepCopy(b.pendingMove)
  reject(api, game, stale, "stale", label .. "pending move identity changed")
  reject(api, game, intent(api, 11, "target", { target = 1 }), "pending", label .. "orphaned pending move")
  b.pendingMove = b.player.curMoves[1]
  b.pendingMove.pp = 0
  reject(api, game, intent(api, 11, "target", { target = 1 }), "PP", label .. "pending move rechecks PP")
  b.pendingMove.pp = 20
  b:battlerAt(1).mon.hp = 0
  reject(api, game, intent(api, 11, "target", { target = 1 }), "field", label .. "fainted target refused")
  b:battlerAt(1).mon.hp = 30
  T.eq(send(api, 11, "target", { target = 1 }), true, label .. "first target")
  T.eq(send(api, 12, "menu", { choice = "fight" }), true, label .. "second FIGHT")
  T.eq(send(api, 13, "move", { slot = 1 }), true, label .. "second move")
  T.eq(send(api, 14, "target", { target = 0 }), true, label .. "target position zero supported")
  T.eq(b.chosenTargets[2], b.player, label .. "second actor aimed at left partner")
  T.eq(b.turnCount, 1, label .. "second chooser resolves one whole turn")
  -- A surviving right flank still owns a usable menu.
  api, game, b = boot(version)
  doubles(api, game, b)
  b:placeBattler(0, nil)
  T.eq(api:snapshot().active, 2, label .. "missing-left chooser")
  T.eq(send(api, 1, "menu", { choice = "fight" }), true, label .. "right-only FIGHT")
  T.eq(b.phase, "moveSelect", label .. "right-only moves")
  -- Mimic belongs to its queued user, even when that is the right flank.
  b.phase = "mimicSelect"
  local user = b:battlerAt(2)
  local target = b.enemy
  b.mimicCtx = { user = user, target = target, moveInst = user.curMoves[1] }
  b.mimicMoves = { { slot = 1, id = target.curMoves[1].id } }
  b.mimicIndex = 1
  T.eq(api:snapshot().active, 2, label .. "Mimic uses queued right-flank user")
  local picked = intent(api, 2, "mimic", { index = 1 })
  b.mimicCtx.target = b:battlerAt(3)
  reject(api, game, picked, "stale", label .. "Mimic source identity changed")
  b.mimicCtx.target = target
  T.eq(send(api, 2, "mimic", { index = 1 }), true, label .. "native Mimic copy")
  T.eq(user.curMoves[1].id, target.curMoves[1].id, label .. "Mimic installs selected source")
  T.eq(b.phase, "messages", label .. "Mimic resumes queue")
  T.eq(#b.mimicRestores, 1, label .. "native restoration bookkeeping preserved")
end

-- Safari uses its native model, including Platinum's own action implementation.
for _, version in ipairs({ "red", "firered", "platinum", "heartgold" }) do
  for _, action in ipairs({ "ball", "bait", "rock", "run" }) do
    local api, game, b = boot(version)
    local control, cgame, cb = boot(version)
    for _, battle in ipairs({ b, cb }) do
      battle.safari = { balls = 5 }
      battle.safariCatchRate = 80
      battle.baitFactor = 0
      battle.escapeFactor = 0
      if version == "platinum" then
        battle.gen4Safari = require("src.battle.Gen4Safari").init()
      end
    end
    T.eq(send(api, 1, "safari", { action = action }), true, version .. ": Safari " .. action)
    cb.menuIndex = ({ ball = 1, bait = 2, rock = 3, run = 4 })[action]
    press(cgame, cb, "a")
    T.same(view(api), view(control), version .. ": Safari matches native " .. action)
    T.eq(b.safari.balls, action == "ball" and 4 or 5, version .. ": ball spent only for throw")
    local old = intent(api, 2, "safari", { action = "ball" })
    reject(api, game, old, "", version .. ": cannot repeat Safari action during messages")
    b.phase = "menu"
    b.result = nil
    b.safari.balls = 0
    reject(
      api,
      game,
      intent(api, 2, "safari", { action = "run" }),
      "balls",
      version .. ": depleted Safari belongs to automatic exit"
    )
    b.safari.balls = 1
    reject(
      api,
      game,
      intent(api, 2, "menu", { choice = "fight" }),
      "safari",
      version .. ": regular menu cannot bypass Safari"
    )
  end
end

-- BW eligibility goes through the native read-only rules, not the snapshot's
-- deliberately partial disabled flag.
for _, version in ipairs({ "black", "white" }) do
  for _, guard in ipairs({ "choice", "imprison", "gravity", "heal", "sky" }) do
    local api, game, b = boot(version)
    b.phase = "moveSelect"
    b.bw = { field = {}, sides = { {}, {} } }
    local mv = b.player.curMoves[1]
    local def = game.data.moves[mv.id]
    if guard == "choice" then
      game.data.items.CHOICE = { name = "Choice", bwPocket = 1, holdEffect = 55 }
      b.player.items = game.data.items
      b.player.mon.item = "CHOICE"
      b.player.bwChoiceLock = "FIX_CUT"
      b.player.curMoves[2] = { id = "FIX_CUT", pp = 3 }
    elseif guard == "imprison" then
      b.enemy.bwImprison = true
      b.enemy.curMoves = { { id = mv.id, pp = 2 } }
    elseif guard == "gravity" then
      b.bw.field.gravity = 3
      def.gravityBanned = true
    elseif guard == "heal" then
      b.player.bwHealBlock = 3
      def.healMove = true
    else
      b.player.bwSkyDropped = b.enemy
    end
    reject(
      api,
      game,
      intent(api, 1, "move", { slot = 1 }),
      "",
      version .. ": native BW restriction " .. guard
    )
  end
end

-- Cross-facade atomicity, consumption and recovery are deliberately tested
-- with native boundary overrides; the real-input cases above verify gameplay.
do
  local api, game, b, other = boot("crystal")
  reject(
    api,
    game,
    { id = 1, revision = 1, kind = "menu", choice = "fight" },
    "snapshot",
    "unobserved context"
  )
  local native = b.chooseMenu
  local executions = 0
  local nested, mid
  local otherRequest = intent(other, 1, "menu", { choice = "fight" })
  b.chooseMenu = function(self, choice)
    executions = executions + 1
    nested = { other:submit(otherRequest) }
    mid = other:snapshot()
    return native(self, choice)
  end
  T.eq(send(api, 1, "menu", { choice = "fight" }), true, "outer command accepted")
  T.eq(nested[1], nil, "reentrant other mod rejected")
  T.check(nested[2]:find("progress", 1, true) ~= nil, "reentrant rejection reason")
  T.eq(mid.prompt, "locked", "mid-dispatch snapshot is locked")
  reject(
    other,
    game,
    { id = 1, revision = mid.revision, kind = "back" },
    "stale",
    "mid-dispatch revision cannot act after return"
  )
  T.eq(executions, 1, "one native dispatch")
  T.eq(send(other, 1, "back"), true, "other facade has independent intent ID sequence")
  b.chooseMenu = function()
    executions = executions + 1
    return true
  end
  local held = intent(other, 2, "menu", { choice = "fight" })
  T.eq(send(api, 2, "menu", { choice = "fight" }), true, "same-shaped accepted native command")
  reject(other, game, held, "stale", "shared epoch invalidates unchanged records across mods")
  local raw = intent(api, 3, "menu", { choice = "fight" })
  b.chooseMenu = function()
    executions = executions + 1
    b.phase = "messages"
    error("native boom")
  end
  local accepted, err = api:submit(raw)
  T.eq(accepted, nil, "native exception reported")
  T.check(
    err:find("consumed", 1, true) ~= nil and err:find("native boom", 1, true) ~= nil,
    "native error explains consumed ID"
  )
  reject(api, game, raw, "replayed", "partial failure cannot replay")
  T.eq(Intents.state(game).busy, false, "error clears shared busy flag")
  b.phase = "menu"
  b.chooseMenu = native
  T.eq(send(api, 4, "menu", { choice = "fight" }), true, "new request recovers after native failure")
end

do
  local api, game, b, other, loader = boot("red")
  local original = b.menuBattler
  local request = intent(api, 1, "menu", { choice = "fight" })
  local nested
  local otherRequest = intent(other, 1, "menu", { choice = "fight" })
  b.menuBattler = function(self)
    nested = { other:submit(otherRequest) }
    return original(self)
  end
  T.eq(api:submit(request), true, "validation rejects recursion while outer intent succeeds")
  T.eq(nested[1], nil, "validation reentry rejected")
  T.eq(send(api, 2, "back"), true, "validation reentry leaves facade usable")
  b.menuBattler = function(self)
    game.stack.states[2] = {}
    return original(self)
  end
  local ok, err = api:submit(intent(api, 3, "menu", { choice = "fight" }))
  T.eq(ok, nil, "preflight context change refused")
  T.check(err:find("stale", 1, true) ~= nil, "preflight context change reason")
  -- The intentionally overridden validator above changed the stack itself;
  -- test the refusal separately from the normal no-side-effects contract.
  game.stack.states[2] = nil
  b.menuBattler = original
  T.eq(Intents.state(game).busy, false, "preflight failure clears busy flag")
  local raw = intent(api, 3, "menu", { choice = "fight" })
  b.menuBattler = function(self)
    raw.choice = "run"
    raw.id = 999
    return original(self)
  end
  T.eq(api:submit(raw), true, "intent copied before native validation")
  T.eq(b.phase, "moveSelect", "caller mutation cannot change dispatch choice")
  b.menuBattler = original
  local _, newGame, newBattle = boot("blue")
  loader.game = newGame
  reject(
    api,
    newGame,
    { id = 3, revision = raw.revision, kind = "back" },
    "replayed",
    "consumption survives Game replacement"
  )
  T.eq(send(api, 4, "menu", { choice = "fight" }), true, "captured facade follows new Game")
  T.eq(newBattle.phase, "moveSelect", "action reaches replacement Game")
end

-- Accepted calls can enter normal refusal/forced-action paths too. They do
-- not reinterpret a native trainer RUN, no-PP Struggle or trapped FIGHT.
for _, mode in ipairs({ "struggle", "trapping", "ghost", "trainerRun" }) do
  local api, game, b = boot("crystal", mode == "trainerRun")
  local control, cgame, cb = boot("crystal", mode == "trainerRun")
  for _, bb in ipairs({ b, cb }) do
    if mode == "struggle" then
      for _, mv in ipairs(bb.player.curMoves) do
        mv.pp = 0
      end
    end
    if mode == "trapping" then
      bb.player.trappingTurns = 2
    end
    if mode == "ghost" then
      bb.ghost = true
    end
  end
  local choice = mode == "trainerRun" and "run" or "fight"
  T.eq(send(api, 1, "menu", { choice = choice }), true, mode .. ": public selection accepted")
  cb.menuIndex = mode == "trainerRun" and 4 or 1
  press(cgame, cb, "a")
  local actual, expected = view(api), view(control)
  actual.menuIndex = nil
  expected.menuIndex = nil
  T.same(actual, expected, mode .. ": preserves native branch")
  T.eq(#b.queue, #cb.queue, mode .. ": native queue preserved")
end

do
  local api, game, b = boot("red")
  local raw = intent(api, 1, "menu", { choice = "fight" })
  local rev = raw.revision
  raw.extra = "typo"
  reject(api, game, raw, "field", "invalid field is observational")
  T.eq(api:snapshot().revision, rev, "pure invalid intent does not advance revision")
  raw.extra = nil
  local native = b.chooseMenu
  b.chooseMenu = function()
    return nil, "native declined"
  end
  local ok, err = api:submit(raw)
  T.eq(ok, nil, "native refusal returned")
  T.eq(err, "native declined", "native refusal reason retained")
  reject(api, game, raw, "replayed", "native invocation consumes even when it declines")
  b.chooseMenu = native
  T.eq(send(api, 2, "menu", { choice = "fight" }), true, "native decline clears busy lock")
  local _, otherGame = boot("blue")
  game.stack.states[1] = otherGame.stack.states[1]
  reject(api, game, intent(api, 3, "back"), "Game", "foreign Game battle cannot be controlled")
end
do
  local api, game, b = boot("red")
  local owner = Runtime.currentMod
  Runtime.currentMod = "probe"
  b.chooseMenu = function()
    T.eq(Runtime.currentMod, nil, "native dispatch uses engine attribution")
    error("scope failure")
  end
  local ok = send(api, 1, "menu", { choice = "fight" })
  T.eq(ok, nil, "scoped native error returned")
  T.eq(Runtime.currentMod, "probe", "native error restores caller attribution")
  Runtime.currentMod = owner
end
do
  local api, game, b, other, loader = boot("emerald")
  local callbackCount, nested, mid = 0, nil, nil
  local held = intent(other, 1, "menu", { choice = "fight" })
  loader.apis.probe.events:on("battle.turn_started", function()
    callbackCount = callbackCount + 1
    T.eq(Runtime.currentMod, nil, "real event uses native engine scope")
    mid = other:snapshot()
    nested = { other:submit(held) }
  end)
  T.eq(send(api, 1, "menu", { choice = "fight" }), true, "real event test selects FIGHT")
  T.eq(send(api, 2, "move", { slot = 1 }), true, "real event test plans native turn")
  T.eq(callbackCount, 1, "one native turn-start callback")
  T.eq(nested[1], nil, "real event cannot recursively submit")
  T.eq(mid.prompt, "locked", "real event sees locked in-flight snapshot")
  reject(
    other,
    game,
    { id = 1, revision = mid.revision, kind = "back" },
    "stale",
    "real event snapshot expires after dispatch"
  )
  T.eq(Runtime.currentMod, nil, "real native event restores engine/caller scope")
end
local api = boot("red", false, 1)
T.eq(send(api, 1, "menu", { choice = "fight" }), true, "API 1 mod can use additive public actions")
GameVersion.set(oldVersion)
T.finish("battle actions")
