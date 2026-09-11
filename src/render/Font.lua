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
  -- A CACHE MAY CARRY NO FONT AT ALL, and that has to degrade rather than
  -- stop the boot: `data.font` is nil for any dataset whose extractor does
  -- not write one, and reading `def.source` off nil took the whole game down
  -- before the title screen -- from a module the loader itself calls optional.
  local def = data.font or {}
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

  -- The named faces travel BESIDE the pages, not among them.
  --
  -- Emerald has five Latin faces and they all number their glyphs from zero,
  -- so registering them as pages would give five pages a base of 0 and the
  -- code-to-page lookup would answer with whichever sorted first.  A face is
  -- chosen by NAME (Font.pushFace) rather than resolved from a glyph id, so
  -- it is kept out of that lookup entirely.
  state.faces = {}
  local sources = {}
  for id, page in pairs(pagesOf(def)) do sources[id] = { page, false } end
  for id, face in pairs(def.faces or {}) do
    if type(face) == "table" and face.image then
      sources["face:" .. id] = { face, id }
    end
  end
  for id, src in pairs(sources) do
    local page = src[1]
    local faceName = src[2]
    -- A CELL IS NOT ALWAYS 8x8.  Gen 1 and Gen 2 draw an 8x8 tile per
    -- character; a GBA cartridge draws its own text and its glyphs are
    -- neither square nor tile-sized -- Emerald's are 8 wide and 11 tall.  The
    -- page says what its cell is and the quads follow, so a font with a taller
    -- cell needs no other change anywhere.
    local cw = math.floor(tonumber(page.glyphWidth) or GLYPH)
    local ch = math.floor(tonumber(page.glyphHeight) or GLYPH)
    if cw < 1 or ch < 1 then cw, ch = GLYPH, GLYPH end
    local ok, img = pcall(Assets.image, page.image)
    if ok then
      local iw, ih = img:getDimensions()
      local minHeight = id == "extra" and 16 or 64
      if iw < 128 or ih < minHeight or iw % cw ~= 0 or ih % ch ~= 0 then
        ok = false
      end
    end
    if ok then
      local iw, ih = img:getDimensions()
      local perRow = page.glyphsPerRow or math.floor(iw / cw)
      local quads = {}
      for i = 0, perRow * math.floor(ih / ch) - 1 do
        quads[i] = love.graphics.newQuad((i % perRow) * cw,
          math.floor(i / perRow) * ch, cw, ch, iw, ih)
      end
      -- A PRE-TINTED PAGE carries its own colours.  Gen 1/2 atlases are
      -- black pixels on a transparent field, so a caller's setColor picks
      -- the ink; Emerald's glyphs are two-toned -- a dark letter with a
      -- light shadow under it, which is what makes GBA text read as text
      -- rather than as a black blob -- and multiplying that by the black
      -- every menu in this engine sets flattens the shadow into the letter.
      -- So such a page blits at full white and keeps the caller's ALPHA
      -- (fades still work); repainting it a single colour is what
      -- Font.beginTint is for and still happens through a pushed style.
      -- The flag is read off the page when the dataset carries it, and
      -- inferred from the font's own source line otherwise, so a cache
      -- extracted before this existed renders correctly too.
      local preTinted = page.preTinted
      if preTinted == nil and type(def.source) == "string" then
        preTinted = def.source:find("gFontNormalLatinGlyphs", 1, true) ~= nil
      end
      local entry = { id = id, image = img, quads = quads,
                      base = page.base, advance = page.advance or GLYPH,
                      cellWidth = cw, cellHeight = ch,
                      preTinted = preTinted or nil,
                      -- per-glyph advances, when the cartridge ships them;
                      -- unused while `advance` is fixed, and carried anyway
                      -- so a proportional pass has them to read
                      widths = type(page.widths) == "table" and page.widths
                               or nil }
      if faceName then
        entry.id = faceName
        state.faces[faceName] = entry
      else
        state.pages[id] = entry
        state.order[#state.order + 1] = entry
      end
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
  -- TYPOGRAPHIC FOLDS, so the port's own English does not lose characters to
  -- a cartridge font that never needed them.
  --
  -- Emerald's font carries the curly quotes and no straight ones: 4,513 of
  -- its strings use U+2019 and not one uses an ASCII apostrophe, so there is
  -- no glyph for `'` to find.  Every line this ENGINE writes is typed with
  -- straight quotes -- "You don't have enough money." and the rest -- and a
  -- character with no glyph is drawn as a SPACE, so those read "don t".
  --
  -- Aliasing rather than substituting: the fold only fills a hole.  A font
  -- that has its own `'` keeps it, because the alias is skipped when the
  -- sequence is already spoken for -- which is what leaves Gen 1 and Gen 2,
  -- whose fonts do carry the straight forms, exactly as they were.
  local FOLD = {
    ["'"] = "\226\128\153",   -- ' -> the right single quote
    ['"'] = "\226\128\157",   -- " -> the right double quote
  }
  local function seqCode(seq)
    for _, entries in pairs(state.byFirstByte) do
      for _, entry in ipairs(entries) do
        if entry.seq == seq then return entry.code end
      end
    end
  end
  for plain, curly in pairs(FOLD) do
    if not seqCode(plain) then
      local code = seqCode(curly)
      if code then bucket({ seq = plain, code = code }) end
    end
  end

  for _, entries in pairs(state.byFirstByte) do
    table.sort(entries, function(a, b) return #a.seq > #b.seq end)
  end
  -- The main+extra pair is a Gen 1/Gen 2 shape: `image` is the letters and
  -- `imageExtra` the box corners.  A font that declares neither -- Gen 3's,
  -- which is one page and draws its frame rather than tiling it -- is not
  -- half-loaded, so demanding both would have dropped a font that is entirely
  -- there onto LOVE's built-in raster.
  if def.image and def.imageExtra
     and not (state.pages.main and state.pages.extra) then
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
-- THE FACE IN FORCE.
--
-- Emerald sets different screens in different faces -- its dialogue in one,
-- its menus and its trainer card in narrower ones -- and they are the same
-- 512 glyph ids drawn differently, not different alphabets.  So a face is
-- pushed for a region of drawing the way a style is, and while one is pushed
-- every code resolves to it; with none pushed nothing changes and the page
-- chain answers as it always has.
local faceStack = {}

-- Push the named face for the drawing that follows.  Returns false when the
-- dataset has no such face, which is the answer for every Gen 1 and Gen 2
-- cache and for a Gen 3 one imported before the faces were found -- the
-- caller draws in the primary face and the screen is legible either way.
function Font.pushFace(name)
  local face = state and state.faces and state.faces[name]
  if not face then return false end
  faceStack[#faceStack + 1] = face
  return true
end

function Font.popFace()
  if #faceStack > 0 then faceStack[#faceStack] = nil end
end

-- what a face-aware caller uses to decide whether to bother
function Font.hasFace(name)
  return (state and state.faces and state.faces[name]) ~= nil
end

function Font.clearFaces() faceStack = {} end

local function pageFor(code)
  if not state then return nil end
  local face = faceStack[#faceStack]
  if face and face.quads[code - face.base] then return face end
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

-- ...AND THE ONE THAT KEEPS BOTH TONES.
--
-- Reported from play: "their names are looking a little too bold not matching
-- the rom".  The flat tint above is why.  A Gen 3 glyph page is baked in TWO
-- tones -- the letter, and its drop shadow one pixel down and right -- and
-- that shader takes the ALPHA and paints every opaque pixel one colour, so
-- recolouring a page turns letter and shadow into one solid shape.  That is a
-- letter a pixel thicker on two sides, which is exactly what bold looks like.
--
-- This one asks which tone a pixel IS and paints the two separately, so a
-- caller can restate the ink without restating the shape.  It is what the
-- cartridge's own `{COLOR n}` does: swap the letter's colour and leave the
-- shadow where it was.
local twoToneShader, twoTonePrev, twoToneDepth = nil, nil, 0

local function twoTone()
  if twoToneShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      extern vec4 inkColor;
      extern vec4 shadowColor;
      vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 t = Texel(tex, tc);
        // the letter is the DARK tone and the shadow the light one; the page
        // has no third, so a plain threshold tells them apart
        float lum = (t.r + t.g + t.b) / 3.0;
        vec4 pick = lum < 0.5 ? inkColor : shadowColor;
        return vec4(pick.rgb, t.a * pick.a * color.a);
      }
    ]])
    twoToneShader = ok and sh or false
  end
  return twoToneShader or nil
