package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Fixture, Cases = dofile("tests/gba_item_use/fixture.lua"), dofile("tests/gba_item_use/cases.lua")
local original = Version.get()
for _, version in ipairs({ "firered", "emerald" }) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    T.eq(f.e.api:supports("hooks", "item.use"), true, "native GBA field capability")
    Cases.run(f)
    local bike = f.game.data.items[f.id.MACH_BIKE]
    bike.key, bike.name = nil, "RENAMED PRESENTATION"
    local ok = f.use("MACH_BIKE")
    T.eq(ok, true, "renamed bike retains pristine item semantics")
    T.eq(f.biking(), true, "renamed bike mounts through native field dispatcher")
    f.close()
    for _, scenario in ipairs({ "block", "message", "redirect", "silent" }) do
      f = Fixture.new(".", "gen2", version, mode[1], mode[2])
      f.e.state.mode, f.e.state.redirect = scenario, f.canonicalIds and "SUPER_POTION" or f.id.SUPER_POTION
      local bag, picker = f.nativePicker("POTION")
      T.eq(f.e.state.calls, 0, "native GBA selection precedes field producer")
      f.press("a")
      T.eq(f.e.state.calls, 1, "native GBA target confirmation invokes field producer once")
      T.eq(f.e.state.argCount, 5, "native GBA UI dispatch has field argument shape")
      if scenario == "block" then
        T.eq(f.mon.hp, 15, "native blocked UI leaves HP unchanged")
        T.eq(f.count("POTION"), 3, "native blocked UI leaves inventory unchanged")
      else
        T.eq(f.mon.hp, scenario == "redirect" and 40 or 35, "native UI executes selected medicine")
        T.eq(f.count(scenario == "redirect" and "SUPER_POTION" or "POTION"), 2, "native UI consumes once")
      end
      local TextBox = require("src.render.TextBox")
      for _ = 1, 300 do
        if getmetatable(f.game.stack:top()) == TextBox or f.game.stack:top() == bag then
          break
        end
        f.press()
      end
      if scenario == "silent" then
        T.eq(f.game.stack:top(), bag, "nil result text closes picker after native animation")
      else
        T.eq(getmetatable(f.game.stack:top()), TextBox, "native result text follows HP animation")
      end
      if scenario == "block" or scenario == "message" then
        local box = f.game.stack:top()
        local text = scenario == "block" and "PORTABLE BLOCK" or "PORTABLE TEXT"
        T.same(
          box.pages,
          TextBox.paginate(text, box.maxCols, box.letterSpacing, box.maxPixels),
          "native UI presents wrapper's final result text"
        )
      end
      T.eq(f.e.state.calls, 1, "native animation does not re-enter item hook")
      f.close()
    end
    f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    f.fullMoves()
    f.e.state.mode = "message"
    f.nativePicker("TM_01")
    f.press("a")
    T.eq(f.count("TM_01"), 3, "full TM awaits successful native learning")
    for _ = 1, 1200 do
      local found
      for _, screen in ipairs(f.game.stack.states) do
        if getmetatable(screen) == require("src.ui.Gen3MoveLearnMenu") then
          found = screen
          break
        end
      end
      if found then
        T.eq(found.newMoveId, "FIX_CUT", "post-next text cannot overwrite native move operand")
        break
      end
      f.press("a")
    end
    local found = false
    for _, screen in ipairs(f.game.stack.states) do
      if getmetatable(screen) == require("src.ui.Gen3MoveLearnMenu") then
        found = true
      end
    end
    T.eq(found, true, "full TM retains actual native learning screen")
    f.close()
    local failed = Fixture.new(".", "gen2", version, mode[1], mode[2], false, true)
    T.check(#failed.result.errors > 0, "entry failure is recorded")
    for _, entry in ipairs(Runtime.hooks.chains["item.use"] or {}) do
      T.check(entry.owner ~= "portable_gba_item_use", "entry rollback removes GBA item wrapper")
    end
    local ok, kind = failed.use("POTION", 1)
    T.eq(ok, true, "failed entry restores native field effect")
    T.eq(kind, "heal", "failed entry restores native field result kind")
    T.eq(failed.count("POTION"), 2, "failed entry leaves native consumption once")
    failed.close()
  end
end
-- Flute state affects the actual native encounter modifier, including an
-- empty party, and never applies to GB/Gold/DS hosts.
local Encounter = require("src.world.Encounter")
for _, version in ipairs(Version.ORDER) do
  Version.set(version)
  local data, save = { pokemon = {} }, { party = {}, gen3Flute = "white" }
  local value = Encounter.leadRateMod(data, save)
  if Version.isGen3() then
    T.same(value, { 3, 2 }, "white flute native encounter ratio")
  else
    T.eq(value, nil, "flute state cannot alter other generations")
  end
  save.gen3Flute = "black"
  value = Encounter.leadRateMod(data, save)
  if Version.isGen3() then
    T.same(value, { 1, 2 }, "black flute native encounter ratio")
  else
    T.eq(value, nil, "black flute state cannot alter other generations")
  end
end
Version.set(original)
T.finish("native GBA field item tuple and UI adapter")
