package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local Fixture = dofile("tests/party_grid/fixture.lua")
local Cases = dofile("tests/party_grid/cases.lua")
local old = Version.get()
for _, version in ipairs(Version.ORDER) do
  Version.set(version)
  if Version.generation() <= 3 then
    for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
      local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
      Cases.run(f)
      f.count(6)
      f.index(1)
      T.eq(f.press("right"), f.generation == 3 and 2 or 1, "unwrapped native horizontal navigation")
      f.index(1)
      T.eq(f.press("up"), f.generation == 3 and "cancel" or 6, "unwrapped native vertical navigation")
      f.index(1)
      local menu, api, game = f.menu, f.exports.api, f.game
      local calls = 0
      local off = api.hooks:wrap("ui.party.grid_navigation", function()
        calls = calls + 1
        return true
      end)
      if mode[1] >= 3 then
        local outer = api.hooks:wrap("ui.party.grid_navigation", function(next)
          next()
          return next()
        end, 100)
        T.eq(f.grid(), true, "API 3 retains grid decision")
        T.eq(calls, 1, "API 3 repeated next is cached")
        outer()
      end
      f.count(5)
      f.index(1)
      menu.submenu, menu.subItems, menu.subIndex =
        { { action = "CANCEL" }, { action = "CANCEL" } }, { "A", "B" }, 1
      local before = calls
      f.press("down")
      T.eq(f.index(), 1, "submenu owns cursor input")
      T.eq(menu.subIndex, 2, "submenu uses its own navigation")
      T.eq(calls, before, "submenu bypasses grid predicate")
      menu.submenu = nil
      local mon = game.save.party[1]
      menu.heal = { mon = mon, shown = 0 }
      before = calls
      f.press("right")
      T.eq(f.index(), 1, "healing animation owns input")
      T.eq(calls, before, "healing bypasses grid predicate")
      menu.heal = nil
      if f.generation == 3 then
        menu.noInput = true
        f.press("right")
        T.eq(f.index(), 1, "scripted no-input screen retains cursor")
        T.eq(calls, before, "no-input bypasses predicate")
        menu.noInput = false
        local record = game.data.constants.gen3PartyMenu
        record.slots[2].icon.y, record.slots[3].icon.y = 40, 80
        T.eq(f.press("right"), 2, "imported sprite coordinates determine spatial peer")
        game.data.constants.gen3PartyMenu = nil
        f.index(1)
        T.eq(f.press("right"), 3, "old-cache fallback uses rendered panel positions")
        game.data.constants.gen3PartyMenu = record
        f.count(0)
        f.index("cancel")
        T.eq(f.press("up"), "cancel", "empty GBA party retains cancel")
      else
        f.count(0)
        f.index(1)
        T.eq(f.press("right"), 1, "empty GB party retains cursor")
      end
      f.count(6)
      f.index(1)
      local confirm, cancel = 0, 0
      local oldConfirm, oldCancel = menu.confirm, menu.cancel
      menu.confirm = function()
        confirm = confirm + 1
      end
      menu.cancel = function()
        cancel = cancel + 1
      end
      f.press("a")
      f.press("b")
      T.eq(confirm, 1, "native confirm handler remains reachable")
      T.eq(cancel, 1, "native cancel handler remains reachable")
      f.press({ right = true, a = true })
      T.eq(confirm, f.generation == 3 and 2 or 1, "combined input retains generation-specific priority")
      menu.confirm, menu.cancel = oldConfirm, oldCancel
      off()
      f.close()
    end
  else
    T.eq(
      require("src.mods.Capabilities").supports("hooks", "ui.party.grid_navigation", version),
      false,
      "DS has no shared party producer yet"
    )
  end
end
Version.set(old)
T.finish("portable ui.party.grid_navigation native controllers")
