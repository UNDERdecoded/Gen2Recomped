-- Which games share one GTS (docs/online-design.md 2.7a, workstream WS7).
--
-- The pools follow the cartridges' own link rules (src/online/CompatRules):
--
--   dppt   Diamond / Pearl / Platinum / HeartGold / SoulSilver   (cartridge)
--   bw     Black / White                                         (cartridge)
--   rby    Red / Blue / Yellow                          PORT EXTENSION
--   gsc    Gold / Silver / Crystal                      PORT EXTENSION
--   rse    Ruby / Sapphire / Emerald / FireRed / LeafGreen
--                                                       PORT EXTENSION
--   prism, polishedcrystal: the romhacks, each its own   PORT EXTENSION
--
-- Gen 1 and Gen 2 are NOT pooled together (the Time Capsule is a cable
-- feature, not a GTS one).  R/S/E and FR/LG share one pool the way their
-- cartridges link; the FR/LG National Dex gate is applied per deposit
-- (CompatRules.canSend), so an FR/LG save without it never sees a Hoenn mon.
-- To split them, give frlg its own row below.
--
-- Pure: no love, no data.

local GtsPools = {}

GtsPools.POOLS = {
  rby = { id = "rby", gen = 1, port = true, maxDex = 151,
          families = { rby = true }, label = "RED / BLUE / YELLOW" },
  gsc = { id = "gsc", gen = 2, port = true, maxDex = 251,
          families = { gsc = true }, label = "GOLD / SILVER / CRYSTAL" },
  prism = { id = "prism", gen = 2, port = true,
            families = { prism = true }, label = "PRISM" },
  polishedcrystal = { id = "polishedcrystal", gen = 2, port = true,
                      families = { polishedcrystal = true }, label = "POLISHED CRYSTAL" },
  rse = { id = "rse", gen = 3, port = true, maxDex = 386,
          families = { rse = true, frlg = true },
          label = "RUBY / SAPPHIRE / EMERALD / FIRERED / LEAFGREEN" },
  dppt = { id = "dppt", gen = 4, port = false, maxDex = 493,
           families = { dppt = true, hgss = true },
           label = "DIAMOND / PEARL / PLATINUM / HEARTGOLD / SOULSILVER" },
  bw = { id = "bw", gen = 5, port = false, maxDex = 649,
         families = { bw = true }, label = "BLACK / WHITE" },
}

-- family -> pool id
GtsPools.BY_FAMILY = {}
for id, p in pairs(GtsPools.POOLS) do
  for fam in pairs(p.families) do GtsPools.BY_FAMILY[fam] = id end
end

function GtsPools.get(id) return GtsPools.POOLS[id] end

-- the pool a family (or a game id) trades in; nil when none
function GtsPools.poolFor(familyOrGame)
  local key = tostring(familyOrGame or ""):lower()
  local id = GtsPools.BY_FAMILY[key]
  if id then return id end
  local CompatRules = require("src.online.CompatRules")
  local fam = CompatRules.familyOf(key)
  return fam and GtsPools.BY_FAMILY[fam] or nil
end

-- the pool a hello table belongs to
function GtsPools.poolOfHello(hello)
  if type(hello) ~= "table" then return nil end
  return GtsPools.poolFor(hello.family or hello.game)
end

function GtsPools.isPort(id)
  local p = GtsPools.POOLS[id]
  return p ~= nil and p.port == true
end

-- the line a screen shows under its title: what this pool is
function GtsPools.describe(id)
  local p = GtsPools.POOLS[id]
  if not p then return "Unknown GTS pool" end
  if p.port then return p.label .. " (port extension)" end
  return p.label
end

-- the families a pool id serves, sorted (reports and the refusal text)
function GtsPools.families(id)
  local p = GtsPools.POOLS[id]
  local out = {}
  if p then for f in pairs(p.families) do out[#out + 1] = f end end
  table.sort(out)
  return out
end

return GtsPools
