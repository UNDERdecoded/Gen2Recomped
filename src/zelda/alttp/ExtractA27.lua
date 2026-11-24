-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Round 27 (team A): the import of this round's world / item / sound
-- modules, one call from Extract.lua (each module reads its own GBA tables).

local X = {}

X.MODULES = {
  { "owe27", "OwEnemies27" }, { "items27", "Items27" }, { "story", "Story27" },
  { "dmap", "DungeonMap" }, { "grove", "Grove" }, { "fairy", "FatFairy" }, { "smith", "Smiths" },
  { "flute", "Flute" },
  { "sfx", "Sfx" },   -- last: it wraps the other modules' call sites
}

-- r30: later rounds' modules (imported after, installed before Hooks28)
X.EXTRA = { { "people30", "Townsfolk30" }, { "spr31", "Sprites31" }, { "games31", "Games31" },
            { "cut32", "Cutscenes32" },   -- r31: Sprites31; r32: Cutscenes32
            { "mus34", "Music34" },       -- r34: the remaining music, more sounds
            { "bird34", "Bird34" },       -- r34: the travel bird drawn
            { "prize43", "Prize43" },     -- r43: the boss prize's spot and fall
            { "tele43", "Telepathy43" },  -- r43: Zelda's telepathy after the Master Sword
            { "castle44", "Castle44" },   -- r44: the castle's gate overlay, Agahnim's barrier
            { "shut44", "Shutters44" },   -- r44: the shutters on a transition inside a room
            { "curt44", "Curtain44" },    -- r44: the curtain door cut with the sword
            { "rc44", "RoomCache44" },    -- r44: where a hurting pit puts Link back
            { "kiki46", "Kiki46" },       -- r46: Kiki the monkey, the Palace of Darkness's door
            { "warp48", "Warp48" },       -- r48: the dungeon warp tile (attribute 0x4B)
            { "hop50", "Hop50" },         -- r50: the indoor ledge hop's fixed flight
            { "arena51", "Arena51" },     -- r51: ancillae on crystal switches, no contact mid-hop (no ROM reads)
            { "fall52", "Fall52" },       -- r52: sprites and ancillae run while Link falls into a pit (no ROM reads)
            { "zora52", "Zora52" },       -- r52: King Zora and the flippers he throws
            { "rcpt52", "Receipt52" },    -- r52: rupee / bomb / arrow receipts, the bomb / arrow fillers
            { "lift52", "Lift52" },       -- r52: the big gray blocks lifted with the Power Glove (no ROM reads)
            { "gen53", "Generous53" },    -- r53: the shopkeeper who gives 300 rupees (Hype Cave, Mini Moldorm cave)
            { "swim54", "Swim54" },       -- r54: swimming indoors (the water hop tables, kSpiralTab1)
            { "blast62", "Blast62" },     -- r62: the exploding wall (door 0x30) and its pull-switch tag
            { "burn63", "Burn63" },       -- r63: damage code 0xFD sets a sprite on fire (SpriteModule_Burn)
            { "push63", "PushWall63" },   -- r63: room tag 0x20, a floor switch blows the exploding wall
            { "anim64", "AnimTile64" },   -- r64: the animated sprite tile slot (the heart container's picture)
            { "grate64", "Grate64" },     -- r64: the Thieves' Town grate, Overworld_AlterGargoyleEntrance
            { "anc65", "AncColl65" },     -- r65: the ancillae's tile class table (the thrown bomb over low walls)
            { "cell66", "Cells66" }, { "blind66", "Blind66" },   -- r66: the opened big-key lock's floor; Blind's picture 21
            { "bottle67", "Bottle67" },   -- r67: the bottle merchant (Sprite_75_BottleVendor)
            { "ice67", "Ice67" },   -- r67: the slippery ice floors (link_flag_moving)
            { "dmg68", "Damage68" },   -- r68: the armour column of kPlayerDamages (no ROM reads)
            { "sfx68", "Sfx68" },   -- r68: swim stroke / ledge hop / pit fall sounds (Sfx.lua's ids)
            { "sfx69", "Sfx69" },   -- r69: the ledge hop's jump / land sounds (Sfx.lua's ids, no ROM reads)
            { "chest70", "Chest70" },   -- r70: hidden chests (tags 0x27 / 0x29-0x32 / 0x3C / 0x3E) until revealed
            { "manip71", "Manip71" },   -- r71: hammer pegs indoors, pots broken by the hammer, the big block lifted whole
            { "rain72", "Rain72" },   -- r72: the Mire's rain (area 0x70 until Ether), the thunder and the cartridge's flash
            { "block72", "Block72" },   -- r72: the lifted big gray block carried / thrown whole (no ROM reads)
            { "splash73", "Splash73" },   -- r73: the splash sound entering deep water (Sfx.lua's id)
            { "tab74", "Tables74" },
            { "tab75", "Tables75" },
            { "wall76", "Wall76" },
            { "tab76", "Tables76" },
            { "shake78", "Shake78" },   -- r78: the moving wall's shake tables and stop sound (RoomTag_MovingWallShakeItUp)
            { "throw79", "Throw79" },     -- r79: the throw's speeds / fall from CarriedSprite_CheckForThrow
            { "cat79", "Catfish79" },   -- r79: the catfish (Quake) and what drowns in deep water
            { "walk80", "Walk80" },   -- r80: the walking probes / diagonal points / masks; the overworld walk on the cartridge's collision
            { "peg81", "Peg81" },     -- r81: the Light World's Turtle Rock peg puzzle (HandlePegPuzzles): order, sounds, the warp
            { "regrow81", "Regrow81" },   -- r81: passing tile changes (bushes, rocks, pegs, digging) dropped on the area's reload (no ROM reads)
            { "pit81", "Pit81" },   -- r81: the pit state's one-frame delay before the fall (the Somaria platform boards first; no ROM reads)
            { "somaria82", "Somaria82" },   -- r82: the Somaria block pushed / launched / lifted / thrown; the fission's on-screen test
            { "hurt82", "Hurt82" },   -- r82: a 0-damage touch knocks Link back without the blink (no ROM reads)
            { "ride82", "Ride82" },   -- r82: the platform keeps dragging Link while he uses an item; the d-pad turns him on it (no ROM reads)
            { "chest83", "Chest83" },   -- r83: the push-block chest tag (RoomTag_PushBlockForChest) and the chest reveal sound
            { "ride83", "Ride83" },   -- r83: the d-pad turns Link on the platform only when he is not busy, vertical first (traced; no ROM reads)
            { "shield84", "Shield84" },   -- r84: the shield branch of Sprite_CheckDamageToLink; the laser beam stopped by the Mirror Shield only
            { "fire85", "Fire85" },   -- r85: the fireball's own shield test indoors (Medusa / statue fireballs, the Red Shield or better)
            { "sword87", "Sword87" },   -- r87: the swing goes on while Link recoils (LinkState_Default's order; no ROM reads)
            { "gt88", "Gt88" },   -- r88: Ganon's Tower's seal (sprite 0x37's trigger, the entrance routine run at import)
            { "holes90", "Holes90" },   -- r90: the chest-hole room tags 0x22 / 0x3B (mask, overlay index)
            { "belt90", "Belt90" },   -- r90: the Somaria block on a conveyor (Ancilla_ApplyConveyor speeds)
            { "burn91", "Burn91" },   -- r91: a burning sprite (state 7) is not met by Link's ancillae (no ROM reads)
            { "fall91", "Fall91" },   -- r91: a pit fall waits while the pegs move (submodule 0x16; no ROM reads)
            { "shutter91", "Shutter91" },   -- r91: a tag does not shut the shutter Link is still walking in through (no ROM reads)
            { "wm92", "Wm92" },   -- r92: the screen stays put while a Wallmaster carries Link off (no ROM reads)
            { "push93", "Push93" },   -- r93: a push block leaves the attribute of the tile under it (no ROM reads)
            { "armos94", "Armos94" },   -- r94 (see Armos94.lua)
            { "fairy94", "Fairy94" },
            { "carry95", "Carry95" },   -- r95 bug: a lifted pot's kind / palette (the pot's lift answer, Sprite_EC's Dark World offset read at import)
            { "lamp95", "Lamp95" },   -- r95 bug: a chest's alternate item (kReceiveItemAlternates read at import), duplicate lamps repaired   -- r94: the fairy flies about (Fairy_HandleMovement; its z speed table read at import)   -- r94: the Armos Knights' back row (y 0x50), the crusher's touch (state 0 only), no heart in GT (no ROM reads)
            { "goriya95", "Goriya95" },
            { "lower96", "Lower96" },
            { "pause97", "Pause97" },
            { "hitbox97", "Hitbox97" },
            { "wizz97", "Wizz97" },
            { "kill98", "Kill98" },
            { "belt98", "Belt98" } }   -- r98: no belt step into a doorway's jamb (the cartridge's leading-edge probes; no ROM reads)   -- r98: the off-screen prep's flags4 0x20 rule and Sprite_KillSelf for deflection 0x40 (masks read at import)   -- r97: indoor sprites pause off screen (the pausing types walked from the sprite table at import)   -- r96: lower-level pots / chests redrawn on the lower map (no ROM reads)   -- r95: the Goriyas in Ganon's Tower (SpritePrep_Eyegore rooms, Goriya tables / literals / immediates read at import)
              -- r76: Kodongo's direction / fire tables, the arrow's recoil on a sprite   -- r76: the Mire moving wall room's map swap (RoomTag_MovingWall_East's own room)
              -- r75: crystal switch palettes, cape depletion timers   -- r74: literals moved to import (detection points, pot switch words, Blind trigger, OAM flags)

function X.extract(t, rom, R, check)
  for _, m in ipairs(X.MODULES) do
    t[m[1]] = require("src.zelda.alttp." .. m[2]).extract(rom, R, check)
  end
  for _, m in ipairs(X.EXTRA) do
    t[m[1]] = require("src.zelda.alttp." .. m[2]).extract(rom, R, check)
  end
end

function X.install(G)
  for _, m in ipairs(X.MODULES) do require("src.zelda.alttp." .. m[2]).install(G) end
  for _, m in ipairs(X.EXTRA) do require("src.zelda.alttp." .. m[2]).install(G) end
  require("src.zelda.alttp.Hooks28").install(G)   -- r28: the items on team B's round-27 hooks
  require("src.zelda.alttp.Barrier29").install(G)   -- r29: the people who block Link indoors
end

return X
