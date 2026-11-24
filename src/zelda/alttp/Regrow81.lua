-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 81: cut bushes, lifted rocks, driven-in pegs and dug ground come
-- back when an area is loaded again.
--
-- The cartridge keeps the overworld's map16 tilemap in RAM and rebuilds it
-- from the area's map (plus the overlays its event bits ask for: opened
-- entrances, bombed walls, ...) each time an area is loaded -- after a
-- scroll to the next area, coming out of a building or a cave, a world
-- crossing, the flute's bird. Tile changes made while Link is there
-- (Overworld_DrawMap16_Persist from the sword / lift / hammer / shovel /
-- dash tile interactions) live only in that RAM copy: they are gone on the
-- next load. The counter of the peg puzzle is zeroed at the same moment
-- (overworld submodules 6 / 0x14 at 0x080744EC; Peg81.lua).
--
-- The port wrote those changes to data.mapPatch for good (round 80: the
-- bushes never grew back). Here the cells G:owTileChange writes (and the
-- big rock's / rock pile's other quarters G:owSetMap16 writes in the same
-- frame, BigRock.lua / Dash.lua) are remembered as passing changes and
-- dropped from data.mapPatch when the area is next loaded (the area or the
-- world changes, or Link comes back out of a room), once a scroll has
-- ended. Changes the overlays make (OwEvents, Castle44, Kiki46, Grate64,
-- the bombed walls, the gates) are not touched. No ROM reads.
-- OURS: the check runs after the frame that changed the area (the
-- cartridge rebuilds the map during the transition).

local M = { NAME = "regrow81" }

function M.extract(rom, R, check) return {} end

local function cellsOf(game, x, y)
  local O = require("src.zelda.alttp.Overworld")
  local tx, ty = math.floor(x / 16) * 16, math.floor(y / 16) * 16
  local screen = O.screenAt(game.link.world, tx, ty)
  if not screen then return nil end
  local n = game.data:mapNumber("bg2", screen)
  local lx, ly = (tx % 512) / 8, (ty % 512) / 8
  return screen, n, { O.cellIndex(lx, ly), O.cellIndex(lx + 1, ly), O.cellIndex(lx, ly + 1), O.cellIndex(lx + 1, ly + 1) }
end

local function remember(game, x, y)
  local screen, n, cells = cellsOf(game, x, y)
  if not screen then return end
  game.passing81 = game.passing81 or {}
  local e = game.passing81[n] or { screen = screen, cells = {} }
  game.passing81[n] = e
  for _, c in ipairs(cells) do e.cells[c] = true end
end

-- drop the passing changes (the area's map rebuilt)
function M.reload(game)
  local list = game.passing81
  game.passing81 = nil
  local dropped = 0
  for n, e in pairs(list or {}) do
    local p = game.data.mapPatch and game.data.mapPatch[n]
    if p then
      for c in pairs(e.cells) do
        if p[c] ~= nil then p[c] = nil; dropped = dropped + 1 end
      end
    end
    if game.ow and game.ow.attrCache then game.ow.attrCache[e.screen] = nil end
    if game.view and game.view.screens then game.view.screens[e.screen] = nil end
  end
  game.regrown81 = (game.regrown81 or 0) + dropped
  require("src.zelda.alttp.Peg81").reset(game)
  return dropped
end

-- the key of the loaded area (nil inside)
local function areaKey(game)
  if game.state ~= "play" or not game.area or not game.link then return nil end
  return tostring(game.link.world) .. ":" .. tostring(game.area.parent or game.area.id)
end

function M.check(game)
  if game.scroll or game.mirrorWarp then return end
  local k = areaKey(game)
  if k == game.areaKey81 then return end
  game.areaKey81 = k
  -- a new key (another area, the other world, or back out of a room); the
  -- first area this game sees was loaded fresh already
  if k and game.areaSeen81 then M.reload(game) end
  if k then game.areaSeen81 = true end
end

function M.install(G)
  if G.regrow81Installed then return end
  G.regrow81Installed = true
  local change0 = G.owTileChange
  function G:owTileChange(x, y, fromTo)
    local r = change0(self, x, y, fromTo)
    if r and self.link then
      remember(self, x, y)
      self.passingFrame81 = self.frame
    end
    return r
  end
  local set0 = G.owSetMap16
  function G:owSetMap16(x, y, id)
    local r = set0(self, x, y, id)
    if r and self.link and self.passingFrame81 ~= nil and self.passingFrame81 == self.frame then remember(self, x, y) end
    return r
  end
  local update0 = G.update
  function G:update(dt)
    local r = update0(self, dt)
    M.check(self)
    return r
  end
end

return M
