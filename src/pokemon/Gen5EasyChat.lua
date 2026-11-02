-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S EASY CHAT WORDS and the word-entry screen script 0x1ED
-- opens (the Relocator's passwords, Z050).
--
-- READ FROM CODE (Black, arm9):
--   * a word is u16: its low 11 bits are the cumulative index over thirteen
--     banks (0x020248D8 splits it), the bank sizes at 0x0209F792 {652, 560,
--     17, 165, 44, 38, 48, 103, 47, 32, 26, 10, 61} and their system text
--     banks at 0x0209F7AC {284 species, 286 moves, 287 types, 285 abilities,
--     149, 150, 151, 152, 153, 154, 155, 148, 156}; 0xFFFF is none
--   * two words are the same when equal or in one of the thirteen synonym
--     sets of 0x0209F7C8 (0x020249B0)
--   * 0x1ED <mode, word1Var, word2Var, resultVar> (ov10 0x02166D30) opens
--     the screen; modes 0..3 edit the save's sentence mode + 1 (shown, and
--     kept on confirm), mode 4 one word, mode 5 two free words (the
--     passwords); the result is 1 when confirmed
-- The group names are system bank 140 (POKeMON, STATS, MOVE, TRAINER,
-- UNION, GREETINGS, PEOPLE, LIFESTYLE, FEELINGS, ANIMATED, TERM,
-- CONNECTION, VOICE). INFERRED: which bank each group shows is matched by
-- the words themselves (STATS the types and abilities; UNION has no bank of
-- its own here and is left out; TERM 154; CONNECTION 155; ANIMATED 148); the
-- screen is the port's menu picker (groups, then the words alphabetically),
-- not the cartridge's touch layout; a sentence is kept as its two words
-- (save.gen5Sentences), its pattern half not modelled; the sentence is shown
-- as the picker's title.

local M = {}

M.COUNTS = { 652, 560, 17, 165, 44, 38, 48, 103, 47, 32, 26, 10, 61 }
M.BANKS = { 284, 286, 287, 285, 149, 150, 151, 152, 153, 154, 155, 148, 156 }
M.GROUP_BANK = 140
-- group name index -> word bank indices (1-based into BANKS)
M.GROUPS = { { 0, { 1 } }, { 1, { 3, 4 } }, { 2, { 2 } }, { 3, { 5 } }, { 5, { 7 } }, { 6, { 6 } },
  { 7, { 8 } }, { 8, { 9 } }, { 9, { 12 } }, { 10, { 10 } }, { 11, { 11 } }, { 12, { 13 } } }
M.SYNONYMS = { { 1459, 1440 }, { 1474, 1439, 1471, 1475 }, { 1470, 1461 }, { 1796, 1757 }, { 1800, 1752 },
  { 1492, 1522 }, { 1483, 1477 }, { 1225, 746 }, { 1636, 1315 }, { 1669, 1519 }, { 1672, 1336 },
  { 1745, 1778 }, { 1762, 1787 } }
M.NONE = 0xFFFF

local function label(bank, i) return require("src.import.Gen5Text").label("system", bank, i) end

function M.word(bankIndex, entry)
  local total = 0
  for j = 1, bankIndex - 1 do total = total + M.COUNTS[j] end
  return total + entry
end

function M.split(word)
  word = tonumber(word)
  if not word or word == M.NONE then return nil end
  word = word % 0x800
  for i, n in ipairs(M.COUNTS) do
    if word < n then return i, word end
    word = word - n
  end
  return nil
end

function M.toString(data, word)
  local i, e = M.split(word)
  if not i then return "" end
  local s = data and data.text and data.text[label(M.BANKS[i], e)]
  return type(s) == "string" and (s:gsub("\n", " "):gsub("^絵_", "")) or ""
end

-- 0x020249B0
function M.same(a, b)
  a, b = tonumber(a), tonumber(b)
  if a == b then return true end
  for _, set in ipairs(M.SYNONYMS) do
    local ha, hb = false, false
    for _, w in ipairs(set) do
      if w == a then ha = true end
      if w == b then hb = true end
    end
    if ha and hb then return true end
  end
  return false
end

