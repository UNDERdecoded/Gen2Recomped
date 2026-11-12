-- The Minish Cap (USA): where the cartridge keeps things.
--
-- Every number here is an ADDRESS or a STRUCTURE SIZE in the USA cartridge
-- (game code BZME, revision 0, SHA-1 below), taken from the zeldaret/tmc
-- decompilation's symbol annotations and checked against the ROM itself (see
-- docs/zelda/minishcap.md, "ROM survey").  No cartridge DATA lives here: the
-- importer follows these roots through the player's own ROM.
--
-- Pointers in the cartridge are GBA bus addresses ($08xxxxxx).  `off(p)`
-- turns one into a file offset.

local Layout = {}

Layout.GAME_TITLE = "GBAZELDA MC"
Layout.GAME_CODE = "BZME"
Layout.MAKER = "01"
Layout.SHA1 = "b4bd50e4131b027c334547b4524e2dbbd4227130"
Layout.SIZE = 16 * 1024 * 1024

Layout.ROM_BASE = 0x08000000

-- the room / map system (include/area.h, include/map.h)
Layout.gAreaRoomHeaders = 0x0811E214  -- RoomHeader*[area], 10-byte headers, $FFFF ends
Layout.gAreaTileSets    = 0x0810246C  -- MapDataDefinition**[area][tileSet_id]
Layout.gAreaRoomMaps    = 0x08107988  -- MapDataDefinition**[area][room]
Layout.gAreaTiles       = 0x0810309C  -- MapDataDefinition*[area] (metatiles + types)
Layout.gAreaTable       = 0x080D50FC  -- void**[area][room] (entity lists, room code)
Layout.gExitLists       = 0x0813A7F0  -- Transition**[area][room], 20-byte records
Layout.gAreaMetadata    = 0x08127D30  -- AreaHeader[area]: flags, location, bank, bgm
Layout.gMapData         = 0x08324AE4  -- base every MapDataDefinition.src is relative to
Layout.AREA_COUNT = 0x90
Layout.EXIT_AREA_COUNT = 0x99
Layout.MAX_ROOMS = 64

-- palettes (src/common.c LoadPaletteGroup)
Layout.gPaletteGroups = 0x080FF850       -- PaletteGroup*[208]
Layout.PALETTE_GROUP_COUNT = 208
Layout.gGlobalGfxAndPalettes = 0x085A2E80 -- palette N is at + N * 32

-- the collision lookups the veneer reads (asm/src/veneer.s literal pool)
Layout.PTR_SPECIAL_COLLISION = 0x08000214 -- -> gMapSpecialTileToCollisionData
Layout.PTR_ACT_TILE          = 0x08000218 -- -> gMapTileTypeToActTile
Layout.PTR_TYPE_COLLISION    = 0x0800021C -- -> gMapTileTypeToCollisionData
-- src/movement.c IsTileCollision: the per-pixel masks of the eight partial
-- tile shapes (TileCollisionFunction2..9, 16 rows of u16 each) and the
-- collisionType x (value - 0x10) -> shape lookup (13 types x 0x60 values)
Layout.COLLISION_MASKS = 0x08133918
Layout.COLLISION_SHAPE_LOOKUP = 0x08133A67
Layout.COLLISION_SHAPE_TYPES = 13
-- round 9: Link's own tile test (asm/src/player.s sub_080085CC /
-- sub_080086D8): gUnk_0800823C = 40 pointers to 16-row u16 masks (bit
-- 15 - (x & 15) of row y & 15), then seven 0x60-byte value -> mask tables
-- picked by Link's state: $082DC normal, $0833C Minish, $0839C Minish
-- swimming, $083FC swimming, $0845C jumping / parachute, $084BC gust jar or
-- carrying, $0851C beetles attached
Layout.PLAYER_COLL_MASK_PTRS = 0x0800823C
Layout.PLAYER_COLL_MASKS = 40
Layout.PLAYER_COLL_SHAPES = 0x080082DC
Layout.PLAYER_COLL_TABLES = 7
Layout.TILE_TYPE_COUNT = 0x800
Layout.SPECIAL_TILE_COUNT = 0x80

