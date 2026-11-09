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
  cacheVersion = 5,
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
  })
end

return M
