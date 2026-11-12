-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE BIG ROCKS (round 25): the 32x32 rocks outdoors (the one in front of
-- the old man's cave), as the cartridge lifts them:
--
--   * which glove a liftable attribute wants: TileDetect's kTile50data
--     (the GBA's u16 copy at 0x16831E: 0x54, 0x52, 0x50, 0x51, 0x53, 0x55,
--     0x56) indexes kGetBestActionToPerformOnTile_a (0x168268: 0, 1, 0, 0,
--     2, 1, 2): 0x52 / 0x55 the Power Glove, 0x53 / 0x56 the Titan's Mitt
--     (Carry.lua's pair rule gave 0x55 / 0x56 none and 0x53 the glove);
--   * Overworld_HandleLiftableTiles: a big rock's map16 (0x36D, 0x36E, 0x374,
--     0x375 the light one; 0x23B-0x23E the heavy one) -> SmashRockPile_fromLift:
--     the rock's top left (kBigRockTab1 0, -1, -64, -65 map16 cells), its
--     secret (Overworld_RevealSecret; a hole / stairs: door counter 80),
--     Overworld_DoMapUpdate32x32_B: the four tiles become kDoorAnimTiles
--     [20..23] (0xDCD-0xDD0) or [40..43] (0x918-0x91B), as Dash.rockPile;
--     Link lifts it (kLink_Lift_tab kind 6 light / 7 heavy).
--
-- OURS: the carried / thrown rock is the screen's own 32x32 picture of it
-- (Sprite_EC_ThrownItem's large drawing is not ported); no sound.

local B = {}

B.NEED = { [0x54] = 0, [0x52] = 1, [0x50] = 0, [0x51] = 0, [0x53] = 2, [0x55] = 1, [0x56] = 2 }
B.LIGHT = { [0x36D] = 0, [0x36E] = 1, [0x374] = 2, [0x375] = 3 }
B.HEAVY = { [0x23B] = 0, [0x23C] = 1, [0x23D] = 2, [0x23E] = 3 }
B.TAB_DX = { [0] = 0, -16, 0, -16 }
B.TAB_DY = { [0] = 0, 0, -16, -16 }

-- the map16 number of the 16x16 tile at world (x, y), or nil
local function map16At(game, x, y)
  local m16 = game.data.roomIdx and game.data.roomIdx.map16
  if not m16 then return nil end
  local O = require("src.zelda.alttp.Overworld")
  local tx, ty = math.floor(x / 16) * 16, math.floor(y / 16) * 16
  local screen = O.screenAt(game.link.world, tx, ty)
  if not screen then return nil end
  local n = game.data:mapNumber("bg2", screen)
  local lx, ly = (tx % 512) / 8, (ty % 512) / 8
  local cells = { O.cellIndex(lx, ly), O.cellIndex(lx + 1, ly), O.cellIndex(lx, ly + 1), O.cellIndex(lx + 1, ly + 1) }
  for _, set in ipairs({ B.LIGHT, B.HEAVY }) do
    for id in pairs(set) do
      local w = m16[id]
      if w then
        local same = true
        for c = 1, 4 do if game.data:mapWord(n, cells[c]) ~= w[c] then same = false break end end
        if same then return id end
      end
    end
  end
end
B.map16At = map16At

-- lift the big rock at (px, py) (the point Link's lift checks)
function B.lift(game, px, py)
  local id = map16At(game, px, py)
  if not id then return false end
  local heavy = B.HEAVY[id] ~= nil
  local q = heavy and B.HEAVY[id] or B.LIGHT[id]
  if (heavy and 2 or 1) > game:gloveLevel() then return false end
  local tx, ty = math.floor(px / 16) * 16, math.floor(py / 16) * 16
  local ux, uy = tx + B.TAB_DX[q], ty + B.TAB_DY[q]
  -- the picture before it changes (32x32 from the screen)
  local img, quad
  local O = require("src.zelda.alttp.Overworld")
  local screen = O.screenAt(game.link.world, ux, uy)
  if screen and game.view and love and love.graphics then
    local src = game.view:screen(screen).bg2
    local cv = love.graphics.newCanvas(32, 32)
    cv:setFilter("nearest", "nearest")
    love.graphics.push("all")
    love.graphics.setCanvas(cv)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.origin()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(src, love.graphics.newQuad(ux % 512, uy % 512, 32, 32, 512, 512), 0, 0)
    love.graphics.pop()
    img, quad = cv, love.graphics.newQuad(0, 0, 32, 32, 32, 32)
  end
  -- the secret at the top left, then the four tiles
  local first = heavy and 0x23B or 0x36D
  local s0 = game.secretsFound or 0
  game:owTileChange(ux, uy, { [first] = 0xDCD })
  local hole = (game.secretsFound or 0) > s0 and game.lastSecret == 0xFF
  local base = hole and 0x918 or 0xDCD
  for k = 0, 3 do
    if hole or k > 0 then game:owSetMap16(ux + (k % 2) * 16, uy + math.floor(k / 2) * 16, base + k) end
  end
  game.bigRocks = (game.bigRocks or 0) + 1
  game:startLift({ img = img, quad = quad, x = ux - 8, y = uy - 8, kind = "bush", what = heavy and 7 or 6, big = true })
  return true
end

function B.install(G)
  local C = require("src.zelda.alttp.Carry")
  -- the cartridge's glove rule by attribute (Carry reads it through C.need)
  C.need = function(a) return B.NEED[a] or 3 end
  local try0 = G.tryLift
  function G:tryLift()
    if self.state == "play" and not self.carry then
      local Ca = require("src.zelda.alttp.Carry")
      local q = Ca.QUERY[self.link.facing]
      local px, py = self.link.x + q[1], self.link.y + q[2]
      local a = self.ow:attrAt(self.link.world, px, py)
      if (a == 0x55 or a == 0x56) and B.lift(self, px, py) then return true end
    end
    return try0(self)
  end
end

return B
