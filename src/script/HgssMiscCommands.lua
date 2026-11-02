-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- HEARTGOLD / SOULSILVER'S UNNAMED FIELD COMMANDS that were reaching the
-- `g4_unimplemented` path, read off their handlers (pokeheartgold
-- src/scrcmd_c.c, src/field/scrcmd_pokemon_misc.c, src/sys_vars.c,
-- src/save_pokegear.c):
--
--   ScrCmd_344 <objVar> <dirVar>   ov01_021F9408: MapObject_SetFacingDirection
--     on the object -- the Ruins of Alph research centre turning its scientist
--     to the player after the warp in (D24R0211), T03R0101, the link rooms
--   ScrCmd_546 <mode u8> <dest>    sub_02066BC0: whether VAR_UNK_4043 + mode
--     holds the distribution's magic number (_020FE4A4: 0x06F2, 0xAD7C) --
--     Pewter's Enigma Stone event (T03, T03R0101). A var-writer: unlowered,
--     the script compared a var nothing wrote
--   ScrCmd_811 <itemDest> <qtyDest> PhoneCallPersistentState_MomGiftQueue_Peek
--     (queue slot 0): the item into the first var, the quantity into the
--     second -- 0 / 0 on an empty queue (scr_seq_0144, Mom's deliveries)
--   ScrCmd_812                     MomGiftQueue_Get: drop slot 0, shift the
--     other four up
--
-- The gift queue is `save.hgssMomGifts` (MomGiftCheck's reader in
-- Gen4Commands), a list of { item = id, quantity = n }, front first.
--
-- Loaded by Gen4ScriptVM (`install` with the lowering table).

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, n) return math.floor(tonumber(G4().valueOf(ctx, n)) or 0) end
local function setVar(ctx, id, v) G4().setVar(ctx.save, id, v) end
local function getVar(ctx, id)
  local G = G4()
  if G.getVar then return math.floor(tonumber(G.getVar(ctx.save, id)) or 0) end
  return valueOf(ctx, id)
end

M.VAR_UNK_4043 = 0x4043
M.MAGIC = { [0] = 0x06F2, [1] = 0xAD7C }

function Commands.g4_hgss_var_magic(ctx, mode, destVar)
  local m = math.floor(tonumber(mode) or 0)
  local want = M.MAGIC[m]
  local have = want and getVar(ctx, M.VAR_UNK_4043 + m)
  setVar(ctx, destVar, (want and have == want) and 1 or 0)
end

local function queue(ctx)
  local q = ctx.save and ctx.save.hgssMomGifts
  return type(q) == "table" and q or nil
end

function Commands.g4_hgss_mom_gift_peek(ctx, itemVar, qtyVar)
  local q = queue(ctx)
  local front = q and q[1]
  local item = front and math.floor(tonumber(front.item or front[1]) or 0) or 0
  local qty = front and math.floor(tonumber(front.quantity or front[2]) or 0) or 0
  setVar(ctx, itemVar, item)
  setVar(ctx, qtyVar, qty)
end

function Commands.g4_hgss_mom_gift_pop(ctx)
  local q = queue(ctx)
  if q and #q > 0 then table.remove(q, 1) end
end

-- THE SAFARI ZONE'S OBJECTS (overlay_03_scrcmds.c; src/world/HgssSafariObjects.lua):
--   ScrCmd_718 <slot u8> <idVar>   BufferSafariZoneObjectName (msg_0430 14 + id)
--   ScrCmd_719 <idDest> <indexDest> ov02_0224E754: the object of area set 0 on
--     the tile in front of the player -- its id (255 for none) and its index
--   ScrCmd_720 <indexVar>          SafariZone_RemoveObjectFromArea in the area
--     the tile in front is in (the props it culls are not drawn here)
local function frontTile(ctx)
  local ow = ctx.overworld or (ctx.game and ctx.game.overworld)
  local p = ow and ow.player
  local def = ow and ow.map and ow.map.def
  if not p then return nil end
  local dx, dy = 0, 0
  local f = p.facing or p.dir
  if f == "up" then dy = -1 elseif f == "down" then dy = 1 elseif f == "left" then dx = -1 elseif f == "right" then dx = 1 end
  local lx = (p.cellX or math.floor((p.px or 0) / 16)) + dx
  local ly = (p.cellY or math.floor((p.py or 0) / 16)) + dy
  return (def and def.originX or 32) + lx, (def and def.originY or 32) + ly
end

function Commands.g4_hgss_safari_object_name(ctx, slot, idVar)
  local game = ctx.game
  if not game then return end
  local name = require("src.world.HgssSafariObjects").objectName(game.data, game, valueOf(ctx, idVar))
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[math.floor(tonumber(slot) or 0) + 1] = name
end

function Commands.g4_hgss_safari_object_front(ctx, idVar, indexVar)
  local gx, gz = frontTile(ctx)
  local id, index = 255, 0
  if gx and ctx.save then id, index = require("src.world.HgssSafariObjects").objectAt(ctx.save, gx, gz) end
  setVar(ctx, indexVar, index)
  setVar(ctx, idVar, id)
