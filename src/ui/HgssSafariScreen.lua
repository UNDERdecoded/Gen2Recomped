-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE TWO SAFARI ZONE APPS' SHARED SCREEN PLUMBING (overlay 108's area
-- customizer, src/ui/HgssSafariCustomizer.lua, and decoration app,
-- src/ui/HgssSafariDecoration.lua): the DS's two screens (SecondScreen, as
-- HgssUnownReport does it), the 6-step brightness fades both apps open and
-- close with (BeginNormalPaletteFade 0 / 6 / 1), a touch mapped to the bottom
-- screen, the cartridge's lines (Gen4Text) and plain drawn boxes.
--
-- THE ART is the cartridge's (src/import/Gen4HgssSafariAppArt.lua ->
-- `gen4_hgss_safari_apps`); the drawn panels below are only the fallback for
-- a cache imported before it existed.
--
-- THE SOUND SCENE: both apps call Sound_SetSceneAndPlayBGM(0x43, 0, 0)
-- (overlay_108.s SafariAreaCustomizer_Init, SafariDecoration_Init). Scene
-- 0x43 is a SUB-scene (>= 0x33, unk_02004A44.s Sound_SetScene) and its jump
-- table entry (case 67, _02004FF0) is sub_020052C8 alone: the scene's sound
-- heap state, no PlayBGM -- so the field's music plays on under both apps and
-- nothing has to be restored on exit.

local Font = require("src.render.Font")

local S = {}

S.W, S.H = 256, 192
S.FADE = 6 * 2      -- six brightness steps, two frames each
S.SE = { select = "SEQ_SE_DP_SELECT", cursor = "SEQ_SE_DP_BUTTON3",
         page = "SEQ_SE_DP_SELECT5", refuse = "SEQ_SE_DP_BOX03", pick = "SEQ_SE_DP_SYU02" }

S.INK = { 82, 82, 90 }
S.SHADOW = { 200, 200, 208 }
S.WHITE = { 248, 248, 248 }

-- THE IMPORTED ART: `gen4_hgss_safari_apps`, or nil
function S.art(game)
  local rec = game and game.data and game.data.gen4_hgss_safari_apps
  return type(rec) == "table" and rec or nil
end

