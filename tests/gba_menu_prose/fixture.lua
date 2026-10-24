local F = {}
F.roles = {
  { "summary", "SUMMARY", 0, "gText_Summary5" },
  { "switch", "SWITCH", 1, "gText_Switch2" },
  { "cancel", "CANCEL", 2, "gText_Cancel2" },
  { "item", "ITEM", 3, "gText_Item" },
  { "give", "GIVE", 4, "gMenuText_Give" },
  { "takeItem", "TAKE", 5, "gText_Take" },
  { "shift", "SHIFT", 10, "gText_Shift" },
  { "sendOut", "SEND OUT", 11, "gText_SendOut" },
  { "enter", "ENTER", 12, "gText_Enter" },
  { "noEntry", "NO ENTRY", 13, "gText_NoEntry" },
  { "store", "STORE", 14, "gText_Store" },
}
function F.new(root, backend, version, mode, api, format)
  local T, V = require("tests.modkit"), require("src.core.GameVersion")
  V.set(version)
  local J = require("src.link.Json")
  local data = backend == "gen1" and T.sdk.gen3Data() or { constants = { generation = 3 } }
  data.constants = data.constants or {}
  if backend == "gen1" then
    data.gen3RomText, data.gen3Text = {}, {}
  end
  local labels, texts, manifestLabels = {}, {}, {}
  for i = 1, 19 do
    manifestLabels[i] = "UNUSED_" .. i
  end
  for _, row in ipairs(F.roles) do
    local base = "BASE_" .. row[2]:gsub(" ", "_")
    labels[row[1]] = base
    texts["sCursorOptions[" .. row[3] .. "]"], texts[row[4]] = base, base
    manifestLabels[row[3] + 1] = base
  end
  texts.gFameCheckerText_Cancel, texts.gText_Cancel = "CANCEL", "CANCEL"
  texts.gText_Take2 = "BASE_OTHER_TAKE"
  texts.gText_WithdrawItem, texts.gText_Withdraw, texts.gOtherText_Give = "WITHDRAW ITEM", "WITHDRAW", "GIVE"
  texts.gText_TimesStrVar1, texts.gText_Var1IsSelected = "x{STR_VAR_1}", "{STR_VAR_1} selected."
  data.constants.gen3PartyActions = { labels = labels, fieldMoves = {} }
  data.constants.gen3Screens = {
    partyActions = {
      items = {
        labels.shift,
        labels.sendOut,
        labels.switch,
        labels.summary,
        "MOVES",
        labels.enter,
        labels.noEntry,
        labels.takeItem,
        "READ",
        "TRADE",
      },
    },
  }
  local files, name = {}, "portable_gba_menu_prose"
  for _, path in ipairs({ "main.lua", "manifest.json" }) do
    local h = assert(io.open(root .. "/examples/" .. name .. "/" .. path, "rb"))
    files["mods/" .. name .. "/" .. path] = h:read("*a")
    h:close()
  end
  local m = J.decode(files["mods/" .. name .. "/manifest.json"])
  m.api, m.content_format, m.games, m.gen2compat = api, format, { version }, api < 3 and true or nil
  files["mods/" .. name .. "/manifest.json"] = J.encode(m)
  files["mods/" .. name .. "/case.txt"] = mode
  if mode == "foreign" then
    files["mods/" .. name .. "/profile.txt"] = version == "firered" and "emerald" or "firered"
  end
  if mode == "no-mod" then
    files = {}
  end
  local r = T.sdk.loadMods(
    mode == "no-mod" and {} or { "mods/" .. name },
    { data = data, generation = 3, fs = T.sdk.memfs(files), dev = false }
  )
  local f = { T = T, data = data, result = r, e = r.loader.exports[name], backend = backend }
  f.game = {
    data = data,
    save = { player = { name = "PROBE" }, options = {}, party = {} },
    stack = { pop = function() end },
  }
  local restores = {}
  local function replace(t, k, v)
    local old = t[k]
    t[k] = v
    restores[#restores + 1] = function()
      t[k] = old
    end
  end
  f.replace = replace
  if backend == "gen1" then
    local IR, Rom = require("src.core.game3.scripting.text_ir"), require("src.core.game3.rom_text")
    local Space = require("src.core.game3.scripting.space")
    local ir = {}
    for k, v in pairs(texts) do
      ir[k] = IR.fromAscii(v)
    end
    replace(Space, "bundle", { text = ir })
    replace(Rom, "overrides", data.gen3RomText)
    local Party = require("src.ui.game3.party_menu")
    replace(Party, "_session", { version = version })
    replace(Party, "_actionTexts", nil)
    local Items = require("src.core.game3.items_data")
    for _, key in ipairs({ "_pack", "_byId", "_byName", "_logged" }) do
      replace(Items, key, Items[key])
    end
    Items.installPack({ items = { [13] = { name = "POTION", pocket = "ITEMS" } } })
    local Kit = require("src.ui.game3.rse.scene_kit")
    Kit.resetCaches()
    local info, load = love.filesystem.getInfo, love.filesystem.load
    local path = "data/generated/gba/rse/menus/manifest.lua"
    -- Supply generated fixture IO, so Emerald takes its actual manifest branch.
    replace(love.filesystem, "getInfo", function(p)
      if p == path then
        return { type = "file" }
      end
      return info(p)
    end)
    replace(love.filesystem, "load", function(p)
      if p == path then
        return function()
          return { party = { cursorOptions = manifestLabels, fieldMoves = {} } }
        end
      end
      return load(p)
    end)
    restores[#restores + 1] = Kit.resetCaches
    function f.actions()
      local names = {}
      for i, row in ipairs(F.roles) do
        names[i] = row[2]
      end
      return Party._actionTextsFor(names)
    end
    function f.footer()
      local Chrome, Font = require("src.ui.game3.party_chrome"), require("src.ui.game3.frlg_font")
      local result
      local draw = Font.draw
      Font.draw = function(t)
        result = t
      end
      local old = { Chrome._nativeDelegate, Chrome._manifest, Chrome._cancelBtn, Chrome._balls }
      Chrome._nativeDelegate, Chrome._manifest, Chrome._cancelBtn, Chrome._balls =
        nil,
        { palBuffer = { [51] = { 0, 0, 0 }, [50] = { 0, 0, 0 }, [53] = { 0, 0, 0 } } },
        {},
        { image = {}, frameCount = 1, quads = {} }
      local ok, err = pcall(Chrome.drawCancelButton, 184, 136, false)
      Chrome._nativeDelegate, Chrome._manifest, Chrome._cancelBtn, Chrome._balls = unpack(old)
      Font.draw = draw
      assert(ok, err)
      return result
    end
    function f.itemPc()
      local Pc, Font = require("src.ui.game3.item_pc"), require("src.ui.game3.frlg_font")
      local Window, BagChrome = require("src.ui.game3.window"), require("src.ui.game3.bag_chrome")
      local captured, undo = {}, {}
      local function patch(t, k, value)
        local old = t[k]
        t[k] = value
        undo[#undo + 1] = function()
          t[k] = old
        end
      end
      patch(Pc, "open", true)
      patch(Pc, "mode", "submenu")
      patch(Pc, "scroll", 0)
      patch(Pc, "row", 0)
      patch(Pc, "_session", { version = version, storage = { items = { { id = 13, qty = 1 } } } })
      patch(Pc, "_images", { bg = {}, bg_submenu = {} })
      patch(Pc, "subCursor", 1)
      patch(Font, "draw", function(t, x, y)
        captured[x .. ":" .. y] = t
      end)
      patch(Font, "drawGlyph", function() end)
      patch(BagChrome, "drawItemIcon", function() end)
      patch(Window, "stdFrame", function() end)
      patch(Window, "fixedStdFrame", function() end)
      local ok, err = pcall(Pc.draw)
      for i = #undo, 1, -1 do
        undo[i]()
      end
      assert(ok, err)
      return {
        captured["8:9"],
        captured["184:106"],
        captured["184:122"],
        captured["184:138"],
        captured["65:26"],
      }
    end
  else
    local Party = require("src.ui.Gen3PartyMenu")
    f.party = Party.new(f.game, {})
    function f.actions()
      local out = {}
      for i, row in ipairs(F.roles) do
        out[i] = f.party:actionWord(row[1], nil, row[2])
      end
      return out
    end
    function f.footer()
      return require("src.ui.GbaProse").partyCancel(f.game, "CANCEL")
    end
    function f.itemPc()
      local pc = require("src.ui.Gen3ItemPcFRLG").new(
        f.game,
        { rows = { { id = "POTION", label = "POTION" }, { close = true, label = "CANCEL" } } }
      )
      local sub = require("src.ui.Gen3ItemPcSubmenu").new(f.game, pc, "POTION")
      local entries, captured = sub:entries(), {}
      local Font = require("src.render.Font")
      local draw = Font.draw
      Font.draw = function(t)
        captured[#captured + 1] = t
      end
      local ok, err = pcall(pc.drawRows, pc)
      Font.draw = draw
      assert(ok, err)
      return { pc:titleText(), entries[1].label, entries[2].label, entries[3].label, captured[2] }
    end
  end
  function f.close()
    for i = #restores, 1, -1 do
      restores[i]()
    end
    r.release()
  end
  return f
end
return F
