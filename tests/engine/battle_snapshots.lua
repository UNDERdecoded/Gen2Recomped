-- ROM-free contract tests through the real mod loader and BattleState.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Loader = require("src.mods.Loader")
local BattleState = require("src.battle.BattleState")
local GameVersion = require("src.core.GameVersion")
local Merge = require("src.mods.Merge")
local Json = require("src.link.Json")
local oldVersion, oldLove = GameVersion.get(), love
love = nil

-- Exercise the real loader resolver, including Lua 5.1's in-progress marker.
local cachedGame = package.loaded["src.core.Game"]
package.loaded["src.core.Game"] = nil
T.eq(Loader._game({}, true), nil, "loaded-only lookup does not bootstrap Game")
T.eq(package.loaded["src.core.Game"], nil, "lookup leaves module cache untouched")
package.loaded["src.core.Game"] = true
T.eq(Loader._game({}, true), nil, "in-progress Game is unavailable")
local injected = {}
T.eq(Loader._game({ game = injected }, true), injected, "explicit Game takes precedence")
package.loaded["src.core.Game"] = injected
T.eq(Loader._game({}, true), injected, "live cached Game is available")
package.loaded["src.core.Game"] = cachedGame

local function boot(version, level)
  GameVersion.set(version)
  local ds = GameVersion.generation() >= 4
  local s, m, item = ds and 25 or "PIKACHU", ds and 33 or "TACKLE", ds and 4 or "POKE_BALL"
  local species, move =
    { name = "Pikachu", types = { "ELECTRIC" } },
    { name = "Tackle", pp = 35, power = 40, accuracy = 95, type = "NORMAL" }
  local data = {
    pokemon = { [s] = species },
    moves = { [m] = move },
    items = {
      [item] = { name = "Poké Ball", ball = "POKE_BALL" },
      Z_EXTRA = { name = "Extra" },
      A_EXTRA = { name = "Earlier" },
    },
  }
  if ds then
    data.pokemon.SPECIES_25 = species
    data.moves.MOVE_33 = move
  end
  local function mon(nick)
    return {
      species = s,
      nickname = nick,
      level = 7,
      hp = 19,
      status = "PSN",
      stats = { hp = 23, attack = 10, defense = 11, special = 12, speed = 13 },
      moves = { { id = m, pp = 29, ppUps = 1 } },
      isEgg = false,
      extension = { flag = false },
    }
  end
  local a, b, e, f = mon("Left"), mon("Right"), mon("Foe"), mon("Other foe")
  if GameVersion.generation() > 1 then
    for _, raw in ipairs({ a, b, e, f }) do
      raw.stats.spatk, raw.stats.spdef = 14, 15
    end
  end
  local party = { a, b }
  local function battler(raw)
    return {
      mon = raw,
      name = raw.nickname,
      species = raw.species,
      curStats = raw.stats,
      curTypes = { "ELECTRIC" },
      curMoves = raw.moves,
      stages = {},
    }
  end
  local game = {
    data = data,
    save = {
      party = party,
      inventory = {
        [item] = 3,
        Z_EXTRA = 2,
        A_EXTRA = 1,
        ZERO = 0,
      },
      bagOrder = { item, item, "ZERO" },
    },
    stack = { states = {} },
  }
  local btl = setmetatable({
    game = game,
    data = data,
    kind = "wild",
    phase = "menu",
    queue = {},
    player = battler(a),
    enemy = battler(e),
    enemyParty = { e, f },
    turnCount = 0,
    sides = { { battlers = {} }, { battlers = {} } },
  }, BattleState)
  btl:placeBattler(0, btl.player)
  btl:placeBattler(1, btl.enemy)
  local files = {
    ["mods/probe/manifest.json"] = Json.encode({
      id = "probe",
      name = "Probe",
      version = "1.0.0",
      api = level or 2,
      entry = "main.lua",
    }),
    ["mods/probe/main.lua"] = [[return function(mod)
      assert(type(mod.battle.snapshot)=="function")
      mod.exports.api=mod
      mod.content.moves:register("MOVE_9000", {id="MOVE_9000", name="Late move", pp=10, power=10,
        accuracy=100, type="NORMAL", effect="NO_ADDITIONAL_EFFECT"})
    end]],
  }
  local fs = {
    read = function(p)
      return files[p]
    end,
    load = function(p)
      return loadstring(files[p], p)
    end,
    getDirectoryItems = function(p)
      return p == "mods" and { "probe" } or {}
    end,
    getInfo = function(p)
      return (p == "mods" or p == "mods/probe") and { type = "directory" } or files[p] and { type = "file" }
    end,
  }
  local loader = Loader.new({ fs = fs, dev = false })
  local resolves = 0
  loader._game = function()
    resolves = resolves + 1
    return game
  end
  assert(loader:load(data), table.concat(loader.errors, "; "))
  return loader.apis.probe, loader, game, btl, battler, { s, m, item }, function()
    return resolves
  end
