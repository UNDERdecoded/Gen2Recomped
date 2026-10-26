local M = {}
function M.run(f)
  local T, e, rows = f.T, f.e, {}
  local samples = {
    { "LEFTOVERS", "residual", "HELD_LEFTOVERS", 10 },
    { "QUICK_CLAW", "priority", "HELD_QUICK_CLAW", f.gen == 3 and 51 or 20 },
    { "BRIGHTPOWDER", "accuracy", "HELD_BRIGHTPOWDER", f.gen == 3 and 25 or 10 },
    { "FOCUS_BAND", "endure", "HELD_FOCUS_BAND", f.gen == 3 and 25 or 10 },
    { "KINGS_ROCK", "flinch", "HELD_FLINCH", f.gen == 3 and 25 or 10 },
    { "SCOPE_LENS", "damage", "HELD_CRITICAL_UP", 0 },
    { "ORAN_BERRY", "residual", "HELD_BERRY", 10 },
    { "PERSIM_BERRY", f.gen == 2 and "status" or "residual", "HELD_HEAL_CONFUSION", 0 },
    { "LEPPA_BERRY", f.gen == 2 and "pp" or "residual", "HELD_RESTORE_PP", 10 },
    { "CHARCOAL", "damage", "HELD_FIRE_BOOST", 10 },
  }
  for _, sample in ipairs(samples) do
    local item, trigger, name, param = unpack(sample)
    f.reset(item)
    T.eq(f.read(trigger), f.effect(name), "native reader preserves held effect")
    T.eq(e.state.calls, 1, "native held reader dispatches once")
    local ctx = e.state.last
    T.eq(ctx.effect, name, "shared HELD name")
    T.eq(ctx.parameter, param, "shared byte/proportion parameter")
    T.eq(ctx.trigger, trigger, "native comparison role")
    T.eq(ctx.battle, f.battle, "opaque actual battle controller")
    if f.api >= 3 then
      T.eq(ctx.item, item, "API-3 canonical item ID")
      T.eq(ctx.def.id, item, "API-3 item definition role")
      T.eq(ctx.mon.species, "CHARMANDER", "API-3 canonical holder species")
    end
    rows[#rows + 1] = {
      label = item .. ":" .. trigger,
      effect = ctx.effect,
      parameter = ctx.parameter,
      trigger = ctx.trigger,
      holder = ctx.mon.nickname,
    }
  end
  f.reset("NO_EFFECT")
  e.state.mode, e.state.effect, e.state.parameter = "override", "HELD_BERRY", 7
  local effect, amount = f.read("check")
  T.eq(effect, f.effect("HELD_BERRY"), "an ordinary held item may acquire an effect")
  T.eq(amount, 7, "ordinary item substitution parameter")
  T.check(e.state.last.def ~= nil, "ordinary held item retains definition even without native effect")
  rows[#rows + 1] = { label = "ordinary item override", parameter = amount }
  f.reset(nil)
  e.state.mode, e.state.effect, e.state.parameter, e.state.requiresItem = "override", "HELD_BERRY", 7, false
  effect, amount = f.read("check")
  T.eq(effect, f.effect("HELD_BERRY"), "empty-hand reads may acquire a public effect")
  T.eq(amount, 7, "empty-hand override parameter")
  T.eq(e.state.last.def, nil, "empty hand has no item definition")
  rows[#rows + 1] = { label = "empty-hand override", parameter = amount }
  e.state.requiresItem = true
  for _, trigger in ipairs({
    "priority",
    "damage",
    "endure",
    "flinch",
    "accuracy",
    "confuse",
    "residual",
    "status",
    "pp",
    "run",
    "check",
  }) do
    f.reset("LEFTOVERS")
    f.read(trigger, "enemy")
    T.eq(e.state.last.mon.nickname, "ENEMY", "opponent's actual mon crosses read boundary")
    T.eq(e.state.last.trigger, trigger, "arbitrary comparison role passes through")
    rows[#rows + 1] = { label = "opponent:" .. trigger, trigger = e.state.last.trigger }
  end
  for _, chosen in ipairs({ "HELD_BERRY", "HELD_CRITICAL_UP", "HELD_QUICK_CLAW", "HELD_FIRE_BOOST" }) do
    f.reset("LEFTOVERS")
    e.state.mode, e.state.effect, e.state.parameter = "override", chosen, 128
    local effect, parameter = f.read("damage")
    T.eq(effect, f.effect(chosen), "public substitution reaches native effect ID")
    local wanted = f.gen == 3 and chosen == "HELD_QUICK_CLAW" and 50 or 128
    T.eq(parameter, wanted, "substitution converts byte odds to GBA native percent")
    rows[#rows + 1] = { label = "substitute:" .. chosen, parameter = parameter }
  end
  for _, mode in ipairs({ "suppress", "invalid", "mutate", "fallback" }) do
    f.reset("LEFTOVERS")
    e.state.mode = mode
    if mode == "invalid" then
      e.state.mode, e.state.effect = "override", 7
    end
    if mode == "fallback" then
      e.state.mode, e.state.effect, e.state.parameter = "override", "HELD_LEFTOVERS", "invalid"
    end
    if mode == "mutate" then
      e.state.effect, e.state.parameter = "HELD_BERRY", "7"
    end
    local effect, parameter = f.read("residual")
    local expected = mode == "mutate" and "HELD_BERRY" or mode == "fallback" and "HELD_LEFTOVERS" or nil
    T.eq(effect, f.effect(expected), "return/mutation decision reaches native reader")
    T.eq(
      parameter,
      mode == "mutate" and 7 or mode == "fallback" and 10 or 0,
      "fallback preserves native parameter"
    )
    rows[#rows + 1] = { label = "decision:" .. mode, parameter = parameter }
  end
  for _, after in ipairs({ false, true }) do
    f.reset("LEFTOVERS")
    local off = e.api.hooks:wrap("held_item.trigger", function(next, ctx)
      if after then
        next(ctx)
      end
      error("intentional held-item wrapper failure")
    end, 100)
    T.eq(f.read("residual"), f.effect("HELD_LEFTOVERS"), "wrapper error retains native effect")
    T.eq(e.state.calls, 1, "wrapper recovery delegates once")
    off()
    rows[#rows + 1] = { label = "error:" .. tostring(after), calls = e.state.calls }
  end
  if f.api >= 3 then
    f.reset("LEFTOVERS")
    local off = e.api.hooks:wrap("held_item.trigger", function(next, ctx)
      local a, b = next(ctx)
      local c, d = next(ctx)
      T.eq(a, c, "API-3 replay preserves first effect")
      T.eq(b, d, "API-3 replay preserves second result")
      return a, b
    end, 100)
    f.read("residual")
    off()
    T.eq(e.state.calls, 1, "API-3 replay executes downstream read once")
    rows[#rows + 1] = { label = "replay", calls = e.state.calls }
  end
  for _, mode in ipairs({ "delegate", "suppress", "override" }) do
    f.reset("LEFTOVERS")
    f.mon("player").hp = 100
    e.state.mode, e.state.trigger = mode, "residual"
    e.state.requiresItem = true
    e.state.effect, e.state.parameter = "HELD_BERRY", 7
    f.residual()
    local healed = f.mon("player").hp - 100
    T.eq(
      healed,
      mode == "delegate" and 25 or mode == "override" and 7 or 0,
      "real residual applies public held decision"
    )
    local held = f.mon("player").item
    local remains = held ~= nil and held ~= 0
    T.eq(remains, mode ~= "override", "native effect owns item consumption")
    T.check(e.state.seen.residual ~= nil, "real residual code dispatches held read")
    rows[#rows + 1] = { label = "residual:" .. mode, healed = healed, held = remains }
  end
  for _, active in ipairs({ false, true }) do
    f.reset("LEFTOVERS")
    if active then
      e.state.mode, e.state.trigger, e.state.effect, e.state.parameter =
        "override", "priority", "HELD_QUICK_CLAW", 256
    end
    T.eq(f.priority(), active, "native move order follows held priority substitution")
    rows[#rows + 1] = { label = "priority:" .. tostring(active), first = active }
  end
  local damages = {}
  for _, active in ipairs({ false, true }) do
    f.reset("LEFTOVERS")
    if active then
      e.state.mode, e.state.trigger, e.state.effect, e.state.parameter =
        "override", "damage", "HELD_NORMAL_BOOST", 100
    end
    f.attack()
    damages[#damages + 1] = 400 - f.mon("enemy").hp
  end
  T.check(damages[1] > 0 and damages[2] > damages[1], "real native move damage responds to held type boost")
  rows[#rows + 1] = { label = "damage boost", increased = damages[2] > damages[1] }
  for _, active in ipairs({ false, true }) do
    f.reset(nil)
    f.hold("enemy", "LEFTOVERS")
    if active then
      e.state.mode, e.state.trigger, e.state.effect, e.state.parameter =
        "override", "accuracy", "HELD_BRIGHTPOWDER", 256
    end
    f.attack()
    local missed = f.mon("enemy").hp == 400
    T.eq(missed, active, "native 100-percent move honors held accuracy modifier")
    rows[#rows + 1] = { label = "accuracy:" .. tostring(active), missed = missed }
  end
  for _, active in ipairs({ false, true }) do
    f.reset(nil)
    f.hold("enemy", "LEFTOVERS")
    f.mon("enemy").hp = 1
    if active then
      e.state.mode, e.state.trigger, e.state.effect, e.state.parameter =
        "override", "endure", "HELD_FOCUS_BAND", 256
    end
    f.attack()
    T.eq(f.mon("enemy").hp, active and 1 or 0, "native lethal move on one HP honors held endurance")
    rows[#rows + 1] = { label = "endure:" .. tostring(active), hp = f.mon("enemy").hp }
  end
  for _, hp in ipairs({ 199, 200 }) do
    f.reset("ORAN_BERRY")
    f.mon("player").hp = hp
    f.residual()
    local wanted = hp == 199 or f.gen == 3
    T.eq(f.mon("player").hp - hp, wanted and 10 or 0, "native generation berry threshold")
    rows[#rows + 1] = { label = "berry threshold:" .. hp, healed = f.mon("player").hp - hp }
  end
  if f.gen == 3 then
    for _, active in ipairs({ false, true }) do
      f.reset("LEFTOVERS")
      f.hold("enemy", "LEFTOVERS")
      if active then
        e.state.mode, e.state.trigger, e.state.holder = "override", "priority", "ENEMY"
        e.state.effect, e.state.parameter = "HELD_MACHO_BRACE", 0
      end
      T.eq(f.priority(75, 100), active, "native GBA speed honors held Macho Brace substitution")
      rows[#rows + 1] = { label = "macho:" .. tostring(active), first = active }
      f.reset("LEFTOVERS")
      if active then
        e.state.mode, e.state.trigger, e.state.effect = "override", "run", "HELD_ESCAPE"
      end
      local escaped = f.runEffect()
      T.eq(escaped, active, "native GBA escape honors held read")
      rows[#rows + 1] = { label = "escape:" .. tostring(active), escaped = escaped }
    end
    f.reset("LEFTOVERS")
    e.state.mode, e.state.trigger, e.state.effect = "override", "check", "HELD_AMULET_COIN"
    f.entry()
    local prize = f.battle.amuletCoin == true or f.battle.moneyMultiplier == 2
    T.eq(prize, true, "native entry held read sets money multiplier")
    rows[#rows + 1] = { label = "entry prize", prize = prize }
    f.reset("LEFTOVERS")
    f.battle.player.stages.attack = -1
    e.state.mode, e.state.trigger, e.state.effect = "override", "check", "HELD_RESTORE_STATS"
    f.entry()
    T.eq(f.battle.player.stages.attack, 0, "native entry held read restores stat stages")
    local held = f.mon("player").item
    T.check(held == nil or held == 0, "native entry consumes substituted White Herb")
    rows[#rows + 1] = { label = "entry herb", stage = f.battle.player.stages.attack }
    f.reset(nil)
    f.hold("enemy", "LEFTOVERS")
    e.state.mode, e.state.trigger, e.state.effect = "override", "check", "HELD_AMULET_COIN"
    f.entry("enemy")
    prize = f.battle.amuletCoin == true or f.battle.moneyMultiplier == 2
    T.eq(prize, require("src.core.GameVersion").get() ~= "emerald", "native GBA enemy prize policy")
    rows[#rows + 1] = { label = "enemy entry prize", prize = prize }
    f.reset("LEFTOVERS")
    f.mon("player").hp = 300
    e.state.mode, e.state.trigger, e.state.effect, e.state.parameter =
      "override", "flinch", "HELD_SHELL_BELL", 8
    f.attack()
    local damage, healed = 400 - f.mon("enemy").hp, f.mon("player").hp - 300
    T.eq(healed, math.max(1, math.floor(damage / 8)), "native Shell Bell read heals from actual dealt damage")
    rows[#rows + 1] = { label = "shell bell", correctShare = healed == math.max(1, math.floor(damage / 8)) }
  end
  for _, active in ipairs({ false, true }) do
    f.reset("LEFTOVERS")
    if active then
      e.state.mode, e.state.trigger, e.state.effect, e.state.parameter =
        "override", "flinch", "HELD_FLINCH", 256
    end
    f.attack()
    T.eq(f.flinched(), active, "actual native move honors held King's Rock substitution")
    rows[#rows + 1] = { label = "flinch:" .. tostring(active), flinched = f.flinched() }
    f.reset("PERSIM_BERRY")
    f.confused(3)
    if not active then
      e.state.mode, e.state.trigger = "suppress", f.gen == 2 and "status" or "residual"
    end
    f.residual()
    T.eq(f.confused(), not active, "actual native residual honors held confusion cure/suppression")
    rows[#rows + 1] = { label = "confusion cure:" .. tostring(active), confused = f.confused() }
    f.reset("LEPPA_BERRY")
    f.pp(0)
    if not active then
      e.state.mode, e.state.trigger = "suppress", f.gen == 2 and "pp" or "residual"
    end
    f.residual()
    local expected = active and (f.gen == 2 and 5 or 10) or 0
    T.eq(f.pp(), expected, "actual native held PP restore uses generation's own amount")
    rows[#rows + 1] = { label = "PP restore:" .. tostring(active), pp = f.pp() }
    if f.gen == 2 then
      f.reset(nil)
      f.hold("enemy", "LEFTOVERS")
      if active then
        e.state.mode, e.state.trigger, e.state.effect = "override", "confuse", "HELD_PREVENT_CONFUSE"
      end
      local confused = f.inflictConfusion()
      T.eq(confused, not active, "native Gold confusion gate honors held prevention")
      rows[#rows + 1] = { label = "confusion prevent:" .. tostring(active), confused = confused }
    end
  end
  for _, item in ipairs(f.catalog) do
    f.reset(item[1])
    local effect, param = f.read("check")
    T.eq(effect, f.backend == "gen1" and item[6] or item[3], "all native GBA enum names round-trip")
    T.eq(param, 16, "all native GBA default parameters round-trip without quantization")
    rows[#rows + 1] = {
      label = "GBA enum:" .. item[3],
      effect = e.state.last.effect,
      parameter = e.state.last.parameter,
    }
  end
  if f.api >= 3 then
    f.reset("LEFTOVERS")
    local off = e.api.hooks:wrap("held_item.trigger", function(next, ctx)
      ctx.def.price, ctx.def.heldEffect, ctx.def.heldParameter = 999, "HELD_BERRY", 7
      return next(ctx)
    end, 100)
    T.eq(
      f.read("residual"),
      f.effect("HELD_LEFTOVERS"),
      "definition edits do not rewrite captured current effect"
    )
    off()
    T.eq(e.state.last.def.price, 999, "downstream sees committed public definition edits")
    local effect, param = f.read("residual")
    T.eq(
      effect,
      f.effect(f.gen == 2 and "HELD_BERRY" or "HELD_LEFTOVERS"),
      "definition persistence follows native producer"
    )
    T.eq(param, f.gen == 2 and 7 or 10, "definition parameter persistence follows native producer")
    rows[#rows + 1] = {
      label = "definition metadata",
      price = e.state.last.def.price,
      parameter = param,
      effect = e.state.last.effect,
    }
    local restore = e.api.hooks:wrap("held_item.trigger", function(next, ctx)
      ctx.def.price, ctx.def.heldEffect, ctx.def.heldParameter = 100, "HELD_LEFTOVERS", 10
      return next(ctx)
    end, 100)
    f.read("check")
    restore()
  end
  f.reset("LEFTOVERS")
  e.stop()
  e.stop()
  T.eq(f.read("residual"), f.effect("HELD_LEFTOVERS"), "unsubscribe restores native reader")
  T.eq(e.state.calls, 0, "unsubscribe removes held callback")
  rows[#rows + 1] = { label = "unsubscribed", calls = e.state.calls }
  return rows
end
return M
