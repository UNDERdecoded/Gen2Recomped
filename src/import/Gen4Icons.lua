-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- src/import/Gen4Icons.lua -- THE LITTLE POKEMON IN THE PARTY LIST.
--
-- Reported from play: "in the pokemon party menus the pokemon party sprites are
-- missing". They were not broken -- THEY WERE NEVER EXTRACTED. Nothing in the
-- Gen 4 pipeline had ever opened /poketool/icongra/pl_poke_icon.narc, so
-- `data.icons` was nil on a Platinum cache, `Gen4PartyMenu:iconFor` found
-- nothing and every slot fell back to the ball behind it.
--
-- THE ARCHIVE, measured: 547 members.
--
--   0        NCLR, 256 colours -- and only THREE of its sixteen sub-palettes
--            carry any colour, which is the whole reason the table below has
--            to exist
--   1..6     three NANR/NCER pairs, the bounce animation's cell banks
--   7..546   one NCGR per icon, 540 of them
--
-- `IconTilesIndex(icon) = icon + icon_00000_NCGR` (src/pokemon_icon.c), so the
-- sheet for species N is member 7 + N and the sheets past the species run are
-- the forms -- Unown's letters, Deoxys, Burmy, Wormadam, Shellos, Gastrodon,
-- Giratina, Shaymin, Rotom -- plus the two eggs.
--
-- Each sheet is 1072 bytes: a 48-byte NCGR header and 1024 of pixels, which at
-- 4bpp is 32x64 -- TWO 32x32 FRAMES, the up and down of the bounce.
--
-- ---------------------------------------------------------------------------
-- !! WHICH OF THE THREE RAMPS A SPECIES USES IS A TABLE IN THE ARM9
--
-- `PokeIconPaletteIndex` ends `return sPokemonIconPaletteIndex[species]`, and
-- that array is `#include "res/pokemon/species_icon_palettes.h"` -- compiled
-- into the binary, like the healthbox parts. One byte per icon, values 0..2.
--
-- FOUND BY STRUCTURE, like the type chart and the healthbox parts: a run of at
-- least ICON_COUNT bytes, every one of them below the number of sub-palettes
-- that actually carry colour. Over the whole ARM9 that matches TWICE, so there
-- is a tie-break, and it is worth stating plainly because it is a judgement
-- rather than a derivation:
--
--   THE RUN WHOSE VALUES ARE MOST EVENLY SPREAD WINS.
--
--   measured over the first 540 bytes of each:
--     the other run   434 / 86 / 20    0.852 bits
--     this one        252 / 149 / 139  1.530 bits   (of a possible 1.585)
--
-- A selector that puts eighty per cent of the species on one ramp is not
-- selecting. That reasoning is suggestive and not proof, so THE ANSWER WAS
-- CHECKED BY LOOKING: a hundred icons rendered with it come out the right
-- colours -- Bulbasaur green, Charmander orange, Squirtle blue, Pikachu
-- yellow, Mewtwo purple, the three Sinnoh starters -- and with the other run
-- every one of those seven lands on ramp 0, which cannot be right for two
-- species of different colours.
--
-- `tools/gen4_icon_check.lua` then asserts the seven values that render was
-- verified against, so a build that moves the table and picks the wrong run
-- fails loudly instead of quietly recolouring the party list.
--
-- A DISCRIMINATOR I TRIED AND THREW AWAY, because it is the kind that looks
-- rigorous and decides nothing: "the ramp that puts the most non-black colour
-- on the icon". Both candidates score IDENTICALLY -- all three sub-palettes are
-- fully populated, so every ramp colours every pixel. Measuring it is what
-- stopped it going in.

local Gen4Icons = {}

Gen4Icons.PATH = "/poketool/icongra/pl_poke_icon.narc"

Gen4Icons.PALETTE_MEMBER = 0
Gen4Icons.FIRST_SHEET = 7          -- icon_00000_NCGR
Gen4Icons.WIDTH = 32
Gen4Icons.FRAME_HEIGHT = 32
Gen4Icons.FRAMES = 2               -- the bounce: 32x64 of pixels per sheet
Gen4Icons.TILES_WIDE = 4           -- 32 pixels across

