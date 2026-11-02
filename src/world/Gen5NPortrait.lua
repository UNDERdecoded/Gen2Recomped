-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- N'S FAREWELL PORTRAIT (0x1D3 / 0x1D5 / 0x1D4, N's Castle, member 556).
--
-- N's last lines are spoken over a full-screen picture of him, not over the
-- field; the art is src/import/Gen5NPortrait.lua's.
--
-- READ FROM CODE (Black):
--   0x1D3 <mode, u16, close> (ov10 0x02164910): overlay 82 loaded, the
--        portrait task made (0x021F5260) and the script WAITS on it:
--          fade the main screen to black (0x0204E720(1, 0, 16, 0): one
--          brightness step a frame, 16 frames), build BG2 / BG3
--          (0x021F53B4), fade back from black, then N (BG3) blended in over
--          30 frames (0x021F5708: ev = 16 * n / 30)
--   0x1D5 (ov82 0x021F558C): +0x1C = 0, +0x74 = 1 (as the task's own set-up
--        leaves them, 0x021F531E, so the first line talks too; Nimbasa's
--        Ferris wheel scene, mode 0, has no 0x1D5) -- the mouth animates for
--        the next message: while the text prints it loops frames 1,2,1,0
--        (0x021F5748 restarts it each time the message state reads 0) and it
--        stops once the message has finished (state 2)
--        the eyes blink on their own, 0,1,2,1,0, every 80 + rand(20) frames
--   0x1D4 (ov10 0x02164994 -> ov82 0x021F55A0): waits on the close: a fade
--        to black -- the main screen at once when <close> is 0, BOTH screens
--        slowly (speed -8: nine frames a step, 144 frames) when it is 1 --
--        then the BGs restored (0x021F5648); with <close> 0 the field fades
--        back in, with 1 it stays black for what follows (the game clear)
-- INFERRED: field frames are counted at 30 Hz here (the frame counts above
-- are the cartridge's own); the "message state" is read off the port's text
-- box (still typing = printing); the black after a <close> 1 is held until
-- the map changes or 300 frames pass, whichever is first.

local M = {}

local FADE = 16
local FACE = 30
local SLOW = 144

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local function rec(game)
  local c = game and game.data and game.data.constants
  return c and c.gen5NPortrait
end

local images = {}
local function image(entry)
  local path = type(entry) == "table" and entry.path or entry
  if not path then return nil end
  if images[path] == nil then
    local ok, img = pcall(function() return require("src.render.Assets").image(path) end)
    images[path] = ok and img or false
  end
  return images[path] or nil
end

local function typing(game)
  local top = game and game.stack and game.stack.top and game.stack:top()
  if not top then
    local st = game and game.stack and game.stack.states
    top = st and st[#st]
  end
  return type(top) == "table" and top.codes ~= nil and top.charIndex ~= nil
    and not top.done and top.charIndex < #top.codes
end

function M.open(ow, mode, close, runner)
  ow.gen5NPortrait = { mode = mode, close = close, phase = "out", t = 0, runner = runner,
                       blink = 80, eye = 0, eyeAt = nil, mouth = nil, talk = true, mouthAt = 0 }
end

function M.talk(ow)
  local p = ow.gen5NPortrait
  if p then p.talk = true; p.mouthAt = 0 end
end

function M.closeBegin(ow, runner)
  local p = ow.gen5NPortrait
  if not p then if runner then runner:resume() end return false end
  p.phase, p.t, p.runner = "closing", 0, runner
  return true
end

local function resume(p)
  local r = p.runner
  p.runner = nil
  if r then r:resume() end
end

-- one field frame (30 Hz)
local function step(ow, p, game)
  p.t = p.t + 1
  if p.phase == "out" and p.t >= FADE then p.phase, p.t = "in", 0
  elseif p.phase == "in" and p.t >= FADE then p.phase, p.t = "face", 0
  elseif p.phase == "face" and p.t >= FACE then p.phase, p.t = "shown", 0; resume(p)
  elseif p.phase == "closing" and p.t >= (p.close ~= 0 and SLOW or FADE) then
    if p.close ~= 0 then
      ow.gen5NPortrait = { phase = "black", t = 0, map = ow.map and ow.map.id }
    else
      ow.gen5NPortrait = { phase = "back", t = 0 }
    end
    resume(p)
    return
  elseif p.phase == "back" and p.t >= FADE then ow.gen5NPortrait = nil return
  elseif p.phase == "black" and (p.t >= 300 or (ow.map and ow.map.id ~= p.map)) then ow.gen5NPortrait = nil return
  end
  M.animate(p, game)
end

-- the eyes and the mouth, one field frame
function M.animate(p, game)
  -- the eyes: 0,1,2,1,0 every 80 + rand(20) frames
  if p.mode then
    p.blink = (p.blink or 80) - 1
    if p.blink <= 0 then p.eyeAt, p.blink = 0, 80 + math.random(0, 19) end
    if p.eyeAt then
      p.eye = ({ 0, 1, 2, 1, 0 })[p.eyeAt + 1]
      p.eyeAt = p.eyeAt + 1
      if p.eyeAt >= 5 then p.eyeAt, p.eye = nil, 0 end
    end
    -- the mouth: 1,2,1,0 looping while the text prints, after a 0x1D5
    if p.talk then
      if typing(game) then
        p.mouth = ({ 1, 2, 1, 0 })[(p.mouthAt % 4) + 1]
        p.mouthAt = p.mouthAt + 1
      elseif (p.mouthAt or 0) > 0 then
        p.talk, p.mouth = false, nil
      end
    end
  end
end

function M.update(ow, dt)
  local p = ow and ow.gen5NPortrait
  if not p then return end
  local game = require("src.core.Game")
  p.acc = (p.acc or 0) + (tonumber(dt) or 1 / 60)
  local n = 0
  while p.acc >= 1 / 30 and n < 4 and ow.gen5NPortrait == p do
    p.acc = p.acc - 1 / 30
    step(ow, p, game)
    n = n + 1
  end
end

-- drawn by OverworldState:drawUI over the field and under the text box
function M.draw(ow)
  local p = ow and ow.gen5NPortrait
  if not p then return end
  local game = require("src.core.Game")
  -- under a text box the overworld is not updated (the stack ticks its top
  -- only), so the face keeps moving from here: a field frame every two draws
  local top = game.stack and game.stack.top and game.stack:top()
  if top and top ~= ow then
    p.dacc = (p.dacc or 0) + 1
    if p.dacc >= 2 then p.dacc = 0; M.animate(p, game) end
  end
  local r = rec(game)
  local w, h = 256, 192
  local black = 0
  local shown = p.mode ~= nil and (p.phase == "in" or p.phase == "face" or p.phase == "shown" or p.phase == "closing")
  if p.phase == "out" then black = p.t / FADE
  elseif p.phase == "in" then black = 1 - p.t / FADE
  elseif p.phase == "closing" then black = p.t / (p.close ~= 0 and SLOW or FADE)
  elseif p.phase == "black" then black = 1
  elseif p.phase == "back" then black = 1 - p.t / FADE end
  if shown and r then
    love.graphics.setColor(1, 1, 1, 1)
    local bg = image(r.bg and (r.bg[p.mode] or r.bg[tostring(p.mode)]))
    if bg then love.graphics.draw(bg, 0, 0) else
      love.graphics.setColor(0, 0, 0, 1); love.graphics.rectangle("fill", 0, 0, w, h)
    end
    local a = (p.phase == "face") and math.min(1, p.t / FACE) or ((p.phase == "in") and 0 or 1)
    if a > 0 then
      love.graphics.setColor(1, 1, 1, a)
      local face = image(r.face)
      if face then
        -- the face map is 256 x 256; the screen shows its top 192
        love.graphics.draw(face, love.graphics.newQuad(0, 0, w, h, face:getDimensions()), 0, 0)
      end
      local eyes = r.eyes and image(r.eyes[p.eye or 0] or r.eyes[tostring(p.eye or 0)])
      if eyes and (p.eye or 0) ~= 0 then love.graphics.draw(eyes, r.eyeAt[1], r.eyeAt[2]) end
      local mouth = p.mouth and r.mouth and image(r.mouth[p.mouth] or r.mouth[tostring(p.mouth)])
      if mouth then love.graphics.draw(mouth, r.mouthAt[1], r.mouthAt[2]) end
    end
  end
  if black > 0 then
    love.graphics.setColor(0, 0, 0, math.min(1, black))
    love.graphics.rectangle("fill", 0, 0, w, h)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- the commands
function Commands.g5_nportrait_open(ctx, mode, _u16, close)
  local ow = ctx.overworld
  if not ow then return end
  local okG, G4 = pcall(require, "src.script.Gen4Commands")
  local v = function(x) return okG and G4.valueOf(ctx, x) or tonumber(x) or 0 end
  if not rec(ctx.game) then
    require("src.core.Logger").warn("gen5 N portrait: no art in this cache (re-import the ROM)")
    return
  end
  local runner = ctx.runner
  M.open(ow, math.floor(v(mode)), math.floor(v(close)), runner)
  if runner then runner:yield() end
end
function Commands.g5_nportrait_talk(ctx)
  if ctx.overworld then M.talk(ctx.overworld) end
end
function Commands.g5_nportrait_close(ctx)
  local ow = ctx.overworld
  if not ow then return end
  local runner = ctx.runner
  if M.closeBegin(ow, runner) and runner then runner:yield() end
end
Commands.meta = Commands.meta or {}
Commands.meta.g5_nportrait_open = { blocking = true }
Commands.meta.g5_nportrait_close = { blocking = true }

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwnportraitopen = L.bwnportraitopen or function(ins, s)
    emit(s, { "g5_nportrait_open", ins.args[1], ins.args[2], ins.args[3] })
  end
  L.bwnportraittalk = L.bwnportraittalk or function(_, s) emit(s, { "g5_nportrait_talk" }) end
  L.bwnportraitclose = L.bwnportraitclose or function(_, s) emit(s, { "g5_nportrait_close" }) end
  -- an old cache keeps 0x1D5 as an operand-less bw_1D5 (it has none)
  L.bw_1D5 = L.bw_1D5 or function(_, s) emit(s, { "g5_nportrait_talk" }) end
end

return M
