local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local function configure(data, engine, ids, rom, names)
    ids.BEAT_UP, names[251] = engine == "gen1" and "BEAT_UP" or "MOVE_251", "BEAT_UP"
    if engine == "gen1" then
      local d =
        { effect = 154, power = 10, type = 17, target = 0, priority = 0, accuracy = 100, pp = 20, flags = 2 }
      data.gen3Moves._rom[251], rom[251], data.gen3Pokemon._moveNames[251] = d, d, "BEAT_UP"
      data.gen3Pokemon._stats[4] = { hp = 50, atk = 60, def = 40, spe = 50, spa = 50, spd = 50 }
    else
      data.moves.MOVE_251 = {
        id = "MOVE_251",
        index = 251,
        name = "BEAT_UP",
        gen3Effect = 154,
        effect = "BEAT_UP_EFFECT",
        power = 10,
        type = "DARK",
        target = 0,
        priority = 0,
        accuracy = 100,
        accuracyRaw = 255,
        pp = 20,
        protectAffected = true,
      }
      data.pokemon.CHARMANDER.baseStats.attack, data.pokemon.CHARMANDER.baseStats.defense = 60, 40
      data.pokemon.CHARMANDER.baseStats.spatk, data.pokemon.CHARMANDER.baseStats.spdef = 50, 50
      data.pokemon.CHARMANDER.evYield = { attack = 1 }
      data.type_chart.types = data.type_chart.types or {}
      data.type_chart.types.DARK = { id = "DARK", index = 17, category = "special" }
      for id, row in pairs({
        SCOPE_LENS = { 198, "SCOPE_LENS" },
        CUSTOM_SCOPE = { 1198, "SCOPE_LENS" },
        LUCKY_PUNCH = { 222, "LUCKY_PUNCH" },
        STICK = { 225, "STICK" },
        LANSAT_BERRY = { 173, "CRITICAL_UP" },
      }) do
        data.items[id] = { index = row[1], name = id, holdEffect = row[2], holdEffectParam = 4 }
      end
      for name, index in pairs({ RATTATA = 19, PIDGEY = 16, CHANSEY = 113, FARFETCH_D = 83 }) do
        local d = require("src.mods.Merge").deepCopy(data.pokemon.CHARMANDER)
        d.id, d.name, d.index, d.dex, d.evolutions = name, name, index, index, {}
        data.pokemon[name] = d
      end
    end
  end
  local f =
    dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, 3, "unified", configure)
  local T = f.T
  local sourceItems, oldItems
  if native then
    sourceItems = require("src.core.game3.items_data")
    oldItems = { sourceItems._byId, sourceItems._byName, sourceItems._pack }
    local raw = { [1198] = { name = "CUSTOM SCOPE", pocket = "ITEMS", holdEffect = 41, holdEffectParam = 0 } }
    sourceItems._byId, sourceItems._byName, sourceItems._pack = raw, {}, { items = raw }
  end
  local rows, hits, draws, calls, contexts = {}, {}, {}, {}, {}
  local policy, liveBattle
  local function criticalHook(nextCrit, context)
    calls.crit = calls.crit + 1
    contexts[#contexts + 1] = {
      battle = context.battle ~= nil,
      target = context.target and context.target.mon.nickname,
      move = context.moveId,
      number = context.moveNum,
      stage = context.stage,
    }
    if policy == "force" then
      return true
    end
    local result = nextCrit(context)
    if policy == "after" then
      return true
    end
    if policy == "suppress" then
      return false
    end
    return result
  end
  local stopCrit = f.e.api.hooks:wrap("battle.crit", criticalHook)
  local stopDamage = f.e.api.hooks:wrap("battle.damage", function(nextDamage, ...)
    calls.damage = calls.damage + 1
    return nextDamage(...)
  end)
  local stopHit = f.e.api.events:on("battle.damage_dealt", function(e)
    hits[#hits + 1] = {
      damage = e.damage,
      crit = e.crit,
      user = e.user.mon.nickname,
      target = e.target.mon.nickname,
      kind = e.kind,
      substitute = e.substitute or false,
      oakFlags = liveBattle.oakMsgFlags or 0,
    }
  end)
  local function at(b, id)
    return native and b.battlers[id] or b:battlerAt(id)
  end
  local function put(b, id, a)
    if native then
      b.battlers[id] = a
    else
      b:placeBattler(id, a)
    end
  end
  local specs = {
    { name = "ordinary", kind = "normal" },
    { name = "ordinary-unhooked", kind = "normal", noHook = true },
    { name = "ordinary-special", kind = "normal", special = true },
    { name = "scope-lens", kind = "normal", item = "SCOPE_LENS", stage = 1 },
    { name = "scope-native-id", kind = "normal", item = "SCOPE_LENS", noEffect = true, stage = 1 },
    { name = "custom-scope", kind = "normal", item = "CUSTOM_SCOPE", stage = 0 },
    {
      name = "lucky-punch-current-species",
      kind = "normal",
      item = "LUCKY_PUNCH",
      species = "CHANSEY",
      speciesNum = 113,
      stage = 2,
    },
    {
      name = "stick-current-species",
      kind = "normal",
      item = "STICK",
      species = "FARFETCH_D",
      speciesNum = 83,
      stage = 2,
    },
    { name = "high-critical", kind = "normal", high = true, stage = 1 },
    { name = "stage-cap", kind = "normal", high = true, focus = true, item = "SCOPE_LENS", stage = 4 },
    { name = "lansat", kind = "normal", item = "LANSAT_BERRY", berry = true, stage = 2 },
    {
      name = "lansat-focus-energy",
      kind = "normal",
      item = "LANSAT_BERRY",
      berry = true,
      focus = true,
      stage = 2,
    },
    { name = "focus-energy", kind = "normal", focus = true },
    { name = "armor", kind = "normal", armor = true },
    { name = "forced-hook", kind = "normal", hook = "force" },
    { name = "suppressed-hook", kind = "normal", hook = "suppress" },
    { name = "after-hook", kind = "normal", hook = "after" },
  }
  local extra = version == "firered"
      and {
        { name = "pokedude", kind = "pokedude" },
        { name = "pokedude-unhooked", kind = "pokedude", noHook = true },
        { name = "pokedude-focus", kind = "pokedude", focus = true },
        { name = "pokedude-forced", kind = "pokedude", hook = "force" },
        { name = "pokedude-after", kind = "pokedude", hook = "after" },
        { name = "pokedude-armor", kind = "pokedude", armor = true },
        { name = "old-man-control", kind = "oldman" },
        { name = "oak-before", kind = "oak" },
        { name = "oak-after", kind = "oak", flags = 1 },
        { name = "oak-substitute", kind = "oak", substitute = true },
      }
    or {
      { name = "first-battle", kind = "first" },
      { name = "first-unhooked", kind = "first", noHook = true },
      { name = "first-battle-after-damage", kind = "first", flags = 1 },
      { name = "first-forced", kind = "first", hook = "force" },
      { name = "first-after", kind = "first", hook = "after" },
      { name = "first-armor", kind = "first", armor = true },
      { name = "first-kind-only", kind = "firstKind" },
      { name = "wally", kind = "wally" },
      { name = "wally-unhooked", kind = "wally", noHook = true },
      { name = "wally-forced", kind = "wally", hook = "force" },
      { name = "wally-after", kind = "wally", hook = "after" },
      { name = "wally-focus", kind = "wally", focus = true },
    }
  for _, s in ipairs(extra) do
    specs[#specs + 1] = s
  end
  for _, spec in ipairs(specs) do
    for id = 0, 3 do
      for _, name in ipairs({ "TACKLE", "BEAT_UP" }) do
        hits, draws, calls, contexts, policy = {}, {}, { crit = 0, damage = 0 }, {}, spec.hook
        local b = f.fresh("TACKLE", { enemy = true }).battle
        if native then
          if spec.kind == "first" or spec.kind == "oak" then
            b.firstBattle = true
          end
          if spec.kind == "pokedude" then
            b.pokedude = true
          end
          if spec.kind == "oldman" then
            b.oldManTutorial = true
          end
          b.kinds = {}
          if spec.kind == "first" or spec.kind == "firstKind" then
            b.kinds.firstBattle = "birch"
          end
          if spec.kind == "wally" then
            b.kinds.tutorial = "wally"
          end
        elseif spec.kind == "first" then
          f.data.constants.gen3FirstBattle = { species = "CHARMANDER", level = 30, canLose = true }
          local yielded = 0
          local ctx = {
            game = f.game,
            save = f.game.save,
            runner = {
              yield = function()
                yielded = yielded + 1
              end,
            },
            overworld = {
              pushBattle = function(_, battle)
                b = battle
              end,
            },
          }
          T.eq(require("src.script.Gen3Commands").firstBattle(ctx), true, "native first-battle script starts")
          T.eq(yielded, 1, "native script yields after creating its battle")
          T.eq(b.firstBattle, true, "first-battle metadata survives the native script and constructor")
        elseif spec.kind == "firstKind" then
          b =
            require("src.battle.BattleState").newWild(f.game, "CHARMANDER", 30, { firstBattleKind = "birch" })
        elseif spec.kind == "pokedude" then
          b = require("src.battle.BattleState").newPokedudeDemo(f.game, "battle")
          T.check(b.pokedudeDemo ~= nil, "native Teachy TV constructor supplies its controller state")
        elseif spec.kind == "wally" then
          b:makeDudeDemo("WALLY")
        elseif spec.kind == "oldman" then
          b:makeOldManDemo("OLD MAN")
        elseif spec.kind == "oak" then
          b.firstBattle = true
        end
        b.oakMsgFlags = spec.flags or 0
        b.double = true
        if not native then
          b:syncSides()
        end
        for pos = 2, 3 do
          local mon = require("src.mods.Merge").deepCopy(at(b, pos - 2).mon)
          local a = native
              and require("src.core.game3.battle.state").makeBattler(
                mon,
                pos == 2 and "player" or "enemy",
                { id = pos, partyIndex = 2 }
              )
            or require("src.battle.BattleState").makeBattler(f.data, mon, pos == 2)
          put(b, pos, a)
        end
        if not native then
          b:syncSides()
        end
        for pos = 0, 3 do
          local a = at(b, pos)
          a.mon.nickname, a.mon.hp, a.mon.level = "P" .. pos, 10000, 30
          if native then
            a.species, a.mon.species, a.mon.maxHp = 4, 4, 10000
            a.type1, a.type2, a.ability, a.mon.ability = 0, 0, 0, 0
            a.mon.moves, a.mon.pp, a.mon.maxPp = { 33, 251 }, { 10, 20 }, { 10, 20 }
            for _, k in ipairs({ "attack", "defense", "speed", "spAtk", "spDef" }) do
              a.mon[k] = 50
            end
          else
            a.species, a.mon.species = "CHARMANDER", "CHARMANDER"
            a.curStats =
              { hp = 10000, attack = 50, defense = 50, speed = 50, special = 50, spatk = 50, spdef = 50 }
            a.mon.stats, a.curTypes, a.abilityOverride = a.curStats, { "NORMAL" }, false
            a.curMoves = { { id = f.ids.TACKLE, pp = 10 }, { id = f.ids.BEAT_UP, pp = 20 } }
            a.mon.moves = a.curMoves
          end
        end
        if native then
          b.playerParty, b.foeParty = { at(b, 0).mon, at(b, 2).mon }, { at(b, 1).mon, at(b, 3).mon }
        else
          f.game.save.party, b.enemyParty = { at(b, 0).mon, at(b, 2).mon }, { at(b, 1).mon, at(b, 3).mon }
        end
        local user, target = at(b, id), at(b, id % 2 == 0 and 1 or 0)
        liveBattle = b
        if native then
          require("src.core.game3.battle.moves")._rom[33].type = spec.special and 17 or 0
          require("src.core.game3.battle.moves")._rom[33].effect = spec.high and 43 or 0
          if spec.special then
            user.type1, user.type2 = 17, 17
          end
        else
          f.data.moves[f.ids.TACKLE].type = spec.special and "DARK" or "NORMAL"
          local move = f.data.moves[f.ids.TACKLE]
          move.effect, move.gen3Effect, move.highCrit =
            spec.high and "HIGH_CRITICAL_EFFECT" or "NO_ADDITIONAL_EFFECT", spec.high and 43 or 0, spec.high
          f.data.items.SCOPE_LENS.holdEffect = spec.noEffect and "NONE" or "SCOPE_LENS"
          if spec.special then
            user.curTypes = { "DARK" }
          end
        end
        user.focusEnergy = spec.focus
        if spec.item then
          if native then
            local item = ({
              SCOPE_LENS = 198,
              CUSTOM_SCOPE = 1198,
              LUCKY_PUNCH = 222,
              STICK = 225,
              LANSAT_BERRY = 173,
            })[spec.item]
            user.item, user.mon.item = item, item
          else
            user.items, user.mon.item = f.data.items, spec.item
          end
        end
        if spec.species then
          user.species = native and spec.speciesNum or spec.species
        end
        if spec.berry then
          user.mon.hp = 2500
          local active
          if native then
            active = require("src.core.game3.battle.held_items").normal(
              require("src.core.game3.battle.adapter").new(b),
              user,
              false
            )
          else
            active = b:holdItemTrigger(user, "turn")
          end
          T.eq(active, spec.focus ~= true, "Lansat activates only without existing Focus Energy")
          local held = native and user.item == 173 or not native and user.mon.item == "LANSAT_BERRY"
          T.eq(held, spec.focus == true, "already focused users keep their unconsumed berry")
          T.eq(user.focusEnergy, true, "the native berry producer uses the Focus Energy marker")
        end
        if spec.armor then
          if native then
            target.ability, target.mon.ability = 4, 4
          else
            target.abilityOverride = "BATTLE_ARMOR"
          end
        end
        if spec.substitute then
          target.substituteHP = 1
        end
        b.rng = function(lo, hi)
          if lo == 85 and hi == 100 then
            draws[#draws + 1] = { kind = "variation" }
            return 100
          end
          if
            (lo == 0 and (hi == 15 or hi == 7 or hi == 3 or hi == 2 or hi == 1))
            or (lo == 1 and (hi == 16 or hi == 8 or hi == 4 or hi == 3 or hi == 2))
          then
            draws[#draws + 1] = { kind = "critical", den = hi - lo + 1 }
            return lo
          end
          return lo or 0
        end
        f.e.choose(function()
          return { move = name, target = id % 2 == 0 and 1 or 0 }
        end)
        local slot = name == "TACKLE" and 1 or 2
        if spec.noHook then
          stopCrit()
        end
        if native then
          local C = require("src.core.game3.battle.commands")
          local action = id % 2 == 0 and C.playerAction(b, 1, slot, id, id % 2 == 0 and 1 or 0)
            or C.enemyAction(b, id)
          require("src.core.game3.battle.engine").resolveMove(
            id,
            action.target,
            action.move,
            action.slot,
            require("src.core.game3.battle.adapter").new(b),
            b,
            {}
          )
        else
          if id % 2 == 0 then
            b.chosenTargets = { [id] = target }
          end
          local action = id % 2 == 0 and user.curMoves[slot] or b:enemyAction(user)
          b:executeAction(user, target, action)
        end
        if spec.noHook then
          stopCrit = f.e.api.hooks:wrap("battle.crit", criticalHook)
        end
        local ordinary = name == "TACKLE"
        local guarded = spec.kind == "first" or spec.kind == "firstKind" or spec.kind == "wally"
        local oakPending = spec.kind == "oak" and not spec.flags
        local expected, criticalDraws = {}, 0
        local force = ordinary and (spec.hook == "force" or spec.hook == "after")
        for hit = 1, ordinary and 1 or 2 do
          local suppressed = guarded or (oakPending and (id % 2 == 1 or hit == 1 or spec.substitute))
          local critical = force
            or not (
              suppressed
              or spec.kind == "pokedude"
              or (ordinary and (spec.armor or spec.hook == "suppress"))
            )
          expected[hit] = ordinary and (critical and 33 or 16) or (critical and 12 or 6)
          if spec.substitute and hit == 1 then
            expected[hit] = 1
          end
          if not suppressed and not (ordinary and (spec.armor or spec.hook == "force")) then
            criticalDraws = criticalDraws + 1
          end
        end
        local amounts = {}
        local actualDraws = 0
        for _, h in ipairs(hits) do
          amounts[#amounts + 1] = h.damage
          T.eq(
            h.kind,
            ordinary and not spec.special and "physical" or "special",
            "native event carries the damage kind"
          )
        end
        for _, r in ipairs(draws) do
          if r.kind == "critical" then
            actualDraws = actualDraws + 1
          end
        end
        T.same(amounts, expected, spec.name .. " native critical damage")
        T.eq(actualDraws, criticalDraws, spec.name .. " native critical draw count")
        T.eq(
          calls.crit,
          ordinary and not spec.armor and not spec.noHook and 1 or 0,
          "only ordinary unarmored hits enter the public critical hook"
        )
        T.eq(calls.damage, ordinary and 1 or 0, "scripted Beat Up bypasses ordinary damage hooks")
        for _, c in ipairs(contexts) do
          T.same(c, {
            battle = true,
            target = target.mon.nickname,
            move = "TACKLE",
            number = 33,
            stage = spec.stage or (spec.focus and 2 or 0),
          }, "public critical context carries the native battle/target/move/stage")
        end
        T.eq(
          native and user.mon.pp[slot] or user.curMoves[slot].pp,
          ordinary and 9 or 19,
          "owned PP is spent once"
        )
        rows[#rows + 1] = {
          case = spec.name,
          user = id,
          move = name,
          hits = hits,
          draws = draws,
          calls = calls,
          contexts = contexts,
          oakFlags = b.oakMsgFlags or 0,
        }
      end
    end
  end
  stopHit()
  stopDamage()
  stopCrit()
  if sourceItems then
    sourceItems._byId, sourceItems._byName, sourceItems._pack = unpack(oldItems, 1, 3)
  end
  f.close()
  return rows
end
return M
