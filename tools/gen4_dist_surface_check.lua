-- Run:  python tools/run_lua_check.py tools/gen4_dist_surface_check.lua <platinum cache dir>
--
-- THE DISTORTION WORLD'S WALLS, CAMERA AND MOVING PLATFORMS
-- (src/world/Gen4DistSurface.lua, src/world/Gen4DistPlatforms.lua), checked
-- against the extracted cache and pret's tables.

package.path = './?.lua;./?/init.lua;' .. package.path
love = love or {}

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = (arg and arg[1] or ''):gsub('[/\\]$', '')
if cacheDir == '' then print('usage: gen4_dist_surface_check.lua <cache dir>') os.exit(2) end
local dw = assert(loadfile(cacheDir .. '/gen4_distortion_world.lua'))()
local S = require('src.world.Gen4DistSurface')
local P = require('src.world.Gen4DistPlatforms')
local Camera = require('src.render.Gen4Camera')

-- sDistortionStepDirection*: a key moves along the plane it is pressed on
check(S.STEP[1].up[2] == 1 and S.STEP[1].left[3] == 1, 'west wall: up climbs, left walks +z')
check(S.STEP[2].left[3] == -1 and S.STEP[3].up[3] == 1, 'east wall left is -z, ceiling up is +z')
check(S.FACE[1].up == 'left' and S.FACE[3].left == 'right', 'the sprite facings are the turning tables')

-- B1F: the wall's jump point and the camera record that turns towards it
local b1 = dw.maps[574]
local j1 = b1 and b1.jumps[1]
check(j1 and j1.playerDir == 2 and j1.targetKind == 1 and j1.targetIndex == 0, 'B1F: pressing west at the edge jumps onto wall 0')
local c1 = b1 and b1.cameras[1]
check(c1 and c1.angleX == 20 and c1.angleY == 45 and c1.steps == 16, 'B1F: the camera turns by (20, 45) over 16 frames')
S.cam.x, S.cam.y, S.cam.n = 0, 0, 0
S.aimCamera(c1)
check(S.cam.toX == 20 and S.cam.toY == 45, 'aimCamera eases towards the record')
S.cam.x, S.cam.y = 0, 0
S.aimCamera({ angleX = 55, angleY = 240, steps = 16 })
check(S.cam.toY == -16, 'a yaw of 240/256 is reached the short way (-16)')
S.cam.x, S.cam.y, S.cam.n = 0, 0, 0

-- B4F: an east wall and a ceiling, joined by a jump point
local b4 = dw.maps[577]
check(b4 and b4.platforms[2].kind == 3, 'B4F platform 2 is a ceiling')
local up
for _, j in ipairs(b4 and b4.jumps or {}) do if j.targetKind == 3 then up = j end end
check(up and up.playerDir == 0 and up.displaceY == 1, 'B4F: up the east wall onto the ceiling')

-- the overlay's own camera replaces the headers' orthographic type 4
local cfg = Camera.forMap({ gen4DistWorld = true, cameraType = 4 })
check(cfg.projection == 'perspective' and math.abs(cfg.distance - 666.92) < 0.01, 'the Distortion World camera is CameraInit\'s, not type 4')
check(math.abs(cfg.pitch - 59.05) < 0.01, 'at the base angle -10750')

-- B2F's rafts: the event parameters are decoded
local e1 = dw.events[575] and dw.events[575][1]
local a1 = e1 and e1.params and e1.params[1]
check(a1 and a1.platformIndex == 1 and a1.offsetZ == -8 and a1.movePlayer == 1 and a1.deltaZ == -4,
      'B2F event 1 carries the player 8 tiles north on raft 1')
local a2 = e1 and e1.params and e1.params[2]
check(a2 and a2.localId == 255 and P.HOP_DIR[a2.movementAction] and P.HOP_DIR[a2.movementAction][3] == 'up',
      'then the player hops north (JUMP_DISTORTION_WORLD_NORTH)')

-- the lift flags: a fresh world has B4F_1 and B5F_1
package.loaded['src.core.Game'] = { save = {} }
check(P.flagSet(3) and P.flagSet(7) and not P.flagSet(0), 'a fresh Distortion World starts with B4F_1 and B5F_1')
check(P.flagSet(11), 'a lift with no flag is always there')
package.loaded['src.core.Game'] = { save = {} }
P.flags(581)
check(P.flagSet(0) and P.flagSet(10), 'starting on B7F sets every lift flag')
package.loaded['src.core.Game'] = nil

