-- THE DRESS-UP PHOTO COMMANDS (pt_photo round), Platinum and HGSS:
--
--   Platinum                       HGSS            what (READ FROM CODE)
--   ScrCmd_0A6 slot dest first     ScrCmd_154      sub_0203DAC0 / sub_0203F198: the
--                                                  dress-up app on party[slot]
--                                                  into photo 0; dest = 1 when the
--                                                  photo was saved, else 0
--                                                  (sub_0203DA64); `first` (var)
--                                                  = the explanation screen
--   ShowDressUpPhoto slot dest     ScrCmd_155      sub_02041DC8: NULL (dest 1) when
--                                                  the slot is empty, else dest 0
--                                                  and the frame viewer
--   0A8 slot dest                                  the same on the CONTEST photos
--   DressUpPhotoHasData slot dest  ScrCmd_255      ImageClips_DressUpPhotoHasData
--   ContestPhotoHasData slot dest                  sub_02029D2C
--   SetDressUpPhotoTitle word      ScrCmd_256      DressUpPhoto_SetTitle on photo 0
--
-- pokeplatinum src/scrcmd.c 2933-3205, src/unk_0203D1B8.c 816-909;
-- pokeheartgold src/scrcmd_c.c 1919-1963, src/launch_application.c 798-858.
-- `slot` / `first` of 0A6 / 154 are vars (ScriptContext_GetVar); the viewer's
-- and HasData's slot is a literal half-word. The store is
-- src/pokemon/Gen4Photos.lua, the app src/ui/Gen4PhotoDressUp.lua, the
-- viewer src/ui/Gen4PhotoViewer.lua.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, n) return math.floor(tonumber(G4().valueOf(ctx, n)) or 0) end
local function setVar(ctx, id, v) if id and ctx.save then G4().setVar(ctx.save, id, v) end end
local function Photos() return require("src.pokemon.Gen4Photos") end

function Commands.g4_photo_dress_up(ctx, slot, dest, first)
  setVar(ctx, dest, 0)
  local game = ctx.game
  local mon = ctx.save and ctx.save.party and ctx.save.party[valueOf(ctx, slot) + 1]
  if not (game and game.stack and mon) then return end
  local runner = ctx.runner
  local done = false
  game.stack:push(require("src.ui.Gen4PhotoDressUp").new(game, {
    mon = mon, firstTime = valueOf(ctx, first) == 1,
    onDone = function(saved)
      if done then return end
      done = true
      setVar(ctx, dest, saved and 1 or 0)
      if runner then runner:resume() end
    end,
  }))
  if runner and not done then runner:yield() end
end

function Commands.g4_photo_show(ctx, kind, slot, dest)
  local s = valueOf(ctx, slot)
  if not Photos().hasData(ctx.save, kind, s) then setVar(ctx, dest, 1) return end
  setVar(ctx, dest, 0)
  local game = ctx.game
  if not (game and game.stack) then return end
  local runner = ctx.runner
  local done = false
  game.stack:push(require("src.ui.Gen4PhotoViewer").new(game, { kind = kind, slot = s, onDone = function()
    if done then return end
    done = true
    if runner then runner:resume() end
  end }))
  if runner and not done then runner:yield() end
end

function Commands.g4_photo_has_data(ctx, kind, slot, dest)
  setVar(ctx, dest, Photos().hasData(ctx.save, kind, valueOf(ctx, slot)) and 1 or 0)
end

function Commands.g4_photo_set_title(ctx, word)
  Photos().setTitle(ctx.save, valueOf(ctx, word))
end

if Commands.meta then
  Commands.meta.g4_photo_dress_up = { foreground = true, blocking = true }
  Commands.meta.g4_photo_show = { foreground = true, blocking = true }
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  -- Platinum
  L["0a6"] = function(ins, s) emit(s, { "g4_photo_dress_up", ins.args[1], ins.args[2], ins.args[3] }) end
  L.showdressupphoto = function(ins, s) emit(s, { "g4_photo_show", "dressUp", ins.args[1], ins.args[2] }) end
  L["0a8"] = function(ins, s) emit(s, { "g4_photo_show", "contest", ins.args[1], ins.args[2] }) end
  L.dressupphotohasdata = function(ins, s) emit(s, { "g4_photo_has_data", "dressUp", ins.args[1], ins.args[2] }) end
  L.contestphotohasdata = function(ins, s) emit(s, { "g4_photo_has_data", "contest", ins.args[1], ins.args[2] }) end
  L.setdressupphototitle = function(ins, s) emit(s, { "g4_photo_set_title", ins.args[1] }) end
  -- HGSS (Goldenrod Tunnel's photo studio, D37R0102)
  L.scrcmd_154 = function(ins, s) emit(s, { "g4_photo_dress_up", ins.args[1], ins.args[2], ins.args[3] }) end
  L.scrcmd_155 = function(ins, s) emit(s, { "g4_photo_show", "dressUp", ins.args[1], ins.args[2] }) end
  L.scrcmd_255 = function(ins, s) emit(s, { "g4_photo_has_data", "dressUp", ins.args[1], ins.args[2] }) end
  L.scrcmd_256 = function(ins, s) emit(s, { "g4_photo_set_title", ins.args[1] }) end
end

return M
