-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE DOOR ANIMATION'S REAL BLOCKER WAS THE JOIN, AND A STALE CLAIM HID IT.
--
-- Pass 178 shipped the door sounds and recorded, in two files, that the
-- animation was out of reach because "this port reads NSBMD without NSBCA and
-- bakes a chunk's props into a flat canvas". Both halves were already false:
--
--   * `Gen4Anim.jointMatrices` parses BCA0 and the title sequence and starter
--     models already wear joint poses;
--   * `Gen4Ground` draws every prop as a LIVE model each frame, and
--     `Gen4Model:draw(viewProjection, pose, ...)` takes a pose.
--
-- `Gen4Doors.lua` opens by warning about exactly this failure mode -- a
-- declined feature outliving its blocker -- and then committed it in its own
-- next paragraph.
--
-- The actual blocker: `/arc/bm_anime.narc` holds 98 animations and NO models,
-- so the extractor's same-archive node-count pairing marked all 98 `unworn`.
-- The pairing is in a third file, which pokeplatinum's own map-format graph
-- names:
--
--     area_build    --> bm_anime_list : mapPropModelIDs
--     bm_anime_list --> bm_anime      : animeArchiveIDs
--
-- THE DOCUMENTED RECORD LAYOUT IS WRONG BY ONE, and section 2 is the reason
-- this check exists rather than a table of numbers. The spec puts
-- `animeArchiveIDs` at 0x03; the records are 20 bytes with a zero at 0x03 and
-- the array starts at 0x04. Section 2 reads the archive BOTH WAYS and compares
-- how many ids land inside the 98-member target -- 0 out of range at 0x04
-- against 264 at 0x03 -- so the correction is re-derived every run and would
-- fail if it were wrong.
--
-- Run:  texlua tools/gen4_prop_anim_check.lua <rom> [pokeplatinum] [cache dir]

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local ROM   = arg and arg[1]
local PRET  = arg and arg[2]
local CACHE = arg and arg[3]