end

function Font.beginTwoTone(ink, shadow)
  local sh = twoTone()
  if not sh then return false end
  if twoToneDepth == 0 then
    twoTonePrev = love.graphics.getShader()
    love.graphics.setShader(sh)
  end
  twoToneDepth = twoToneDepth + 1
  pcall(sh.send, sh, "inkColor",
        { ink[1] or 0, ink[2] or 0, ink[3] or 0, ink[4] or 1 })
  pcall(sh.send, sh, "shadowColor",
        { shadow[1] or 0, shadow[2] or 0, shadow[3] or 0, shadow[4] or 1 })
  return true
end

function Font.endTwoTone()
  if not twoTone() or twoToneDepth == 0 then return end
  twoToneDepth = twoToneDepth - 1
  if twoToneDepth == 0 then
    love.graphics.setShader(twoTonePrev)
    twoTonePrev = nil
  end
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
  faceStack = {}
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
  if not quad then return end
  -- A PRE-TINTED PAGE CARRIES ITS OWN TWO TONES, so an ordinary draw blits it
  -- as it is rather than multiplying it by whatever colour a menu happened to
  -- set -- that is what `preTinted` is for.
  --
  -- ...UNLESS SOMETHING IS DELIBERATELY PAINTING IT.  Reported from play: "the
  -- pokemon names and lvls etc in battle are showing as white and blending
  -- with the background".  Font.drawCode's style path turns the tint shader on
  -- and sets the colour it wants, and this branch then threw that colour away
  -- and put white back -- and the shader takes its rgb from exactly that
  -- colour, so the glyph came out FLAT WHITE.  A pre-tinted page was the one
  -- kind of page a style could not paint, which is the one place it is needed:
  -- the healthbox, whose letters are not the dialogue's.
  if page.preTinted and tintDepth == 0 then
    local r, g, b, a = love.graphics.getColor()
    love.graphics.setColor(1, 1, 1, a or 1)
    love.graphics.draw(page.image, quad, x, y)
    love.graphics.setColor(r, g, b, a)
    return
  end
  love.graphics.draw(page.image, quad, x, y)
