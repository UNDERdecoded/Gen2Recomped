-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum): the two screens a new game opens with -- the television
-- broadcast, and Professor Rowan's introduction.
--
-- NEITHER ARCHIVE HAS A NAME TABLE.  `/demo/intro/intro_tv.narc` has ten
-- members and `/demo/intro/intro.narc` has fifty, and not one of them is
-- named, so the generic screen planner -- which pairs tiles with a palette and
-- a tilemap BY NAME -- cannot touch either.  Every index below is therefore
-- arithmetic, and arithmetic is the thing this project has been burned by
-- most: a member index that is wrong by one still decodes, still composes and
-- still produces a picture.
--
-- So none of it is inferred.  All of it is transcribed from the two files that
-- state it outright -- `RowanIntroTv_InitGraphics` and
-- `RowanIntro_LoadInitialTilemaps` / `_LoadLayer3Tilemap` / `_LoadTilemap` --
-- and every composed picture is then LOOKED AT.  That is what caught the
-- television's palette: composed with the palette the first load names, the
-- broadcast is a black rectangle with coloured noise in it, which reads as a
-- decoder bug rather than as a half-loaded palette.

local Gen4IntroScene = {}

Gen4IntroScene.TV_PATH = "/demo/intro/intro_tv.narc"
Gen4IntroScene.PATH = "/demo/intro/intro.narc"

-- ---------------------------------------------------------------------------
-- The television
-- ---------------------------------------------------------------------------

-- Three background layers, back to front, exactly as RowanIntroTv_InitGraphics
-- assigns them:
--
--   BG_LAYER_MAIN_3   tiles 8, tilemap 7, 256-colour   the broadcast itself
--   BG_LAYER_MAIN_1   tiles 2, tilemap 5, 16-colour    the scanline overlay
--   BG_LAYER_MAIN_0   tiles 1, tilemap 4, 16-colour    the set's bezel
--
-- BG_LAYER_MAIN_2 is initialised and then cleared: it is the CRT band the app
-- scrolls down the screen at run time, not a picture, so there is nothing here
-- to extract for it.
Gen4IntroScene.TV_LAYERS = {
  { name = "broadcast", tiles = 8, tilemap = 7 },
  { name = "scanlines", tiles = 2, tilemap = 5 },
  { name = "bezel",     tiles = 1, tilemap = 4 },
}

-- THE PALETTE IS TWO LOADS AND ONLY THE SECOND ONE HAS THE PICTURE IN IT.
--
--   Graphics_LoadPalette(..., 6, PAL_LOAD_MAIN_BG, 0, 0, ...)
--   Graphics_LoadPaletteWithSrcOffset(..., 9, PAL_LOAD_MAIN_BG,
--                                     0x20 * 2, 0x20 * 2, 0x20 * 14, ...)
--
-- Member 6 fills the whole background palette; member 9 then overwrites
-- colours 32 upwards -- fourteen rows of sixteen -- and the broadcast is drawn
-- almost entirely out of those.  Compose with member 6 alone and the result is
-- a black rectangle with a few coloured pixels in it: a picture, and wrong.
Gen4IntroScene.TV_PALETTE = 6
Gen4IntroScene.TV_PALETTE_OVERLAY = 9
Gen4IntroScene.TV_OVERLAY_FIRST = 32          -- 0x20 * 2 bytes in = colour 32
Gen4IntroScene.TV_OVERLAY_COUNT = 16 * 14     -- 0x20 * 14 bytes

-- ---------------------------------------------------------------------------
-- Rowan's introduction
-- ---------------------------------------------------------------------------

-- The backdrop: one tile sheet, five tilemaps, one palette.
--
-- `RowanIntro_LoadInitialTilemaps` picks the palette by cartridge --
-- 3 for Platinum, 1 for Diamond, 2 for Pearl -- which is worth keeping even
-- though only one of the three is ever asked for here: it is the reason
-- member 3 rather than member 1 is right, and a reader who saw a bare `3`
-- would have no way to tell that from a guess.
Gen4IntroScene.BACKDROP_TILES = 0
Gen4IntroScene.BACKDROP_MAPS = { 4, 5, 6, 7, 8 }
Gen4IntroScene.BACKDROP_PALETTE = { platinum = 3, diamond = 1, pearl = 2 }

-- What each of the five backdrops is, confirmed by looking at every one of
-- them rather than by counting.  Named so a screen can ask for the one it
-- wants instead of an index.
Gen4IntroScene.BACKDROP_ROLE = {
  [1] = "speech",       -- the cream and gold field Rowan stands on
  [2] = "controls_ab",  -- the blue card with the +Control Pad, A and B
  [3] = "controls_xy",  -- the same card with X and Y
  [4] = "plain",        -- blue, no diagram
  [5] = "touchscreen",  -- green, with a message window drawn on it
}

