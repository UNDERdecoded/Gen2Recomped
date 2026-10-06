-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) user interface: which archive members make up each screen.
--
-- The title sequence, the start menu, the summary pages, the bag, the trainer
-- card and the Poketch are all built the same way -- tiles, a palette and a
-- tilemap -- but the three parts are NOT stored together and NOT in a fixed
-- order.  In pl_winframe, message_box_00's tiles are member 3 and its palette
-- is member 26; taking members in threes puts the wrong palette on every
-- frame, which produces a picture rather than an error, in the wrong colours.
--
-- What pairs them is the NAME.  Gen4Archives recovers the names, and this
-- module says what to do with them:
--
--   * A group with tiles, a palette and a tilemap is a SCREEN -- compose all
--     three and you have the picture as the game draws it.
--   * A group with only a tilemap borrows the tiles and palette from the
--     archive's main sheet.  This is how the ten summary pages work: one
--     shared 480-tile sheet, ten tilemaps over it.
--   * A group with tiles and a palette but no tilemap is a SHEET -- a set of
--     pieces the game assembles through OAM, not a screen.  It is laid out at
--     a stated width so it can be looked at, and that layout is provisional.
--
-- The point of the table below is that it is nearly all derivable.  Only the
-- shared-sheet choice and the sheet widths are stated, and each is stated
-- because the archive genuinely does not record it.

local Gen4Archives = require("src.import.Gen4Archives")

local Gen4Screens = {}

