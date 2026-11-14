-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) type effectiveness, read out of the battle overlay.
--
-- The chart is not a 18x18 grid.  It is a LIST of exceptions -- attacking
-- type, defending type, multiplier in tenths -- and every pair not listed is
-- 1x.  Multipliers are 0 (immune), 5 (half) and 20 (double).
--
-- IT HAS TWO SECTIONS AND TWO TERMINATORS, and that is the part worth getting
-- right.  108 rows, then a 0xFE marker, then TWO more rows -- Normal vs Ghost
-- and Fighting vs Ghost, both immune -- and then 0xFF.  The game's own
-- multiplier routine loops until 0xFF, so it walks straight past the marker
-- and applies all 110; other code stops at 0xFE deliberately, because those
-- last two are the immunities Foresight and Scrappy lift.
--
-- A reader that stops at the FIRST terminator therefore produces a chart in
-- which NORMAL DOES NEUTRAL DAMAGE TO GHOST.  Nothing errors; the game is
-- simply wrong in a way that takes a battle to notice.
--
-- WHERE IT LIVES.  Overlay 16, the battle overlay -- not the ARM9, which is
-- where a search that only looks there comes back empty.  The offset is found
-- by SEARCHING for the table's own shape rather than hardcoded, because Rev 0
-- is a different binary: a run of at least 90 triples whose first two bytes
-- are valid type ids and whose third is one of the three multipliers, ending
-- in a terminator.  That shape is specific enough that nothing else in a
-- 220 KB overlay matches it.

local Gen4TypeChart = {}

local byte = string.byte

