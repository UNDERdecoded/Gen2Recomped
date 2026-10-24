local M = {}
function M.run(f)
  local T, e, rows = f.T, f.e, {}
  local function observe(label, b, beforeHP, beforePP, calls)
    local out = {
      label = label,
      damaged = b.hp() < beforeHP,
      spent = beforePP - b.pp(),
      charging = b.charging(),
      hidden = b.hidden(),
      calls = e.state.calls - calls,
    }
    rows[#rows + 1] = out
    return out
  end
  for _, name in ipairs({ "SOLARBEAM", "FLY", "DIG", "RAZOR_WIND", "SKULL_BASH", "SKY_ATTACK" }) do
    for _, bypass in ipairs({ false, true }) do
      e.state.mode = bypass and "bypass" or "native"
      local b = f.fresh(name)
      local hp, pp, calls = b.hp(), b.pp(), e.state.calls
      b.use()
      local out = observe(name .. ":" .. tostring(bypass), b, hp, pp, calls)
      T.eq(out.calls, 1, "initial charge-capable move invokes callback once")
      T.eq(out.charging, not bypass, "public verdict controls native continuation")
      T.eq(out.damaged, bypass, "bypass resolves native damage immediately")
      T.eq(out.spent, 1, "initial move spends one PP")
      T.eq(e.state.charge, true, "default charge context")
      T.eq(e.state.isCalled, false, "ordinary initial use is not called")
      T.check(
        e.state.battle ~= nil and e.state.user ~= nil and e.state.target ~= nil,
        "context has native battle and actors"
      )
      local expected = f.backend == "gen2"
          and f.gen == 3
          and f.api < 3
          and f.format == "native"
          and f.ids[name]
        or name
      T.eq(e.state.move, expected, "native/canonical move ID follows selected callback format")
      if not bypass then
        local releaseHP, releasePP, releaseCalls = b.hp(), b.pp(), e.state.calls
        b.use()
        out = observe(name .. ":release", b, releaseHP, releasePP, releaseCalls)
        T.eq(out.charging, false, "release clears native continuation")
        T.eq(out.hidden, false, "release clears native semi-invulnerability")
        T.eq(out.damaged, true, "release resolves native damage")
        T.eq(out.spent, 0, "release cannot spend a second PP")
        T.eq(out.calls, 0, "release cannot invoke initial-charge callback")
      else
        T.eq(out.hidden, false, "bypass creates no semi-invulnerable state")
      end
    end
  end
  f.nativePolicy = {}
  local ordinary = f.fresh("TACKLE", { enemy = true })
  local ordinaryPP = ordinary.pp()
  ordinary.use()
  f.nativePolicy.enemyNormalPPCost = ordinaryPP - ordinary.pp()
  for _, bypass in ipairs({ false, true }) do
    e.state.mode = bypass and "bypass" or "native"
    local b = f.fresh("FLY", { enemy = true })
    local hp, pp, calls = b.hp(), b.pp(), e.state.calls
    b.use()
    local out = observe("enemy:" .. tostring(bypass), b, hp, pp, calls)
    T.eq(out.calls, 1, "enemy initial charge invokes shared seam")
    T.eq(out.charging, not bypass, "enemy verdict controls continuation")
    T.eq(out.damaged, bypass, "enemy bypass resolves native damage")
    f.nativePolicy[bypass and "enemyBypassPPCost" or "enemyChargePPCost"] = out.spent
    T.eq(out.spent, f.nativePolicy.enemyNormalPPCost, "charge decision retains native enemy PP policy")
    out.nativePPPreserved, out.spent = out.spent == f.nativePolicy.enemyNormalPPCost, nil
  end
  for _, mode in ipairs({ "edit", "nil", "truthy" }) do
    e.state.mode = mode
    local b = f.fresh("SOLARBEAM")
    local hp, pp, calls = b.hp(), b.pp(), e.state.calls
    b.use()
    local out = observe(mode, b, hp, pp, calls)
    T.eq(out.charging, mode ~= "edit", "only false bypasses charge")
    T.eq(out.damaged, mode == "edit", "edited next verdict reaches native damage")
  end
  e.state.mode = "native"
  local b = f.fresh("TACKLE")
  local hp, pp, calls = b.hp(), b.pp(), e.state.calls
  b.use()
  T.eq(observe("ordinary move", b, hp, pp, calls).calls, 0, "ordinary move bypasses charge seam")
  b = f.fresh("FLY")
  hp, pp, calls = b.hp(), b.pp(), e.state.calls
  b.use(true)
  local out = observe("called", b, hp, pp, calls)
  T.eq(e.state.isCalled, true, "called-move context")
  T.eq(out.spent, 0, "called-move PP semantics preserved")
  T.eq(out.charging, true, "called charge move retains native continuation")
  e.state.mode = "bypass"
  b = f.fresh("FLY")
  hp, pp, calls = b.hp(), b.pp(), e.state.calls
  b.use(true)
  out = observe("called bypass", b, hp, pp, calls)
  T.eq(out.spent, 0, "called bypass retains caller-owned PP")
  T.eq(out.charging, false, "called bypass stores no continuation")
  T.eq(out.damaged, true, "called bypass resolves ordinary damage")
  e.state.mode = "native"
  if f.gen > 1 then
    b = f.fresh("SOLARBEAM", { sun = true })
    hp, pp, calls = b.hp(), b.pp(), e.state.calls
    b.use()
    out = observe("native sun", b, hp, pp, calls)
    T.eq(out.calls, 0, "native sun bypass precedes public seam")
    T.eq(out.charging, false, "native sun retains instant SolarBeam")
    T.eq(out.damaged, true, "native sun damages immediately")
  end
  for _, after in ipairs({ false, true }) do
    local off = e.api.hooks:wrap("battle.charge_required", function(next, ...)
      if after then
        next(...)
      end
      error("intentional charge wrapper failure")
    end, 100)
    b = f.fresh("FLY")
    hp, pp, calls = b.hp(), b.pp(), e.state.calls
    b.use()
    out = observe("failure:" .. tostring(after), b, hp, pp, calls)
    T.eq(out.calls, 1, "wrapper failure executes downstream once")
    T.eq(out.spent, 1, "wrapper failure spends exactly one PP")
    T.eq(out.charging, true, "wrapper failure retains native verdict")
    off()
  end
  if f.api >= 3 then
    local off = e.api.hooks:wrap("battle.charge_required", function(next, ctx)
      local a, b = next(ctx), next(ctx)
      T.eq(a, b, "replayed next retains charge decision")
      return a
    end, 100)
    b = f.fresh("FLY")
    hp, pp, calls = b.hp(), b.pp(), e.state.calls
    b.use()
    out = observe("replay", b, hp, pp, calls)
    T.eq(out.calls, 1, "API-3 replay invokes downstream once")
    T.eq(out.spent, 1, "API-3 replay retains one native PP spend")
    off()
  end
  e.stop()
  e.stop()
  e.state.mode = "bypass"
  b = f.fresh("FLY")
  hp, pp, calls = b.hp(), b.pp(), e.state.calls
  b.use()
  out = observe("unsubscribed", b, hp, pp, calls)
  T.eq(out.calls, 0, "unsubscribe removes charge callback")
  T.eq(out.charging, true, "unsubscribe restores native charge")
  return rows
end
return M
