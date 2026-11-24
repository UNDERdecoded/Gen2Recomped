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
  cacheVersion = 77,   -- 77: round 90 (Holes90: the chest-hole room tags 0x22 / 0x3B -- the chest mask and overlay index immediates, data.t.holes90; Belt90: the Somaria block's conveyor speeds from Ancilla_ApplyConveyor, data.t.belt90); 76: round 88 (Gt88: Ganon's Tower's seal -- the trigger's area / crystals / event bit / sprite / timer / trigger immediates, the entrance routine's frames run at import, data.t.gt88); 75: round 85 (Fire85: the fireball's shield test -- level, Link box tables, remap, spawn flags4, sound -- from Sprite_Fireball / Sprite_SpawnFireball, data.t.fire85); 74: round 84 (Shield84: Sprite_CheckDamageToLink's shield branch -- the facing tables, flag bit, sounds, type numbers -- and LaserEye_FireBeam's Mirror Shield level, data.t.shield84); 73: round 83 (Chest83: the push-block chest tag number and the reveal sound from the tag routine table / RoomTag_OperateChestReveal, data.t.chest83; Ride83: no ROM reads); 72: round 82 (Somaria82: the Somaria block's push / launch / lift / throw tables and immediates, data.t.somaria82; Hurt82: no ROM reads); 71: round 81 (Peg81: HandlePegPuzzles' positions, count, sounds and event bit, data.t.peg81; Regrow81: no ROM reads); 70: round 80 (Walk80: TileDetect_Movement_Y / _X's probe tables, TileDetect_Diagonal's points and LimitDirections' masks, data.t.walk80); 69: round 79 (Catfish79: the catfish's tables, timers, message and medallion from its code, data.t.cat79; Throw79: the throw's x / y / z speed tables and fall, data.t.throw79); 68: round 78 (Shake78: RoomTag_MovingWallShakeItUp's two offset tables and the wall's stop sound, data.t.shake78); 67: round 76 (Wall76: the Mire moving wall room's two LZ77 maps and attribute strip, data.t.wall76); 66: round 75 (Tables75: kCrystalSwitchPal, kCapeDepletionTimers, data.t.tab75); 65: round 74 (Tables74: TileDetectNearby's points, the pot switch words, Blind's trigger, Agahnim / Gibo OAM flags, data.t.tab74); 64: round 73 (Sfx.lua: the splash site 0x080AD20A, data.t.sfx.ev.splash; Splash73 plays it); 63: round 72 (Rain72: OverworldOverlay_HandleRain's area / frames / thunder id / flash levels, data.t.rain72); 62: round 71 (Manip71: the hammer peg's words / state, the hole replacement table and sounds, the pegs per room, data.t.manip71); 61: round 67 (Bottle67: the bottle merchant's draw entries, messages, price, receipt, data.t.bottle67; Ice67: the ice floor's handler check and top speed, data.t.ice67); 60: round 66 (Cells66: the opened big-key lock's floor filler per room, data.t.cell66; Blind66: no ROM reads); 59: round 65 (AncColl65: kAncilla_TileCollClass and the probe offsets, data.t.anc65); 58: round 64 (AnimTile64: DecodeAnimatedSpriteTile_variable's table and slot, the heart container's variant, data.t.anim64; Grate64: the Thieves' Town grate and the gargoyle entrance's tiles, data.t.grate64); 57: round 63 (Burn63: the burn code 0xFD, SpriteModule_Burn delay / flames, data.t.burn63; PushWall63: room tag 0x20, data.t.push63); 56: round 62 (Blast62: the exploding wall door 0x30 and RoomTag_PullSwitchExplodingWall, data.t.blast62); 55: round 60 (Hole60: the overworld hole keys' mask and drop lift, RomTables hole60.*; Slope60: the indoor diagonal wall slide tables, slope60.*); 54: round 59 (OwEdge59: the overworld edge test and transition walk, RomTables edge59.*); 53: round 54 (Swim54: the indoor water hop tables and kSpiralTab1, data.t.swim54); 52: round 53 (Generous53: the shopkeeper kinds by room, the 300-rupee man's message and item, data.t.gen53); 51: round 52 (Zora52: King Zora's tables, messages and price, data.t.zora52; Receipt52: the receipt rupee amounts and bomb counts, data.t.rcpt52); 50: round 50 (Hop50: the indoor ledge hop speeds, z speeds, timers and gravity, data.t.hop50); 49: round 48 (Warp48: the dungeon warp tile's probe, sound and handler check); 48: round 46 (Kiki46: Kiki the monkey's tables and code numbers, the Palace of Darkness door overlay run from the GBA routine, data.t.kiki46); 47: round 44 (Castle44: the castle event overlay run from the GBA routine, the barrier draw tables, data.t.castle44); 46: round 43 (Prize43: the falling prize spot tables, data.t.prize43; Telepathy43: the telepathy follower immediates, data.t.tele43); 45: round 42 (Hera: the pit fall tables, data.t.d26.hera.fallGfx / fallMask / fallHH / fallHelm); 44: round 41 (Hera: the Firebar ball scales, data.t.d26.hera.barScale); 43: round 40 (DungeonMap: the map screen's chars, frame map, box words and palette, data.t.dmap.art); 42: round 38 (RomTables: Sahasrahla's boots table and his last branch, the old man's revert compare, the 20-rupee fee); 41: round 37 (RomTables: the other message entry points and message tables, the bee price, the door scroll walk, the new-file stats, more code-immediate prices); 40: round 36 (FrontRun: the front end's OBJ layouts and display registers from the cartridge's own code run at import, alttp_front.lua layouts; the item strip from the cartridge's loader, data.t.strip36; RomTables code-immediate kinds imm / msg and 14 more specs); 39: round 35 (RomTables: the modules' small tables read from the ROM, data.t.rt35); 38: round 34 (Music34: the music / sound call-site ids, boss rooms, low-health table: data.t.mus34; Bird34: the travel bird tables, data.t.bird34); 37: round 33 (AlttpSynth: the sound bank image snd.bin, data.t.sfx.entMusic); 36: round 32 (Sfx.lua: the sound ids, call-site ids and the sound bank walk, data.t.sfx); 35: round 31 (Sprites31 / Games31 / DungeonMap tables: data.t.spr31, games31, dmap); 34: round 30 (Townsfolk30 / Smiths / Flute tables: data.t.people30, smith, flute); 33: round 29 (Grove.lua: the special-area and Master Sword tables, data.t.grove); 32: round 27 team B (Enemies27A/B, Traps27, Mech27, Floors27, Ending27 tables in data.t.d26); 31: round 26 team B (Trinexx and Ganon tables: TurtleRock.lua, Ganon.lua); 30: round 26 team B (the bosses' tables: Agahnim, PoD, Swamp, Skull Woods, Thieves' Town, Ice, Mire in data.t.d26); 29: round 26 team A (Dark World, gear, swim, tools, medallions: ExtractA26.lua);   -- 28: round 26 team B (the later palaces' tables: Dungeons26.lua, Hera.lua); 27: round 25 (the outdoor enemies' tables: OwEnemies.lua); 26: round 24 (the Desert Palace's sprite tables, moving walls, prizes: DesertPalace.lua); 25: round 23 (the desert statue draw table, Desert.lua); 24: round 22 (the shop clerk's draw table, Shop.lua); 23: round 21 (death puff, dash dust, item strip DMA: Effects.lua); 17: round 14 (the OBJ priority tables, Layers.lua); 18: round 15 (animated tile sheets); 19: round 16 (room objects: push blocks, rupee floors...); 20: round 17 (Eastern Palace, world interactions); 21: round 18 (items: bow, bombs, lamp, torches, damage tables); 22: round 20 (sword damage classes, the spin attack)
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
