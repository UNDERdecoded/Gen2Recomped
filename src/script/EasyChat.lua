-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- EASY CHAT: how everybody in Hoenn who is not reading a script says
-- something of their own.
--
-- Nobody in this game types a sentence.  A phrase is two to six WORD IDS
-- picked out of twenty-two groups, and one screen -- gSpecials[98], called
-- from nineteen places across the region -- is how every one of them is
-- chosen: the four Mauville old men, the QUIZ LADY's question, DEWFORD's
-- trend, the interviews, a secret base's greeting, and every piece of mail.
--
-- A WORD IS ONE NUMBER: `group * 512 + index`, and that only works because
-- no group reaches five hundred and twelve words -- the largest holds two
-- hundred and two.  extractEasyChat asserts that headroom rather than the
-- encoding, because the headroom is the thing that could stop being true.
--
-- FIVE OF THE GROUPS DO NOT CARRY THEIR OWN TEXT.  Two hold species numbers
-- and two hold move numbers, into tables this import already read; asking
-- them for `.text` gets nothing, which is why every lookup goes through here
-- rather than indexing the words directly.

local EasyChat = {}

function EasyChat.record(data)
  local c = data and data.constants
  local r = c and c.gen3EasyChat
  if type(r) ~= "table" or type(r.groups) ~= "table" then return nil end
  return r
end

function EasyChat.shift(data)
  local r = EasyChat.record(data)
  return (r and tonumber(r.shift)) or 512
end

-- The group and index a word id names, or nil when it names neither.
function EasyChat.split(data, word)
  local r = EasyChat.record(data)
  word = math.floor(tonumber(word) or -1)
  if not r or word < 0 then return nil end
  local shift = EasyChat.shift(data)
  local g, i = math.floor(word / shift), word % shift
  local group = r.groups[g + 1]
  if not group or i >= (tonumber(group.count) or 0) then return nil end
  return g, i, group
end

function EasyChat.id(data, groupIndex, wordIndex)
  return groupIndex * EasyChat.shift(data) + wordIndex
end

-- ONE WORD, whatever kind of group it came out of.
function EasyChat.text(data, word)
  local g, i, group = EasyChat.split(data, word)
  if not group then return nil end
  local entry = group.words[i + 1]
  if group.kind == "text" then
    return type(entry) == "table" and entry.text or nil
  end
  if group.kind == "species" then
    local order = (data.constants or {}).speciesOrder
    local id = order and order[entry]
    local def = id and (data.pokemon or {})[id]
    return (def and def.name) or id or nil
  end
  if group.kind == "move" then
    local order = (data.constants or {}).moveOrder
    local id = order and order[entry]
    local def = id and (data.moves or {})[id]
    return (def and def.name) or id or nil
  end
  return nil
end

-- A PHRASE, laid out the way the screen that wrote it lays it out: `perLine`
-- words to a line, separated by a space, and a newline at the end of each.
-- The BARD's song is six words two to a line, which is three lines -- the
-- shape gSpecials[98] hands the picker for him.
function EasyChat.phrase(data, words, perLine)
  if type(words) ~= "table" then return "" end
  perLine = math.max(1, math.floor(tonumber(perLine) or 2))
  local out = {}
  for i, word in ipairs(words) do
    local text = EasyChat.text(data, word)
    if text and text ~= "" then
      out[#out + 1] = text
      -- ...and the separator goes AFTER the word rather than before it, so a
      -- phrase that is one word short does not open on a blank line
      if i < #words then
        out[#out + 1] = (i % perLine == 0) and "\n" or " "
      end
    end
  end
  return (table.concat(out):gsub("%s+$", ""))
end

-- ONE GROUP DOES NOT START OPEN.  The thirty-three TRENDY SAYINGS are locked
-- on a new file and the MAUVILLE HIPSTER teaches them one at a time, tracked
-- by a bitfield in the save -- so which of them the picker may offer is a
-- question about the SAVE, not about the cartridge.  Every other group is the
-- same on the first morning as on the last.
function EasyChat.trendyGroup(data)
  local man = (data and data.constants or {}).gen3MauvilleMan
  local hipster = man and man.hipster
  return hipster and tonumber(hipster.group) or nil
end

function EasyChat.knowsPhrase(save, index)
  local known = save and save.gen3TrendyPhrases
  return type(known) == "table" and known[index] == true
end

function EasyChat.learnPhrase(save, index)
  if not save then return end
  save.gen3TrendyPhrases = save.gen3TrendyPhrases or {}
  save.gen3TrendyPhrases[index] = true
end

function EasyChat.phrasesKnown(data, save)
  local man = (data and data.constants or {}).gen3MauvilleMan
  local hipster = man and man.hipster
  local total = hipster and tonumber(hipster.count) or 0
  local n = 0
  for i = 0, total - 1 do
    if EasyChat.knowsPhrase(save, i) then n = n + 1 end
  end
  return n, total
end

-- Every word a group offers, as { id, text } rows, skipping the ones the
-- cartridge has switched off.  `enabled` on a text word is the cartridge's
-- own flag; the id groups have no per-word flag and the group's own count of
-- enabled words is where the line falls.  `save` is optional and only the
-- trendy sayings care about it.
function EasyChat.words(data, groupIndex, save)
  local r = EasyChat.record(data)
  local group = r and r.groups[groupIndex + 1]
  if not group then return {} end
  local trendy = (groupIndex == EasyChat.trendyGroup(data))
  local out = {}
  for i = 1, (tonumber(group.count) or 0) do
    local entry = group.words[i]
    local on = true
    if group.kind == "text" then
      on = type(entry) == "table" and entry.enabled == true
    else
      on = i <= (tonumber(group.enabled) or 0)
    end
    -- ...and a trendy saying is only yours once he has said it to you
    if on and trendy then on = EasyChat.knowsPhrase(save, i - 1) end
    if on then
      local id = EasyChat.id(data, groupIndex, i - 1)
      local text = EasyChat.text(data, id)
      if text and text ~= "" then out[#out + 1] = { id = id, text = text } end
    end
  end
  return out
end

function EasyChat.groupNames(data)
  local r = EasyChat.record(data)
  local out = {}
  for i, g in ipairs((r and r.groups) or {}) do out[i] = g.name end
  return out
end

return EasyChat