-- VRAM: area tilesets decompress into BG character memory $06000000..$0600C000
Layout.VRAM_BG = 0x06000000
Layout.VRAM_BG_SIZE = 0xC000
-- where MapDataDefinition.dest points inside the two MapLayer structs; only
-- the OFFSET within the struct matters (gMapBottom / gMapTop are in EWRAM)
Layout.LAYER_MAPDATA   = 0x0004
Layout.LAYER_COLLISION = 0x2004
Layout.LAYER_TILETYPES = 0x5004
Layout.LAYER_SUBTILES  = 0x7004
Layout.LAYER_SIZE      = 0xB004 + 0x1000

-- sprites (include/structures.h SpritePtr; src/affine.c)
Layout.gSpritePtrs    = 0x080029B4        -- {animations, frames, gfx, pad}[n]
Layout.SPRITE_COUNT   = 0x149         -- gSpritePtrs (322) + gMoreSpritePtrs (7), contiguous
Layout.gFrameObjLists = 0x082F3D74

-- NPCs and object graphics (src/npcUtils.c NPCInit, src/vram.c, src/color.c)
Layout.gNPCDefinitions = 0x08114AE4       -- NPCDefinition[0x80], 8 bytes each
Layout.NPC_COUNT = 0x80
Layout.gFixedTypeGfxData = 0x08132B30     -- u32[527]: offset | compressed bit 0 | slots << 24
Layout.FIXED_GFX_COUNT = 527
Layout.gObjPalettes = 0x08133368          -- u32[]: offset | count << 24 (obj palette 0x16+)
Layout.OBJ_PALETTE_COUNT = 0x16E

-- Kinstones (include/kinstone.h, src/common.c, src/gameData.c)
Layout.gKinstoneWorldEvents = 0x080C9CBC  -- KinstoneWorldEvent[0x76], 8 bytes
Layout.KINSTONE_EVENT_COUNT = 0x76         -- fusions 1..100 and piece types $65..$75
Layout.SharedFusions = 0x080CA11C          -- u8[18]: the random "shared" fusions
Layout.SHARED_FUSION_COUNT = 18
Layout.gWorldEvents = 0x080FE320           -- WorldEvent[], 20 bytes
Layout.WORLD_EVENT_COUNT = 0x70

-- tileset managers: rooms that swap BG graphics by camera region
-- (src/manager/hyruleTownTileSetManager.c, minishVillageTileSetManager.c).
-- slots = region lists ({group, x, y, w, h}..., $FF), infos = per group
-- {gfx offset into gGlobalGfxAndPalettes, VRAM dest} records, `per` of them.
Layout.TILE_SWAPS = {
  { area = 0x02, room = 0, slots = { 0x08108398, 0x081083AE, 0x081083C4 },
    infos = 0x08108408, groups = 6, per = 2 },
  { area = 0x15, room = 0, slots = { 0x081083DA, 0x081083F0, 0x081083F2 },
    infos = 0x08108468, groups = 6, per = 2 },
  { area = 0x01, room = 0, slots = { 0x08108050 },
    infos = 0x081080A4, groups = 5, per = 8, palettes = 0x081081E4 },
}
Layout.SWAP_BLOCK = 0x1000 -- BG_SCREEN_SIZE * 2

-- UI (src/text.c, src/ui.c, src/common.c LoadGfxGroup)
Layout.FONT_GLYPHS = 0x08692F60           -- gUnk_08109248[0]: 8x16 glyphs, 64 bytes (nibble rows)
Layout.FONT_GLYPH_COUNT = 0x100
Layout.gGfxGroups = 0x08100AA8            -- GfxItem* per group: {offset|ctrl<<24|more<<31, dest, size|compressed<<31}
Layout.RUPEE_DIGITS = 0x085C48A0          -- normal digits (RupeeKeyDigits - 0x280); yellow (RupeeKeyDigits) at +0x280
Layout.gUnk_080C8F2C = 0x080C8F2C          -- heart tile entries (DrawHearts)
Layout.gItemMetaData = 0x080FD5B4          -- ItemMetaData[0x80], 8 bytes
Layout.ITEM_COUNT = 0x80

