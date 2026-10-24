local M = {}
function M.run(f)
  local T, e, rows = f.T, f.e, {}
  local mon = f.game.save.party[1]
  local function observe(label, id)
    rows[#rows + 1] =
      { label = label, count = f.count(id), hp = mon.hp, status = mon.status or false, item = e.state.item }
  end
  for _, inBattle in ipairs({ false, true }) do
    for _, id in ipairs({ "POTION", "ANTIDOTE", "ETHER" }) do
      e.state.mode = "block"
      local beforePicker = e.state.calls
      f.begin(id, inBattle)
      T.eq(e.state.calls, beforePicker, "target selection itself has no effect")
      local hp, count, status = mon.hp, f.count(id), mon.status
      local calls = e.state.calls
      f.target()
      if id == "ETHER" then
        f.move()
      end
      T.eq(e.state.calls, calls + 1, "selected native item dispatch reaches public hook once")
      T.eq(mon.hp, hp, "blocking prevents HP effect")
      T.eq(mon.status, status, "blocking prevents status effect")
      T.eq(f.count(id), count, "blocking preserves inventory")
      T.eq(e.state.game, f.game, "original opaque Game is preserved")
      T.eq(e.state.target, mon, "native target identity is preserved")
      T.eq(e.state.item, id, "public canonical item ID")
      T.eq(e.state.battle ~= nil, inBattle, "battle presence is preserved")
      if id == "ETHER" then
        T.eq(e.state.moveIndex, 1, "chosen move index is forwarded")
      end
      observe("blocked:" .. tostring(inBattle), id)
      e.state.mode = "native"
      f.begin(id, inBattle)
      f.target()
      if id == "ETHER" then
        f.move()
      end
      T.eq(f.count(id), 2, "delegating consumes native item once")
      if id == "POTION" then
        T.eq(mon.hp, hp + 20, "native medicine heals")
      end
      if id == "ANTIDOTE" then
        T.eq(mon.status, nil, "native status medicine cures")
      end
      if id == "ETHER" then
        T.eq(mon.moves[1].pp, 10, "native move medicine restores chosen move")
      end
      observe("delegated:" .. tostring(inBattle), id)
    end
  end
  for _, id in ipairs({ "REPEL", "INVALID", "BICYCLE", "OLD_ROD", "POKE_BALL", "POKE_DOLL", "X_ATTACK" }) do
    e.state.mode = "block"
    local before = e.state.calls
    f.begin(id, id == "POKE_BALL" or id == "POKE_DOLL" or id == "X_ATTACK")
    T.eq(e.state.calls, before + 1, "whole-dispatch hook includes untargeted branch " .. id)
    T.eq(f.count(id), 3, "whole-dispatch refusal prevents native consume " .. id)
    T.eq(f.game.save.onBike, nil, "blocked bicycle cannot mount")
    observe("blocked:branch", id)
  end
  for _, id in ipairs({ "TM_01", "MOON_STONE" }) do
    e.state.mode = "block"
    f.begin(id, false)
    local before = e.state.calls
    local species, moves = mon.species, #mon.moves
    f.target()
    T.eq(e.state.calls, before + 1, "machine/stone reaches native whole-dispatch hook")
    T.eq(f.count(id), 3, "blocked machine/stone is not consumed")
    T.eq(mon.species, species, "blocked stone cannot evolve target")
    T.eq(#mon.moves, moves, "blocked machine cannot teach a move")
    observe("blocked:targeted branch", id)
  end
  f.begin("POTION", false)
  local beforeCancel = e.state.calls
  f.press("b")
  T.eq(e.state.calls, beforeCancel, "cancelled target selection never dispatches item use")
  T.eq(f.count("POTION"), 3, "cancelled target selection preserves inventory")
  -- A native no-effect decision remains inside the wrapper's reach.
  e.state.mode = "native"
  f.begin("POTION", false)
  mon.hp = mon.stats.hp
  f.target()
  T.eq(f.count("POTION"), 3, "native no-effect medicine is not consumed")
  observe("no effect", "POTION")
  e.state.mode, e.state.redirect = "redirect", "SUPER_POTION"
  f.begin("POTION", false)
  require("src.inventory.Bag").add(f.game.save, "SUPER_POTION", 3, f.game.data)
  f.target()
  T.eq(mon.hp, mon.stats.hp, "replacement ID reaches native effect dispatcher")
  T.eq(f.count("SUPER_POTION"), 2, "replacement consumes the selected replacement item")
  T.eq(f.count("POTION"), 3, "replacement retains original inventory")
  observe("redirect", "SUPER_POTION")
  e.state.mode = "native"
  for _, after in ipairs({ false, true }) do
    local stop = e.api.hooks:wrap("item.use", function(next, ...)
      if after then
        next(...)
      end
      error("intentional item wrapper failure")
    end, 100)
    f.begin("POTION", false)
    local before = e.state.calls
    f.target()
    T.eq(e.state.calls, before + 1, "wrapper failure calls downstream once")
    T.eq(f.count("POTION"), 2, "wrapper failure cannot double-consume")
    observe("failure:" .. tostring(after), "POTION")
    stop()
  end
  if f.api >= 3 then
    local stop = e.api.hooks:wrap("item.use", function(next, ...)
      local before = e.state.calls
      T.eq(select("#", ...), 7, "native dispatch retains holes and trailing picker")
      T.eq(select("#", next(...)), 0, "GB UI dispatch has no result tuple")
      T.eq(select("#", next(...)), 0, "repeated next keeps empty return arity")
      T.eq(e.state.calls, before + 1, "API-3 repeated next evaluates downstream once")
    end, 100)
    f.begin("POTION", false)
    f.target()
    T.eq(f.count("POTION"), 2, "API-3 repeated next consumes once")
    observe("replay", "POTION")
    stop()
  end
  e.stop()
  e.stop()
  local before = e.state.calls
  f.begin("POTION", false)
  f.target()
  T.eq(e.state.calls, before, "unsubscribe removes native item wrapper")
  T.eq(f.count("POTION"), 2, "unsubscribe restores native item use")
  observe("unsubscribed", "POTION")
  return rows
end
return M
