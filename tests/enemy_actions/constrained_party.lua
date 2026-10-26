-- Run the actual native builders with ROM-shaped data, never patched formulas.
local M = {}
local SPECIES = {
  { 19, "RATTATA", { 30, 56, 35, 72, 25, 35 }, 127, 50, 62, 70, 0 },
  { 16, "PIDGEY", { 40, 45, 40, 56, 35, 35 }, 127, 51, 0, 70, 3 },
  { 43, "ODDISH", { 45, 50, 55, 30, 75, 65 }, 127, 34, 0, 70, 3 },
  { 60, "POLIWAG", { 40, 50, 40, 90, 40, 40 }, 127, 11, 6, 70, 3 },
  { 12, "BUTTERFREE", { 60, 45, 50, 70, 80, 80 }, 127, 14, 0, 70, 0 },
  { 39, "JIGGLYPUFF", { 115, 45, 20, 20, 45, 25 }, 191, 56, 0, 35, 4 },
}
local MOVES = {
  { 33, "TACKLE", 35 },
  { 39, "TAIL_WHIP", 30 },
  { 158, "HYPER_FANG", 15 },
  { 98, "QUICK_ATTACK", 30 },
  { 28, "SAND_ATTACK", 15 },
  { 16, "GUST", 35 },
  { 71, "ABSORB", 25 },
  { 230, "SWEET_SCENT", 20 },
  { 77, "POISONPOWDER", 35 },
  { 55, "WATER_GUN", 25 },
  { 95, "HYPNOSIS", 20 },
  { 145, "BUBBLE", 30 },
  { 93, "CONFUSION", 25 },
  { 78, "STUN_SPORE", 30 },
  { 79, "SLEEP_POWDER", 15 },
  { 47, "SING", 15 },
  { 111, "DEFENSE_CURL", 40 },
  { 1, "POUND", 35 },
}
local LESSONS = { "battle", "status", "matchups", "catch" }
local STATS = { "hp", "attack", "defense", "speed", "spatk", "spdef" }
local SHORT = { "hp", "atk", "def", "spe", "spa", "spd" }
local SOURCE_STATS = { "maxHp", "attack", "defense", "speed", "spAtk", "spDef" }
local NATURES = { [1] = "LONELY", [4] = "NAUGHTY", [19] = "RASH", [23] = "CAREFUL" }
local GROWTH = { [0] = "MEDIUM_FAST", [3] = "MEDIUM_SLOW", [4] = "FAST" }
local GROWTH_IDS = {}
for n, id in pairs(GROWTH) do
  GROWTH_IDS[id] = n
end
local function key(format, prefix, n, name)
  if format == "raw" then
    return (prefix .. "_%03d"):format(n)
  end
  return format == "translated" and ("DE_" .. name) or name
