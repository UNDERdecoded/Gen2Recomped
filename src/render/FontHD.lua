-- THE CARTRIDGE'S GLYPHS, SMOOTHED FOR A BIG SCREEN.
--
-- A battle drawn at a multiple of its screen (src/render/SuperSample.lua) would
-- still print every letter as the DS's 1-pixel blocks, R window pixels each --
-- the "pixelated" text of single-screen play. This keeps the cartridge's OWN
-- letterforms and takes the blocks off them: each page is enlarged FACTOR
-- times by COVERAGE. Every colour on the page is a mask; each mask is sampled
-- bilinearly at the new size, the colour with the most coverage wins the
-- pixel, and the summed coverage, through a soft threshold, is its alpha. A
-- stair-stepped diagonal becomes a clean edge, a corner rounds, a 1-pixel
-- stroke keeps its width, and a two-tone glyph keeps both tones. Drawn back at
-- 1/FACTOR with linear filtering. At 1x nothing changes: Font only asks for
-- this inside a supersampled pass.
--
-- (Scale2x was tried first: on a font made of straight strokes it changes
-- almost nothing, which is what was reported.)

local H = {}

H.FACTOR = 4
local cache = setmetatable({}, { __mode = "k" })

local okFfi, ffi = pcall(require, "ffi")

