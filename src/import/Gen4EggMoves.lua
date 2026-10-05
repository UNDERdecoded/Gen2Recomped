-- PLATINUM'S EGG MOVES (pokeplatinum src/overlay005/daycare.c,
-- res/pokemon/*/data.json "egg_moves").
--
-- `sEggMoves` is compiled into OVERLAY 5 beside the day care that reads it:
-- one flat u16 list, each species introduced by 20000 + species
-- (EGG_MOVES_SPECIES_OFFSET) and followed by its moves, the whole closed by
-- 0xFFFF. LoadSpeciesEggMoves reads at most sixteen (MAX_EGG_MOVES).
--
-- Found by content: the table opens with Bulbasaur -- 20001, Light Screen,
-- Skull Bash, Safeguard.
--
-- Written to the cache module `gen4_egg_moves` as { [species] = { moves } }.

local Gen4EggMoves = {}

Gen4EggMoves.OVERLAY = 5
Gen4EggMoves.OFFSET = 20000
Gen4EggMoves.MAX = 16
Gen4EggMoves.SIGNATURE = string.char(0x21, 0x4E, 113, 0, 130, 0, 219, 0)

function Gen4EggMoves.parse(ov)
  if type(ov) ~= "string" then return nil, "no overlay" end
  local at = ov:find(Gen4EggMoves.SIGNATURE, 1, true)
  if not at then return nil, "sEggMoves not found in overlay 5" end
  local out, species, count = {}, nil, 0
  local o = at
  while o + 1 <= #ov do
    local v = ov:byte(o) + ov:byte(o + 1) * 256
    o = o + 2
    if v == 0xFFFF then break end
    if v > Gen4EggMoves.OFFSET then
      species = v - Gen4EggMoves.OFFSET
      out[species] = {}
      count = count + 1
    elseif species then
      local list = out[species]
      list[#list + 1] = v
    end
  end
  return out, count
end

function Gen4EggMoves.extract(rom)
  local ov = rom and rom:overlay(Gen4EggMoves.OVERLAY)
  return (Gen4EggMoves.parse(ov))
end

-- LoadSpeciesEggMoves: the first sixteen of the species' list.
function Gen4EggMoves.of(rec, species)
  local list = rec and rec[tonumber(species)]
  local out = {}
  for i = 1, math.min(Gen4EggMoves.MAX, list and #list or 0) do out[i] = list[i] end
  return out
end

return Gen4EggMoves
