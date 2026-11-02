-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S LAYERED FIELD THEMES: the Village Bridge musicians.
--
-- Village Bridge's theme (SEQ 0x422) is one sequence whose bands are faded in
-- and out per musician: talk to Derleth and his whistle joins, talk again and
-- it fades away. Accumula Town's (0x3FB) has two such players. The records
-- (which tracks belong to which part, the fade, the zones) are
-- src/import/Gen5MusicParts.lua's.
--
-- READ FROM CODE (Black, arm9 unless noted):
--   * the manager (game system +0x20) finds the record whose sequence is the
--     one playing (0x0202C1D4 -> 0x0202C29C / 0x0202C268) and, when it is a
--     new record, sets part 0 ON and parts 1..8 OFF (0x0202C4A4) and applies
--     the volumes (0x0202C2C0 / 0x0202C518)
--   * each part is a state machine (0x0202C5F0): 0 ON (127), 1 OFF (0),
--     2 fading in (127 * n / fade), 3 fading out (127 - 127 * n / fade), n
--     counting up one a tick to the record's fade (0x0202C5CC), then ON / OFF
--     (0x0202C6C4 the volume)
--   * the volume goes to the BGM player's tracks in the part's mask
--     (0x0202C710 -> 0x02005F24 -> 0x02072FE8, NNS_SndPlayerSetTrackVolume)
--   * leaving the record's zones resets the parts and drops the record
--     (0x0202C218)
--   * 0x0A3 <part>: OFF / fading out -> fading in (ov21 0x021AF458 ->
--     0x0202C0D0 -> 0x0202C670); 0x0A4 <part>: ON / fading in -> fading out
--     (0x021AF484 -> 0x0202C688); 0x0A5 <dest, part>: 1 when ON or fading in
--     (0x021AF4B0 -> 0x0202C0F8 -> 0x0202C72C), 0 without a record
-- INFERRED: the manager ticks once a 60 Hz frame (it runs from the game
-- system's per-frame list, 0x0202C09C); a record is looked for again
-- whenever the playing sequence or the zone changes (the cartridge's own
-- activation runs from the field's start-up, 0x0202B758).

local M = {}

M.ON, M.OFF, M.FADE_IN, M.FADE_OUT = 0, 1, 2, 3

local function records(game)
  local c = game and game.data and game.data.constants
  return c and c.gen5MusicParts
end

local function zoneNumber(ow)
  local id = ow and ow.map and ow.map.id
  return tonumber(type(id) == "string" and id:match("^Z(%d+)") or id)
end

local function inZones(rec, zone)
  for _, z in ipairs(rec.zones or {}) do if z == zone then return true end end
  return false
end

-- the manager, one per game
function M.state(game)
  game.gen5MusicParts = game.gen5MusicParts or { parts = {} }
  return game.gen5MusicParts
end

local function reset(st)
  st.parts = {}
  for i = 0, 8 do st.parts[i] = { state = i == 0 and M.ON or M.OFF, n = 0 } end
end

function M.volume(st, i)
  local p = st.parts[i]
  if not p then return 0 end
  local fade = math.max(1, st.rec and st.rec.fade or 60)
  if p.state == M.ON then return 127
  elseif p.state == M.OFF then return 0
  elseif p.state == M.FADE_IN then return math.floor(127 * p.n / fade)
  end
  return 127 - math.floor(127 * p.n / fade)
end

local function apply(st)
  if not st.rec then return end
  local ok, Audio = pcall(require, "src.audio.NitroAudio")
  if not ok or not Audio.playing then return end
  for _, player in ipairs(Audio.playing(st.rec.seq)) do
    if player.setTrackVolume then
      for i = 0, 8 do
        local mask = st.rec.masks[i] or 0
        if mask ~= 0 then player:setTrackVolume(mask, M.volume(st, i)) end
      end
    end
  end
end

local function tick(st)
  local fade = math.max(1, st.rec and st.rec.fade or 60)
  for i = 0, 8 do
    local p = st.parts[i]
    if p and (p.state == M.FADE_IN or p.state == M.FADE_OUT) then
      p.n = math.min(fade, p.n + 1)
      if p.n >= fade then p.state, p.n = p.state == M.FADE_IN and M.ON or M.OFF, 0 end
    end
  end
end

-- per overworld frame (dt in seconds; the manager ticks at 60 Hz)
function M.update(ow, dt)
  local game = ow and require("src.core.Game")
  local recs = records(game)
  if not recs then return end
  local st = M.state(game)
  local song = require("src.core.Music").current()
  local zone = zoneNumber(ow)
  -- leaving the record's zones drops it (0x0202C218)
  if st.rec and zone and not inZones(st.rec, zone) then st.rec = nil; reset(st) end
  if song ~= st.song or zone ~= st.zone then
    st.song, st.zone = song, zone
    local found
    for _, rec in ipairs(recs) do
      if rec.seq == tonumber(song) and (not zone or inZones(rec, zone)) then found = rec end
    end
    if found and found ~= st.rec then st.rec = found; reset(st) end
  end
  if not st.rec then return end
  -- the game's 60 Hz audio loop ticks the parts (M.audioTick), under text
  -- boxes too; only when it is not running (a harness ticking the state
  -- stack alone) does the field's own clock stand in
  if st.audioTicks ~= st.seenAudioTicks then
    st.seenAudioTicks = st.audioTicks
    st.acc = 0
  else
    st.acc = (st.acc or 0) + (tonumber(dt) or 1 / 60)
    local steps = 0
    while st.acc >= 1 / 60 and steps < 8 do st.acc = st.acc - 1 / 60; tick(st); steps = steps + 1 end
  end
  apply(st)
end

-- one tick of the sound system (Game:update's 60 Hz audio loop)
function M.audioTick(game)
  local st = game and game.gen5MusicParts
  if not (st and st.rec) then return end
  st.audioTicks = (st.audioTicks or 0) + 1
  tick(st)
  apply(st)
end

-- 0x0A3 / 0x0A4 / 0x0A5
function M.on(game, part)
  local st = M.state(game)
  local p = st.rec and st.parts[part]
  if p and not (p.state == M.ON or p.state == M.FADE_IN) then p.state, p.n = M.FADE_IN, 0 end
end
function M.off(game, part)
  local st = M.state(game)
  local p = st.rec and st.parts[part]
  if p and not (p.state == M.OFF or p.state == M.FADE_OUT) then p.state, p.n = M.FADE_OUT, 0 end
end
function M.isOn(game, part)
  local st = M.state(game)
  local p = st.rec and st.parts[part]
  return (p and (p.state == M.ON or p.state == M.FADE_IN)) and 1 or 0
end

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
local function valueOf(ctx, v)
  local okG, G4 = pcall(require, "src.script.Gen4Commands")
  if okG and G4 and G4.valueOf then return G4.valueOf(ctx, v) end
  return tonumber(v) or 0
end

function Commands.g5_music_part_on(ctx, part)
  if ctx.game then M.on(ctx.game, math.floor(valueOf(ctx, part))) end
end
function Commands.g5_music_part_off(ctx, part)
  if ctx.game then M.off(ctx.game, math.floor(valueOf(ctx, part))) end
end
function Commands.g5_music_part_query(ctx, dest, part)
  local v = ctx.game and M.isOn(ctx.game, math.floor(valueOf(ctx, part))) or 0
  require("src.script.Gen4Commands").setVar(ctx.save, dest, v)
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwmusicparton = L.bwmusicparton or function(ins, s) emit(s, { "g5_music_part_on", ins.args[1] }) end
  L.bwmusicpartoff = L.bwmusicpartoff or function(ins, s) emit(s, { "g5_music_part_off", ins.args[1] }) end
  L.bwmusicpartquery = L.bwmusicpartquery or function(ins, s)
    emit(s, { "g5_music_part_query", ins.args[1], ins.args[2] })
  end
end

return M