-- smooth(src, F) -> ImageData F times the size (see the header)
local function smooth(src, F, cw, ch)
  cw, ch = cw or 8, ch or 8
  local w, h = src:getDimensions()
  local out = love.image.newImageData(w * F, h * F)
  if not (okFfi and src.getFFIPointer) then return nil end
  local S = ffi.cast("uint32_t*", src:getFFIPointer())
  local O = ffi.cast("uint32_t*", out:getFFIPointer())
  -- the page's colours (opaque ones), each a mask
  local colours, index = {}, {}
  local n = w * h
  local id = ffi.new("uint8_t[?]", n)
  for i = 0, n - 1 do
    local v = S[i]
    local a = math.floor(v / 16777216) % 256
    if a >= 128 then
      local k = index[v]
      if not k then
        colours[#colours + 1] = v
        k = #colours
        index[v] = k
        if k > 250 then return nil end
      end
      id[i] = k
    else
      id[i] = 0
    end
  end
  local C = #colours
  local cover = {}
  local W, Hh = w * F, h * F
  for oy = 0, Hh - 1 do
    local sy = (oy + 0.5) / F - 0.5
    local y0 = math.floor(sy)
    local fy = sy - y0
    local y1 = y0 + 1
    -- inside this glyph's own cell: a neighbour's ink must not bleed in
    local cy = math.floor(oy / F / ch) * ch
    if y0 < cy then y0 = cy end
    if y1 > cy + ch - 1 then y1 = cy + ch - 1 end
    if y1 > h - 1 then y1 = h - 1 end
    for ox = 0, W - 1 do
      local sx = (ox + 0.5) / F - 0.5
      local x0 = math.floor(sx)
      local fx = sx - x0
      local x1 = x0 + 1
      local cx = math.floor(ox / F / cw) * cw
      if x0 < cx then x0 = cx end
      if x1 > cx + cw - 1 then x1 = cx + cw - 1 end
      if x1 > w - 1 then x1 = w - 1 end
      local a00, a10, a01, a11 = id[y0 * w + x0], id[y0 * w + x1], id[y1 * w + x0], id[y1 * w + x1]
      local o = oy * W + ox
      if a00 == 0 and a10 == 0 and a01 == 0 and a11 == 0 then
        O[o] = 0
      else
        local w00, w10, w01, w11 = (1 - fx) * (1 - fy), fx * (1 - fy), (1 - fx) * fy, fx * fy
        for k = 1, C do cover[k] = 0 end
        if a00 > 0 then cover[a00] = cover[a00] + w00 end
        if a10 > 0 then cover[a10] = cover[a10] + w10 end
        if a01 > 0 then cover[a01] = cover[a01] + w01 end
        if a11 > 0 then cover[a11] = cover[a11] + w11 end
        local best, bk, total = -1, 1, 0
        for k = 1, C do
          local c = cover[k]
          total = total + c
          if c > best then best, bk = c, k end
        end
        -- the soft threshold: half coverage is the edge, a pixel's width of ramp
        local t = (total - 0.5) * F * 0.5 + 0.5
        if t <= 0 then
          O[o] = 0
        else
          if t > 1 then t = 1 end
          local v = colours[bk]
          local rgb = v % 16777216
          local a = math.floor(v / 16777216) % 256
          O[o] = rgb + math.floor(a * t + 0.5) * 16777216
        end
      end
    end
  end
  return out
end

-- the pixels of an Image, through a canvas (LOVE 11 Images keep none)
local function pixelsOf(image)
  local g = love.graphics
  local w, h = image:getDimensions()
  -- dpiscale 1: on a high-DPI window (every phone) a canvas defaults to the
  -- screen's density, so its ImageData came back ~3x the page each way and
  -- `smooth` then worked on ~9x the pixels -- the first menu frame cost 72s
  -- interpreted -- and the quads no longer matched the page
  local ok, c = pcall(g.newCanvas, w, h, { dpiscale = 1 })
  if not ok then return nil end
  g.push("all")
  g.origin(); g.setScissor(); g.setShader()
  g.setCanvas(c)
  g.clear(0, 0, 0, 0)
  g.setBlendMode("replace")
  g.setColor(1, 1, 1, 1)
  g.draw(image, 0, 0)
  g.pop()
  local data = c:newImageData()
  c:release()
  return data
end

-- ONLY WHERE THE JIT RUNS. `smooth` is a per-pixel Lua loop over a page
-- FACTOR^2 times the size, one pass per colour: instant compiled, but
-- interpreted it takes minutes -- and love-android runs LuaJIT with the
-- compiler off (iOS forbids it outright). The first smoothed letter is the
-- Black / White main menu in single-screen play, so on a phone pressing A
-- on the title froze the game there. Without the JIT the glyphs stay the
-- cartridge's own 1-pixel ones (Font falls back when this answers nil).
-- Answered once: Font asks for every letter of a supersampled screen, and a
-- require + jit.status + getOS per glyph is real time interpreted.
local availableAnswer
function H.available()
  if H.forced ~= nil then return H.forced end
  if availableAnswer ~= nil then return availableAnswer end
  availableAnswer = false
  local okJ, jitLib = pcall(require, "jit")
  if not (okJ and type(jitLib) == "table" and jitLib.status) then return false end
  if not jitLib.status() then return false end
  local os = love.system and love.system.getOS and love.system.getOS()
  if os == "Android" or os == "iOS" then return false end
  availableAnswer = true
  return true
end

-- forPage(page) -> { image, quads } at FACTOR times the page, or nil
function H.forPage(page)
  if not (page and page.image and page.quads) then return nil end
  if not H.available() then return nil end
  local hit = cache[page]
  if hit ~= nil then return hit or nil end
  local ok, hd = pcall(function()
    local data = pixelsOf(page.image)
    if not data then return nil end
    data = smooth(data, H.FACTOR, page.cellWidth, page.cellHeight)
    if not data then return nil end
    local img = love.graphics.newImage(data)
    img:setFilter("linear", "linear")
    local iw, ih = img:getDimensions()
    local quads = {}
    for i, q in pairs(page.quads) do
      local x, y, w, h = q:getViewport()
      quads[i] = love.graphics.newQuad(x * H.FACTOR, y * H.FACTOR, w * H.FACTOR, h * H.FACTOR, iw, ih)
    end
    return { image = img, quads = quads }
  end)
  cache[page] = ok and hd or false
  return ok and hd or nil
end

-- draw(page, index, x, y): the glyph at its 1x place and size
function H.draw(page, index, x, y)
  local hd = H.forPage(page)
  local q = hd and hd.quads[index]
  if not q then return false end
  local s = 1 / H.FACTOR
  love.graphics.draw(hd.image, q, x, y, 0, s, s)
  return true
end

return H
