-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Round 35: where the cartridge keeps the small tables of RomTables.lua
-- (GBA ROM offsets, counts and kinds only; the values are read at import).
-- S(name, addr, count, kind, base, opts) -- see RomTables.lua.

return function(S)
  -- Guard.lua: kSoldierB_* (wall-following guards), kSoldier_HeadDirs
  S("guard.bXv", 0x176960, 8, "s8", 0, { lo = -1, hi = 1 })
  S("guard.bYv", 0x176968, 8, "s8", 0, { lo = -1, hi = 1 })
  S("guard.bXv2", 0x176970, 8, "s8", 0, { lo = -8, hi = 8 })
  S("guard.bYv2", 0x176978, 8, "s8", 0, { lo = -8, hi = 8 })
  S("guard.bDir", 0x176980, 8, "u8", 0, { lo = 0, hi = 3 })
  S("guard.bMask2", 0x176988, 8, "u8", 0, { lo = 1, hi = 8 })
  S("guard.bMask", 0x176990, 8, "u8", 0, { lo = 1, hi = 8 })
  S("guard.bNext2", 0x176998, 8, "u8", 0, { lo = 0, hi = 7 })
  S("guard.bNext", 0x1769A0, 8, "u8", 0, { lo = 0, hi = 7 })
  S("guard.bTab0", 0x1769A8, 8, "u8", 0, { lo = 0, hi = 7 })
  S("guard.headDirs", 0x176938, 32, "u8", 0, { lo = 0, hi = 3 })
  -- Tools.lua: kRodAnimDelays (after kHammerAnimDelays), kFireRod_X/Y, the ice
  -- rod's, kBoomerang_Tab6/7/X0/Y0, the hookshot's collision / move offsets
  S("tools.rodDelays", 0x16909B, 3, "u8", 1, { lo = 1, hi = 16 })
  S("tools.fireX", 0x171D4A, 4, "s16", 1, { lo = -32, hi = 32 })
  S("tools.fireY", 0x171D52, 4, "s16", 1, { lo = -32, hi = 32 })
  S("tools.iceX", 0x16E17C, 4, "s16", 1, { lo = -32, hi = 32 })
  S("tools.iceY", 0x16E174, 4, "s16", 1, { lo = -32, hi = 32 })
  S("tools.boomTab6", 0x16E0D0, 8, "s16", 1, { lo = -16, hi = 16 })
  S("tools.boomTab7", 0x16E0E0, 8, "s16", 1, { lo = -16, hi = 16 })
  S("tools.boomX0", 0x16E100, 8, "s16", 1, { lo = -16, hi = 16 })
  S("tools.boomY0", 0x16E0F0, 8, "s16", 1, { lo = -16, hi = 16 })
  S("tools.hookCollX", 0x1682C6, 8, "s16", 1, { lo = 0, hi = 15 })
  S("tools.hookCollY", 0x1682B6, 8, "s16", 1, { lo = 0, hi = 15 })
  S("tools.hookMoveX", 0x17F934, 4, "s16", 1, { lo = -16, hi = 16 })
  S("tools.hookMoveY", 0x17F92C, 4, "s16", 1, { lo = -16, hi = 16 })
  -- Doors.lua: kLink_Move_Helper6_tab0..3 (HandleNudging), kStaircaseTab2
  S("doors.nudgeY0", 0x168276, 8, "s16", 1, { lo = 0, hi = 31 })
  S("doors.nudgeX0", 0x168286, 8, "s16", 1, { lo = 0, hi = 15 })
  S("doors.nudgeY1", 0x168296, 8, "s16", 1, { lo = 0, hi = 31 })
  S("doors.nudgeX1", 0x1682A6, 8, "s16", 1, { lo = 0, hi = 15 })
  S("doors.stairTab2", 0x14CB40, 20, "s8", 1, { lo = -96, hi = 96 })
  -- Carry.lua: the lift query offsets (x 0x1532CC, y 0x1532C4, by facing
  -- 0/2/4/6), the gloves needed by liftable, kLiftTab2[0..2]
  S("carry.query", { 0x1532CC, 0x1532C4 }, 4, "s16", 0, { keys = { 0, 2, 4, 6 }, lo = -8, hi = 32 })
  S("carry.gloves", 0x168268, 7, "u8", 0, { lo = 0, hi = 2 })
  S("carry.liftTimes", 0x168C2C, 3, "u8", 1, { lo = 1, hi = 16 })
  -- Dash.lua: kPlayerActionBoxRun_XLo / YLo (rows {x, y} by facing >> 1)
  S("dash.runBox", { 0x171E92, 0x171E9A }, 4, "s8", 0, { lo = -16, hi = 16 })
  -- Drops.lua: kLink_Lift_tab (9 attributes; 0xFF unused), as attribute -> kind
  S("drops.liftKind", 0x168C40, 9, "u8", 0, { invert = true, skip = 0xFF,
    check = function(v) for _, a in ipairs(v) do if a ~= 0xFF and (a < 0x50 or a > 0x57) then return false end end return true end })
  -- DesertPalace.lua: kMovingWall_Tab1
  S("dpal.wallTab1", 0x167914, 8, "s16", 1, { lo = -300, hi = 0 })
  -- Dungeons26.lua: kFallHolePitDirs, kFallHoleDirs2
  S("d26.fallPit", 0x167FBA, 4, "u8", 0, { lo = 0, hi = 15 })
  S("d26.fallDirs2", 0x167FAA, 8, "u8", 0, { lo = 0, hi = 15 })
  -- Escape.lua: kOverworld_DrawBadWeather_X / Y (the GBA's words are << 8)
  S("escape.rainX", 0x14D794, 4, "u16", 0, { scale = 1 / 256, check = function(v) for _, x in ipairs(v) do if x % 256 ~= 0 then return false end end return true end })
  S("escape.rainY", 0x14D79C, 4, "u16", 0, { scale = 1 / 256, check = function(v) for _, x in ipairs(v) do if x % 256 ~= 0 then return false end end return true end })
  -- Games31.lua: the super bomb's explosion offsets (Y then X), the bounce z speeds
  S("games31.explodeX", 0x17F82E, 9, "s16", 0, { lo = -32, hi = 32 })
  S("games31.explodeY", 0x17F81C, 9, "s16", 0, { lo = -32, hi = 32 })
  S("games31.bounceZv", 0x180388, 4, "u8", 0, { lo = 0, hi = 0x40 })
  -- Gear.lua: kBottleList, kPotionList (item ids)
  S("gear.bottleList", 0x16E518, 7, "u8", 1, { lo = 1, hi = 0x7F })
  S("gear.potionList", 0x16E51F, 5, "u8", 1, { lo = 1, hi = 0xFF })
  -- Mech27.lua: kTurnOffWater_Tab0 (first period), kTurnOnWater_Tab2 / 1 / 0 (s16 on the GBA)
  S("mech.turnOff", 0x1535D4, 4, "s16", 0, { lo = -2, hi = 2 })
  S("mech.turnOn2", 0x1535F4, 4, "s16", 0, { lo = -2, hi = 2 })
  S("mech.turnOn1", 0x1535FC, 4, "s16", 0, { lo = -2, hi = 2 })
  S("mech.turnOn0", 0x153604, 4, "s16", 0, { lo = -2, hi = 2 })
  -- Items27.lua: kCaneSpark_Magic (after kCaneSpark_Transmute_Tab), the
  -- Somaria platform's velocities / poof / junction masks, Witch_Draw's rows
  S("items27.sparkMagic", 0x17F9EC, 3, "u8", 1, { lo = 1, hi = 8 })
  S("items27.platXv", 0x17D484, 8, "s8", 1, { lo = -16, hi = 16 })
  S("items27.platYv", 0x17D48B, 8, "s8", 1, { lo = -16, hi = 16 })
  S("items27.platPoof", 0x17FC2E, 4, "u8", 1, { lo = 0, hi = 3 })
  S("items27.junction", 0x17D4B8, 7, "u8", 0, { w = 4, lo = 1, hi = 15 })
  S("items27.witchA", 0x174AAC, 16, "s16", 1, { w = 4, lo = -16, hi = 0xFF })
  S("items27.witchB", 0x174B2C, 3, "s16", 1, { w = 4, lo = -16, hi = 0xFF })
  S("items27.witchC", 0x174B44, 2, "s16", 1, { w = 4, lo = -16, hi = 0xFF })
  -- Sprites.lua: the rupee shimmer (kLinkDmaCtrs0 delays, kLinkDmaSources9 /
  -- 0x20 frames), kOffsToShadowGivenDir Y / X
  S("spr.shimmerDelay", 0x22AB12, 6, "u16", 1, { lo = 1, hi = 64 })
  S("spr.shimmerFrame", 0x22AB1E, 6, "u16", 1, { scale = 1 / 0x20, check = function(v) for _, x in ipairs(v) do if x % 0x20 ~= 0 or x > 0x40 then return false end end return true end })
  S("spr.linkShadowY", 0x16AAF0, 4, "u8", 0, { lo = 0, hi = 32 })
  S("spr.linkShadowX", 0x16AAFC, 4, "s8", 0, { lo = -8, hi = 8 })
  -- Shop.lua: the shop subtype by room-low list, the three wares' x offsets
  S("shop.where", 0x17D020, 13, "u8", 1, {})
  S("shop.itemX", 0x17D02E, 3, "s16", 1, { lo = -64, hi = 64 })
  -- Items27.lua: the Somaria block's switch-cover probes (after kSomarianBlock_Coll_X)
  S("items27.coverY", 0x17FA9C, 4, "s16", 1, { lo = -8, hi = 8 })
  S("items27.coverX", 0x17FAA4, 4, "s16", 1, { lo = -8, hi = 8 })
  -- Townsfolk30.lua: Thief_Draw's head by direction (the guards' head chars / flags)
  S("folk.headChar", 0x176EB0, 4, "u8", 0, { lo = 0, hi = 0x3F })
  S("folk.headFlags", 0x176EB4, 4, "u8", 0, {})
  -- Agahnim.lua: kChattyAgahnim_LevitateGfx
  S("agahnim.levitate", 0x175A18, 4, "u8", 0, { lo = 0, hi = 7 })

  -- ---------------------------------------------------------- round 36
  -- Items27.lua: kByrnaDelays (LinkItem_CaneOfByrna 0x080A3040 / 0x080A309C;
  -- the GBA keeps 3 bytes, index 3 reads the next table's first)
  S("items27.byrnaDelays", 0x1690EF, 4, "u8", 1, { lo = 1, hi = 64 })
  -- Tools.lua: kShovelAnimDelay / kShovelAnimDelay2 (LinkItem_Shovel 0x080A27D2)
  S("tools.shovelDelay", 0x1690D6, 6, "u8", 1, { lo = 1, hi = 64 })
  S("tools.shovelStep", 0x1690DC, 6, "u8", 1, { lo = 0, hi = 2 })
  -- Weapon.lua: kSwordTypeToGfxOffs / kShieldTypeToGfxOffs, the GBA's in
  -- halfwords of the decompressed sheet (0x0812F25E / 0x0812FC86): a tile is
  -- 16; the shield's tiles sit 64 tiles into the port's sheet 0x5E
  S("weapon.swordTile", 0x22BA48, 5, "u16", 0, { scale = 1 / 16, check = function(v) for _, x in ipairs(v) do if x % 16 ~= 0 or x > 0x400 then return false end end return true end })
  S("weapon.shieldTile", 0x22BA52, 4, "u16", 0, { scale = 1 / 16, add = 64, check = function(v) for _, x in ipairs(v) do if x % 16 ~= 0 or x > 0x400 then return false end end return true end })
  -- Items27.lua: the Somaria platform's DrawMultipleData (0x081110CE):
  -- rows {x, y, char | flags << 8, size}
  S("items27.platDmd", 0x17D510, 16, "s16", 1, { w = 4, lo = -32768, hi = 32767 })
  -- BigRock.lua: kGetBestActionToPerformOnTile_b (attribute & 15 -> the
  -- index into _a = carry.gloves)
  S("carry.actionB", 0x16826F, 7, "u8", 0, { lo = 0, hi = 6 })
  -- Sprites31.lua: the cauldron's prices (the GBA's ware rows of 8 bytes,
  -- u16 price at +6; read at 0x0810F77C)
  S("spr31.cauldronRows", 0x17D378, 5, "u16", 0, { w = 4 })

  -- code immediates (kind "imm": the instruction's own number)
  -- Hera.lua: GiantMoldorm_Draw's segment look-backs 16 / 28 / 0x28 / 0x30
  -- (the GBA inlines `subtype2 - n`: 0x080D98B4 / D8DC / D916 / D962)
  S("hera.tailBack", { 0x080D98B4, 0x080D98DC, 0x080D9916, 0x080D9962 }, 4, "imm", 1, { op = { subs = true }, lo = 1, hi = 0x7F })
  -- Shop.lua: the wares' prices (ShopItem_HandleCost: `bl 0x080AA868`
  -- (rupees) then `subs r0, #price`; the fire shield's is its wrapper's
  -- argument 0x0810F3AA); keys = the ware numbers
  S("shop.price", { 0x0810E81A, 0x0810E8E0, 0x0810F3AA, 0x0810EBB2, 0x0810EC90, 0x0810ED68 }, 6, "imm", 0,
    { keys = { 7, 8, 9, 10, 11, 12 }, lo = 1, hi = 999 })

  -- message numbers (kind "msg": the r1 of a call of the message routine)
  S("msg.flute", { 0x080D28E2, 0x080D28BC, 0x080D2886, 0x080D2966, 0x080D2942, 0x080DBF4E }, 6, "msg", 0,
    { keys = { "kidDone", "kidShovel", "kidAsk", "kidYes", "kidNo", "dad" }, lo = 1, hi = 0x1C7 })
  S("msg.ending", { 0x080FDB64, 0x080FDBA8 }, 2, "msg", 0, { keys = { "understand", "way" }, lo = 1, hi = 0x1C7 })
  S("msg.story", { 0x080F3834, 0x080F3870, 0x080F340E }, 3, "msg", 0,
    { keys = { "telepathy", "uncleLeaves", "priest" }, lo = 1, hi = 0x1C7 })
  S("msg.items27", { 0x080D031E, 0x080CFA76, 0x080CFEDA, 0x080D1A92, 0x080D17CE, 0x080D1786, 0x080DCA20, 0x080DCB94 }, 8, "msg", 0,
    { keys = { "bee", "fairy", "noBottle", "witchNone", "witchTook", "witchGive", "bat1", "bat2" }, lo = 1, hi = 0x1C7 })
  S("msg.npc", { 0x080DE51E, 0x080DE644, 0x080F0FBC, 0x080F101A }, 4, "msg", 0,
    { keys = { "sashaIceRod", "sashaMap", "legend", "legendEnd" }, lo = 1, hi = 0x1C7 })
  S("msg.shop", { 0x0810F0CA, 0x0810E808, 0x0810EC76, 0x0810E8EC }, 4, "msg", 0,
    { keys = { "have", "bottle", "full", "poor" }, lo = 1, hi = 0x1C7 })
  S("msg.games31", { 0x080DEBD6 }, 1, "msg", 0, { keys = { "bombShop" }, lo = 1, hi = 0x1C7 })
  S("msg.spr31", { 0x080DF8DA, 0x080E0414, 0x080DFB20, 0x080DFB90, 0x0810F7BC }, 5, "msg", 0,
    { keys = { "pond", "pondUnder", "pondUpgrade", "pondBack", "cauldronNoBottle" }, lo = 1, hi = 0x1C7 })

  -- Round 37: the other message entry points (RomTables.MSG_CALLS) and the
  -- message tables the code indexes. MSG(name, { {key, site}, .. }): the
  -- call sites, in the routine of the sprite / module named (sites found by
  -- tracing each routine; a site of the wrong form fails the import).
  local function MSG(name, list)
    local addr, keys = {}, {}
    for i, e in ipairs(list) do keys[i], addr[i] = e[1], e[2] end
    S(name, addr, #addr, "msg", 0, { keys = keys, lo = 1, hi = 0x1C7 })
  end
  -- FatFairy.lua: the pond of the fairy who swaps items (sprite 0x72's
  -- second half; r36 had taken four calls of the wrong states)
  MSG("msg.fairy", { { "intro", 0x080DFD82 }, { "dont", 0x080DFDEC }, { "select", 0x080DFE1E },
    { "drop", 0x080E0000 }, { "honest", 0x080E012A }, { "sure", 0x080E0686 }, { "lies", 0x080E06E8 },
    { "back", 0x080E013A }, { "silver", 0x080E00C2 } })
  -- Ganon.lua: Ganon's opening (his fight's state 0) and the dark phase
  MSG("msg.ganon", { { "hello", 0x0810A664 }, { "dark", 0x08109134 } })
  -- Agahnim.lua: the altar (Zelda's sacrifice), his tower, Ganon's Tower
  MSG("msg.agahnim", { { "altar1", 0x080DA5A4 }, { "altar2", 0x080DA5E2 }, { "tower", 0x080DB584 },
    { "gt", 0x080DAAC4 } })
  -- player / story: the big key door (0x080AF4FC), no magic (the item
  -- code), the Triforce room (Module19), the blind maiden, the Thieves'
  -- Town light, the uncle in the passage, the old man (lost)
  MSG("msg.story37", { { "bigKey", 0x08086D72 }, { "noMagic", 0x080A37A6 }, { "triforce", 0x0806B706 },
    { "blindMaiden", 0x080FF7F2 }, { "bright", 0x081006FE }, { "uncle", 0x080F394E },
    { "oldManLost", 0x080DCE3C } })
  -- Games31.lua / Townsfolk30 0x65: the archery game's keeper (0x080E1058)
  MSG("msg.archery", { { "hello", 0x080E0B64 }, { "start", 0x080E0BE6 }, { "no", 0x080E0BB6 },
    { "again", 0x080E0AB8 } })
  -- Npc.lua: Sahasrahla (no pendant), his wife, 0x2A, 0x3C (map / after),
  -- 0x34 / 0x3D
  MSG("msg.npc37", { { "sasha", 0x080DE56A }, { "wife", 0x080F0F7E }, { "t2A", 0x080F10E8 },
    { "t3C", 0x080F0A5C }, { "t3Cafter", 0x080F0A42 }, { "t3D", 0x080F1226 } })
  -- Smiths.lua: the smiths (Smithy) and the frog / dwarf
  MSG("msg.smith", { { "home", 0x080D31AC }, { "dash", 0x080D322E }, { "frog", 0x080D3044 },
    { "frog2", 0x080D3762 }, { "offer", 0x080D320E }, { "no", 0x080D326C }, { "ask", 0x080D38DE },
    { "best", 0x080D3296 }, { "price", 0x080D32B2 }, { "paid", 0x080D32FA }, { "busy", 0x080D31FE },
    { "done", 0x080D341A }, { "wait", 0x080D33EE } })
  -- Sprites31.lua: the pond of happiness, 0x15A's cloud, the cauldron, the
  -- Four Sword keeper (0xF5), the riddle carver (0xF7)
  MSG("msg.spr37", { { "happiness", 0x080DF79E }, { "pondCost", 0x080DF84C }, { "cloud", 0x080DDD40 }, { "cauldronFull", 0x0810FB06 },
    { "cauldron", 0x0810F916 }, { "keeper", 0x08111C60 }, { "keeperNo", 0x08111ADA },
    { "carver0", 0x0811440A }, { "carver1", 0x08114426 }, { "carverNo", 0x0811419C },
    { "carverYes", 0x081141C4 }, { "carverBasket", 0x0811445A }, { "carverEmpty", 0x081144FA },
    { "carverRight", 0x0811453A }, { "carverDone", 0x081145F2 } })
  -- Townsfolk30.lua
  MSG("msg.town", { { "t1Fno", 0x080DC1B6 }, { "t1Fgive", 0x080DC232 }, { "t1Fafter", 0x080DC35C },
    { "t28end", 0x080DDFB8 }, { "t28", 0x080DE18A }, { "t28a", 0x080DE204 }, { "t28b", 0x080DE290 },
    { "t28c", 0x080DE2F6 }, { "t28d", 0x080DE364 }, { "t28no", 0x080DE1DA },
    { "t29again", 0x080DBEE6 }, { "t29need", 0x080DBF64 }, { "t29", 0x080DBF2E }, { "t29b", 0x080DBE60 },
    { "t29c", 0x080DC01C }, { "fortunePoor", 0x080D40DC }, { "fortune", 0x080D40F6 },
    { "fortuneDone", 0x080D3F30 }, { "quarrel", 0x0810E146 }, { "bombFull", 0x080DE96A },
    { "bombSold", 0x080DE9B2 }, { "tBC", 0x080DC40C } })
  -- numbers the code keeps in a register before a shared call (kind imm;
  -- add -3 = GBA -> SNES numbering): the cukeman (0x17D + frame & 1),
  -- the quarrelling brothers (door open / shut), the cauldron's bottle
  -- message, the Four Sword keeper (done / not yet), the carver's right
  -- answer (riddles 1 / 4 / 7, the others)
  S("msg.imm37", { 0x080E5E2E, 0x0810E116, 0x0810E130, 0x0810F8DE, 0x08111ABE, 0x08111B30, 0x0811426C, 0x08114246 }, 8, "imm", 0,
    { keys = { "cukeman", "quarrelOpen", "quarrelShut", "cauldronHalf", "keeperDone", "keeperPaid", "carverNext1", "carverNext" },
      op = { movs = true, ldr = true }, lo = 4, hi = 0x1CA, add = -3 })
  -- message tables (u16 GBA numbers; add -3), each tied to the code using it
  S("msg.tablets", 0x1797C8, 4, "u16", 0, { keys = { "cant", "ether", "cant2", "bombos" },
    lo = 4, hi = 0x1CA, add = -3, ref = { { 0x080F4EB0 } } })
  S("msg.book", 0x1796E0, 2, "u8", 0, { keys = { "nobook", "book" }, lo = 4, hi = 0xFF, add = -3,
    ref = { { 0x080F4A86 }, { 0x080F4B36, 2 } } })
  S("msg.bombGuy", 0x17645C, 2, "u16", 0, { lo = 4, hi = 0x1CA, add = -3, ref = { { 0x080DE8F4 } } })
  S("msg.inn", 0x175FDC, 2, "u16", 0, { lo = 4, hi = 0x1CA, add = -3, ref = { { 0x080DC120 } } })
  S("msg.shopHello", 0x17D080, 2, "u16", 0, { lo = 4, hi = 0x1CA, add = -3, ref = { { 0x0810E38A } } })
  -- kShopKeeper_GiveItemMsgs (ware - 7)
  S("msg.shopGive", 0x17D0CC, 7, "u16", 7, { lo = 4, hi = 0x1CA, add = -3, ref = { { 0x0810EF6C } } })
  -- Shop.lua: the bottle wares' prices (0x0810EDB4 reads s16 [index * 4];
  -- the bee's ware 13 is index 0: 0x0810F3B8 `movs r1, #0`)
  S("shop.bottlePrice", 0x17D0BC, 1, "s16", 0, { lo = 1, hi = 999, ref = { { 0x0810EE20 } } })
  S("shop.beeIndex", { 0x0810F3BE }, 1, "imm", 0, { op = { movs = true }, lo = 0, hi = 0 })
  -- Actors.lua: the follower's text triggers (0x08115D30 walks rows of 10
  -- bytes {y, x, bit, message (GBA number), follower}); the rooms
  -- (0x0817EC48, 7 u16) and each room's first row (0x0817ED06) pick a group
  S("msg.follow", 0x17EC56, 12, "u16", 0, { w = 5, ref = { { 0x08115F46 } } })
  S("msg.followRooms", 0x17EC48, 7, "u16", 0, { lo = 0, hi = 0x127, ref = { { 0x08115D0C } } })
  S("msg.followIdx", 0x17ED06, 8, "u8", 0, { lo = 0, hi = 12, ref = { { 0x08115F42 } } })
  -- Doors.lua: DungeonTransition_ScrollRoom (0x0806C6F0): the scroll's step
  -- by direction (0x14CAF2), kStaircaseTab4 (the counter from which Link
  -- moves with it, 0x14CAFA) and the camera bounds the scroll runs between
  -- (vertical 0x14CE14, set at 0x0806FBD0; horizontal 0x14CE0C, 0x0806F6E2)
  S("doors.scrollStep", 0x14CAF2, 4, "s16", 0, { lo = -8, hi = 8, ref = { { 0x0806C734 } } })
  S("doors.stairTab4", 0x14CAFA, 4, "s16", 0, { lo = 1, hi = 127, ref = { { 0x0806C766 }, { 0x0806C794 } } })
  S("doors.boundsV", 0x14CE14, 4, "u16", 0, { lo = 0, hi = 0x1FF, ref = { { 0x0806FBD0 } } })
  S("doors.boundsH", 0x14CE0C, 4, "u16", 0, { lo = 0, hi = 0x1FF, ref = { { 0x0806F6E2 } } })
  -- Hud.lua: the new game (0x0806BDB8, called after the file is made at
  -- 0x0812D9B6): the save area's fill value and the health / capacity value;
  -- "newfile.at" checks the store goes to the health capacity (0x0200234C)
  S("newfile", { 0x0806BDE8, 0x0806BDBE }, 2, "imm", 0, { keys = { "health", "fill" }, op = { movs = true }, lo = 0, hi = 0xA0 })
  S("newfile.at", { 0x0806BDE6 }, 1, "imm", 0, { op = { ldr = true }, lo = 0x0200234C, hi = 0x0200234C })
  -- prices / counts as code immediates: the smiths' tempering (10), the
  -- bomb guy's big bag (100 rupees, 27 bombs)
  S("price37", { 0x080D32EC, 0x080DE988, 0x080DE99C }, 3, "imm", 0,
    { keys = { "temper", "bombBag", "bombBagCount" }, op = { movs = true }, lo = 1, hi = 255 })
  -- r38: Sasha_Idle (0x080DE4C0) with the Pendant of Courage and no boots:
  -- u16 [map marked (> 2) ? 1 : 0] at 0x176428; with boots and the ice rod:
  -- all three pendants -> 0x080DE50E (sword <= 1) / 0x080DE4F6, else 0x080DE514
  S("msg.sashaBoots", 0x176428, 2, "u16", 0, { keys = { "unmarked", "marked" }, lo = 4, hi = 0x1CA, add = -3,
    ref = { { 0x080DE524 } } })
  S("msg.sasha38", { 0x080DE50E, 0x080DE4F6, 0x080DE514 }, 3, "imm", 0,
    { keys = { "allLow", "allHigh", "notAll" }, op = { movs = true }, lo = 4, hi = 0x1CA, add = -3 })
  -- r38: Follower_HandleTrigger (0x08115D30) turns the old man back into his
  -- sprite on the trigger message it compares with (`cmp r2, #n` 0x08115DDA)
  S("msg.oldManRevert", { 0x08115DDA }, 1, "imm", 0, { op = { cmp = true }, lo = 4, hi = 0x1CA, add = -3 })
  -- r38: the shared 20-rupee fee (0x080DE0DC: `cmp r0, #n - 1` / `movs r0,
  -- #n; rsbs`), paid to the storytellers (0x080DE1CC...) and the Four Sword
  -- keeper (0x08111ACC)
  S("fee20", { 0x080DE0EA, 0x080DE0E2 }, 2, "imm", 0, { keys = { "pay", "below" }, op = { movs = true, cmp = true }, lo = 1, hi = 255 })
  -- r59 (OwEdge59.lua): the overworld edge test 0x08071E7C (`cmp r2, #up`
  -- 0x08071ECE, `cmp r2, #left` 0x08071F34, `adds r0, #right-extra`
  -- 0x08071EF8), +0xC96's low byte (`movs r0, #n` 0x08076D26), the
  -- transition walk's step (`movs r4, #n` 0x0807274E) and its end bytes
  -- kOverworld_TransEnd (0x14D5C4, read at 0x0807278C)
  S("edge59.imm", { 0x08071ECE, 0x08071F34, 0x08071EF8, 0x08076D26, 0x0807274E }, 5, "imm", 0,
    { keys = { "up", "left", "rightExtra", "c96", "step" }, op = { movs = true, cmp = true, adds = true }, lo = 1, hi = 255 })
  S("edge59.end", 0x14D5C4, 4, "u16", 0, { lo = 0, hi = 255 })
  -- r60 (Hole60.lua): the overworld cell mask for a large / small area
  -- (`movs r4, #n; lsls` 0x0806A15A / 0x0806A162, stored to +0xC8A) and the
  -- pit drop's lift above the screen row (`adds r2, #n` 0x0809A9D2)
  S("hole60.imm", { 0x0806A15A, 0x0806A162, 0x0809A9D2 }, 3, "imm", 0,
    { keys = { "maskBig", "maskSmall", "drop" }, op = { movs = true, adds = true }, lo = 1, hi = 0x3FF })
  -- r60 (Slope60.lua): the indoor diagonal walls -- the kind by attr & 3
  -- (0x081682F6, read by 0x080A0698 / 0x0809FE64), the depths (0x08167D02,
  -- FlagMovingIntoSlopes_Y / _X 0x08093B68 / 0x08093CF8), the side bits
  -- (0x08167D22), the diagonal keys' pushes (0x08167D26 / 30 / 3A / 44,
  -- 0x08093EB0)
  S("slope60.kind", 0x1682F6, 4, "u16", 0, { lo = 0, hi = 7, ref = { { 0x080A06AA }, { 0x0809FE82 } } })
  S("slope60.depth", 0x167D02, 32, "u8", 0, { lo = 0, hi = 7, ref = { { 0x08093DC4 }, { 0x08093C10 } } })
  S("slope60.side", 0x167D22, 4, "u8", 0, { lo = 1, hi = 8, ref = { { 0x08093E8C }, { 0x08093CD0 } } })
  S("slope60.pxp", 0x167D26, 10, "u8", 0, { lo = 0, hi = 255, ref = { { 0x08093FA0 } } })
  S("slope60.pxn", 0x167D30, 10, "u8", 0, { lo = 0, hi = 255, ref = { { 0x08093FDA } } })
  S("slope60.pyp", 0x167D3A, 10, "u8", 0, { lo = 0, hi = 255, ref = { { 0x0809400C } } })
  S("slope60.pyn", 0x167D44, 10, "u8", 0, { lo = 0, hi = 255, ref = { { 0x0809402A } } })
end
