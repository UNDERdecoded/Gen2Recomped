-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT MAKES A PLATINUM MOVE BUTTON LOOK LIKE ITS MOVE.
--
-- `BattleSubscreen_DrawMoveSelectMenu` (pokeplatinum src/battle/
-- battle_subscreen.c) does four things to each of the four buttons the port
-- drew as one cream panel with a name on it:
--
--   * RECOLOURS it by the move's TYPE: `LoadMoveSelectPltt` copies a 16-colour
--     palette out of overlay 11's `sMovePaletteTable` (src/overlay011/
--     move_palettes.c) over sub-palette 8 + slot. Those palettes are code
--     data, not a graphics file -- read here through the table's own 18
--     pointers, since the palettes are NOT stored in type order.
--   * an EMPTY slot gets sub-palette 14 of the subscreen palette instead
--     (`LoadEmptyMoveSlotBg`) and no text.
--   * prints the name (FONT_SUBSCREEN, TEXT_COLOR(7,8,9) on OBJ palette 3),
--     a TYPE ICON, "PP" and "cur/max" (FONT_SYSTEM on OBJ palette 4), in a
--     colour from `GetPPTextColor`.
--
-- So this carries: the 18 type palettes, the empty one, the two text
-- palettes, and per button a MASK -- which of the button's pixels are drawn
-- from its slot sub-palette and with which entry -- made by composing the
-- `moves` tilemap with a coding palette. With the mask a button is repainted
-- in any type's colours entry for entry, exactly as the DS swaps palettes.

local Gen4MoveButtons = {}

Gen4MoveButtons.OVERLAY = 11
Gen4MoveButtons.TYPES = 18
Gen4MoveButtons.OBJ_ARCHIVE = "/battle/graphic/pl_batt_obj.narc"
Gen4MoveButtons.OBJ_PALETTE = 72          -- 7 sub-palettes into sub OBJ 0..6
Gen4MoveButtons.EMPTY_SUBPALETTE = 14     -- subscreenPaletteBuf[0xe * 16]
Gen4MoveButtons.SLOT_SUBPALETTE = 8       -- 8 + slot

-- `GetPPTextColor` -> (ink, shadow) indices into OBJ sub-palette 4.
function Gen4MoveButtons.ppColour(cur, max)
  cur, max = tonumber(cur) or 0, tonumber(max) or 0
  if cur == 0 then return 7, 8 end
  if max == cur then return 1, 2 end
  if max <= 2 then
    if cur == 1 then return 5, 6 end
  elseif max <= 7 then
    if cur == 1 then return 5, 6 end
    if cur == 2 then return 3, 4 end
  else
    if cur <= math.floor(max / 4) then return 5, 6 end
    if cur <= math.floor(max / 2) then return 3, 4 end
  end
  return 1, 2
end

local function u32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
local function rgb555(s, at)
  local a, b = s:byte(at + 1, at + 2)
  local v = a + b * 256
  local function x(n) return math.floor(n * 255 / 31 + 0.5) end
  return { x(v % 32), x(math.floor(v / 32) % 32), x(math.floor(v / 1024) % 32) }
end

-- The 18 palettes, by type, through `sMovePaletteTable`. Every one of them
-- opens RGB(13,14,29), RGB(31,31,31) -- which is how the table is recognised.
function Gen4MoveButtons.typePalettes(overlay, ram)
  if type(overlay) ~= "string" then return nil, "overlay 11 missing" end
  local size = #overlay
  local function pal(off)
    return off >= 0 and off + 32 <= size
      and overlay:byte(off + 1) == 0xCD and overlay:byte(off + 2) == 0x75
      and overlay:byte(off + 3) == 0xFF and overlay:byte(off + 4) == 0x7F
  end
  for at = 0, size - 72, 4 do
    local ok = true
    for i = 0, Gen4MoveButtons.TYPES - 1 do
      if not pal(u32(overlay, at + i * 4) - ram) then ok = false break end
    end
    if ok then
      local out = {}
      for i = 0, Gen4MoveButtons.TYPES - 1 do
        local off = u32(overlay, at + i * 4) - ram
        local p = {}
        for k = 0, 15 do p[k + 1] = rgb555(overlay, off + k * 2) end
        out[i] = p
      end
      return out, at
    end
  end
  return nil, "sMovePaletteTable not found"
