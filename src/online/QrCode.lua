-- A small pure-Lua QR code encoder (ISO/IEC 18004), for the launcher's
-- HOST WITH FRIENDS screen: a phone can scan a friend's invite off a PC
-- screen instead of typing it.
--
--   local qr = QrCode.encode("PK:ABCD-EFGH-JKMN-PQRS-T")      -- or nil, why
--   qr.size, qr.version, qr.ecl, qr.mask
--   qr:get(x, y)  -> true for a dark module (0-based, x right, y down)
--   QrCode.draw(qr, x, y, cell)  -- LOVE: dark squares on whatever is behind
--
-- Byte mode only, versions 1..10 (up to 271 bytes at level L), levels L and
-- M (M by default: survives a smudged screen or a glare spot).  LuaJIT: no
-- bit ops from 5.3, so the GF(256) and BCH arithmetic uses `bit` when it is
-- there and plain arithmetic otherwise.

local QrCode = {}
QrCode.__index = QrCode

local okBit, bit = pcall(require, "bit")
if not okBit then bit = nil end

local function bxor(a, b)
  if bit then return bit.bxor(a, b) end
  local r, p = 0, 1
  while a > 0 or b > 0 do
    local x, y = a % 2, b % 2
    if x ~= y then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end

local function getBit(v, i) return math.floor(v / 2 ^ i) % 2 == 1 end

-- ECC table, versions 1..10: { eccPerBlock, { {blocks, dataPerBlock}, ... } }
QrCode.ECC = {
  L = {
    { 7, { { 1, 19 } } }, { 10, { { 1, 34 } } }, { 15, { { 1, 55 } } }, { 20, { { 1, 80 } } },
    { 26, { { 1, 108 } } }, { 18, { { 2, 68 } } }, { 20, { { 2, 78 } } }, { 24, { { 2, 97 } } },
    { 30, { { 2, 116 } } }, { 18, { { 2, 68 }, { 2, 69 } } },
  },
  M = {
    { 10, { { 1, 16 } } }, { 16, { { 1, 28 } } }, { 26, { { 1, 44 } } }, { 18, { { 2, 32 } } },
    { 24, { { 2, 43 } } }, { 16, { { 4, 27 } } }, { 18, { { 4, 31 } } },
    { 22, { { 2, 38 }, { 2, 39 } } }, { 22, { { 3, 36 }, { 2, 37 } } },
    { 26, { { 4, 43 }, { 1, 44 } } },
  },
}
QrCode.FORMAT_BITS = { L = 1, M = 0 }
QrCode.ALIGN = {
  {}, { 6, 18 }, { 6, 22 }, { 6, 26 }, { 6, 30 }, { 6, 34 },
  { 6, 22, 38 }, { 6, 24, 42 }, { 6, 26, 46 }, { 6, 28, 50 },
}
QrCode.MAX_VERSION = 10

local function dataCapacity(version, ecl)
  local n = 0
  for _, g in ipairs(QrCode.ECC[ecl][version][2]) do n = n + g[1] * g[2] end
  return n
end
QrCode.dataCapacity = dataCapacity

-------------------------------------------------------------- GF(256)

local EXP, LOG = {}, {}
do
  local x = 1
  for i = 0, 254 do
    EXP[i] = x
    LOG[x] = i
    x = x * 2
    if x >= 256 then x = bxor(x, 0x11D) end
  end
  for i = 255, 511 do EXP[i] = EXP[i - 255] end
end

local function gfMul(a, b)
  if a == 0 or b == 0 then return 0 end
  return EXP[LOG[a] + LOG[b]]
end
QrCode.gfMul = gfMul

-- the generator polynomial of degree n, coefficients highest first
-- (leading 1 dropped): prod (x - a^i), i = 0..n-1
local function generator(n)
  local poly = { 1 }
  for i = 0, n - 1 do
    local nxt = {}
    for j = 1, #poly + 1 do nxt[j] = 0 end
    for j = 1, #poly do
      nxt[j] = bxor(nxt[j], poly[j])
      nxt[j + 1] = bxor(nxt[j + 1], gfMul(poly[j], EXP[i]))
    end
    poly = nxt
  end
  table.remove(poly, 1)
  return poly