-- THE FIGURES, and why they are all the same size.
--
-- Every one of them is a full-screen 256x192 tilemapped picture rather than a
-- sprite: `RowanIntro_LoadTilemap` loads the figure's TILES into BG layer 1 or
-- 2, loads its palette into row 7 or 8, and then lays them out with tilemap
-- member 23 -- the SAME tilemap for all ten.  So a figure is a (tiles,
-- palette) pair over one shared map, which is why the table in that function
-- is a list of pairs and nothing else.
--
-- Index 0 in the cartridge's table is `{ 0, 0 }`, meaning "no figure"; it is
-- dropped here so this list is one-based with no hole in it.
Gen4IntroScene.FIGURE_TILEMAP = 23
Gen4IntroScene.FIGURES = {
  { name = "rowan",  tiles = 19, palette = 20 },
  { name = "boy_1",  tiles = 9,  palette = 13 },
  { name = "boy_2",  tiles = 10, palette = 13 },
  { name = "boy_3",  tiles = 11, palette = 13 },
  { name = "boy_4",  tiles = 12, palette = 13 },
  { name = "girl_1", tiles = 14, palette = 18 },
  { name = "girl_2", tiles = 15, palette = 18 },
  { name = "girl_3", tiles = 16, palette = 18 },
  { name = "girl_4", tiles = 17, palette = 18 },
  { name = "rival",  tiles = 21, palette = 22 },
}

-- Which figure a screen asks for by role.  The four boy and four girl pictures
-- are poses of the same character, and the intro's gender question needs one
-- of each side by side.
Gen4IntroScene.ROLE = {
  rowan = "rowan", boy = "boy_1", girl = "girl_1", rival = "rival",
}

-- A FIGURE'S PALETTE GOES INTO ROW 7 (layer 1) or ROW 8 (layer 2), and the app
-- then rewrites its tilemap's cells to point at that row
-- (RowanIntro_ChangePaletteAndCopyTilemap).  Extracting one picture at a time
-- there is no second layer to keep out of the way, so the sixteen colours are
-- replicated across every row instead: whatever palette index a cell of the
-- shared tilemap carries, it lands on this figure's own colours.  That is the
-- same picture the hardware draws and it needs no cell rewriting.
Gen4IntroScene.FIGURE_ROWS = 16

-- ---------------------------------------------------------------------------
-- The Poke Ball
-- ---------------------------------------------------------------------------

-- THE STEP THE PORT SKIPPED ENTIRELY.  Reported from play: "in the intro rowan
-- isnt thorwing out a pokemon like he does in the rom".  He does, and this is
-- the art behind it, transcribed from `RowanIntro_LoadPokeballTilemap`.
--
-- THREE PICTURES, NOT ONE.  The ball is one tilemap (40) with one palette (41)
-- and THREE tile sheets loaded into the same place in turn -- 32, then 33, then
-- 34 -- which is the button being pushed in.  Reading it as a single picture is
-- the mistake to avoid: the animation is not a transform of the art, it IS
-- three pieces of art.
--
-- THE PALETTE IS THE THIRD ROW OF MEMBER 41, and nothing says so except the
-- arithmetic in the app: it loads three rows of that member starting at
-- background row 7 and then points the tilemap's cells at row 9 -- the third.
-- So the sixteen colours the ball is drawn in are member 41's colours 32..47.
-- Composing with its first sixteen gives a picture that is wrong without
-- looking broken, which is this archive's whole hazard.
--
-- What the port DOES with these three -- the hold, the flashes, the Pokemon
-- and its arc -- is `Gen4RowanIntro`'s, not this file's: those are frame counts
-- and parabolas rather than member indices, and they belong next to the code
-- that plays them.
--
-- AND THE SIXTEEN TILES ARE LOADED AT TILE 32, which is the other half of the
-- same arithmetic and was missing.  Member 40's cells are tile 0 everywhere
-- except a 32-cell circle that runs 0x20..0x2F -- exactly sixteen indices for
-- a sixteen-tile sheet, with `flipX` doing the ball's right-hand side.  A
-- composition that reads those indices straight finds nothing (the sheet is
-- 512 bytes; tile 32 begins at byte 1024) and draws the sheet's tile 0 into
-- all 736 empty cells instead, which is a screen of one repeated glyph with a
-- 48x48 hole where the ball should be.  That is what shipped, and it is what
-- "the pokeball screen where your supposed to touch the pokeball isnt
-- rendering properly" was.
Gen4IntroScene.BALL = {
  tilemap = 40,
  palette = 41,
  paletteFirst = 32,        -- 0-based; colours 32..47 of member 41
  tileFirst = 32,           -- the tile the sheet is loaded at, not an offset
  frames = { 32, 33, 34 },  -- closed, pushed, pushed further
}

-- ---------------------------------------------------------------------------
-- The words
-- ---------------------------------------------------------------------------

-- Bank 389 (TEXT_BANK_ROWAN_INTRO): 45 entries, read out of this cartridge and
-- checked against every id in pokeplatinum's own text file -- 0 is "Hello
-- there!", 21 is the gender question, 24 asks the player's name, 28 asks the
-- rival's, and 36-44 are the eight preset rival names with "New name!" first.
Gen4IntroScene.BANK = 389