-- the ghost props: the floating stepping stones, parsed from each map file
local gp = b1 and b1.ghostProps
check(gp and #gp == 21 and b1.ghostDefaultVisible == 1, 'B1F has 21 ghost props, group 0 visible by default')
local stones = 0
for _, g in ipairs(gp or {}) do if g.propKind == 0 and g.y == 257 then stones = stones + 1 end end
check(stones >= 6, 'B1F: a row of small platforms at floor height (the stepping stones)')
check(dw.maps[576].ghostTriggers and #dw.maps[576].ghostTriggers == 74, 'B3F: 74 ghost triggers')

-- Gen 4 Strength boulders are pushable by their graphics name
local Map = require('src.world.Map')
check(Map.isPushable({ spriteName = 'strength_boulder' }) and Map.isPushable({ spriteName = 'rock' })
      and not Map.isPushable({ spriteName = 'rock_smash' }), 'Platinum and HGSS boulders push; Rock Smash rocks do not')

-- the cast's conditions (CheckFlagCondition) and the B7F teleport wall
package.loaded['src.core.Game'] = { save = { gen4Vars = { [0x4055] = 8 }, flags = {} } }
check(P.condition(3, 8) and P.condition(4, 8) and not P.condition(5, 10), 'progress conditions read 0x4055')
check(P.condition(2, 0) and not P.condition(1, 0), 'a fresh puzzle has the Mesprit boulder in B5F')
package.loaded['src.core.Game'] = nil
check(P.blocked({ header = 581 }, dw.maps[581], 15, 24) and not P.blocked({ header = 581 }, dw.maps[581], 15, 25),
      'B7F: the tile past the teleport is walled off')
local ms = assert(loadfile(cacheDir .. '/map_scripts.lua'))()
local b7 = (ms.maps or ms)['D34R0109']
check(b7 and b7.entries and b7.entries[2] == 'M0388/S001F', "B7F's script 2 (the teleport) is in the map's own list")
local cast = dw.cast[581]
check(cast and #cast == 5 and cast[1].graphicsId == 138, "B7F's cast: Cynthia and Cyrus by progress")

-- THE LIFT'S PASSENGER (BeginMovement / ChangeMaps): Cynthia rides 1F's lift
-- down at progress 2 and B6F's at progress 7, renumbered for the next floor;
-- neither next floor has her in its own table for that moment
do
  local game = { data = { gen4_distortion_world = dw }, save = { gen4Vars = { [0x4055] = 2 }, flags = {} } }
  package.loaded['src.core.Game'] = game
  local hadOW = package.loaded['src.world.OverworldController']
  package.loaded['src.world.OverworldController'] = hadOW or {}
  local function castOf(h, id, val)
    for _, c in ipairs(dw.cast[h]) do
      if c.localId == id and (val == nil or c.flagCondVal == val) then return c end
    end
  end
  local function standing(h, c)
    local m = dw.maps[h]
    local x, y = c.x - (m.offsetX or 0), c.z - (m.offsetZ or 0)
    return { def = { localId = c.localId, gen4DistCast = c, x = x, y = y }, cellX = x, cellY = y }
  end
  local c129 = castOf(573, 129)
  local ow = { npcs = { standing(573, c129) } }
  local pas = P.passengerFor(ow, { header = 573 }, dw.maps[573], 574)
  check(pas and pas.fromId == 129 and pas.localId == 128 and pas.script == nil,
        '1F lift at progress 2 carries Cynthia (1F 129 -> B1F 128)')
  local b1 = { header = 574, objects = {} }
  ow.dwPassenger = pas
  P.spawnCast(ow, b1, dw.maps[574])
  local got
  for _, o in ipairs(b1.objects) do if o.localId == 128 then got = o end end
  check(got and got.x == c129.x - dw.maps[574].offsetX and got.y == c129.z - dw.maps[574].offsetZ
        and ow.dwPassenger == nil, "...and B1F's first-entry scene finds her, on the world tile she rode on")
  game.save.gen4Vars[0x4055] = 3
  check(P.passengerFor(ow, { header = 573 }, dw.maps[573], 574) == nil, 'no passenger once the progress moved on')
  game.save.gen4Vars[0x4055] = 7
  local c134 = castOf(580, 134, 7)
  local ow6 = { npcs = { standing(580, c134) } }
  local pas6 = P.passengerFor(ow6, { header = 580 }, dw.maps[580], 581)
  check(pas6 and pas6.fromId == 134 and pas6.localId == 128 and pas6.script == 6,
        "B6F lift at progress 7 carries her to B7F as B7F_CYNTHIA, script 6")
  package.loaded['src.world.OverworldController'] = hadOW
  package.loaded['src.core.Game'] = nil
end

-- the story's events: every command's arguments decoded
local gr = dw.events[582]
check(gr and gr[3].params[1].scriptId == 7 and gr[3].params[3].progress == 11,
      "Giratina's room: script 7, then progress 11")
local sh = gr and gr[3].params[2]
check(sh and sh.steps == 48 and sh.deltaX == 16 and sh.rot == 3, "and the shadow's flyby template")
check(dw.boulderFalls and #dw.boulderFalls == 14 and dw.boulderFalls[4].flag == 6,
      'sBoulderFallLocations: 14 pits, B6F has the Mesprit pit')
check(dw.externalShadows and dw.externalShadows[1].x == 6 and dw.externalShadows[1].steps == 64,
      "1F's scripted flyby (sGiratinaShadowExternal)")
package.loaded['src.core.Game'] = { data = { gen4_distortion_world = dw }, save = {} }
check(P.fallAt({ header = 579 }, 76 - 57, 68 - 34) ~= nil, "B5F's pit beside Mesprit's boulder takes a boulder")
package.loaded['src.core.Game'] = nil
local S = require('src.world.Gen4DistSurface')
check(S.CASCADES[577] and S.CASCADES[579] and S.CASCADES[577].to == 579, 'the waterfall rides B4F <-> B5F')

-- EventCmdCascadeDown/Up: the rotator's turns add up to the change of side
local down, up = S.CASCADES[577], S.CASCADES[579]
local turnDown = down.startTurn + down.cams[1].rotate + down.cams[2].rotate + down.endTurn
local turnUp = up.startTurn + up.endTurn
check((down.startRoll + turnDown) % 360 == 0, 'riding down turns the sprite from the ceiling to the floor')
check((up.startRoll + turnUp) % 360 == 180, 'riding up turns it from the floor to the ceiling')
check(down.cams[1].at == -20 and down.cams[2].at == -36 and up.cams[1].at == 20, 'the cameras swing at 20 and 36 tiles')
-- the closing turn fires 16 units short (CASCADE_FINISHING_THRESHOLD), which
-- each ride's own speed reaches exactly
local function reaches(c)
  local off = c.delta / 2 * c.turn
  while off < c.final - 16 do off = off + c.delta end
  return off == c.final - 16
end
check(reaches(down) and reaches(up), 'both rides land exactly on the finishing threshold')
check(#down.moveAway == 2 and #up.moveAway == 3, 'walked off two tiles (down) and three (up)')

-- the cast's flights (ShowUxie/Azelf/MespritBoulderTuto, PlayGiratinaArrival)
check(P.tilesOf(272) == 17 and P.tilesOf(271.9) == 16 and P.tilesOf(-32) == -2 and P.tilesOf(-31) == -1,
      '(fx >> 4) / FX32_ONE truncates toward zero')
check(P.LAKE_TRIO.showUxieBoulderTuto.rise == 17 and P.LAKE_TRIO.showAzelfBoulderTuto.rise == 13
      and P.LAKE_TRIO.showMespritBoulderTuto.rise == 9, 'the trio rise 17, 13 and 9 tiles')
local az = P.expandWalk(P.TRIO_WALKS.azelf)
local frames, dx = 0, 0
for _, c in ipairs(az.list) do frames = frames + c.n; dx = dx + (c.dx or 0) end
check(frames == 32 + 32 + 32 + 16 + 32 + 16 and dx == 0, "Azelf's walk: 160 frames, back where it started")
local me = P.expandWalk(P.TRIO_WALKS.playerMesprit)
check(#me.list == 1 + 2 + 2 * (4 + 4 * 3) + 1 and me.list[#me.list].face == 'left', "the player turns round twice after Mesprit")
check(P.ARRIVAL.startY == 160 and math.abs(P.ARRIVAL.skyDelta - 364 / 4096) < 1e-9, "Giratina from ten tiles, the sky by 8/90")
-- Uxie's hover: 3 round trips through the eight steps
local trio = P.LAKE_TRIO.showUxieBoulderTuto
local ow = { dwSprites = {}, player = { cellY = 0 }, map = { def = { header = 579 } }, npcs = {} }
package.loaded['src.core.Game'] = { data = { gen4_distortion_world = dw }, save = {} }
P.castAdd, P.castDelete = function() return true end, function() end
local ev, n = {}, 0
repeat n = n + 1 until P.trioTuto(ow, ev, trio) or n > 2000
check(n < 2000 and ow.dwSprites[131] == nil, "Uxie's tutorial runs to its end and the sprite is let go")
check(n > 300 and n < 500, ("...in about thirteen seconds (%d frames)"):format(n))
package.loaded['src.core.Game'] = nil

-- the sky (tw_arc_etc, Gen4DistSky / Gen4DistSkyView)
check(dw.sky and dw.sky.background and #dw.sky.clouds == 7, 'the sky background and its seven cloud kinds')
local V = require('src.render.Gen4DistSkyView')
V.reset(V.NORMAL)
V.frame(65 * 16); check(V.state.darkness == 0, 'no darkness at the bottom of the world (y 65)')
V.frame(289 * 16); check(V.state.darkness == 12, 'all of it at the top (y 289)')
V.hold(5); V.frame(65 * 16); check(V.state.darkness == 5, 'an event holds the darkness')

-- Platinum's surf mount (surf_mount_renderer.c)
local M = require('src.world.Gen4SurfMount')
check(M.MODEL == 81 and M.MIN_Y == 1 and M.MAX_Y == 4 and M.DELTA == 0.25, 'the surf mount: fldeff 81, bobbing 1..4 by 1/4')
check(M.ANGLE.down == 0 and M.ANGLE.up == 180 and M.ANGLE.left == 270 and M.ANGLE.right == 90, 'and turned with the player')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