-- Only three of the palette's sixteen sub-palettes carry colour, and that is
-- the fact the whole selector rests on. Asserted at import rather than
-- assumed: a cartridge whose icons used more would need a wider scan.
Gen4Icons.RAMPS = 3

-- !! THE ANCHORS ARE THE CARTRIDGE'S OWN VALUES NOW, not a render judged by
-- eye. The first version of this table was "checked by looking" and was
-- wrong for Pikachu and Piplup (0, where pokeplatinum's
-- res/pokemon/<species>/data.json says `"icon_palette": 2`): the scan had
-- found a run of small bytes that STARTS 118 bytes before the real array, so
-- every species read its neighbour's ramp -- Infernape green and pink,
-- Pikachu purple, reported from the party screen. The table is now located
-- by these values, at whatever offset inside a qualifying run they all hold.
-- Species id -> ramp, from each species' data.json.
Gen4Icons.VERIFIED = {
  [1] = 1,    -- Bulbasaur
  [4] = 0,    -- Charmander
  [7] = 0,    -- Squirtle
  [25] = 2,   -- Pikachu
  [54] = 1,   -- Psyduck
  [74] = 1,   -- Geodude
  [130] = 0,  -- Gyarados
  [133] = 2,  -- Eevee
  [150] = 2,  -- Mewtwo
  [387] = 1,  -- Turtwig
  [390] = 1,  -- Chimchar
  [392] = 0,  -- Infernape
  [393] = 2,  -- Piplup
  [395] = 0,  -- Empoleon
}

local function spread(bin, at, count, ramps)
  local seen, total = {}, 0
  for i = 0, count - 1 do
    local v = bin:byte(at + i)
    if not v or v >= ramps then return nil end
    seen[v] = (seen[v] or 0) + 1
    total = total + 1
  end
  if total == 0 then return nil end
  -- Shannon entropy, in bits. A run that is almost all one value scores near
  -- zero and loses to one that actually distinguishes species.
  local h = 0
  for _, n in pairs(seen) do
    local p = n / total
    h = h - p * (math.log(p) / math.log(2))
  end
  return h, seen
end

-- Find sPokemonIconPaletteIndex in the ARM9 binary.
-- Returns a 1-based byte offset and the entropy it won with, or nil.
function Gen4Icons.findPaletteTable(bin, icons)
  if type(bin) ~= "string" then return nil end
  icons = icons or 540
  local ramps = Gen4Icons.RAMPS
  local best, bestAt, bestCounts = -1, nil, nil
  local at, n = 1, #bin
  while at <= n - icons do
    local b = bin:byte(at)
    if b and b < ramps then
      -- walk to the end of this run, then test it from its start: the table
      -- begins where the run begins, because the byte before it is not a ramp
      local last = at
      while last <= n and (bin:byte(last) or ramps) < ramps do last = last + 1 end
      local length = last - at
      if length >= icons then
        -- the array can begin INSIDE the run (the bytes before it may be
        -- small too): the offset where every anchor holds wins outright
        for start = at, last - icons do
          if Gen4Icons.verify(bin, start) then
            local h, counts = spread(bin, start, icons, ramps)
            return start, h, counts
          end
        end
        local h, counts = spread(bin, at, icons, ramps)
        if h and h > best then best, bestAt, bestCounts = h, at, counts end
      end
      at = last
    else
      at = at + 1
    end
  end
  if not bestAt then return nil end
  return bestAt, best, bestCounts
end

-- Does the table this scan found agree with what the render was checked
-- against? The extractor refuses a table that does not, because a wrong one
-- produces a party list that is merely MIS-COLOURED -- which looks like a
-- palette bug rather than a located-the-wrong-array bug.
function Gen4Icons.verify(bin, at)
  local wrong = {}
  for species, ramp in pairs(Gen4Icons.VERIFIED) do
    local got = bin:byte(at + species)
    if got ~= ramp then
      wrong[#wrong + 1] = ("%d got %s want %d")
        :format(species, tostring(got), ramp)
    end
  end
  return #wrong == 0, wrong
end

function Gen4Icons.ramp(bin, at, species)
  return bin:byte(at + (tonumber(species) or 0)) or 0
end

return Gen4Icons
