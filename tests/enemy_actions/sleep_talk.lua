local M = {}
local DEFS = {
  { 701, "MOD_STRIKE", 0, "NO_ADDITIONAL_EFFECT", 35, 0 },
  { 700, "MOD_SLEEP_TALK", 97, "SLEEP_TALK_EFFECT", 0, 1 },
  { 57, "SURF", 0, "NO_ADDITIONAL_EFFECT", 35, 8 },
  { 89, "EARTHQUAKE", 0, "NO_ADDITIONAL_EFFECT", 35, 32 },
  { 99, "RAGE", 81, "RAGE_EFFECT", 15, 0 },
  { 214, "SLEEP_TALK", 97, "SLEEP_TALK_EFFECT", 0, 1 },
  { 173, "SNORE", 92, "SNORE_EFFECT", 40, 0 },
  { 33, "TACKLE", 0, "NO_ADDITIONAL_EFFECT", 35, 0 },
  { 10, "SCRATCH", 0, "NO_ADDITIONAL_EFFECT", 40, 0 },
  { 167, "TRIPLE_KICK", 104, "TRIPLE_KICK_EFFECT", 10, 0 },
  { 3, "DOUBLE_SLAP", 29, "TWO_TO_FIVE_ATTACKS_EFFECT", 15, 0 },
  { 105, "RECOVER", 32, "HEAL_EFFECT", 0, 16 },
  { 118, "METRONOME", 83, "METRONOME_EFFECT", 0, 0 },
  { 119, "MIRROR_MOVE", 9, "MIRROR_MOVE_EFFECT", 0, 0 },
  { 274, "ASSIST", 181, "ASSIST_EFFECT", 0, 0 },
  { 264, "FOCUS_PUNCH", 170, "FOCUS_PUNCH_EFFECT", 150, 0 },
  { 253, "UPROAR", 159, "UPROAR_EFFECT", 50, 0 },
  { 117, "BIDE", 26, "BIDE_EFFECT", 0, 0 },
  { 13, "RAZOR_WIND", 39, "CHARGE_EFFECT", 80, 0 },
  { 143, "SKY_ATTACK", 75, "SKY_ATTACK_EFFECT", 140, 0 },
  { 130, "SKULL_BASH", 145, "CHARGE_EFFECT", 100, 0 },
  { 76, "SOLARBEAM", 151, "SOLARBEAM_EFFECT", 120, 0 },
  { 19, "FLY", 155, "FLY_EFFECT", 70, 0 },
}
function M.fixture(root, backend, version, entry)
  local native = backend == "gen1"
  local nativeRows, nativeNames
  local fixture = dofile(root .. "/tests/enemy_actions/fixture.lua").new(
    root,
    backend,
    version,
    3,
    "unified",
    function(data, _, ids, rom, names)
      nativeRows, nativeNames = rom, names
      for _, r in ipairs(DEFS) do
        local number, name, effect, binding, power, target = unpack(r)
        local id = native and name or ("MOVE_%03d"):format(number)
        ids[name], names[number] = id, name
        if native then
          local def = {
            effect = effect,
            power = power,
            type = 0,
            accuracy = 100,
            pp = 10,
            target = target,
            flags = 51,
            secondaryChance = 0,
            priority = 0,
          }
          data.gen3Moves._rom[number], rom[number], data.gen3Pokemon._moveNames[number] = def, def, name
          data.gen3Pokemon._types[4], data.gen3Pokemon._abilities[4] = { 0, 0 }, { 0, 0 }
        else
          data.moves[id] = {
            id = id,
            index = number,
            name = name,
            gen3Effect = effect,
            effect = binding,
            power = power,
            type = "NORMAL",
            accuracy = 100,
            pp = 10,
            target = target,
            flags = 51,
            protectAffected = target ~= 16,
            secondaryChance = 0,
          }
          data.pokemon.CHARMANDER.types, data.pokemon.CHARMANDER.abilities = { "NORMAL" }, {}
        end
      end
    end,
    entry
  )
  fixture.nativeRows, fixture.nativeNames = nativeRows, nativeNames
  return fixture