-- The archives that make up the parts of the game the player actually looks
-- at.  `label` is what the progress line says; `shared` names the group that
-- supplies tiles and palette to tilemap-only groups; `tilesWide` is the
-- fallback layout width for sheets that carry no size, and `tilesWideFor`
-- overrides it for the ones whose real width is known.
--
-- A WRONG WIDTH IS NOT A WRONG SIZE, IT IS A DIFFERENT PICTURE.  The tiles
-- are all there and all in order either way, so nothing fails and nothing
-- looks empty; the pieces simply land next to the wrong neighbours.  That is
-- why `tilesWideFor` states a width rather than letting the fallback stand:
-- `pocket_selector_icons` came out 64x64 instead of 256x16 and drew as tile
-- soup in the bag's pocket strip, and measuring the 64x64 file only ever
-- confirmed whatever the 64x64 file happened to contain.
--
-- THE FALLBACK WAS ALMOST NEVER RIGHT.  The cache already marks every sheet
-- whose width it guessed -- `provisionalLayout` in `gen4_graphics` -- and
-- there are 113 of them.  Checked one by one against the width pokeplatinum
-- states for the same graphic: 110 wrong, 3 right, and the three are right by
-- coincidence rather than by rule.  Eight tiles was never a measurement; it
-- was the number a sheet gets when nothing knows.  The widths below are the
-- cartridge's.
Gen4Screens.ARCHIVES = {
  {
    path = "/demo/title/titledemo.narc", label = "title screen",
    out = "title", tilesWide = 8,
  },
  {
    path = "/graphic/menu_gra.narc", label = "menus",
    out = "menu", tilesWide = 8,
  },
  {
    path = "/graphic/pl_winframe.narc", label = "window frames",
    out = "windows", tilesWide = 8,
  },
  {
    path = "/graphic/touch_subwindow.narc", label = "touch sub-windows",
    out = "touch", tilesWide = 8,
    tilesWideFor = {
      yes_no_button = 29,
    },
  },
  {
    path = "/graphic/config_gra.narc", label = "options screen",
    out = "options", tilesWide = 8,
    tilesWideFor = {
      tiles = 5,
    },
  },
  {
    path = "/graphic/pl_pst_gra.narc", label = "summary screen",
    out = "summary", shared = "tiles_main", tilesWide = 8,
    tilesWideFor = {
      a_button = 2, ability = 4, alert = 4, blue = 4, careless = 4,
      carnival = 4, cherish_ball = 2, classic = 4, dive_ball = 2,
      double_ability = 4, downcast = 4, dummy121 = 4, dummy_12 = 4,
      dummy_13 = 4, dummy_14 = 4, dummy_15 = 4, dusk_ball = 2,
      festival = 4, footprint = 4, gorgeous = 4, gorgeous_royal = 4,
      great_ability = 4, great_ball = 2, green = 4, heal_ball = 2,
      history = 4, hoenn_artist = 4, hoenn_champion = 4, hoenn_contest = 4,
      hoenn_contest_hyper = 4, hoenn_contest_master = 4,
      hoenn_contest_super = 4, hoenn_country_national = 4,
      hoenn_earth_world = 4, hoenn_effort = 4, hoenn_marine_land_sky = 4,
      hoenn_victory = 4, hoenn_winning = 4, legend = 4, luxury_ball = 2,
      marking_circle = 1, marking_diamond = 1, marking_heart = 1,
      marking_square = 1, marking_star = 1, marking_triangle = 1,
      master_ball = 2, multi_ability = 4, nest_ball = 2, net_ball = 2,
      pair_ability = 4, poke_ball = 2, premier = 4, premier_ball = 2,
      quick_ball = 2, record = 4, red = 4, relax = 4, repeat_ball = 2,
      royal = 4, safari_ball = 2, shiny_and_pokerus_cured_icon = 1,
      shock = 4, sinnoh_champion = 4, sinnoh_contest = 4,
      sinnoh_contest_great = 4, sinnoh_contest_master = 4,
      sinnoh_contest_ultra = 4, smile = 4, snooze = 4, sub_buttons = 30,
      tiles_main = 32, timer_ball = 2, ultra_ball = 2, world_ability = 4,
    },
  },
  {
    path = "/graphic/pl_plist_gra.narc", label = "party screen",
    out = "party", tilesWide = 8,
    tilesFrom = { menu = "menu_tiles", menu_panels = "menu_tiles", subscreen = "subscreen_tiles" },
    palettesFrom = { menu_panels = "menu" },
    tilesWideFor = {
      touch_button = 5,
    },
  },
  {
    path = "/graphic/pl_bag_gra.narc", label = "bag",
    out = "bag", tilesWide = 8,
    -- The header's word where nothing else states one; the Pokedex row explains
    -- why that is the cartridge speaking rather than a decoder guessing.  Here it
    -- moves no pixels -- member 38 declares the 8 it was already laid out at, and
    -- the composed bytes are identical either way -- so all it does is stop the
    -- record calling a width the cartridge supplied "provisional".
    preferDeclaredSize = true,
    -- Both of these are blitted as BACKGROUND bitmaps rather than drawn as
    -- sprites, so neither has a cell bank to take its shape from, and both
    -- are the cartridge's own numbers rather than a shape that looked right:
    --
    --   * `BagUI_DrawPocketSelectorIcons` (src/applications/bag/windows.c)
    --     blits from a source bitmap declared `32 * POCKET_MAX` by 16, and
    --     POCKET_MAX is 8 -- 256 by 16, which is 32 tiles by 2.  Thirty-two
    --     by two is sixty-four tiles, which is exactly what the member holds,
    --     so the byte count agrees with the declared shape.
    --   * `buttons` is 810 tiles laid thirty wide; the member rounds up to a
    --     whole row, which is where the six spare tiles come from.
    tilesWideFor = {
      buttons = 30, pocket_selector_icons = 32,
    },
  },
  {
    path = "/graphic/trainer_case.narc", label = "trainer card",
    out = "trainer_card", tilesWide = 8,
    tilesWideFor = {
      ace_trainer_f = 10, ace_trainer_m = 10, battle_girl = 10,
      beauty = 10, black_belt = 10, bug_catcher = 10, cowgirl = 10,
      idol = 10, lady = 10, lass = 10, player = 32, player_dp = 32,
      psychic_m = 10, rich_boy = 10, roughneck = 10, ruin_maniac = 10,
      school_kid_m = 10, socialite = 10, trainer_card = 16,
    },
    -- The card's two faces share one sheet, and so do the two trainers and
    -- the two Diamond/Pearl trainers.  See `tilesFrom` in `plan`.
    tilesFrom = {
      trainer_card_front = "trainer_card",
      trainer_card_back = "trainer_card",
      lucas = "player", dawn = "player",
      lucas_dp = "player_dp", dawn_dp = "player_dp",
    },
    -- AND THE PALETTE IS A SEPARATE QUESTION FROM THE SHEET.  This archive
    -- carries thirteen NCLRs and none of them is named after the card, so the
    -- front, the back and the two trainers all fell through to the shared
    -- palette -- which here resolves to `badge_case_lid_tiles.NCLR`, the
    -- first group in the archive holding all three roles.  Lucas came out in
    -- the lid's colours: tan cap, washed-out jacket, brown trousers, the
    -- right shape in the wrong paint.  `TrainerCase_DrawTrainerCard` loads
    -- `trainer_card_normal.NCLR` over the whole sub-BG palette first and says
    -- so in its own comment -- "will mostly be overwritten ... with the
    -- exception of the palette for the trainer sprite" -- so that one file is
    -- the palette for all four.
    -- THE CARD'S SIX LEVELS AND ITS NO-DEX FACE ARE THE SAME PICTURE IN A
    -- DIFFERENT PALETTE, and they are not a tint.  `TrainerCase_LoadCardPalette`
    -- swaps rows 1-3 and 15 by `TrainerCase_CalculateTrainerCardLevel`, and the
    -- front's tiles use ONLY rows 0-3 with row 0 byte-identical in all seven
    -- files -- so one compose of the same tilemap against each NCLR is the
    -- whole difference, with no stitching and no shift.
    --
    -- WHAT THE SWAP ACTUALLY DRAWS, looked at rather than assumed: the STAR
    -- RATING in the top-right corner is painted by the palette.  The star
    -- tiles are in the tilemap the whole time and the normal palette makes
    -- them the colour of the card; cobalt reveals one, bronze two, silver
    -- three, gold four, black five.  And `no_dex` hides the POKeDEX row's
    -- BAND the same way, which is why `TrainerCard_DrawFrontText` only has to
    -- skip the text.  A port drawing the normal face to a player without a
    -- Pokedex shows an empty slot the cartridge does not.
    paletteVariants = {
      trainer_card_front = {
        { suffix = "_cobalt", palette = "trainer_card_cobalt" },
        { suffix = "_bronze", palette = "trainer_card_bronze" },
        { suffix = "_silver", palette = "trainer_card_silver" },
        { suffix = "_gold", palette = "trainer_card_gold" },
        { suffix = "_black", palette = "trainer_card_black" },
        { suffix = "_no_dex", palette = "trainer_card_normal_no_dex" },
      },
      trainer_card_back = {
        { suffix = "_cobalt", palette = "trainer_card_cobalt" },
        { suffix = "_bronze", palette = "trainer_card_bronze" },
        { suffix = "_silver", palette = "trainer_card_silver" },
        { suffix = "_gold", palette = "trainer_card_gold" },
        { suffix = "_black", palette = "trainer_card_black" },
        { suffix = "_no_dex", palette = "trainer_card_normal_no_dex" },
      },
    },
    palettesFrom = {
      trainer_card = "trainer_card_normal",
      trainer_card_front = "trainer_card_normal",
      trainer_card_back = "trainer_card_normal",
      lucas = "trainer_card_normal", dawn = "trainer_card_normal",
      -- `lucas_dp` and `dawn_dp` are NOT here on purpose.  Their palette is
      -- `player_dp_tiles.NCLR`, but the cartridge loads its first two rows to
      -- PLTT_OFFSET(4) -- so the file's colours 0..31 are the tilemap's
      -- colours 64..95, and composing against it unshifted is wrong by 64.
      -- Naming it here would look right and read wrong.  A palette shift is
      -- its own change; these two pictures are unreachable in a Platinum
      -- port meanwhile.
    },
  },
  {
    path = "/graphic/poketch.narc", label = "Poketch",
    out = "poketch", tilesWide = 8,
    -- As the bag: members 8 and 23 declare the 8 they were already drawn at, so
    -- this moves no pixels and only makes the provenance honest.
    preferDeclaredSize = true,
    shared = "generic",
    firstTileFor = { poketch_border = 64 },
    paletteSlotFor = { poketch_border = 15 },
    tilesWideFor = {
      generic = 4,
    },
    -- Both watches draw on one background, and the digit strip has its own.
    tilesFrom = {
      digital_watch = "watch", analog_watch = "watch",
      digital_watch_digits = "generic",
      marking_map = "map", berry_searcher = "map",
    },
  },
  {
    path = "/graphic/shop_gra.narc", label = "shop",
    out = "shop", tilesWide = 8,
    tilesWideFor = {
      tiles = 32,
    },
  },
  {
    path = "/graphic/tmap_gra.narc", label = "town map",
    out = "town_map", tilesWide = 8,
    tilesWideFor = {
      bottom_screen_button = 34, bottom_screen_map = 64,
      top_screen_map = 64,
    },
  },
  {
    path = "/resource/eng/zukan/zukan.narc", label = "Pokedex",
    out = "pokedex", tilesWide = 8,
    -- THE HEADER'S WORD, because one sheet here was laid out at a width the file
    -- contradicts: `weight_scale` (member 36) says 16x2 and was laid out 8 wide,
    -- so it extracted as 64x32 instead of 128x16 -- the same thirty-two tiles
    -- re-flowed into the wrong rectangle.
    --
    -- WHAT THIS IS AND IS NOT WORTH: nothing draws this sheet today.
    -- `Gen4Pokedex` takes its art from `gen4_dex`, not from
    -- `gen4_graphics.screens`, so no player sees either rectangle and pass 157
    -- said so.  The fix is worth making anyway for one reason: with it, the
    -- provenance census can say that NO sheet in this table is laid out at a
    -- width nobody states, and mean it exactly rather than with an exception
    -- carried in a comment.  An exact zero is checkable; "one known wrong one"
    -- decays into the next stale figure.
    --
    -- Three sources agree on 128x16, which is why this is the cartridge's word:
    --
    --   * the NCGR states tilesX=16, tilesY=2, and 16*2 is exactly its 32 tiles,
    --     so the declared shape accounts for the whole member with none spare;
    --   * pokeplatinum centres it as `xPos = 128 - (128 / 2)` and
    --     `yPos = 96 - (16 / 2)` in ov21_021E7F40 -- the centring arithmetic
    --     spells the sprite's size out, 128 by 16 pixels;
    --   * it is loaded as a `SoftwareSprite`, not an OAM one, so there is no
    --     cell bank to take the shape from and the header is the only in-file
    --     source.  That is also why no amount of bank work would have found it.
    --
    -- The flag changes exactly this one sheet.  The three widths below are
    -- `stated` and win ahead of it, and the other eighteen sheets in this
    -- archive come from cell banks and never reach the width question at all.
    preferDeclaredSize = true,
    tilesWideFor = {
      entry_main = 32, entry_sub = 32, scroll_sub_background = 32,
    },
  },
  {
    path = "/graphic/mail_gra.narc", label = "mail",
    out = "mail", tilesWide = 8,
  },
  {
    path = "/graphic/ntag_gra.narc", label = "berry tag",
    out = "berry_tag", tilesWide = 8,
  },
  {
    path = "/graphic/pl_font.narc", label = "fonts",
    out = "font", tilesWide = 16,
    tilesWideFor = {
      font_special_chars = 23, screen_indicators = 3,
    },
  },
  -- THE UNDERGROUND'S MINING ART, and the one archive in this table that needs
  -- no widths written down at all.
  --
  -- `tilesWide` exists because a sprite sheet usually records no size -- its
  -- NCGR says 0xFFFF x 0xFFFF and the shape lives in a cell bank instead. Every
  -- one of ug_parts' 71 NCGR members states a real tilesX/tilesY, measured
  -- against the cartridge, so the file already answers the question this table
  -- normally has to. `preferDeclaredSize` says so: take the sheet's word.
  --
  -- And it is the right word. Cross-checked against `Gen4Mining.OBJECTS`, whose
  -- sizes come from a completely separate place -- `sMiningObjects`, compiled
  -- into an ARM9 overlay -- 70 of the 71 agree exactly, at two tiles per mining
  -- cell. The one that is not in the mining table is `dirt_tiles`, the seven
  -- layers of earth over the buried objects, which is not a buried object.
  {
    path = "/data/ug_parts.narc", label = "underground mining objects",
    out = "underground", preferDeclaredSize = true,
  },
  {
    path = "/data/ug_fossil.narc", label = "underground mining interface",
    out = "underground", preferDeclaredSize = true,
  },
  -- ...AND THE OTHER THREE UNDERGROUND ARCHIVES, which are a DIFFERENT SHAPE
  -- from the two above and were left out for that reason rather than by
  -- oversight.
  --
  -- `ug_parts` is 71 plain sheets and every one of them DECLARES its own
  -- tilesX/tilesY, which is why `preferDeclaredSize` is the whole story there.
  -- These three are mostly CELL ACTORS: an NCGR beside an NCER and an NANR,
  -- where the bank says how many pieces there are, how big each is and where
  -- it sits, and the sheet declares no size at all (0 of 2, 0 of 14 and 0 of 2
  -- respectively). A width would be a guess, and a wrong width is not a wrong
  -- size, it is a different picture.
  --
  -- The planner already handles that: `Gen4Archives.cellBank` finds a bank
  -- named `<base>_cell`, and all three archives are named exactly that way --
  -- `crack_end.NCGR` with `crack_end_cell.NCER`, `petal` with `petal_cell`,
  -- `map_markers` with `map_markers_cell`. Every match is `named`; not one
  -- falls back to the prefix or sole-bank guesses. So what was missing was
  -- only an entry here.
  --
  -- MEASURED, so that "it works" is a number: every sheet in the three is
  -- covered by a bank or by its own declared size, and none by a chosen width
  -- -- 16 by a cell bank, 1 (`smoke_tiles`, 32x32, the one with no bank) by
  -- its header, 0 left over. `preferDeclaredSize` is kept on all three for
  -- that one sheet and for the screens.
  {
    path = "/data/ug_anim.narc", label = "underground wall-crack animation",
    out = "underground", preferDeclaredSize = true,
  },
  {
    path = "/data/ug_trap.narc", label = "underground traps",
    out = "underground", preferDeclaredSize = true,
  },
  {
    path = "/data/underg_radar.narc", label = "underground radar screen",
    out = "underground", preferDeclaredSize = true,
  },
}