local images = {}
-- an imported image entry -> a love Image (an absolute path is read straight
-- off the disk: a scratch import's index)
function S.image(entry)
  if type(entry) ~= "table" or not entry.path then return nil end
  local hit = images[entry.path]
  if hit ~= nil then return hit or nil end
  local ok, img = pcall(function()
    if entry.path:match("^%a:[/\\]") or entry.path:match("^/") then
      local f = assert(io.open(entry.path, "rb"))
      local bytes = f:read("*a"); f:close()
      return love.graphics.newImage(love.image.newImageData(love.filesystem.newFileData(bytes, entry.path)))
    end
    return require("src.render.Assets").image(entry.path)
  end)
  if ok and img then img:setFilter("nearest", "nearest") end
  images[entry.path] = (ok and img) or false
  return (ok and img) or nil
end

function S.draw(entry, x, y, sx, sy, w, h)
  local img = S.image(entry)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  if w then
    local q = love.graphics.newQuad(sx or 0, sy or 0, w, h, img:getDimensions())
    love.graphics.draw(img, q, x, y)
  else
    love.graphics.draw(img, x, y)
  end
  return true
end

-- a cell of an imported sprite bank, its origin at (x, y)
function S.cell(sprites, n, x, y)
  local e = sprites and sprites.cells and sprites.cells[(n or 0) + 1]
  if not e then return false end
  return S.draw(e, x - (e.ox or 0), y - (e.oy or 0))
end

-- the cell a NANR sequence shows `t` frames in (looping)
function S.seqCell(sprites, seq, t)
  local a = sprites and sprites.anims and sprites.anims[(seq or 0) + 1]
  local frames = a and a.frames
  if not (frames and #frames > 0) then return nil end
  local total = 0
  for _, f in ipairs(frames) do total = total + math.max(1, f.duration or 1) end
  local at = (t or 0) % total
  for _, f in ipairs(frames) do
    at = at - math.max(1, f.duration or 1)
    if at < 0 then return f.cell end
  end
  return frames[#frames].cell
end

function S.sprite(sprites, seq, t, x, y)
  local c = S.seqCell(sprites, seq, t)
  if c then return S.cell(sprites, c, x, y) end
  return false
end

-- TouchscreenHitbox_FindRectAtTouchNew: { top, bottom, left, right }, a right
-- of 0 meaning 256; the first rect that holds the point
function S.hitbox(rects, x, y)
  for i, r in ipairs(rects) do
    local right = r[4] == 0 and 256 or r[4]
    if y >= r[1] and y < r[2] and x >= r[3] and x < right then return i - 1 end
  end
  return nil
end

-- DrawFrameAndWindow2 around a window at tile (tx, ty), tw x th: the frame
-- the player chose (Font.drawBox, the Options screen's frame), one tile out
function S.userFrame(tx, ty, tw, th)
  local ok = pcall(function() Font.drawBox(tx - 1, ty - 1, tw + 2, th + 2) end)
  if not ok then S.box((tx - 1) * 8, (ty - 1) * 8, (tw + 2) * 8, (th + 2) * 8) end
  love.graphics.setColor(1, 1, 1, 1)
end

-- YesNoPrompt's two buttons from touch_subwindow: 6 x 4 tiles each at tile
-- (x, y) and (x, y + 4), the selected one in its second look
function S.yesNoArt(art, cursor, tx, ty)
  local yn = art and art.yesNo
  if not yn then return false end
  for i = 0, 1 do
    local look = (cursor == i + 1) and 1 or 0
    if not S.draw(yn[i] and yn[i][look], tx * 8, (ty + 4 * i) * 8, 0, 0, 48, 32) then return false end
  end
  return true
end
function S.yesNoHit(x, y, tx, ty)
  for i = 0, 1 do
    local bx, by = tx * 8, (ty + 4 * i) * 8
    if x >= bx and y >= by and x < bx + 48 and y < by + 32 then return i + 1 end
  end
  return nil
end

function S.se(game, which)
  local name = S.SE[which] or which
  pcall(function() require("src.core.Sound").playSe(game.data, name) end)
end

-- `buffers` (optional): the {STRVAR_1} slots for this line alone, from 0
function S.line(game, bank, n, fallback, buffers)
  local T = require("src.import.Gen4Text")
  local keep = game.stringBuffers
  if buffers then
    game.stringBuffers = {}
    for i, v in ipairs(buffers) do game.stringBuffers[i] = tostring(v) end
  end
  local s = T.resolve(game.data, bank, n, game)
  if buffers then game.stringBuffers = keep end
  if type(s) ~= "string" or s:match("^%s*$") then return fallback or "" end
  return (s:gsub("{[^}]*}", ""))
end

function S.dual(game)
  local okS, SS = pcall(require, "src.ui.SecondScreen")
  if not okS then return false end
  return SS.separateMode(SS.mode(game)) and not SS.stowed(game), SS
end

-- a window point -> the bottom screen's pixels, or nil
function S.point(game, px, py)
  local dual, SS = S.dual(game)
  if dual then return SS.toLocal(game, px, py) end
  local r = require("src.render.Renderer").uiPresentation
  if not r or px < r.x or py < r.y or px >= r.x + r.w or py >= r.y + r.h then return nil end
  return (px - r.x) / r.scaleX, (py - r.y) / r.scaleY
end

function S.color(c, a)
  love.graphics.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1)
end

function S.text(s, x, y, ink, shadow)
  s = tostring(s or "")
  if shadow ~= false then
    S.color(shadow or S.SHADOW)
    Font.draw(s, x + 1, y); Font.draw(s, x, y + 1); Font.draw(s, x + 1, y + 1)
  end
  S.color(ink or S.INK)
  Font.draw(s, x, y)
end

function S.width(s) return Font.width(tostring(s or "")) end

function S.centred(s, x, w, y, ink, shadow)
  S.text(s, x + math.floor((w - S.width(s)) / 2), y, ink, shadow)
end

-- lines 16 px apart
function S.lines(s, x, y, ink, shadow)
  for l in (tostring(s or "") .. "\n"):gmatch("(.-)\n") do
    S.text(l, x, y, ink, shadow)
    y = y + 16
  end
end

function S.box(x, y, w, h, fill, edge)
  local g = love.graphics
  S.color(fill or { 248, 248, 248 })
  g.rectangle("fill", x, y, w, h, 3, 3)
  S.color(edge or { 96, 120, 96 })
  g.setLineWidth(2)
  g.rectangle("line", x + 1, y + 1, w - 2, h - 2, 3, 3)
  g.setLineWidth(1)
end

-- the message window across the bottom of a screen (two lines)
function S.message(s, y)
  y = y or (S.H - 46)
  S.box(4, y, S.W - 8, 42, { 248, 248, 248 }, { 88, 104, 136 })
  S.lines(s, 12, y + 6)
end

-- a Yes / No prompt (YesNoPrompt) stacked at the right
function S.yesNo(cursor, y)
  y = y or 88
  local labels = { "YES", "NO" }
  for i = 1, 2 do
    local by = y + (i - 1) * 26
    S.box(184, by, 64, 22, cursor == i and { 255, 232, 160 } or { 240, 240, 240 },
          cursor == i and { 216, 120, 40 } or { 120, 120, 128 })
    S.centred(labels[i], 184, 64, by + 4)
  end
end

function S.backdrop(top, bottom)
  local g = love.graphics
  for i = 0, S.H - 1, 4 do
    local t = i / S.H
    love.graphics.setColor((top[1] + (bottom[1] - top[1]) * t) / 255,
                           (top[2] + (bottom[2] - top[2]) * t) / 255,
                           (top[3] + (bottom[3] - top[3]) * t) / 255, 1)
    g.rectangle("fill", 0, i, S.W, 4)
  end
end

function S.veil(f)
  if f > 0 then
    love.graphics.setColor(0, 0, 0, math.min(1, f))
    love.graphics.rectangle("fill", 0, 0, S.W, S.H)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- both screens, or the bottom one alone (the one the player works)
function S.present(game, drawTop, drawBottom, veil)
  local dual, SS = S.dual(game)
  if dual then
    love.graphics.push("all")
    love.graphics.setScissor()
    drawTop(); S.veil(veil)
    love.graphics.pop()
    SS.draw(game, function() drawBottom(); S.veil(veil) end)
  else
    drawBottom(true); S.veil(veil)
  end
end

function S.pressed(game, k)
  local input = game.input
  return input and input.wasPressed and input:wasPressed(k) or false
end

return S
