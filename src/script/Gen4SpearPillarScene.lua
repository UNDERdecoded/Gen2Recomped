-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S `ScrCmd_2FB`: the Spear Pillar cinematic.
--
--     static BOOL ScrCmd_2FB(ScriptContext *ctx) {
--         sub_020985E4(ctx->task, ctx->fieldSystem->saveData);
--         return TRUE;
--     }
--
-- sub_020985E4 (src/unk_020985E4.c) hands the options, the trainer info and
-- the player's gender to a field task, sub_0209862C, which
--   0  FieldMap_FadeScreen(FADE_TYPE_BRIGHTNESS_OUT)   -- 6 steps to black
--   1  waits for the fade, then FieldSystem_StartChildProcess(the app)
--   2  waits for the app to exit, FieldSystem_StartFieldMap
--   3  waits for the field map to be running
--   4  one more frame, 5 frees and returns
-- FieldTask_InitCall holds the script until the task returns, so the script
-- waits for all of it.  The screen is left black: the script's next commands
-- set its flags and Warp, and the warp's own fade brings the new map in.
--
-- One site: scripts_spear_pillar.s, SpearPillar_WaitThenWarpToSpearPillar-
-- Distorted, after the `ScrCmd_20D 1` poll.  The app is src/ui/
-- Gen4SpearPillarCutscene.lua.  HeartGold / SoulSilver name their 0x2FB
-- differently (LegendCutsceneWaitCameraPan), so this row is Platinum's alone;
-- the version is checked again here so a mod lowering it elsewhere falls back
-- to the old no-op.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end
local Logger = require("src.core.Logger")

local M = {}
-- FieldMap_FadeScreen: StartScreenFade(.., 6 steps, 1 frame a step)
M.FIELD_FADE_STEPS = 6

local function platinum()
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and GV.isPlatinumFamily and GV.isPlatinumFamily() or false
end

function Commands.g4_spear_pillar_cutscene(ctx)
  local game = ctx.game
  local Screen = require("src.ui.Gen4SpearPillarCutscene")
  if not platinum() then return end
  if not (game and game.stack and Screen.available(game)) then
    Logger.warn("spear pillar: the cinematic's art is not in this cache (re-import Platinum) -- the story goes on without it")
    return
  end
  local runner = ctx.runner
  -- state 0/1: the field fades to black first (and stays black)
  if ctx.overworld and Commands.fade and runner then
    Commands.fade(ctx, "out", M.FIELD_FADE_STEPS, "black")
  end
  game.stack:push(Screen.new(game, function() if runner then runner:resume() end end))
  if runner then runner:yield() end
  -- THE SCREEN STAYS BLACK until the map changes: the script's next rows are
  -- flags and a Warp, and on the cartridge the warp's arrival is what brings
  -- the picture back.  The port's script fade survives a warp (its watchdog
  -- lifts it two seconds later with a warning), so it is told to lift itself
  -- the way an arrival does once the player is on another map.
  local ow = ctx.overworld
  local overlay = ow and ow.fadeOverlay
  if overlay and type(overlay.update) == "function" then
    local mapId = ow.map and ow.map.id
    local update = overlay.update
    overlay.update = function(o, dt)
      local here = o.ow and o.ow.map and o.ow.map.id
      if here and here ~= mapId and not o.ramp then
        o.update = nil
        o.ramp = { from = o.alpha or 1, to = 0, frames = M.FIELD_FADE_STEPS * 2, t = 0 }
      end
      return update(o, dt)
    end
  end
end
if Commands.meta then
  Commands.meta.g4_spear_pillar_cutscene = { foreground = true, blocking = true }
end

-- `ScrCmd_20D 0` / `ScrCmd_20D 1`: the Red Chain (src/world/Gen4SpearPillarChain).
-- Mode 0 starts it and answers 0 (the effect plays on while the script goes
-- on); mode 1 is the poll, which the script spins on in a backwards jump --
-- so it waits here until the effect reaches its state 11, deletes it and
-- answers 1.  Both write their var through Commands.g4_field_effect, the
-- port's reading of the other eight modes.
function Commands.g4_spear_pillar_chain(ctx, mode, destVar)
  mode = math.floor(tonumber(mode) or -1)
  local game = ctx.game
  local Chain = require("src.world.Gen4SpearPillarChain")
  local function answer(m)
    if Commands.g4_field_effect then return Commands.g4_field_effect(ctx, m, destVar) end
  end
  if not (platinum() and game and game.stack) then return answer(mode) end
  if mode == 0 then
    Chain.start(game)
    return answer(0)
  end
  local fx = Chain.current
  local runner = ctx.runner
  if fx and not fx.closed and not fx.done and runner then
    fx.polled = true
    runner.waitingCheck = function() return fx.done or fx.closed end
    runner:yield()
  end
  if fx then fx:close() end
  return answer(1)
end
if Commands.meta then
  Commands.meta.g4_spear_pillar_chain = { foreground = true, blocking = true }
end

function M.install(L)
  local previous20d = L["20d"]
  L["20d"] = function(ins, s)
    local mode = ins and ins.args and tonumber(ins.args[1])
    if ins and not ins.hgssName and (mode == 0 or mode == 1) then
      s.out[#s.out + 1] = { "g4_spear_pillar_chain", ins.args[1], ins.args[2] }
      return
    end
    if previous20d then return previous20d(ins, s) end
  end
  local previous = L["2fb"]
  L["2fb"] = function(ins, s)
    if ins and ins.hgssName then
      if previous then return previous(ins, s) end
      return
    end
    s.out[#s.out + 1] = { "g4_spear_pillar_cutscene" }
  end
end

return M
