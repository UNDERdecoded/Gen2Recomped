-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A DARK CAVE IN HOENN IS A HOLE, NOT A SHADE.
--
-- The port already knew which seven maps need FLASH -- the map header says so
-- and OverworldState.isDarkMap reads it -- and then drew them the way Kanto
-- and Johto are drawn: the whole picture one shade darker, uniformly, to the
-- edges of the screen.  That is the Game Boy's darkness and it is not
-- Emerald's.  Emerald draws the map at full brightness and lays a black
-- window over it with a CIRCLE cut out around the player; how big that circle
-- is IS the mechanic, and it is why FLASH is a Hidden Machine rather than a
-- convenience:
--
--     level 7   radius 24   a cave you walked into without FLASH
--     level 1   radius 72   the same cave after you use it
--     level 0   radius 200  bigger than the screen -- no darkness at all
--
-- The radii, the levels, the flag and the centre are all read off the
-- cartridge by RomExtractorGen3:extractFlash; that stage's comment carries the
-- disassembly.  Nothing here invents a number: with no record the questions
-- below answer "no darkness", which leaves a cave lit rather than guessing a
-- radius and drawing a hole in the wrong place.
--
-- WHERE THE HOLE GOES.  The cartridge centres it on (120,80), the middle of
-- the GBA screen, because the field camera keeps the player there.  This port
-- lets the window be other sizes, so the centre is taken from where the player
-- actually IS -- which is the same point whenever the view is 240x160 and
-- stays right when it is not.

local Gen3Flash = {}

local function record(data)
  local r = (data and data.constants or {}).gen3Flash
  if type(r) ~= "table" or type(r.radii) ~= "table" then return nil end
  return r
end
Gen3Flash.record = record

-- radii[level + 1] -- see the record's own comment about the off-by-one
function Gen3Flash.radiusOf(data, level)
  local r = record(data)
  if not r then return nil end
  level = math.floor(tonumber(level) or 0)
  if level < 0 then level = 0 end
  if level > (tonumber(r.maxLevel) or 0) then level = r.maxLevel end
  return tonumber(r.radii[level + 1])
end

-- HAS FLASH BEEN USED?  Two answers have to be one.
--
-- The port has kept this in `save.flashLit` since Kanto, and the cartridge
-- keeps it in an ordinary script flag -- $888, which extractFlash reads out of
-- SetDefaultFlashLevel and files as `record.flag`.  Nothing joined them, so a
-- real Emerald save that had used FLASH arrived here with the flag set and
-- `flashLit` unset, and walked into Granite Cave at a radius of 24; and a port
-- save exported the other way told the cartridge FLASH had never been used.
--
-- The flag is the truth where the record names one, because that is what
-- survives a round trip through a .sav; `flashLit` is kept in step for the
-- generations that have no such flag and for a dataset with no record.
function Gen3Flash.lit(game)
  local save = game and game.save
  if not save then return false end
  local r = record(game.data)
  local key = r and r.flag
  if key and save.flags and save.flags[key] ~= nil then
    return save.flags[key] and true or false
  end
  return save.flashLit and true or false
end

function Gen3Flash.setLit(game, on)
  local save = game and game.save
  if not save then return end
  on = on and true or nil
  save.flashLit = on
  local r = record(game.data)
  if r and r.flag then
    save.flags = save.flags or {}
    save.flags[r.flag] = on
  end
end

-- Overworld_SetFlashLevel: out of range means 0, which is "no darkness".
function Gen3Flash.setLevel(game, level)
  local save = game and game.save
  if not save then return 0 end
  local r = record(game.data)
  local max = r and tonumber(r.maxLevel) or 0
  level = math.floor(tonumber(level) or 0)
  if level < 0 or level > max then level = 0 end
  save.gen3FlashLevel = level
  -- a snap ends whatever was easing; animateTo re-seeds it straight after
  save.gen3FlashRadius = nil
  return level
end

function Gen3Flash.level(game)
  return math.floor(tonumber(game and game.save and game.save.gen3FlashLevel)
                    or 0)
end