-- objects / enemies / drops
Layout.gObjectDefinitions = 0x08126798    -- ObjectDefinition[], 8 bytes (as NPCs)
Layout.OBJECT_COUNT = 0xC0
Layout.gEnemyDefinitions = 0x080D2C58     -- EnemyDefinition[], 16 bytes; gfx $FFFF = multi-form
Layout.ENEMY_COUNT = 0x6F
Layout.gEnemyDroptables = 0x0800137C      -- Droptable (16 s16)[18]
Layout.gAreaDroptables = 0x080015BC       -- [19]
Layout.DeathFx_EnemyDroptables = 0x0811EC64 -- u8 per enemy id
Layout.gUnk_080FE1B4 = 0x080FE1B4          -- droptable slot -> item id (16)
Layout.gUnk_080FE1C6 = 0x080FE1C6          -- location -> area droptable (23)
-- round 9: the rest of CreateRandomItemDrop's tables (src/droptables.c,
-- USA layout checked against the ROM) and the drop sources' own tables
Layout.gObjectDroptables = 0x0800181C       -- [8]: CreateRandomItemDrop 16..23
Layout.gUnk_0800191C = 0x0800191C           -- [2]: 24 / 25 (by needHealthDrop)
Layout.gDroptableModifiers = 0x08001A1C     -- [3]: none / no shells / no kinstones
Layout.gUnk_0811F960 = 0x0811F960           -- SpecialFx {flags, droptable, sfx u16} x $58
Layout.gUnk_0811FAC8 = 0x0811FAC8           -- FX_BUSH variants (4), then FX_GRASS_CUT's (4)
Layout.gUnk_0811E84C = 0x0811E84C           -- ItemOnGround {?, ?, bounce sfx u16, gustJarFlags, ...} x 118

-- tile interactions (asm/src/player.s DoTileInteraction) and the sword
Layout.gUnk_080046A4 = 0x080046A4          -- {u16 tileType, u16 index} until key 0
Layout.gUnk_080047F6 = 0x080047F6          -- {u16 actMask, u8 objId, u8 objType, u16 ?, u16 newTile} per index
Layout.gUnk_08129072 = 0x08129072          -- sword tile probe {s8 x, s8 y} per frame flag 1..
Layout.gUnk_08129096 = 0x08129096          -- sword hitbox {s8 x, s8 y, u8 w, u8 h} per frameIndex - $6A

-- combat (asm/src/intr.s, src/collision.c, src/enemyUtils.c)
Layout.gCollisionMtx = 0x080B7B74          -- ColSettings (12 bytes)[173 * 34], [hitType * 34 + hurtType]
Layout.COLLISION_MTX_SIZE = 173 * 34 * 12
Layout.gUnk_080D3D94 = 0x080D3D94          -- enemy home range {x, y} per enemy id

-- projectiles (src/projectile.c): ProjectileDefinition, 16 bytes, gfx $FFFF = multi-form
Layout.gProjectileDefinitions = 0x0813210C
Layout.PROJECTILE_COUNT = 0x30
-- sprites past gSpritePtrs' end ("sprite index too high" in the decomp):
-- no animations, but gFrameObjLists still has their OAM frames
Layout.OAM_SPRITE_LAST = 0x1FF

-- BG tile animations (src/backgroundAnimations.c): gUnk_080B755C[area] is a
-- u16 list of animation indices ($FFFF ends), gUnk_080B7278[index] a list
-- of BgAnimationFrame {gfx*, u32 timer}; a NULL gfx ends it and loops back
-- `timer` frames.  BgAnimationGfx: {u16 vramOffset, u8 tiles, u8 flags,
-- u32 gfxOffset}; flags bit 7 = more follow, bit 4 = palettes.
Layout.gUnk_080B755C = 0x080B755C
Layout.gUnk_080B7278 = 0x080B7278