end

-- the n error-correction bytes of `data` (a list of byte values)
function QrCode.rsRemainder(data, n)
  local gen = generator(n)
  local rem = {}
  for i = 1, n do rem[i] = 0 end
  for _, b in ipairs(data) do
    local factor = bxor(b, rem[1])
    table.remove(rem, 1)
    rem[n] = 0
    for i = 1, n do rem[i] = bxor(rem[i], gfMul(gen[i], factor)) end
  end
  return rem
end

-------------------------------------------------------------- bits

local function bitsOf(text, version, ecl)
  local cap = dataCapacity(version, ecl)
  local bits = {}
  local function put(v, n)
    for i = n - 1, 0, -1 do bits[#bits + 1] = getBit(v, i) and 1 or 0 end
  end
  put(4, 4) -- byte mode
  put(#text, version < 10 and 8 or 16)
  for i = 1, #text do put(text:byte(i), 8) end
  if #bits > cap * 8 then return nil end
  for _ = 1, math.min(4, cap * 8 - #bits) do bits[#bits + 1] = 0 end
  while #bits % 8 ~= 0 do bits[#bits + 1] = 0 end
  local bytes = {}
  for i = 1, #bits, 8 do
    local v = 0
    for j = 0, 7 do v = v * 2 + bits[i + j] end
    bytes[#bytes + 1] = v
  end
  local pad = { 0xEC, 0x11 }
  local k = 1
  while #bytes < cap do
    bytes[#bytes + 1] = pad[k]
    k = 3 - k
  end
  return bytes
end

-- split into blocks, add ECC, interleave
local function codewords(bytes, version, ecl)
  local row = QrCode.ECC[ecl][version]
  local nEcc = row[1]
  local blocks, pos = {}, 1
  for _, g in ipairs(row[2]) do
    for _ = 1, g[1] do
      local d = {}
      for i = 1, g[2] do d[i] = bytes[pos]; pos = pos + 1 end
      blocks[#blocks + 1] = { data = d, ecc = QrCode.rsRemainder(d, nEcc) }
    end
  end
  local out, maxData = {}, 0
  for _, b in ipairs(blocks) do maxData = math.max(maxData, #b.data) end
  for i = 1, maxData do
    for _, b in ipairs(blocks) do
      if b.data[i] then out[#out + 1] = b.data[i] end
    end
  end
  for i = 1, nEcc do
    for _, b in ipairs(blocks) do out[#out + 1] = b.ecc[i] end
  end
  return out
end

-------------------------------------------------------------- the matrix

local function newGrid(size, v)
  local g = {}
  for y = 0, size - 1 do
    local r = {}
    for x = 0, size - 1 do r[x] = v end
    g[y] = r
  end
  return g
end

function QrCode:get(x, y)
  local r = self.modules[y]
  return r ~= nil and r[x] == true
end

local function setF(self, x, y, dark)
  self.modules[y][x] = dark
  self.isFunction[y][x] = true
end

local function finder(self, cx, cy)
  for dy = -4, 4 do
    for dx = -4, 4 do
      local x, y = cx + dx, cy + dy
      if x >= 0 and x < self.size and y >= 0 and y < self.size then
        local d = math.max(math.abs(dx), math.abs(dy))
        setF(self, x, y, d ~= 2 and d ~= 4)
      end
    end
  end
end

local function alignment(self, cx, cy)
  for dy = -2, 2 do
    for dx = -2, 2 do
      setF(self, cx + dx, cy + dy, math.max(math.abs(dx), math.abs(dy)) ~= 1)
    end
  end
end

-- the 15 format bits for a level and mask (BCH(15,5) and the 0x5412 mask)
function QrCode.formatBits(ecl, mask)
  local data = QrCode.FORMAT_BITS[ecl] * 8 + mask
  local rem = data
  for _ = 1, 10 do
    rem = rem * 2
    if rem >= 1024 then rem = bxor(rem, 0x537) end
  end
  return bxor(data * 1024 + rem, 0x5412)
end

function QrCode.versionBits(version)
  local rem = version
  for _ = 1, 12 do
    rem = rem * 2
    if rem >= 4096 then rem = bxor(rem, 0x1F25) end
  end
  return version * 4096 + rem
end

local function drawFormat(self, mask)
  local bits = QrCode.formatBits(self.ecl, mask)
  local size = self.size
  for i = 0, 5 do setF(self, 8, i, getBit(bits, i)) end
  setF(self, 8, 7, getBit(bits, 6))
  setF(self, 8, 8, getBit(bits, 7))
  setF(self, 7, 8, getBit(bits, 8))
  for i = 9, 14 do setF(self, 14 - i, 8, getBit(bits, i)) end
  for i = 0, 7 do setF(self, size - 1 - i, 8, getBit(bits, i)) end
  for i = 8, 14 do setF(self, 8, size - 15 + i, getBit(bits, i)) end
  setF(self, 8, size - 8, true)
end

local function drawFunctions(self)
  local size = self.size
  for i = 0, size - 1 do
    setF(self, 6, i, i % 2 == 0)
    setF(self, i, 6, i % 2 == 0)
  end
  finder(self, 3, 3)
  finder(self, size - 4, 3)
  finder(self, 3, size - 4)
  local pos = QrCode.ALIGN[self.version]
  local n = #pos
  for i = 1, n do
    for j = 1, n do
      local corner = (i == 1 and j == 1) or (i == 1 and j == n) or (i == n and j == 1)
      if not corner then alignment(self, pos[i], pos[j]) end
    end
  end
  drawFormat(self, 0) -- reserves the cells; redrawn with the real mask
  if self.version >= 7 then
    local bits = QrCode.versionBits(self.version)
    for i = 0, 17 do
      local a, b = size - 11 + i % 3, math.floor(i / 3)
      local d = getBit(bits, i)
      setF(self, a, b, d)
      setF(self, b, a, d)
    end
  end
end

local function drawData(self, cw)
  local size = self.size
  local i, total = 0, #cw * 8
  local right = size - 1
  while right >= 1 do
    if right == 6 then right = 5 end
    for vert = 0, size - 1 do
      for j = 0, 1 do
        local x = right - j
        local upward = (math.floor((right + 1) / 2) % 2) == 0
        local y = upward and (size - 1 - vert) or vert
        if not self.isFunction[y][x] then
          if i < total then
            local byte = cw[math.floor(i / 8) + 1]
            self.modules[y][x] = getBit(byte, 7 - i % 8)
            i = i + 1
          else
            self.modules[y][x] = false -- remainder bits
          end
        end
      end
    end
    right = right - 2
  end
end

QrCode.MASKS = {
  [0] = function(x, y) return (x + y) % 2 == 0 end,
  function(x, y) return y % 2 == 0 end,
  function(x, y) return x % 3 == 0 end,
  function(x, y) return (x + y) % 3 == 0 end,
  function(x, y) return (math.floor(x / 3) + math.floor(y / 2)) % 2 == 0 end,
  function(x, y) return (x * y) % 2 + (x * y) % 3 == 0 end,
  function(x, y) return ((x * y) % 2 + (x * y) % 3) % 2 == 0 end,
  function(x, y) return ((x + y) % 2 + (x * y) % 3) % 2 == 0 end,
}

local function applyMask(self, mask)
  local f = QrCode.MASKS[mask]
  for y = 0, self.size - 1 do
    for x = 0, self.size - 1 do
      if not self.isFunction[y][x] and f(x, y) then
        self.modules[y][x] = not self.modules[y][x]
      end
    end
  end
end

-- the standard penalty (N1 runs, N2 blocks, N3 finder look-alikes, N4 balance)
function QrCode.penalty(self)
  local size, m = self.size, self.modules
  local score, dark = 0, 0
  local function line(get)
    local run, last = 0, nil
    local seq = {}
    for i = 0, size - 1 do
      local v = get(i)
      seq[#seq + 1] = v and 1 or 0
      if v == last then
        run = run + 1
        if run == 5 then score = score + 3 elseif run > 5 then score = score + 1 end
      else
        run, last = 1, v
      end
    end
    -- 1011101 with four light modules on either side
    local s = table.concat(seq)
    local a, b = "00001011101", "10111010000"
    local from = 1
    while true do
      local p = s:find(a, from, true)
      if not p then break end
      score = score + 40
      from = p + 1
    end
    from = 1
    while true do
      local p = s:find(b, from, true)
      if not p then break end
      score = score + 40
      from = p + 1
    end
  end
  for y = 0, size - 1 do line(function(i) return m[y][i] end) end
  for x = 0, size - 1 do line(function(i) return m[i][x] end) end
  for y = 0, size - 2 do
    for x = 0, size - 2 do
      local c = m[y][x]
      if c == m[y][x + 1] and c == m[y + 1][x] and c == m[y + 1][x + 1] then score = score + 3 end
    end
  end
  for y = 0, size - 1 do
    for x = 0, size - 1 do if m[y][x] then dark = dark + 1 end end
  end
  local total = size * size
  local k = math.ceil(math.abs(dark * 20 - total * 10) / total) - 1
  return score + math.max(0, k) * 10
end

--- QrCode.encode(text, opts) -> qr | nil, why
--   opts.ecl "L" | "M" (default "M"); opts.mask 0..7 to force one;
--   opts.minVersion
function QrCode.encode(text, opts)
  opts = opts or {}
  text = tostring(text or "")
  local ecl = opts.ecl == "L" and "L" or "M"
  local version, bytes
  for v = opts.minVersion or 1, QrCode.MAX_VERSION do
    bytes = bitsOf(text, v, ecl)
    if bytes then version = v break end
  end
  if not version then return nil, "too long for a QR code here" end
  local cw = codewords(bytes, version, ecl)
  local size = version * 4 + 17
  local self = setmetatable({ version = version, ecl = ecl, size = size, text = text }, QrCode)
  self.modules = newGrid(size, false)
  self.isFunction = newGrid(size, false)
  drawFunctions(self)
  drawData(self, cw)
  local best, bestScore = opts.mask, nil
  if best == nil then
    for mask = 0, 7 do
      applyMask(self, mask)
      drawFormat(self, mask)
      local s = QrCode.penalty(self)
      if not bestScore or s < bestScore then best, bestScore = mask, s end
      applyMask(self, mask) -- undo (xor)
    end
  end
  applyMask(self, best)
  drawFormat(self, best)
  self.mask = best
  self.codewords = cw
  return self
end

-- rows of "#"/" " (tests, logs)
function QrCode:toStrings()
  local out = {}
  for y = 0, self.size - 1 do
    local row = {}
    for x = 0, self.size - 1 do row[#row + 1] = self.modules[y][x] and "#" or "." end
    out[#out + 1] = table.concat(row)
  end
  return out
end

-- LOVE: a white quiet zone (4 cells) and the dark modules, cell px each.
-- Returns the drawn width (size + 8 cells).
function QrCode.draw(qr, x, y, cell)
  local g = love.graphics
  local full = (qr.size + 8) * cell
  g.setColor(1, 1, 1, 1)
  g.rectangle("fill", x, y, full, full)
  g.setColor(0, 0, 0, 1)
  for yy = 0, qr.size - 1 do
    local row = qr.modules[yy]
    local xx = 0
    while xx < qr.size do
      if row[xx] then
        local start = xx
        while xx < qr.size and row[xx] do xx = xx + 1 end
        g.rectangle("fill", x + (start + 4) * cell, y + (yy + 4) * cell, (xx - start) * cell, cell)
      else
        xx = xx + 1
      end
    end
  end
  return full
end

return QrCode