end
function M.run(root, backend, version)
  local native, all = backend == "gen1", {}
  for _, format in ipairs({ "canonical", "raw", "translated" }) do
    local speciesKeys, moveKeys, expectedPp, natureIds, abilityIds = {}, {}, {}, {}, {}
    local function configure(data, engine, ids, rom, names)
      data.constants = data.constants or {}
      data.constants.speciesOrder, data.constants.moveOrder = {}, {}
      data.constants.natureOrder, data.constants.natures = {}, {}
      data.abilities = data.abilities or {}
      if not native then
        local id = key(format, "ITEM", 4, "POKE_BALL")
        data.items[id] = { index = 4, name = "POKE BALL", ball = "POKE_BALL" }
        data.constants.itemOrder = { [4] = id }
        if format == "raw" then
          data.items.FIX_BADGE_1.index = nil
          data.constants.itemOrder = nil
        end
      end
      for n, name in pairs(NATURES) do
        local id = key(format, "NATURE", n, name)
        data.constants.natureOrder[n + 1] = id
        data.constants.natures[id] = { index = n, modifiers = {} }
        natureIds[id] = n
      end
      for _, s in ipairs(SPECIES) do
        local n, name, stats, ratio, a1, a2, friendship, growth = unpack(s)
        local id = key(format, "SPECIES", n, name)
        speciesKeys[n] = id
        local display = format == "translated" and ("DE " .. name) or name
        if native then
          local p = data.gen3Pokemon
          p._names[n], p._types[n] = display, { 0, 0 }
          p._stats[n] = {}
          for i, k in ipairs(SHORT) do
            p._stats[n][k] = stats[i]
          end
          p._speciesMeta[n] = {
            genderRatio = ratio,
            friendship = friendship,
            growthRate = growth,
            catchRate = 45,
            expYield = 50,
          }
          p._abilities[n] = { a1, a2 }
          p._learnsets[n] = { { 1, 33 } }
        else
          local def = require("src.mods.Merge").deepCopy(data.pokemon.CHARMANDER)
          def.id, def.name, def.index, def.dex = id, display, n, n
          def.baseStats, def.evYield, def.genderRatio = {}, {}, ratio
          for i, k in ipairs(STATS) do
            def.baseStats[k] = stats[i]
          end
          def.baseStats.special = def.baseStats.spatk
          def.friendship, def.growthRate, def.evolutions = friendship, GROWTH[growth], {}
          def.abilities = {}
          for i, a in ipairs({ a1, a2 }) do
            if a ~= 0 then
              local aid = "ABILITY_" .. a
              def.abilities[i], abilityIds[aid] = aid, a
              data.abilities[aid] = { index = a, name = aid }
            end
          end
          data.pokemon[id] = def
          data.constants.speciesOrder[n] = id
        end
      end
      for _, m in ipairs(MOVES) do
        local n, name, pp = unpack(m)
        local id = key(format, "MOVE", n, name)
        moveKeys[id], expectedPp[n] = n, pp
        local display = format == "translated" and ("DE " .. name) or name
        names[n] = display
        if native then
          local d = {
            effect = 0,
            power = 35,
            type = 0,
            target = 0,
            priority = 0,
            accuracy = 100,
            pp = pp,
            flags = 0,
          }
          data.gen3Moves._rom[n], rom[n], data.gen3Pokemon._moveNames[n] = d, d, display
        else
          -- Remove fixture aliases: translated/raw rows are the only valid IDs.
          for k, d in pairs(data.moves) do
            if d.index == n then
              data.moves[k] = nil
            end
          end
          data.moves[id] = {
            id = id,
            name = display,
            index = n,
            pp = pp,
            power = 35,
            accuracy = 100,
            type = "NORMAL",
            effect = "NO_ADDITIONAL_EFFECT",
          }
          data.constants.moveOrder[n] = id
        end
      end
      if not native then
        if format == "raw" then
          data.constants.speciesOrder, data.constants.moveOrder, data.constants.natureOrder = nil, nil, nil
        end
        for _, s in ipairs(SPECIES) do
          if speciesKeys[s[1]] ~= s[2] then
            data.pokemon[s[2]] = nil
          end
        end
      end
    end
    local f =
      dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, 3, "unified", configure)
    local T, calls, policy = f.T, {}, "none"
    local stop
    local function hook(nextGender, c)
      calls[#calls + 1] =
        { species = c.species, def = c.def.id, ratio = c.ratio, personality = c.personality }
      if policy == "reject-first" and #calls == 1 then
        return "female"
      end
      if policy == "invalid" then
        return "not-a-gender"
      end
      if policy == "threshold" then
        c.def.genderRatio = 0
      end
      return nextGender(c)
    end
    local sourceRng, oldRandom, oldState
    if native then
      sourceRng = require("src.core.game3.rng")
      oldRandom, oldState = sourceRng.Random, sourceRng.getState()
    end
    for _, mode in ipairs({ "none", "delegate", "reject-first", "invalid", "threshold" }) do
      policy = mode
      if mode ~= "none" then
        stop = f.e.api.hooks:wrap("gender.roll", hook)
      end
      for _, seed in ipairs({ 0, 1, 65535 }) do
        for lesson, name in ipairs(LESSONS) do
          calls = {}
          local words, state = {}, seed
          -- Independent input generator; the source still executes its original Random().
          local function word(lo, hi)
            T.eq(lo, 0, "constructor requests a complete low/high word")
            T.eq(hi, 65535, "constructor requests a complete low/high word")
            local low, high = state % 65536, math.floor(state / 65536)
            state = (low * 20077 + ((low * 16838 + high * 20077) % 65536) * 65536 + 24691) % 4294967296
            local value = math.floor(state / 65536)
            words[#words + 1] = value
            return value
          end
          local original = { { species = "REAL", hp = 17, nested = { marker = seed } } }
          f.game.save.party = original
          local before = require("src.link.Json").encode(original)
          local party, foes, b
          if native then
            sourceRng.SeedRng(seed)
            sourceRng.Random = function()
              local result = oldRandom()
              words[#words + 1] = result
              return result
            end
            party, foes = require("src.core.game3.battle.pokedude").build(lesson - 1)
            state = sourceRng.getState().value
            sourceRng.Random = oldRandom
          else
            b = require("src.battle.BattleState").newPokedudeDemo(f.game, name, word)
            party, foes = f.game.save.party, b.enemyParty
          end
          T.eq(#party, lesson == 3 and 2 or 1, "native player party size")
          T.eq(#foes, 1, "native opposing party size")
          local observed = {}
          for _, side in ipairs({ party, foes }) do
            local out = {}
            for _, mon in ipairs(side) do
              local n = native and mon.species or f.data.pokemon[mon.species].index
              local stats, ivs, evs, moves = {}, {}, {}, {}
              for i, k in ipairs(STATS) do
                stats[i] = native and mon[SOURCE_STATS[i]] or mon.stats[k]
                ivs[i], evs[i] = mon.ivs[native and SHORT[i] or k], mon.evs[native and SHORT[i] or k]
                T.eq(ivs[i], 0, "native preset IV is zero")
                T.eq(evs[i], 0, "native preset EV is zero")
              end
              for j, m in ipairs(mon.moves) do
                local mn = native and m or moveKeys[m.id]
                local pp, maxPp = native and mon.pp[j] or m.pp, native and mon.maxPp[j] or m.maxPp
                T.eq(pp, expectedPp[mn], "move PP follows its native definition")
                T.eq(maxPp, pp, "native slots start with full PP")
                moves[#moves + 1] = { mn, pp, maxPp }
              end
              local nature = native and mon.nature or natureIds[mon.nature]
              T.eq(mon.personality % 25, nature, "stored nature agrees with the native PID")
              T.eq(mon.gender, native and "M" or "male", "native requested gender is stored")
              T.eq(mon.hp, stats[1], "preset starts at full HP")
              local ball = native and mon.pokeball or (f.data.items[mon.ball] or {}).index
              T.eq(ball, 4, "native preset records its Poke Ball")
              out[#out + 1] = {
                species = n,
                level = mon.level,
                metLevel = mon.metLevel,
                exp = mon.exp,
                personality = mon.personality,
                nature = nature,
                gender = "male",
                stats = stats,
                ivs = ivs,
                evs = evs,
                moves = moves,
                ability = native and mon.ability or abilityIds[mon.ability],
                ball = ball,
                growthRate = native and mon.growthRate or GROWTH_IDS[mon.growthRate],
                happiness = mon.happiness,
                friendship = mon.friendship,
              }
            end
            observed[#observed + 1] = out
          end
          if lesson == 4 then
            local ids = {}
            for _, m in ipairs(observed[1][1].moves) do
              ids[#ids + 1] = m[1]
            end
            T.same(ids, { 93, 77, 79, 78 }, "catching lesson preserves native move-slot order")
          end
          if b then
            T.eq(b.player.mon, party[1], "native player battler uses the created party member")
            T.eq(b.enemy.mon, foes[1], "native opposing battler uses the created foe")
            b:restorePokedudeParty()
            T.eq(f.game.save.party, original, "demo restores the original party reference")
            b:restorePokedudeParty()
            T.eq(f.game.save.party, original, "restoration is idempotent")
          end
          T.eq(
            require("src.link.Json").encode(original),
            before,
            "native preset leaves real party bytes unchanged"
          )
          all[#all + 1] = {
            format = format,
            mode = mode,
            seed = seed,
            lesson = name,
            parties = observed,
            words = words,
            finalState = state,
            genderCalls = calls,
          }
        end
      end
      if stop then
        stop()
        stop = nil
      end
    end
    if native then
      sourceRng.Random = oldRandom
      sourceRng.setState(oldState)
    else
      local B, Preset = require("src.battle.BattleState"), require("src.pokemon.Gen3ConstrainedMon")
      local original = f.game.save.party
      local missing = f.data.moves[key(format, "MOVE", 16, "GUST")]
      f.data.moves[key(format, "MOVE", 16, "GUST")] = nil
      T.raises(
        function()
          B.newPokedudeDemo(f.game, "battle")
        end,
        "missing native moves ID 16",
        "incomplete preset data fails explicitly before party ownership changes"
      )
      T.eq(f.game.save.party, original, "failed opposing preset leaves the real party selected")
      T.eq(f.game.save.partyAside, nil, "failed preset does not leave a borrowed-party stash")
      f.data.moves[key(format, "MOVE", 16, "GUST")] = missing
      local shinyCalls, wordCalls = 0, 0
      local stopShiny = f.e.api.hooks:wrap("shiny.roll", function(nextShiny, ...)
        shinyCalls = shinyCalls + 1
        return nextShiny(...)
      end)
      local oldRandom = love.math.random
      love.math.random = function(lo, hi)
        wordCalls = wordCalls + 1
        T.eq(lo, 0, "default preset source requests a low/high word")
        T.eq(hi, 65535, "default preset source requests a low/high word")
        return wordCalls % 2 == 1 and 151 or 0
      end
      local mon =
        Preset.new(f.data, { species = 19, level = 15, nature = 1, gender = "male", moves = { 33 } })
      love.math.random = oldRandom
      stopShiny()
      T.eq(mon.personality, 151, "default word source follows native low-word-first identity")
      T.eq(wordCalls, 2, "native preset draws no generic IV/DV or shiny-odds randomness")
      T.eq(shinyCalls, 0, "private native creation does not call the shiny predicate")
    end
    f.close()
  end
  return all
end
return M
