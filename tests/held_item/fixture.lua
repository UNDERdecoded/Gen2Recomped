local M = {}
function M.new(root, backend, version, api, format, noMod, failing)
  local items = {
    { "NO_EFFECT", 371, "NONE", 0, 0 },
    { "LEFTOVERS", 200, "LEFTOVERS", 3, 10 },
    { "QUICK_CLAW", 183, "QUICK_CLAW", 74, 20 },
    { "BRIGHTPOWDER", 179, "EVASION_UP", 77, 10 },
    { "FOCUS_BAND", 196, "FOCUS_BAND", 79, 10 },
    { "KINGS_ROCK", 187, "FLINCH", 75, 10 },
    { "SCOPE_LENS", 198, "SCOPE_LENS", 73, 0 },
    { "ORAN_BERRY", 139, "RESTORE_HP", 1, 10 },
    { "PERSIM_BERRY", 140, "CURE_CONFUSION", 16, 0 },
    { "LEPPA_BERRY", 138, "RESTORE_PP", 6, 10 },
    { "CHARCOAL", 215, "FIRE_POWER", 58, 10 },
  }
  local catalog = {}
  local gbaNames = [[
RESTORE_HP CURE_PAR CURE_SLP CURE_PSN CURE_BRN CURE_FRZ RESTORE_PP CURE_CONFUSION CURE_STATUS
CONFUSE_SPICY CONFUSE_DRY CONFUSE_SWEET CONFUSE_BITTER CONFUSE_SOUR ATTACK_UP DEFENSE_UP
SPEED_UP SP_ATTACK_UP SP_DEFENSE_UP CRITICAL_UP RANDOM_STAT_UP EVASION_UP RESTORE_STATS
MACHO_BRACE EXP_SHARE QUICK_CLAW FRIENDSHIP_UP CURE_ATTRACT CHOICE_BAND FLINCH BUG_POWER
DOUBLE_PRIZE REPEL SOUL_DEW DEEP_SEA_TOOTH DEEP_SEA_SCALE CAN_ALWAYS_RUN PREVENT_EVOLVE
FOCUS_BAND LUCKY_EGG SCOPE_LENS STEEL_POWER LEFTOVERS DRAGON_SCALE LIGHT_BALL GROUND_POWER
ROCK_POWER GRASS_POWER DARK_POWER FIGHTING_POWER ELECTRIC_POWER WATER_POWER FLYING_POWER
POISON_POWER ICE_POWER GHOST_POWER PSYCHIC_POWER FIRE_POWER DRAGON_POWER NORMAL_POWER
UP_GRADE SHELL_BELL LUCKY_PUNCH METAL_POWDER THICK_CLUB STICK
]]
  local goldNames = {
    [1] = "BERRY",
    [16] = "HEAL_CONFUSION",
    [73] = "CRITICAL_UP",
    [77] = "BRIGHTPOWDER",
    [58] = "FIRE_BOOST",
  }
  local f = dofile(root .. "/tests/charge_required/fixture.lua").new(
    root,
    backend,
    version,
    api,
    format,
    noMod,
    failing,
    "portable_held_item",
    function(data, gen)
      if backend == "gen2" then
        data.constants.generation = gen
      end
      if gen == 3 then
        for name in gbaNames:gmatch("%S+") do
          local index = #catalog + 1
          local row = { "PORTABLE_HOLD_" .. index, 500 + index, name, 0, 16, index }
          catalog[#catalog + 1] = row
          items[#items + 1] = row
        end
      end
      for _, row in ipairs(items) do
        local name, id, effect, gold, param = unpack(row)
        if backend == "gen1" and gen == 3 then
          data.gen3Items._byId[id] = {
            name = name:gsub("_", " "),
            pocket = "ITEMS",
            price = 100,
            holdEffect = row[6] or ({
              NONE = 0,
              LEFTOVERS = 43,
              QUICK_CLAW = 26,
              EVASION_UP = 22,
              FOCUS_BAND = 39,
              FLINCH = 30,
              SCOPE_LENS = 41,
              RESTORE_HP = 1,
              CURE_CONFUSION = 8,
              RESTORE_PP = 7,
              FIRE_POWER = 58,
            })[effect],
            holdEffectParam = param,
          }
        else
          local key = backend == "gen2" and gen == 3 and ("ITEM_%03d"):format(id) or name
          data.items[key] = { id = key, index = id, name = name:gsub("_", " "), price = 100 }
          if backend == "gen1" and gen == 2 then
            data.items[key].heldEffect = "HELD_" .. (goldNames[gold] or effect)
            data.items[key].heldParameter = param
          elseif gen == 2 then
            data.items[key].heldEffect, data.items[key].heldParam = gold, param
          end
          if gen >= 3 then
            data.items[key].holdEffect, data.items[key].holdEffectParam = effect, param
          end
        end
      end
    end
  )
  f.catalog = catalog
  if backend == "gen1" and f.gen == 3 then
    -- Supply native extractor-shaped item data to the real fallback reader.
    local Items = require("src.core.game3.items_data")
    local previous, close = Items._byId, f.close
    Items._byId = f.data.gen3Items._byId
    f.close = function()
      Items._byId = previous
      close()
    end
  end
  local native = f.fresh
  local b, step
  function f.reset(item)
    step = native("TACKLE")
    b = step.battle
    if backend == "gen1" and f.gen == 2 then
      b.random = function()
        return 0
      end
    end
    f.battle = b
    for _, side in ipairs({ "player", "enemy" }) do
      local mon = backend == "gen1" and f.gen == 2 and b[side] or b[side].mon
      mon.hp, mon.maxHp, mon.stats = 400, 400, mon.stats or {}
      mon.stats.hp, mon.nickname = 400, side == "player" and "PLAYER" or "ENEMY"
    end
    b.queue, b.phase, b.turnCount = {}, "menu", 1
    if f.e then
      f.e.state.mode, f.e.state.trigger, f.e.state.holder = "delegate", nil, nil
      f.e.state.calls, f.e.state.seen, f.e.state.views = 0, {}, {}
    end
    f.hold("player", item)
    f.hold("enemy", nil)
    return b
  end
  function f.mon(side)
    return backend == "gen1" and f.gen == 2 and b[side] or b[side].mon
  end
  function f.hold(side, name)
    local id
    for _, row in ipairs(items) do
      if row[1] == name then
        id = row[2]
      end
    end
    local key = name
    if f.gen == 3 then
      key = backend == "gen1" and (id or 0) or (id and ("ITEM_%03d"):format(id))
    end
    f.mon(side).item = key
    if backend == "gen1" and f.gen == 3 then
      b[side].item = key
    end
    return key
  end
  function f.read(trigger, side)
    side = side or "player"
    if backend == "gen1" and f.gen == 2 then
      return b:heldEffect(b[side], trigger)
    end
    if backend == "gen1" and f.gen == 3 then
      return require("src.core.game3.battle.held_items").of(b[side], trigger, b)
    end
    if f.gen == 2 then
      return require("src.battle.HeldItems").effect(f.data, b[side], trigger)
    end
    return require("src.battle.HoldItems").effectOf(b[side], trigger)
  end
  function f.residual()
    if backend == "gen1" and f.gen == 2 then
      b:betweenTurnEffects()
    elseif backend == "gen1" and f.gen == 3 then
      require("src.core.game3.battle.engine")
      return require("src.core.game3.battle.residuals").runTurn(
        require("src.core.game3.battle.adapter").new(b)
      )
    else
      b:endOfTurn()
    end
  end
  function f.attack()
    return step.use()
  end
  function f.flinched()
    if backend == "gen1" and f.gen == 2 then
      return not not b:volatile(b.enemy).flinched
    end
    return not not b.enemy.flinched
  end
  function f.confused(turns)
    if backend == "gen1" and f.gen == 2 then
      if turns then
        b:volatile(b.player).confuseCount = turns
      end
      return (b:volatile(b.player).confuseCount or 0) > 0
    elseif backend == "gen1" and f.gen == 3 then
      if turns then
        b.player.confusionTurns = turns
      end
      return (b.player.confusionTurns or 0) > 0
    end
    if turns then
      b.player.confusedTurns = turns
    end
    return (b.player.confusedTurns or 0) > 0
  end
  function f.pp(value)
    local mon = f.mon("player")
    if backend == "gen1" and f.gen == 3 then
      if value then
        mon.pp[1] = value
      end
      return mon.pp[1]
    end
    if value then
      mon.moves[1].pp = value
    end
    return mon.moves[1].pp
  end
  function f.inflictConfusion()
    if backend == "gen1" then
      b:applyConfusion(b.enemy, 3, b.player)
      return (b:volatile(b.enemy).confuseCount or 0) > 0
    end
    require("src.battle.MoveEffects").primary.CONFUSION_EFFECT(b, b.player, b.enemy)
    return (b.enemy.confusedTurns or 0) > 0
  end
  function f.priority(playerSpeed, enemySpeed)
    playerSpeed, enemySpeed = playerSpeed or 10, enemySpeed or 100
    if backend == "gen1" and f.gen == 2 then
      b.player.stats.speed, b.enemy.stats.speed = playerSpeed, enemySpeed
      return b:orderOf(f.ids.TACKLE, f.ids.TACKLE) == "player"
    elseif backend == "gen1" and f.gen == 3 then
      b.player.mon.speed, b.enemy.mon.speed, b.randomTurnNumber = playerSpeed, enemySpeed, 0
      local Engine = require("src.core.game3.battle.engine")
      local ad = require("src.core.game3.battle.adapter").new(b)
      return Engine.speedOf(b.player, b, ad) > Engine.speedOf(b.enemy, b, ad)
    end
    b.player.curStats.speed, b.enemy.curStats.speed = playerSpeed, enemySpeed
    if f.gen == 3 and b:quickClawWins(b.player) then
      return true
    end
    return require("src.battle.TurnOrder").firstMover(
      b.player,
      f.data.moves[f.ids.TACKLE],
      b.enemy,
      f.data.moves[f.ids.TACKLE],
      b.rng,
      nil,
      b,
      f.data
    )
  end
  function f.entry(side)
    side = side or "player"
    if backend == "gen1" then
      return require("src.core.game3.battle.held_items").onSwitchIn(
        require("src.core.game3.battle.adapter").new(b),
        b[side]
      )
    end
    return require("src.battle.HeldItems").onEntry(b, b[side])
  end
  function f.runEffect()
    if backend == "gen1" then
      b.player.mon.speed, b.enemy.mon.speed = 10, 100
      b.rng = function(lo, hi)
        return hi or lo or 0
      end
      return require("src.core.game3.battle.engine").tryFlee(
        b,
        require("src.core.game3.battle.adapter").new(b),
        b.player
      )
    end
    b.rng = function(lo, hi)
      return hi or lo or 0
    end
    return b:runRoll(0, 255)
  end
  function f.effect(kind)
    if backend == "gen1" and f.gen == 2 then
      return kind
    end
    if f.gen == 2 then
      return ({
        HELD_NONE = 0,
        HELD_LEFTOVERS = 3,
        HELD_BERRY = 1,
        HELD_QUICK_CLAW = 74,
        HELD_BRIGHTPOWDER = 77,
        HELD_FOCUS_BAND = 79,
        HELD_FLINCH = 75,
        HELD_CRITICAL_UP = 73,
        HELD_FIRE_BOOST = 58,
        HELD_HEAL_CONFUSION = 16,
        HELD_RESTORE_PP = 6,
        HELD_PREVENT_CONFUSE = "PREVENT_CONFUSE",
      })[kind] or 0
    end
    local key = ({
      HELD_LEFTOVERS = "LEFTOVERS",
      HELD_BERRY = "RESTORE_HP",
      HELD_QUICK_CLAW = "QUICK_CLAW",
      HELD_BRIGHTPOWDER = "EVASION_UP",
      HELD_FOCUS_BAND = "FOCUS_BAND",
      HELD_FLINCH = "FLINCH",
      HELD_CRITICAL_UP = "SCOPE_LENS",
      HELD_FIRE_BOOST = "FIRE_POWER",
      HELD_HEAL_CONFUSION = "CURE_CONFUSION",
      HELD_RESTORE_PP = "RESTORE_PP",
    })[kind]
    if backend == "gen2" then
      return key
    end
    return key and require("src.core.game3.battle.held_items").HOLD[key] or 0
  end
  f.reset("LEFTOVERS")
  return f
end
return M
