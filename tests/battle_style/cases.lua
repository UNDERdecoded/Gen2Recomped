local C = {}

function C.run(f)
  local T, e, rows = f.T, assert(f.exports, "portable consumer did not execute"), {}
  local cases = {
    { name = "native shift", mode = "forward", option = "shift", want = "shift", offer = true },
    { name = "native set", mode = "forward", option = "set", want = "set", offer = false },
    { name = "force set", mode = "set", option = "shift", want = "set", offer = false },
    { name = "force shift", mode = "shift", option = "set", want = "shift", offer = true },
    { name = "false fallback", mode = false, option = "shift", want = "shift", offer = true },
    { name = "zero fallback", mode = 0, option = "set", want = "set", offer = false },
    { name = "nil fallback", option = "shift", want = "shift", offer = true },
    { name = "uppercase invalid", mode = "SET", option = "shift", want = "shift", offer = true },
    { name = "invalid string", mode = "invalid", option = "SET", want = "set", offer = false },
    { name = "error fallback", mode = "error", option = "shift", want = "shift", offer = true },
  }
  for _, c in ipairs(cases) do
    e.set(c.mode)
    local b, save = f.battle(c.option)
    T.check(type(b.battleStyle) == "function", "native battle exposes battleStyle")
    if type(b.battleStyle) ~= "function" then
      return rows
    end
    local calls = e.calls()
    local value = b:battleStyle()
    T.eq(value, c.want, c.name .. " decision")
    T.eq(e.calls(), calls + 1, c.name .. " dispatches once")
    local offered = f.faint(b)
    T.eq(offered, c.offer, c.name .. " actual trainer send-out")
    T.eq(e.calls(), calls + 2, c.name .. " native faint dispatches once")
    T.eq(save.options.battleStyle, c.option, c.name .. " keeps saved option unchanged")
    rows[#rows + 1] = { name = c.name, decision = value, offer = offered, option = save.options.battleStyle }
  end

  e.set("shift")
  local single, save = f.battle("set")
  table.remove(save.party, 2)
  T.eq(f.faint(single), false, "forced shift retains one-party-slot exclusion")
  local fainted = f.battle("set")
  fainted.player.mon.hp = 0
  T.eq(f.faint(fainted), false, "forced shift retains fainted-player exclusion")
  local final = f.battle("set")
  for _, mon in ipairs(final.enemyParty) do
    mon.hp = 0
  end
  local calls = e.calls()
  f.faint(final)
  T.eq(e.calls(), calls, "final trainer faint does not query the unused decision")

  e.off()
  local b = f.battle("set")
  calls = e.calls()
  T.eq(b:battleStyle(), "set", "unsubscribe restores stored decision")
  T.eq(f.faint(b), false, "unsubscribe restores actual native set behavior")
  T.eq(e.calls(), calls, "unsubscribed consumer is never called")
  return rows
end

return C