-- ---------------------------------------------------------------------------
-- ...AND THE ONE THAT OPENS RATHER THAN SNAPS.
--
-- `setflashlevel` (script 0x99, 0099C8C) hands its number straight to
-- Overworld_SetFlashLevel and the window is that wide on the next frame.
-- `animateflash` (0x9A, 0099C70) does not: it calls AnimateFlash (0B009C),
-- which looks the CURRENT level's radius and the new one's out of the same
-- table (0x0854FE64, which is this record's `radii`) and hands both to a task
-- whose per-frame step is ONE PIXEL -- `strh r7,[r1,#10]` at 0B001C, with r7
-- the 1 AnimateFlash passes -- negated when the window is closing.  So the
-- animation's length is not a constant: it is the DISTANCE, and adjacent
-- levels are eight pixels apart, so one step of the Dewford gym's ladder
-- takes eight frames and the first flash in a cave takes twenty-four.
--
-- The level is set at once, exactly as the cartridge does; what eases is the
-- radius the draw asks for.
-- ---------------------------------------------------------------------------
local ANIM_STEP = 1

function Gen3Flash.animateTo(game, level)
  local save = game and game.save
  if not save then return 0 end
  local from = Gen3Flash.radiusOf(game.data, Gen3Flash.level(game))
  local set = Gen3Flash.setLevel(game, level)
  local to = Gen3Flash.radiusOf(game.data, set)
  if from and to and from ~= to then
    save.gen3FlashRadius = from
  else
    save.gen3FlashRadius = nil
  end
  return set
end

-- One frame of it.  Returns true while the window is still moving, which is
-- what the script's own wait is for (0098E54 blocks until the task retires).
function Gen3Flash.tick(game)
  local save = game and game.save
  local at = save and tonumber(save.gen3FlashRadius)
  if not at then return false end
  local want = Gen3Flash.radiusOf(game.data, Gen3Flash.level(game))
  if not want or at == want then
    save.gen3FlashRadius = nil
    return false
  end
  local step = (want > at) and ANIM_STEP or -ANIM_STEP
  at = at + step
  if (step > 0 and at >= want) or (step < 0 and at <= want) then
    save.gen3FlashRadius = nil
    return false
  end
  save.gen3FlashRadius = at
  return true
end

-- SetDefaultFlashLevel, which runs on every map load: not a cave, no darkness;
-- a cave you have used FLASH in, the lit level; a cave you have not, the dark
-- one.  `lit` here is the port's own save bit -- the same one the FLASH menu
-- entry sets -- and the cartridge's flag name travels beside it in the record
-- so a save converted either way agrees about which it is.
function Gen3Flash.defaultFor(game, isCave, lit)
  local r = record(game and game.data)
  if not r then return Gen3Flash.setLevel(game, 0) end
  if not isCave then return Gen3Flash.setLevel(game, 0) end
  return Gen3Flash.setLevel(game, lit and r.lit or r.dark)
end

-- The circle to cut, or nil when there is no darkness to draw.  `radius` is
-- nil at level 0 and at any level whose radius covers the whole view, so the
-- caller never draws a window it cannot see the edge of.
function Gen3Flash.circle(game, viewW, viewH, centerX, centerY)
  local r = record(game and game.data)
  if not r then return nil end
  -- THE BATTLE PYRAMID'S DARK is its own radius (frontier.pyramidLightRadius),
  -- drawn by the same window: 32 on a new floor, wider with each trainer
  if require("src.core.GameVersion").get() == "emerald" then
    local ok, radius = pcall(function()
      return require("src.script.Gen3BattlePyramid").lightRadius(game)
    end)
    if ok and radius then
      local width, height = tonumber(viewW) or r.screen[1], tonumber(viewH) or r.screen[2]
      local cx, cy = centerX or width / 2, centerY or height / 2
      local w, h = math.max(math.abs(cx), math.abs(width-cx)), math.max(math.abs(cy), math.abs(height-cy))
      if radius * radius >= w * w + h * h then return nil end
      return { radius = radius }
    end
  end
  local level = Gen3Flash.level(game)
  if level <= 0 then return nil end
  -- mid-animation the window is wherever the one-pixel step has got to
  local radius = tonumber(game.save and game.save.gen3FlashRadius)
                 or Gen3Flash.radiusOf(game.data, level)
  if not radius or radius <= 0 then
    -- the darkest level the table has closes the window completely; the
    -- cartridge does not use it, but a script may set it
    return { radius = 0 }
  end
  -- bigger than the corner of the view is the same as no darkness
  local width, height = tonumber(viewW) or r.screen[1], tonumber(viewH) or r.screen[2]
  local cx, cy = centerX or width / 2, centerY or height / 2
  local w, h = math.max(math.abs(cx), math.abs(width-cx)), math.max(math.abs(cy), math.abs(height-cy))
  if radius * radius >= w * w + h * h then return nil end
  return { radius = radius }
end

-- Integer window edges, including the scanline update order. A floating-point
-- circle at pixel centres has different edge pixels. Keep geometry independent
-- of the save and graphics backend; callers get fresh, mutable span records.
function Gen3Flash.spans(radius, width, height, centerX, centerY)
  local w, h = math.floor(width or 240), math.floor(height or 160)
  local cx, cy = math.floor(centerX or w/2), math.floor(centerY or h/2)
  radius = math.floor(radius)
  assert(radius==radius and radius<math.huge, 'invalid Flash radius')
  local lefts, rights, maxX = {}, {}, math.max(255, w)
  local function put(y, left, right)
    if y>=0 and y<h then
      lefts[y] = math.max(0, math.min(maxX, left))
      rights[y] = math.max(0, math.min(maxX, right))
    end
  end
  local x, err, y = radius, radius, 0
  while x>=y do
    put(cy-y,cx-x,cx+x); put(cy+y,cx-x,cx+x)
    put(cy-x,cx-y,cx+y); put(cy+x,cx-y,cx+y)
    err=err-((y*2)-1); y=y+1
    if err<0 then err=err+2*(x-1); x=x-1 end
  end
  local result, row = {}, 0
  while row<h do
    local left, right = lefts[row] or 0, rights[row] or 0
    local stop = row+1
    while stop<h and (lefts[stop] or 0)==left and (rights[stop] or 0)==right do stop=stop+1 end
    result[#result+1]={y=row,height=stop-row,left=left,right=right}
    row=stop
  end
  return result
end

-- Only this private geometry cache is reused by native drawing. Public span
-- records cannot corrupt it, and it never retains a game, world or texture.
local mask
function Gen3Flash.drawMask(radius, w, h, cx, cy)
  if not mask or mask.radius~=radius or mask.w~=w or mask.h~=h or mask.cx~=cx or mask.cy~=cy then
    mask={radius=radius,w=w,h=h,cx=cx,cy=cy,spans=Gen3Flash.spans(radius,w,h,cx,cy)}
  end
  love.graphics.setColor(0,0,0,1)
  for _,s in ipairs(mask.spans)do
    if s.left>0 then love.graphics.rectangle('fill',0,s.y,math.min(s.left,w),s.height)end
    if s.right<w then love.graphics.rectangle('fill',s.right,s.y,w-s.right,s.height)end
  end
  love.graphics.setColor(1,1,1,1)
end

return Gen3Flash
