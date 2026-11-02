-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- PLATINUM FIELD COMMANDS THAT WERE A NO-OP, A FALLBACK OR MISSING, read off
-- their handlers in pokeplatinum (2026-11-01 pt_cmd audit; coverage scan in
-- G:/Gen2Recomped/scratch_claude/pt_cmds). Each row below names its source.
--
--   CallTVBroadcast / CallTVInterview / ScrCmd_27C   -> src/script/PtTvBroadcast.lua
--   ScrCmd_29F <mode var>        the camera quake (ov6_0223E384 / ov6_0223E4EC)
--   ScrCmd_0B3 / ScrCmd_2F6 / TryStartGTSApp / ScrCmd_2F7 / ScrCmd_30E
--                                the Global Terminal's Wi-Fi gates
--   TryRecordChatotCry / StopRecordingChatotCry / StoreRecordedChatotCry /
--   SetPokemonPreviewAnim / WaitPokemonPreviewAnim   the Chatot cry recorder
--   ShowBattleHallRecordMonSelectionMenu            the Frontier records' list
--   SetScenePlayBGMMusicBox / SetFieldScene         the Villa's music box
--   GetBattleFrontierReporterPosition               the Frontier TV reporter
--   DoGroupConnectionAction                         the Jubilife groups NPC
--   Dummy19E / Dummy316 / Dummy14F                  cartridge dummies
--
-- Loaded by Gen4ScriptVM (`install` with the lowering table). A row that was
-- already lowered elsewhere is replaced only where this file says why.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
Commands.meta = Commands.meta or {}

local M = {}

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, n) return math.floor(tonumber(G4().valueOf(ctx, n)) or 0) end
local function setVar(ctx, id, v) if id then G4().setVar(ctx.save, id, v) end end

