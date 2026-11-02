-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE LIFT'S "CURRENT FLOOR" WINDOW -- Platinum's ShowCurrentFloor and
-- HGSS's ElevatorCurFloorBox.
--
-- PLATINUM (pokeplatinum src/overlay005/field_menu.c,
-- FieldMenu_ShowCurrentFloorWindow):
--
--     width  = 8 * Font_GetAttribute(FONT_SYSTEM, FONTATTR_MAX_LETTER_WIDTH)
--              -> 8 * 11 = 88 px -> 11 tiles (sFontAttributes, src/font.c)
--     Window_Add(BG_LAYER_MAIN_3, left, top, 11, CURRENT_FLOOR_WINDOW_HEIGHT 4)
--     Window_DrawStandardFrame
--     FieldMenuManager_PrintString(361 #15 "Current Floor", 0, 0)
--     FieldMenuManager_PrintString(361 #16 "{STRVAR_1}",   32, GLYPH_ROW_HEIGHT)
--
-- both in FONT_SYSTEM through the script's string template, so #16 prints the
-- floor `BufferFloorNumber` put in slot 0.  A SysTask then watches the var
-- the command was handed and takes the window down the frame it reads
-- 0xFFFF -- the `SetVar VAR_ELEVATOR_FLOORS_ABOVE, -1` every lift script
-- runs before its ride, its "same floor" and its "never mind".
--
-- HGSS (pokeheartgold asm/overlay_01_021EDAFC.s, PrintCurFloorInNewWindow):
-- the same 11 x 4 window (GetFontAttribute(0, 0) is sFontInfos[FONT_SYSTEM]
-- 0x0B), msg_0191 #16 "Current Floor" at (0, 0), then the floor line chosen
-- by ov01_021EE934(current map, floor):
--
--     map 441 (Goldenrod Dept. Store elevator) and floor 0 -> #122 "B1F" at x 32
--     map 443 / 444 (Celadon Condominiums' lifts) and floor 3 -> #125 "ROOF" at x 16
--     otherwise                                   -> #17 "{STRVAR_1}" at x 32
--
-- and the same 0xFFFF watch (ov01_021EE7B8).
--
-- The panel is kept on the overworld (`ow.gen4FloorWindow`) and drawn with the
-- money window's frame; `draw` is also the cartridge's SysTask, so the check
-- for 0xFFFF happens where the cartridge's does -- once a frame, on the var.

local M = {}

M.WIDTH_TILES = 11   -- 8 * maxLetterWidth 11 / 8
M.HEIGHT_TILES = 4   -- CURRENT_FLOOR_WINDOW_HEIGHT
M.ROW_PITCH = 16     -- GLYPH_ROW_HEIGHT

M.PLATINUM = { bank = 361, label = 15, floor = 16 }
M.HGSS = { bank = 191, label = 16, floor = 17, basement = 122, roof = 125 }
-- the HGSS maps ov01_021EE934 singles out (pokeheartgold constants/maps.h)
M.HGSS_GOLDENROD_LIFT = 441   -- MAP_GOLDENROD_DEPARTMENT_STORE_ELEVATOR (T25R1007)
M.HGSS_CONDO_LIFTS = { [443] = true, [444] = true }  -- MAP_CELADON_CONDOMINIUMS_*_ELEVATOR

local function hgss(data)
  local okV, GV = pcall(require, "src.core.GameVersion")
  if okV and GV.family and GV.family() == "hgss" then return true end
  local v = data and data.gen4_version
  return v and v.family == "hgss" or false
end

-- the floor line's (entry, x) on HGSS, by the CURRENT map's header
function M.hgssFloorLine(header, floor)
  local h = M.HGSS
  header, floor = tonumber(header), tonumber(floor)
  if header == M.HGSS_GOLDENROD_LIFT and floor == 0 then return h.basement, 32 end
  if header and M.HGSS_CONDO_LIFTS[header] and floor == 3 then return h.roof, 16 end
  return h.floor, 32
end

-- panelFor(game, left, top, var, floor, header) -> panel | nil
function M.panelFor(game, left, top, var, floor, header)
  if type(game) ~= "table" then return nil end
  local data = game.data
  local Gen4Text = require("src.import.Gen4Text")
  local bank, labelEntry, floorEntry, floorX
  if hgss(data) then
    bank, labelEntry = M.HGSS.bank, M.HGSS.label
    floorEntry, floorX = M.hgssFloorLine(header, floor)
  else
    bank, labelEntry, floorEntry, floorX = M.PLATINUM.bank, M.PLATINUM.label, M.PLATINUM.floor, 32
  end
  local label = Gen4Text.resolve(data, bank, labelEntry, game)
  local line = Gen4Text.resolve(data, bank, floorEntry, game)
  return {
    left = math.floor(tonumber(left) or 20),
    top = math.floor(tonumber(top) or 1),
    var = tonumber(var),
    label = (type(label) == "string" and label ~= "") and label or nil,
    floor = (type(line) == "string") and line or "",
    floorX = floorX,
    tilesW = M.WIDTH_TILES,
    tilesH = M.HEIGHT_TILES,
  }
end

-- the SysTask's test: the var the window watches reads 0xFFFF
function M.closed(panel, save)
  if not (panel and panel.var) then return false end
  local G4 = require("src.script.Gen4Commands")
  local v = tonumber(G4.getVar(save, panel.var)) or 0
  return v == -1 or v % 65536 == 0xFFFF
end

-- one frame: drop the panel when its var says so (returns false), else draw
function M.drawOn(ow, save)
  local panel = ow and ow.gen4FloorWindow
  if not panel then return false end
  if M.closed(panel, save) or (panel.map and ow.map and ow.map.id ~= panel.map) then
    ow.gen4FloorWindow = nil
    return false
  end
  return M.draw(panel)
end

function M.draw(panel)
  if type(panel) ~= "table" then return false end
  local Font = require("src.render.Font")
  local tw, th = panel.tilesW or M.WIDTH_TILES, panel.tilesH or M.HEIGHT_TILES
  local left, top = panel.left or 20, panel.top or 1
  Font.drawBox(left - 1, top - 1, tw + 2, th + 2)
  local x, y = left * 8, top * 8
  love.graphics.setColor(0, 0, 0, 1)
  if panel.label then Font.draw(panel.label, x, y) end
  if panel.floor and panel.floor ~= "" then
    Font.draw(panel.floor, x + (panel.floorX or 32), y + M.ROW_PITCH)
  end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

return M
