-- Which two games may link, and how (docs/online-design.md 2.5, WS3).
--
-- The pairs are the cartridges' own:
--
--   R/B/Y  <-> R/B/Y           trade + battle
--   G/S/C  <-> G/S/C           trade + battle
--   R/B/Y  <-> G/S/C           TIME CAPSULE: trade only (src/online/TimeCapsule)
--   R/S/E  <-> R/S/E, FR/LG    trade + battle; FR/LG takes no non-Kanto
--                              POKéMON until it has the National Pokédex
--   D/P/Pt <-> D/P/Pt, HG/SS   trade + battle; HG/SS-only items cannot go
--                              to D/P/Pt, and HG/SS's Spiky-eared PICHU
--                              cannot be traded at all
--   B      <-> W               trade + battle
--   anything else              refused, with the reason
--
-- Battles: "lockstep" when the two battle fingerprints match (both machines
-- run the same simulation, LinkBattle today), "host" when they are one
-- family's two different games (host-authoritative, WS5), false otherwise.
--
-- This module is pure: it reads two hello tables (Handshake.hello) and,
-- for the per-mon gates, packed mons (MonCodec.pack).  The romhacks
-- (Prism, Polished Crystal) are their own family: their data is not the
-- base game's, so they pair only with themselves.

local CompatRules = {}

CompatRules.FAMILY = {
  red = "rby", blue = "rby", green = "rby", yellow = "rby",
  gold = "gsc", silver = "gsc", crystal = "gsc",
  ruby = "rse", sapphire = "rse", emerald = "rse",
  firered = "frlg", leafgreen = "frlg",
  diamond = "dppt", pearl = "dppt", platinum = "dppt",
  heartgold = "hgss", soulsilver = "hgss",
  black = "bw", white = "bw",
  prism = "prism", polishedcrystal = "polishedcrystal",
}

CompatRules.GEN = {
  rby = 1, gsc = 2, prism = 2, polishedcrystal = 2,
  rse = 3, frlg = 3, dppt = 4, hgss = 4, bw = 5,
}

-- family -> family -> link kind
local LINKS = {
  rby = { rby = "same", gsc = "timecapsule" },
  gsc = { gsc = "same", rby = "timecapsule" },
  prism = { prism = "same" },
  polishedcrystal = { polishedcrystal = "same" },
  rse = { rse = "same", frlg = "family" },
  frlg = { frlg = "same", rse = "family" },
  dppt = { dppt = "same", hgss = "family" },
  hgss = { hgss = "same", dppt = "family" },
  bw = { bw = "same" },
}

CompatRules.LINKS = LINKS

