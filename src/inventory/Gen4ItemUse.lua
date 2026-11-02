-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S BAG "USE", BY THE CARTRIDGE'S OWN DISPATCH.
--
-- Reported from play: "Rowan forbids using various items".  An audit of every
-- item with a field function, used from the bag out of battle, found 78 that
-- answered Rowan's "There's a time and place for everything" -- because a
-- Platinum item is a NUMBER and the engine's item branches are NAMES.  The
-- cartridge reads the record's `fieldUseFunc`, an index into sItemUseFuncs
-- (pokeplatinum src/item_use_functions.c), and so does this:
--
--    4  BICYCLE       the bike
--    8  BERRY         plant it in the empty soft soil ahead (BERRY_TREE_
--                     INTERACTIONS 1), else use it on a Pokemon like medicine
--   13  MULCH         the empty soil ahead (BERRY_TREE_INTERACTIONS 3)
--   12  SPRAYDUCK     a planted patch ahead (BERRY_TREE_INTERACTIONS 2)
--   14  HONEY         the Sweet Scent lure (ov5_021F0488 is Sweet Scent's task)
--   15  VS_SEEKER     VS_SEEKER 0, anywhere on the overworld matrix
--   19  BAG_MESSAGE   Repels, the Flutes, and the cases' counts (bank 7)
--   21  ESCAPE_ROPE
--   24  GRACIDEA      a Pokemon: Shaymin's Land Forme becomes Sky Forme
--
-- Rowan's line is still the answer where the cartridge gives it
-- (ITEM_USE_CANNOT_USE_GENERIC): Mulch or the Sprayduck with no patch ahead,
-- the Azure Flute anywhere but its one event.

local Strings = require("src.core.Strings")

local G = {}

G.BAND_BERRY, G.BAND_VS_SEEKER = "berry_tree_interactions", "vs_seeker"
G.SHAYMIN = 492

-- the number behind 79 or "ITEM_079"
function G.numeric(id)
  if type(id) == "number" then return id end
  local n = type(id) == "string" and id:match("^ITEM_(%d+)$")
  return n and tonumber(n) or nil
end

local function isPlatinum(data)
  local v = data and data.gen4_version
  return data and data.isGen4Cache and not (v and v.family == "hgss")
end

local function game() return package.loaded["src.core.Game"] end

-- the berry patch the player faces, and its state (BERRY_PATCH_FLAG_*)
function G.facingPatch()
  local Game = game()
  local ow = Game and Game.overworld
  local p = ow and ow.player
  if not (p and ow.npcAtCell) then return nil end
  local fx, fy = p:facingCell()
  local npc = ow:npcAtCell(fx, fy)
  local def = npc and (npc.def or npc)
  if not (def and def.berryPatch) then return nil end
  local patch = require("src.world.Gen4BerryPatches").get(Game, def.berryPatch)
  return patch, npc
end

local function bagLine(data, index, fallback, ...)
  local Game = game()
  local T = require("src.import.Gen4Text")
  if Game and select("#", ...) > 0 then pcall(T.buffer, Game, ...) end
  -- HGSS's bag bank is 10, renumbered (src/ui/Gen4PartyText.lua)
  local bank, n = require("src.ui.Gen4PartyText").bagIndex(data, index)
  return (Game and bank and T.resolve(data, bank, n, Game)) or fallback
end

-- ITEM_USE_CANNOT_USE_GENERIC's words: BagContext_FormatErrorMessage's
-- `default` arm prints CommonStrings_Text_CantDoThatRightNow (TEXT_BANK_
-- COMMON_STRINGS, generated/text_banks.txt line 214, so bank 213, entry 36)
-- with the player's name in STRVAR 0 -- "Rowan's words echoed... <name>!
-- There's a time and place for everything! But not now."
G.BANK_COMMON_STRINGS, G.CANT_DO_THAT_RIGHT_NOW = 213, 36
-- HGSS: ITEMUSEERROR_OAKSWORDS, msg_0040 entry 37 ("Oak's words echoed...")
G.HGSS_BANK_COMMON, G.HGSS_OAKS_WORDS = 40, 37
function G.rowanLine(data, save)
  local name = save and save.player and save.player.name or ""
  local Game = game()
  local T = require("src.import.Gen4Text")
  if Game then pcall(T.buffer, Game, name) end
  -- BLACK / WHITE: Juniper's words (bag bank 3 line 56). Their bank 213 is
  -- story text -- line 36 is Alder's Dragonspiral speech, which is what every
  -- refused item printed in Unova.
  if require("src.core.GameVersion").isGen5() then
    return require("src.inventory.Gen5ItemUse").juniper(data, save)
  end
  local v = data and data.gen4_version
  if v and v.family == "hgss" then
    local oak = Game and T.resolve(data, G.HGSS_BANK_COMMON, G.HGSS_OAKS_WORDS, Game)
    return oak or Strings("Oak's words echoed...\n%s! There's a time and\nplace for everything! But not now.", name)
  end
  local line = Game and T.resolve(data, G.BANK_COMMON_STRINGS, G.CANT_DO_THAT_RIGHT_NOW, Game)
  return line or Strings("Rowan's words echoed...\n%s! There's a time and\nplace for everything! But not now.", name)
end

local function rowan(save)
  local Game = game()
  return "failed", { G.rowanLine(Game and Game.data, save) }
end

-- The engine's refusal is Gen 2's ("OAK: ...This isn't the time to use
-- that!"), written at a dozen sites; on Platinum it is Rowan's line.
function G.translateRefusal(data, save, msgs)
  if not (data and data.isGen4Cache and type(msgs) == "table" and type(msgs[1]) == "string") then return msgs end
  if msgs[1]:find("time to use that", 1, true) then
    local out = { G.rowanLine(data, save) }
    for i = 2, #msgs do out[i] = msgs[i] end
    return out
  end
  return msgs
end

-- Does USE open the party picker first?  Berries away from soil (as medicine)
-- and the Gracidea.
function G.needsTarget(id, itemDef, data)
  if not (isPlatinum(data) and itemDef and G.numeric(id)) then return nil end
  local f = tonumber(itemDef.fieldUseFunc)
  if f == 24 then return true end
  if f == 8 then
    local patch = G.facingPatch()
    if patch and (patch.stage or 0) == 0 then return false end
    return true
  end
  return nil
end

-- (kind, messages, extra), or nil to let ItemEffects carry on
-- HEARTGOLD / SOULSILVER's own field-use rows (pokeheartgold
-- src/field_use_item.c sItemFieldUseFuncs): Honey 14, the Apricorn Box 23,
-- the Dowsing MCHN 26.
function G.useHgss(data, save, id, itemDef, target, battle)
  local n = G.numeric(id)
  if not (n and itemDef) or battle then return nil end
  local f = tonumber(itemDef.fieldUseFunc) or 0
  if f == 14 then return "honey", nil, { item = n } end
  if f == 23 then return "hgss_apricorn_box", nil, { item = n } end
  -- the UNOWN Report (ItemMenuUseFunc_UnownReport -> overlay 113)
  if f == 25 then return "hgss_unown_report", nil, { item = n } end
  if f == 26 then return "hgss_dowsing", nil, { item = n } end
  return nil
end

function G.use(data, save, id, itemDef, target, battle)
  local v = data and data.gen4_version
  if data and data.isGen4Cache and v and v.family == "hgss" then
    return G.useHgss(data, save, id, itemDef, target, battle)
  end
  local n = G.numeric(id)
  if not (n and itemDef and isPlatinum(data)) or battle then return nil end
  local f = tonumber(itemDef.fieldUseFunc) or 0
  local name = itemDef.name or tostring(id)
  if f == 8 then
    local patch, npc = G.facingPatch()
    if patch and (patch.stage or 0) == 0 and not target then
      return "gen4_script", nil, { band = G.BAND_BERRY, entry = 1, item = n, npc = npc }
    end
    -- on a Pokemon: a berry that heals or cures is medicine (ItemEffects);
    -- any other is "It won't have any effect."
    local r = require("src.inventory.ItemEffects").recordFor(id)
    if target and not (r and (r.heal or r.cures or r.cureAll or r.pp or r.confusion)) then
      return "failed", { "It won't have any effect." }
    end
    return nil
  elseif f == 13 then
    local patch, npc = G.facingPatch()
    if patch and (patch.stage or 0) == 0 and (patch.mulch or 0) == 0 then
      return "gen4_script", nil, { band = G.BAND_BERRY, entry = 3, item = n, npc = npc }
    end
    return rowan(save)
  elseif f == 12 then
    local patch, npc = G.facingPatch()
    if patch and (patch.stage or 0) > 0 then
      return "gen4_script", nil, { band = G.BAND_BERRY, entry = 2, item = n, npc = npc }
    end
    return rowan(save)
  elseif f == 7 then
    -- UseMailFromMenu: the mail app, checking a blank letter of this design
    -- (Item_GetMailType: the twelve Mails are items 137..148 in design order)
    local mailType = n - 137
    local Game = game()
    if mailType >= 0 and mailType < 12 and Game and require("src.ui.Gen4MailView").available(Game, mailType) then
      return "gen4_mail", nil, { mailType = mailType }
    end
    return nil
  elseif f == 14 then
    return "honey", nil, { item = n }
  elseif f == 15 then
    -- CanUseVsSeeker: MapHeader_IsOnMainMatrix
    local Game = game()
    local def = Game and Game.overworld and Game.overworld.map and Game.overworld.map.def
    -- the map's matrix is its layout id here; 0 is the overworld's
    if def and tonumber(def.layout) == 0 then
      return "gen4_script", nil, { band = G.BAND_VS_SEEKER, entry = 0, item = n }
    end
    return rowan(save)
  elseif f == 19 then
    -- BagContext_FormatUsageMessage's cases (the Repels and Flutes are
    -- ItemEffects' own, from the name)
    if name == "Point Card" then
      return "failed", { bagLine(data, 97, Strings("Saved Battle Points\n%d BP", save.battlePoints or 0), tostring(save.battlePoints or 0)) }
    elseif name == "Fashion Case" then
      local acc, bd = 0, 0
      for _, c in pairs((save.gen4Accessories or {})) do acc = acc + (tonumber(c) or 0) end
      for _ in pairs((save.gen4Backdrops or {})) do bd = bd + 1 end
      return "failed", { bagLine(data, 93, Strings("Accessories: %d\nBackdrops: %d", acc, bd), tostring(acc), tostring(bd)) }
    elseif name == "Coin Case" then
      return "failed", { bagLine(data, 57, ("Your Coins: %d"):format(save.coins or 0), tostring(save.coins or 0)) }
    end
    return nil
  elseif f == 24 then
    -- the party menu's Gracidea: Shaymin's Land Forme to Sky Forme
    if target and tonumber(target.species) == G.SHAYMIN and (tonumber(target.form) or 0) == 0 then
      local hour = tonumber(os.date("%H")) or 12
      local frozen = target.status == "FRZ" or target.status == "freeze"
      if hour >= 4 and hour < 20 and not frozen then
        target.form = 1
        return "kept", { ("%s changed Forme!"):format(target.nickname or "Shaymin") }
      end
    end
    return "failed", { "It won't have any effect." }
  end
  return nil
end

return G
