-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- 109 SCRIPT ROWS ASKED FOR A WINDOW THAT WAS NOT THERE.
--
-- `showmoney`, `hidemoney` and `updatemoneydisplay` lowered onto `g4_noop`
-- with the subjects "money box" and "the money window refresh". The census
-- that found the door sounds (rank every declined subject by its real
-- invocation count over the decoded corpus) puts them second: **109**, behind
-- doors at 194 and ahead of the journal at 78.
--
-- It is not the shop's balance -- `ShopMenu` has one of those. This is the
-- standalone window a FIELD script puts up while you decide: the Game Corner,
-- the Day-Care's fee, the Ribbon Syndicate, Floaroma's flower seller, the
-- Pastoria gates, the cafe.
--
-- THE ONE THING MOST LIKELY TO BE SILENTLY WRONG IS THE OPERAND ORDER, and
-- pret's middle layer is actively misleading about it:
--
--     ScrCmd_ShowMoney:  tilemapLeft = GetVar; tilemapTop = GetVar;
--                        FieldMenu_CreateMoneyWindow(fs, tilemapLeft, tilemapTop)
--     FieldMenu_CreateMoneyWindow(FieldSystem *fs, u8 tilemapTop, u8 tilemapLeft)
--                        Window_Add(..., tilemapTop, tilemapLeft, ...)
--     Window_Add(..., u8 tilemapLeft, u8 tilemapTop, ...)
--
-- The names are swapped twice and cancel: operand one is the LEFT. Section 2
-- derives that from all three signatures AND from the call sites, because a
-- reader who follows only the function's parameter names gets it backwards and
-- puts the window off the bottom of the screen.
--
-- Run:  texlua tools/gen4_money_window_check.lua <data/generated> [pokeplatinum] [rom]

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local CACHE = arg and arg[1]
local PRET  = arg and arg[2]
local ROM   = arg and arg[3]

