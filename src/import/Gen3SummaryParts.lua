-- Optional summary resources from the selected cartridge, not shipped images.
-- Offsets are gated by the GBA game code and software revision. Unsupported
-- sources keep the existing renderer. An address table may also be supplied by
-- a manifest's summaryPresentation field for another verified source build.
local S = {}
S.ROMS = {
  BPEE0 = {
    game = "emerald",
    offsets = {
      ["gSummaryScreen_Pal"] = 0xD9853C,
      ["gPPTextPalette"] = 0xD85620,
      ["pokemon_summary_screen.o:sTextColors"] = 0x61CD2C,
      ["gSpeciesInfo"] = 0x3203CC,
      ["pokemon_summary_screen.o:sButtons_Gfx"] = 0x61CD53,
      ["sMonMarkings_Gfx"] = 0x59E67C,
      ["sMarkings_Pal"] = 0x61D120,
      ["gSummaryMoveSelect_Gfx"] = 0xD97BEC,
      ["gSummaryMoveSelect_Pal"] = 0xD97CF4,
      ["gMoveTypes_Gfx"] = 0xD971B0,
      ["gMoveTypes_Pal"] = 0xD97B84,
      ["sMoveTypeToOamPaletteNum"] = 0x61CFDC,
    },
    words = {
      cancel = 0x5E8CF7,
      info = 0x5EA406,
      switch = 0x5EA3C8,
      level = 0x5E8D4D,
      number = 0x5E8D4F,
      accuracy = 0x5EA384,
      power = 0x5EA37E,
      appeal = 0x5EA38D,
      jam = 0x5EA394,
    },
  },
  BPRE0 = {
    game = "firered",
    offsets = { keypad = 0x1EA700 },
    words = {
      Cancel = 0x419C72,
      Page = 0x419C7B,
      PageCancel = 0x419C62,
      PageDetail = 0x419C82,
      Pick = 0x419CA2,
      PickSwitch = 0x419C92,
      PickDelete = 0x419CA9,
    },
  },
}
local function stringBytes(value)
  if type(value) == "string" then
    return value
  end
  local out = {}
  for i, v in ipairs(value) do
    out[i] = string.char(v)
  end
  return table.concat(out)