Gen4Screens.SCREEN = "screen"
Gen4Screens.SHEET = "sheet"

-- TWO NAMING CONVENTIONS LIVE IN THESE ARCHIVES, and a planner that knows only
-- one silently drops half the game's screens.
--
--   SUBJECT-NAMED.  The base name is the thing and the extension is the role:
--   "message_box_00.NCGR" with "message_box_00.NCLR", "logo.NCGR" with
--   "logo.NCLR" and "logo.NSCR".  Grouping by base name is exactly right.
--
--   ROLE-NAMED.  The NAME is the role and the archive is the thing:
--   shop_gra is "tiles.NCGR", "default.NCLR", "tilemap.NSCR",
--   "tilemap_no_item.NSCR".  Here every base name differs, so grouping by
--   base name produces four groups of one and not a single composable screen.
--
-- A third case sits between them: pl_plist_gra names its sheet
-- "subscreen_tiles.NCGR" and its tilemap "subscreen.NSCR", so the two belong
-- together but their bases differ by a suffix.
--
-- So: normalise away the role suffixes, then let a group that is missing a
-- part fall back to the archive's own sheet and palette.  Falling back is
-- recorded on the job rather than hidden, because a borrowed palette is a
-- guess and a guess that is not marked is indistinguishable from a fact.
-- `_bg_tiles` is FIRST because the list is tried in order and `_tiles` would
-- otherwise match it and leave a stray `_bg`.  Its absence was the whole
-- reason the Pokétch drew as tile soup: every app names its background
-- `<app>_bg_tiles.NCGR` beside `<app>.NSCR`, and without this suffix the two
-- never grouped, so each app's tilemap fell back to the archive's shared
-- sheet -- the device border -- and composed the border's tiles through the
-- app's map.
local ROLE_SUFFIXES = { "_bg_tiles", "_tileset", "_tiles", "_tilemap",
                        "_gra", "_graphics" }

