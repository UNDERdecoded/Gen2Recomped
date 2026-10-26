-- ROM-free source-resource regression. No cartridges or extracted art needed.
local Parts = require("src.import.Gen3SummaryParts")
local writes, pixels, encoded = 0, {}, 0
package.loaded["src.import.CacheFs"] = {
  write = function(path, bytes)
    assert(path:match("^assets/generated/ui/summary_"))
    assert(bytes == "png")
    writes = writes + 1
    return true
  end,
}
love = {
  image = {
    newImageData = function(w, h)
      local index = encoded + 1
      pixels[index] = { w = w, h = h }
      return {
        setPixel = function(_, x, y, r, g, b, a)
          if x == 0 and y == 0 then
            pixels[index].first = { r, g, b, a }
          end
        end,
        release = function() end,
        encode = function()
          encoded = encoded + 1
          return {
            getString = function()
              return "png"
            end,
          }
        end,
      }
    end,
  },
}
local function bytes(s)
  local t = {}
  for i = 1, #s do
    t[i] = s:byte(i)
  end
  return t
end
local function zeros(n)
  return string.rep("\0", n)
end
local spec = Parts.ROMS.BPEE0
local o = spec.offsets
local blobs = {
  [o.gSummaryScreen_Pal] = zeros(256),
  [o.gSummaryMoveSelect_Gfx] = zeros(1024),
  [o.gSummaryMoveSelect_Pal] = zeros(32),
  [o.gMoveTypes_Gfx] = zeros(23 * 256),
  [o.gMoveTypes_Pal] = zeros(96),
}
local raw = {
  [o.gPPTextPalette] = zeros(30),
  [o["pokemon_summary_screen.o:sTextColors"]] = zeros(39),
  [o["pokemon_summary_screen.o:sButtons_Gfx"]] = zeros(256),
  [o.sMonMarkings_Gfx] = zeros(2048),
  [o.sMarkings_Pal] = zeros(32),
}
local map = { [0xBB] = "A", [0xBC] = "B", [0x00] = " " }
local rom = {
  u8 = function(_, at)
    if at >= o.gSpeciesInfo and at <= o.gSpeciesInfo + 411 * 28 + 25 then
      return 0
    end
    if at >= o.sMoveTypeToOamPaletteNum and at < o.sMoveTypeToOamPaletteNum + 23 then
      return 13
    end
    error("Unexpected synthetic read " .. at)
  end,
  bytes = function(_, at, n)
    local s = assert(raw[at])
    assert(#s == n)
    return bytes(s)
  end,
  lz77 = function(_, at)
    return bytes(assert(blobs[at]))
  end,
}
local files, parts = Parts.resources(rom, o, "emerald")
assert(parts.images.buttons and parts.images.markings and parts.images.selector)
assert(parts.palette[143] and #parts.textColors == 39)
assert(pixels[1].w == 16 and pixels[1].h == 32 and pixels[1].first[4] == 0)
assert(pixels[2].w == 32 and pixels[2].h == 128)
assert(pixels[3].w == 16 and pixels[3].h == 128)
blobs[o.gMoveTypes_Gfx] = zeros(18 * 256)
assert(not pcall(Parts.badges, rom, o), "Missing contest frames accepted")
blobs[o.gMoveTypes_Gfx] = zeros(23 * 256)
local png, badges = Parts.badges(rom, o)
assert(png == "png" and badges.count == 23 and badges.width == 32)
blobs[o.gSummaryMoveSelect_Gfx] = zeros(32)
assert(not pcall(Parts.resources, rom, o, "emerald"), "Truncated selector accepted")
blobs[o.gSummaryMoveSelect_Gfx] = zeros(1024)
local at = 100
local text = { 0xF8, 9, 0xBB, 0xFC, 0x13, 8, 0, 0xF8, 0, 0xBC, 0xFF }
local reader = {
  rom = {
    u8 = function(_, p)
      return text[p - at + 1]
    end,
  },
  charmap = function()
    return map
  end,
}
assert(Parts.readWords(reader, at) == "{DPAD_RIGHT}A {A_BUTTON}B")
text = { 0x34, 0xF9, 8, 0xFC, 0x11, 1, 0xFF }
assert(Parts.readWords(reader, at) == "Lv№")
text = { 0xFC, 0x99, 0xFF }
assert(not pcall(Parts.readWords, reader, at))
text = { 0xF8, 0x77, 0xFF }
assert(not pcall(Parts.readWords, reader, at))
local unsupported = {
  rom = {
    u8 = function(_, p)
      if p == 0xBC then
        return 0
      end
      return string.byte("XXXX", p - 0xAC + 1)
    end,
  },
}
assert(not Parts.extract(unsupported) and writes == 0, "Unsupported ROM wrote cache")
local wrong = { rom = rom, version = "firered", manifest = { summaryPresentation = spec } }
assert(not pcall(Parts.extract, wrong) and writes == 0, "Wrong-game resources wrote cache")
-- Check the import publication path with a synthetic manifest and charmap.
local position = {}
for _, address in pairs(spec.words) do
  position[address] = true
end
local u8 = rom.u8
rom.u8 = function(self, p)
  if position[p] then
    return 0xBB
  elseif position[p - 1] then
    return 0xFF
  end
  return u8(self, p)
end
local extractor = {
  rom = rom,
  version = "emerald",
  manifest = { summaryPresentation = spec },
  charmap = function()
    return map
  end,
  write = function(self, name, c)
    assert(name == "constants")
    self.published = c
  end,
}
assert(
  Parts.extract(extractor)
    and writes == 4
    and extractor.published.gen3Summary.typeBadges.count == 23
)
assert(extractor.published.gen3Summary.words.cancel == "A")
print(
  "GEN3_SUMMARY_PARTS_TEST_OK compressed palettes, 23 badge frames, alpha/geometry, controls, source guards, cache publication"
)
