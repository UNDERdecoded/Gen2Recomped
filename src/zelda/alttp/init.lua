-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The Legend of Zelda: A Link to the Past & Four Swords (GBA, USA) -- the game
-- module the Zelda runtime loads (docs/zelda/CONTRACT.md).

local RomMap = require("src.zelda.alttp.RomMap")
local Extract = require("src.zelda.alttp.Extract")

local M = {
  id = "alttp",
  cacheVersion = 32,   -- 32: round 27 team B (Enemies27A/B, Traps27, Mech27, Floors27, Ending27 tables in data.t.d26); 31: round 26 team B (Trinexx and Ganon tables: TurtleRock.lua, Ganon.lua); 30: round 26 team B (the bosses' tables: Agahnim, PoD, Swamp, Skull Woods, Thieves' Town, Ice, Mire in data.t.d26); 29: round 26 team A (Dark World, gear, swim, tools, medallions: ExtractA26.lua);   -- 28: round 26 team B (the later palaces' tables: Dungeons26.lua, Hera.lua); 27: round 25 (the outdoor enemies' tables: OwEnemies.lua); 26: round 24 (the Desert Palace's sprite tables, moving walls, prizes: DesertPalace.lua); 25: round 23 (the desert statue draw table, Desert.lua); 24: round 22 (the shop clerk's draw table, Shop.lua); 23: round 21 (death puff, dash dust, item strip DMA: Effects.lua); 17: round 14 (the OBJ priority tables, Layers.lua); 18: round 15 (animated tile sheets); 19: round 16 (room objects: push blocks, rupee floors...); 20: round 17 (Eastern Palace, world interactions); 21: round 18 (items: bow, bombs, lamp, torches, damage tables); 22: round 20 (sword damage classes, the spin attack)
  gameCode = RomMap.GAME_CODE,
  sha1 = RomMap.SHA1,
}

-- header = the first 0x200 bytes of a cartridge
function M.detect(header)
  return Extract.detect(header)
end

-- extract(romPath, cache, progress, ctx): ctx.bytes is the verified ROM.
function M.extract(romPath, cache, progress, ctx)
  local bytes = ctx and ctx.bytes
  if not bytes and romPath then
    local f = io.open(romPath, "rb")
    if f then bytes = f:read("*a"); f:close() end
  end
  assert(type(bytes) == "string", "ALttP import: no cartridge bytes")
  return Extract.run(bytes, cache, progress, {
    checkpoint = ctx and ctx.checkpoint,
    force = ctx and ctx.fresh,
  })
end

function M.isReady(cache)
  return Extract.isReady(cache)
end

function M.newGame(opts)
  opts = opts or {}
  local cache = opts.cache or opts.root
  local data = opts.data or require("src.zelda.alttp.Data").load(cache)
  local Game = require("src.zelda.alttp.Game")
  return Game.new({
    data = data, cache = cache, input = opts.input, save = opts.save,
    options = opts.options, online = opts.online, host = opts.host,
    headless = opts.headless, skipTitle = opts.skipTitle, mode = opts.mode,
    -- round 14: tests / harnesses (the runtime's options come through host)
    noFrontEnd = opts.noFrontEnd, zoom = opts.zoom, cartTransitions = opts.cartTransitions,
  })
end

return M