end

function Commands.g4_hgss_safari_object_remove(ctx, indexVar)
  local gx, gz = frontTile(ctx)
  if not (gx and ctx.save) then return end
  local Obj = require("src.world.HgssSafariObjects")
  local _, _, area = Obj.objectAt(ctx.save, gx, gz)
  Obj.removeObject(ctx.save, area or 0, valueOf(ctx, indexVar))
  -- the prop culled and the land's collision back (HgssSafariProps)
  pcall(function() require("src.world.HgssSafariProps").changed(ctx.game) end)
end

-- THE SAFARI ZONE'S TWO APPS AND THE PLACEMENT CHECK (overlay_03_scrcmds.c):
--   ScrCmd_716            SafariAreaCustomizer_LaunchApp (overlay 108): the
--     six areas of set 0 rearranged; FLAG_UNK_99D says whether anything
--     changed (src/ui/HgssSafariCustomizer.lua)
--   ScrCmd_717 <resultVar> sub_02097720 -> SafariDecoration_LaunchApp: the
--     object placed, its id into the var (255 for none)
--     (src/ui/HgssSafariDecoration.lua)
--   ScrCmd_721 <resultVar> ov02_0224E698 (src/world/HgssSafariPlace.lua)
local function blockOn(ctx, state)
  local game = ctx.game
  if not (game and game.stack and state) then return end
  game.stack:push(state)
  if ctx.runner then ctx.runner:yield() end
end

function Commands.g4_hgss_safari_customizer(ctx)
  local game = ctx.game
  if not (game and game.stack and ctx.save) then return end
  local UI = require("src.ui.HgssSafariCustomizer")
  blockOn(ctx, UI.new(game, function()
    if ctx.runner then ctx.runner:resume() end
  end))
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_hgss_safari_customizer = { foreground = true, blocking = true }

function Commands.g4_hgss_safari_decoration(ctx, resultVar)
  local game = ctx.game
  if not (game and game.stack and ctx.save) then
    setVar(ctx, resultVar, 255)
    return
  end
  local ow = ctx.overworld or game.overworld
  local Place = require("src.world.HgssSafariPlace")
  local args = Place.decorationArgs(ow, ctx.save)
  local UI = require("src.ui.HgssSafariDecoration")
  blockOn(ctx, UI.new(game, args, function(id)
    setVar(ctx, resultVar, id or 255)
    if id and id ~= 255 then
      pcall(function() require("src.world.HgssSafariProps").changed(game) end)
    end
    if ctx.runner then ctx.runner:resume() end
  end))
end
Commands.meta.g4_hgss_safari_decoration = { foreground = true, blocking = true }

function Commands.g4_hgss_safari_place_check(ctx, resultVar)
  local ow = ctx.overworld or (ctx.game and ctx.game.overworld)
  local r = 0
  if ctx.save then r = require("src.world.HgssSafariPlace").precheck(ow, ctx.save) end
  setVar(ctx, resultVar, r)
end

function M.install(L)
  L.scrcmd_718 = L.scrcmd_718 or function(ins, st)
    st.out[#st.out + 1] = { "g4_hgss_safari_object_name", ins.args[1], ins.args[2] }
  end
  L.scrcmd_719 = L.scrcmd_719 or function(ins, st)
    st.out[#st.out + 1] = { "g4_hgss_safari_object_front", ins.args[1], ins.args[2] }
  end
  L.scrcmd_720 = L.scrcmd_720 or function(ins, st)
    st.out[#st.out + 1] = { "g4_hgss_safari_object_remove", ins.args[1] }
  end
  L.scrcmd_716 = L.scrcmd_716 or function(_, st)
    st.out[#st.out + 1] = { "g4_hgss_safari_customizer" }
  end
  L.scrcmd_717 = L.scrcmd_717 or function(ins, st)
    st.out[#st.out + 1] = { "g4_hgss_safari_decoration", ins.args[1] }
  end
  L.scrcmd_721 = L.scrcmd_721 or function(ins, st)
    st.out[#st.out + 1] = { "g4_hgss_safari_place_check", ins.args[1] }
  end
  L.scrcmd_344 = L.scrcmd_344 or function(ins, st)
    st.out[#st.out + 1] = { "g4_face_dir", ins.args[1], ins.args[2] }
  end
  L.scrcmd_546 = L.scrcmd_546 or function(ins, st)
    st.out[#st.out + 1] = { "g4_hgss_var_magic", ins.args[1], ins.args[2] }
  end
  L.scrcmd_811 = L.scrcmd_811 or function(ins, st)
    st.out[#st.out + 1] = { "g4_hgss_mom_gift_peek", ins.args[1], ins.args[2] }
  end
  L.scrcmd_812 = L.scrcmd_812 or function(_, st)
    st.out[#st.out + 1] = { "g4_hgss_mom_gift_pop" }
  end
end

return M
