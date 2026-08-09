-- The badge set as data (constants.badges): an ordered list of
-- { id, name?, icon?, item? } records where list position is the badge
-- number.  Every screen that used to carry its own copy of the gym order
-- reads it from here; the literal survives only as the fallback for caches
-- imported before the constant existed.

local Badges = {}

-- gym order (data/scripts/victories.lua)
local VANILLA = {
  { id = "BOULDERBADGE" }, { id = "CASCADEBADGE" }, { id = "THUNDERBADGE" },
  { id = "RAINBOWBADGE" }, { id = "SOULBADGE" },    { id = "MARSHBADGE" },
  { id = "VOLCANOBADGE" }, { id = "EARTHBADGE" },
}

-- Gold/Silver's sixteen, in trainer card order (RomExtractorGen2's
-- GEN2_BADGES).  Only the launcher needs this literal: it summarises saves
-- before any Data exists, so falling back to the Kanto-only list above
-- counted every Johto playthrough as zero badges.
local GEN2 = {
  { id = "ZEPHYRBADGE" },  { id = "HIVEBADGE" },     { id = "PLAINBADGE" },
  { id = "FOGBADGE" },     { id = "STORMBADGE" },    { id = "MINERALBADGE" },
  { id = "GLACIERBADGE" }, { id = "RISINGBADGE" },
  { id = "BOULDERBADGE" }, { id = "CASCADEBADGE" }, { id = "THUNDERBADGE" },
  { id = "RAINBOWBADGE" }, { id = "SOULBADGE" },    { id = "MARSHBADGE" },
  { id = "VOLCANOBADGE" }, { id = "EARTHBADGE" },
}

function Badges.list(data, version)
  local list = data and data.constants and data.constants.badges
  if type(list) == "table" and #list > 0 then return list end
  if require("src.core.GameVersion").isGen2(version) then return GEN2 end
  return VANILLA
end

-- badges are stored under an inventory key, which is the badge id unless
-- the record names a different item
function Badges.itemFor(entry)
  return entry.item or entry.id
end

-- R/B hands badges over as inventory items; Gen2 has no badge item at all --
-- its gyms run `setflag ENGINE_ZEPHYRBADGE`, which lands in save.flags under
-- the badge id (see Gen2ScriptVM's ENGINE_FLAG_NAMES).  Either store counts.
function Badges.has(save, entry)
  local key = Badges.itemFor(entry)
  return (save.inventory and save.inventory[key])
    or (save.flags and save.flags[key]) and true or false
end

function Badges.count(data, save, version)
  if not save then return 0 end
  local n = 0
  for _, entry in ipairs(Badges.list(data, version)) do
    if Badges.has(save, entry) then n = n + 1 end
  end
  return n
end

return Badges