end
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = M.fixture(root, backend, version)
  local T, Copy = f.T, require("src.mods.Merge").deepCopy
  local rows, draws, used, damage = {}, {}, {}, {}
  local offUsed = f.e.api.events:on("battle.move_used", function(e)
    used[#used + 1] = {
      user = e.user.mon.nickname,
      target = e.target.mon.nickname,
      move = e.move.id,
      called = e.isCalled or false,
    }
  end)
  local offDamage = f.e.api.events:on("battle.damage_dealt", function(e)
    damage[#damage + 1] = {
      user = e.user.mon.nickname,
      target = e.target.mon.nickname,
      move = e.move.id,
      damage = e.damage,
      crit = e.crit or false,
      substitute = e.substitute or false,
      typeMult = e.typeMult,
    }
  end)
  local function at(b, id)
    return native and b.battlers[id] or b:battlerAt(id)
  end
  local function def(number)
    if native then
      return f.data.gen3Moves._rom[number]
    end
    return f.data.moves[("MOVE_%03d"):format(number)]
  end
  local function field(b)
    local all = {}
    for id = 0, b.double and 3 or 1 do
      local a = at(b, id)
      local pp = {}
      for i = 1, 4 do
        pp[i] = native and a.mon.pp[i] or a.curMoves[i].pp
      end
      all[#all + 1] = {
        hp = a.mon.hp,
        status = a.mon.status,
        sleep = a.sleepTurns,
        pp = pp,
        last = native and a.lastMoveId or a.lastMove and f.data.moves[a.lastMove].index,
        sub = tonumber(a.substituteHP) or 0,
        attack = a.stages.attack or 0,
        rage = not not a.rage,
      }
    end
    return all
  end
  for _, double in ipairs({ false, true }) do
    for uid = 0, double and 3 or 1 do
      local tid = uid % 2 == 0 and uid + 1 or uid - 1
      for pick = 1, 3 do
        for _, kind in ipairs({
          "ordinary",
          "awake",
          "wake",
          "early_bird",
          "early_wake",
          "missing_counter",
          "zero_pp",
          "disabled_choice",
          "encore_self",
          "empty",
          "multi",
          "triple",
          "snore",
          "recover",
          "flinch",
          "sleep_block",
          "wake_ordinary",
          "uproar",
          "soundproof",
          "forbidden",
          "bide",
          "razor_wind",
          "sky_attack",
          "skull_bash",
          "solar_beam",
          "disabled_caller",
          "called",
          "called_awake",
          "custom_caller",
          "zero_id",
          "fifth_slot",
          "spread_both",
          "spread_all",
          "rage",
          "wake_flinch",
          "indexless",
        }) do
          draws, used, damage = {}, {}, {}
          local b = f.fresh("TACKLE", { enemy = true }).battle
          b.double = double
          if not native then
            b:syncSides()
          end
          if double then
            for id = 2, 3 do
              local mon = Copy(at(b, id % 2).mon)
              if native then
                b.battlers[id] = require("src.core.game3.battle.state").makeBattler(
                  mon,
                  id % 2 == 0 and "player" or "enemy",
                  { id = id, partyIndex = 2 }
                )
              else
                b:placeBattler(id, require("src.battle.BattleState").makeBattler(f.data, mon, id % 2 == 0))
              end
            end
          end
          if not native then
            b:syncSides()
          end
          local slots = { 214, 33, 10, 33 }
          if kind == "multi" then
            slots = { 214, 3, 3, 3 }
          end
          if kind == "triple" then
            slots = { 214, 167, 167, 167 }
          end
          if kind == "snore" then
            slots = { 214, 173, 173, 173 }
          end
          if kind == "recover" then
            slots = { 214, 105, 105, 105 }
          end
          if kind == "empty" then
            slots = { 214, 118, 119, 274 }
          end
          if kind == "forbidden" then
            slots = { 214, 264, 253, 19 }
          end
          local nested = ({ spread_both = 57, spread_all = 89, rage = 99, indexless = 701 })[kind]
          if nested then
            slots = { 214, nested, nested, nested }
          end
          local banned = (
            { bide = 117, razor_wind = 13, sky_attack = 143, skull_bash = 130, solar_beam = 76 }
          )[kind]
          if banned then
            slots = { 214, banned, banned, banned }
          end
          if kind == "custom_caller" then
            slots[1] = 700
          end
          if kind == "zero_id" then
            slots = { 214, 0, 10, 0 }
          end
          if kind == "fifth_slot" then
            slots = { 214, 118, 119, 274, 33 }
          end
          for id = 0, double and 3 or 1 do
            local a = at(b, id)
            a.mon.nickname = "P" .. id
            if native then
              a.mon.moves, a.mon.pp, a.mon.maxPp = Copy(slots), { 10, 10, 10, 10 }, { 10, 10, 10, 10 }
              a.mon.maxHp, a.ability, a.mon.ability, a.type1, a.type2 = 400, 0, 0, 0, 0
            else
              a.mon.moves = {}
              for _, num in ipairs(slots) do
                a.mon.moves[#a.mon.moves + 1] = { id = ("MOVE_%03d"):format(num), pp = 10 }
              end
              a.curMoves, a.curTypes, a.abilityOverride = a.mon.moves, { "NORMAL" }, false
              a.mon.stats.hp = 400
              for _, stat in ipairs({ "attack", "defense", "spatk", "spdef" }) do
                a.curStats[stat] = 50
              end
            end
            a.mon.hp = 400
          end
          if kind == "indexless" and not native then
            def(701).index = nil
          end
          local user, target = at(b, uid), at(b, tid)
          user.mon.status, user.sleepTurns = "SLP", 4
          if kind == "awake" or kind == "called_awake" then
            user.mon.status, user.sleepTurns = nil, nil
          end
          if kind == "wake" or kind == "wake_ordinary" or kind == "wake_flinch" then
            user.sleepTurns = 1
          end
          if kind == "missing_counter" then
            user.sleepTurns = nil
          end
          if kind == "early_bird" or kind == "early_wake" then
            user[native and "ability" or "abilityOverride"] = native and 48 or "EARLY_BIRD"
            user.sleepTurns = kind == "early_wake" and 2 or 4
          end
          if kind == "zero_pp" then
            for i = 2, 4 do
              if native then
                user.mon.pp[i] = 0
              else
                user.curMoves[i].pp = 0
              end
            end
          end
          if kind == "disabled_choice" then
            user[native and "expDisabledMove" or "disabledMove"] = native and 33 or f.ids.TACKLE
            user[native and "expDisableTurns" or "disabledTurns"] = 3
          end
          if kind == "disabled_caller" then
            user[native and "expDisabledMove" or "disabledMove"] = native and 214 or f.ids.SLEEP_TALK
            user[native and "expDisableTurns" or "disabledTurns"] = 3
          end
          if kind == "encore_self" then
            user[native and "expEncoreMove" or "encoreMove"] = native and 214 or f.ids.SLEEP_TALK
            user[native and "expEncoreTurns" or "encoreTurns"] = 3
          end
          if kind == "recover" then
            user.mon.hp = 100
          end
          if kind == "flinch" or kind == "wake_flinch" then
            user.flinched = true
          end
          if kind == "uproar" or kind == "soundproof" then
            target[native and "expUproarTurns" or "uproarTurns"] = 3
            if kind == "soundproof" then
              user[native and "ability" or "abilityOverride"] = native and 43 or "SOUNDPROOF"
            end
          end
          user.lastMoveId, user.lastMove = native and 10 or nil, native and 10 or f.ids.SCRATCH
          local sleepPending = kind == "missing_counter"
          b.rng = function(lo, hi)
            local value = hi
            if lo == 1 and hi <= 3 then
              value = math.min(pick, hi)
            end
            if lo == 1 and hi == 100 then
              value = 1
            end
            if lo == 0 and hi == 3 then
              if sleepPending then
                sleepPending = false
                value = 0
              else
                value = tid
              end
            end
            draws[#draws + 1] = { lo = lo, hi = hi, value = value }
            return value
          end
          local ordinary = kind == "sleep_block" or kind == "wake_ordinary"
          local slot = ordinary and 2 or 1
          local called = kind == "called" or kind == "called_awake"
          if native then
            local nativeSlot = slot
            if called then
              nativeSlot = nil
            end
            require("src.core.game3.battle.engine").resolveMove(
              uid,
              tid,
              user.mon.moves[slot],
              nativeSlot,
              require("src.core.game3.battle.adapter").new(b),
              b,
              {},
              { called = called }
            )
          elseif called then
            b:performMove(user, target, user.curMoves[slot], true)
          else
            b:executeAction(user, target, user.curMoves[slot])
          end
          rows[#rows + 1] = {
            label = (double and "double" or "single") .. "/" .. uid .. "/" .. pick .. "/" .. kind,
            field = field(b),
            draws = Copy(draws),
            used = Copy(used),
            damage = Copy(damage),
          }
          if kind == "indexless" and not native then
            def(701).index = 701
          end
          if kind == "indexless" then
            T.eq(#used, 2, "a learned custom move needs no imported numeric index")
            T.eq(#damage, 1, "the indexless custom move executes through the native caller")
          end
          if kind == "ordinary" or kind == "zero_pp" then
            T.eq(#used, 2, "Sleep Talk and the chosen move each emit one public event")
            T.eq(native and user.mon.pp[1] or user.curMoves[1].pp, 9, "only the selected caller spends PP")
            T.eq(user.sleepTurns, 3, "nested called execution does not decrement sleep again")
          end
          if
            banned
            or kind == "empty"
            or kind == "forbidden"
            or kind == "encore_self"
            or kind == "fifth_slot"
          then
            T.eq(#damage, 0, "an empty native eligible pool cannot execute a forbidden move")
          end
          if kind == "called" then
            T.eq(#used, 2, "called Sleep Talk dispatches its nested move")
            T.eq(user.sleepTurns, 4, "called Sleep Talk bypasses the outer sleep canceller")
            T.eq(
              native and user.mon.pp[1] or user.curMoves[1].pp,
              10,
              "called Sleep Talk spends neither caller nor child PP"
            )
          end
          if kind == "sleep_block" then
            T.eq(#used, 0, "ordinary moves remain blocked while asleep")
          end
          if kind == "wake_ordinary" then
            T.eq(user.mon.status, nil, "native wake clears persistent sleep")
          end
        end
      end
    end
  end
  T.same(f.result.loader.errors, {}, "public callbacks complete without swallowed runtime errors")
  offUsed()
  offDamage()
  f.close()
  return rows
end
function M.content(root, backend, version)
  local native = backend == "gen1"
  local rows = {}
  for _, kind in ipairs({ "ordinary", "zero_pp", "awake", "primary", "patched" }) do
    local entry = [=[return function(mod)
   assert(mod.content.move_effects:register("PORTABLE_SLEEP_CHOICE",{kind="secondary",run=function(ctx)
    mod.exports.runs=mod.exports.runs+1
    return {}
   end}))
   assert(mod.content.moves:register("PORTABLE_SLEEP_MOVE",{id="PORTABLE_SLEEP_MOVE",name="PORTABLE_SLEEP_MOVE",type="NORMAL",power=35,accuracy=100,pp=10,effect="PORTABLE_SLEEP_CHOICE"}))
   mod.exports.runs=0
   mod.exports.api=mod
  end]=]
    if kind == "primary" then
      entry = entry:gsub('kind="secondary"', 'kind="primary"'):gsub("power=35", "power=0")
      entry = entry:gsub(
        "mod.exports.runs=mod.exports.runs%+1",
        'mod.exports.runs=mod.exports.runs+1;ctx.changeStage(ctx.user,"attack",1)'
      )
    elseif kind == "patched" then
      entry = entry:gsub(
        "mod.exports.runs=0",
        'assert(mod.content.moves:patch("FLY",{effect="PORTABLE_SLEEP_CHOICE"}));mod.exports.runs=0'
      )
    end
    local f = M.fixture(root, backend, version, entry)
    local T = f.T
    local c = f.fresh("TACKLE", { enemy = true })
    local b, user, target = c.battle, c.user, c.target
    if not native then
      for _, actor in ipairs({ user, target }) do
        for _, stat in ipairs({ "attack", "defense", "spatk", "spdef" }) do
          actor.curStats[stat] = 50
        end
      end
    end
    local number, previousRegistryData
    if native then
      number = kind == "patched" and 19
        or assert(require("src.mods.Gen3Compat").moveId("PORTABLE_SLEEP_MOVE"))
      -- The base fixture mounts its explicit native rows after public load.
      -- Mount the actually merged authored row/name too; do not reconstruct
      -- or modify its effect/power/type/flags. All mounted tables are owned
      -- by this fixture and restored by close(). The source checkout stays clean.
      local moves = require("src.core.game3.battle.moves")
      assert(moves._rom == f.nativeRows and moves.BY_NUM == f.nativeNames)
      f.nativeRows[number] = assert(f.data.gen3Moves._rom[number])
      local name = kind == "patched" and "FLY" or "PORTABLE_SLEEP_MOVE"
      f.nativeNames[number] = name
      moves._numByName[name] = number
      local registries = require("src.core.game3.battle.mod_registries")
      previousRegistryData = registries.data()
      registries.bind(f.data)
      assert(registries.hasEffects())
      user.mon.moves, user.mon.pp, user.mon.maxPp =
        { 214, number }, { 10, kind == "zero_pp" and 0 or 10 }, { 10, 10 }
    else
      b:syncSides()
      T.eq(
        f.data.moves.PORTABLE_SLEEP_MOVE.index,
        nil,
        "portable authored move has no required numeric index"
      )
      user.mon.moves = {
        { id = f.ids.SLEEP_TALK, pp = 10 },
        { id = kind == "patched" and f.ids.FLY or "PORTABLE_SLEEP_MOVE", pp = kind == "zero_pp" and 0 or 10 },
      }
      user.curMoves = user.mon.moves
      if kind == "patched" then
        T.eq(f.data.moves[f.ids.FLY].gen3Effect, nil, "authored effect clears the old native two-turn script")
      end
    end
    user.mon.status, user.sleepTurns = "SLP", 4
    if kind == "awake" then
      user.mon.status, user.sleepTurns = nil, nil
    end
    local draws, used, damage = {}, {}, {}
    b.rng = function(lo, hi)
      local v = lo == 1 and 1 or hi
      draws[#draws + 1] = { lo = lo, hi = hi, value = v }
      return v
    end
    local off = f.e.api.events:on("battle.move_used", function(e)
      used[#used + 1] = { move = e.move.id, called = e.isCalled or false }
    end)
    local offDamage = f.e.api.events:on("battle.damage_dealt", function(e)
      damage[#damage + 1] =
        { move = e.move.id, damage = e.damage, crit = e.crit or false, typeMult = e.typeMult }
    end)
    if native then
      require("src.core.game3.battle.engine").resolveMove(
        1,
        0,
        214,
        1,
        require("src.core.game3.battle.adapter").new(b),
        b,
        {}
      )
    else
      b:executeAction(user, target, user.curMoves[1])
    end
    T.eq(f.e.runs, kind == "awake" and 0 or 1, "same API-3 authored effect executes through Sleep Talk")
    T.eq(native and user.mon.pp[1] or user.curMoves[1].pp, 9, "portable custom call spends caller PP only")
    T.eq(
      native and user.mon.pp[2] or user.curMoves[2].pp,
      kind == "zero_pp" and 0 or 10,
      "portable learned custom move keeps its PP"
    )
    T.same(f.result.loader.errors, {}, "custom content and public callbacks execute without runtime errors")
    rows[#rows + 1] = {
      label = kind,
      runs = f.e.runs,
      attack = user.stages.attack or 0,
      pp = {
        native and user.mon.pp[1] or user.curMoves[1].pp,
        native and user.mon.pp[2] or user.curMoves[2].pp,
      },
      hp = { user.mon.hp, target.mon.hp },
      status = user.mon.status,
      sleep = user.sleepTurns,
      draws = draws,
      used = used,
      damage = damage,
    }
    off()
    offDamage()
    if native then
      require("src.core.game3.battle.mod_registries").bind(previousRegistryData)
    end
    f.close()
  end
  return rows
end
return M