-- menus and screens (Ppu.lua)
Layout.LANGUAGE = 1                       -- gSaveHeader->language for the USA cartridge (English)
Layout.GFX_GROUP_COUNT = 139              -- gGfxGroups entries
-- EWRAM tile-map buffers (linker.ld) the gfx groups and menus write
Layout.gUnk_080CA06C = 0x080CA06C        -- kinstone piece gfx offsets (kinstoneMenu.c sub_080A4418)
Layout.gBG0Buffer = 0x02034CB0
Layout.gBG1Buffer = 0x02021F30
Layout.gBG2Buffer = 0x020344B0
Layout.gBG3Buffer = 0x02001A40
-- the menu code's data tables: name -> {address, size}
Layout.MENU_DATA = {
  gUnk_08128AD8 = { 0x08128AD8, 11 * 8 },  -- pause screen {pal group, gfx group, dispcnt, bg1, bg2}
  -- text.c: nibble -> colour tables (12 rows of 16 per fill colour), fill
  -- patterns, border glyphs (gUnk_081092AC targets, $E0 apart)
  textColors = { 0x0810942E, 0xC0 * 16 },
  textFill = { 0x0810926C, 64 },
  textBorders = { 0x086926A0, 0x8C0 },
  pauseFonts = { 0x08128FA8, 0x78 },      -- the pause screens' Font descriptors (subtask.c)
  fontBanks = { 0x08692F60, 0x086AEEE0 - 0x08692F60 }, -- gUnk_08109248 banks 0-8
  uiDefs = { 0x080C8F8C, 11 * 16 },        -- gUIElementDefinitions (ui.c)
  -- pauseMenu.c / figurineMenuData.c tables, gUnk_08128A38 (screens) up to
  -- the map and figurine tables: screens, item / quest layouts, KeyButtonLayouts
  pauseData = { 0x08128A38, 0x08128F38 - 0x08128A38 },
  ammoDigits = { 0x085C4620, 20 * 0x20 },  -- gUnk_085C4620: tens then ones digit tiles
  -- round 5 (one anchor per screen family; add entries under your own)
  -- [r5 maps]
  overworldLocs = { 0x08127F94, 0x100 },     -- gOverworldLocations {minX, minY, maxX, maxY, windcrestId, pad, textIndex}
  dungeonFloors = { 0x080C9C6C, 0x40 },      -- gDungeonFloorMetadatas {numFloors, highestFloor, unk_2, pad}
  pauseData2 = { 0x08128F38, 0x0812901C - 0x08128F38 }, -- map hint table, map fonts, gDungeonNames
  -- [r5 title]
  titleAlpha = { 0x08107C30, 16 },           -- title.c sLightRaysAlphaBlends
  titleObjs = { 0x08125014, 5 * 8 },         -- titleScreenObject.c gUnk_08125014
  fileSparkle = { 0x080FC8DE, 30 },          -- fileselect.c gUnk_080FC8DE
  -- [r5 kinstone]
  kinstoneMenu = { 0x081280DC, 0x60 },       -- kinstoneMenu.c gUnk_081280DC .. gUnk_08128120
  -- GetFuserId's lists (code_08001A7C.s: enemy list at +6, NPC list at
  -- 0x08002348; 6-byte {id, type, type2, fuserId, name text}) and the
  -- NPCData pointers gUnk_08001A7C (InitializeNPCFusion's three texts)
  fusers = { 0x08001A7C, 0x08002632 - 0x08001A7C },
  -- [r5 sword-save]
  -- CreateDialogBox (fileselect.c): Font gUnk_080FC844 + gUnk_080FC85C
  -- {palette, text, sfx} x 12
  dialogBox = { 0x080FC844, 0x18 + 12 * 6 },
  -- [r5 fx]
  -- [r5 misc]
  madderHitbox = { 0x080FD298, 8 },          -- madderpillar.c gUnk_080FD298 (the open tail)
  madderTables = { 0x080CCDA0, 0x3C },       -- madderpillar.c gUnk_080CCDA0 / gUnk_080CCDC8 / gUnk_080CCDD4
  fileObjTables = { 0x08121CD4, 0x150 },     -- fileScreenObjects.c gUnk_08121CD4 .. gUnk_08121D54[26]
  keyboardTables = { 0x080FC970, 0x40 },     -- fileselect.c gUnk_080FC970 / gUnk_080FC980 / gUnk_080FC9A0
  -- [r6]
  barrelTables = { 0x08108228, 0xE0 },       -- rollingBarrelManager.c gUnk_08108228..gUnk_081082B8 (4 x 6 exit boxes), gUnk_081082E8 (exits), gUnk_08108300 (start)
  lilyKick = { 0x08120620, 12 },             -- lilypadLarge.c gUnk_08120620 (the jar's kick per charge)
  -- [r7] multi-part NPCs (NpcParts.lua): the NPC code's const tables
  -- (SpriteLoadData lists, head frame tables; data/const/npc and the npc/*.c
  -- consts, gUnk_0810A348 .. gUnk_081146D0) and gExtraFrameOffsets
  npcData = { 0x0810A300, 0x08114800 - 0x0810A300 },
  extraFrameOffsets = { 0x089FB770, 0xF60 },
  fuseBubble = { 0x085CA6A0, 0x960 },        -- gGlobalGfxAndPalettes + $027820: the fusion bubble and its icons (cameraTarget.c)
  fuseBubbleIcons = { 0x0811F744, 16 },      -- cameraTarget.c gUnk_0811F744 (icon offsets)
  minecartData = { 0x080FCAF8, 32 },         -- gameUtils.c sMinecartData (sub_080530B0)
  furnitureCfg = { 0x08121EF8, 0x08122218 - 0x08121EF8 }, -- furniture.c gUnk_08121EF8 + the nine sCfgTable tables
  -- round 8
  scrubTables = { 0x080CC954, 0xC0 },        -- businessScrub.c gUnk_080CC954 (sales), kinstoneTypes, gUnk_080CCA04 (animations)
}

-- round 5: extra importer modules (each returns { extract = function(rom,
-- store, manifest) }), run at the end of the menus step (Extract.lua)
Layout.R5_EXTRACT = {
  -- [r5x maps]
  "src.zelda.tmc.ExtractMaps",
  -- [r5x title]
  -- [r5x kinstone]
  -- [r5x sword-save]
  -- [r5x fx]
  "src.zelda.tmc.ExtractFx",
  -- [r5x boss]
  -- [r5x crenel]
  -- [r5x misc]
  "src.zelda.tmc.PlayerMacro",
}

-- text (src/text.c): the USA build has one translation table
Layout.TEXT_TABLE = 0x089B1D90

-- entity lists: data/map/entity_headers.s (every Entities_*, Enemies_*,
-- gUnk_* list room code and scripts load by address) sits in this span
Layout.ENTITY_LO = 0x080D4000
Layout.ENTITY_HI = 0x08100000

-- scripts: data/scripts.o sits between asm/src/player.o and asm/src/script.o
Layout.SCRIPT_LO = 0x08008000
Layout.SCRIPT_HI = 0x08016984

-- sound (src/sound.c gSongTable, 8-byte {header*, ms, me})
Layout.gSongTable = 0x08A11DBC
Layout.SONG_MAX = 0x224          -- 548 entries (src/sound.c)

function Layout.off(ptr)
  return ptr - Layout.ROM_BASE
end

function Layout.isRomPtr(p, size)
  return type(p) == "number" and p >= Layout.ROM_BASE
     and p < Layout.ROM_BASE + (size or Layout.SIZE)
end

-- header = the first 0x200 bytes (or the whole ROM) as a string
function Layout.detect(header)
  if type(header) ~= "string" or #header < 0xB2 then return false end
  return header:sub(0xA1, 0xAB) == Layout.GAME_TITLE
     and header:sub(0xAD, 0xB0) == Layout.GAME_CODE
end

return Layout
