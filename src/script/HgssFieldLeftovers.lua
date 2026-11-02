-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- HEARTGOLD / SOULSILVER COMMANDS THAT WERE STEPPED OVER (`g4_unimplemented`)
-- although they matter to a single-player game, read off their handlers
-- (pokeheartgold src/scrcmd_c.c, src/scrcmd_move_relearner.c,
-- src/field/scrcmd_message.c):
--
--   ScrCmd_466 <dest> <slot>    MoveRelearner_IsValidMove over the mon's
--     eligible level-up moves: Blackthorn's Move Reminder asks it before
--     taking the Heart Scale (scr_seq_T30R0601) -- Platinum's
--     checkhaslearnableremindermoves
--   ScrCmd_527 <msg>            the script's own message printed in font 3,
--     FONT_UNOWN (ov01_021EF4DC with fontId 3): the stone panel's words in the
--     Ruins of Alph research centre (scr_seq_D24R0211, msg 4)
--   ScrCmd_528 <dest>           gSystem.unk6A, the Game Boy Advance slot's game
--     (sub_0201A4B0; 0 with none) -- the Pal Park lobby's gift man
--     (scr_seq_T08R0201_009) branches on 1..5. Platinum's
--     GetGBACartridgeVersion, 0 here
--   ScrCmd_538 <dest> <slot>    Save_EasyChat_SetRandomTrendySaying: a random
--     locked trendy (TOUGH) word unlocked and buffered, 0xFFFF when all 32
--     are (the Route 16 gate, scr_seq_R16R0101) -- Platinum's
--     trybufferandunlockrandomtoughword
--   ScrCmd_540 <dest>           Save_EasyChat_TrendySayingsUnlockedAllCheck --
--     Platinum's checkalltoughwordsunlocked
--   ScrCmd_805                  sub_02004B24(75): loads the SE_EVENT sound bank
--     and wave archive before the Kimono Girls' dance (D17R0110, D40R0107);
--     this port's sequences carry their own banks -- nothing to do
--   ScrCmd_491 <var>            reads a var pointer and returns (scrcmd_20.c)
--     -- nothing to do (Vermilion's PP Max man)
--
-- Loaded by Gen4ScriptVM (`install` with the lowering table).

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

local function G4v(ctx, n) return math.floor(tonumber(require("src.script.Gen4Commands").valueOf(ctx, n)) or 0) end

-- ScrCmd_527: the message in FONT_UNOWN
function Commands.g4_hgss_unown_message(ctx, bank, entry)
  local G4 = require("src.script.Gen4Commands")
  local T = require("src.import.Gen4Text")
  local label = T.label(math.floor(tonumber(G4.valueOf(ctx, bank)) or 0), math.floor(tonumber(G4.valueOf(ctx, entry)) or 0))
  return Commands.show_text(ctx, label, nil, { face = "unown" })
end

function Commands.g4_hgss_process_soundplate(ctx)
  local game = ctx.game
  local ow = ctx.overworld or (game and game.overworld)
  pcall(require("src.world.HgssSoundplates").process, game, ow, true)
end

-- ScrCmd_459: the Olivine Lighthouse's lamp (src/world/HgssLighthouse.lua),
-- two blocking halves around the script engine's own white fades
local TICKS_PER_FIELD_FRAME = 2
local function waitFrames(ctx, step)
  local runner = ctx.runner
  if not runner then while not step() do end return end
  local tick = 0
  runner.waitingCheck = function()
    tick = tick + 1
    if tick % TICKS_PER_FIELD_FRAME ~= 0 then return false end
    return step() and true or false
  end
  runner:yield()
end
function Commands.g4_hgss_lighthouse_flash(ctx)
  local L = require("src.world.HgssLighthouse")
  local ow = ctx.overworld or (ctx.game and ctx.game.overworld)
  L.startFlash(ctx.game, ow)
  waitFrames(ctx, function() return L.stepFlash(ctx.game) end)
end
function Commands.g4_hgss_lighthouse_lit(ctx)
  local L = require("src.world.HgssLighthouse")
  local ow = ctx.overworld or (ctx.game and ctx.game.overworld)
  local n = 0
  waitFrames(ctx, function()
    n = n + 1
    if n < L.LIT_WAIT then return false end
    L.lit(ctx.game, ow)
    return true
  end)
end
Commands.meta = Commands.meta or {}
Commands.meta.g4_hgss_lighthouse_flash = { foreground = true, blocking = true }
Commands.meta.g4_hgss_lighthouse_lit = { foreground = true, blocking = true }

-- CameronPhoto's Photo record (field_take_photo.c 527-547): the player's
-- name, the lead's nickname, how many are in the shot, where and when --
-- written onto the album entry g4_take_photo just added
function Commands.g4_hgss_photo_details(ctx)
  local save = ctx.save
  local album = save and save.hgssPhotoAlbum
  local p = album and album[#album]
  if not p or p.player then return end
  local party = save.party or {}
  local lead = party[1]
  local data = ctx.game and ctx.game.data
  p.player = save.player and save.player.name or ""
  p.lead = lead and (lead.nickname or ((data and data.pokemon and data.pokemon[lead.species]) or {}).name) or ""
  p.numMons = #party
  local d = os.date("*t")
  p.date = { year = d.year, month = d.month, day = d.day }
  p.hour, p.min = d.hour, d.min
  local ow = ctx.overworld or (ctx.game and ctx.game.overworld)
  if ow and ow.player then p.x, p.y = ow.player.cellX, ow.player.cellY end
end

-- OpenPhotoAlbum (src/ui/HgssPhotoAlbum.lua), the script waiting
function Commands.g4_hgss_photo_album(ctx)
  local game = ctx.game
  if not (game and game.stack) then return end
  game.stack:push(require("src.ui.HgssPhotoAlbum").new(game, function()
    if ctx.runner then ctx.runner:resume() end
  end))
  if ctx.runner then ctx.runner:yield() end
end

-- ScrCmd_681 <var> (asm/unk_020961D8.s): the easy chat editor in mode 2 on
-- the save's battle greeting (SaveMisc_GetBattleGreeting; a fresh one is
-- MailMsg_Init_WithBank 4, msg_0295); confirmed -> var 1 and
-- SaveMisc_SetBattleGreeting, cancelled -> var 0
function Commands.g4_hgss_battle_greeting(ctx, destVar)
  local game = ctx.game
  local G4 = require("src.script.Gen4Commands")
  if not (game and game.stack and ctx.save) then G4.setVar(ctx.save, destVar, 0) return end
  local Mail = require("src.pokemon.Gen4Mail")
  local cur = ctx.save.hgssBattleGreeting
  local msg = Mail.msgIsInit(cur) and Mail.copyMsg(cur) or Mail.msgWithBank(4)
  game.stack:push(require("src.ui.HgssMailScreen").new(game, { mode = "sentence", msg = msg, onDone = function(out)
    if out then
      ctx.save.hgssBattleGreeting = out
      G4.setVar(ctx.save, destVar, 1)
    else
      G4.setVar(ctx.save, destVar, 0)
    end
    if ctx.runner then ctx.runner:resume() end
  end }))
  if ctx.runner then ctx.runner:yield() end
end
Commands.meta.g4_hgss_photo_album = { foreground = true, blocking = true }
Commands.meta.g4_hgss_battle_greeting = { foreground = true, blocking = true }

-- THE MYSTRI STAGE (src/world/HgssSinjohStage.lua): MystriStageGymmickInit,
-- ScrCmd_820 <choice> (waits for the chosen model's turn), ScrCmd_819
function Commands.g4_hgss_sinjoh_init(ctx)
  if ctx.save then require("src.world.HgssSinjohStage").init(ctx.save) end
end
function Commands.g4_hgss_sinjoh_choose(ctx, choice)
  local SJ = require("src.world.HgssSinjohStage")
  if not (ctx.game and SJ.choose(ctx.game, choice)) then return end
  local runner = ctx.runner
  if not runner then SJ.waiting = nil return end
  runner.waitingCheck = function() return not SJ.waiting end
  runner:yield()
end
function Commands.g4_hgss_sinjoh_freeze(ctx)
  require("src.world.HgssSinjohStage").freeze()
end
Commands.meta.g4_hgss_sinjoh_choose = { foreground = true, blocking = true }

-- UnownCircle / ScrCmd_817 (src/world/HgssSinjohStage.lua cutscenes)
function Commands.g4_hgss_sinjoh_cut_load(ctx, kind, legend)
  local ow = ctx.overworld or (ctx.game and ctx.game.overworld)
  require("src.world.HgssSinjohStage").cutsceneLoad(ctx.game, ow, kind, legend and G4v(ctx, legend))
end
function Commands.g4_hgss_sinjoh_cut_run(ctx)
  local SJ = require("src.world.HgssSinjohStage")
  local runner = ctx.runner
  if not runner then SJ.cutsceneFree() return end
  runner.waitingCheck = function() return SJ.cutsceneTick() end
  runner:yield()
end
function Commands.g4_hgss_sinjoh_cut_free(ctx)
  require("src.world.HgssSinjohStage").cutsceneFree()
end
Commands.meta.g4_hgss_sinjoh_cut_run = { foreground = true, blocking = true }

local function emit(s, row) s.out[#s.out + 1] = row end

function M.install(L)
  L.scrcmd_466 = L.scrcmd_466 or function(ins, s) emit(s, { "g4_has_reminder_moves", ins.args[1], ins.args[2] }) end
  L.scrcmd_527 = L.scrcmd_527 or function(ins, s)
    local bank = s.bankFor and s.bankFor(s.member)
    if bank then emit(s, { "g4_hgss_unown_message", bank, ins.args[1] })
    else emit(s, { "g4_message", ins.args[1] }) end
  end
  L.scrcmd_528 = L.scrcmd_528 or function(ins, s) emit(s, { "g4_gba_cartridge", ins.args[1] }) end
  L.scrcmd_538 = L.scrcmd_538 or function(ins, s) emit(s, { "g4_unlock_tough_word", ins.args[1], ins.args[2] }) end
  L.scrcmd_540 = L.scrcmd_540 or function(ins, s) emit(s, { "g4_all_tough_words", ins.args[1] }) end
  L.scrcmd_805 = L.scrcmd_805 or function() end
  L.scrcmd_491 = L.scrcmd_491 or function() end
  L.cameronphoto = function(ins, s)
    emit(s, { "g4_take_photo", ins.args[1] })
    emit(s, { "g4_hgss_photo_details" })
  end
  L.openphotoalbum = L.openphotoalbum or function(_, s) emit(s, { "g4_hgss_photo_album" }) end
  L.scrcmd_681 = L.scrcmd_681 or function(ins, s) emit(s, { "g4_hgss_battle_greeting", ins.args[1] }) end
  -- ShowSaveStats / HideSaveStats (scrcmd_c.c): Platinum's save-info panel
  L.showsavestats = L.showsavestats or function(_, s) emit(s, { "g4_save_info", 1 }) end
  L.hidesavestats = L.hidesavestats or function(_, s) emit(s, { "g4_save_info", 0 }) end
  -- ScrCmd_492 <mode> <resultVar> <wordVar> (scrcmd_c.c -> sub_0203E960):
  -- one easy-chat word, 0xFFFF until picked -- Platinum's
  -- choosecustommessageword, now that Gen4EasyChat reads HGSS's own banks
  -- (HgssFieldQueries answered "cancelled" while the word lists were wrong)
  L.scrcmd_492 = function(ins, s) emit(s, { "g4_choose_message_word", ins.args[1], ins.args[2], ins.args[3] }) end
  -- ScrCmd_154 / 155 / 255 / 256 (the Goldenrod Tunnel photo studio) are
  -- src/script/Gen4PhotoCommands.lua's; an old save's `hgssPortrait.title`
  -- is carried into the photo store (Gen4Photos.store)
  L.mystristagegymmickinit = function(_, s) emit(s, { "g4_hgss_sinjoh_init" }) end
  -- the flashes: FADE_TYPE_BRIGHTNESS_OUT / IN to white, 2 steps x 1
  local function flash(s, dir) emit(s, { "g4_fade", dir, 2, 1, 0x7FFF }); emit(s, { "g4_wait_fade" }) end
  L.unowncircle = function(_, s)
    flash(s, 0)
    emit(s, { "g4_hgss_sinjoh_cut_load", "unown" })
    flash(s, 1)
    emit(s, { "g4_hgss_sinjoh_cut_run" })
    flash(s, 0)
    emit(s, { "g4_hgss_sinjoh_cut_free" })
    -- INFERRED: the Cinematic that follows comes back faded in
    flash(s, 1)
  end
  L.scrcmd_817 = function(ins, s)
    flash(s, 0)
    emit(s, { "g4_hgss_sinjoh_cut_load", "egg", ins.args[1] })
    flash(s, 1)
    emit(s, { "g4_hgss_sinjoh_cut_run" })
    emit(s, { "g4_hgss_sinjoh_cut_free" })
  end
  L.scrcmd_820 = function(ins, s) emit(s, { "g4_hgss_sinjoh_choose", ins.args[1] }) end
  L.scrcmd_819 = function(_, s) emit(s, { "g4_hgss_sinjoh_freeze" }) end
  L.scrcmd_459 = L.scrcmd_459 or function(_, s)
    emit(s, { "g4_hgss_lighthouse_flash" })
    emit(s, { "g4_fade", 0, 24, 2, 0x7FFF })
    emit(s, { "g4_wait_fade" })
    emit(s, { "g4_hgss_lighthouse_lit" })
    emit(s, { "g4_fade", 1, 18, 1, 0x7FFF })
    emit(s, { "g4_wait_fade" })
  end
  -- ProcessSoundplate (scrcmd_pokemon_misc.c): FieldSystem_ProcessSoundplate
  -- with the state wiped (src/world/HgssSoundplates.lua); answers nothing
  -- outside HGSS
  L.processsoundplate = function(_, s) emit(s, { "g4_hgss_process_soundplate" }) end
end

return M