end

-- One button's mask: a string of w*h bytes, 0 where the pixel is not drawn
-- from the slot's sub-palette, else the palette entry (1..15).
function Gen4MoveButtons.masks(Gen4Graphics, map, sheet, rects)
  local coding = {}
  for i = 1, 256 do coding[i] = { 0, 0, 0 } end
  for slot = 0, 3 do
    local base = (Gen4MoveButtons.SLOT_SUBPALETTE + slot) * 16
    for k = 1, 15 do coding[base + k + 1] = { 100 + slot, k * 10, 77 } end
  end
  local image = Gen4Graphics.compose(map, sheet, coding)
  if not (image and image.rgba) then return nil, "moves layer would not compose" end
  local out = {}
  for i, r in ipairs(rects) do
    local bytes = {}
    for y = r.y, r.y + r.h - 1 do
      for x = r.x, r.x + r.w - 1 do
        local at = (y * image.width + x) * 4
        local cr, cg, cb, ca = image.rgba:byte(at + 1, at + 4)
        local k = 0
        if ca and ca > 0 and cb == 77 and cr == 100 + (i - 1) then
          k = math.floor(cg / 10 + 0.5)
        end
        bytes[#bytes + 1] = string.char(k)
      end
    end
    out[i] = { x = r.x, y = r.y, w = r.w, h = r.h, index = table.concat(bytes) }
  end
  return out
end

-- extract(rom, subscreenArc, Gen4Graphics, Gen4Subscreen) -> the record.
function Gen4MoveButtons.extract(rom, subscreenArc, Gen4Graphics, Gen4Subscreen)
  local overlay, info = rom:overlay(Gen4MoveButtons.OVERLAY)
  local types, why = Gen4MoveButtons.typePalettes(overlay, info and info.ram or 0)
  if not types then return nil, why end
  local Narc = require("src.import.NarcArchive")
  local function member(arc, i)
    local bytes = arc and arc:get(i)
    if bytes and Gen4Graphics.isCompressed(bytes) then bytes = Gen4Graphics.decompress(bytes) end
    return bytes
  end
  local base = Gen4Graphics.palette(member(subscreenArc, Gen4Subscreen.PALETTE))
  local empty = {}
  for k = 1, 16 do
    empty[k] = base and base[Gen4MoveButtons.EMPTY_SUBPALETTE * 16 + k] or { 0, 0, 0 }
  end
  local objRaw = rom:read(Gen4MoveButtons.OBJ_ARCHIVE)
  local objArc = objRaw and Narc.parse(objRaw)
  local obj = objArc and Gen4Graphics.palette(member(objArc, Gen4MoveButtons.OBJ_PALETTE))
  local function sub(n)
    local p = {}
    for k = 1, 16 do p[k] = obj and obj[n * 16 + k] or { 0, 0, 0 } end
    return p
  end
  local movesLayer
  for _, l in ipairs(Gen4Subscreen.LAYERS) do if l.name == "moves" then movesLayer = l end end
  local map = Gen4Graphics.tilemap(member(subscreenArc, movesLayer.member))
  local sheet = Gen4Graphics.tiles(member(subscreenArc, Gen4Subscreen.TILES))
  if map then map.height = math.min(map.height or 256, Gen4Subscreen.HEIGHT) end
  local rects = {}
  for i = 1, 4 do rects[i] = Gen4Subscreen.MOVE_BUTTONS[i] end
  local masks, mwhy = map and sheet and Gen4MoveButtons.masks(Gen4Graphics, map, sheet, rects)
  if not masks then return nil, mwhy or "moves tilemap missing" end
  return { types = types, empty = empty, masks = masks,
           text = { action = sub(2), name = sub(3), pp = sub(4) } }
end

return Gen4MoveButtons
