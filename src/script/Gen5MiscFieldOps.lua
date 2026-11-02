-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FOUR SMALL BLACK / WHITE SCRIPT OPS, READ FROM CODE (Black):
--
--   0x242 <record, slot> (ov21 0x021B6628): the nickname the trade record
--         `record` keeps (save block 0x43, 32 bytes a record, +4 the name,
--         +0x1A bit 0 present: 0x0200E740 / 0x0200E7AC) into string buffer
--         `slot`; an empty one when there is none. The records are what 0x120
--         copies at an NPC trade (Gen5TradeCommands keeps them in
--         save.gen5TradedAway) -- "I trained and trained the {VAR1} that you
--         traded me" (Z101), Z023
--   0x139 <var> (ov10 0x0215F1C8, task 0x0215F169): the var cleared, then a
--         wait on the wireless session (0x02189734): 1 ends it, 2 ends it
--         with the var 2. No wireless here, so it ends at once with 0
--         ("Ending communication. Please wait.", the Subway's link car)
--   0x23C (ov10 0x0216CC30 -> 0x0216CC40): word 0 of save block 0x34
--         (0x0200B3A4, at +0x5EC) set to 1 (Z235); kept as
--         save.gen5Block34 -- nothing here reads it yet
--   0x25E (ov10 0x0215F2DC -> 0x02012158 -> 0x02012BC8 -> 0x02008450): bit
--         0x400 of the C-Gear's state halfword cleared -- the C-Gear powered
--         off before the ferry (Z039) and the Battle Subway (Z075); 0x0215F2B8
--         reads the same bit into a var, 0x021A1012 checks it with the
--         C-Gear's (0x02009208). Kept as save.gen5CGearOn = false; this port
--         has no C-Gear screen to switch off
--   0x1A3 <n> (ov21 0x021B5650): the field camera (0x02188C58) set to record
--         ov56 0x021F36C8's table 0x021F42B0 [n - 1] = 0x1C + n - 1 of
--         /a/0/6/0 (0x0218E17C -> 0x0218E260) -- each Elite Four room's own
--         (Z140..Z143). Here it stands in for the map's camera until another
--         map is drawn (Gen4Camera.gen5Override); INFERRED: at once, as the
--         cartridge's set is

local M = {}

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local function G4() return require("src.script.Gen4Commands") end
local function val(ctx, v) return math.floor(tonumber(G4().valueOf(ctx, v)) or 0) end

function Commands.g5_buffer_traded_name(ctx, record, slot)
  if not ctx.game then return end
  local save = ctx.save or {}
  local mon = save.gen5TradedAway and save.gen5TradedAway[val(ctx, record) + 1]
  local text = ""
  if type(mon) == "table" then
    local data = ctx.game.data
    local def = data and data.pokemon and data.pokemon[mon.species]
    text = mon.nickname or (def and def.name) or ""
  end
  ctx.game.stringBuffers = ctx.game.stringBuffers or {}
  ctx.game.stringBuffers[val(ctx, slot) + 1] = text
end

function Commands.g5_wireless_end(ctx, var)
  local n = tonumber(var)
  if n and n >= 0x4000 then G4().setVar(ctx.save, n, 0) end
end

function Commands.g5_save_block34(ctx)
  if ctx.save then ctx.save.gen5Block34 = 1 end
end

function Commands.g5_cgear_off(ctx)
  if ctx.save then ctx.save.gen5CGearOn = false end
end

M.ROOM_CAMERA = { 0x1C, 0x1D, 0x1E, 0x1F }
function Commands.g5_room_camera(ctx, n)
  local idx = M.ROOM_CAMERA[val(ctx, n)]
  local data = ctx.game and ctx.game.data
  local cams = data and data.constants and data.constants.gen5Cameras
  local cam = idx and cams and cams.records and cams.records[idx + 1]
  local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
  if not (cam and def) then return end
  local Cam = require("src.render.Gen4Camera")
  Cam.gen5Override = { key = def.header or def.id, config = cam }
  Cam.generation = (Cam.generation or 0) + 1
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwbuffertradedname = L.bwbuffertradedname or function(ins, s) emit(s, { "g5_buffer_traded_name", ins.args[1], ins.args[2] }) end
  L.bwwirelessend = L.bwwirelessend or function(ins, s) emit(s, { "g5_wireless_end", ins.args[1] }) end
  L.bwsaveblock34 = L.bwsaveblock34 or function(_, s) emit(s, { "g5_save_block34" }) end
  L.bwcgearoff = L.bwcgearoff or function(_, s) emit(s, { "g5_cgear_off" }) end
  L.bwroomcamera = L.bwroomcamera or function(ins, s) emit(s, { "g5_room_camera", ins.args[1] }) end
end

return M
