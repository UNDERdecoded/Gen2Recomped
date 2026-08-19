-- Text renderer using the real extracted font sheets and charmap.
-- Glyphs live on *pages*: font.png holds codes $80-$FF, font_extra.png
-- $60-$7F (borders etc), and a mod registers more (a kana block at $100,
-- a replacement sheet for an existing page) through the font registry,
-- which merges into data.font.pages.  A page may set its own `advance`
-- for variable-width text; the default is the GB's flat 8px.
-- The charmap is matched greedily (longest sequence first) so multi-byte
-- UTF-8 chars and ligature glyphs like 'd 'l 's map to single glyphs.

local Assets = require("src.render.Assets")

local Font = {}

local GLYPH = 8
local FALLBACK = { enabled = false, font = nil }

local state
local loadedFrom

-- the two vanilla pages as the legacy def spells them, so a cache that
-- predates the pages table still loads and a mod that registers only one
-- page replaces just that one
local function pagesOf(def)
  local pages = {}
  if def.image then
    pages.main = { image = def.image, base = def.mainBase or 0x80,
                   glyphsPerRow = def.glyphsPerRow or 16 }
  end
  if def.imageExtra then
    pages.extra = { image = def.imageExtra, base = def.extraBase or 0x60,
                    glyphsPerRow = def.glyphsPerRow or 16 }
  end
  for id, page in pairs(def.pages or {}) do
    if type(page) == "table" and page.image then pages[id] = page end
  end
  return pages
end