end

function Font.drawCode(code, x, y)
  local style = activeStyle
  local paint = borderPaint or (style and style.text)
  if not paint then return blitCode(code, x, y) end
  -- A style that names BOTH tones recolours without thickening; see
  -- Font.beginTwoTone.  Only a pre-tinted page has two tones to tell apart,
  -- so anything else falls through to the flat tint it always took.
  local shadow = (not borderPaint) and style and style.shadow
  local page = shadow and pageFor(code)
  if shadow and page and page.preTinted then
    local pr, pg, pb, pa = love.graphics.getColor()
    if Font.beginTwoTone(paint, shadow) then
      love.graphics.setColor(1, 1, 1, pa or 1)
      local quad = page.quads[code - page.base]
      if quad then love.graphics.draw(page.image, quad, x, y) end
      Font.endTwoTone()
      love.graphics.setColor(pr, pg, pb, pa)
      return
    end
    love.graphics.setColor(pr, pg, pb, pa)
  end
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

-- HOW TALL A DRAWN GLYPH ACTUALLY IS.
--
-- 8 for a Game Boy cache, because a Game Boy character is one tile.  Emerald's
-- dialogue face is FIFTEEN, and every piece of layout in this engine was
-- written against the 8 -- which is why the save panel's second line ran
-- through the bottom of its own window the moment the right face was loaded.
-- A layout that asks for this instead of assuming lays out correctly for both.
-- HOW TALL ONE LINE IS -- IN THE FACE THAT IS ACTUALLY IN FORCE.
--
-- This read state.order[1], the default page, and ignored the face stack
-- entirely.  Font.width does not: it measures through pageFor, which asks the
-- pushed face first.  So a screen that pushed a face got its WIDTHS from that
-- face and its HEIGHT from the dialogue one, and every layout that stacks
-- rows by glyph height was laying them out for a taller line than it drew.
--
-- The battle healthbox is the worst of them, because its arithmetic is exact.
-- The cartridge sets a healthbox in FONT_SMALL, eleven pixels tall, and the
-- foe's cream interior is nineteen: eleven plus the bar's eight is exactly
-- that, and the player's twenty-seven takes a third row of eleven with the
-- three that do not fit coming out of descender space.  Answering fifteen --
-- the dialogue face -- turned that three-pixel lift into eleven and pulled
-- the HP bar up into the name.
function Font.glyphHeight()
  if FALLBACK.enabled then return GLYPH end
  local face = faceStack[#faceStack]
  local page = face or (state and state.order and state.order[1])
  return (page and page.cellHeight) or GLYPH
end

-- how far the pen moves past a glyph; 8 unless its page says otherwise
-- HOW WIDE ONE GLYPH IS.
--
-- This returned the page's single fixed advance and ignored the per-glyph
-- widths sitting right beside it, which is a Game Boy assumption: Red's font
-- IS monospaced, so the two answers agree there and always have.
--
-- Emerald's is not.  Its width table runs from 3 to 10 pixels, and rendering
-- it at a flat 8 makes an 'i' as wide as a 'W' -- text comes out airy and
-- far wider than the cartridge draws it, and a line the wrapper thought fit
-- runs past the end of the box.  The widths were already being extracted and
-- carried; nothing read them.
--
-- Everything measures through here -- Font.width, Font.draw's pen, and
-- TextBox's own wrapping via spansFitting -- so one answer keeps the layout
-- and the drawing agreeing.  A page with no width table is unchanged.
function Font.advanceOf(code)
  local page = pageFor(code)
  if not page then return GLYPH end
  local widths = page.widths
  if widths then
    -- the table is written 1-based over the page's own code range
    local w = widths[code - (page.base or 0) + 1]
    if type(w) == "number" and w > 0 then return w end
  end
  return page.advance or GLYPH
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

-- `text` cut to fit `pixels`, with a trailing '.' when something was cut.
--
-- Measured through the font's own advances, which is the whole point: the
-- Gen 3 page is PROPORTIONAL, so counting characters and multiplying by 8
-- both over- and under-cuts depending on the name.  Every panel that puts a
-- name beside a level -- the healthbox, the party screen -- needs this, and
-- two copies of it would drift.
function Font.fit(text, pixels)
  local spans = Font.split(text or "")
  local n = Font.spansFitting(spans, pixels)
  if n >= #spans then return text or "" end
  local out = {}
  for i = 1, math.max(0, n - 1) do
    out[#out + 1] = (text or ""):sub(spans[i].from, spans[i].to)
  end
  return table.concat(out) .. "."
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

-- A FRAME THAT IS DRAWN RATHER THAN TILED.
--
-- Gen 1 and Gen 2 build a text box out of six glyphs at $79-$7E, and every
-- box in this engine is drawn that way.  A GBA cartridge has no such glyphs:
-- its window frame is its own graphic and its corners are rounded, so a font
-- record from one says `frame = "drawn"` and gets this instead -- the same
-- rectangle, with the cartridge's own two-tone edge, rather than six blanks
-- that would have left every box in the game an empty white hole.
local DRAWN_FRAME = {
  fill   = { 0.98, 0.98, 0.98 },
  edge   = { 0.36, 0.40, 0.51 },
  inner  = { 0.70, 0.74, 0.84 },
}

-- THE CARTRIDGE'S OWN FRAME, nine-sliced.
--
-- Emerald draws every box from a nine-tile border set -- four corners, four
-- edges and a fill -- and ships TWENTY of them for the player to choose
-- between on the OPTION screen. The extractor bakes all twenty into one
-- sheet, a 24x24 cell each, in the table's order; here the cell is cut into
-- its nine 8x8 tiles and laid out over the box.
--
-- Which of the twenty is the save's business, so the FRAME row on the OPTION
-- screen is an index into this and nothing more -- no reload, no second
-- record. A save that has never touched it gets frame 1, which is the
-- cartridge's default.
--
-- The `drawn` frame below stays as the fallback and is not dead code: a
-- dataset extracted before this existed has no frames record, and a box with
-- no border at all is worse than an approximate one.
local frameSheet = { image = nil, path = nil, quads = nil }

local function frameQuads(def)
  local frames = def and def.frames
  if not (frames and frames.image) then return nil end
  if frameSheet.path ~= frames.image then
    local ok, img = pcall(Assets.image, frames.image)
    frameSheet.image = ok and img or nil
    frameSheet.path = frames.image
    frameSheet.quads = nil
  end
  if not frameSheet.image then return nil end
  if not frameSheet.quads then
    local cell = frames.cell or 24
    local tile = frames.tile or 8
    local iw, ih = frameSheet.image:getDimensions()
    local quads = {}
    for frame = 0, (frames.count or 1) - 1 do
      local set = {}
      for row = 0, 2 do
        for col = 0, 2 do
          set[row * 3 + col + 1] = love.graphics.newQuad(
            col * tile, frame * cell + row * tile, tile, tile, iw, ih)
        end
      end
      quads[frame + 1] = set
    end
    frameSheet.quads = quads
  end
  return frameSheet.quads, frameSheet.image
end

-- Which frame this save is set to, clamped: an option written by a mod (or a
-- save carried from a build with more frames) must not index off the sheet.
local function frameIndex(def)
  local count = (def.frames and def.frames.count) or 1
  local ok, Game = pcall(require, "src.core.Game")
  local options = ok and Game and Game.save and Game.save.options
  local want = math.floor(tonumber(options and options.gen3Frame) or 1)
  if want < 1 then want = 1 end
  if want > count then want = count end
  return want
end

local function sheetFrame(tx, ty, tw, th)
  local def = state and state.def or {}
  local quads, image = frameQuads(def)
  if not quads then return false end
  local set = quads[frameIndex(def)]
  if not set then return false end
  local tile = (def.frames.tile) or 8
  local x, y = tx * 8, ty * 8
  love.graphics.setColor(1, 1, 1, 1)
  -- the middle is drawn first and the edges over it, so a box narrower or
  -- shorter than three tiles still has its corners intact
  for row = 0, th - 1 do
    for col = 0, tw - 1 do
      local r = (row == 0 and 0) or (row == th - 1 and 2) or 1
      local c = (col == 0 and 0) or (col == tw - 1 and 2) or 1
      love.graphics.draw(image, set[r * 3 + c + 1],
                         x + col * tile, y + row * tile)
    end
  end
  return true
end

local function drawnFrame(tx, ty, tw, th, style)
  local def = state and state.def or {}
  local theme = def.frameColors or DRAWN_FRAME
  local x, y = tx * 8, ty * 8
  local w, h = tw * 8, th * 8
  local fill = (style and style.fill) or theme.fill or DRAWN_FRAME.fill
  local edge = (style and style.border) or theme.edge or DRAWN_FRAME.edge
  local inner = theme.inner or DRAWN_FRAME.inner
  local a = fill[4] or 1
  love.graphics.setColor(fill[1], fill[2], fill[3], a)
  love.graphics.rectangle("fill", x + 1, y + 1, w - 2, h - 2)
  love.graphics.setColor(inner[1], inner[2], inner[3], a)
  love.graphics.rectangle("line", x + 1.5, y + 1.5, w - 3, h - 3)
  love.graphics.setColor(edge[1], edge[2], edge[3], edge[4] or 1)
  -- the corners are the rounded ones, so the four rules stop one pixel short
  love.graphics.rectangle("fill", x + 1, y, w - 2, 1)
  love.graphics.rectangle("fill", x + 1, y + h - 1, w - 2, 1)
  love.graphics.rectangle("fill", x, y + 1, 1, h - 2)
  love.graphics.rectangle("fill", x + w - 1, y + 1, 1, h - 2)
  love.graphics.setColor(1, 1, 1, 1)
end

-- Draw a Game Boy style bordered box in tile coordinates.
function Font.drawBox(tx, ty, tw, th)
  if not FALLBACK.enabled and state and state.def then
    -- the cartridge's own nine-slice first; the drawn rectangle is what a
    -- dataset without one falls back to
    if state.def.frames and sheetFrame(tx, ty, tw, th) then return end
    if state.def.frame == "drawn" or state.def.frame == "sheet" then
      return drawnFrame(tx, ty, tw, th, activeStyle)
    end
  end
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
  -- A frame may carve its edges finer than h/v: polished's textbox table
  -- (00:$0e1a) has distinct top/bottom rules and left/right rails, so the
  -- optional t/b/l/r keys override the shared pair when the font record
  -- sets them.  Crystal's six-piece frames never set them and draw as
  -- they always have.
  local top, bottom = B.t or B.h, B.b or B.h
  local left, right = B.l or B.v, B.r or B.v
  for i = 1, tw - 2 do
    Font.drawCode(top, (tx + i) * 8, ty * 8)
    Font.drawCode(bottom, (tx + i) * 8, (ty + th - 1) * 8)
  end
  for j = 1, th - 2 do
    Font.drawCode(left, tx * 8, (ty + j) * 8)
    Font.drawCode(right, (tx + tw - 1) * 8, (ty + j) * 8)
  end
  borderPaint = nil
end

return Font