end

-- Freeze the whole graph as table identities + raw entries, including cycles.
local function freeze(root)
  local graph = {}
  local function visit(value)
    if type(value) ~= "table" or graph[value] then
      return
    end
    local entries = {}
    graph[value] = entries
    for key, child in pairs(value) do
      entries[key] = child
      visit(child)
    end
  end
  visit(root)
  return function()
    for tbl, entries in pairs(graph) do
      for key, value in pairs(entries) do
        if tbl[key] ~= value then
          return false
        end
      end
      for key in pairs(tbl) do
        if entries[key] == nil then
          return false
        end
      end
    end
    return true
  end
end

local function forbidden()
  error("snapshot crossed into gameplay")
end
local oldRandom = math.random
math.random = forbidden
for _, version in ipairs(GameVersion.ORDER) do
  local api, loader, game, b, battler, ids, resolves = boot(version)
  local label = version .. ": "
  T.eq(resolves(), 0, label .. "entry can capture facade before Game exists")
  if api.supports then
    T.eq(api:supports("battle", "snapshot"), true, label .. "snapshot capability")
    T.eq(api:supports("battle", "submit"), false, label .. "no input submission")
    T.eq(resolves(), 0, label .. "probe does not resolve Game")
  end
  T.eq(api.battle, api.battle, label .. "stable facade")
  T.eq(api.battle.submit, nil, label .. "no mutation method")
  local no, reason = api.battle:snapshot()
  T.eq(no, nil, label .. "no battle")
  T.eq(reason, "no battle", label .. "no battle reason")
  game.stack.states = { { battle = b, phase = "menu", player = b.player, enemy = b.enemy } }
  T.eq(api.battle:snapshot(), nil, label .. "a UI holding battle is not battle")
  game.stack.states = { b }
  b.rng = forbidden
  b.menuLockedAction, b.fightLockedAction, b.menuBattler, b.playerHasPP =
    forbidden, forbidden, forbidden, forbidden
  b.catchAttempt, b.ballDef, b.moveDef, b.choosingSlotNow = forbidden, forbidden, forbidden, forbidden
  b.volatile, b.enemyAction, b.update, b.draw = forbidden, forbidden, forbidden, forbidden
  local unchanged = freeze(game)
  local snap = api.battle:snapshot()
  T.check(unchanged(), label .. "complete game graph unchanged")
  T.eq(snap.revision, 1, label .. "first revision")
  T.eq(snap.prompt, "menu", label .. "menu phase")
  T.eq(snap.double, false, label .. "single battle")
  T.eq(snap.active, 0, label .. "left actor")
  T.eq(snap.kind, "wild", label .. "wild kind")
  T.eq(snap.turn, 0, label .. "before first turn")
  T.eq(snap.catchable, true, label .. "single wild target")
  T.eq(#snap.battlers, 2, label .. "both occupied slots")
  T.eq(snap.player.species, "PIKACHU", label .. "portable species")
  T.eq(snap.player.name, "Left", label .. "battler display name")
  T.eq(snap.player.hp, 19, label .. "logical HP")
  T.eq(snap.player.maxHp, 23, label .. "max HP")
  T.eq(snap.player.status, "poison", label .. "portable status")
  T.eq(snap.player.stats.specialAttack, GameVersion.generation() == 1 and 12 or 14, label .. "special attack")
  T.eq(
    snap.player.stats.specialDefense,
    GameVersion.generation() == 1 and 12 or 15,
    label .. "special defense"
  )
  T.eq(snap.player.partyIndex, 1, label .. "party slot by identity")
  T.eq(snap.party[1].active, true, label .. "lead active")
  T.eq(snap.party[2].active, false, label .. "bench inactive")
  T.eq(snap.party[2].slot, 2, label .. "party slot one based")
  T.eq(snap.moves[1].id, "TACKLE", label .. "portable move")
  T.eq(snap.moves[1].maxPp, 42, label .. "PP Up maximum")
  T.eq(snap.moves[1].pp, 29, label .. "current PP")
  T.eq(snap.moves[1].disabled, false, label .. "unrestricted move")
  T.eq(snap.moves[1].accuracy, 95, label .. "base accuracy")
  T.eq(#snap.items, 3, label .. "positive inventory deduplicated")
  T.eq(snap.items[1].id, "POKE_BALL", label .. "portable ball and bag order")
  T.eq(snap.items[1].count, 3, label .. "inventory quantity")
  T.eq(snap.items[1].ball, true, label .. "ball classification")
  T.eq(snap.items[2].id, "A_EXTRA", label .. "unlisted inventory sorted")
  T.eq(snap.items[3].id, "Z_EXTRA", label .. "stable inventory order")
  T.eq(snap.items[1].catchChance, nil, label .. "no guessed catch preview")
  T.eq(snap.items[1].needsTarget, nil, label .. "no guessed item eligibility")
  T.same(api.battle:snapshot(), snap, label .. "unchanged reads stable")
  snap.player.hp = 0
  snap.player.native.hp = 0
  snap.player.native.extension.flag = true
  snap.moves[1].pp = 0
  snap.items[1].count = 0
  snap.party[1].stats.hp = 0
  snap.player.types[1] = "WATER"
  snap.player.stages.attack = 6
  local clean = api.battle:snapshot()
  T.eq(clean.revision, 1, label .. "caller writes do not alter revision")
  T.eq(clean.player.hp, 19, label .. "caller writes isolated")
  T.eq(clean.player.native.extension.flag, false, label .. "false preserved in diagnostics")
  T.eq(clean.moves[1].pp, 29, label .. "move tables isolated")
  T.eq(clean.items[1].count, 3, label .. "item tables isolated")
  T.eq(clean.party[1].stats.hp, 23, label .. "party stats isolated")
  T.eq(clean.player.types[1], "ELECTRIC", label .. "types isolated")
  T.eq(clean.player.stages.attack, nil, label .. "stages isolated")

  b.frame, b.player.shownHP, b.player.picAnim = 99, 12, { tick = 5 }
  T.eq(api.battle:snapshot().revision, 1, label .. "animation ticks excluded")
  b.player.mon.hp = 18
  local changed = api.battle:snapshot()
  T.eq(changed.revision, 2, label .. "HP changes revision")
  T.eq(changed.player.hp, 18, label .. "new logical HP visible")
  T.eq(clean.player.hp, 19, label .. "old result remains detached")
  b.turnCount = 1
  T.eq(api.battle:snapshot().turn, 1, label .. "turn number updates")
  local rev = api.battle:snapshot().revision
  game.stack.states[#game.stack.states + 1] = { battle = b }
  T.eq(api.battle:snapshot().prompt, "locked", label .. "covered battle locked")
  T.check(api.battle:snapshot().revision > rev, label .. "coverage changes revision")
  table.remove(game.stack.states)
  local cases = {
    { "intro", "locked" },
    { "messages", "locked" },
    { "moveSelect", "moves" },
    { "targetSelect", "target" },
    { "mimicSelect", "mimic" },
    { "finished", "locked" },
  }
  for _, c in ipairs(cases) do
    b.phase = c[1]
    T.eq(api.battle:snapshot().prompt, c[2], label .. "phase " .. c[1])
  end
  b.phase = "messages"
  b.current = { text = "Current text" }
  b.msgPrompt = true
  b.msgPromptWait = 3
  T.eq(api.battle:snapshot().prompt, "locked", label .. "pre-advance delay")
  b.msgPromptWait = 0
  T.eq(api.battle:snapshot().prompt, "advance", label .. "manual message advance")
  T.eq(api.battle:snapshot().messageSource, "Current text", label .. "current message source")
  T.eq(api.battle:snapshot().message, nil, label .. "no invented visible message")
  game.data.font =
    { charmap = { { code = 128, seq = "A" }, { code = 129, seq = "B" }, { code = 130, seq = "C" } } }
  b.shown = { { 128, 129 }, { 130 } }
  local text = api.battle:snapshot()
  T.same(text.message, { "AB", "C" }, label .. "only revealed glyphs in visible message")
  b.shown[2][2] = 128
  T.check(api.battle:snapshot().revision > text.revision, label .. "revealed glyph changes revision")
  T.same(text.message, { "AB", "C" }, label .. "older visible message detached")
  b.shown[1][1] = 999999
  T.eq(api.battle:snapshot().message, nil, label .. "unknown glyph is not guessed")
  game.data.font.pages = { extra = { charmap = { { code = 999999, seq = "Ω" } } } }
  T.same(api.battle:snapshot().message, { "ΩB", "CA" }, label .. "font page charmap read")
  local unicode = package.loaded["src.translation.UnicodeFont"]
  package.loaded["src.translation.UnicodeFont"] = { chars = { [-1] = "漢" } }
  b.shown = { { -1 } }
  T.same(api.battle:snapshot().message, { "漢" }, label .. "already loaded Unicode mapping read")
  package.loaded["src.translation.UnicodeFont"] = unicode
  game.data.font = { source = "Gen2 scaffold" }
  b.shown = { { 65, 66 } }
  T.same(api.battle:snapshot().message, { "AB" }, label .. "scaffold ASCII glyphs read")
  game.stack.states[2] = { battle = b }
  T.eq(api.battle:snapshot().message, nil, label .. "covered screen has no guessed visible message")
  game.stack.states[2] = nil
  b.shown = nil
  b.current.choice = function() end
  T.eq(api.battle:snapshot().prompt, "locked", label .. "choice is its own controller")
  b.current = nil
  b.msgPrompt = nil
  b.phase = "menu"
  for _, flag in ipairs({ "waitingUI", "demo", "pokedudeDemo", "palace", "arena" }) do
    b[flag] = true
    T.eq(api.battle:snapshot().prompt, "locked", label .. flag .. " locked")
    b[flag] = nil
  end
  for _, flag in ipairs({ "mustRecharge", "charging", "rageMove", "thrashTurns" }) do
    b.player[flag] = 1
    T.eq(api.battle:snapshot().prompt, "locked", label .. flag .. " locked")
    b.player[flag] = nil
  end
  b.bw = true
  b.player.bwSkyDropped = true
  T.eq(api.battle:snapshot().prompt, "locked", label .. "Sky Drop lock")
  b.bw = nil
  b.player.bwSkyDropped = nil
  b.safari = { balls = 3 }
  T.eq(api.battle:snapshot().kind, "safari", label .. "Safari battle kind")
  T.eq(api.battle:snapshot().safariBalls, 3, label .. "Safari ball count")
  T.eq(api.battle:snapshot().prompt, "safari", label .. "Safari prompt")
  b.safari.balls = 0
  T.eq(api.battle:snapshot().prompt, "locked", label .. "no Safari balls")
  b.safari = nil
  b.demo = true
  T.eq(api.battle:snapshot().kind, "oldman", label .. "automatic capture demo kind")
  b.demo = nil
  b.ghost = true
  T.eq(api.battle:snapshot().kind, "ghost", label .. "ghost kind")
  b.ghost = nil
  b.menuIndex = 2
  b.moveIndex = 3
  b.moveSwapIndex = 1
  local cursors = api.battle:snapshot()
  T.eq(cursors.menuIndex, 2, label .. "menu cursor")
  T.eq(cursors.moveIndex, 3, label .. "move cursor")
  T.eq(cursors.moveSwapIndex, 1, label .. "reorder cursor")
  b.menuIndex = 1
  T.check(api.battle:snapshot().revision > cursors.revision, label .. "cursor changes revision")
  for _, flag in ipairs({ "ghost", "noCatch", "result" }) do
    b[flag] = true
    T.eq(api.battle:snapshot().catchable, false, label .. flag .. " uncatchable")
    b[flag] = nil
  end
  b.kind = "trainer"
  T.eq(api.battle:snapshot().catchable, false, label .. "trainer uncatchable")
  b.kind = "wild"
  b.phase = "moveSelect"
  for _, guard in ipairs({ "disable", "pp", "taunt", "torment" }) do
    if guard == "disable" then
      b.player.disabledSlot = 1
    end
    if guard == "pp" then
      b.player.curMoves[1].pp = 0
    end
    if guard == "taunt" then
      b.player.tauntTurns = 2
      game.data.moves[ids[2]].power = 0
    end
    if guard == "torment" then
      b.player.tormented = true
      b.player.lastMove = ids[2]
    end
    T.eq(api.battle:snapshot().moves[1].disabled, true, label .. guard .. " menu restriction")
    b.player.disabledSlot = nil
    b.player.curMoves[1].pp = 29
    b.player.tauntTurns = nil
    game.data.moves[ids[2]].power = 40
    b.player.tormented = nil
    b.player.lastMove = nil
  end
  -- Native alias keys may be split during merging; a name patch must not
  -- rename a portable ID. Later registrations still appear in fresh reads.
  game.data.pokemon[ids[1]].name = "Renamed presentation"
  T.eq(api.battle:snapshot().player.species, "PIKACHU", label .. "name patches preserve identity")
  local originalMoves = b.player.curMoves
  b.player.curMoves = { { id = "MOVE_9000", pp = 8 } }
  T.eq(api.battle:snapshot().moves[1].id, "LATE_MOVE", label .. "late mod ID resolved")
  b.player.curMoves = originalMoves
  b.bw = { field = {}, sides = { {}, {} } }
  T.eq(api.battle:snapshot().moves[1].disabled, nil, label .. "BW eligibility remains unknown")
  b.player.disabledSlot = 1
  T.eq(api.battle:snapshot().moves[1].disabled, true, label .. "BW known common restriction")
  b.player.disabledSlot = nil
  b.bw = nil
  b.player.curMoves[1].ppUps = 99
  T.eq(api.battle:snapshot().moves[1].maxPp, 56, label .. "PP Ups clamped as native engine")
  b.player.curMoves[1].ppUps = -1
  T.eq(api.battle:snapshot().moves[1].maxPp, 35, label .. "negative PP Ups clamped")
  b.player.curMoves[1].ppUps = 1
  -- Transform changes the in-battle view while the stored party keeps its moves/stats.
  game.data.moves.COPIED = { name = "Copied", pp = 10, power = 50, type = "WATER" }
  b.player.curMoves = { { id = "COPIED", pp = 5 } }
  b.player.curStats = { hp = 23, attack = 90, special = 80 }
  b.player.species = "COPIED_SPECIES"
  b.player.curTypes = { "WATER" }
  local transformed = api.battle:snapshot()
  T.eq(transformed.moves[1].id, "COPIED", label .. "current transformed move")
  T.eq(transformed.party[1].moves[1].id, "TACKLE", label .. "stored party move")
  T.eq(transformed.player.battleStats.attack, 90, label .. "current transformed stats")
  T.eq(transformed.player.stats.attack, 10, label .. "base stats preserved")
  T.eq(transformed.player.displaySpecies, "COPIED_SPECIES", label .. "display species separate")
  T.eq(transformed.player.species, "PIKACHU", label .. "original species preserved")
  -- All four native positional slots, including a missing left flank.
  b.double = true
  b:placeBattler(2, battler(game.save.party[2]))
  b:placeBattler(3, battler(b.enemyParty[2]))
  b.choosingSlot = 2
  b.phase = "menu"
  local double = api.battle:snapshot()
  T.eq(double.double, true, label .. "doubles flag")
  T.eq(#double.battlers, 4, label .. "four occupied battlers")
  T.eq(double.active, 2, label .. "second chooser")
  T.eq(double.player.name, "Right", label .. "player follows chooser")
  T.eq(double.player.partyIndex, 2, label .. "second chooser party index")
  T.eq(double.catchable, false, label .. "cannot aim at two wild foes")
  T.eq(double.party[2].active, true, label .. "both player slots active")
  b.phase = "targetSelect"
  b.targetChoices = { b.enemy, b.sides[2].battlers[2], b.player }
  b.targetIndex = 2
  T.same(api.battle:snapshot().targets, { 1, 3, 0 }, label .. "target IDs, not array positions")
  T.eq(api.battle:snapshot().targetIndex, 2, label .. "target cursor")
  b:placeBattler(0, nil)
  b:placeBattler(1, nil)
  b.choosingSlot = nil
  b.phase = "menu"
  local missing = api.battle:snapshot()
  T.eq(missing.active, 2, label .. "right flank after left faint")
  T.eq(missing.enemy, nil, label .. "missing enemy left not silently aliased")
  T.eq(missing.catchable, true, label .. "one wild foe remaining")
  T.eq(#missing.battlers, 2, label .. "missing slots omitted")
  T.eq(missing.battlers[1].id, 2, label .. "battler identity survives sparse slots")
  b.phase = "mimicSelect"
  b.mimicMoves = { { id = ids[2], slot = 3 } }
  b.mimicIndex = 1
  local mimic = api.battle:snapshot()
  T.eq(mimic.mimicMoves[1].id, "TACKLE", label .. "portable mimic ID")
  T.eq(mimic.mimicMoves[1].slot, 3, label .. "original mimic move slot")
  b.phase = "menu"
  local ally = b.sides[1].battlers[2]
  ally.ally = true
  b.ally = { party = { ally.mon } }
  local withAlly = api.battle:snapshot()
  T.eq(withAlly.party[2].active, false, label .. "NPC ally not player active party")
  T.eq(withAlly.battlers[1].ally, true, label .. "NPC ally marked")
  T.eq(withAlly.prompt, "locked", label .. "NPC controlled actor menu locked")
  ally.ally = nil
  b.ally = nil
  b.kind = "link"
  b.playerParty = { game.save.party[2] }
  local link = api.battle:snapshot()
  T.eq(#link.party, 1, label .. "link uses clamped battle party")
  T.eq(link.party[1].nickname, "Right", label .. "link party is actual participant")
  T.eq(link.prompt, "locked", label .. "link controller owns input")
  b.kind = "wild"
  b.playerParty = nil
  -- Snapshot diagnostics discard executable values and remain cycle-safe.
  local raw = game.save.party[2]
  raw.extension.self = raw.extension
  raw.extension.fn = forbidden
  raw.extension[{}] = "hidden"
  setmetatable(raw.extension, { __index = { secret = true } })
  local cyc = api.battle:snapshot()
  T.eq(cyc.party[2].native.extension.self, cyc.party[2].native.extension, label .. "cycles copied")
  T.eq(cyc.party[2].native.extension.fn, nil, label .. "function dropped")
  T.eq(getmetatable(cyc.party[2].native.extension), nil, label .. "metatable dropped")
  T.eq(cyc.party[2].native.extension.secret, nil, label .. "no inherited value")
  T.eq(api.battle:snapshot().revision, cyc.revision, label .. "cyclic record stable revision")
  local last = cyc.revision
  game.stack.states = {}
  T.eq(api.battle:snapshot(), nil, label .. "battle exit")
  game.stack.states = { b }
  T.check(api.battle:snapshot().revision > last, label .. "re-entry invalidates revision")
  last = api.battle:snapshot().revision
  local replacement = setmetatable(Merge.deepCopy(b), BattleState)
  game.stack.states = { replacement }
  T.check(api.battle:snapshot().revision > last, label .. "identical new battle invalidates revision")
  -- A previously captured facade follows the loader's current Game.
  local other = { data = game.data, save = game.save, stack = game.stack }
  loader._game = function()
    return other
  end
  last = api.battle:snapshot().revision
  loader._game = function()
    return game
  end
  T.check(api.battle:snapshot().revision > last, label .. "Game replacement invalidates revision")
end
math.random = oldRandom

-- Exercise constructors and a native damage action with the committed fixture
-- dataset, rather than asserting only hand-built record shapes.
love = require("tests.love_stub")
local Fixtures = require("tests.modkit.fixtures")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Font = require("src.render.Font")
local function native(version, trainer)
  local api, loader = boot(version)
  love = require("tests.love_stub")
  math.randomseed(12345)
  local data = Fixtures.fresh()
  Font.load(data)
  local save = SaveData.newGame()
  save.party = { Pokemon.new(data, "FIXMON_A", 20), Pokemon.new(data, "FIXMON_B", 12) }
  local game = {
    data = data,
    save = save,
    input = {
      wasPressed = function()
        return false
      end,
    },
    stack = {
      states = {},
      push = function() end,
      pop = function() end,
      top = function(self)
        return self.states[#self.states]
      end,
    },
  }
  local b = trainer and BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
    or BattleState.newWild(game, "FIXMON_C", 10)
  game.stack.states = { b }
  loader._game = function()
    return game
  end
  local calls = 0
  b.rng = function(_, high)
    calls = calls + 1
    return high
  end
  return api, game, b, function()
    return calls
  end
end
for _, version in ipairs(GameVersion.ORDER) do
  for _, trainer in ipairs({ false, true }) do
    local api, game, b, calls = native(version, trainer)
    local unchanged = freeze(game)
    local rngBefore = calls()
    local oldLoveRandom, oldLuaRandom = love.math.random, math.random
    love.math.random, math.random = forbidden, forbidden
    local Runtime = require("src.mods.Runtime")
    local oldEmit, oldCall = Runtime.emit, Runtime.call
    Runtime.emit, Runtime.call = forbidden, forbidden
    local loaded = {}
    for name in pairs(package.loaded) do
      loaded[name] = true
    end
    local s = api.battle:snapshot()
    for _ = 1, 10 do
      T.eq(api.battle:snapshot().revision, s.revision, version .. ": repeated native snapshot stable")
    end
    local noNewModules = true
    for name in pairs(package.loaded) do
      if not loaded[name] then
        noNewModules = false
      end
    end
    T.check(noNewModules, version .. ": snapshot loads no modules")
    Runtime.emit, Runtime.call = oldEmit, oldCall
    T.check(unchanged(), version .. ": native constructor graph unchanged")
    T.eq(calls(), rngBefore, version .. ": native RNG unchanged")
    T.eq(s.kind, trainer and "trainer" or "wild", version .. ": native constructor kind")
    T.eq(s.player.species, "FIXMON_A", version .. ": real Pokemon record")
    T.eq(s.player.maxHp, b.player.mon.stats.hp, version .. ": constructor HP")
    T.eq(s.moves[1].id, b.player.curMoves[1].id, version .. ": constructor moves")
    T.eq(s.catchable, not trainer, version .. ": constructor catchability")
    love.math.random, math.random = oldLoveRandom, oldLuaRandom
    -- The same native action on an independently constructed control battle
    -- must produce the same HP, PP, queue and RNG consumption.
    local _, _, control, controlCalls = native(version, trainer)
    b:performMove(b.player, b.enemy, b.player.curMoves[1])
    control:performMove(control.player, control.enemy, control.player.curMoves[1])
    T.eq(b.enemy.mon.hp, control.enemy.mon.hp, version .. ": action damage unaffected")
    T.eq(b.player.curMoves[1].pp, control.player.curMoves[1].pp, version .. ": action PP unaffected")
    T.eq(calls(), controlCalls(), version .. ": action RNG consumption unaffected")
    T.eq(#b.queue, #control.queue, version .. ": action queue unaffected")
    local later = api.battle:snapshot()
    T.eq(later.enemy.hp, b.enemy.mon.hp, version .. ": snapshot follows native damage")
    T.check(later.revision > s.revision, version .. ": native damage changes revision")
  end
end
local api = boot("crystal", 1)
T.eq(type(api.battle.snapshot), "function", "API 1 mods also get additive reader")
GameVersion.set(oldVersion)
love = oldLove
T.finish("battle snapshots")
