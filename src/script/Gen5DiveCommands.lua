-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ABYSSAL RUINS: SURFACING (0x0DC / 0x0C8), and three presentation-only
-- commands named so they stop reporting as unimplemented.
--
-- READ FROM CODE (Black):
--   0x0DC <zone, warp, x, y, z> (ov10 0x0215ADCC): a location record built
--         from the five values (0x02014184) and stored as the game's special
--         location (0x0201289C). Abyssal Ruins' exits store Undella Bay
--         (zone 240) at matrix (801, 276) and the like; one site in Nuvema
--         stores zone 391 (5, 6)
--   0x0C8 <mode> (ov21 0x021C46A4): a task the script waits on; 0 dives
--         (0x021D2418: the camera drops 0x40 units over 40 frames, SE 0x63C,
--         then the warp below), 1 / 2 surface (0x021D2440 -> 0x021D2358: SE
--         0x63C, 24 frames, then a warp to the special location,
--         0x02184F88) -- every script site is a surfacing: `0DC ..., 0C8 1`
--   0x252 (ov21 0x021B2FB0 -> 0x021BC5A0): the current zone's camera record
--         applied again after a fade (Castelia / Nimbasa interiors); this
--         port's camera already follows the zone, so nothing to do
--   0x033 <flag> (ov21 0x021B15C8): a field byte (+0x160, 0x02193208) and
--         the script system's bit 9 set / cleared (0x02159144 / 0x02159168)
--         round the Musical's stage and Anville's turntable -- no visible
--         effect
--   0x076 <dir, frames, units, sign> (ov21 0x021B1D64): the field camera
--         slid up or down by <units> over <frames> (0x021C78DC /
--         0x021C6DE0) before Abyssal Ruins' stairs warp -- not ported
-- INFERRED: the surfacing arrives on the water (surfing); the frames are
-- folded into the warp's own fade. Mode 0 (the dive down) is
-- src/world/Gen5Dive.lua's table and landing.

local M = {}

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

M.SE = 0x63C

local function G4() return require("src.script.Gen4Commands") end

function Commands.g5_special_location(ctx, zone, warp, x, y, z)
  local v = function(a) return math.floor(tonumber(G4().valueOf(ctx, a)) or 0) end
  if ctx.save then
    ctx.save.gen5SpecialLocation = { zone = v(zone), warp = v(warp), x = v(x), y = v(y), z = v(z) }
  end
end

function Commands.g5_dive(ctx, mode)
  local m = math.floor(tonumber(G4().valueOf(ctx, mode)) or 0)
  if m == 0 then
    -- the dive itself (src/world/Gen5Dive.lua): the table's destination,
    -- landing on the zone's own location, on foot
    local Dive = require("src.world.Gen5Dive")
    local ow = ctx.overworld
    local dest = Dive.destination(ow)
    local mapId, x, y
    if dest then mapId, x, y = Dive.arrival(ctx.game and ctx.game.data, dest) end
    if not mapId then
      require("src.core.Logger").warn("gen5 dive: no destination here -- skipped")
      return
    end
    pcall(function() require("src.core.Sound").play(ctx.game.data, M.SE) end)
    if ow and ow.player then ow.player.surfing = false end
    return Commands.g4_warp(ctx, dest, x, y, 0)
  end
  local loc = ctx.save and ctx.save.gen5SpecialLocation
  if not loc then
    require("src.core.Logger").warn("gen5 dive: mode %d without a special location -- skipped", m)
    return
  end
  pcall(function() require("src.core.Sound").play(ctx.game.data, M.SE) end)
  local ow = ctx.overworld
  local p = ow and ow.player
  if p then p.surfing = true end
  return Commands.g4_warp(ctx, loc.zone, loc.x, loc.z, 0)
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwspeciallocation = L.bwspeciallocation or function(ins, s)
    local a = ins.args
    emit(s, { "g5_special_location", a[1], a[2], a[3], a[4], a[5] })
  end
  L.bwdive = L.bwdive or function(ins, s) emit(s, { "g5_dive", ins.args[1] }) end
end

return M