local fails, checks, reports, skips = 0, 0, 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function report(fmt, ...)
  reports = reports + 1
  io.write("REPORT: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function skip(fmt, ...)
  skips = skips + 1
  io.write("SKIP: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(p)
  if not p then return nil end
  local f = io.open(p, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function loadTable(dir, name)
  if not dir then return nil end
  local f = loadfile(dir .. "/" .. name .. ".lua")
  if not f then return nil end
  local okRun, t = pcall(f)
  return okRun and t or nil
end
local function code(src)
  if not src then return "" end
  return (src:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\r\n]*", " "))
end
local function cdefn(src, name)
  return src and src:match("[%w_%*%s]-" .. name .. "%s*%b()%s*\n{(.-)\n}")
end

local drawn = {}
love = love or {
  graphics = { getWidth = function() return 256 end,
               getHeight = function() return 192 end,
               getDimensions = function() return 256, 192 end,
               getPixelDimensions = function() return 256, 192 end,
               getDPIScale = function() return 1 end,
               newCanvas = function() return nil end,
               newImage = function() return nil end,
               setColor = function() end, rectangle = function() end,
               push = function() end, pop = function() end,
               setFont = function() end },
  window = { getMode = function() return 256, 192, {} end },
  timer = { getTime = function() return 0 end },
  filesystem = { getInfo = function() return nil end, read = function() return nil end },
  system = { getOS = function() return "Linux" end },
  image = { newImageData = function() return nil end },
  math = { random = math.random },
}

local GameVersion = require("src.core.GameVersion")
GameVersion.set("platinum")
local Commands = require("src.script.Commands")

local Gen4PropAnim = require("src.import.Gen4PropAnim")
local Gen4Doors    = require("src.world.Gen4Doors")
local A            = require("src.import.Gen4Archives")
local NdsRom = require("src.import.NdsRom")
local Narc   = require("src.import.NarcArchive")

local LIST_PATH  = "/arc/bm_anime_list.narc"
local ANIM_PATH  = "/arc/bm_anime.narc"
local MODEL_PATH = "/fielddata/build_model/build_model.narc"

local function u32(s, at)
  local a, b, c, d = s:byte(at, at + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- ---------------------------------------------------------------------------
section("1. the constants, with nothing but the repository")
-- ---------------------------------------------------------------------------
ok(Gen4PropAnim.RECORD_BYTES == 20,
   "the list record is %s bytes; they are 20",
   tostring(Gen4PropAnim.RECORD_BYTES))
ok(Gen4PropAnim.IDS_AT == 4,
   "animeArchiveIDs is at 0x%02X; the spec says 0x03 and the archive says "
   .. "0x04 -- see section 2", Gen4PropAnim.IDS_AT or 0)
ok(Gen4PropAnim.PAD_AT == 3, "the pad byte is not recorded at 0x03")
ok(Gen4PropAnim.MAX_ANIMATIONS == 4,
   "a prop supports %s animations; the record holds four ids",
   tostring(Gen4PropAnim.MAX_ANIMATIONS))
ok(Gen4PropAnim.NONE == 0xFFFFFFFF, "the empty-id sentinel is not 0xFFFFFFFF")
ok(Gen4PropAnim.HAS == 1,
   "hasAnimations is tested against %s; it must be `== 1`, because the archive "
   .. "writes 0xFF rather than 0 for a prop with none and `~= 0` would call "
   .. "every one of those animated", tostring(Gen4PropAnim.HAS))
ok(Gen4PropAnim.OPEN_INDEX == 0 and Gen4PropAnim.CLOSE_INDEX == 1,
   "open/close are animation indices %s/%s; both of pokeplatinum's count arms "
   .. "collapse to 0 for open and 1 for close",
   tostring(Gen4PropAnim.OPEN_INDEX), tostring(Gen4PropAnim.CLOSE_INDEX))
ok(#Gen4PropAnim.DOORS == 20,
   "%d door rows; `doorModelIDs[]` has twenty", #Gen4PropAnim.DOORS)

-- the parser, on records built here, so section 1 can fail with no cartridge
do
  local function rec(has, flags, slope, ids)
    local s = string.char(has, flags, slope, 0)
    for k = 1, 4 do
      local v = ids[k] or 0xFFFFFFFF
      s = s .. string.char(v % 256, math.floor(v / 256) % 256,
                           math.floor(v / 65536) % 256,
                           math.floor(v / 16777216) % 256)
    end
    return s
  end
  local two = Gen4PropAnim.parse(rec(1, 0x03, 0, { 5, 6 }))
  ok(two and two.has and two.count == 2 and two.ids[1] == 5 and two.ids[2] == 6,
     "a two-animation record parsed as %s",
     two and tostring(two.count) or "nil")
  local four = Gen4PropAnim.parse(rec(1, 0x03, 0, { 7, 8, 9, 10 }))
  ok(four and four.count == 4, "a four-animation record parsed as %s",
     four and tostring(four.count) or "nil")
  -- THE 0xFF OVERSIGHT, which is the one that would quietly animate everything
  local none = Gen4PropAnim.parse(rec(0xFF, 0xFF, 0xFF, {}))
  ok(none and none.has == false and none.count == 0,
     "a record with hasAnimations = 0xFF came back as animated (count %s); "
     .. "the archive writes 0xFF, not 0, when a prop has none",
     none and tostring(none.count) or "nil")
  ok(Gen4PropAnim.parse("short") == nil,
     "a truncated record parsed instead of being refused")
  ok(Gen4PropAnim.deferredLoad({ flags = 0x03 }) == true
     and Gen4PropAnim.deferredLoad({ flags = 0x02 }) == false,
     "the deferred-load flag is not bit 0")
end

-- ---------------------------------------------------------------------------
section("2. the record offset, measured both ways")
-- ---------------------------------------------------------------------------
local list, anim, models
if not ROM then
  skip("no cartridge, so the record layout is not re-derived this run")
else
  local rom = NdsRom.open(ROM)
  ok(rom ~= nil, "could not open %s", tostring(ROM))
  if rom then
    list   = Narc.parse(rom:read(LIST_PATH))
    anim   = Narc.parse(rom:read(ANIM_PATH))
    models = Narc.parse(rom:read(MODEL_PATH))
  end
  ok(list ~= nil and anim ~= nil and models ~= nil,
     "one of %s / %s / %s is missing from the cartridge",
     LIST_PATH, ANIM_PATH, MODEL_PATH)
end

if list and anim and models then
  ok(list.count == models.count,
     "%d list records against %d prop models; the list is one record PER "
     .. "MODEL, so a mismatch means the join is not index-for-index",
     list.count, models.count)
  ok(list.count == 590, "the list has %d members, not 590", list.count)
  ok(anim.count == 98, "bm_anime has %d members, not 98", anim.count)

  -- every record the documented size, and the byte at 0x03 always zero
  local sizes, pads = {}, {}
  for i = 0, list.count - 1 do
    local r = list:get(i) or ""
    sizes[#r] = (sizes[#r] or 0) + 1
    if #r >= 4 then pads[r:byte(4)] = (pads[r:byte(4)] or 0) + 1 end
  end
  ok(sizes[Gen4PropAnim.RECORD_BYTES] == list.count,
     "%s of %d records are %d bytes",
     tostring(sizes[Gen4PropAnim.RECORD_BYTES]), list.count,
     Gen4PropAnim.RECORD_BYTES)
  ok(pads[0] == list.count,
     "the byte at 0x03 is zero in %s of %d records; the id array starts after "
     .. "it, and a non-zero there would mean it is a field rather than padding",
     tostring(pads[0]), list.count)

  -- THE COMPARISON. Both offsets, scored by how many ids land in the target.
  local score = {}
  for _, base in ipairs({ 3, 4 }) do
    local inRange, none, out, props = 0, 0, 0, 0
    for i = 0, list.count - 1 do
      local r = list:get(i) or ""
      if #r >= base + 16 and r:byte(1) == Gen4PropAnim.HAS then
        props = props + 1
        for k = 0, 3 do
          local v = u32(r, base + 1 + k * 4)
          if v == Gen4PropAnim.NONE then none = none + 1
          elseif v and v < anim.count then inRange = inRange + 1
          else out = out + 1 end
        end
      end
    end
    score[base] = { inRange = inRange, none = none, out = out, props = props }
  end
  ok(score[4].out == 0,
     "reading animeArchiveIDs at 0x04 puts %d id(s) outside the %d-member "
     .. "archive; it should put none", score[4].out, anim.count)
  ok(score[3].out > 0,
     "reading at the documented 0x03 puts %d ids out of range -- if that is "
     .. "now zero, the archive or the decoder has changed and the correction "
     .. "recorded in Gen4PropAnim needs re-deriving, not keeping",
     score[3].out)
  -- AND THE MARGIN, so "0x04 is at least as good" cannot pass for a derivation
  ok(score[4].inRange > score[3].inRange,
     "0x04 resolves %d ids and 0x03 resolves %d; the correction is only worth "
     .. "anything if it resolves MORE", score[4].inRange, score[3].inRange)
  ok(score[4].props == 112,
     "%d props carry animations, not 112", score[4].props)
  report("ids at 0x04: %d resolved, %d empty, 0 out of range, across %d props "
         .. "(at 0x03: %d out of range)",
         score[4].inRange, score[4].none, score[4].props, score[3].out)
end

-- ---------------------------------------------------------------------------
section("3. the twenty doors, every row re-derived")
-- ---------------------------------------------------------------------------
if not (list and anim) then
  skip("no cartridge, so the door rows are not re-derived this run")
else
  -- THE NAMES COME FROM `Gen4Doors.MODELS`, which pass 178 derived from
  -- `doorModelIDs[]`. Asserting the two tables agree on membership first, so a
  -- row added to one and not the other is caught rather than silently skipped.
  local inDoors = {}
  for _, n in ipairs(Gen4Doors.MODELS) do inDoors[n] = true end
  local missing = {}
  for _, row in ipairs(Gen4PropAnim.DOORS) do
    if not inDoors[row.name] then missing[#missing + 1] = row.name end
  end
  ok(#missing == 0,
     "%d animation row(s) name a model Gen4Doors.MODELS does not: %s",
     #missing, table.concat(missing, ", "))
  ok(#Gen4PropAnim.DOORS == #Gen4Doors.MODELS,
     "%d animation rows against %d door models",
     #Gen4PropAnim.DOORS, #Gen4Doors.MODELS)

  local counts, byKind = {}, {}
  for _, row in ipairs(Gen4PropAnim.DOORS) do
    local member = A.find(MODEL_PATH, row.name .. ".nsbmd")
    ok(member == row.member,
     "`%s` is build_model member %s and the row says %s",
     row.name, tostring(member), tostring(row.member))
    if member then
      local entry = Gen4PropAnim.parse(list:get(member))
      ok(entry ~= nil and entry.has,
         "`%s` has no animations according to the cartridge; all twenty doors "
         .. "do", row.name)
      if entry and entry.has then
        local same = #entry.ids == #row.ids
        if same then
          for k = 1, #row.ids do
            if entry.ids[k] ~= row.ids[k] then same = false end
          end
        end
        ok(same, "`%s` resolves to [%s] and the row says [%s]", row.name,
           table.concat(entry.ids, " "), table.concat(row.ids, " "))
        ok(Gen4PropAnim.VALID_COUNTS[entry.count] == true,
           "`%s` has %d animations; pokeplatinum handles 2 and 4 and asserts "
           .. "on anything else", row.name, entry.count)
        ok(Gen4PropAnim.deferredLoad(entry),
           "`%s` is not flagged for deferred loading (flags 0x%02X); the doc "
           .. "names doors as the bit-0 case", row.name, entry.flags or 0)
        ok(entry.slope == false,
           "`%s` is flagged as a bicycle slope", row.name)
        counts[entry.count] = (counts[entry.count] or 0) + 1
        -- the KIND of each animation it names
        for _, id in ipairs(entry.ids) do
          local m = anim:get(id) or ""
          local magic = (#m >= 4) and m:sub(1, 4) or "?"
          byKind[magic] = (byKind[magic] or 0) + 1
          ok(magic == "BCA0" or magic == "BTP0" or magic == "BTA0"
             or magic == "BMA0" or magic == "BVA0",
             "`%s` animation %d is %q, which is not an animation magic this "
             .. "port knows", row.name, id, magic)
        end
      end
    end
  end
  ok(counts[4] == 11 and counts[2] == 9,
     "the split is %s doors with four animations and %s with two; it is 11 "
     .. "and 9", tostring(counts[4]), tostring(counts[2]))
  report("door animation kinds: %s", (function()
    local t = {}
    for k, v in pairs(byKind) do t[#t + 1] = ("%s x%d"):format(k, v) end
    table.sort(t); return table.concat(t, ", ")
  end)())
end

-- ---------------------------------------------------------------------------
section("4. count and sound are independent axes")
-- ---------------------------------------------------------------------------
-- This is the assertion that stops someone "simplifying" one table into the
-- other. `DoorAnimation_GetSoundEffectType` switches on the MODEL and
-- `animationCount` comes from a different archive entirely.
do
  ok(Gen4Doors.soundType("mansion_door") == "hinged",
     "`mansion_door` is %q; `DoorAnimation_GetSoundEffectType` lists only the "
     .. "Veilstone chime and six sliding doors, so this one is hinged",
     tostring(Gen4Doors.soundType("mansion_door")))
  ok(Gen4PropAnim.countFor("mansion_door") == 2,
     "`mansion_door` has %s animations; it is hinged and has two, which is "
     .. "why the count cannot be derived from the sound type",
     tostring(Gen4PropAnim.countFor("mansion_door")))
  ok(Gen4PropAnim.countFor("pokecenter_inside_counter_door") == 2,
     "`pokecenter_inside_counter_door` has %s animations; the second hinged "
     .. "door with two", tostring(Gen4PropAnim.countFor("pokecenter_inside_counter_door")))
  ok(Gen4PropAnim.countFor("door01") == 4,
     "`door01` has %s animations; an ordinary hinged door has four",
     tostring(Gen4PropAnim.countFor("door01")))
  -- ...AND THE SHARED PAIR, which is the sharpest form of it: the hinged
  -- mansion door and the chiming department store play the SAME two
  -- animations and different sounds.
  local m = Gen4PropAnim.doorRow("mansion_door")
  local v = Gen4PropAnim.doorRow("veilstone_dpt_store_door")
  ok(m and v and #m.ids == #v.ids and m.ids[1] == v.ids[1]
     and m.ids[2] == v.ids[2],
     "`mansion_door` and `veilstone_dpt_store_door` no longer share an "
     .. "animation pair; they did, and that is what proves the two axes are "
     .. "independent")
  ok(Gen4Doors.soundType("veilstone_dpt_store_door") == "chime"
     and Gen4Doors.soundType("mansion_door") == "hinged",
     "the two doors that share a pair no longer differ in sound type, so the "
     .. "example above proves nothing")
  -- the sliding doors all have two, which is the half that DOES line up
  local slidingCounts = {}
  for name in pairs(Gen4Doors.SLIDING) do
    slidingCounts[Gen4PropAnim.countFor(name) or 0] = true
  end
  local kinds = 0
  for _ in pairs(slidingCounts) do kinds = kinds + 1 end
  ok(kinds == 1 and slidingCounts[2],
     "the six sliding doors do not all have two animations")
end

-- ---------------------------------------------------------------------------
section("5. the texture-pattern door, which could move today")
-- ---------------------------------------------------------------------------
if not anim then
  skip("no cartridge, so the animation magics are not re-derived")
else
  local row = Gen4PropAnim.doorRow("elevator_door")
  ok(row ~= nil, "no row for elevator_door")
  if row then
    for _, id in ipairs(row.ids) do
      local m = anim:get(id) or ""
      ok(m:sub(1, 4) == "BTP0",
         "elevator_door animation %d is %q, not BTP0 -- the claim that one of "
         .. "the twenty is a texture flipbook rests on this", id,
         m:sub(1, 4))
    end
  end
  ok(Gen4Doors.animatesByTexture("elevator_door") == true,
     "the port does not report elevator_door as texture-animated")
  ok(Gen4Doors.animatesByTexture("door01") == false,
     "the port reports door01 as texture-animated; it is BCA0")
  -- AND EVERY OTHER DOOR IS BCA0, asserted as the complement so a second
  -- BTP0 door appearing is caught rather than averaged away.
  local bca = 0
  for _, r in ipairs(Gen4PropAnim.DOORS) do
    if r.name ~= "elevator_door" then
      local allB = true
      for _, id in ipairs(r.ids) do
        local m = anim:get(id) or ""
        if m:sub(1, 4) ~= "BCA0" then allB = false end
      end
      if allB then bca = bca + 1 end
    end
  end
  ok(bca == 19,
     "%d of the other nineteen doors are entirely BCA0; if a second one is a "
     .. "flipbook, TEXTURE_PATTERN_DOORS needs it", bca)
end

-- ---------------------------------------------------------------------------
section("6. the lookup the script path will use")
-- ---------------------------------------------------------------------------
do
  ok(Gen4Doors.animationFor("door01", "open") == 7,
     "door01's open animation is %s, not 7 (index 0 of [7 8 9 10])",
     tostring(Gen4Doors.animationFor("door01", "open")))
  ok(Gen4Doors.animationFor("door01", "close") == 8,
     "door01's close animation is %s, not 8 (index 1)",
     tostring(Gen4Doors.animationFor("door01", "close")))
  ok(Gen4Doors.animationFor("pokecenter_door", "open") == 5
     and Gen4Doors.animationFor("pokecenter_door", "close") == 6,
     "a two-animation door's open/close are %s/%s, not 5/6 -- the index rule "
     .. "is the same for two and for four",
     tostring(Gen4Doors.animationFor("pokecenter_door", "open")),
     tostring(Gen4Doors.animationFor("pokecenter_door", "close")))
  ok(Gen4Doors.animationFor("door01", "load") == nil
     and Gen4Doors.animationFor("door01", "unload") == nil,
     "load/unload resolved to an animation; only open and close name one")
  ok(Gen4Doors.animationFor("not_a_door", "open") == nil,
     "an unknown model resolved to an animation")
  -- THE FOUR-ANIMATION DOORS' indices 2 and 3 are loaded and never played by
  -- the door path, which is easy to mistake for a bug and "fix".
  local row = Gen4PropAnim.doorRow("door01")
  ok(row and #row.ids == 4 and row.ids[3] == 9 and row.ids[4] == 10,
     "door01's third and fourth animations are no longer 9 and 10; they are "
     .. "loaded by the cartridge and played by neither open nor close")
end

-- ---------------------------------------------------------------------------
section("7. the extractor's pairing, and what it costs")
-- ---------------------------------------------------------------------------
--
-- Pass 184. The extractor used to decide "can anything wear this joint
-- animation?" by looking for a model in the SAME archive with that many
-- nodes. `bm_anime` has no models, so all 98 of its animations came out
-- `unworn` -- right by that rule and wrong about the cartridge.
--
-- It now asks the claim table for an archive that declares `claims = true`.
-- This section rebuilds that table the same way and asserts the outcome,
-- because the extractor's own output needs a 10 MB cache regeneration to
-- inspect and this does not.
if not (list and anim) then
  skip("no cartridge, so the extractor pairing is not re-derived this run")
else
  local Anim = require("src.import.Gen4Anim")

  -- THE EXTRACTOR'S OWN TABLE, not a rebuild of it.
  --
  -- The first draft of this section built the claim map here, with the same
  -- ten lines the extractor uses. A planted fault that emptied the
  -- extractor's loop then changed nothing: 275 checks green while the real
  -- builder returned an empty table. That is shape 6a of
  -- claude/check_design_lessons.md -- setup that mirrors the subject grades
  -- the mirror -- so this asks the subject.
  --
  -- `propAnimationClaims` needs only `archiveAt` and `Gen4PropAnim`, so a
  -- real extractor can be constructed for the cartridge and asked.
  local Extractor = require("src.import.RomExtractorGen4")
  local ex = Extractor.new(ROM, "platinum", nil, nil)
  ok(ex ~= nil, "could not construct the extractor over %s", tostring(ROM))
  local claims = ex and ex:propAnimationClaims()
  ok(type(claims) == "table",
     "propAnimationClaims answered %s; everything below reads it",
     type(claims))
  claims = claims or {}
  local distinct = 0
  for _ in pairs(claims) do distinct = distinct + 1 end
  -- NOTHING IS ORPHANED, which is the strongest statement the join can make:
  -- every member of the animation archive is claimed by some prop. If this
  -- ever drops, some animation has no owner and the pairing is incomplete.
  ok(distinct == anim.count,
     "%d of %d bm_anime members are claimed by a prop; every one should be, "
     .. "and a member nobody claims is an animation the join cannot place",
     distinct, anim.count)

  local kinds, wornBCA, unwornBCA, joints, frames, longest = {}, 0, 0, 0, 0, 0
  local packed, verifyFailed = 0, 0
  for member = 0, anim.count - 1 do
    local bytes = anim:get(member)
    local parsed = bytes and Anim.parse(bytes)
    if parsed then
      kinds[parsed.kind] = (kinds[parsed.kind] or 0) + 1
      if parsed.kind == "BCA0" then
        for _, a in ipairs(parsed.animations or {}) do
          if claims[member] then
            wornBCA = wornBCA + 1
            local tracks = Anim.jointMatrices(bytes, a) or {}
            ok(#tracks > 0,
               "bm_anime member %d is claimed and decodes to no joint tracks",
               member)
            for _, j in ipairs(tracks) do
              joints = joints + 1
              frames = frames + (j.frames or 0)
              if (j.frames or 0) > longest then longest = j.frames end
              local blob = Anim.packTrack(j.track)
              packed = packed + #blob
              if not Anim.verifyTrack(j.track, blob) then
                verifyFailed = verifyFailed + 1
              end
            end
          else
            unwornBCA = unwornBCA + 1
          end
        end
      end
    end
  end
  ok(kinds.BCA0 == 32 and kinds.BTA0 == 43 and kinds.BTP0 == 23,
     "bm_anime holds %s BCA0 / %s BTA0 / %s BTP0; it is 32 / 43 / 23",
     tostring(kinds.BCA0), tostring(kinds.BTA0), tostring(kinds.BTP0))
  ok(unwornBCA == 0,
     "%d joint animation(s) are still unworn; the whole point of the claim "
     .. "table is that none of them is", unwornBCA)
  ok(wornBCA == 32, "%d joint animations are worn, not 32", wornBCA)
  ok(verifyFailed == 0,
     "%d packed track(s) failed `verifyTrack`; a pose that does not round-trip "
     .. "is worse than no pose", verifyFailed)
  ok(joints == 90, "the worn animations carry %d joints, not 90", joints)

  -- THE COST, PINNED, because it is a deliberate 2.2 MB of cache and the next
  -- person weighing cache size should find a number rather than a shrug. A
  -- floor as well as a ceiling: if this collapses, the tracks have stopped
  -- being written.
  ok(packed > 500 * 1024,
     "the packed matrices come to %d bytes; they were 613.7 KB, and a sudden "
     .. "collapse means the decode has stopped producing frames", packed)
  ok(packed < 900 * 1024,
     "the packed matrices come to %d bytes, well above the 613.7 KB measured; "
     .. "something is being written twice", packed)
  report("worn: %d BCA0, %d joints, %d joint-frames (longest %d), %.1f KB "
         .. "packed -- a deliberate cache cost",
         wornBCA, joints, frames, longest, packed / 1024)

  -- AND THE EXTRACTOR REALLY ASKS. The assertions above rebuild the table;
  -- these two read the extractor's source, because a claim table that is
  -- correct and unused would pass everything above.
  local src = code(slurp("src/import/RomExtractorGen4.lua")
                     or slurp("../src/import/RomExtractorGen4.lua"))
  ok(src ~= "", "could not read RomExtractorGen4.lua")
  -- THE CALL, not the name. `function RomExtractorGen4:propAnimationClaims()`
  -- contains the bare name, so a `find` on it matches the DEFINITION and a
  -- planted fault that deleted the only call passed. Anchored on the `self:`
  -- form, which only a call can be.
  ok(src:find("self:propAnimationClaims%s*%(") ~= nil,
     "nothing in the extractor CALLS propAnimationClaims -- the definition "
     .. "existing is not the pairing being computed")
  ok(src:find('claims%s*=%s*true') ~= nil,
     "no archive declares `claims = true`, so the claim route is never taken")
  -- the bm_anime entry specifically, not just any entry
  local bm = src:match('path%s*=%s*"/arc/bm_anime%.narc".-}')
  ok(bm ~= nil, "could not find the bm_anime archive entry")
  ok(bm and bm:find("claims%s*=%s*true") ~= nil,
     "the bm_anime entry does not declare `claims = true`; another archive "
     .. "declaring it would satisfy the assertion above while leaving the 98 "
     .. "animations unworn")
  -- ...and the wearability test must consult it
  ok(src:find("wearable%[item%.anim%.nodes%]%s*or%s*claimedBy") ~= nil,
     "the wearability test no longer reads the claim, so node count is "
     .. "deciding again")
  -- RECORDED ON EVERY ANIMATION, not only the joint ones. `pending` holds
  -- BCA0 alone, so writing `props` inside that loop left the 43 BTA0 and 23
  -- BTP0 claims unrecorded -- `elevator_door` among them, the one door that
  -- could move through the texture path.
  --
  -- Found by a plant that did NOT fail: dropping the `tracks` requirement from
  -- the renderer's one-shot set changed nothing, because every record with
  -- `props` also had `tracks` -- true only because `props` was written nowhere
  -- else.
  ok(src:find("record%.props%s*=%s*owners") ~= nil,
     "the claiming prop models are not recorded on every animation, which is "
     .. "the join a renderer needs and the node count never gave")
  ok(src:find("for _, record in ipairs%(set%.animations%) do") ~= nil,
     "the claim loop does not walk the whole animation set, so only the joint "
     .. "animations carry their owners")
end

-- ---------------------------------------------------------------------------
section("8. the one-shot runner, and the wait that was unreachable")
-- ---------------------------------------------------------------------------
--
-- Pass 185. Two faults, and the second hid the first: `g4_wait_animation` was
-- `noop`, and there were TWO `L.waitforanimation` lowerings -- an early one
-- onto `g4_wait_animation` and a later one onto `g4_noop` that, being later in
-- the same table, silently overwrote it. So the handler was unreachable and
-- the census filed all 48 sites under "the door animation's wait".
do
  local OneShot = require("src.world.Gen4PropOneShot")

  -- FRAME COUNTS, derived. Two regularities, either of which breaking means
  -- the ids have moved.
  for _, row in ipairs(Gen4PropAnim.DOORS) do
    local open = Gen4PropAnim.animationFor(row.name, "open")
    local close = Gen4PropAnim.animationFor(row.name, "close")
    local fo, fc = Gen4PropAnim.framesFor(open), Gen4PropAnim.framesFor(close)
    ok(fo ~= nil and fc ~= nil,
       "`%s` has no frame count for open/close (%s/%s)", row.name,
       tostring(fo), tostring(fc))
    ok(fo == fc,
       "`%s` opens in %s frames and closes in %s; every door's two are equal",
       row.name, tostring(fo), tostring(fc))
    ok(fo and fo >= 6 and fo <= 15,
       "`%s` animates in %s frames; they run 6 to 15", row.name, tostring(fo))
  end
  -- the four-animation doors' unplayed pair is a DIFFERENT animation, which is
  -- the second reason not to treat indices 2 and 3 as spares
  local four = Gen4PropAnim.doorRow("door01")
  ok(four and #four.ids == 4
     and Gen4PropAnim.framesFor(four.ids[1]) ~= Gen4PropAnim.framesFor(four.ids[3]),
     "door01's played pair and its unplayed pair are the same length, so the "
     .. "claim that indices 2 and 3 are a different animation no longer holds")

  if ROM and anim then
    -- ...and re-derived from the cartridge, so the table is not a number
    -- somebody typed
    local Anim = require("src.import.Gen4Anim")
    local wrong = {}
    for id, frames in pairs(Gen4PropAnim.FRAMES) do
      local b = anim:get(id)
      local p = b and Anim.parse(b)
      local got = p and p.animations and p.animations[1]
                    and p.animations[1].frames
      if got ~= frames then
        wrong[#wrong + 1] = ("%d: table %d, cartridge %s")
                              :format(id, frames, tostring(got))
      end
    end
    table.sort(wrong)
    ok(#wrong == 0, "%d frame count(s) disagree with the cartridge: %s",
       #wrong, table.concat(wrong, "; "))
  end

  -- THE RUNNER. A fake overworld, because the runner touches nothing else.
  local ow = {}
  local prop = { model = 66 }
  ok(OneShot.start(ow, 3, "door01", "open", prop) == true,
     "starting a door01 open on tag 3 was refused")
  local slot = OneShot.running(ow, 3)
  ok(slot ~= nil and slot.animation == 7 and slot.frames == 8,
     "tag 3 is running animation %s for %s frames, not 7 for 8",
     slot and tostring(slot.animation), slot and tostring(slot.frames))
  ok(OneShot.finished(ow, 3) == false,
     "a freshly started one-shot reports finished")
  OneShot.advance(ow, 4)
  ok(OneShot.finished(ow, 3) == false,
     "half way through, the one-shot reports finished")
  OneShot.advance(ow, 4)
  ok(OneShot.finished(ow, 3) == true,
     "after its full %s frames the one-shot is still running",
     slot and tostring(slot.frames))
  -- IT HOLDS ITS LAST FRAME. Clearing on completion would snap the door shut
  -- the instant it finished opening; `unloadanimation` is what releases it.
  -- NO BARE INDEXING. `OneShot.running(...).frame` raises rather than fails
  -- when a plant clears the slot, and an assertion that can raise reports
  -- nothing: two planted faults in `advance` landed silently that way, and one
  -- of them took the whole run down before the summary printed.
  local held = OneShot.running(ow, 3)
  ok(held ~= nil,
     "the finished one-shot cleared itself; the last frame is the pose the "
     .. "door holds until unloadanimation")
  ok(held and held.frame == 8,
     "the finished one-shot sits at frame %s, not 8",
     tostring(held and held.frame))
  -- Advancing an ALREADY finished one-shot must do nothing, which is a
  -- different assertion from clamping.
  OneShot.advance(ow, 100)
  local after = OneShot.running(ow, 3)
  ok(after ~= nil,
     "advancing past the end released the tag; only unloadanimation may")
  ok(after and after.frame == 8,
     "advancing an already-finished one-shot moved it to %s",
     tostring(after and after.frame))

  -- THE OVERSHOOT IN ONE STEP, which is the only path that reaches the clamp.
  --
  -- Stepping 0 -> 4 -> 8 never executes it (`8 > 8` is false), and advancing a
  -- slot that is already at its end is skipped by the guard above -- so two
  -- planted faults in the clamp passed every assertion here until this case
  -- existed. A branch no test reaches is not a tested branch.
  local fresh = {}
  OneShot.start(fresh, 1, "door01", "open", { model = 66 })
  OneShot.advance(fresh, 100)
  local jumped = OneShot.running(fresh, 1)
  ok(jumped ~= nil,
     "one 100-frame step released an 8-frame one-shot instead of clamping it")
  ok(jumped and jumped.frame == 8,
     "one 100-frame step left the frame at %s; an 8-frame animation clamps "
     .. "to 8, and an unclamped frame would index past the end of the track",
     tostring(jumped and jumped.frame))
  ok(OneShot.finished(fresh, 1) == true,
     "after a single overshooting step the one-shot reports unfinished")
  OneShot.stop(ow, 3)
  ok(OneShot.running(ow, 3) == nil, "stop did not release the tag")

  -- AN UNRESOLVABLE DOOR MUST NOT HANG THE SCRIPT. This is the contract the
  -- old no-op had by accident, and the one thing a real wait could get
  -- catastrophically wrong.
  -- A SLOT MUST ALWAYS CARRY ITS LENGTH. Asserted here rather than left to
  -- the `finished` calls below, because a slot with no length made those
  -- compare a number with nil and the run DIED instead of failing -- and a
  -- crash is a worse diagnostic than a FAIL.
  ok(slot and slot.frames and slot.frames > 0,
     "a running one-shot has no frame count, so nothing can tell when it ends")
  ok(OneShot.start(ow, 4, nil, "open", prop) == false,
     "a tag with no model started a one-shot")
  ok(OneShot.finished(ow, 4) == true,
     "a tag that never started reports UNfinished -- a `waitforanimation` on "
     .. "it would hold the script for ever")
  ok(OneShot.start(ow, 5, "not_a_door", "open", prop) == false,
     "an unknown model started a one-shot")
  ok(OneShot.finished(ow, 5) == true, "an unknown model's tag never finishes")
  ok(OneShot.finished(ow, 99) == true,
     "a tag nothing ever touched reports UNfinished")

  -- THE LENGTHLESS SLOT, FORCED. `start` refuses to make one, so the guards in
  -- `finished` and `advance` that tolerate it are unreachable from any normal
  -- path -- cold, not dead, and the difference has to be proved. Reached here
  -- by breaking a live slot on purpose, which is what a damaged `start` would
  -- do: without these guards a nil comparison raises inside the overworld's
  -- update, and the fault is reported nowhere near where it happened.
  do
    local broken = {}
    OneShot.start(broken, 1, "door01", "open", { model = 66 })
    local victim = OneShot.all(broken)[1]
    ok(victim ~= nil, "could not reach the slot to break it")
    if victim then
      victim.frames = nil
      -- Through pcall, because the fault being tested is a nil comparison:
      -- calling it bare makes the plant kill the run instead of failing it,
      -- and "the check died" is a worse diagnostic than "the check says no".
      local okFin, fin = pcall(OneShot.finished, broken, 1)
      ok(okFin,
         "asking whether a slot with no length is finished RAISED; a wait "
         .. "would take the script down rather than step over")
      ok(okFin and fin == true,
         "a slot with no length reports %s, so a wait on it would hold the "
         .. "script for ever", tostring(okFin and fin))
      local okAdvance = pcall(OneShot.advance, broken, 1)
      ok(okAdvance,
         "advancing a slot with no length raised; the overworld's update runs "
         .. "this every frame")
    end
  end

  -- TAGS ARE INDEPENDENT: a script opens two doors and waits on one.
  local a, b = { model = 66 }, { model = 70 }
  OneShot.start(ow, 1, "door01", "open", a)
  OneShot.start(ow, 2, "pokecenter_door", "open", b)
  OneShot.advance(ow, 8)
  ok(OneShot.finished(ow, 1) == true and OneShot.finished(ow, 2) == false,
     "tag 1 (8 frames) and tag 2 (15 frames) finished together, so the two "
     .. "are sharing a clock")
  -- and the pose lookup finds the right prop by identity
  local pa = OneShot.poseIn(OneShot.all(ow), a)
  local pb = OneShot.poseIn(OneShot.all(ow), b)
  ok(pa ~= nil and pb ~= nil, "the pose lookup found no slot for a live prop")
  ok(pa and pb and pa.tag == 1 and pb.tag == 2,
     "the pose lookup confused two props (%s / %s)",
     tostring(pa and pa.tag), tostring(pb and pb.tag))
  ok(OneShot.poseIn(OneShot.all(ow), { model = 66 }) == nil,
     "the pose lookup matched a DIFFERENT table with the same contents; it "
     .. "must match on identity, because two copies of one door model are two "
     .. "props")
  ok(OneShot.poseIn(nil, a) == nil and OneShot.poseIn(OneShot.all(ow), nil) == nil,
     "the pose lookup did not survive a nil")
end

-- ---------------------------------------------------------------------------
section("9. the wiring, which is where this would be cold")
-- ---------------------------------------------------------------------------
do
  local Commands = require("src.script.Commands")
  require("src.script.Gen4Commands")
  ok(type(Commands.g4_wait_animation) == "function",
     "g4_wait_animation is %s; it was `noop`",
     type(Commands.g4_wait_animation))

  local vm = code(slurp("src/script/Gen4ScriptVM.lua")
                    or slurp("../src/script/Gen4ScriptVM.lua"))
  ok(vm ~= "", "could not read Gen4ScriptVM.lua")
  -- EXACTLY ONE LOWERING. Two assignments to one key in one table is the
  -- fault this section exists for, and the later one wins silently.
  local assignments = 0
  for _ in vm:gmatch("\nL%.waitforanimation%s*=") do
    assignments = assignments + 1
  end
  ok(assignments == 1,
     "`waitforanimation` has %d lowering(s); two assignments to one key in one "
     .. "table means the later one wins and the earlier is unreachable",
     assignments)
  local body = vm:match("\nL%.waitforanimation%s*=%s*function.-\nend")
  ok(body ~= nil, "could not read the waitforanimation lowering")
  if body then
    ok(body:find("g4_wait_animation", 1, true) ~= nil,
       "`waitforanimation` does not lower onto g4_wait_animation")
    ok(body:find("g4_noop") == nil,
       "`waitforanimation` is still on g4_noop")
    -- THE TAG. The opcode is `b` -- one byte, the tag -- and the old lowering
    -- threw it away, so even the reachable spelling would have waited on the
    -- wrong thing.
    local order = {}
    for n in body:gmatch("ins%.args%[(%d)%]") do order[#order + 1] = n end
    ok(table.concat(order, ",") == "1",
       "`waitforanimation` forwards operands [%s]; it has one, the tag, and "
       .. "`ScrCmd_WaitForAnimation` reads it with ScriptContext_ReadByte",
       table.concat(order, ","))
  end

  -- THE RENDERER'S POSE IS REACHED. `oneShotPose` reading a field nothing
  -- sets would be cold by construction -- it would answer nil for ever and
  -- nothing would say so -- which is exactly what `self.overworld` did in the
  -- first draft of this pass.
  local ground = code(slurp("src/render/Gen4Ground.lua")
                        or slurp("../src/render/Gen4Ground.lua"))
  ok(ground ~= "", "could not read Gen4Ground.lua")
  ok(ground:find("function Gen4Ground:oneShotPose") ~= nil,
     "Gen4Ground has no oneShotPose")
  ok(ground:find("self%.oneShots") ~= nil,
     "oneShotPose does not read self.oneShots")
  ok(ground:find("self%.overworld") == nil,
     "Gen4Ground reads self.overworld, which it is never given -- the pose "
     .. "would be cold by construction")
  local poses = 0
  for _ in ground:gmatch("self:oneShotPose%(object, building%)") do
    poses = poses + 1
  end
  ok(poses == 2,
     "%d LIVE prop draw(s) ask for a pose; both of them must", poses)
  -- AND THE ANIMATED BAKE, which pass 187 added. It iterates `moving` and so
  -- names `item.object`, not `object` -- a different spelling, which is why it
  -- is counted separately rather than folded into the number above.
  local bakedPose = 0
  for _ in ground:gmatch("self:oneShotPose%(item%.object, building%)") do
    bakedPose = bakedPose + 1
  end
  ok(bakedPose == 1,
     "%d animated-bake draw(s) ask for a pose; the one that draws the moving "
     .. "props must, or a door selected into that pass is drawn at rest and "
     .. "never moves in the 2D view", bakedPose)
  ok(ground:find("animsByMember") ~= nil,
     "Gen4Ground has no animsByMember, so a one-shot's animation cannot be "
     .. "found in the cache")

  -- AND THE CONTROLLER HANDS IT OVER, which is the other half of not being
  -- cold.
  local ow = code(slurp("src/world/OverworldController.lua")
                    or slurp("../src/world/OverworldController.lua"))
  ok(ow ~= "", "could not read OverworldController.lua")
  ok(ow:find("OneShot%.advance%(self") ~= nil,
     "nothing advances the one-shots, so a door would freeze on frame 0 and a "
     .. "wait on it would never end")
  ok(ow:find("ground%.oneShots%s*=%s*OneShot%.all") ~= nil,
     "the controller does not hand the slot table to the renderer, so "
     .. "oneShotPose reads nil for ever")
  ok(ow:find("Gen4PropOneShot") ~= nil, "OverworldController never requires the runner")

  -- AND THE DOOR COMMANDS START AND RELEASE IT.
  local cmds = code(slurp("src/script/Gen4Commands.lua")
                      or slurp("../src/script/Gen4Commands.lua"))
  ok(cmds:find("Gen4PropOneShot\"%)%.start") ~= nil,
     "g4_door_anim never starts a one-shot")
  ok(cmds:find("Gen4PropOneShot\"%)%.stop") ~= nil,
     "unloadanimation never releases the one-shot, so a tag reused for another "
     .. "door would hold the first one's pose")
  ok(cmds:find("ow%.gen4DoorProps") ~= nil,
     "the door's prop object is not remembered, so the pose cannot find it")
end

-- ---------------------------------------------------------------------------
section("10. two namespaces for one door")
-- ---------------------------------------------------------------------------
--
-- Pass 186. pokeplatinum's `doorModelIDs[]` names the FILE
-- (`brown_wooden_door`); the cache names the MODEL INSIDE it (`t1_door1`).
-- They disagree for nineteen of the twenty, and nothing had joined them.
--
-- `door01` agreeing is the dangerous part: a reader who spot-checked one door
-- would have concluded the two namespaces were the same.
do
  ok(#Gen4PropAnim.DOORS == 20, "expected twenty door rows")
  local missing, agree = {}, 0
  for _, row in ipairs(Gen4PropAnim.DOORS) do
    if not row.modelName then missing[#missing + 1] = row.name end
    if row.modelName == row.name then agree = agree + 1 end
  end
  ok(#missing == 0, "%d row(s) carry no internal model name: %s",
     #missing, table.concat(missing, ", "))
  -- EXACTLY ONE AGREES. Asserted as a number, because "most differ" is the
  -- fact and "one is the same" is the trap.
  ok(agree == 1,
     "%d door file name(s) equal their internal model name; exactly one does "
     .. "(door01), and that coincidence is why the split went unnoticed", agree)
  ok(Gen4PropAnim.internalName("brown_wooden_door") == "t1_door1",
     "brown_wooden_door's internal name is %s, not t1_door1",
     tostring(Gen4PropAnim.internalName("brown_wooden_door")))
  ok(Gen4PropAnim.fileNameOf("t1_door1") == "brown_wooden_door",
     "t1_door1 does not map back to brown_wooden_door")
  ok(Gen4PropAnim.internalName("not_a_door") == nil
     and Gen4PropAnim.fileNameOf("not_a_model") == nil,
     "an unknown name resolved to something")
  -- THE NEAR-MISS PAIR, which is the one a typo would swap silently.
  ok(Gen4PropAnim.internalName("gym_door") == "gym_door00"
     and Gen4PropAnim.internalName("hearthome_gym_inside_door") == "gym_door01",
     "gym_door and hearthome_gym_inside_door map to %s and %s; they are "
     .. "gym_door00 and gym_door01, and swapping them picks the wrong door "
     .. "with no symptom",
     tostring(Gen4PropAnim.internalName("gym_door")),
     tostring(Gen4PropAnim.internalName("hearthome_gym_inside_door")))
  -- every internal name distinct, or the reverse map is ambiguous
  local seen, dupes = {}, {}
  for _, row in ipairs(Gen4PropAnim.DOORS) do
    if row.modelName then
      if seen[row.modelName] then dupes[#dupes + 1] = row.modelName end
      seen[row.modelName] = true
    end
  end
  ok(#dupes == 0,
     "%d internal name(s) appear twice, so fileNameOf is ambiguous: %s",
     #dupes, table.concat(dupes, ", "))
end

-- RE-DERIVED FROM THE CACHE, which is the only place the internal names live.
if not CACHE then
  skip("no cache, so the internal model names are not re-derived this run")
else
  local models = loadTable(CACHE, "gen4_models")
  local bs = models and models.sets and models.sets.buildings
  ok(bs ~= nil, "the cache has no buildings set")
  if bs then
    ok(#(bs.models or {}) == 590,
       "the buildings set holds %d models, not 590", #(bs.models or {}))
    -- POSITION IS MEMBER for this archive, which the extractor states and the
    -- static bake relies on. Asserted rather than trusted, because every
    -- lookup below and every prop draw depends on it.
    local offBy = 0
    for member, at in pairs(bs.byMember or {}) do
      if at ~= member + 1 then offBy = offBy + 1 end
    end
    ok(offBy == 0,
       "%d of the buildings' byMember entries are not member + 1; the bake "
       .. "reads models[index + 1] directly, so that must hold", offBy)
    local wrong = {}
    for _, row in ipairs(Gen4PropAnim.DOORS) do
      local entry = bs.models[row.member + 1]
      if not (entry and entry.name == row.modelName) then
        wrong[#wrong + 1] = ("%s: member %d holds %s, row says %s")
          :format(row.name, row.member, tostring(entry and entry.name),
                  tostring(row.modelName))
      end
    end
    table.sort(wrong)
    ok(#wrong == 0, "%d door row(s) disagree with the cache: %s",
       #wrong, table.concat(wrong, "; "))
    -- AND THE FILE NAMES DO *NOT* RESOLVE IN THE CACHE, which is the fault
    -- this section exists to pin: a lookup by file name finds nothing for
    -- nineteen of them, and finds the right thing for door01.
    local byCacheName = {}
    for _, m in ipairs(bs.models or {}) do
      if m.name then byCacheName[m.name] = true end
    end
    local resolvable = 0
    for _, row in ipairs(Gen4PropAnim.DOORS) do
      if byCacheName[row.name] then resolvable = resolvable + 1 end
    end
    ok(resolvable == 1,
       "%d door FILE name(s) resolve against the cache's model names; one "
       .. "does, and anything that looks a door up in the cache by its "
       .. "pokeplatinum name is wrong about the other nineteen", resolvable)
    report("internal names re-derived for 20/20 doors; %d of 20 file names "
           .. "resolve in the cache", resolvable)
  end
end

-- ---------------------------------------------------------------------------
section("11. the two prop selections must be complements")
-- ---------------------------------------------------------------------------
--
-- The static bake draws every object `animationsFor` answers nil for; the
-- animated bake draws every object it answers records for. So every prop must
-- land in exactly one: NEITHER means the prop vanishes, BOTH means it is drawn
-- twice.
--
-- Pass 186 found these two asking different questions -- the bake guard passed
-- `object.archive` and the animated selection did not -- so for a `fldeff`
-- prop they consulted different models. Harmless only because zero fldeff
-- props are placed in terrain chunks.
do
  local ground = code(slurp("src/render/Gen4Ground.lua")
                        or slurp("../src/render/Gen4Ground.lua"))
  ok(ground ~= "", "could not read Gen4Ground.lua")
  -- BOTH PREDICATES, counted together.
  --
  -- This assertion pinned `animationsFor(object.model, object.archive)` at
  -- four, and pass 187 replaced the static bake's guard with
  -- `movesAtRuntime(...)` -- so it failed on a correct tree, which is shape 2
  -- of claude/check_design_lessons.md: a pin on the past. The fact worth
  -- holding is not how many calls wear one spelling, it is that NO
  -- per-object call omits the archive.
  local bare = 0
  for _ in ground:gmatch("animationsFor%(object%.model%)") do bare = bare + 1 end
  for _ in ground:gmatch("movesAtRuntime%(object%.model%)") do bare = bare + 1 end
  for _ in ground:gmatch("building%(item%.object%.model%)") do bare = bare + 1 end
  ok(bare == 0,
     "%d per-object call(s) omit the archive; the two selections must consult "
     .. "the same table or they stop being complements", bare)
  -- THE TWO PASSES MUST CALL THE NAMED DECISIONS, not inline a predicate of
  -- their own -- that is what makes the complement assertion in section 12
  -- able to grade them at all.
  ok(ground:find("if self:shouldBake%(object%) then") ~= nil,
     "the static bake's guard does not call shouldBake, so section 12 is "
     .. "grading a decision the renderer does not make")
  ok(ground:find("if self:shouldAnimate%(object%) then") ~= nil,
     "the animated bake's selection does not call shouldAnimate")
  ok(ground:find("function Gen4Ground:shouldBake%(object%)%s*\n%s*return not self:shouldAnimate%(object%)") ~= nil,
     "shouldBake is not defined as the negation of shouldAnimate; two "
     .. "separate tests is how the two passes stop being complements")

  -- AND THE PROPERTY ITSELF, against the cache. A prop is baked when
  -- `animationsFor` is nil and animated when it is not, so the two sets
  -- partition the placed props by construction -- but only while both ask the
  -- same question, which is what the source assertions above hold.
  if CACHE then
    local terrain = loadTable(CACHE, "gen4_terrain")
    local fldeff = 0
    for _, chunk in pairs((terrain or {}).chunks or {}) do
      for _, o in ipairs(chunk.objects or {}) do
        if o.archive == "fldeff" then fldeff = fldeff + 1 end
      end
    end
    -- Reported rather than asserted at zero: a future pass that places
    -- signposts as terrain props SHOULD see this number move, and a check
    -- that forbade it would be a pin on today.
    report("fldeff props placed in terrain chunks: %d (the archive mismatch "
           .. "above could only ever have mattered for these)", fldeff)
  end
end

-- ---------------------------------------------------------------------------
section("12. the bake split, against the regenerated cache")
-- ---------------------------------------------------------------------------
--
-- Pass 187, after the re-import. The static bake draws every prop
-- `movesAtRuntime` says no to; the animated bake draws every prop it says yes
-- to. EVERY PLACED PROP MUST LAND IN EXACTLY ONE: neither means the prop
-- vanishes, both means it is drawn twice.
--
-- `movesAtRuntime` is graded here, not a copy of it. A rebuilt predicate would
-- pass while the real one was broken -- which is exactly what happened in
-- pass 184's section 7 before it was made to call the extractor.
if not CACHE then
  skip("no cache, so the bake split is not graded this run")
else
  local models  = loadTable(CACHE, "gen4_models")
  local terrain = loadTable(CACHE, "gen4_terrain")
  ok(models ~= nil and terrain ~= nil,
     "the cache has no gen4_models / gen4_terrain")
  if models and terrain then
    local Gen4Ground = require("src.render.Gen4Ground")
    -- A REAL INSTANCE, with only the fields these two methods read. Built by
    -- hand because `forMap` wants LOVE; the methods under test are pure.
    local ground = setmetatable({}, Gen4Ground)
    ground.buildingSet = models.sets and models.sets.buildings
    ground.animsByName, ground.animsByMember = {}, {}
    local field = models.sets and models.sets.field
    for _, record in ipairs((field or {}).animations or {}) do
      if record.name then
        local list = ground.animsByName[record.name]
        if not list then list = {}; ground.animsByName[record.name] = list end
        list[#list + 1] = record
      end
      if record.member and ground.animsByMember[record.member] == nil then
        ground.animsByMember[record.member] = record
      end
    end
    ok(type(ground.buildingSet) == "table", "no buildings set in the cache")
    ok(type(ground.movesAtRuntime) == "function"
       and type(ground.oneShotProps) == "function",
       "Gen4Ground has no movesAtRuntime/oneShotProps, so nothing below grades "
       .. "the real predicate")

    -- THE CACHE CARRIES WHAT PASS 184 PROMISED. A floor, because every
    -- assertion after this is vacuous over an empty set.
    local tracked, claimed = 0, 0
    for _, record in pairs(ground.animsByMember) do
      if record.tracks then tracked = tracked + 1 end
      if record.props then claimed = claimed + 1 end
    end
    ok(tracked == 32,
       "%d animation(s) in the cache carry joint tracks, not 32 -- has the "
       .. "cache been regenerated since the extractor learned the pairing?",
       tracked)
    -- THE CLAIM COUNT IS NOT A NUMBER, IT IS ONE OF TWO STATES.
    --
    -- This read `claimed == 32` and failed on a correct tree the moment
    -- Cedric re-imported -- shape 2d of claude/check_design_lessons.md, an
    -- assertion whose subject was a to-do item, demanding the work NOT be
    -- done. 32 is the count of BCA0 records, and pass 187 made the extractor
    -- record the claim on every animation rather than only inside the loop
    -- over `pending`.
    --
    -- All 98 members of `bm_anime` are claimed on the cartridge (section 7),
    -- so a cache is legitimately in one of exactly two states and a third is
    -- a claim table that has stopped resolving for part of the archive:
    --
    --   current      every record carries it            -- 98 of 98
    --   pre-pass-187 exactly the joint records carry it  -- 32 of 98
    --
    -- Stated as the relation each state rests on rather than as the two
    -- numbers, so neither can go stale: `claimed == total` and
    -- `claimed == tracked`. `tools/gen4_prop_claim_check.lua` section 9 holds
    -- the same invariant from the other side and names which state it found.
    local total = 0
    for _ in pairs(ground.animsByMember) do total = total + 1 end
    ok(total >= 98,
       "the cache's field animation index holds %d record(s), not the 98 the "
       .. "archive has -- every assertion below would measure a fraction of "
       .. "it", total)
    ok(claimed == total or claimed == tracked,
       "%d of %d animation(s) carry their claiming prop models, and %d carry "
       .. "joint tracks. A current cache claims ALL of them and a cache "
       .. "imported before pass 187 claims exactly the joint ones; anything "
       .. "between means the claim map has stopped resolving for part of the "
       .. "archive", claimed, total, tracked)
    if claimed == total then
      report("the cache claims all %d animations (post-pass-187 import)", total)
    else
      report("the cache claims %d of %d animations -- the joint records only, "
             .. "so it predates pass 187's extractor fix", claimed, total)
    end
    local propSet = ground:oneShotProps()
    local propCount = 0
    for _ in pairs(propSet) do propCount = propCount + 1 end
    ok(propCount == 46,
       "%d prop models support script-driven motion, expected 46 including "
       .. "PC/healing display texture animations", propCount)

    -- EVERY DOOR IS IN THE SET, by index.
    local absent = {}
    for _, row in ipairs(Gen4PropAnim.DOORS) do
      -- Both joint and texture one-shots require a live prop.
      if not propSet[row.member] then
        absent[#absent + 1] = ("%s (member %d)"):format(row.name, row.member)
      end
    end
    ok(#absent == 0,
       "%d door(s) cannot run a one-shot: %s", #absent,
       table.concat(absent, ", "))
    ok(propSet[75] == true,
       "elevator_door (member 75) must remain live for its script-driven BTP0")
    for _,model in ipairs({112,115,119,124,248,517}) do
      ok(propSet[model]==true,"PC/healing display model %d must remain live",model)
      ok(ground:animationsFor(model)==nil,"PC/healing display model %d must not loop at idle",model)
    end

    -- THE COMPLEMENT, over every placed prop in every chunk.
    local placed, baked, animated, both, neither = 0, 0, 0, 0, 0
    local neitherEg = {}
    for _, chunk in pairs(terrain.chunks or {}) do
      for _, object in ipairs(chunk.objects or {}) do
        placed = placed + 1
        -- ASKED, NOT MODELLED. `shouldBake` and `shouldAnimate` are the
        -- methods the two passes actually call, so a change to either
        -- predicate shows up here. Recomputing them -- which this section did
        -- at first -- made a reverted static guard invisible: every door would
        -- have been drawn twice with 427 checks green.
        local inStatic = ground:shouldBake(object)
        local inAnimated = ground:shouldAnimate(object)
        if inStatic and inAnimated then both = both + 1 end
        if not inStatic and not inAnimated then
          neither = neither + 1
          if #neitherEg < 4 then
            neitherEg[#neitherEg + 1] = ("model %s archive %s")
              :format(tostring(object.model), tostring(object.archive))
          end
        end
        if inStatic then baked = baked + 1 end
        if inAnimated then animated = animated + 1 end
      end
    end
    ok(placed > 1000,
       "only %d prop(s) are placed across the cache; the complement below "
       .. "would be vacuous over a small set", placed)
    -- THESE TWO CANNOT FAIL WHILE `shouldBake` IS `not shouldAnimate`, and
    -- saying so is the point: a measurement that cannot fail says nothing.
    -- They are kept as cheap cover for the day somebody writes the two
    -- decisions as two tests instead of one negation -- and the assertion
    -- that actually protects the complement is the source one in section 11,
    -- which requires that definition. A plant that made `shouldAnimate`
    -- answer false for everything left both of these green, which is how
    -- their real strength was measured.
    ok(neither == 0,
     "%d placed prop(s) are in NEITHER selection -- they would not be drawn "
     .. "at all: %s", neither, table.concat(neitherEg, "; "))
    ok(both == 0,
       "%d placed prop(s) are in BOTH selections -- they would be drawn twice, "
       .. "which shows as a brighter or double-shadowed object", both)
    ok(baked + animated == placed,
       "%d baked + %d animated = %d, which is not the %d placed props",
       baked, animated, baked + animated, placed)
    report("%d placed props: %d baked, %d animated, 0 in both, 0 in neither",
           placed, baked, animated)

    -- AND THE SPLIT ACTUALLY MOVED SOMETHING. A `movesAtRuntime` that always
    -- answered false would satisfy every complement assertion above while
    -- baking every door flat.
    local jointOnly = 0
    for _, chunk in pairs(terrain.chunks or {}) do
      for _, object in ipairs(chunk.objects or {}) do
        if ground:movesAtRuntime(object.model, object.archive)
           and not ground:animationsFor(object.model, object.archive) then
          jointOnly = jointOnly + 1
        end
      end
    end
    -- The live set includes script-owned texture displays as well as joints.
    -- Current ROM/cache census: 290 placements, seven also ambient-animated.
    -- Both numbers are asserted, because quoting one where the other belongs
    -- is how this assertion failed on a correct tree the first time.
    ok(jointOnly == 283,
       "%d placed props require a script-driven live pass; expected 283, and zero "
       .. "would mean the split answers false everywhere and every door is "
       .. "still baked flat", jointOnly)
    local jointCapable = 0
    for _, chunk in pairs(terrain.chunks or {}) do
      for _, object in ipairs(chunk.objects or {}) do
        if object.archive ~= "fldeff" and propSet[object.model] then
          jointCapable = jointCapable + 1
        end
      end
    end
    ok(jointCapable == 290,
       "%d placements support script-driven motion, expected 290", jointCapable)
    report("%d script-driven placements, %d of them live for that reason "
           .. "alone (the other 7 are texture-animated too)",
           jointCapable, jointOnly)
  end
end

-- ---------------------------------------------------------------------------
section("13. the tracks the pose will actually read")
-- ---------------------------------------------------------------------------
if not CACHE then
  skip("no cache, so the joint tracks are not inspected this run")
else
  local models = loadTable(CACHE, "gen4_models")
  local Anim = require("src.import.Gen4Anim")
  local byMember = {}
  for _, r in ipairs((((models or {}).sets or {}).field or {}).animations or {}) do
    if r.member and byMember[r.member] == nil then byMember[r.member] = r end
  end
  -- EVERY DOOR ANIMATION THAT SHOULD HAVE TRACKS HAS THEM, and the one that
  -- should not, does not.
  local noTracks, haveTracks = {}, 0
  for _, row in ipairs(Gen4PropAnim.DOORS) do
    for _, id in ipairs(row.ids) do
      local rec = byMember[id]
      local want = not Gen4PropAnim.isTexturePattern(row.name)
      local got = rec ~= nil and rec.tracks ~= nil and #rec.tracks > 0
      if want and not got then
        noTracks[#noTracks + 1] = ("%s:%d"):format(row.name, id)
      elseif want and got then haveTracks = haveTracks + 1 end
      if not want then
        ok(not got,
           "%s's animation %d has joint tracks; it is BTP0 and should have "
           .. "none", row.name, id)
      end
    end
  end
  ok(#noTracks == 0, "%d door animation(s) have no usable tracks: %s",
     #noTracks, table.concat(noTracks, " "))
  ok(haveTracks == 60,
     "%d door animation members carry joint tracks, not 60 (62 ids less "
     .. "elevator_door's two BTP0s)", haveTracks)

  -- THE DOOR ACTUALLY SWINGS. Frame 0 must be the rest pose and the last
  -- frame must differ from it -- a track of identical frames would pose a door
  -- that never visibly moves, and every assertion above would still pass.
  local rec = byMember[7]
  ok(rec ~= nil and rec.tracks and rec.tracks[1] ~= nil,
     "the hinged doors' animation 7 has no first joint track")
  if rec and rec.tracks and rec.tracks[1] then
    local track = rec.tracks[1]
    local first = Anim.unpackFrame(track.matrices, 0)
    local last = Anim.unpackFrame(track.matrices, (track.frames or 1) - 1)
    ok(first ~= nil and last ~= nil,
       "animation 7's first or last frame did not unpack")
    if first and last then
      local moved = false
      for i = 1, 16 do
        if math.abs(first[i] - last[i]) > 1e-4 then moved = true end
      end
      ok(moved,
         "animation 7's first and last frames are identical, so a door posed "
         .. "from it would never visibly move")
      -- frame 0 is the identity: a closed door sits where the static bake drew it
      local identity = true
      for i, want in ipairs({ 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 }) do
        if math.abs(first[i] - want) > 1e-4 then identity = false end
      end
      ok(identity,
         "animation 7's frame 0 is not the identity matrix, so a door at rest "
         .. "would not sit where it does today")
    end
    ok(rec.props ~= nil and #rec.props == 11,
       "animation 7 is claimed by %s prop(s), not the eleven ordinary hinged "
       .. "doors", rec.props and tostring(#rec.props))
  end
end

-- ---------------------------------------------------------------------------
section("14. how a door moves, and the joint that moves it")
-- ---------------------------------------------------------------------------
--
-- Pass 188. Section 13 inspected `tracks[1]` of animation 7 and concluded the
-- doors move. Four of the twelve door animations carry THREE joints with joint
-- 1 static at both ends -- the motion is in a later joint -- so that spot
-- check said nothing about them. A sample of one is not a measurement.
if not CACHE then
  skip("no cache, so the door motions are not inspected this run")
else
  local models = loadTable(CACHE, "gen4_models")
  local Anim = require("src.import.Gen4Anim")
  local byMember = {}
  for _, r in ipairs((((models or {}).sets or {}).field or {}).animations or {}) do
    if r.member and byMember[r.member] == nil then byMember[r.member] = r end
  end

  local function framesOf(rec)
    local out = {}
    for _, track in ipairs(rec.tracks or {}) do
      local n = track.frames or 0
      out[#out + 1] = {
        index = track.index,
        first = Anim.unpackFrame(track.matrices, 0),
        last = Anim.unpackFrame(track.matrices, n - 1),
        frames = n,
      }
    end
    return out
  end
  local function differs(a, b)
    if not (a and b) then return false end
    for i = 1, 16 do
      if math.abs(a[i] - b[i]) > 1e-4 then return true end
    end
    return false
  end
  -- kept for the single-joint assertion below, where the identity really is
  -- the rest pose
  local function identity(m)
    if not m then return false end
    local want = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 }
    for i = 1, 16 do
      if math.abs(m[i] - want[i]) > 1e-4 then return false end
    end
    return true
  end

  -- EVERY DOOR ANIMATION MOVES SOMETHING, whichever joint it is.
  -- DEDUPED. The first version pushed both tables into one list, so an id in
  -- BOTH counted twice and the "twelve" assertion passed over eleven distinct
  -- ids -- a planted fault that moved 5 into the rotate table went unnoticed.
  local seenId, ids = {}, {}
  for id in pairs(Gen4PropAnim.ROTATE_DOORS) do seenId[id] = true end
  for id in pairs(Gen4PropAnim.SCALE_DOORS) do
    ok(not Gen4PropAnim.ROTATE_DOORS[id],
       "animation %d is listed as both rotating and scaling; a door does one "
       .. "or the other", id)
    seenId[id] = true
  end
  for id in pairs(seenId) do ids[#ids + 1] = id end
  table.sort(ids)
  ok(#ids == 12, "expected twelve distinct joint door animations, found %d",
     #ids)
  local multiJoint = 0
  for _, id in ipairs(ids) do
    local rec = byMember[id]
    ok(rec ~= nil and rec.tracks ~= nil, "animation %d has no tracks", id)
    if rec and rec.tracks then
      local tracks = framesOf(rec)
      if #tracks > 1 then multiJoint = multiJoint + 1 end
      local moved, movedIndex = false, nil
      for _, t in ipairs(tracks) do
        if differs(t.first, t.last) then moved = true; movedIndex = t.index end
      end
      ok(moved,
         "animation %d has %d joint(s) and NONE of them differs between its "
         .. "first and last frame -- a door posed from it would never visibly "
         .. "move", id, #tracks)
      -- THE REST POSE MUST BE WHERE THE STATIC BAKE DRAWS IT, which is the
      -- assertion that stops a door POPPING the moment it joins the animated
      -- pass. The first version of this demanded the IDENTITY and failed on
      -- animation 29 -- wrongly: a multi-joint door's rest frame carries the
      -- model's own node translations (d3_door1's panels sit at -10 and +10),
      -- so the identity is only right for the single-joint doors.
      --
      -- The real property is that an open animation's frame 0 equals the REST
      -- MATRIX of each model that claims it. Checked below against the models
      -- themselves, with one enumerated exception.
      local isOpen = (id % 2 == 1)
      if isOpen and models.sets and models.sets.buildings then
        local bs = models.sets.buildings
        for _, member in ipairs(rec.props or {}) do
          local m = bs.models[member + 1]
          local matches = true
          for _, t in ipairs(tracks) do
            local node = m and m.nodes and m.nodes[(t.index or 0) + 1]
            if not (node and not differs(t.first, node.matrix)) then
              matches = false
            end
          end
          -- `c5_door_s` IS THE ONE EXCEPTION, and it is a cartridge quirk
          -- rather than a port fault.
          --
          -- Animation 29 is claimed by d3_door1 (mansion, panels at +/-10)
          -- AND c5_door_s (Veilstone department store, panels at +/-12), and
          -- its frame 0 carries -10/+10 as real constant translation channels
          -- -- `isSet(flags, 1)` would mark translation ABSENT and it is not
          -- set. So the hardware writes those values to the joint, and opening
          -- the Veilstone door moves its panels two units inward.
          --
          -- Applying the animation verbatim is therefore the ROM's behaviour,
          -- and preserving the model's own translation instead would be the
          -- divergence. Pinned as an exception so it cannot be "fixed" into a
          -- difference.
          local excepted = (m and m.name == "c5_door_s")
          if excepted then
            ok(not matches,
               "c5_door_s now agrees with animation 29's rest frame; the "
               .. "exception below it is no longer needed and the comment "
               .. "explaining the two-unit shift is wrong")
          else
            ok(matches,
               "animation %d's frame 0 does not match model %s's own node "
               .. "matrices, so that door would jump the instant it joined "
               .. "the animated pass", id, tostring(m and m.name))
          end
        end
      end
      if movedIndex then
        report("animation %2d: %d joint(s), %d frames, motion in joint %s",
               id, #tracks, tracks[1] and tracks[1].frames or 0,
               tostring(movedIndex))
      end
    end
  end
  -- THE SINGLE-JOINT DOORS' rest frame IS the identity, which is the half of
  -- the old assertion that was right.
  for _, id in ipairs({ 5, 7, 9, 33 }) do
    local rec = byMember[id]
    local tracks = rec and rec.tracks and framesOf(rec)
    if tracks and #tracks == 1 then
      ok(identity(tracks[1].first),
         "animation %d has one joint and its frame 0 is not the identity", id)
    end
  end

  ok(multiJoint == 4,
     "%d door animation(s) carry more than one joint; four do (27, 28, 29, 30) "
     .. "and they are the ones a tracks[1] spot check cannot see", multiJoint)

  -- OPEN AND CLOSE ARE MIRRORS. This is the data confirming pret's index rule:
  -- open's last frame is close's first, and open's first is close's last.
  for _, pair in ipairs({ {5,6}, {7,8}, {9,10}, {27,28}, {29,30}, {33,34} }) do
    local a, b = byMember[pair[1]], byMember[pair[2]]
    ok(a ~= nil and b ~= nil, "animation %d or %d is missing", pair[1], pair[2])
    if a and b and a.tracks and b.tracks then
      local ta, tb = framesOf(a), framesOf(b)
      ok(#ta == #tb,
         "animations %d and %d carry %d and %d joints; an open/close pair "
         .. "drives the same joints", pair[1], pair[2], #ta, #tb)
      if #ta == #tb then
        local mirrored = true
        for i = 1, #ta do
          if differs(ta[i].last, tb[i].first) then mirrored = false end
          if differs(ta[i].first, tb[i].last) then mirrored = false end
        end
        ok(mirrored,
           "animations %d and %d are not mirrors: open's last frame must be "
           .. "close's first and open's first must be close's last, which is "
           .. "what makes index 0 open and index 1 close rather than the "
           .. "other way round", pair[1], pair[2])
      end
    end
  end

  -- THE TWO MOTIONS ARE DIFFERENT, and the sliding one is a SCALE.
  do
    local rec = byMember[7]
    local tracks = rec and rec.tracks and framesOf(rec)
    local last = tracks and tracks[1] and tracks[1].last
    ok(last ~= nil, "animation 7's last frame did not unpack")
    if last then
      -- a 90-degree turn about Y: the X axis has become -Z
      ok(math.abs(last[1]) < 1e-3 and math.abs(last[3] + 1) < 1e-3
         and math.abs(last[9] - 1) < 1e-3,
         "animation 7's last frame is not a quarter turn about Y; the hinged "
         .. "doors swing, and this is the matrix that makes them")
    end
    local pc = byMember[5]
    local pcTracks = pc and pc.tracks and framesOf(pc)
    local pcLast = pcTracks and pcTracks[1] and pcTracks[1].last
    ok(pcLast ~= nil, "animation 5's last frame did not unpack")
    if pcLast then
      -- an X scale to about a fifth, with no rotation at all
      ok(math.abs(pcLast[1] - 0.20) < 0.02,
         "animation 5 scales X to %.3f, not about 0.20 -- the Pokemon Centre "
         .. "door SLIDES, and it does it by squashing rather than turning",
         pcLast[1])
      ok(math.abs(pcLast[3]) < 1e-3 and math.abs(pcLast[9]) < 1e-3,
         "animation 5's last frame has a rotation in it; the sliding doors do "
         .. "not turn, and six of the twenty doors are this kind")
    end
  end
end

-- ---------------------------------------------------------------------------
section("15. the pose arithmetic, executed")
-- ---------------------------------------------------------------------------
--
-- Pass 188. `oneShotPose` needs a built model and therefore LOVE, so the check
-- had only read its source -- and planted faults inside it (writing every
-- track to joint 0, dropping the frame clamp) changed nothing. The arithmetic
-- is `jointMatricesAt` now, which needs neither, and this runs it.
if not CACHE then
  skip("no cache, so the pose arithmetic is not executed this run")
else
  local models = loadTable(CACHE, "gen4_models")
  local Gen4Ground = require("src.render.Gen4Ground")
  local Anim = require("src.import.Gen4Anim")
  local ground = setmetatable({}, Gen4Ground)
  ground.animsByMember = {}
  for _, r in ipairs((((models or {}).sets or {}).field or {}).animations or {}) do
    if r.member and ground.animsByMember[r.member] == nil then
      ground.animsByMember[r.member] = r
    end
  end
  ok(type(ground.jointMatricesAt) == "function",
     "Gen4Ground has no jointMatricesAt, so the pose arithmetic is ungraded "
     .. "again")

  -- A MULTI-JOINT DOOR, which is the case a single-joint spot check misses.
  -- Animation 29 drives three joints and the motion is in joint 2.
  local three = ground:jointMatricesAt({ animation = 29, frame = 0 })
  ok(type(three) == "table", "animation 29 produced no joint matrices")
  if type(three) == "table" then
    local n = 0
    for _ in pairs(three) do n = n + 1 end
    ok(n == 3,
       "animation 29 posed %d joint(s), not 3 -- a pose that writes every "
       .. "track to one index leaves two joints at rest and the door half "
       .. "moves", n)
    ok(three[0] ~= nil and three[1] ~= nil and three[2] ~= nil,
       "animation 29's joints are not keyed 0, 1 and 2")
    -- joint 1 sits at -10 on X and joint 2 at +10: the mansion door's panels
    ok(three[1] and math.abs(three[1][4] + 10) < 1e-3,
       "animation 29's joint 1 is at x=%s, not -10",
       tostring(three[1] and three[1][4]))
    ok(three[2] and math.abs(three[2][4] - 10) < 1e-3,
       "animation 29's joint 2 is at x=%s, not +10",
       tostring(three[2] and three[2][4]))
  end

  -- THE FRAME MOVES THE POSE. Frame 0 and the last frame must differ, or the
  -- frame argument is being ignored.
  do
    local first = ground:jointMatricesAt({ animation = 7, frame = 0 })
    local last = ground:jointMatricesAt({ animation = 7, frame = 7 })
    ok(first and last and first[0] and last[0],
       "animation 7 did not pose joint 0 at both ends")
    if first and last and first[0] and last[0] then
      local moved = false
      for i = 1, 16 do
        if math.abs(first[0][i] - last[0][i]) > 1e-4 then moved = true end
      end
      ok(moved,
         "animation 7's frame 0 and frame 7 pose the same matrix, so the "
         .. "frame is being ignored and a door would never move")
    end
  end

  -- THE CLAMP, which is the one that matters for a HELD-OPEN door.
  --
  -- `advance` stops a finished one-shot with `frame == frames`, and a track
  -- has `frames` entries indexed from zero -- so the last readable index is
  -- `frames - 1`. Asking for `frame` itself runs one past the end of every
  -- door that is standing open.
  do
    local atEnd = ground:jointMatricesAt({ animation = 7, frame = 7 })
    local atFrames = ground:jointMatricesAt({ animation = 7, frame = 8 })
    local wayPast = ground:jointMatricesAt({ animation = 7, frame = 9999 })
    ok(atEnd and atFrames and wayPast,
       "one of the clamped frames produced no pose")
    if atEnd and atFrames and wayPast then
      local function same(a, b)
        if not (a and b) then return false end
        for i = 1, 16 do if math.abs(a[i] - b[i]) > 1e-4 then return false end end
        return true
      end
      ok(same(atEnd[0], atFrames[0]),
         "frame 8 of an 8-frame animation does not pose the same matrix as "
         .. "frame 7; `advance` leaves a finished one-shot at frame == frames, "
         .. "so this is the pose every held-open door uses")
      ok(same(atEnd[0], wayPast[0]),
         "frame 9999 does not clamp to the last frame")
    end
  end
  -- a negative frame clamps to zero rather than indexing backwards
  do
    local back = ground:jointMatricesAt({ animation = 7, frame = -5 })
    local zero = ground:jointMatricesAt({ animation = 7, frame = 0 })
    ok(back and zero and back[0] and zero[0], "a negative frame posed nothing")
    if back and zero and back[0] and zero[0] then
      local same = true
      for i = 1, 16 do
        if math.abs(back[0][i] - zero[0][i]) > 1e-4 then same = false end
      end
      ok(same, "a negative frame does not clamp to frame 0")
    end
  end
  -- AND THE REST-POSE GUARANTEE, executed: an animation with no tracks in the
  -- cache poses nothing, so the prop draws at rest rather than collapsing.
  ok(ground:jointMatricesAt({ animation = 51, frame = 0 }) == nil,
     "animation 51 produced joint matrices; it is BTP0 and carries none, and "
     .. "nil is what makes the draw fall back to the rest pose")
  ok(ground:jointMatricesAt({ animation = 9999, frame = 0 }) == nil,
     "an unknown animation produced joint matrices")
  ok(ground:jointMatricesAt(nil) == nil, "a nil slot produced joint matrices")
end

io.write(("\n%d checks, %d failed, %d reported, %d skipped\n")
           :format(checks, fails, reports, skips))
os.exit(fails == 0 and 0 or 1)