-- ONE-WAY UPWARD TRANSFER between two players (the user's decision, 2.13
-- #6 revised): the cartridges' own same-owner moves, played across a link.
-- Gen 3 -> Gen 4 is Pal Park (src/world/Gen4PalPark.lua), Gen 4 -> Gen 5 is
-- Poke Transfer (src/world/Gen5PokeTransfer.lua); the receiver is always the
-- newer game, the mon never comes back, and nothing goes the other way.
-- Gen 1/2 onward (a Gen 7-style Transporter) and any two-step jump
-- (Gen 3 -> Gen 5) are out of scope, as on the cartridges.
local TRANSFER = {
  rse = { dppt = "palpark", hgss = "palpark" },
  frlg = { dppt = "palpark", hgss = "palpark" },
  dppt = { bw = "poketransfer" },
  hgss = { bw = "poketransfer" },
}

CompatRules.TRANSFER = TRANSFER

-- Platinum's last item id: HGSS's 468..536 (apricorns, the Pokéathlon
-- items, the Johto key items ...) do not exist in D/P/Pt
CompatRules.DPPT_MAX_ITEM = 467
CompatRules.KANTO_MAX_DEX = 151

function CompatRules.familyOf(game)
  return CompatRules.FAMILY[tostring(game or ""):lower()]
end

-- ------------------------------------------------------------ hello info

-- the save's National Pokédex flag, read the way WalkerLink reads it
function CompatRules.hasNationalDex(save)
  if type(save) ~= "table" then return false end
  if save.nationalDex == true or save.nationalDex == 1 then return true end
  if type(save.pokedex) == "table" and save.pokedex.national == true then return true end
  local flags = save.flags
  return type(flags) == "table"
    and (flags.FLAG_SYS_NATIONAL_DEX or flags.nationalDex) and true or false
end

-- the v3 fields a hello adds (Handshake.hello merges these in)
function CompatRules.info(game)
  local GV = require("src.core.GameVersion")
  local id = GV.get()
  local family = CompatRules.familyOf(id) or id
  local gen = CompatRules.GEN[family] or GV.generation(id)
  return {
    gen = gen,
    game = id,
    family = family,
    nationalDex = CompatRules.hasNationalDex(game and game.save),
  }
end

-- ------------------------------------------------------------ pairing

local REASON_TEXT = {
  needs_national_dex = "The DS game needs the NATIONAL DEX for PAL PARK.",
  peer_v2 = "Update the other game to trade.",
  no_family = "The other game is not known.",
  cross_generation = "These two games can't link.",
  cross_family = "These two games can't link.",
}

CompatRules.REASON_TEXT = REASON_TEXT

local function refuse(code)
  return { trade = false, battle = false, reason = code,
           reasons = { REASON_TEXT[code] or code } }
end

-- localHello, remoteHello: Handshake.hello tables (the v3 fields: gen, game,
-- family, battleFingerprint).  Returns
--   { trade = bool, battle = "lockstep"|"host"|false, timeCapsule = bool,
--     kind = "same"|"family"|"timecapsule", reason = code, reasons = {...} }
function CompatRules.pair(localHello, remoteHello)
  localHello, remoteHello = localHello or {}, remoteHello or {}
  local mine = localHello.family or CompatRules.familyOf(localHello.game)
  local theirs = remoteHello.family or CompatRules.familyOf(remoteHello.game)
  if not remoteHello.gen and not theirs then
    -- a v2 peer: only the Gen 1/2 v2 path is still open to it
    if (tonumber(localHello.gen) or 1) >= 3 then return refuse("peer_v2") end
    return { trade = true, battle = "lockstep", kind = "legacy", reasons = {} }
  end
  if not mine or not theirs or not LINKS[mine] then return refuse("no_family") end
  local kind = LINKS[mine][theirs]
  local route = (TRANSFER[mine] or {})[theirs] or (TRANSFER[theirs] or {})[mine]
  if not kind and route then
    -- one way, older -> newer: this side sends when it is the older game
    local sending = (TRANSFER[mine] or {})[theirs] ~= nil
    local receiver = sending and remoteHello or localHello
    local out = { trade = false, battle = false, kind = "transfer",
                  transfer = { route = route, direction = sending and "send" or "receive",
                               fromGen = CompatRules.GEN[sending and mine or theirs],
                               toGen = CompatRules.GEN[sending and theirs or mine] },
                  reasons = { route == "palpark" and "PAL PARK: one way to the DS game."
                              or "POKé TRANSFER: one way to BLACK/WHITE." } }
    -- Pal Park opens only once the DS game has the National Pokédex
    -- (Gen4PalPark.blocked)
    if route == "palpark" and not receiver.nationalDex then
      out.transfer = nil
      out.kind = nil
      out.reason = "needs_national_dex"
      out.reasons = { "The DS game needs the NATIONAL DEX for PAL PARK." }
      return out
    end
    return out
  end
  if not kind then
    if (tonumber(localHello.gen) or 0) ~= (tonumber(remoteHello.gen) or -1) then
      return refuse("cross_generation")
    end
    return refuse("cross_family")
  end
  local sameBattle = localHello.battleFingerprint ~= nil
    and localHello.battleFingerprint == remoteHello.battleFingerprint
  local out = { trade = true, kind = kind, reasons = {} }
  if kind == "timecapsule" then
    out.battle = false
    out.timeCapsule = true
    out.reasons[1] = "Time Capsule: trade only."
  elseif sameBattle then
    out.battle = "lockstep"
  elseif kind == "family" or (CompatRules.GEN[mine] or 0) >= 3 then
    out.battle = "host"
  else
    -- Gen 1/2 with different data (mods): no shared simulation
    out.battle = false
  end
  return out
end

-- ------------------------------------------------------------ per mon

-- Can the sender's packed mon (MonCodec.pack) go to this peer?  true, or
-- false and the reason shown beside the greyed slot.  Both sides run it
-- over the SENDER's party with the same two hellos, so they agree on
-- which slots are in play.
function CompatRules.canSend(packed, localHello, remoteHello)
  localHello, remoteHello = localHello or {}, remoteHello or {}
  local mine = localHello.family or CompatRules.familyOf(localHello.game)
  local theirs = remoteHello.family or CompatRules.familyOf(remoteHello.game)
  if type(packed) ~= "table" then return false, "not a POKéMON" end
  -- HG/SS: the Spiky-eared PICHU (species 172 form 1) cannot be traded
  if mine == "hgss" and tonumber(packed.species) == 172 and tonumber(packed.form) == 1 then
    return false, "can't be traded"
  end
  if mine == "gsc" and theirs == "rby" then
    return require("src.online.TimeCapsule").gen2ToGen1Allowed(packed)
  end
  if theirs == "frlg" and not remoteHello.nationalDex then
    local dex = tonumber(packed.dex)
    if not dex or dex > CompatRules.KANTO_MAX_DEX then
      return false, "needs NATIONAL DEX"
    end
  end
  if theirs == "dppt" and mine == "hgss" then
    local item = tonumber(packed.item or packed.heldItem)
    if item and item > CompatRules.DPPT_MAX_ITEM then
      return false, "item not in that game"
    end
  end
  return true
end

-- the receiver's own check of an arriving mon, against the same rules from
-- the other end (a sender that skipped canSend is caught here)
function CompatRules.canReceive(packed, localHello, remoteHello)
  return CompatRules.canSend(packed, remoteHello, localHello)
end

return CompatRules