local function normalise(base)
  for _, suffix in ipairs(ROLE_SUFFIXES) do
    if #base > #suffix and base:sub(-#suffix) == suffix then
      return base:sub(1, #base - #suffix)
    end
  end
  return base
end

-- A group is only worth drawing if it can be given pixels.  A lone animation,
-- a lone cell bank, a 3D model -- all real members, none of them a picture.
local function kindOf(group)
  if group.NSCR then return Gen4Screens.SCREEN end
  if group.NCGR then return Gen4Screens.SHEET end
  return nil
end

-- plan(path, options) -> array of jobs, or nil when the archive has no names.
--
-- Each job is { name, kind, tiles, palette, tilemap, tilesWide }, with member
-- indices already resolved.  Nothing is read from the cartridge here; this is
-- only the plan.
function Gen4Screens.plan(path, options)
  options = options or {}
  local raw = Gen4Archives.groups(path)
  if not raw then return nil, "no name table for " .. tostring(path) end

  -- Re-group on the normalised base, so subscreen_tiles.NCGR and
  -- subscreen.NSCR land together.
  local byBase, groups = {}, {}
  for _, group in ipairs(raw) do
    local base = normalise(group.base)
    local merged = byBase[base]
    if not merged then
      -- Keep the name AS WRITTEN as well as the normalised one: cell banks are
      -- found by the spelling the cartridge uses ("bag_sprite_male"), not by
      -- the shortened form this table groups on.
      merged = { base = base, raw = group.base }
      byBase[base] = merged
      groups[#groups + 1] = merged
    end
    if group.NCGR and not merged.sheetName then merged.sheetName = group.base end
    -- A BASE CAN OWN TWO SHEETS, and only one of them is the background.
    -- `stopwatch_bg_tiles.NCGR` and `stopwatch.NCGR` normalise to the same
    -- name; the first is the app's background and the second is its sprite
    -- sheet, and taking whichever came first in the archive picked the sprites
    -- about half the time.  A sheet whose own name carries a role suffix is
    -- the background, and it wins.
    if group.NCGR and group.base ~= merged.base then
      merged.bgNCGR = merged.bgNCGR or group.NCGR
    end
    if group.NCGR and group.base == merged.base then merged.spriteNCGR = group.NCGR end
    for _, role in ipairs({ "NCGR", "NCLR", "NSCR" }) do
      if group[role] and not merged[role] then merged[role] = group[role] end
    end
  end

  -- The archive's fallback sheet and palette.  Named outright where the
  -- caller knows better; otherwise the first of each, which in every archive
  -- here is the main one.
  local sharedTiles, sharedPalette, sharedFrom
  for _, group in ipairs(groups) do
    if options.shared and normalise(options.shared) == group.base then
      sharedTiles, sharedPalette, sharedFrom = group.NCGR, group.NCLR, group.base
      break
    end
  end
  -- Otherwise: prefer the sheet that a tilemap already points at, because a
  -- tilemap with no sheet of its own is far likelier to belong to a screen
  -- than to the first sprite in the archive.  In pl_bag_gra the first NCGR is
  -- the player's bag sprite and the screen sheet is the twelfth member; taking
  -- the first one puts the bag sprite's pixels behind the bag's own UI.
  if not sharedTiles then
    for _, group in ipairs(groups) do
      if group.NCGR and group.NSCR and group.NCLR then
        sharedTiles, sharedPalette, sharedFrom = group.NCGR, group.NCLR, group.base
        break
      end
    end
  end
  if not sharedTiles then
    for _, group in ipairs(groups) do
      if group.NCGR and group.NCLR then
        sharedTiles, sharedPalette, sharedFrom = group.NCGR, group.NCLR, group.base
        break
      end
    end
  end
  if not sharedTiles then
    for _, group in ipairs(groups) do
      if group.NCGR and not sharedTiles then
        sharedTiles, sharedFrom = group.NCGR, group.base
      end
      if group.NCLR and not sharedPalette then sharedPalette = group.NCLR end
    end
  end

  -- WHERE A SCREEN BORROWS ITS SHEET FROM, when the names do not pair it.
  --
  -- Normalising the role suffixes pairs most of them, and the shared sheet is
  -- a reasonable last resort -- but between those two sit the screens that
  -- name their sheet after something else entirely.  Both watches draw on
  -- `watch_bg_tiles`; the card's front and back both draw on
  -- `trainer_card_tiles`; Lucas and Dawn both draw on `player_tiles`.  No rule
  -- over the names finds those, and the shared sheet is WRONG rather than
  -- merely worse, so they are written down per archive and the rest is left to
  -- the suffixes.
  local byBaseGroup = {}
  for _, group in ipairs(groups) do byBaseGroup[group.base] = group end

  local jobs = {}
  for _, group in ipairs(groups) do
    local kind = kindOf(group)
    if kind then
      local lent = options.tilesFrom and options.tilesFrom[group.base]
      local donor = lent and byBaseGroup[lent] or nil
      local lentPal = options.palettesFrom and options.palettesFrom[group.base]
      local palDonor = lentPal and byBaseGroup[lentPal] or nil
      -- A DONOR OUTRANKS THE GROUP'S OWN SHEET, because it is written down
      -- for the cases where the group's own sheet is the wrong one: the analog
      -- watch has an `analog_watch.NCGR`, and it is the hands, not the face.
      local tiles = (donor and donor.NCGR) or group.bgNCGR or group.NCGR
                    or sharedTiles
      -- A NAMED PALETTE DONOR OUTRANKS EVERYTHING, for the same reason a
      -- named sheet donor does: it is written down precisely for the groups
      -- where the rules below pick the wrong file.
      --
      -- WHICH FILE IT CAME FROM IS CARRIED ALONGSIDE, not recomputed later.
      -- The graphics stage publishes each palette once under this name and
      -- points every screen that shares it at the same entry; recovering the
      -- name from the member index afterwards would mean running these same
      -- four rules a second time, in another file, and hoping they agree.
      local palette, paletteName
      if palDonor and palDonor.NCLR then
        palette, paletteName = palDonor.NCLR, lentPal
      elseif group.NCLR then
        palette, paletteName = group.NCLR, group.base
      elseif donor and donor.NCLR then
        palette, paletteName = donor.NCLR, lent
      else
        palette, paletteName = sharedPalette, sharedFrom
      end
      -- A tilemap with no sheet of its own takes the shared sheet AND the
      -- shared palette together.  Pairing the shared sheet with this group's
      -- own palette is the precise mistake the name table exists to stop.
      if group.NSCR and not (group.bgNCGR or group.NCGR) then
        tiles = (donor and donor.NCGR) or sharedTiles
        if palDonor and palDonor.NCLR then
          palette, paletteName = palDonor.NCLR, lentPal
        elseif group.NCLR then
          palette, paletteName = group.NCLR, group.base
        elseif donor and donor.NCLR then
          palette, paletteName = donor.NCLR, lent
        else
          palette, paletteName = sharedPalette, sharedFrom
        end
      end
      if tiles and palette then
        local job = {
          name = group.base,
          kind = kind,
          tiles = tiles,
          palette = palette,
          paletteName = paletteName,
          firstTile = options.firstTileFor and options.firstTileFor[group.base],
          paletteSlot = options.paletteSlotFor and options.paletteSlotFor[group.base],
          tilemap = group.NSCR,
          watchDigits = path=="/graphic/poketch.narc" and group.base=="digital_watch_digits" or nil,
          tilesWide = (options.tilesWideFor
                       and options.tilesWideFor[group.base])
                      or options.tilesWide or 8,
          -- WHICH OF THE THREE ANSWERED, not just what it said. A width written
          -- down for this group was measured on purpose and outranks everything;
          -- the archive default and the bare 8 are guesses wearing a number, and
          -- only those may be overruled by the sheet's own header. Without this
          -- flag the two are indistinguishable downstream -- `tilesWide = 8` on a
          -- message box is the archive default falling through, and `= 8` on a
          -- sheet somebody measured at eight is a statement.
          tilesWideStated = (options.tilesWideFor
                             and options.tilesWideFor[group.base]) ~= nil,
          preferDeclaredSize = options.preferDeclaredSize or nil,
          borrowedTiles = (group.NCGR == nil) or false,
          borrowedPalette = (group.NCLR == nil) or false,
        }
        -- A sheet with a cell bank is not a guess any more: the bank says how
        -- many pieces it has, how big each one is and where it sits.  Only a
        -- sheet with no bank anywhere in its archive still needs a width.
        if kind == Gen4Screens.SHEET then
          local at, via, how =
            Gen4Archives.cellBank(path, group.sheetName or group.raw or group.base)
          if at then
            job.cell = at
            job.cellFrom = via
            job.cellMatch = how
          end
        end
        jobs[#jobs + 1] = job
        -- Poketch apps have a BG tilemap AND an OBJ sheet under the same
        -- base name. Keep the cell-assembled sprites alongside the background.
        if path == "/graphic/poketch.narc" and kind == Gen4Screens.SCREEN
           and group.spriteNCGR and group.bgNCGR then
          local cell, via, how = Gen4Archives.cellBank(path, group.base)
          if cell then
            jobs[#jobs + 1] = { name = group.base .. "_sprite", kind = Gen4Screens.SHEET,
              tiles = group.spriteNCGR, palette = sharedPalette, paletteName = sharedFrom,
              cell = cell, cellFrom = via, cellMatch = how, tilesWide = 8 }
          end
        end
      end
    end
  end
  -- THE SAME PICTURE IN ANOTHER PALETTE, where the cartridge composes one
  -- screen several ways.  Emitted as ORDINARY JOBS -- the graphics stage needs
  -- no knowledge of them -- named `<base><suffix>`, so the trainer card's six
  -- levels arrive as `trainer_card_front_cobalt` and the rest.
  --
  -- `borrowedPalette` is set on every copy: the palette is by definition not
  -- this group's own, which is exactly what that flag records.
  if options.paletteVariants then
    local extra = {}
    for _, job in ipairs(jobs) do
      for _, v in ipairs(options.paletteVariants[job.name] or {}) do
        local src = v.palette and byBaseGroup[v.palette]
        if src and src.NCLR then
          local copy = {}
          for k, value in pairs(job) do copy[k] = value end
          copy.name = job.name .. tostring(v.suffix)
          copy.palette = src.NCLR
          copy.paletteName = v.palette
          copy.borrowedPalette = true
          extra[#extra + 1] = copy
        end
      end
    end
    for _, job in ipairs(extra) do jobs[#jobs + 1] = job end
  end

  return jobs, sharedFrom
end

-- planAll() -> { { archive = <entry>, jobs = {...} }, ... }
function Gen4Screens.planAll()
  local out = {}
  for _, entry in ipairs(Gen4Screens.ARCHIVES) do
    local jobs = Gen4Screens.plan(entry.path, entry)
    if jobs and #jobs > 0 then
      out[#out + 1] = { archive = entry, jobs = jobs }
    end
  end
  return out
end

return Gen4Screens