function M.groups(data, save)
  local seen = {}
  for k, v in pairs((save and save.pokedex and save.pokedex.seen) or {}) do
    if v == true or (type(v) == "number" and v > 0) then
      seen[tonumber(k) or tonumber(tostring(k):match("(%d+)$")) or -1] = true
    end
  end
  local out = {}
  for _, g in ipairs(M.GROUPS) do
    -- (banks 140..145 are the same names; a cache may carry only some)
    local name
    for gb = M.GROUP_BANK, M.GROUP_BANK + 5 do
      name = name or (data and data.text and data.text[label(gb, g[1])])
    end
    name = name or "?"
    local words = {}
    for _, bi in ipairs(g[2]) do
      local first = (bi == 1 or bi == 2 or bi == 4) and 1 or 0
      for e = first, M.COUNTS[bi] - 1 do
        local s = data and data.text and data.text[label(M.BANKS[bi], e)]
        if type(s) == "string" and s ~= "" and (bi ~= 1 or seen[e]) then
          words[#words + 1] = { label = (s:gsub("\n", " "):gsub("^絵_", "")), word = M.word(bi, e) }
        end
      end
    end
    if #words > 0 then
      table.sort(words, function(a, b) return a.label:upper() < b.label:upper() end)
      out[#out + 1] = { label = name, words = words }
    end
  end
  return out
end

-- the picker: groups, then words; done(word) or done(nil) when backed out
-- `title` / `onKeep`: the sentence being edited, offered as the first row
-- (choosing it keeps the sentence as it stands)
function M.pick(game, done, title, onKeep)
  local Menu = require("src.ui.Menu")
  local groups = M.groups(game.data, game.save)
  local openGroups
  local function openWords(g)
    local rows = {}
    for i, w in ipairs(g.words) do rows[i] = { label = w.label, onSelect = function() done(w.word) end } end
    game.stack:push(Menu.new(game, rows, { cancelable = true, maxVisible = math.min(#rows, 8),
      onCancel = function() openGroups() end }))
  end
  openGroups = function()
    local rows = {}
    if title and onKeep then rows[1] = { label = title, onSelect = onKeep } end
    for _, g in ipairs(groups) do rows[#rows + 1] = { label = g.label, onSelect = function() openWords(g) end } end
    game.stack:push(Menu.new(game, rows, { cancelable = true, maxVisible = math.min(#rows, 8), title = title,
      onCancel = function() done(nil) end }))
  end
  openGroups()
end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
local function G4() return require("src.script.Gen4Commands") end

-- 0x1ED: the word entry (ov10 0x02166D30, its end 0x02166E50). READ: a
-- cancel writes only result 0; mode 5 hands back both words, mode 4 one (the
-- second var 0); modes 0..3 edit the save's sentence `mode + 1` (four u16 in
-- block 0x3E, 0x0200E6FC / 0x0200E714): it is shown as it stands, written
-- back on confirm, and its two words returned. A test (or a caller) may
-- answer through M.scripted = { { word1, word2 }, ... } (consumed in order)
-- or false (cancel) instead of the screen.
function M.sentence(save, n)
  local s = save and save.gen5Sentences
  return s and (s[n] or s[tostring(n)]) or nil
end

function Commands.g5_word_entry(ctx, mode, w1, w2, dest)
  local save = ctx.save
  local set = function(v, x) if v then G4().setVar(save, v, x) end end
  set(dest, 0)
  local m = math.floor(tonumber(G4().valueOf(ctx, mode)) or 0)
  local two = m ~= 4
  local function finish(a, b)
    if m <= 3 then
      save.gen5Sentences = save.gen5Sentences or {}
      save.gen5Sentences[m + 1] = { a, b }
    end
    set(w1, a); set(w2, two and b or 0); set(dest, 1)
  end
  if M.scripted ~= nil then
    local s = M.scripted
    if type(s) == "table" and type(s[1]) == "table" then s = table.remove(s, 1) end
    if s then finish(s[1] or M.NONE, s[2] or M.NONE) end
    return
  end
  if not (ctx.game and ctx.game.stack) then return end
  local title
  if m <= 3 then
    local cur = M.sentence(save, m + 1)
    if cur then title = M.toString(ctx.game.data, cur[1]) .. " " .. M.toString(ctx.game.data, cur[2]) end
  end
  local runner = ctx.runner
  local keep
  if title then
    local cur = M.sentence(save, m + 1)
    keep = function() finish(cur[1], cur[2]); if runner then runner:resume() end end
  end
  M.pick(ctx.game, function(first)
    if not first then if runner then runner:resume() end return end
    if not two then finish(first, 0); if runner then runner:resume() end return end
    M.pick(ctx.game, function(second)
      if second then finish(first, second) end
      if runner then runner:resume() end
    end)
  end, title, keep)
  if runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g5_word_entry = { foreground = true, blocking = true }

return M
