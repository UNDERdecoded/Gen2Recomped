package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local F = dofile("tests/gba_menu_prose/fixture.lua")
for _, version in ipairs({ "firered", "emerald" }) do
  local f = F.new(".", "gen2", version, "all", 3, "unified")
  local p = f.party
  local base = require("src.mods.Merge").deepCopy(f.data.constants)
  p.battle, p.onSwitch = {}, function() end
  local actions = p:actionsFor()
  T.same(
    { actions[1].label, actions[2].label, actions[3].label },
    { "MOD_SHIFT", "MOD_SUMMARY", "MOD_CANCEL" },
    "battle menu reads native labels"
  )
  T.same(
    { actions[1].action, actions[2].action, actions[3].action },
    { "switch", "summary", "cancel" },
    "battle action identities survive replacement"
  )
  p.forceSwitch = true
  T.eq(p:actionsFor()[1].label, "MOD_SEND_OUT", "forced-switch label")
  actions = p:itemActions()
  T.same(
    { actions[1].label, actions[2].label, actions[3].label },
    { "MOD_GIVE", "MOD_TAKE", "MOD_CANCEL" },
    "item submenu uses primary TAKE"
  )
  T.same(
    { actions[1].action, actions[2].action, actions[3].action },
    { "give", "take", "cancel" },
    "item action identities survive replacement"
  )
  p.chooseOrder = { most = 3 }
  T.eq(p:orderActionsFor(1)[1].label, "MOD_ENTER", "team-order entry")
  p.order = { 1 }
  T.eq(p:orderActionsFor(1)[1].label, "MOD_NO_ENTRY", "team-order removal")
  T.eq(p:word(5, "MOVES"), "MOVES", "unbound native word preserved")
  T.eq(p:actionWord("read", 9, "READ"), "READ", "unbound action preserved")
  T.eq(p:actionWord("takeMail", nil, "TAKE"), "MOD_TAKE", "reference primary TAKE reused")
  T.eq(
    p:actionWord("cancel2", nil, "OTHER CANCEL"),
    "OTHER CANCEL",
    "unmapped role does not borrow first cancel"
  )
  T.same(f.data.constants, base, "native readers preserve imported constants")
  f.data.constants.gen3PartyActions = nil
  p.words = nil
  T.eq(p:actionWord("summary", nil, "SUMMARY"), "MOD_SUMMARY", "older cache without action tables")
  T.eq(p:word(4, "SUMMARY"), "MOD_SUMMARY", "older battle-menu cache")
  f.data.constants = base
  local Font = require("src.render.Font")
  local captured, draw = {}, Font.draw
  Font.draw = function(text)
    captured[#captured + 1] = text
  end
  local pc = require("src.ui.Gen3ItemPcFRLG").new(f.game, {})
  local sub = require("src.ui.Gen3ItemPcSubmenu").new(f.game, pc, "POTION")
  local ok, err = pcall(sub.draw, sub)
  Font.draw = draw
  T.check(ok, "actual submenu render: " .. tostring(err))
  T.same(
    { captured[1], captured[2], captured[3] },
    version == "firered" and { "MOD_PC_WITHDRAW", "MOD_PC_GIVE", "MOD_FOOTER" }
      or { "WITHDRAW", "GIVE", "CANCEL" },
    "native submenu rendering respects profile boundary"
  )
  for index, kind in ipairs({ "withdraw", "give", "cancel" }) do
    local selected, popped = nil, 0
    f.game.stack.pop = function()
      popped = popped + 1
    end
    local menu = require("src.ui.Gen3ItemPcSubmenu").new(f.game, pc, "POTION", function(k)
      selected = k
    end)
    menu.index = index
    menu:keypressed("a")
    T.eq(selected, kind ~= "cancel" and kind or nil, "translated action still selects " .. kind)
    T.eq(popped, 1, "submenu closes exactly once")
    T.eq(pc.transientWindow, nil, "submenu releases native description window")
  end
  local custom = require("src.ui.Gen3ItemPcFRLG").new(f.game, { title = "TOSS ITEM" })
  T.eq(custom.title, "TOSS ITEM", "withdraw override cannot rename another dialog")
  local routed =
    require("src.ui.Gen3ItemPcFRLG").new(f.game, { title = "LOCALIZED BASE", nativeProse = true })
  T.eq(
    routed:titleText(),
    version == "firered" and "MOD_PC_TITLE" or "LOCALIZED BASE",
    "explicit native withdrawal title"
  )
  f.close()
  -- Match the existing registry-retirement fixture: discard unrelated builtin
  -- namespaces whose duplicate registration is a known baseline issue.
  for root in pairs(require("src.mods.Builtins").namespaceRoots()) do
    if root ~= "text" and root ~= "constants" then
      f.data[root] = nil
    end
  end
  local retired = T.sdk.loadMods({}, { data = f.data, generation = 3, fs = T.sdk.memfs({}), dev = false })
  T.eq(#retired.errors, 0, "empty reload succeeds")
  T.eq(routed:titleText(), "LOCALIZED BASE", "existing title reader retires removed owner")
  T.eq(sub:entries()[1].label, "WITHDRAW", "existing submenu reader retires removed owner")
  T.eq(p:actionWord("summary", nil, "SUMMARY"), "BASE_SUMMARY", "existing party reader retires removed owner")
  retired.release()
end
T.finish("native menu action and render integration")
