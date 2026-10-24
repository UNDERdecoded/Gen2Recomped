local M = {}
function M.run(f)
  local T, e, mon, rows = f.T, f.e, f.mon, {}
  for _, key in ipairs({ "POTION", "AWAKENING", "REVIVE", "ETHER", "COIN_CASE" }) do
    if key == "AWAKENING" then
      mon.status = "SLP"
    end
    if key == "REVIVE" then
      mon.hp = 0
    end
    e.state.mode = "block"
    local hp, count, pp = mon.hp, f.count(key), f.pp()
    local ok, kind, text = f.use(key, key ~= "COIN_CASE" and 1 or nil, key == "ETHER" and 1 or nil)
    T.eq(ok, false, "block refuses native field effect")
    T.eq(kind, "blocked", "block preserves replacement kind")
    T.eq(text, "PORTABLE BLOCK", "block preserves replacement text")
    T.eq(mon.hp, hp, "block preserves HP")
    T.eq(f.count(key), count, "block preserves bag")
    T.eq(f.pp(), pp, "block preserves PP")
    T.eq(e.state.argCount, 5, "GBA native field signature has five arguments")
    T.eq(e.state.game, f.game, "original Game handle")
    T.eq(e.state.battle, nil, "field battle hole is preserved")
    T.eq(e.state.slot, key ~= "COIN_CASE" and 1 or nil, "party slot is primitive")
    e.state.mode = "native"
    ok, kind, text = f.use(key, key ~= "COIN_CASE" and 1 or nil, key == "ETHER" and 1 or nil)
    T.eq(ok, true, "native field effect succeeds")
    T.eq(e.state.returnCount, 3, "native field result has three values")
    T.eq(
      f.count(key),
      count - (key == "COIN_CASE" and 0 or 1),
      "native field consumes once or keeps key item"
    )
    rows[#rows + 1] = {
      item = key,
      ok = ok,
      kind = kind,
      hp = mon.hp,
      pp = f.pp(),
      count = f.count(key),
      textType = type(text),
    }
  end
  local function observe(label, key, slot, move)
    local ok, kind, text = f.use(key, slot, move)
    rows[#rows + 1] = {
      label = label,
      ok = ok == true,
      kind = kind,
      textType = type(text),
      hp = mon.hp,
      pp = f.pp(),
      count = f.count(key),
    }
    return ok, kind, text
  end
  mon.hp = 40
  local before = f.count("POTION")
  local ok, kind = observe("no effect", "POTION", 1)
  T.eq(ok, false, "native no-effect is false")
  T.eq(kind, "noeffect", "native no-effect kind")
  T.eq(f.count("POTION"), before, "native no-effect does not consume")
  ok, kind = observe("missing slot", "POTION")
  T.eq(ok, false, "missing target slot refused")
  T.eq(kind, "need_slot", "missing slot kind")
  ok, kind = observe("invalid slot", "POTION", 99)
  T.eq(ok, false, "invalid target slot refused")
  T.eq(kind, "noparty", "invalid slot kind")
  ok, kind = observe("missing move", "ETHER", 1)
  T.eq(ok, false, "missing move index refused")
  T.eq(kind, "need_move", "missing move kind")
  f.fill()
  observe("repel", "REPEL")
  local counter = f.count("REPEL")
  ok, kind = observe("repel active", "REPEL")
  T.eq(ok, false, "active Repel is not replaced")
  T.eq(kind, "repel", "active Repel refusal retains field kind")
  T.eq(f.count("REPEL"), counter, "active Repel refusal does not consume")
  mon.hp = 15
  e.state.mode = "message"
  local text
  ok, kind, text = observe("replace text", "POTION", 1)
  T.eq(text, "PORTABLE TEXT", "post-next text replacement reaches caller")
  T.eq(f.count("POTION"), 2, "text replacement consumes once")
  e.state.mode, e.state.redirect = "redirect", f.canonicalIds and "SUPER_POTION" or f.id.SUPER_POTION
  mon.hp = 15
  observe("redirect", "POTION", 1)
  T.eq(f.count("POTION"), 2, "redirect keeps original item")
  T.eq(f.count("SUPER_POTION"), 2, "redirect consumes replacement item")
  T.eq(mon.hp, 40, "redirect runs replacement native medicine")
  e.state.mode = "native"
  for _, key in ipairs({ "OLD_ROD", "ESCAPE_ROPE", "EVERSTONE", "UNKNOWN" }) do
    ok = observe("native refusal:" .. key, key)
    T.eq(ok, false, "native field preflight rejects unavailable action")
    T.eq(f.count(key), 3, "native field refusal does not consume")
  end
  e.state.mode = "silent"
  mon.hp = 15
  local text
  ok, kind, text = observe("silent result", "POTION", 1)
  T.eq(text, nil, "post-next nil text is preserved")
  T.eq(f.count("POTION"), 1, "silent result consumes once")
  e.state.mode = "native"
  local off = e.api.hooks:wrap("item.use", function(next, game, battle, id, _, bag)
    return next(game, battle, id, 2, bag)
  end, 100)
  f.fill()
  mon.hp, f.second.hp = 15, 5
  observe("replacement slot", "POTION", 1)
  T.eq(mon.hp, 15, "replacement slot retains original target")
  T.eq(f.second.hp, 25, "replacement slot reaches native second party mon")
  T.eq(e.state.slot, 2, "replacement slot remains an integer")
  off()
  observe("white flute", "WHITE_FLUTE")
  T.eq(f.flute(), "white", "white flute enables native state")
  observe("black flute", "BLACK_FLUTE")
  T.eq(f.flute(), "black", "black flute replaces white native state")
  T.eq(f.count("WHITE_FLUTE"), 3, "white flute is reusable")
  T.eq(f.count("BLACK_FLUTE"), 3, "black flute is reusable")
  observe("bike mount", "MACH_BIKE")
  T.eq(f.biking(), true, "native bicycle mounts")
  observe("bike dismount", "MACH_BIKE")
  T.eq(f.biking(), false, "native bicycle dismounts")
  observe("TM teach", "TM_01", 1)
  T.eq(#mon.moves, 2, "native TM teach changes party moves")
  T.eq(f.count("TM_01"), 2, "native TM teach consumes once")
  ok, kind = observe("TM known", "TM_01", 1)
  T.eq(ok, false, "known TM refuses")
  T.eq(kind, "knows", "known TM reason survives field boundary")
  T.eq(f.count("TM_01"), 2, "known TM refusal does not consume")
  f.fullMoves()
  ok, kind = observe("TM full", "TM_01", 1)
  T.eq(ok, false, "full move set requires native learning continuation")
  T.eq(kind, "full", "full move set preserves field result kind")
  T.eq(#mon.moves, 4, "full move set is not replaced before selection")
  T.eq(f.count("TM_01"), 2, "pending TM does not consume")
  for _, after in ipairs({ false, true }) do
    local off = e.api.hooks:wrap("item.use", function(next, ...)
      if after then
        next(...)
      end
      error("intentional GBA item wrapper failure")
    end, 100)
    f.fill()
    mon.hp = 15
    local before = e.state.calls
    observe("failure:" .. tostring(after), "POTION", 1)
    T.eq(e.state.calls, before + 1, "wrapper failure runs downstream once")
    T.eq(f.count("POTION"), 2, "wrapper failure cannot double-consume")
    off()
  end
  if f.api >= 3 then
    local off = e.api.hooks:wrap("item.use", function(next, ...)
      local before = e.state.calls
      local function pack(...)
        return { n = select("#", ...), ... }
      end
      local a, b = pack(next(...)), pack(next(...))
      T.eq(a.n, 3, "first next returns GBA triple")
      T.same(a, b, "repeated next retains GBA result")
      T.eq(e.state.calls, before + 1, "repeated next reaches downstream once")
      return unpack(a, 1, a.n)
    end, 100)
    f.fill()
    mon.hp = 15
    observe("replay", "POTION", 1)
    T.eq(f.count("POTION"), 2, "replayed GBA next consumes once")
    off()
  end
  e.stop()
  e.stop()
  f.fill()
  mon.hp = 15
  local beforeCalls = e.state.calls
  observe("unsubscribed", "POTION", 1)
  T.eq(e.state.calls, beforeCalls, "unsubscribe stops native GBA callbacks")
  T.eq(f.count("POTION"), 2, "unsubscribe restores ordinary native use")
  return rows
end
return M
