-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S BUILDING ANIMATIONS, out of the building packs' records.
--
-- A pack (/a/2/2/9 outdoors, /a/2/3/0 indoors; src/import/Gen5Field.lua) is
-- an "AB" table whose first half are records and second half the models, in
-- the same order. Gen5Field kept each record's id and dropped the rest; the
-- rest is the building's animations. READ FROM CODE (ov21, Black):
--
--   +0  u16 id            the record id a placement names
--   +2  u16 kind          -> the SCRIPT's model id through the 16-byte table
--                            at 0x021D3DC4 (0x0218BCB0): kinds 1/2/3/13/14/15
--                            are model 1 (doors, the badge gates' bars), 11
--                            is 8, 10 is 7 ... -- this is the "model id" of
--                            0x127 / 0x12B / 0x12D / 0x12E. The same kind keys
--                            the open / close SE table at 0x021D3D88
--                            (0x0218C944).
--   +4  u16 door          the record of the door this building stands
--                         beside it (0xFFFF none), at
--   +6  s16 x, +8 s16 y, +10 s16 z  its offset in world units, NOT turned
--                         with the building -- the loader (0x0218B974 ->
--                         0x0218B930) places the door at (x + dx, y + dy,
--                         -z + dz) with the building's own rotation. A
--                         Pokemon Center (record 0) has door 0x5D at
--                         (0, 0, 15): the doors are not placements of their
--                         own, which is why 0x127 found nothing at one
--   +16 u8  type          the animation controller (table 0x021D3D58,
--                         12 bytes a row: init, per-frame, command):
--                           0 none   1 every attached animation loops
--                           2 script-driven (0x0218C3E0, see the runtime)
--                           3 one set by the time of day, looping
--   +18 u8  perSet        animations played together as one "set"
--   +19 u8  sets          how many sets (a door: 2 -- open, close)
--   +20 u32[4]            each animation file's offset from +16
--                         (0xFFFFFFFF none); every file holds ONE animation
--
-- Measured over both archives' 4,364 records (Black): 3,356 have no
-- animation, 534 loop (type 1), 442 are script-driven (349 of them model 1:
-- 340 doors of two BCA0s, open and close, and the 9 badge gates' bars, kind
-- 3, one 54-frame BCA0), 32 follow the time of day; every file is BCA0,
-- BTA0, BTP0 or BMA0 with one animation in it.
--
-- WHAT THIS WRITES, on the pack's set (the shape Gen4Ground already reads
-- for Platinum / HGSS's prop animations, plus `bw`):
--   set.animations  records { member, kind, frames, props = { id }, ... }
--                   member = id * 8 + the animation's index in the record
--   set.scripted    the type-2 members (never on the frame clock)
--   set.claimsOnly  true: a record animates only the model it belongs to
--   set.bw[id]      { type, kind, model, perSet, sets, members = { [k] },
--                     door = { id, x, y, z } }
--   models[id+1].patternImages  the flipbook frames a BTP0 names, out of the
--                   pack's texture set

local Gen5BuildingAnim = {}

-- 0x021D3DC4: record kind -> the scripts' model id (READ FROM CODE)
Gen5BuildingAnim.MODEL_OF_KIND = { [0] = 0, 1, 1, 1, 2, 0, 3, 4, 5, 6, 7, 8, 9, 1, 1, 1 }
-- 0x021D3D88: { kind, SE per slot 0..3 } (READ FROM CODE, six rows)
Gen5BuildingAnim.SOUNDS = {
  [1] = { 1669, 1670 }, [2] = { 1671, 1671 }, [5] = { 1671, 1671 },
  [13] = { 1910, 1910 }, [14] = { 1914, 1915 }, [15] = { 1671, 1671 },
}
Gen5BuildingAnim.MEMBERS_PER_RECORD = 8

local function u16(s, o) local a, b = s:byte(o + 1, o + 2) return (a or 0) + (b or 0) * 256 end
local function u32(s, o)
  local a, b, c, d = s:byte(o + 1, o + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

function Gen5BuildingAnim.modelOf(kind)
  if type(kind) ~= "number" or kind >= 16 or kind < 0 then return 0 end
  return Gen5BuildingAnim.MODEL_OF_KIND[kind] or 0
end

-- record(seg) -> { id, kind, model, type, perSet, sets, files = { bytes } }
function Gen5BuildingAnim.record(seg)
  if type(seg) ~= "string" or #seg < 36 then return nil end
  local out = { id = u16(seg, 0), kind = u16(seg, 2), door = u16(seg, 4),
                type = seg:byte(17), perSet = seg:byte(19), sets = seg:byte(20), files = {} }
  out.model = Gen5BuildingAnim.modelOf(out.kind)
  if out.door == 0xFFFF then out.door = nil end
  local function s16(o) local v = u16(seg, o) return v >= 32768 and v - 65536 or v end
  if out.door then out.door = { id = out.door, x = s16(6), y = s16(8), z = s16(10) } end
  for f = 0, 3 do
    local off = u32(seg, 20 + f * 4)
    if off and off ~= 0xFFFFFFFF and 16 + off + 16 <= #seg then
      local at = 16 + off
      local size = u32(seg, at + 8)
      if size and size > 16 and at + size <= #seg then
        out.files[f + 1] = seg:sub(at + 1, at + size)
      end
    end
  end
  return out
end

-- The animation records of one building record, in file order.
local function recordsOf(rec, Anim)
  local list = {}
  for f = 1, 4 do
    local bytes = rec.files[f]
    local parsed = bytes and Anim.parse(bytes)
    local a = parsed and parsed.animations and parsed.animations[1]
    if a then
      local r = { name = a.name, member = rec.id * Gen5BuildingAnim.MEMBERS_PER_RECORD + (f - 1),
                  kind = parsed.kind, frames = a.frames, props = { rec.id }, bwIndex = f - 1 }
      if parsed.kind == "BTA0" then r.srt = Anim.textureSrt(bytes, a)
      elseif parsed.kind == "BTP0" then r.pattern = Anim.texturePattern(bytes, a)
      elseif parsed.kind == "BMA0" then r.colour = Anim.materialColour(bytes, a)
      elseif parsed.kind == "BCA0" then
        -- the file, decoded at run time (Gen4PropClock.inflate), as HGSS's
        r.bca = bytes
        r.bcaIndex = 1
      else r = nil end
      if r then list[#list + 1] = r end
    end
  end
  return list
end

-- attach(set, packBytes, textures, texBytes, save, kind, p) -> records, scripted
function Gen5BuildingAnim.attach(set, packBytes, textures, texBytes, save, kind, p)
  if not (set and type(packBytes) == "string" and packBytes:sub(1, 2) == "AB") then return 0, 0 end
  local Anim = require("src.import.Gen4Anim")
  local Models = require("src.import.Gen4Models")
  local n = u16(packBytes, 2)
  set.animations, set.scripted, set.claimsOnly, set.bw = set.animations or {}, set.scripted or {}, true, set.bw or {}
  local count, scripted = 0, 0
  local written = {}
  for i = 0, n - 1 do
    local a, e = u32(packBytes, 4 + i * 4), u32(packBytes, 4 + (i + 1) * 4)
    if a and e and a < e and e <= #packBytes and packBytes:sub(a + 1, a + 4) ~= "BMD0" then
      local ok, rec = pcall(Gen5BuildingAnim.record, packBytes:sub(a + 1, e))
      -- a building with no animation still answers to its model id (the
      -- scripts' search takes the first match, animated or not)
      if ok and rec and (rec.model ~= 0 or rec.door) and not (rec.type and rec.type > 0 and next(rec.files)) then
        set.bw[rec.id] = { type = 0, kind = rec.kind, model = rec.model, members = {}, door = rec.door }
      end
      if ok and rec and rec.type and rec.type > 0 and next(rec.files) then
        local okR, list = pcall(recordsOf, rec, Anim)
        list = okR and list or {}
        local info = { type = rec.type, kind = rec.kind, model = rec.model, perSet = math.max(1, rec.perSet or 1), door = rec.door,
                       sets = rec.sets or 1, members = {} }
        for _, r in ipairs(list) do
          info.members[r.bwIndex] = r.member
          local keep = true
          if rec.type == 1 then
            -- 0x0218C040: only the first `perSet` are attached, each looping
            keep = r.bwIndex < info.perSet
            r.loop = true
          elseif rec.type == 3 then
            -- 0x0218C08C: the set for the time of day (0x021D3D50: periods
            -- 0..4 -> 0,1,2,3,3) is attached and loops
            r.loop = true
            r.timeOfDay = { [rec.id] = math.floor(r.bwIndex / info.perSet) }
          else
            r.bwScripted = true
            set.scripted[r.member] = true
            scripted = scripted + 1
          end
          if keep then
            set.animations[#set.animations + 1] = r
            count = count + 1
            -- the flipbook's frames, from the pack's texture set
            local packed = set.models[rec.id + 1]
            if r.pattern and packed and textures and texBytes and save then
              packed.patternImages = packed.patternImages or {}
              for k, name in ipairs(r.pattern.textures or {}) do
                if packed.patternImages[name] == nil then
                  local key = name .. "/" .. tostring((r.pattern.palettes or {})[k] or (r.pattern.palettes or {})[1])
                  if written[key] == nil then
                    local ti, pi
                    local pal = (r.pattern.palettes or {})[k] or (r.pattern.palettes or {})[1]
                    for x, t in ipairs(textures.textures or {}) do if t.name == name then ti = x end end
                    for x, pl in ipairs(textures.palettes or {}) do if pl.name == pal then pi = x end end
                    local image = ti and Models.decode(textures, texBytes, ti, pi or 1)
                    local saved = image and save.image(("models/bw_%s/%02d/anim_%s_%d"):format(kind, p,
                      name:gsub("[^%w_%-]", "_"), pi or 1), image, { texture = name, palette = pal })
                    written[key] = saved and saved.path or false
                  end
                  packed.patternImages[name] = written[key] or nil
                end
              end
            end
          end
        end
        set.bw[rec.id] = info
      end
    end
  end
  return count, scripted
end

return Gen5BuildingAnim