end
function S.resources(rom, offsets, game)
  local files, spec = {}, { images = {} }
  local function at(name)
    local v = assert(offsets[name], "Missing summary resource " .. name)
    return type(v) == "table" and v[1] or v
  end
  local function palette(raw)
    raw = stringBytes(raw)
    local p = {}
    for i = 0, #raw / 2 - 1 do
      local lo, hi = raw:byte(i * 2 + 1, i * 2 + 2)
      local c = lo + hi * 256
      assert(c < 32768, "Invalid summary RGB555 colour")
      p[i] = {
        math.floor((c % 32) * 255 / 31 + 0.5) / 255,
        math.floor((math.floor(c / 32) % 32) * 255 / 31 + 0.5) / 255,
        math.floor((math.floor(c / 1024) % 32) * 255 / 31 + 0.5) / 255,
        1,
      }
    end
    return p
  end
  local function image(key, raw, w, h, p, bank)
    raw = stringBytes(raw)
    assert(#raw >= w * h / 2, "Truncated summary sprite " .. key)
    local d = love.image.newImageData(w, h)
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local tile = math.floor(y / 8) * (w / 8) + math.floor(x / 8)
        local byte = assert(raw:byte(tile * 32 + (y % 8) * 4 + math.floor(x % 8 / 2) + 1))
        local ink = x % 2 == 0 and byte % 16 or math.floor(byte / 16)
        local c = p[(bank or 0) * 16 + ink] or { 0, 0, 0, 0 }
        d:setPixel(x, y, c[1], c[2], c[3], ink == 0 and 0 or (c[4] or 1))
      end
    end
    local path = "assets/generated/ui/summary_" .. key .. ".png"
    files[path] = d:encode("png"):getString()
    d:release()
    spec.images[key] = path
  end
  if game == "emerald" then
    local pal = palette(rom:lz77(at("gSummaryScreen_Pal")))
    spec.palette = pal
    assert(#stringBytes(rom:lz77(at("gSummaryScreen_Pal"))) == 256, "Invalid summary palette size")
    local pp = palette(rom:bytes(at("gPPTextPalette"), 30))
    for i = 0, 14 do
      pal[129 + i] = pp[i]
    end
    spec.textColors = rom:bytes(at("pokemon_summary_screen.o:sTextColors"), 39)
    if offsets.gSpeciesInfo then
      spec.noFlip = {}
      for i = 0, 411 do
        if rom:u8(at("gSpeciesInfo") + i * 28 + 25) >= 128 then
          spec.noFlip[i] = true
        end
      end
    end
    image("buttons", rom:bytes(at("pokemon_summary_screen.o:sButtons_Gfx"), 256), 16, 32, pal, 7)
    image(
      "markings",
      rom:bytes(at("sMonMarkings_Gfx"), 2048),
      32,
      128,
      palette(rom:bytes(at("sMarkings_Pal"), 32))
    )
    local raw = stringBytes(rom:lz77(at("gSummaryMoveSelect_Gfx")))
    assert(#raw == 1024, "Invalid selector shape")
    image("selector", raw, 16, #raw / 8, palette(rom:lz77(at("gSummaryMoveSelect_Pal"))))
  else
    -- FireRed text.c keypad icons, decoded from the selected source.
    local p = {
      [0] = { 0, 0, 0, 0 },
      [1] = { 1, 1, 1, 1 },
      [2] = { 98 / 255, 98 / 255, 98 / 255, 1 },
      [3] = { 213 / 255, 213 / 255, 205 / 255, 1 },
      [4] = { 230 / 255, 8 / 255, 8 / 255, 1 },
      [5] = { 1, 189 / 255, 115 / 255, 1 },
      [6] = { 32 / 255, 156 / 255, 8 / 255, 1 },
      [7] = { 148 / 255, 246 / 255, 148 / 255, 1 },
      [8] = { 49 / 255, 82 / 255, 205 / 255, 1 },
      [9] = { 164 / 255, 197 / 255, 246 / 255, 1 },
    }
    image("keypad", rom:bytes(at("keypad"), 2048), 128, 32, p)
  end
  return files, spec
end
function S.badges(rom, offsets)
  local function at(name)
    local row = assert(offsets[name], "Missing type sprite symbol: " .. name)
    return type(row) == "table" and row[1] or row
  end
  local raw = assert(rom:lz77(at("gMoveTypes_Gfx")))
  if type(raw) == "table" then
    local s = {}
    for i, v in ipairs(raw) do
      s[i] = string.char(v)
    end
    raw = table.concat(s)
  end
  local count = #raw / 256
  assert(count == math.floor(count) and count >= 23 and count <= 32, "Invalid type sprite geometry")
  local palette = assert(rom:lz77(at("gMoveTypes_Pal")))
  if type(palette) == "table" then
    local s = {}
    for i, v in ipairs(palette) do
      s[i] = string.char(v)
    end
    palette = table.concat(s)
  end
  assert(#palette >= 96, "Truncated type sprite palettes")
  local banks = at("sMoveTypeToOamPaletteNum")
  local image = love.image.newImageData(32, count * 16)
  for frame = 0, count - 1 do
    local bank = rom:u8(banks + frame) - 13
    assert(bank >= 0 and bank <= 2, "Invalid type sprite palette bank")
    for y = 0, 15 do
      for x = 0, 31 do
        local tile = math.floor(y / 8) * 4 + math.floor(x / 8)
        local value = raw:byte(frame * 256 + tile * 32 + (y % 8) * 4 + math.floor(x % 8 / 2) + 1)
        local ink = x % 2 == 0 and value % 16 or math.floor(value / 16)
        local offset = (bank * 16 + ink) * 2
        local lo, hi = palette:byte(offset + 1, offset + 2)
        local color = lo + hi * 256
        local r = color % 32
        local g = math.floor(color / 32) % 32
        local b = math.floor(color / 1024) % 32
        image:setPixel(
          x,
          frame * 16 + y,
          math.floor(r * 255 / 31 + 0.5) / 255,
          math.floor(g * 255 / 31 + 0.5) / 255,
          math.floor(b * 255 / 31 + 0.5) / 255,
          ink == 0 and 0 or 1
        )
      end
    end
  end
  local bytes = image:encode("png"):getString()
  image:release()
  return bytes,
    { image = "assets/generated/ui/summary_types.png", width = 32, height = 16, count = count }
end

function S.romKey(rom)
  local code = {}
  for i = 0, 3 do
    code[#code + 1] = string.char(rom:u8(0xAC + i))
  end
  return table.concat(code) .. tostring(rom:u8(0xBC))
end
-- Preserve keypad controls as tokens; decode lettering with the source's own
-- charmap. These short source labels use CLEAR_TO to space the button hints.
function S.readWords(extractor, at)
  local rom, map = extractor.rom, extractor:charmap()
  local out = {}
  local icons = {
    [0] = "A_BUTTON",
    [1] = "B_BUTTON",
    [6] = "DPAD_UP",
    [7] = "DPAD_DOWN",
    [8] = "DPAD_LEFT",
    [9] = "DPAD_RIGHT",
    [10] = "DPAD_UPDOWN",
    [11] = "DPAD_LEFTRIGHT",
    [12] = "DPAD_ANY",
  }
  local i = 0
  while i < 128 do
    local b = rom:u8(at + i)
    if b == 0xFF then
      return table.concat(out)
    end
    if b == 0xF8 then
      local tag = assert(icons[rom:u8(at + i + 1)], "Unknown summary keypad control")
      out[#out + 1] = "{" .. tag .. "}"
      i = i + 2
    elseif b == 0xF9 then
      local symbol = rom:u8(at + i + 1)
      out[#out + 1] = assert(
        ({ [5] = "Lv", [6] = "PP", [7] = "ID", [8] = "№" })[symbol],
        "Unknown summary extra symbol"
      )
      i = i + 2
    elseif b == 0x34 then
      out[#out + 1] = "Lv"
      i = i + 1
    elseif b == 0xFC then
      local cmd = rom:u8(at + i + 1)
      assert(cmd == 0x13 or cmd == 0x11, "Unsupported summary text control")
      i = i + 3
    else
      out[#out + 1] = assert(map[b], "Invalid summary lettering")
      i = i + 1
    end
  end
  error("Unterminated summary label")
end
function S.extract(extractor)
  local rom = extractor.rom
  local spec = (extractor.manifest or {}).summaryPresentation or S.ROMS[S.romKey(rom)]
  if not spec then
    return false
  end
  local version = type(extractor.version) == "table" and extractor.version.id or extractor.version
  assert(spec.game == version, "Summary source game mismatch")
  local files, parts = S.resources(rom, spec.offsets, spec.game)
  local words = {}
  for key, at in pairs(spec.words) do
    words[key] = S.readWords(extractor, at)
  end
  local types
  if spec.game == "emerald" then
    local png
    png, types = S.badges(rom, spec.offsets)
    files[types.image] = png
  end
  -- Decode and validate everything before changing the cache metadata.
  local CacheFs = require("src.import.CacheFs")
  for path, bytes in pairs(files) do
    assert(CacheFs.write(path, bytes), "Cannot write summary art")
  end
  local constants = extractor._constants or {}
  local rec = constants.gen3Summary or {}
  rec.parts, rec.words = parts, words
  rec.typeBadges = types or rec.typeBadges
  constants.gen3Summary = rec
  extractor._constants = constants
  extractor:write("constants", constants)
  return true
end
return S