-- Bank 607 (TEXT_BANK_ROWAN_INTRO_TV_APP): one entry, the broadcast's script.
Gen4IntroScene.TV_BANK = 607
Gen4IntroScene.TV_TEXT = 0

Gen4IntroScene.TEXT = {
  hello = 0, myName = 1,
  infoAnythingElse = 9,
  widelyInhabited = 16, havePokeBall = 17, liveAlongside = 19,
  aboutYourself = 20,
  gender = 21, confirmBoy = 22, confirmGirl = 23,
  name = 24, confirmNameMale = 25, confirmNameFemale = 26,
  soYoure = 27, rivalName = 28, confirmRivalName = 29,
  ending = 30,
  choiceControlInfo = 31, choiceAdventureInfo = 32, choiceNoInfo = 33,
  yes = 34, no = 35,
}

-- The control and adventure lectures, in the order the app offers them.  Kept
-- because they are the cartridge's and cost nothing to carry; the screen that
-- plays the intro is free to skip them, and says so where it does.
Gen4IntroScene.CONTROL_INFO = { 2, 3, 4, 5 }
Gen4IntroScene.ADVENTURE_INFO = { 10, 11, 12, 13, 14, 15 }

-- The eight names the cartridge offers for the rival, plus "New name!" first,
-- which is how the menu itself is ordered (entry 36 before 37).
Gen4IntroScene.RIVAL_NAME_FIRST = 36
Gen4IntroScene.RIVAL_NAME_LAST = 44

-- The main line, in order, with what each step does.  A screen walks this
-- rather than hard-coding a sequence of bank indices, so the flow can be read
-- in one place and the indices stay next to the names above.
--
-- `figure` is the picture standing on the backdrop while the line is read;
-- `backdrop` is the role from BACKDROP_ROLE.  A step with `ask` is the one
-- place the player answers something.
Gen4IntroScene.SCRIPT = {
  { text = "hello",           figure = "rowan", backdrop = "speech" },
  { text = "myName",          figure = "rowan", backdrop = "speech" },
  { text = "widelyInhabited", figure = "rowan", backdrop = "speech" },
  -- The Poke Ball, which the port used to skip straight past: the app fades the
  -- ball in, reads this line, waits for the player, and then plays the release.
  -- `scene = "ball"` is what tells the screen this step is not just words.
  -- Rowan does NOT leave for this: his layer is never faded, he is simply on
  -- the other screen while the ball is on the touch one.  With one screen the
  -- ball covers him while it is being pushed in and he is back underneath the
  -- moment the Pokemon is out.
  { text = "havePokeBall",    figure = "rowan", backdrop = "speech", scene = "ball" },
  { text = "liveAlongside",   figure = "rowan", backdrop = "speech" },
  { text = "aboutYourself",   figure = "rowan", backdrop = "speech" },
  { text = "gender",          figure = nil,     backdrop = "plain", ask = "gender" },
  { text = "name",            figure = nil,     backdrop = "plain", ask = "name" },
  { text = "soYoure",         figure = "rival", backdrop = "speech" },
  { text = "rivalName",       figure = "rival", backdrop = "speech", ask = "rivalName" },
  { text = "ending",          figure = "rowan", backdrop = "speech" },
}

-- THE POKEMON ROWAN RELEASES, read from overlay 73 rather than assumed.
--
-- Overlay 73 is the opening's own code (`RowanIntro_LoadBunearySprite` and the
-- cry played as the ball opens).  Retail Platinum names Buneary (427) in both
-- places as an instruction literal; Renegade Platinum edits exactly those two
-- literals to Eevee (133) and touches nothing else in the overlay, which is
-- how this was found: it is the intro's Pokemon, not Amity Square's walkers.
--
-- The sprite loader is a fixed Thumb sequence --
--     ldr  r1, [pc, #n]      ; the species literal
--     str  r2, [sp, #8]      ; 0x9202
--     add  r0, sp, #0x10     ; 0xA804
--     movs r3, #2            ; 0x2302  (FACE_FRONT)
--     bl   <sprite template builder>
-- -- so the species is the literal that `ldr r1` loads there.  Returns nil when
-- the sequence is absent (another build of the overlay), and the screen keeps
-- Buneary.
Gen4IntroScene.OVERLAY = 73
function Gen4IntroScene.monSpecies(overlay, maxSpecies)
  if type(overlay) ~= "string" then return nil end
  local function h16(at)
    local a, b = overlay:byte(at + 1, at + 2)
    if not b then return nil end
    return a + b * 256
  end
  for at = 0, #overlay - 12, 2 do
    local w = h16(at)
    if w and w >= 0x4900 and w < 0x4A00
       and h16(at + 2) == 0x9202 and h16(at + 4) == 0xA804
       and h16(at + 6) == 0x2302 then
      local target = math.floor((at + 4) / 4) * 4 + (w % 256) * 4
      local a, b, c, d = overlay:byte(target + 1, target + 4)
      if d then
        local value = a + b * 256 + c * 65536 + d * 16777216
        if value >= 1 and value <= (maxSpecies or 493) then return value end
      end
    end
  end
  return nil
end

return Gen4IntroScene