local fails, checks, reports, skips = 0, 0, 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function report(fmt, ...)
  reports = reports + 1
  io.write("REPORT: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function skip(fmt, ...)
  skips = skips + 1
  io.write("SKIP: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(p)
  if not p then return nil end
  local f = io.open(p, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function loadTable(dir, name)
  if not dir then return nil end
  local f = loadfile(dir .. "/" .. name .. ".lua")
  if not f then return nil end
  local okRun, t = pcall(f)
  return okRun and t or nil
end
local function code(src)
  if not src then return "" end
  return (src:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\r\n]*", " "))
end
local function cdefn(src, name)
  return src and src:match("[%w_%*%s]-" .. name .. "%s*%b()%s*\n{(.-)\n}")
end

local drawn = {}
love = love or {
  graphics = { getWidth = function() return 256 end,
               getHeight = function() return 192 end,
               getDimensions = function() return 256, 192 end,
               getPixelDimensions = function() return 256, 192 end,
               getDPIScale = function() return 1 end,
               newCanvas = function() return nil end,
               newImage = function() return nil end,
               setColor = function() end, rectangle = function() end,
               push = function() end, pop = function() end,
               setFont = function() end },
  window = { getMode = function() return 256, 192, {} end },
  timer = { getTime = function() return 0 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  system = { getOS = function() return "Linux" end },
  image = { newImageData = function() return nil end },
  math = { random = math.random },
}

local GameVersion = require("src.core.GameVersion")
GameVersion.set("platinum")
local MW       = require("src.ui.Gen4MoneyWindow")
local Commands = require("src.script.Commands")
local Gen4Commands = require("src.script.Gen4Commands")

ok(type(Commands.g4_money_window) == "function",
   "g4_money_window has no handler, so the rows the lowering emits reach "
   .. "nothing -- and the Gen 4 verbs may not be on the shared Commands table")

-- ---------------------------------------------------------------------------
section("1. the geometry, against pokeplatinum")
-- ---------------------------------------------------------------------------
-- NEEDS NOTHING but the repository, so this check has something that can fail
-- with no cache, no pret and no cartridge.
ok(MW.WIDTH_TILES == 10 and MW.HEIGHT_TILES == 4,
   "the window is %sx%s tiles; field_menu.c says 10x4",
   tostring(MW.WIDTH_TILES), tostring(MW.HEIGHT_TILES))
ok(MW.ROW_PITCH == 16,
   "the row pitch is %s; GLYPH_ROW_HEIGHT is 16", tostring(MW.ROW_PITCH))
ok(MW.DIGITS == 6,
   "the amount is padded to %s digits; StringTemplate_SetNumber is given 6",
   tostring(MW.DIGITS))
ok(MW.BANK == 543 and MW.LABEL_ENTRY == 18 and MW.AMOUNT_ENTRY == 19,
   "the window reads bank %s entries %s and %s; the cartridge reads 543, 18 "
   .. "and 19", tostring(MW.BANK), tostring(MW.LABEL_ENTRY),
   tostring(MW.AMOUNT_ENTRY))

if not PRET then
  skip("no pokeplatinum checkout, so the geometry, the operand order and the "
       .. "bank number are unverified against pret")
else
  local fm = slurp(PRET .. "/src/overlay005/field_menu.c")
  ok(fm ~= nil, "src/overlay005/field_menu.c is not readable")
  if fm then
    for name, want in pairs({ MONEY_WINDOW_WIDTH = MW.WIDTH_TILES,
                              MONEY_WINDOW_HEIGHT = MW.HEIGHT_TILES,
                              GLYPH_ROW_HEIGHT = MW.ROW_PITCH }) do
      local got = tonumber(fm:match("#define%s+" .. name .. "%s+(%d+)"))
      ok(got == want, "pret's %s is %s; this port uses %s", name,
         tostring(got), tostring(want))
    end
    -- the number's format: six digits AND SPACES, not zeros
    local printer = cdefn(fm, "FieldMenu_PrintMoneyToWindow")
    ok(printer ~= nil, "FieldMenu_PrintMoneyToWindow is not defined")
    if printer then
      local digits = tonumber(printer:match(
        "StringTemplate_SetNumber%s*%([^,]*,[^,]*,[^,]*,%s*(%d+)"))
      ok(digits == MW.DIGITS,
         "pret formats the balance to %s digits; this port uses %s",
         tostring(digits), tostring(MW.DIGITS))
      ok(printer:find("PADDING_MODE_SPACES", 1, true) ~= nil,
         "pret no longer space-pads the balance -- zero-padding a "
         .. "right-aligned number changes what is on screen")
      -- RIGHT-ALIGNED to the window's own right edge
      ok(printer:find("MONEY_WINDOW_WIDTH %* TILE_WIDTH_PIXELS%) %- Font_CalcStringWidth")
         ~= nil or printer:find("%- Font_CalcStringWidth") ~= nil,
         "pret no longer right-aligns the amount, which is what the padding "
         .. "is for")
      -- ...and on the SECOND glyph row
      ok(printer:find("GLYPH_ROW_HEIGHT") ~= nil,
         "pret no longer prints the amount a glyph row down from the label")
    end
    -- the label is entry 18, printed at the window's own origin
    local creator = cdefn(fm, "FieldMenu_CreateMoneyWindow")
    ok(creator ~= nil, "FieldMenu_CreateMoneyWindow is not defined")
    if creator then
      local label = tonumber(creator:match("pl_msg_00000543_000(%d+)"))
      ok(label == MW.LABEL_ENTRY,
         "pret's label is bank-543 entry %s; this port reads %s",
         tostring(label), tostring(MW.LABEL_ENTRY))
      ok(creator:find("Text_AddPrinterWithParams%b(),?") ~= nil
         or creator:find("Text_AddPrinterWithParams") ~= nil,
         "pret no longer prints the label")
    end
    if printer then
      local amount = tonumber(printer:match("pl_msg_00000543_000(%d+)"))
      ok(amount == MW.AMOUNT_ENTRY,
         "pret's amount format is bank-543 entry %s; this port reads %s",
         tostring(amount), tostring(MW.AMOUNT_ENTRY))
    end
  end
  -- the bank, by the line-minus-one rule the rest of the port uses
  local banks = slurp(PRET .. "/generated/text_banks.txt")
  if not banks then
    skip("generated/text_banks.txt is not readable")
  else
    local line = 0
    local found
    for name in banks:gmatch("[^\r\n]+") do
      line = line + 1
      if name == "TEXT_BANK_UNK_0543" then found = line - 1 end
    end
    ok(found == MW.BANK,
       "TEXT_BANK_UNK_0543 is line %s of text_banks.txt, so bank %s; this "
       .. "port uses %d", tostring(found and found + 1), tostring(found),
       MW.BANK)
  end
end

-- ---------------------------------------------------------------------------
section("2. the operand order, three ways")
-- ---------------------------------------------------------------------------
if not PRET then
  skip("no pokeplatinum checkout, so the operand order is unverified")
else
  local sm = slurp(PRET .. "/src/scrcmd_money.c")
  local fm = slurp(PRET .. "/src/overlay005/field_menu.c")
  local bw = slurp(PRET .. "/include/bg_window.h")
  if not (sm and fm and bw) then
    skip("scrcmd_money.c, field_menu.c or bg_window.h is not readable")
  else
    -- (a) the script command reads LEFT first
    local body = cdefn(sm, "ScrCmd_ShowMoney")
    ok(body ~= nil, "ScrCmd_ShowMoney is not defined")
    if body then
      local first = body:match("u16%s+tilemap(%a+)%s*=%s*ScriptContext_GetVar")
      ok(first == "Left",
         "the first operand ScrCmd_ShowMoney reads is tilemap%s, not "
         .. "tilemapLeft", tostring(first))
    end
    -- (b) the middle function's parameters are SWAPPED relative to its name
    local sig = fm:match("Window %*FieldMenu_CreateMoneyWindow%s*%(([^)]*)%)")
    ok(sig ~= nil, "could not read FieldMenu_CreateMoneyWindow's signature")
    if sig then
      local p1 = sig:match("u8%s+tilemap(%a+)")
      ok(p1 == "Top",
         "FieldMenu_CreateMoneyWindow's first u8 parameter is tilemap%s; the "
         .. "swap this check exists to pin is that it is named Top while "
         .. "receiving the LEFT", tostring(p1))
    end
    -- (c) and Window_Add takes left first, so the two swaps cancel
    local add = bw:match("void Window_Add%s*%(([^)]*)%)")
    ok(add ~= nil, "could not read Window_Add's declaration")
    if add then
      local order = {}
      for n in add:gmatch("u8%s+tilemap(%a+)") do order[#order + 1] = n end
      ok(order[1] == "Left" and order[2] == "Top",
         "Window_Add takes tilemap%s then tilemap%s; if that order ever "
         .. "changes the double swap stops cancelling and the window moves",
         tostring(order[1]), tostring(order[2]))
    end
  end
  -- (d) THE CALL SITES SETTLE IT. Every ShowMoney in the cartridge puts the
  -- window in the right half of a 32-tile screen, which is only true if the
  -- first operand is the left.
  local sites, lefts, tops = 0, {}, {}
  local p = io.popen('ls "' .. PRET .. '/res/field/scripts/" 2>/dev/null')
  if p then
    for name in p:lines() do
      if name:match("%.s$") then
        local body = slurp(PRET .. "/res/field/scripts/" .. name)
        for a, b in (body or ""):gmatch("ShowMoney%s+(%d+),%s*(%d+)") do
          sites = sites + 1
          lefts[tonumber(a)] = (lefts[tonumber(a)] or 0) + 1
          tops[tonumber(b)] = (tops[tonumber(b)] or 0) + 1
        end
      end
    end
    p:close()
  end
  ok(sites >= 8,
     "only %d ShowMoney call site(s) with literal operands were read, which "
     .. "is too few to settle the order", sites)
  if sites >= 8 then
    local maxLeft, maxTop = 0, 0
    for v in pairs(lefts) do if v > maxLeft then maxLeft = v end end
    for v in pairs(tops) do if v > maxTop then maxTop = v end end
    -- a 10-tile window on a 32-tile screen: a left of 20 fits, a top of 20
    -- would be off a 24-tile-tall screen
    ok(maxLeft + MW.WIDTH_TILES <= 32,
       "the largest first operand is %d, and a %d-tile window there runs off "
       .. "a 32-tile screen -- which would mean the first operand is NOT the "
       .. "left", maxLeft, MW.WIDTH_TILES)
    ok(maxTop + MW.HEIGHT_TILES <= 24,
       "the largest second operand is %d, and a %d-tile window there runs off "
       .. "a 24-tile screen", maxTop, MW.HEIGHT_TILES)
    ok(maxLeft > maxTop,
       "the first operand's largest value (%d) is not bigger than the "
       .. "second's (%d); on a wider-than-tall screen the left is the one "
       .. "that gets large", maxLeft, maxTop)
    local ls, ts = {}, {}
    for v, n in pairs(lefts) do ls[#ls + 1] = ("%d x%d"):format(v, n) end
    for v, n in pairs(tops) do ts[#ts + 1] = ("%d x%d"):format(v, n) end
    table.sort(ls); table.sort(ts)
    report("%d call sites: first operand %s, second %s", sites,
           table.concat(ls, ", "), table.concat(ts, ", "))
  end
end

-- ---------------------------------------------------------------------------
section("3. the panel, built from the cartridge's own two strings")
-- ---------------------------------------------------------------------------
local text = loadTable(CACHE, "text")
if not text then
  skip("no text.lua in this cache, so the window's two lines are unverified")
else
  local Gen4Text = require("src.import.Gen4Text")
  local rawLabel = text[Gen4Text.label(MW.BANK, MW.LABEL_ENTRY)]
  local rawAmount = text[Gen4Text.label(MW.BANK, MW.AMOUNT_ENTRY)]
  ok(type(rawLabel) == "string" and rawLabel ~= "",
     "bank %d entry %d is absent, so the window has no label", MW.BANK,
     MW.LABEL_ENTRY)
  ok(type(rawAmount) == "string" and rawAmount ~= "",
     "bank %d entry %d is absent, so the window has no amount", MW.BANK,
     MW.AMOUNT_ENTRY)
  report("label %q, amount %q", tostring(rawLabel), tostring(rawAmount))
  -- THE POUND SIGN IS IN THE CARTRIDGE'S STRING, which is the reason this
  -- module reads a format string instead of formatting a number itself.
  -- `Gen4TrainerCard` keeps a MONEY_SIGN local because it builds its own
  -- line; a second hand-spelled sign here would be the drift this port keeps
  -- finding.
  if type(rawAmount) == "string" then
    ok(rawAmount:find("$", 1, true) ~= nil,
       "bank %d entry %d has no money sign in it (%q), so reading the "
       .. "cartridge's format string no longer brings one along and this "
       .. "module needs its own", MW.BANK, MW.AMOUNT_ENTRY, rawAmount)
    ok(rawAmount:find("{STRVAR_1", 1, true) ~= nil,
       "entry %d has no string-variable token, so the balance has nowhere to "
       .. "go", MW.AMOUNT_ENTRY)
  end
  ok(code(slurp("src/ui/Gen4MoneyWindow.lua")):find('MONEY_SIGN') == nil,
     "Gen4MoneyWindow has a money-sign constant of its own; the cartridge's "
     .. "format string carries the sign and a second spelling will drift")

  -- AND THE SIGN HAS ONE OWNER ACROSS THE WHOLE TREE, as an invariant.
  --
  -- `GameVersion.moneySign` holds the three cartridge families' signs and six
  -- screens read it. `Gen4TrainerCard` kept a `MONEY_SIGN = "$"` local with a
  -- paragraph that ended "ShopMenu has the same line and will have the same
  -- fault in a Gen 4 shop; that is its own fix" -- and that fix had landed, so
  -- the local was the last hand-spelling of something with an owner and the
  -- forward reference was stale. Both are gone.
  --
  -- The subject derives itself: any file that writes a bare "$" or U+00A5 or
  -- U+20BD next to a balance is found the day it is written. ShopMenu is the
  -- argued exception -- it holds the two Game Boy glyphs it HANDS to
  -- `moneySign` as the fallback, which is the opposite of bypassing it.
  do
    local ARGUED = { ["src/ui/ShopMenu.lua"] = true }
    local offenders = {}
    local function sweep(dir)
      local ph = io.popen('ls "' .. dir .. '" 2>/dev/null')
      if not ph then return end
      local names = {}
      for name in ph:lines() do names[#names + 1] = name end
      ph:close()
      for _, name in ipairs(names) do
        local path = dir .. "/" .. name
        if name:match("%.lua$") then
          local rel = path:gsub("^%./", "")
          if not ARGUED[rel] and rel ~= "src/core/GameVersion.lua" then
            local body = code(slurp(path))
            if body:find('MONEY_SIGN%s*=') or body:find('MONEY_GLYPH%s*=') then
              offenders[#offenders + 1] = rel
            end
          end
        elseif not name:find("%.") then
          sweep(path)
        end
      end
    end
    sweep("src")
    ok(#offenders == 0,
       "%d file(s) keep a money sign of their own instead of asking "
       .. "GameVersion.moneySign: %s", #offenders,
       table.concat(offenders, ", "))
    -- ...and the floor: the owner has to still answer, or the sweep above is
    -- finding nothing because there is nothing to find.
    ok(GameVersion.moneySign() == "$",
       "GameVersion.moneySign answers %q for a Gen 4 game, not the ASCII "
       .. "dollar the DS font draws as the Poke-dollar",
       tostring(GameVersion.moneySign()))
    local readers = 0
    local function count(dir)
      local ph = io.popen('ls "' .. dir .. '" 2>/dev/null')
      if not ph then return end
      local names = {}
      for name in ph:lines() do names[#names + 1] = name end
      ph:close()
      for _, name in ipairs(names) do
        local path = dir .. "/" .. name
        if name:match("%.lua$") then
          local body = code(slurp(path))
          if body:find("moneySign%s*%(") then readers = readers + 1 end
        elseif not name:find("%.") then
          count(path)
        end
      end
    end
    count("src")
    ok(readers >= 6,
       "only %d file(s) ask GameVersion.moneySign; it had six readers when "
       .. "this was written and a drop means somebody went back to a local",
       readers)
    report("%d file(s) read GameVersion.moneySign, none keeps its own",
           readers)
  end

  local game = { data = { text = text }, save = { money = 12345 } }
  local panel = MW.panelFor(game, 20, 2)
  ok(type(panel) == "table", "panelFor answered %s", tostring(panel))
  if panel then
    ok(panel.left == 20 and panel.top == 2,
       "panelFor put the window at %s,%s rather than at the 20,2 it was given",
       tostring(panel.left), tostring(panel.top))
    ok(panel.label == rawLabel,
       "the label is %q rather than the bank's %q", tostring(panel.label),
       tostring(rawLabel))
    ok(type(panel.amount) == "string"
       and panel.amount:find("12345", 1, true) ~= nil,
       "the amount %q does not contain the balance", tostring(panel.amount))
    ok(panel.amount:find("{") == nil,
       "the amount %q still carries markup, so the balance was never spliced "
       .. "in", tostring(panel.amount))
  end
  -- SIX DIGITS, SPACE PADDED, and the padding only shows as alignment.
  for _, case in ipairs({ { 0, 5 }, { 7, 5 }, { 12345, 1 }, { 999999, 0 } }) do
    game.save.money = case[1]
    local q = MW.panelFor(game, 20, 2)
    local spaces = select(2, tostring(q.amount):gsub(" ", ""))
    ok(spaces == case[2],
       "a balance of %d padded to %d space(s), expected %d -- the cartridge "
       .. "pads to six digits with spaces", case[1], spaces, case[2])
    ok(tostring(q.amount):find("0" .. tostring(case[1]), 1, true) == nil
       or case[1] == 0,
       "a balance of %d looks zero-padded (%q)", case[1], tostring(q.amount))
  end
  -- ...and a balance that will not fit is NOT truncated, which is the
  -- cartridge's behaviour too: SetNumber's digit count is a minimum.
  game.save.money = 1234567
  ok(MW.panelFor(game, 20, 2).amount:find("1234567", 1, true) ~= nil,
     "a seven-digit balance was truncated to fit the six-digit pad")
  -- a negative balance cannot happen but must not print a sign either
  game.save.money = -5
  ok(MW.panelFor(game, 20, 2).amount:find("-", 1, true) == nil,
     "a negative balance printed a minus sign")
end

-- ---------------------------------------------------------------------------
section("4. the draw, in tile coordinates")
-- ---------------------------------------------------------------------------
if not text then
  skip("no text.lua, so the draw geometry is unverified")
else
  local Font = require("src.render.Font")
  local realBox, realDraw, realWidth = Font.drawBox, Font.draw, Font.width
  local calls = {}
  Font.drawBox = function(a, b, c, d) calls[#calls + 1] = { "box", a, b, c, d } end
  Font.draw = function(t, x, y) calls[#calls + 1] = { "text", t, x, y } end
  Font.width = function(t) return #tostring(t) * 6 end

  local game = { data = { text = text }, save = { money = 12345 } }
  local panel = MW.panelFor(game, 20, 2)
  MW.draw(panel)
  Font.drawBox, Font.draw, Font.width = realBox, realDraw, realWidth

  local box, label, amount
  for _, c in ipairs(calls) do
    if c[1] == "box" then box = c
    elseif c[1] == "text" and not label then label = c
    elseif c[1] == "text" then amount = c end
  end
  -- THE FRAME IS ONE TILE OUT AND TWO TILES BIGGER, which is the convention
  -- `drawGen4SaveInfo` and FireRed's lift window already use.
  ok(box and box[2] == 19 and box[3] == 1,
     "the frame starts at tile %s,%s; a window at 20,2 draws its frame at "
     .. "19,1", tostring(box and box[2]), tostring(box and box[3]))
  ok(box and box[4] == MW.WIDTH_TILES + 2 and box[5] == MW.HEIGHT_TILES + 2,
     "the frame is %sx%s tiles; a %dx%d window needs %dx%d",
     tostring(box and box[4]), tostring(box and box[5]),
     MW.WIDTH_TILES, MW.HEIGHT_TILES, MW.WIDTH_TILES + 2, MW.HEIGHT_TILES + 2)
  ok(label and label[3] == 160 and label[4] == 16,
     "the label is drawn at %s,%s; the window's own origin at tile 20,2 is "
     .. "160,16", tostring(label and label[3]), tostring(label and label[4]))
  -- RIGHT-ALIGNED, which is the whole reason the number is padded.
  ok(amount ~= nil, "the amount was not drawn")
  if amount then
    local right = (20 + MW.WIDTH_TILES) * 8
    ok(amount[3] + #tostring(amount[2]) * 6 == right,
       "the amount ends at %s rather than at the window's right edge (%d), so "
       .. "it is not right-aligned",
       tostring(amount[3] + #tostring(amount[2]) * 6), right)
    ok(amount[4] == 16 + MW.ROW_PITCH,
       "the amount is drawn at y %s; the label is at 16 and the pitch is %d",
       tostring(amount[4]), MW.ROW_PITCH)
  end
  -- AND THE FIELD DRAWS IT. A panel nothing draws is the fault being fixed.
  local owc = code(slurp("src/world/OverworldController.lua"))
  ok(owc:find("gen4MoneyWindow") ~= nil,
     "OverworldController never mentions gen4MoneyWindow, so the panel is "
     .. "built and never drawn")
  ok(owc:find("Gen4MoneyWindow") ~= nil,
     "OverworldController never requires Gen4MoneyWindow")
end

-- ---------------------------------------------------------------------------
section("5. the three commands, and where the state lives")
-- ---------------------------------------------------------------------------
do
  local src = code(slurp("src/script/Gen4ScriptVM.lua"))
  for _, name in ipairs({ "showmoney", "hidemoney", "updatemoneydisplay" }) do
    local body = src:match("L%." .. name .. "%s*=%s*function.-\nend")
    ok(body ~= nil, "`%s` has no lowering", name)
    if body then
      ok(body:find("g4_money_window") ~= nil,
         "`%s` does not lower onto g4_money_window", name)
      ok(body:find("g4_noop") == nil, "`%s` still lowers onto a no-op", name)
    end
  end
  local arms = {}
  for arm in src:gmatch('"g4_money_window",%s*"([a-z]+)"') do
    arms[arm] = (arms[arm] or 0) + 1
  end
  for _, arm in ipairs({ "show", "hide", "update" }) do
    ok(arms[arm] == 1,
       "the %q arm of g4_money_window is emitted %s time(s), expected once",
       arm, tostring(arms[arm]))
  end
end

if not text then
  skip("no text.lua, so the handler's behaviour is unverified")
else
  local ow = { }
  local ctx = { save = { money = 500 }, overworld = ow }
  ctx.game = { save = ctx.save, data = { text = text } }
  Commands.g4_money_window(ctx, "show", 20, 2)
  ok(type(ow.gen4MoneyWindow) == "table",
     "showmoney did not put a panel on the overworld")
  ok(ctx.save.gen4MoneyWindow == nil,
     "the money window went into the save, where it would come back on a map "
     .. "that never opened it -- SCRIPT_MANAGER_MONEY_WINDOW is a "
     .. "field-system slot")
  local first = ow.gen4MoneyWindow and ow.gen4MoneyWindow.amount

  -- THE BEAT THE GAME CORNER DEPENDS ON: taking money does NOT change the
  -- window until `updatemoneydisplay` runs. A window that read the balance at
  -- draw time would be "more correct" and wrong -- the cartridge puts the
  -- refresh after the transaction on purpose.
  ctx.save.money = 100
  ok(ow.gen4MoneyWindow.amount == first,
     "the window changed when the balance did, before updatemoneydisplay ran")
  Commands.g4_money_window(ctx, "update")
  ok(ow.gen4MoneyWindow.amount ~= first,
     "updatemoneydisplay did not rebuild the amount (%q both times)",
     tostring(first))
  ok(ow.gen4MoneyWindow.amount:find("100", 1, true) ~= nil,
     "the refreshed amount %q does not show the new balance",
     tostring(ow.gen4MoneyWindow.amount))
  ok(ow.gen4MoneyWindow.left == 20 and ow.gen4MoneyWindow.top == 2,
     "the refresh moved the window to %s,%s",
     tostring(ow.gen4MoneyWindow.left), tostring(ow.gen4MoneyWindow.top))

  Commands.g4_money_window(ctx, "hide")
  ok(ow.gen4MoneyWindow == nil, "hidemoney left the window up")
  -- a refresh with no window is not an error on the cartridge either
  local okCall = pcall(Commands.g4_money_window, ctx, "update")
  ok(okCall, "updatemoneydisplay raised with no window open")
  ok(ow.gen4MoneyWindow == nil,
     "updatemoneydisplay opened a window that no showmoney asked for")
  -- ...and the operands are var-or-literal, which is what the cartridge reads
  ctx.save.vars = ctx.save.vars or {}
  Gen4Commands.setVar(ctx.save, 0x4000, 18)
  Commands.g4_money_window(ctx, "show", 0x4000, 2)
  ok(ow.gen4MoneyWindow and ow.gen4MoneyWindow.left == 18,
     "a var operand resolved to %s rather than the 18 it holds; "
     .. "ScrCmd_ShowMoney reads both with ScriptContext_GetVar",
     tostring(ow.gen4MoneyWindow and ow.gen4MoneyWindow.left))
end

-- ---------------------------------------------------------------------------
section("6. the cartridge's own call sites, decoded")
-- ---------------------------------------------------------------------------
if not ROM then
  skip("no ROM, so the decoded call sites are not counted")
else
  local okR, NdsRom = pcall(require, "src.import.NdsRom")
  local okN, Narc = pcall(require, "src.import.NarcArchive")
  local okS, Script = pcall(require, "src.import.Gen4Script")
  if not (okR and okN and okS) then
    skip("the ROM readers are not available in this harness")
  else
    local rom = NdsRom.open(ROM)
    if not rom then
      skip("could not open %s", tostring(ROM))
    else
      local arc = Narc.parse(rom:read("/fielddata/script/scr_seq.narc"))
      local counts, shows = {}, {}
      for m = 0, (arc and arc.count or 0) - 1 do
        local bytes = arc:get(m)
        if bytes and #bytes >= 6 then
          local queue, seen = {}, {}
          for _, at in ipairs(Script.entries(bytes)) do
            if not seen[at] then seen[at] = true; queue[#queue + 1] = at end
          end
          local i = 1
          while i <= #queue do
            local at = queue[i]; i = i + 1
            local ins = Script.decode(bytes, at)
            for _, op in ipairs(ins) do
              local n = op.name
              if n == "showmoney" or n == "hidemoney"
                 or n == "updatemoneydisplay" then
                counts[n] = (counts[n] or 0) + 1
                if n == "showmoney" then
                  shows[#shows + 1] = { op.args[1], op.args[2] }
                end
              end
              local t = op.target
              if t and t >= 1 and t <= #bytes and not seen[t] then
                seen[t] = true; queue[#queue + 1] = t
              end
            end
          end
        end
      end
      rom:close()
      local total = (counts.showmoney or 0) + (counts.hidemoney or 0)
                    + (counts.updatemoneydisplay or 0)
      ok(total >= 100,
         "%d money-window invocation(s) in the decoded corpus; the census "
         .. "that chose this pass measured 109", total)
      report("showmoney x%d, hidemoney x%d, updatemoneydisplay x%d (%d total)",
             counts.showmoney or 0, counts.hidemoney or 0,
             counts.updatemoneydisplay or 0, total)
      -- EVERY DECODED SITE FITS ON THE SCREEN with the operand order this
      -- port uses. Reading them the other way round puts the window off the
      -- bottom, so this is the order asserted against the whole cartridge
      -- rather than against the eight literal call sites in section 2.
      local offRight, offBottom, literal = 0, 0, 0
      for _, s in ipairs(shows) do
        local l, t = s[1], s[2]
        if l and t and l < 0x4000 and t < 0x4000 then
          literal = literal + 1
          if l + MW.WIDTH_TILES > 32 then offRight = offRight + 1 end
          if t + MW.HEIGHT_TILES > 24 then offBottom = offBottom + 1 end
        end
      end
      ok(literal >= 10,
         "only %d showmoney site(s) pass literal coordinates, too few to "
         .. "check the order against", literal)
      ok(offRight == 0,
         "%d of %d site(s) would put the window off the right of a 32-tile "
         .. "screen", offRight, literal)
      ok(offBottom == 0,
         "%d of %d site(s) would put the window off the bottom of a 24-tile "
         .. "screen -- which is what reading the operands the other way round "
         .. "produces", offBottom, literal)
      report("%d showmoney sites with literal coordinates, all on screen",
             literal)
    end
  end
end

io.write(("\n%d checks, %d failed, %d reported, %d skipped\n")
           :format(checks, fails, reports, skips))
os.exit(fails == 0 and 0 or 1)