local function row(s, r) s.out[#s.out + 1] = r end

-- ---------------------------------------------------------------------------
-- ScrCmd_29F <mode>: THE QUAKE. pokeplatinum scrcmd.c ScrCmd_29F ->
-- overlay006/ov6_0223E140.c. Both modes build the camera shaker
-- (ov6_0223FE1C: a copy of the camera tracks a target offset from the real
-- one; SEQ_SE_DP_CLIMAX09 plays) and the script waits for the field task.
--
--   mode 0  ov6_0223E384: amplitude x = 2.0, y = 0, ramp 1 frame, 16 cycles
--   else    ov6_0223E4EC: amplitude x = 4.0, ramp 1 frame, 24 cycles, run by
--           ov6_0223E408: Sound_FadeOutBGM(0, 1), wait for the fade, 16 frames,
--           SEQ_SE_DP_FW089, the shake with its amplitude cut by 1/8 every
--           time a cycle ends (ov6_0223E3D8), Sound_StopEffect(1628), 16
--           frames, Sound_FadeInBGM(127, 16), wait for the fade.
--
-- One cycle of ov6_0223FE9C with a 1-frame ramp is four frames: +A, 0, -A, 0
-- on the target's x. The offset is world units (FX32_ONE, 16 to a tile),
-- which is this port's pixels; `ow.gen4ShakeOffset` is the same nudge HGSS's
-- ScreenShake uses (OverworldState:followCamera).
-- ---------------------------------------------------------------------------
M.SE_CLIMAX09 = 1749   -- SEQ_SE_DP_CLIMAX09 (pl_sound_data.json seqInfo index)
M.SE_FW089 = 1628      -- SEQ_SE_DP_FW089 (the Sound_StopEffect(1628) literal)

-- The x offsets of one run, frame by frame, as ov6_0223FE9C produces them.
function M.quakeFrames(mode)
  local amp = (mode == 0) and 2.0 or 4.0
  local cycles = (mode == 0) and 16 or 24
  local decay = mode ~= 0
  local out = {}
  for c = 1, cycles do
    out[#out + 1] = amp; out[#out + 1] = 0; out[#out + 1] = -amp; out[#out + 1] = 0
    -- ov6_0223E3D8 runs after each ov6_0223FE9C step and sees unk_48 drop
    -- when a cycle closes: the next cycle's amplitude is amp - amp / 8
    if decay then amp = amp - amp / 8 end
  end
  return out
end

function Commands.pt_quake(ctx, mode)
  local ow, runner = ctx.overworld, ctx.runner
  local m = valueOf(ctx, mode)
  pcall(Commands.play_sound, ctx, M.SE_CLIMAX09)
  if not (ow and runner) then return end
  local Music = require("src.core.Music")
  local frames = M.quakeFrames(m)
  local stage = (m == 0) and "shake" or "fadeout"
  local i, wait = 0, 0
  runner.waitingCheck = function()
    if stage == "fadeout" then
      if Music.dsFade then Music.dsFade(0, 1) end
      stage = "fadewait"
      return false
    elseif stage == "fadewait" then
      if not (Music.dsFading and Music.dsFading()) then stage, wait = "pause", 16 end
      return false
    elseif stage == "pause" then
      wait = wait - 1
      if wait <= 0 then
        stage = "shake"
        pcall(Commands.play_sound, ctx, M.SE_FW089)
      end
      return false
    elseif stage == "shake" then
      i = i + 1
      if i > #frames then
        ow.gen4ShakeOffset = nil
        if m == 0 then return true end
        pcall(function() require("src.core.Sound").stop(M.SE_FW089) end)
        stage, wait = "after", 16
        return false
      end
      ow.gen4ShakeOffset = { frames[i], 0 }
      return false
    elseif stage == "after" then
      wait = wait - 1
      if wait <= 0 then
        if Music.dsFade then Music.dsFade(1, 16, 0) end
        stage = "fadein"
      end
      return false
    elseif stage == "fadein" then
      return not (Music.dsFading and Music.dsFading())
    end
    return true
  end
  runner:yield()
end
Commands.meta.pt_quake = { blocking = true }

-- ---------------------------------------------------------------------------
-- THE GLOBAL TERMINAL'S WI-FI GATES (scrcmd.c). Every one of them asks
-- WiFiList_HasValidLogin first and this port has no Wi-Fi list, so each takes
-- its "no valid login" arm -- which is what the script then branches on.
--
--   ScrCmd_0B3 <dest>            sub_0207DDE0: the Nintendo WFC setup app
--     (ov65), whose result lands in dest; with no login it never connects, so
--     0 (INFERRED: the app's own answer without a connection)
--   ScrCmd_2F6 <a> <b> <dest>    dest = FALSE without a login (READ)
--   TryStartGTSApp <conn> <dest> dest = FALSE without a login (READ)
--   ScrCmd_2F7 <var>             does nothing without a login (READ)
--   ScrCmd_30E <dest>            sub_0209B344: the Union Room greeting
--     sentence editor; cancelled (INFERRED: 0 into dest)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- THE CHATOT CRY RECORDER (scrcmd_sound.c): TryRecordChatotCry writes TRUE
-- only when Sound_StartRecordingChatotCry gets the microphone. There is no
-- microphone here, so FALSE, and RecordChatotCry_FailedToLearnSaying (READ).
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- ShowBattleHallRecordMonSelectionMenu <type> <letters> <result> <listPos>
-- <cursor> (ov5_021F6454.c), READ: the species of zukan_data member
-- sAlphabeticalSpeciesLists[letters] (18..26: the dex's ABC .. YZ lists,
-- imported as data.gen4_dex.orders.ABC .. YZ) that have a Battle Hall record
-- for the challenge (BattleHallWinRecords_GetRecordForSpecies != 0), species
-- names from bank 412, then EXIT (menu bank, MenuEntries_Text_ListMenu_Exit
-- = 12) = MENU_CANCEL; the window at tile (20, 1); the pick (a species id)
-- into <result>. The list-position / cursor vars are not kept (the port's
-- menu opens on its first row).
-- ---------------------------------------------------------------------------
M.HALL_LETTER_KEYS = { [0] = "ABC", "DEF", "GHI", "JKL", "MNO", "PQR", "STU", "VWX", "YZ" }
M.SPECIES_BANK = 412
M.MENU_EXIT_LINE = 12
function M.hallRecordSpecies(data, save, challenge, letters)
  local orders = data and data.gen4_dex and data.gen4_dex.orders
  local list = orders and orders[M.HALL_LETTER_KEYS[letters] or ""]
  local out = {}
  if type(list) ~= "table" then return out end
  local recs = require("src.script.Gen4BattleHallLobby").records(save, challenge)
  for _, sp in ipairs(list) do
    if (tonumber(recs[sp]) or 0) ~= 0 then out[#out + 1] = sp end
  end
  return out
end
function Commands.pt_hall_record_menu(ctx, challenge, letters, resultVar)
  local data = ctx.game and ctx.game.data
  local Text = require("src.import.Gen4Text")
  local species = M.hallRecordSpecies(data, ctx.save, valueOf(ctx, challenge), valueOf(ctx, letters))
  local rows = {}
  for _, sp in ipairs(species) do
    rows[#rows + 1] = { text = data.text[Text.label(M.SPECIES_BANK, sp)] or ("#" .. sp), value = sp }
  end
  local Bands = require("src.import.Gen4ScriptBands")
  rows[#rows + 1] = { text = data.text[Text.label(Bands.MENU_ENTRIES_BANK, M.MENU_EXIT_LINE)] or "EXIT",
                      value = M.MENU_CANCEL }
  ctx.g4Menu = { anchorX = 20, anchorY = 1, destVar = resultVar, cancelable = true, cursor = 1, rows = rows }
  return Commands.g4_menu_show(ctx)
end
Commands.meta.pt_hall_record_menu = { foreground = true, blocking = true }

M.MENU_CANCEL = 0xFFFE

-- ---------------------------------------------------------------------------
-- THE VILLA'S MUSIC BOX (scrcmd_sound.c):
--   SetScenePlayBGMMusicBox  Sound_SetSceneAndPlayBGM(VILLA_MUSIC_BOX,
--                            SEQ_PL_TOWN02, 1) -- seq 1218
--   SetFieldScene <bgm var>  Sound_SetSceneAndPlayBGM(FIELD, bgm, 1): the
--                            script hands back the GetCurrentBGM it saved
-- ---------------------------------------------------------------------------
M.SEQ_PL_TOWN02 = 1218
function Commands.pt_play_bgm(ctx, bgm)
  local id = valueOf(ctx, bgm)
  if id and id > 0 then Commands.play_music(ctx, id) end
end

-- ---------------------------------------------------------------------------
-- GetBattleFrontierReporterPosition <x> <z> <dir> <movementType>
-- (scrcmd_tv_broadcast.c): a switch on the TV broadcast's pending interview
-- (sub_0202E81C(broadcast)->unk_01). This port records no interviews, which
-- is the `default` arm: (47, 21), DIR_NORTH, MOVEMENT_TYPE_LOOK_NORTH (14).
-- Behind CheckTVInterviewEligible = FALSE, so not reached today.
-- ---------------------------------------------------------------------------
function Commands.pt_frontier_reporter_pos(ctx, xVar, zVar, dirVar, typeVar)
  setVar(ctx, xVar, 47); setVar(ctx, zVar, 21)
  setVar(ctx, dirVar, 0); setVar(ctx, typeVar, 14)
end

-- ---------------------------------------------------------------------------
-- DoGroupConnectionAction <action> ... (scrcmd_group_connection.c): the
-- groups of the record-mixing RNG. This port keeps no Platinum groups, so
-- the two CHECK actions (0, 1) answer FALSE into their dest var (the second
-- operand), the naming screen (4) answers "cancelled" (1), and the buffers /
-- join / make (2, 3, 5, 6) do nothing (INFERRED: "no group" is the state of a
-- save that never joined one; the naming screen is not built).
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- AMITY SQUARE (pokeplatinum src/scrcmd_amity_square.c), READ. These were
-- `g4_no_feature` -- harmless while the decoder stopped every pick-up script
-- at ScrCmd_27C, and wrong the moment it did not: the follower would hand
-- over item / accessory 0. Now the cartridge's tables:
--
--   CalcAmitySquareFoundAccessory <dest> <species>: LCRNG % 100 into ten
--     bands (15,15,15,15,10,10,8,5,5,2), the follower's species picks one of
--     six pools (default pool 0)
--   CalcAmitySquareBerryAndAccessoryManOptionID <dest>: LCRNG % 16
--   CheckAmitySquareManGiftIsAccessory <id> <dest>: id >= 9
--   GetAmitySquareBerryOrAccessoryIDFromMan <id> <dest>: the 16-entry list
--     (nine berries as item ids, then seven accessories)
-- ---------------------------------------------------------------------------
M.AMITY_BANDS = { 15, 30, 45, 60, 70, 80, 88, 93, 98, 100 }
M.AMITY_POOLS = {
  [0] = { 0, 5, 21, 6, 26, 13, 25, 31, 16, 33 },   -- Chimchar line (and default)
  [1] = { 2, 19, 20, 24, 17, 0, 23, 29, 28, 15 },  -- Piplup line
  [2] = { 9, 8, 3, 6, 22, 30, 17, 7, 14, 32 },     -- Turtwig line
  [3] = { 12, 18, 21, 13, 31, 8, 25, 24, 27, 7 },  -- Psyduck, Buneary, Drifloon
  [4] = { 5, 3, 26, 19, 20, 1, 11, 16, 22, 15 },   -- Pikachu, Clefairy, Pachirisu, Happiny
  [5] = { 12, 30, 2, 20, 29, 4, 9, 27, 14, 10 },   -- Jigglypuff, Torchic, Skitty, Shroomish
}
M.AMITY_POOL_OF = {
  [390] = 0, [391] = 0, [392] = 0, [393] = 1, [394] = 1, [395] = 1,
  [387] = 2, [388] = 2, [389] = 2, [54] = 3, [427] = 3, [425] = 3,
  [25] = 4, [35] = 4, [417] = 4, [440] = 4, [39] = 5, [255] = 5, [300] = 5, [285] = 5,
}
M.AMITY_MAN_OPTIONS = { [0] = 176, 175, 177, 178, 179, 180, 181, 182, 183,
                        11, 7, 10, 16, 27, 32, 33 }

local function rand(n)
  if love and love.math and love.math.random then return love.math.random(0, n - 1) end
  return math.random(0, n - 1)
end
M.rand = rand

function M.amityFoundAccessory(species, roll)
  local band = 10
  for i, edge in ipairs(M.AMITY_BANDS) do
    if roll < edge then band = i break end
  end
  local pool = M.AMITY_POOLS[M.AMITY_POOL_OF[species] or 0]
  return pool[band]
end

function Commands.pt_amity_found_accessory(ctx, destVar, species)
  setVar(ctx, destVar, M.amityFoundAccessory(valueOf(ctx, species), rand(100)))
end
function Commands.pt_amity_man_option(ctx, destVar) setVar(ctx, destVar, rand(16)) end
function Commands.pt_amity_man_is_accessory(ctx, id, destVar)
  setVar(ctx, destVar, valueOf(ctx, id) >= 9 and 1 or 0)
end
function Commands.pt_amity_man_gift(ctx, id, destVar)
  setVar(ctx, destVar, M.AMITY_MAN_OPTIONS[valueOf(ctx, id)] or 0)
end

-- ---------------------------------------------------------------------------
-- MENU ANCHORS, READ: SetMenuXOriginSide <rightSide u8> / SetMenuYOriginSide
-- <bottomSide u8> (scrcmd.c -> FieldMenuManager_SetHorizontalAnchor /
-- _SetVerticalAnchor on the menu the init just made; field_menu.c then takes
-- the init's x as the RIGHT edge / y as the BOTTOM). Kept on the pending
-- menu; g4_menu_show places a Platinum menu by it.
-- ---------------------------------------------------------------------------
function Commands.pt_menu_anchor(ctx, axis, on)
  local menu = ctx.g4Menu
  if not menu then return end
  local yes = (tonumber(on) or 0) ~= 0
  if axis == "x" then menu.anchorRight = yes else menu.anchorBottom = yes end
end

-- ---------------------------------------------------------------------------
-- MoveCamera <x> <y> <z> (scrcmd.c), READ: Camera_Move adds (x, y, z) world
-- units to the camera's position AND target, and the (hidden) player's
-- sprite is offset the same way. Both Battle Tower multi rooms call it with
-- (8, 0, 0) on resume, so the view sits half a tile right, between the two
-- partners. Here: the look-at nudge OverworldState:followCamera already
-- reads (`gen4ShakeOffset`, x right, second value up), dropped on the next
-- map change as the cartridge's camera is rebuilt there.
-- ---------------------------------------------------------------------------
local function s16(v) v = math.floor(tonumber(v) or 0) if v >= 0x8000 then v = v - 0x10000 end return v end
local hookedSetMap = false
function Commands.pt_move_camera(ctx, x, y, z)
  local ow = ctx.overworld
  if not ow then return end
  local dx, dz = s16(valueOf(ctx, x)), s16(valueOf(ctx, z))
  local cur = ow.gen4ShakeOffset or { 0, 0 }
  ow.gen4ShakeOffset = { cur[1] + dx, cur[2] - dz }
  ow.ptCameraMoved = ow.map and ow.map.id
  if not hookedSetMap then
    hookedSetMap = true
    local OS = package.loaded["src.world.OverworldController"]
    if type(OS) == "table" and type(OS.setMap) == "function" then
      local setMap0 = OS.setMap
      OS.setMap = function(self, ...)
        if self.ptCameraMoved then self.ptCameraMoved, self.gen4ShakeOffset = nil, nil end
        return setMap0(self, ...)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- ScrCmd_2B6 <localId> <solid u8> (scrcmd.c), READ: sub_02062D80 clears
-- MAP_OBJ_STATUS_18 when the byte is TRUE and sets it otherwise, and
-- sub_02063F00 (map_object_move.c) skips status-18 objects when it tests a
-- tile for another object -- so the byte is "this object blocks again". Iron
-- Island B2F hands Riley back his solidity after the partner walk (the
-- port's partner is `passable`, and release leaves it so).
-- ---------------------------------------------------------------------------
function Commands.pt_object_solid(ctx, id, solid)
  local ow = ctx.overworld
  local want = valueOf(ctx, id)
  for _, e in ipairs((ow and ow.entities) or {}) do
    local lid = e.localId or (e.def and e.def.localId)
    if lid == want and e ~= ow.player then e.passable = (tonumber(solid) or 0) == 0 or nil end
  end
end

-- ---------------------------------------------------------------------------
-- ScrCmd_2B5 <map> <x> <z> (scrcmd.c), READ: FieldOverworldState's EXIT
-- LOCATION -- where Escape Rope / Dig return to -- set to (map, x, z),
-- WARP_ID_NONE, facing down. This port's exit location is `save.digWarp`
-- (OverworldState:escapePoint). The coordinates are the matrix's; a map cut
-- out of one at an origin takes them back by it, as g4_warp does.
-- ---------------------------------------------------------------------------
function Commands.pt_set_exit_location(ctx, header, x, z)
  local data = ctx.game and ctx.game.data
  local G = G4()
  local mapId = G.mapForHeader and G.mapForHeader(data, valueOf(ctx, header))
  if not (mapId and ctx.save) then return end
  local def = data.maps and data.maps[mapId]
  local wx, wz = valueOf(ctx, x), valueOf(ctx, z)
  if def and def.width and (wx >= def.width or wz >= (def.height or 0)) then
    wx, wz = wx - (def.originX or 0), wz - (def.originY or 0)
  end
  local warp = { id = mapId, x = wx, y = wz, gen4 = true, facing = "down" }
  ctx.save.digWarp = warp
  if ctx.overworld then ctx.overworld.digWarp = warp end
end

-- ---------------------------------------------------------------------------
-- ScrCmd_2CD (scrcmd.c), READ: a SysTask that waits for the weather manager
-- and then ov5_021D5F24(weather, 26) -- the LIVE weather becomes 26, the
-- depth fog ov5_021DB3E0 (slope 3, offset 26095, GX_RGB(2, 2, 6)), without
-- touching the saved one. Galactic Eterna Building 4F's OnLoad. The live
-- weather is `save.gen4WeatherActive` (Gen4DepthFog.current reads it), reset
-- from the header on the next map load.
-- ---------------------------------------------------------------------------
function Commands.pt_live_weather(ctx, weather)
  if ctx.save then ctx.save.gen4WeatherActive = tonumber(weather) end
end

-- ---------------------------------------------------------------------------
-- SetPlayerState <mask> / ChangePlayerState (scrcmd.c), READ: the first ORs a
-- PlayerTransition bit into the avatar's request, the second
-- (PlayerAvatar_RequestChangeState) applies it. The Pokemon Center nurse
-- uses HEALING (1 << 8) then WALKING (1 << 0): the heal sheet, then back.
-- The bike / dismount half stays in g4_player_state, which is applied at
-- the set; the request is kept here and the heal pose applied at the change.
-- ---------------------------------------------------------------------------
M.TRANSITION_WALKING, M.TRANSITION_HEALING = 1, 256
function Commands.pt_request_player_state(ctx, mask)
  if not ctx.save then return end
  local bits = math.floor(tonumber(mask) or 0)
  ctx.save.gen4PlayerStateRequest = (ctx.save.gen4PlayerStateRequest or 0) + 0
  local cur = ctx.save.gen4PlayerStateRequest
  -- OR (no bit library guaranteed): add the bits not already set
  for b = 0, 15 do
    local v = 2 ^ b
    if math.floor(bits / v) % 2 == 1 and math.floor(cur / v) % 2 == 0 then cur = cur + v end
  end
  ctx.save.gen4PlayerStateRequest = cur
end
function Commands.pt_change_player_state(ctx)
  local save = ctx.save
  if not save then return end
  local req = save.gen4PlayerStateRequest or 0
  save.gen4PlayerStateRequest = nil
  -- Platinum's mask and sheets only (HGSS / BW number their states apart)
  if require("src.import.Gen4ScriptBands").family ~= "platinum" then return end
  local was = save.gen4PlayerHeal
  if math.floor(req / M.TRANSITION_HEALING) % 2 == 1 then save.gen4PlayerHeal = true
  elseif req % 2 == 1 then save.gen4PlayerHeal = nil end
  local p = ctx.overworld and ctx.overworld.player
  if was ~= save.gen4PlayerHeal and p and p.refreshForm and ctx.game then
    p.walkId = nil
    pcall(p.refreshForm, p, ctx.game.data)
  end
end

function M.install(L)
  local function noop(what) return function(_, s) row(s, { "g4_noop", what }) end end
  local function nofeature(slot, what)
    return function(ins, s) row(s, { "g4_no_feature", ins.args[slot], what }) end
  end

  require("src.script.PtTvBroadcast").install(L)
  require("src.script.PtSlotMachine").install(L)
  -- the Ball Capsule app behind `opensealcapsuleeditor` (PtCapsuleMenu)
  require("src.script.PtCapsuleCommands").install(L)

  -- 29F was a noop "reads one var and writes nothing": true, and beside the
  -- point -- the field task it starts is the shake
  L["29f"] = function(ins, s) row(s, { "pt_quake", ins.args[1] }) end

  L["0b3"] = L["0b3"] or nofeature(1, "the Nintendo WFC setup")
  L["2f6"] = L["2f6"] or nofeature(3, "a Wi-Fi login")
  L.trystartgtsapp = L.trystartgtsapp or nofeature(2, "the GTS")
  L["2f7"] = L["2f7"] or noop("a Wi-Fi Plaza call (no login)")
  L["30e"] = L["30e"] or nofeature(1, "the Union Room greeting editor")

  L.tryrecordchatotcry = L.tryrecordchatotcry or nofeature(1, "a microphone")
  L.stoprecordingchatotcry = L.stoprecordingchatotcry or noop("the Chatot cry recording")
  L.storerecordedchatotcry = L.storerecordedchatotcry or noop("the Chatot cry recording")
  L.setpokemonpreviewanim = L.setpokemonpreviewanim or noop("the Chatot preview animation")
  L.waitpokemonpreviewanim = L.waitpokemonpreviewanim or noop("the Chatot preview animation")

  L.showbattlehallrecordmonselectionmenu = L.showbattlehallrecordmonselectionmenu or function(ins, s)
    row(s, { "pt_hall_record_menu", ins.args[1], ins.args[2], ins.args[3] })
  end

  L.setsceneplaybgmmusicbox = L.setsceneplaybgmmusicbox or function(_, s)
    row(s, { "pt_play_bgm", M.SEQ_PL_TOWN02 })
  end
  L.setfieldscene = L.setfieldscene or function(ins, s) row(s, { "pt_play_bgm", ins.args[1] }) end

  L.getbattlefrontierreporterposition = L.getbattlefrontierreporterposition or function(ins, s)
    row(s, { "pt_frontier_reporter_pos", ins.args[1], ins.args[2], ins.args[3], ins.args[4] })
  end

  L.dogroupconnectionaction = L.dogroupconnectionaction or function(ins, s)
    -- a cache from before platinum-tv-script-v1 has the row undecoded
    -- (`variable`, no operands): stepped over, as it always was
    if not ins.args then return row(s, { "g4_unimplemented", ins.name, "variable length" }) end
    local action = tonumber(ins.args[1]) or -1
    if action == 0 or action == 1 then
      row(s, { "g4_no_feature", ins.args[3], "Platinum's record-mixing groups" })
    elseif action == 4 then
      -- the naming screen's answer: 1 is "cancelled" (GroupConnection_NameGroup
      -- -> ThatsTooBad), so no group is made with a blank name
      row(s, { "g4_set_var", ins.args[2], 1 })
    else
      row(s, { "g4_noop", "a record-mixing group action" })
    end
  end

  -- Amity Square: these REPLACE the `g4_no_feature` rows in Gen4ScriptVM
  L.calcamitysquarefoundaccessory = function(ins, s)
    row(s, { "pt_amity_found_accessory", ins.args[1], ins.args[2] })
  end
  L.calcamitysquareberryandaccessorymanoptionid = function(ins, s)
    row(s, { "pt_amity_man_option", ins.args[1] })
  end
  L.checkamitysquaremangiftisaccessory = function(ins, s)
    row(s, { "pt_amity_man_is_accessory", ins.args[1], ins.args[2] })
  end
  L.getamitysquareberryoraccessoryidfromman = function(ins, s)
    row(s, { "pt_amity_man_gift", ins.args[1], ins.args[2] })
  end

  do
    local setState0 = L.setplayerstate
    L.setplayerstate = function(ins, s)
      row(s, { "pt_request_player_state", ins.args[1] })
      if setState0 then return setState0(ins, s) end
    end
  end
  L.changeplayerstate = function(_, s) row(s, { "pt_change_player_state" }) end
  L.setmenuxoriginside = function(ins, s) row(s, { "pt_menu_anchor", "x", ins.args[1] }) end
  L.setmenuyoriginside = function(ins, s) row(s, { "pt_menu_anchor", "y", ins.args[1] }) end
  L.movecamera = function(ins, s) row(s, { "pt_move_camera", ins.args[1], ins.args[2], ins.args[3] }) end
  L["2b6"] = function(ins, s) row(s, { "pt_object_solid", ins.args[1], ins.args[2] }) end
  L["2b5"] = function(ins, s) row(s, { "pt_set_exit_location", ins.args[1], ins.args[2], ins.args[3] }) end
  L["2cd"] = function(_, s) row(s, { "pt_live_weather", 26 }) end

  -- Dummy19E <vendor> <dest>: UndergroundVendors_ReturnNull, then the pause
  -- writes UndergroundVendors_ReturnFFFE -- 0xFFFE -- into dest (scrcmd.c)
  L.dummy19e = L.dummy19e or function(ins, s) row(s, { "g4_set_var", ins.args[2], 0xFFFE }) end
  L.dummy316 = L.dummy316 or noop("a cartridge no-op (Dummy316)")
  L.dummy14f = L.dummy14f or noop("a cartridge no-op (Dummy14F)")
end

return M