function Font.load(data)
  loadedFrom = data
  local def = data.font
  state = { def = def, pages = {}, order = {}, byFirstByte = {} }
  FALLBACK.enabled = false
  FALLBACK.font = nil

  -- Gen2 scaffold fonts are placeholder assets, not real glyph atlases.
  -- Use the built-in raster font so dialogue remains readable while
  -- extraction is incomplete.
  if type(def.source) == "string" and def.source:find("Gen2 scaffold", 1, true) then
    FALLBACK.enabled = true
    FALLBACK.font = love.graphics.newFont(GLYPH)
  end

  if FALLBACK.enabled then
    Font.BORDER = {}
    for key, code in pairs(Font.DEFAULT_BORDER) do Font.BORDER[key] = code end
    for key, code in pairs(def.border or {}) do Font.BORDER[key] = code end
    return
  end

  for id, page in pairs(pagesOf(def)) do
    local ok, img = pcall(Assets.image, page.image)
    if ok then
      local iw, ih = img:getDimensions()
      local minHeight = id == "extra" and 16 or 64
      if iw < 128 or ih < minHeight or iw % GLYPH ~= 0 or ih % GLYPH ~= 0 then
        ok = false
      end
    end
    if ok then
      local iw, ih = img:getDimensions()
      local perRow = page.glyphsPerRow or math.floor(iw / GLYPH)
      local quads = {}
      for i = 0, perRow * math.floor(ih / GLYPH) - 1 do
        quads[i] = love.graphics.newQuad((i % perRow) * GLYPH,
          math.floor(i / perRow) * GLYPH, GLYPH, GLYPH, iw, ih)
      end
      local entry = { id = id, image = img, quads = quads,
                      base = page.base, advance = page.advance or GLYPH }
      state.pages[id] = entry
      state.order[#state.order + 1] = entry
    end
  end
  if #state.order == 0 then
    FALLBACK.enabled = true
    FALLBACK.font = love.graphics.newFont(GLYPH)
  end
  -- highest base first: a code resolves against the last page that starts
  -- at or below it, which is exactly what the old main/extra chain did
  table.sort(state.order, function(a, b) return a.base > b.base end)

  -- Bucket the charmap by first byte for fast greedy matching, longest
  -- sequence first *within* each bucket.  The sort is ours rather than
  -- the extractor's: a mod's page ships its own entries and nothing has
  -- put them in length order.
  local function bucket(entry)
    if type(entry) ~= "table" or type(entry.seq) ~= "string"
        or entry.seq == "" then return end
    local b = entry.seq:byte(1)
    state.byFirstByte[b] = state.byFirstByte[b] or {}
    table.insert(state.byFirstByte[b], entry)
  end
  for _, entry in ipairs(def.charmap or {}) do bucket(entry) end
  for _, page in pairs(def.pages or {}) do
    for _, entry in ipairs(type(page) == "table" and page.charmap or {}) do
      bucket(entry)
    end
  end
  for _, entries in pairs(state.byFirstByte) do
    table.sort(entries, function(a, b) return #a.seq > #b.seq end)
  end
  if not (state.pages.main and state.pages.extra) then
    FALLBACK.enabled = true
    FALLBACK.font = love.graphics.newFont(GLYPH)
  end

  Font.BORDER = {}
  for key, code in pairs(Font.DEFAULT_BORDER) do Font.BORDER[key] = code end
  for key, code in pairs(def.border or {}) do Font.BORDER[key] = code end
end

-- re-run load against the data it last saw, so hot reload picks up an
-- edited sheet or a newly merged page
function Font.invalidate()
  if loadedFrom then Font.load(loadedFrom) end
end

Assets.register(Font.invalidate)

-- the page a glyph code draws from, or nil when nothing covers it
local function pageFor(code)
  if not state then return nil end
  for _, page in ipairs(state.order) do
    if code >= page.base then return page end
  end
  return nil
end

local SPACE = 0x7F

-- Segment text into glyph spans: `{ from, to, code }` byte ranges, one per
-- drawn glyph, code nil when the charmap has nothing.  A span is a whole
-- charmap sequence, so a multi-byte char ("é", "♂") and an ASCII ligature
-- ("<PK>", "'d") are each one glyph.
--
-- Every caller that *measures* or *cuts* text walks these instead of bytes.
-- "POKéMON" is 8 bytes and 7 glyphs: measuring it as 8 wraps lines that fit
-- (25 vanilla lines did), and cutting at byte 8 splits the é into two
-- invalid bytes that both draw as spaces.  That distinction is the whole
-- reason a non-English font can be shipped as a mod (#186, #245).
--
-- Safe before Font.load: with no charmap it falls back to UTF-8 lead-byte
-- boundaries, which is all a headless paginate needs.
function Font.split(text)
  local spans = {}
  local i, n = 1, #text
  while i <= n do
    local span
    local candidates = state and state.byFirstByte[text:byte(i)]
    if candidates then
      for _, entry in ipairs(candidates) do
        local len = #entry.seq
        if text:sub(i, i + len - 1) == entry.seq then
          span = { from = i, to = i + len - 1, code = entry.code }
          break
        end
      end
    end
    if not span then
      -- Nothing matched.  Still keep a UTF-8 sequence whole, so a cut never
      -- lands mid-character even for a glyph we cannot draw.
      local last = i
      if text:byte(i) >= 0xC0 then
        local k = i + 1
        while k <= n do
          local b = text:byte(k)
          if b < 0x80 or b > 0xBF then break end
          last, k = k, k + 1
        end
      end
      span = { from = i, to = last }
    end
    spans[#spans + 1] = span
    i = span.to + 1
  end
  return spans
end

-- How many leading spans fit in `budget` pixels.  Advances come from each
-- glyph's own page, so a variable-width page measures correctly.
function Font.spansFitting(spans, budget)
  local used, fit = 0, 0
  for _, span in ipairs(spans) do
    used = used + Font.advanceOf(span.code or SPACE)
    if used > budget then break end
    fit = fit + 1
  end
  return fit
end

-- Convert a text string into a list of glyph codes.  Unknown characters
-- render as space (and are reported once).
local reported = {}
function Font.encode(text)
  if FALLBACK.enabled then
    local codes = {}
    local i, n = 1, #text
    while i <= n do
      local b = text:byte(i)
      if b < 0x80 then
        codes[#codes + 1] = b
        i = i + 1
      else
        -- Keep one cell per UTF-8 sequence in fallback mode.
        local j = i + 1
        while j <= n do
          local nb = text:byte(j)
          if nb < 0x80 or nb > 0xBF then break end
          j = j + 1
        end
        codes[#codes + 1] = string.byte("?")
        i = j
      end
    end
    return codes
  end

  local codes = {}
  for _, span in ipairs(Font.split(text)) do
    local code = span.code
    if not code then
      local ch = text:sub(span.from, span.to)
      if not reported[ch] and text:byte(span.from) >= 32 then
        reported[ch] = true
        require("src.core.Logger").warn("font: no glyph for %q", ch)
      end
      code = SPACE
    end
    codes[#codes + 1] = code
  end
  return codes
end

-- The glyph atlas is black pixels on a transparent field, so setColor can
-- only ever darken it.  Gen 2's Pokedex runs the font through
-- Pokedex_InvertTiles and prints white on black, which needs the glyph shape
-- painted in the current colour instead.
local tintShader, tintPrev, tintDepth = nil, nil, 0

local function tint()
  if tintShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        return vec4(color.rgb, Texel(tex, tc).a * color.a);
      }
    ]])
    tintShader = ok and sh or false
  end
  return tintShader or nil
end

function Font.beginTint()
  local sh = tint()
  if not sh then return end
  if tintDepth == 0 then
    tintPrev = love.graphics.getShader()
    love.graphics.setShader(sh)
  end
  tintDepth = tintDepth + 1
end

function Font.endTint()
  if not tint() or tintDepth == 0 then return end
  tintDepth = tintDepth - 1
  if tintDepth == 0 then
    love.graphics.setShader(tintPrev)
    tintPrev = nil
  end
end

-- ------- window style
--
-- A Game Boy window is white paper with black text on it, and for a screen
-- that IS the Game Boy that is the end of the matter.  It stops being the end
-- of the matter the moment something is drawn BEHIND the window: a battle
-- fought on the live 3D map has a world where the flat white field used to
-- be, and an opaque box sitting on top of it is a hole in the picture.
--
-- So a caller can push a style for a region of drawing:
--
--     Font.pushStyle({ fill = { 1, 1, 1, 0.4 }, text = { 1, 1, 1, 1 } })
--     Font.drawBox(0, 12, 20, 6)
--     Font.draw("...", 8, 112)
--     Font.popStyle()
--
-- `fill` replaces the box's paper colour and `text` repaints the glyphs --
-- repaints, not tints: the atlas is black pixels on a transparent field, so
-- setColor alone can only ever darken it.  That is what Font.beginTint is
-- for, and drawCode reaches for it itself here rather than making every
-- caller remember, because the callers are `Font.draw` loops scattered
-- through the battle screen and half of them set black explicitly on the way
-- past.  `border` styles the frame glyphs separately when it is given, and
-- falls back to `text` when it is not.
--
-- A STACK rather than a single value: one screen draws several windows and
-- only some of them want this (the move list keeps its solid paper while the
-- dialogue underneath goes to glass), so a region has to be able to turn the
-- style OFF and get it back.  `pushStyle(nil)` is that -- it pushes "no
-- style", which is exactly what an unstyled region wants and is why the
-- argument is allowed to be nil rather than rejected.
--
-- Nothing is styled until something pushes one, so the vanilla game never
-- sees this: with an empty stack every draw takes the path it always took.
local styleStack, activeStyle = {}, nil
-- set for the six frame glyphs alone (see drawBox), so `border` can differ
-- from `text` without either one having to be pushed as its own style
local borderPaint = nil
-- boxes already filled in this styled region.  A translucent fill drawn on
-- top of another one is DARKER than either -- the battle menu sits inside
-- the text area, so at 40% the right half of the bottom strip would come out
-- at 64% and the strip would have a seam down the middle that is not in the
-- design.  Opaque paper never had this problem, which is why the rule only
-- exists here: a styled box drawn wholly inside one already filled keeps its
-- FRAME (that is the divider the layout wants) and skips the paper.
local filledRects = {}

function Font.pushStyle(style)
  styleStack[#styleStack + 1] = style or false
  activeStyle = style or nil
  filledRects = {}
end

function Font.popStyle()
  local n = #styleStack
  if n == 0 then return end
  styleStack[n] = nil
  activeStyle = styleStack[n - 1] or nil
  filledRects = {}
end

-- The style in force, or nil.  For a caller that has to make its own
-- decision from it -- a box that draws its interior itself, say.
function Font.style() return activeStyle end

-- Test/frame hygiene: a draw that raised part-way through a styled region
-- would otherwise leave the stack loaded and style the whole next frame.
function Font.clearStyles()
  styleStack, activeStyle, borderPaint = {}, nil, nil
  filledRects = {}
end

-- the unstyled blit; Font.drawCode below is this plus the active style
local function blitCode(code, x, y)
  if FALLBACK.enabled then
    love.graphics.setFont(FALLBACK.font)
    local ch
    if code == 0xED or code == 0xEC then
      ch = ">"
    elseif code == 0xEE then
      ch = "v"
    elseif code >= 32 and code <= 126 then
      ch = string.char(code)
    else
      ch = "?"
    end
    love.graphics.print(ch, x, y)
    return
  end
  local page = pageFor(code)
  if not page then return end
  local quad = page.quads[code - page.base]
  if quad then love.graphics.draw(page.image, quad, x, y) end
end

function Font.drawCode(code, x, y)
  local style = activeStyle
  local paint = borderPaint or (style and style.text)
  if not paint then return blitCode(code, x, y) end
  -- The caller's alpha still counts: it is how a fading box fades its text
  -- with it, and dropping it here would leave the letters hanging in the air
  -- through a fade-out.
  local pr, pg, pb, pa = love.graphics.getColor()
  Font.beginTint()
  love.graphics.setColor(paint[1] or 1, paint[2] or 1, paint[3] or 1,
                         (paint[4] or 1) * (pa or 1))
  blitCode(code, x, y)
  Font.endTint()
  love.graphics.setColor(pr, pg, pb, pa)
end

-- how far the pen moves past a glyph; 8 unless its page says otherwise
function Font.advanceOf(code)
  local page = pageFor(code)
  return page and page.advance or GLYPH
end

-- Pixel width of a string (glyph advances, not UTF-8 byte length).
-- Multi-byte charmap entries like "¥" are one glyph; callers that
-- right-align with `#text * 8` mis-place them.
function Font.width(text)
  local w = 0
  for _, code in ipairs(Font.encode(text)) do
    w = w + Font.advanceOf(code)
  end
  return w
end

-- Draw a plain single-line string at pixel (x, y).  Returns the width
-- drawn, which is #codes * 8 for every fixed-width page.
function Font.draw(text, x, y)
  if FALLBACK.enabled then
    love.graphics.setFont(FALLBACK.font)
    love.graphics.print(text, x, y)
    return #text * GLYPH
  end
  local codes = Font.encode(text)
  local pen = x
  for _, code in ipairs(codes) do
    Font.drawCode(code, pen, y)
    pen = pen + Font.advanceOf(code)
  end
  return pen - x
end

-- Border glyph codes (font_extra.png, from charmap.asm $79-$7E).  A font
-- that draws its boxes from different glyphs sets data.font.border and
-- Font.load folds it over these; the table itself stays writable so a mod
-- can retheme one corner without shipping a whole page.
Font.DEFAULT_BORDER = {
  tl = 0x79, h = 0x7A, tr = 0x7B, v = 0x7C, bl = 0x7D, br = 0x7E,
}
Font.BORDER = {}
for key, code in pairs(Font.DEFAULT_BORDER) do Font.BORDER[key] = code end

-- Draw a Game Boy style bordered box in tile coordinates.
function Font.drawBox(tx, ty, tw, th)
  if FALLBACK.enabled then
    love.graphics.setFont(FALLBACK.font)
    local f = activeStyle and activeStyle.fill
    love.graphics.setColor(f and f[1] or 1, f and f[2] or 1,
                           f and f[3] or 1, f and f[4] or 1)
    love.graphics.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
    local e = activeStyle and (activeStyle.border or activeStyle.text)
    love.graphics.setColor(e and e[1] or 0, e and e[2] or 0,
                           e and e[3] or 0, e and e[4] or 1)
    love.graphics.rectangle("line", tx * 8, ty * 8, tw * 8, th * 8)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local style = activeStyle
  local fill = style and style.fill
  local covered = false
  if fill then
    for _, r in ipairs(filledRects) do
      if tx >= r[1] and ty >= r[2]
         and tx + tw <= r[1] + r[3] and ty + th <= r[2] + r[4] then
        covered = true
        break
      end
    end
  end
  if not covered then
    if fill then
      love.graphics.setColor(fill[1] or 1, fill[2] or 1, fill[3] or 1,
                             fill[4] or 1)
      filledRects[#filledRects + 1] = { tx, ty, tw, th }
    else
      love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
  end
  -- back to full white before the frame: the fill's alpha belongs to the
  -- paper, not to the border glyphs drawn on it, and leaving it set would
  -- fade the frame to match the hole it is supposed to outline
  love.graphics.setColor(1, 1, 1, 1)
  local B = Font.BORDER
  -- `border` is a separate colour from `text` because a frame and the words
  -- inside it are separate decisions.  Held in a local rather than passed
  -- down so drawCode keeps one signature for every caller in the engine;
  -- nil here means the frame simply wears the text colour.
  borderPaint = style and style.border or nil
  Font.drawCode(B.tl, tx * 8, ty * 8)
  Font.drawCode(B.tr, (tx + tw - 1) * 8, ty * 8)
  Font.drawCode(B.bl, tx * 8, (ty + th - 1) * 8)
  Font.drawCode(B.br, (tx + tw - 1) * 8, (ty + th - 1) * 8)
  for i = 1, tw - 2 do
    Font.drawCode(B.h, (tx + i) * 8, ty * 8)
    Font.drawCode(B.h, (tx + i) * 8, (ty + th - 1) * 8)
  end
  for j = 1, th - 2 do
    Font.drawCode(B.v, tx * 8, (ty + j) * 8)
    Font.drawCode(B.v, (tx + tw - 1) * 8, (ty + j) * 8)
  end
  borderPaint = nil
end

return Font