-- The type ids, read from the cartridge rather than assumed: message bank 624
-- is exactly these eighteen names in this order, which is how the numbering
-- was established.  Slot 9 is the unused "???" type and is real -- leaving it
-- out would shift every type after it.
-- !! AND THEY ARE UPPERCASE, BECAUSE EVERY OTHER GENERATION IN THIS LAUNCHER IS.
--
-- Reported from play: *"moves dont seem to be decoded and working properly
-- scratch doesnt work"*. Scratch decodes perfectly -- power 40, pp 35, accuracy
-- 100, physical, effect 0, typeId 0 -- and it still did nothing recognisable,
-- because NOTHING DOWNSTREAM COULD READ ITS TYPE. Three mismatches in one
-- chain, and each one on its own is invisible:
--
--   * a Gen 4 MOVE carried `typeId` and no `type`, and `Damage.lua` reads
--     `move.type` in nine places -- STAB, effectiveness, weather, held items,
--     Abilities.normalizeType. Every Platinum move was TYPELESS.
--   * a Gen 4 SPECIES carried `types = { "grass" }` in lower case, while
--     Crystal's chart is keyed `GRASS`, and TypeChart matches on string
--     identity (`m.defender == dt`). Even with a chart, nothing would have
--     matched.
--   * and `Gen4TypeChart.chart` returned a nested `out[attacker][defender]`
--     map, where `TypeChart.load` wants `matchups` as an ARRAY and `types` as
--     a record per type. So `data.type_chart.matchups` was nil.
--
-- The result was a region where Normal hit Ghost, Water did not beat Fire, and
-- no move ever got its own type's bonus -- with no crash and no log line.
-- Lower case was not wrong on its own; it was wrong BESIDE four other games.
Gen4TypeChart.TYPES = {
  [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK",
  "BUG", "GHOST", "STEEL", "MYSTERY", "FIRE", "WATER", "GRASS",
  "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK",
}
local DEFAULT_NAMES = {}
for i = 0, #Gen4TypeChart.TYPES do DEFAULT_NAMES[i] = Gen4TypeChart.TYPES[i] end

-- setSlotNames({ [id] = NAME }) -- a cartridge that renames a type slot
-- (Renegade Platinum's slot 9 is FAIRY; Gen4Versions.TYPE_SLOTS). Edits
-- TYPES IN PLACE, because Gen4Species.TYPES and Gen4Moves read this very
-- table; nil puts Platinum's names back, so the next extractor in the same
-- process starts clean.
function Gen4TypeChart.setSlotNames(slots)
  for i = 0, #DEFAULT_NAMES do Gen4TypeChart.TYPES[i] = DEFAULT_NAMES[i] end
  for i, name in pairs(slots or {}) do Gen4TypeChart.TYPES[i] = name end
end

-- The physical/special split BY TYPE, which Gen 4 does not use and the engine
-- still asks for. Platinum decides it per MOVE (`class` on the move record,
-- which every Gen 4 move carries), so `Damage.lua` reaches
-- `TypeChart.category` only when a move has neither -- a mod's move, or a
-- damaged cache. Filled with the pre-Gen-4 split so that fallback is the
-- historical answer rather than nil: types 0..8 physical, 10..17 special, and
-- the unused slot 9 physical with them.
Gen4TypeChart.SPECIAL_FROM = 10
Gen4TypeChart.TYPE_COUNT = 18
Gen4TypeChart.TYPE_NAME_BANK = 624

-- Multipliers, in tenths of the base 1x.
Gen4TypeChart.IMMUNE = 0
Gen4TypeChart.NOT_VERY_EFFECTIVE = 5
Gen4TypeChart.SUPER_EFFECTIVE = 20

Gen4TypeChart.FORESIGHT_MARKER = 0xFE
Gen4TypeChart.END = 0xFF

local VALID_MULTIPLIER = {
  [0] = true, [5] = true, [20] = true,
}

-- `dense`: also accept 10 (1x). Platinum's chart lists only the exceptions;
-- Renegade Platinum's replacement lists every pair, neutral ones included.
local function looksLikeRow(data, at, dense)
  local a, b, m = byte(data, at, at + 2)
  if not m then return false end
  if a >= Gen4TypeChart.TYPE_COUNT then return false end
  if b >= Gen4TypeChart.TYPE_COUNT then return false end
  return VALID_MULTIPLIER[m] == true or (dense == true and m == 10)
end

-- find(overlay, minimumRows) -> offset (0-based) of the first row, or nil.
--
-- TAKES THE LONGEST RUN, NOT THE FIRST, and that distinction cost a row.
--
-- The obvious scan -- walk forward, return the first position that starts a
-- long enough run -- is wrong twice over.  A coincidental triple just before
-- the table can start a run that swallows it one byte out of phase; and
-- skipping ahead past a short run can step OVER the true start and lock onto
-- row two, which is what happened here: the chart begins `00 05 05` at
-- 0x33B94 and the first version returned 0x33B97, quietly dropping
-- "normal vs rock, half damage" and reporting 109 rows instead of 110.
--
-- Nothing failed.  The chart was one row short in a way no count would catch
-- without knowing the answer first.
--
-- So: advance one byte at a time, keep the LONGEST run, and then extend it
-- BACKWARD while the preceding triple is also a valid row.  The backward step
-- is what makes the answer independent of where the forward scan happened to
-- lock on.
function Gen4TypeChart.find(data, minimumRows)
  minimumRows = minimumRows or 90
  if type(data) ~= "string" then return nil end

  local bestAt, bestRows
  local at = 1
  while at + 2 <= #data do
    if looksLikeRow(data, at) then
      local rows, p = 0, at
      while p + 2 <= #data and looksLikeRow(data, p) do
        rows = rows + 1
        p = p + 3
      end
      local terminator = byte(data, p)
      if rows >= minimumRows
         and (terminator == Gen4TypeChart.FORESIGHT_MARKER
              or terminator == Gen4TypeChart.END)
         and (not bestRows or rows > bestRows) then
        bestAt, bestRows = at, rows
      end
    end
    at = at + 1
  end

  if not bestAt then return nil end

  while bestAt - 3 >= 1 and looksLikeRow(data, bestAt - 3) do
    bestAt = bestAt - 3
    bestRows = bestRows + 1
  end

  return bestAt - 1, bestRows
end

-- parse(overlay, at) -> { rows = { { attacker, defender, multiplier } },
--                         foresightFrom = n, sections = 2 }
--
-- `foresightFrom` is the 1-based index of the first row past the 0xFE marker:
-- those are the matchups Foresight and Scrappy remove, and a caller that wants
-- the ordinary chart stops there while the damage routine does not.
function Gen4TypeChart.parse(data, at, dense)
  if not at then at = Gen4TypeChart.find(data) end
  if not at then return nil, "no type chart in this binary" end

  local rows, foresightFrom, sections, ended = {}, nil, 1, false
  local p = at + 1
  while p + 2 <= #data do
    local a = byte(data, p)
    if a == Gen4TypeChart.END then ended = true break end
    if a == Gen4TypeChart.FORESIGHT_MARKER then
      foresightFrom = #rows + 1
      sections = sections + 1
      p = p + 3
    else
      local b, m = byte(data, p + 1, p + 2)
      if not looksLikeRow(data, p, dense) then break end
      rows[#rows + 1] = { a, b, m }
      p = p + 3
    end
    if #rows > 512 then break end
  end

  return {
    ended = ended,
    dense = dense == true or nil,
    rows = rows,
    foresightFrom = foresightFrom,
    sections = sections,
    at = at,
  }
end

-- chart(parsed) -> the engine-facing table: chart[attacker][defender] = factor,
-- as a MULTIPLIER IN TENTHS so nothing has to carry a float.  A pair with no
-- entry is absent, and absent means 1x -- filling in 10 everywhere would turn
-- a 324-cell sparse list into a dense one for no gain.
-- chart(parsed) -> the table the ENGINE reads, not a convenient one.
--
-- !! THIS USED TO RETURN A SHAPE NOTHING COULD LOAD. It built
-- `out[attacker][defender] = multiplier`, keyed by numeric type id -- a fine
-- lookup table and not what `TypeChart.load` takes:
--
--     matchups = data.type_chart.matchups   -- an ARRAY of {attacker, defender,
--                                           --   multiplier}, by type NAME
--     types    = data.type_chart.types      -- name -> { name, category }
--
-- so `#matchups` was nil and the chart never loaded. Checked against a real
-- Crystal cache rather than against this file's own idea of the shape:
-- `type_chart.lua` there is `{ ids, matchups, types, source }` with
-- `NORMAL vs ROCK = 5`, multipliers in tenths. That is what this emits now.
--
-- `ids` is kept beside the names because the cartridge's own numbering is what
-- every other Gen 4 table speaks (a species' `typeIds`, a move's `typeId`), and
-- a consumer holding a number should not have to re-derive the map.
function Gen4TypeChart.chart(parsed)
  if not parsed then return nil end
  local names = Gen4TypeChart.TYPES
  local out = { matchups = {}, types = {}, ids = {}, foresight = nil }

  for i = 0, Gen4TypeChart.TYPE_COUNT - 1 do
    local name = names[i]
    if name then
      out.ids[name] = i
      out.types[name] = {
        name = name,
        category = (i >= Gen4TypeChart.SPECIAL_FROM) and "special" or "physical",
      }
    end
  end

  for i, row in ipairs(parsed.rows) do
    local attacker, defender, multiplier = names[row[1]], names[row[2]], row[3]
    -- a dense chart's 1x rows say nothing an absent pair does not
    if attacker and defender and multiplier ~= 10 then
      out.matchups[#out.matchups + 1] = {
        attacker = attacker, defender = defender, multiplier = multiplier,
      }
      -- The Foresight rows are real matchups and belong in the chart; they are
      -- marked so the two moves that lift them can find them again.
      if parsed.foresightFrom and i >= parsed.foresightFrom then
        out.foresight = out.foresight or {}
        out.foresight[#out.foresight + 1] = { attacker, defender }
      end
    end
  end

  out.source = ("ROM: overlay %s, %d rows"):format(
    tostring(parsed.overlay), #out.matchups)
  return out
end

-- follow(rom, data, info, at) -> the chart the battle code ACTUALLY reads,
-- when that is not the one `find` located, else nil.
--
-- The battle overlay reaches its chart through literal-pool words, and it
-- loads the three columns separately: `&chart[0]`, `&chart[1]`, `&chart[2]`,
-- three consecutive words X, X+1, X+2. Platinum's point at the table `find`
-- returns. A hack that rewrites the chart can leave the old table where it is
-- and repoint those words -- Renegade Platinum does exactly that: overlay 16
-- keeps the vanilla 110 rows at 0x33B94, every reference to them now reads
-- 0x021E9F80, and that is a dense 18x18 chart (Fairy row and column
-- included) appended to the end of overlay 21. Read the old one and Fairy
-- does neutral damage to everything.
--
-- So: if the overlay still holds a pointer to the table found, it is the live
-- one and this returns nil (every retail cartridge). Otherwise each X, X+1,
-- X+2 triple is resolved into whichever overlay (or the ARM9) loads at X and
-- parsed there, dense rows allowed; the first that parses to a whole chart
-- (90+ rows, closed by 0xFF) wins.
local function u32(s, i)
  local a, b, c, d = byte(s, i, i + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end
function Gen4TypeChart.follow(rom, data, info, at)
  if not (rom and type(data) == "string" and info and info.ram and at) then return nil end
  local live = info.ram + at
  local triples = {}
  for p = 1, #data - 11, 4 do
    local x = u32(data, p)
    if x == live then return nil end
    if x and x >= 0x02000000 and x < 0x02400000
       and u32(data, p + 4) == x + 1 and u32(data, p + 8) == x + 2 then
      triples[#triples + 1] = x
    end
  end
  local images = {}
  local n = 0
  while true do
    local ok, bytes, oi = pcall(rom.overlay, rom, n)
    if not ok or not bytes then break end
    images[#images + 1] = { overlay = n, bytes = bytes, ram = oi and oi.ram }
    n = n + 1
  end
  local okA, arm9 = pcall(rom.arm9, rom)
  local okH, header = pcall(rom.header, rom)
  if okA and arm9 then
    images[#images + 1] = { overlay = "arm9", bytes = arm9,
                            ram = okH and header and header.arm9 and header.arm9.ram or 0x02000000 }
  end
  for _, x in ipairs(triples) do
    for _, image in ipairs(images) do
      local off = image.ram and (x - image.ram)
      if off and off >= 0 and off + 3 <= #image.bytes then
        local parsed = Gen4TypeChart.parse(image.bytes, off, true)
        if parsed and parsed.ended and #parsed.rows >= 90 then
          parsed.overlay = image.overlay
          parsed.ram = x
          return parsed
        end
      end
    end
  end
  return nil
end

return Gen4TypeChart
