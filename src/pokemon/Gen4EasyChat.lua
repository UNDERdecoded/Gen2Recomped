-- PLATINUM'S EASY CHAT WORDS (pokeplatinum src/easy_chat_words.c).
--
-- A word is one u16: the cumulative entry count of the banks before its own
-- plus its entry in that bank (EasyChatWord_FromBankAndEntry). The eleven banks,
-- in sTextBanks order, with this port's bank numbers (text_banks.txt line - 1):
--
--   species 412, moves (uppercase) 648, types 624, abilities (uppercase) 611,
--   trainer 439, people 440, greetings 441, lifestyle 442, feelings 443,
--   tough words 444, union 445
--
-- Entry counts are read off the cache's own text, so they are the ROM's.
-- 0xFFFF is WORD_NONE.
--
-- THE PICKER is the easy-chat screen's GROUP mode, built from the field's
-- menus: the group names come from bank 436 (TEXT_BANK_EASY_CHAT_GROUPS) and
-- the words in a group are listed alphabetically. POKéMON lists only species
-- the Pokédex has seen; TOUGH WORDS, which start locked, are left out until the
-- save unlocks some (save.gen4ToughWords). The ROM's two-page splits
-- (POKéMON 2, MOVE 2) are one list each here.

local Gen4EasyChat = {}

Gen4EasyChat.BANKS = { 412, 648, 624, 611, 439, 440, 441, 442, 443, 444, 445 }
Gen4EasyChat.GROUP_BANK = 436
Gen4EasyChat.WORD_NONE = 0xFFFF

local SPECIES, MOVES, TYPES, ABILITIES = 1, 2, 3, 4
local TOUGH = 10

local countsCache = setmetatable({}, { __mode = "k" })

function Gen4EasyChat.counts(data)
  local text = data and data.text
  if not text then return {} end
  local c = countsCache[text]
  if c then return c end
  local T = require("src.import.Gen4Text")
  c = {}
  for i, bank in ipairs(Gen4EasyChat.BANKS) do
    local n = 0
    while text[T.label(bank, n)] ~= nil do n = n + 1 end
    c[i] = n
  end
  countsCache[text] = c
  return c
end

-- EasyChatWord_FromBankAndEntry (bank is the 1-based index into BANKS)
function Gen4EasyChat.word(data, bankIndex, entry)
  local c = Gen4EasyChat.counts(data)
  local total = 0
  for j = 1, bankIndex - 1 do total = total + (c[j] or 0) end
  return total + entry
end

-- EasyChatWord_GetLoaderIndexAndEntry
function Gen4EasyChat.split(data, word)
  word = tonumber(word)
  if not word or word == Gen4EasyChat.WORD_NONE then return nil end
  local c = Gen4EasyChat.counts(data)
  for i = 1, #Gen4EasyChat.BANKS do
    local n = c[i] or 0
    if word < n then return i, word end
    word = word - n
  end
  return nil
end

-- EasyChatWord_ToString
function Gen4EasyChat.toString(data, word)
  local i, entry = Gen4EasyChat.split(data, word)
  if not i then return "" end
  local T = require("src.import.Gen4Text")
  return (data.text[T.label(Gen4EasyChat.BANKS[i], entry)] or ""):gsub("\n", " ")
end

local function wordsOf(data, bankIndex, keep)
  local T = require("src.import.Gen4Text")
  local out = {}
  local n = Gen4EasyChat.counts(data)[bankIndex] or 0
  -- entry 0 of the species, move and ability banks is the "-----" placeholder
  local first = (bankIndex == SPECIES or bankIndex == MOVES or bankIndex == ABILITIES) and 1 or 0
  for e = first, n - 1 do
    local s = data.text[T.label(Gen4EasyChat.BANKS[bankIndex], e)]
    if type(s) == "string" and s ~= "" and (not keep or keep(e)) then
      out[#out + 1] = { label = s:gsub("\n", " "), word = Gen4EasyChat.word(data, bankIndex, e) }
    end
  end
  return out
end

-- The groups the picker offers, each a list of { label, word }.
function Gen4EasyChat.groups(data, save)
  local T = require("src.import.Gen4Text")
  local function name(i, fallback)
    local s = data.text and data.text[T.label(Gen4EasyChat.GROUP_BANK, i)]
    return type(s) == "string" and s or fallback
  end
  local seen = {}
  for k, v in pairs((save and save.pokedex and save.pokedex.seen) or {}) do
    if v == true or (type(v) == "number" and v > 0) then
      seen[tonumber(k) or tonumber(tostring(k):match("(%d+)$")) or -1] = true
    end
  end
  local toughUnlocked = (save and save.gen4ToughWords) or {}
  local groups = {
    { label = name(0, "POKéMON"), words = wordsOf(data, SPECIES, function(e) return seen[e] end) },
    { label = name(2, "MOVE"), words = wordsOf(data, MOVES) },
    { label = name(4, "STATUS"), words = (function()
        local w = wordsOf(data, TYPES)
        for _, x in ipairs(wordsOf(data, ABILITIES)) do w[#w + 1] = x end
        return w
      end)() },
    { label = name(5, "TRAINER"), words = wordsOf(data, 5) },
    { label = name(6, "PEOPLE"), words = wordsOf(data, 6) },
    { label = name(7, "GREETINGS"), words = wordsOf(data, 7) },
    { label = name(8, "LIFESTYLE"), words = wordsOf(data, 8) },
    { label = name(9, "FEELINGS"), words = wordsOf(data, 9) },
    { label = name(10, "TOUGH WORDS"), words = wordsOf(data, TOUGH, function(e) return toughUnlocked[e] end) },
    { label = name(11, "UNION"), words = wordsOf(data, 11) },
  }
  local out = {}
  for _, g in ipairs(groups) do
    if #g.words > 0 then
      table.sort(g.words, function(a, b) return a.label:upper() < b.label:upper() end)
      out[#out + 1] = g
    end
  end
  return out
end

-- Open the picker: groups, then words. `done(word)` gets the word, or nil
-- when the player backs all the way out.
function Gen4EasyChat.pick(game, done)
  local Menu = require("src.ui.Menu")
  local groups = Gen4EasyChat.groups(game.data, game.save)
  local openGroups
  local function openWords(g)
    local rows = {}
    for i, w in ipairs(g.words) do
      rows[i] = { label = w.label, onSelect = function() done(w.word) end }
    end
    game.stack:push(Menu.new(game, rows, {
      cancelable = true, maxVisible = math.min(#rows, 8),
      onCancel = function() openGroups() end,
    }))
  end
  openGroups = function()
    local rows = {}
    for i, g in ipairs(groups) do
      rows[i] = { label = g.label, onSelect = function() openWords(g) end }
    end
    game.stack:push(Menu.new(game, rows, {
      cancelable = true, maxVisible = math.min(#rows, 8),
      onCancel = function() done(nil) end,
    }))
  end
  openGroups()
end

return Gen4EasyChat
