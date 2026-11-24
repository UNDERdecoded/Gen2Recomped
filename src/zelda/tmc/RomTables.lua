-- Round 35: the game's small data tables, read from the player's own ROM.
--
-- Nothing in the repository holds the tables' values: RomTablesCat.lua lists
-- for each one only where it sits in the USA ROM (a bus address, usually the
-- decomp symbol) and how to read it (field widths, count, stride), plus a
-- Fletcher-32 checksum of its bytes so a wrong ROM / address fails loudly at
-- import.  Extract copies the bytes into r35.bin (manifest.r35); at runtime
-- Assets.new attaches the cache and every table handed out by RT.t is filled
-- in place.
--
--   local SPEEDS = require("src.zelda.tmc.RomTables").t("EnemyX.SPEEDS")
--
-- returns the same table object for the module's lifetime; it is empty until
-- a cache is attached (reading a key before that raises an error, so a table
-- used before the cache exists shows up at once instead of acting empty).
-- RT.fresh(name) returns a new deep copy (for a constructor that ran inside a
-- function and handed out a new table each call).
--
-- Spec strings (RomTablesCat): "u8" | "s8" | "b8" (u8 ~= 0) | "u16" | "s16" | "u32" | "s32"
-- | "ptr" for a list of numbers, or "{f1,f2,...}" for rows, a field being
-- [name ":"] type or "xN" (N bytes skipped); named fields give records.  n = count (nil with a "{...}"
-- spec = one record), base = first index (0 or 1, default 1), stride = bytes
-- per row (default the sum of the fields), step = key step (rows at base,
-- base + step, ...), rowbase = 0 for rows indexed from 0.  ptrs = true: the
-- address is a table of n pointers to lists of rows (term = the first
-- field's end marker, or "next"), range = { lo, hi } the bytes copied (the
-- lists and the pointer table), dropEmpty leaves empty lists out; group = k
-- puts the n rows in lists of k (indexed from gbase, default 1); as = "set" / "map" turns {key, value} lists into
-- {[key] = true} / {[key] = value} ("keys": the keys' list); one = true: each pointer is to one row.
--
-- Round 36:
--   packed bit-fields: "[u32|flag=0.12|ftype=12.4]" reads one u32 and gives
--     a column per "lo.width" bit range (named "name=lo.width" or positional);
--   term on a plain list: rows stop at the first whose first field == term
--     (n = the most rows read); `as` also applies to plain lists;
--   "ptr" fields / rows: a 4-byte pointer, decoded through `sub` = a nested
--     descriptor { spec, n, base = .., ... } at the address it points to
--     (two-level pointer tables: a sub whose spec is "ptr" with its own sub);
--     a pointer outside the copied bytes (NULL) gives nil;
--   far = true: the bytes are gathered by following the pointers at import
--     (lists anywhere in the ROM, no range): r35.bin keeps the touched bytes
--     as { address, length, bytes } segments and the decode reads by address;
--   lit = true (implies far): e[1] is a literal-pool word in the code that
--     references the table (the table's address is read from it).

local bit = require("bit")
local band = bit.band

local RT = {}

local W = { u8 = 1, s8 = 1, b8 = 1, u16 = 2, s16 = 2, u32 = 4, s32 = 4, ptr = 4 }
local BUS, BUS_END = 0x08000000, 0x0A000000

local specCache = {}
local function parseSpec(spec)
  local c = specCache[spec]
  if c then return c[1], c[2], c[3], c[4] end
  local fields, rec = {}, false
  local body = spec:match("^{(.*)}$")
  if not body then
    assert(W[spec], "RomTables: bad spec " .. spec)
    specCache[spec] = { { { name = nil, ty = spec, off = 0 } }, false, W[spec], false }
    return { { name = nil, ty = spec, off = 0 } }, false, W[spec]
  end
  local size = 0
  for part in body:gmatch("[^,]+") do
    local skip = part:match("^%s*x(%d+)%s*$") -- "xN": N bytes the port does not read
    if skip then
      size = size + tonumber(skip)
      goto continue
    end
    do
      local cty, bits = part:match("^%s*%[(%w+)|(.-)%]%s*$") -- packed bit-fields
      if cty then
        assert(W[cty] and cty ~= "ptr", "RomTables: bad bit-field container " .. part)
        for item in bits:gmatch("[^|]+") do
          local nm, lo, wd = item:match("^%s*([%w_]+)=(%d+)%.(%d+)%s*$")
          if not nm then lo, wd = item:match("^%s*(%d+)%.(%d+)%s*$") end
          assert(lo, "RomTables: bad bit range " .. item .. " in " .. spec)
          if nm then rec = true end
          fields[#fields + 1] = { name = nm, ty = cty, off = size, lo = tonumber(lo), wd = tonumber(wd) }
        end
        size = size + W[cty]
        goto continue
      end
    end
    do
      local name, ty = part:match("^%s*([%w_]+):([%w]+)%s*$")
      if not name then ty = part:match("^%s*([%w]+)%s*$") end
      assert(ty and W[ty], "RomTables: bad field " .. part .. " in " .. spec)
      if name then rec = true end
      fields[#fields + 1] = { name = name, ty = ty, off = size }
      size = size + W[ty]
    end
    ::continue::
  end
  specCache[spec] = { fields, rec, size, true }
  return fields, rec, size, true
end

local function rd(get, o, ty)
  local v
  if ty == "b8" then return get(o) ~= 0
  elseif ty == "u8" or ty == "s8" then
    v = get(o)
    if ty == "s8" and v >= 0x80 then v = v - 0x100 end
  elseif ty == "u16" or ty == "s16" then
    v = get(o) + get(o + 1) * 256
    if ty == "s16" and v >= 0x8000 then v = v - 0x10000 end
  else
    v = get(o) + get(o + 1) * 256 + get(o + 2) * 65536 + get(o + 3) * 16777216
    if ty == "s32" and v >= 0x80000000 then v = v - 0x100000000 end
  end
  return v
end

-- byte size of a catalogue entry (far entries: known only after gathering)
function RT.size(e)
  if e.range then return e.range[2] - e.range[1] end
  local _, _, rowSize = parseSpec(e[2])
  local n = e[3] or 1
  return (n - 1) * (e.stride or rowSize) + rowSize
end

local function isFar(e) return e.far or e.lit end

-- decodes descriptor d (an entry or a `sub`) whose data starts at offset
-- `org` of the bytes get(i) reads; lo / hi = the bus addresses get(0) and
-- the end of the readable bytes stand for (pointers are checked against them)
local decodeAt
-- a `sub` is written { spec, n, base = .. }: seen as an entry { _, spec, n, base = .. }
local subDescs = setmetatable({}, { __mode = "k" })
local function asDesc(sub)
  local d = subDescs[sub]
  if not d then
    d = setmetatable({ false, sub[1], sub[2] }, { __index = sub })
    subDescs[sub] = d
  end
  return d
end
decodeAt = function(d, get, org, lo, hi, t)
  local fields, rec, rowSize, braced = parseSpec(d[2])
  local stride = d.stride or rowSize
  local base, step, rowbase = d.base or 1, d.step or 1, (d.rowbase or 1) - 1
  local function deref(p, sub)
    if not (p >= lo and p < hi) then return nil end
    if not sub then return p end
    return decodeAt(asDesc(sub), get, p - lo, lo, hi, {})
  end
  local function field(o, f)
    local v = rd(get, o + f.off, f.ty)
    if f.wd then v = math.floor(v / 2 ^ f.lo) % 2 ^ f.wd
    elseif f.ty == "ptr" then v = deref(v, d.sub) end
    return v
  end
  local function row(o)
    if not braced then return field(o, fields[1]) end
    local r = {}
    for j, f in ipairs(fields) do r[rec and f.name or (j + rowbase)] = field(o, f) end
    return r
  end
  local function first(o) local f = fields[1]; local v = rd(get, o + f.off, f.ty); if f.wd then v = math.floor(v / 2 ^ f.lo) % 2 ^ f.wd end return v end
  local function convert(list)
    if d.as == "set" or d.as == "map" then -- KeyValuePair lists as {[key] = true / value}
      local m = {}
      for _, r in ipairs(list) do m[r[1]] = d.as == "set" or r[2] end
      return m
    elseif d.as == "keys" then
      for k, r in ipairs(list) do list[k] = r[1] end
    end
    return list
  end
  if d.ptrs then
    -- a table of n pointers, each to rows of the spec that end at the
    -- terminator (first field == term) or, with term = "next", where the
    -- next list (or the pointer table) starts
    local ps, starts = {}, {}
    for i = 0, d[3] - 1 do
      local p = rd(get, org + 4 * i, "u32")
      ps[i] = p
      if p >= lo and p < hi then starts[#starts + 1] = p end
    end
    starts[#starts + 1] = lo + org
    table.sort(starts)
    for i = 0, d[3] - 1 do
      local p = ps[i]
      if d.one and p >= lo and p < hi then -- each pointer to one row
        t[base + i * step] = row(p - lo)
      elseif p >= lo and p < hi then
        local stop = hi
        for _, q in ipairs(starts) do if q > p then stop = q break end end
        local list, o = {}, p - lo
        while o + rowSize <= stop - lo do
          if d.term ~= "next" and first(o) == d.term then break end
          list[#list + 1] = row(o)
          o = o + stride
        end
        list = convert(list)
        if next(list) ~= nil or not d.dropEmpty then t[base + i * step] = list end
      end
    end
    return t
  end
  if braced and d[3] == nil then -- one record
    for j, f in ipairs(fields) do t[rec and f.name or (j + rowbase)] = field(org, f) end
    return t
  end
  if not braced and d[3] == nil then -- one value (a pointer's target)
    return field(org, fields[1])
  end
  if d.group then -- n rows in groups of `group` (each group a 1-based list)
    for g = 0, d[3] / d.group - 1 do
      local list = {}
      for k = 0, d.group - 1 do list[k + (d.gbase or 1)] = row(org + (g * d.group + k) * stride) end
      t[base + g * step] = list
    end
    return t
  end
  if d.term ~= nil or d.as then -- a list (ended by its terminator), maybe as a set / map
    local list = {}
    for i = 0, d[3] - 1 do
      if d.term ~= nil and first(org + i * stride) == d.term then break end
      list[#list + 1] = row(org + i * stride)
    end
    list = convert(list)
    if d.as == "set" or d.as == "map" then for k, v in pairs(list) do t[k] = v end return t end
    for i, v in ipairs(list) do t[base + (i - 1) * step] = v end
    return t
  end
  for i = 0, d[3] - 1 do
    t[base + i * step] = row(org + i * stride)
  end
  return t
end

-- decodes entry e from get(i) (0-based offset in the entry's bytes) into t
local function decode(e, get, t)
  if isFar(e) then
    -- get reads by bus address - BUS (a memory image of the touched bytes)
    local org = e[1] - BUS
    if e.lit then org = rd(get, org, "u32") - BUS end
    return decodeAt(e, get, org, BUS, BUS_END, t)
  end
  local lo = e.range and e.range[1] or e[1]
  local hi = e.range and e.range[2] or (e[1] + RT.size(e))
  return decodeAt(e, get, e[1] - lo, lo, hi, t)
end

function RT.fletcher(get, n)
  local a, b = 0, 0
  for i = 0, n - 1 do
    a = (a + get(i)) % 65535
    b = (b + a) % 65535
  end
  return b * 65536 + a
end

local function cat() return require("src.zelda.tmc.RomTablesCat") end

-- far entries: the bytes a decode touches, as segments { addr, bytes };
-- serialized "u32 count, then per segment u32 addr, u32 length, bytes"
local function u32s(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
local function gatherFar(rom, e)
  local touched = {}
  local function get(o)
    local a = BUS + o
    if not rom:valid(a) then error("outside the ROM", 0) end
    touched[a] = true
    return rom.data:byte(a - BUS + 1)
  end
  decode(e, get, {})
  local addrs = {}
  for a in pairs(touched) do addrs[#addrs + 1] = a end
  table.sort(addrs)
  local segs, cur = {}, nil
  for _, a in ipairs(addrs) do
    if cur and a == cur[1] + cur[2] then cur[2] = cur[2] + 1
    else cur = { a, 1 }; segs[#segs + 1] = cur end
  end
  local parts = { u32s(#segs) }
  for _, s in ipairs(segs) do
    parts[#parts + 1] = u32s(s[1]) .. u32s(s[2]) .. rom:str(s[1], s[2])
  end
  return table.concat(parts)
end

local function farGetter(blob, off)
  local function u32(i) return blob:byte(i + 1) + blob:byte(i + 2) * 256 + blob:byte(i + 3) * 65536 + blob:byte(i + 4) * 16777216 end
  local n, p, segs = u32(off), off + 4, {}
  for _ = 1, n do
    local a, len = u32(p), u32(p + 4)
    segs[#segs + 1] = { a, len, p + 8 }
    p = p + 8 + len
  end
  return function(o)
    local a = BUS + o
    for _, s in ipairs(segs) do
      if a >= s[1] and a < s[1] + s[2] then return blob:byte(s[3] + (a - s[1]) + 1) end
    end
    error(string.format("RomTables: byte %08X not in the gathered table", a), 2)
  end
end

-- ---------------------------------------------------------------------------
-- import side
-- ---------------------------------------------------------------------------
-- builds { name = { addr, off, size } }, blob from an opened Rom; errors when
-- an entry is outside the ROM or its checksum is not the expected one
function RT.build(rom)
  local C = cat()
  local names = {}
  for name in pairs(C) do names[#names + 1] = name end
  table.sort(names)
  local idx, parts, at, bad = {}, {}, 0, {}
  for _, name in ipairs(names) do
    local e = C[name]
    local s, lo
    if isFar(e) then
      local ok, r = pcall(gatherFar, rom, e)
      if not ok and os.getenv("RT_DEBUG") then print(name, r) end
      s, lo = ok and r or nil, e[1]
    else
      lo = e.range and e.range[1] or e[1]
      local size = RT.size(e)
      s = rom:str(lo, size)
      if s and #s ~= size then s = nil end
    end
    if not s then
      bad[#bad + 1] = name .. " (outside the ROM)"
    else
      local size = #s
      local ck = RT.fletcher(function(i) return s:byte(i + 1) end, size)
      if e.ck and ck ~= e.ck then
        bad[#bad + 1] = string.format("%s (checksum %08X, want %08X)", name, ck, e.ck)
      end
      idx[name] = { lo, at, size }
      parts[#parts + 1] = s
      at = at + size
    end
  end
  if #bad > 0 then
    error("Minish Cap import: " .. #bad .. " ROM tables do not look right (not the USA ROM?): "
      .. table.concat(bad, ", ", 1, math.min(#bad, 8)))
  end
  return idx, table.concat(parts)
end

function RT.run(rom, store, manifest)
  local idx, blob = RT.build(rom)
  assert(store:write("r35.bin", blob))
  manifest.r35 = idx
end

-- ---------------------------------------------------------------------------
-- runtime side
-- ---------------------------------------------------------------------------
local handed = {}   -- name -> the table handed out by RT.t
local source = nil  -- { idx = ..., blob = ... }

local EMPTY_MT = {
  __index = function(t, k)
    error("RomTables: '" .. tostring(rawget(t, "__rt")) .. "' read before the Minish Cap cache was attached", 2)
  end,
}

local function fillInto(name, t)
  local e = cat()[name]
  assert(e, "RomTables: no catalogue entry " .. name)
  local ix = source.idx[name]
  assert(ix, "RomTables: the cache has no table " .. name .. " (re-import)")
  local off, blob = ix[2], source.blob
  for k in pairs(t) do t[k] = nil end
  setmetatable(t, nil)
  if isFar(e) then decode(e, farGetter(blob, off), t) return t end
  decode(e, function(i) return blob:byte(off + i + 1) or 0 end, t)
  return t
end

function RT.t(name)
  local t = handed[name]
  if t then return t end
  t = {}
  handed[name] = t
  if source then
    fillInto(name, t)
  else
    rawset(t, "__rt", name)
    setmetatable(t, EMPTY_MT)
  end
  return t
end

local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = deepcopy(x) end
  return o
end

function RT.fresh(name) return deepcopy(RT.t(name)) end

-- the decoded value of one table without registering it (checks / tools)
function RT.peek(name) return source and fillInto(name, {}) or nil end

function RT.attached() return source ~= nil end

local function attachBlob(idx, blob)
  source = { idx = idx, blob = blob }
  for name, t in pairs(handed) do fillInto(name, t) end
  return true
end

-- Assets.new: the cache's r35.bin (an older cache without it leaves the
-- tables unattached: the game asks for a re-import through cacheVersion)
function RT.attach(A)
  local idx = A and A.manifest and A.manifest.r35
  if idx then -- a cache from before a catalogue change lacks entries: as if it had none
    for name in pairs(cat()) do if not idx[name] then idx = nil break end end
  end
  if not idx then
    -- dev scenes on an older cache read the ROM, as ExtractR26.tables does
    -- (or the ROM file named by TMC_DEV_ROM; the shipped game sets neither)
    local dev = rawget(_G, "R26_DEV_ROM")
    if not dev and os.getenv("TMC_DEV_ROM") then dev = require("src.zelda.tmc.Rom").open(os.getenv("TMC_DEV_ROM")) end
    if dev then return RT.attachRom(dev) end
    return false
  end
  local blob = A.store:read("r35.bin")
  if not blob then return false end
  return attachBlob(idx, blob)
end

-- from an opened Rom (tests and dev scenes; the shipped game reads the cache)
function RT.attachRom(rom)
  local idx, blob = RT.build(rom)
  RT._devRom = rom
  return attachBlob(idx, blob)
end

-- the Rom a test / dev scene attached (nil in the shipped game, which reads the cache)
function RT.devRom() return RT._devRom end

-- tests / dev scenes: a sprite's animations straight from the attached ROM
-- (gSpritePtrs -> animation table -> keyframes {frame, duration, settings,
-- flags} up to the $80 flag + loop byte), for code that steps Link's frame
-- flags when the stand-in assets carry no sprite; nil without a dev ROM
local devSprites = {}
function RT.devSprite(i)
  local rom = RT._devRom
  if not rom then return nil end
  if devSprites[i] ~= nil then return devSprites[i] or nil end
  devSprites[i] = false
  local Layout = require("src.zelda.tmc.Layout")
  local animTable = rom:ptr(Layout.gSpritePtrs + 16 * i)
  if not animTable then return nil end
  local spr = { anims = {} }
  for a = 0, 255 do
    local ap = rom:u32(animTable + 4 * a)
    if ap ~= 0 then
      if not rom:valid(ap) then break end
      local keys, q = {}, ap
      for _ = 1, 64 do
        local fl2 = rom:u8(q + 3)
        keys[#keys + 1] = { rom:u8(q), rom:u8(q + 1), rom:u8(q + 2), fl2 }
        q = q + 4
        if band(fl2, 0x80) ~= 0 then keys.loopBack = rom:u8(q) break end
      end
      spr.anims[a] = keys
    end
  end
  devSprites[i] = spr
  return spr
end

-- tests: the player's ROM at TMC_ROM or the repo root; false when absent
function RT.attachForTests()
  if source then return true end
  local Rom = require("src.zelda.tmc.Rom")
  local path = os.getenv("TMC_ROM") or "Legend of Zelda, The - The Minish Cap (USA).gba"
  local rom = Rom.open(path)
  if not rom then return false end
  return RT.attachRom(rom)
end

return RT
