-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE WATT SHOP'S EVENTS SHELF: the real distributions, game by game.
--
-- Two kinds of thing, both as the cartridges really received them:
--
--   KEY EVENTS   the tickets, cards, letters and keys that opened each game's
--                event content (Southern Island, Navel Rock, Birth Island,
--                Faraway Island, Newmoon Island, Flower Paradise, the Rotom
--                room, Liberty Garden, the GS BALL ...). Each one is delivered
--                exactly the way the cartridge's own distribution left it: the
--                item in the KEY ITEMS pocket AND the flags / vars the ROM's
--                scripts test, through the engine's own Mystery Gift code --
--                src/ui/Gen3MysteryGift.lua (the SS Tidal rows),
--                src/pokemon/Gen4MysteryGift.lua (the Poke Mart deliveryman),
--                src/pokemon/Gen5MysteryGift.lua, src/script/Gen2Commands.lua
--                (the GS BALL's mobile-event byte).
--   EVENT POKEMON  the Nintendo / GameStop / Toys"R"Us / movie / tour
--                distributions, with the real event's OT, trainer id, level,
--                moves, held item, ball, ribbons and fateful-encounter mark
--                (and its personality and IVs where the distribution fixed
--                them). The data was read off the Project Pokemon Events
--                Gallery's dumps (one `src` per entry); only the facts are
--                kept. Gen 4 ones wait with the Poke Mart deliveryman, the way
--                a Wonder Card's Pokemon did; the others arrive in the party
--                (or the PC when it is full) on the next load.
--
-- HOW A PURCHASE TRAVELS. The launcher has no game loaded, so the purchase is
-- queued in the target save (`save.walkerEvents.pending`), and the game runs
-- WalkerEvents.apply when it loads that save (WalkerInbox.apply calls it),
-- where it has the dataset to build the Pokemon in that generation's shape and
-- to name the items. `save.walkerEvents.claimed` remembers every event the save
-- has bought, so a one-time event is never sold twice.
--
-- Only games the player can actually deliver to are offered (a save must
-- exist); each entry names the games it is for. Prices are this port's own.

local Ev = {}

-- one id per receiving game, the cartridge's own version numbers (the "origin
-- game" byte a Pokemon carries): Gen 4 Platinum 12, HeartGold 7, SoulSilver
-- 8; Gen 5 White 20, Black 21
Ev.ORIGIN = { platinum = 12, heartgold = 7, soulsilver = 8, white = 20, black = 21 }

-- the Gen 4 / 5 "met" places an event Pokemon carries: 3002 a faraway place
-- (a Wonder Card's Pokemon), 30001 Poke Transfer (a Gen 4 Pokemon in Unova)
Ev.MET_FARAWAY, Ev.MET_TRANSFER = 3002, 30001

-- Crystal: the byte the Mobile Adapter wrote (sMobileEventIndex), which
-- BattleTowerAction's CheckGSBall answers with GS_BALL_AVAILABLE ($0B)
Ev.GS_BALL_EVENT = 0x0B

-- Gen 3 flags the real Wonder Cards set (read off the cards' own scripts):
-- FireRed / LeafGreen FLAG_ENABLE_SHIP_NAVEL_ROCK 0x84A + FLAG_RECEIVED_
-- MYSTIC_TICKET 0x2A8, FLAG_ENABLE_SHIP_BIRTH_ISLAND 0x84B + FLAG_RECEIVED_
-- AURORA_TICKET 0x2A7 (pokefirered include/constants/flags.h); Emerald the
-- SS Tidal's own flag (Gen3MysteryGift) + FLAG_RECEIVED_AURORA_TICKET 0x13A /
-- _MYSTIC_TICKET 0x13B / _OLD_SEA_MAP 0x13C (pokeemerald flags.h)

-- ----------------------------------------------------------------- the list
--
-- Common fields: id, kind ("key" | "mon"), name, event (which distribution),
-- games (the versions it is for), price, about (what it opens), src.
Ev.EVENTS = {
  -- ======================================================= KEY EVENTS
  -- Crystal (pokecrystal GoldenrodPokecenter1F_GSBallScene: the receptionist
  -- appears only when BattleTowerAction's CheckGSBall says $0B)
  { id = "gs_ball", kind = "key", name = "GS Ball", games = { "crystal" }, price = 2000,
    event = "Mobile System GB GS Ball (Japan, 2001) / 3DS Virtual Console (2018)",
    about = "GOLDENROD POKE CENTER -- GS BALL, then CELEBI",
    handler = "gsball", src = "pokecrystal maps/GoldenrodPokecenter1F.asm; engine/events/battle_tower" },
  -- Emerald: the SS Tidal's four island rows (constants.gen3SSTidal)
  { id = "eon_ticket_e", kind = "key", name = "Eon Ticket", games = { "emerald" }, price = 2000,
    event = "Eon Ticket Mystery Event (e-Reader, Japan 2005)", item = "EON_TICKET",
    about = "SOUTHERN ISLAND -- LATIOS or LATIAS", handler = "tidal",
    src = "pokeemerald special ShouldDistributeEonTicket (VAR 0x403F), FLAG_ENABLE_SHIP_SOUTHERN_ISLAND" },
  { id = "mystic_ticket_e", kind = "key", name = "MysticTicket", games = { "emerald" }, price = 2400,
    event = "MysticTicket Wonder Card (Pokemon Trading Card Game World Championships, US 2005)",
    item = "MYSTICTICKET", received = 0x13B, about = "NAVEL ROCK -- LUGIA and HO-OH", handler = "tidal",
    src = "Project Pokemon EventsGallery: E - Item MysticTicket 2005 (ENG) (US).wc3 (script: setflag 0x8E0, 0x13B)" },
  { id = "aurora_ticket_e", kind = "key", name = "AuroraTicket", games = { "emerald" }, price = 2200,
    event = "AuroraTicket Wonder Card (Europe 2005, Pokemon Rocks America / Toys\"R\"Us US 2005)",
    item = "AURORATICKET", received = 0x13A, about = "BIRTH ISLAND -- DEOXYS", handler = "tidal",
    src = "Project Pokemon EventsGallery: E - Item AuroraTicket (ENG) (UK).wc3 (script: setflag 0x8D5, 0x13A)" },
  { id = "old_sea_map", kind = "key", name = "Old Sea Map", games = { "emerald" }, price = 2400,
    event = "Old Sea Map Wonder Card (Japan, 2005)", item = "OLD_SEA_MAP", received = 0x13C,
    about = "FARAWAY ISLAND -- MEW", handler = "tidal",
    src = "pokeemerald FLAG_ENABLE_SHIP_FARAWAY_ISLAND (0x8D6), FLAG_RECEIVED_OLD_SEA_MAP (0x13C)" },
  -- FireRed / LeafGreen: VermilionCity_EventScript_CheckHasMysticTicket /
  -- _CheckHasAuroraTicket want the flag AND the ticket, and the sailor only
  -- asks once the Rainbow Pass is in hand (the National Pokedex)
  { id = "mystic_ticket_frlg", kind = "key", name = "MysticTicket", games = { "firered" }, price = 2400,
    event = "MysticTicket Wonder Card (US, 2005)", item = "MYSTICTICKET", flags = { 0x84A, 0x2A8 },
    needs = "natdex", about = "NAVEL ROCK -- LUGIA and HO-OH", handler = "frlg",
    src = "Project Pokemon EventsGallery: FL - Item MysticTicket (ENG) (US).wc3 (script: setflag 0x84A, 0x2A8)" },
  { id = "aurora_ticket_frlg", kind = "key", name = "AuroraTicket", games = { "firered" }, price = 2200,
    event = "AuroraTicket Wonder Card (Toys\"R\"Us US, fall 2004)", item = "AURORATICKET", flags = { 0x84B, 0x2A7 },
    needs = "natdex", about = "BIRTH ISLAND -- DEOXYS", handler = "frlg",
    src = "Project Pokemon EventsGallery: FL - Item AuroraTicket 2004 Fall (ENG) (US).wc3 (script: setflag 0x84B, 0x2A7)" },
  -- Platinum: the deliveryman's handlers (pokeplatinum src/scrcmd_mystery_gift.c)
  { id = "member_card", kind = "key", name = "Member Card", games = { "platinum" }, price = 2400,
    event = "Member Card Wonder Card (Nintendo Wi-Fi, 2009)", base = "member_card",
    gift = { type = 8, item = 454, event = 0, text = 14 }, about = "NEWMOON ISLAND -- DARKRAI", handler = "gen4",
    src = "Project Pokemon EventsGallery: 018 Pt - Item Member Card (ENG).wc4 (PGT type 8)" },
  { id = "oaks_letter", kind = "key", name = "Oak's Letter", games = { "platinum" }, price = 2400,
    event = "Oak's Letter Wonder Card (Nintendo Wi-Fi, 2009)", base = "oaks_letter",
    gift = { type = 9, item = 452, event = 1, text = 15 }, about = "FLOWER PARADISE -- SHAYMIN", handler = "gen4",
    src = "Project Pokemon EventsGallery: 020 Pt - Item Oak's Letter (ENG).wc4 (PGT type 9)" },
  { id = "secret_key", kind = "key", name = "Secret Key", games = { "platinum" }, price = 1500,
    event = "Secret Key Wonder Card (Nintendo Wi-Fi, 2009)", base = "secret_key",
    gift = { type = 12, item = 467, event = 3, text = 17 }, about = "THE ROTOM ROOM -- ROTOM's forms", handler = "gen4",
    src = "Project Pokemon EventsGallery: 017 Pt - Item Secret Key (NA) (ENG).wc4 (PGT type 12; DISTRIBUTION_EVENT_ROTOM)" },
  { id = "azure_flute", kind = "key", name = "Azure Flute", games = { "platinum" }, price = 3000,
    event = "Azure Flute (prepared for an Arceus event that was never distributed)", base = "azure_flute",
    gift = { type = 10, item = 455, event = 2, text = 16 }, about = "HALL OF ORIGIN -- ARCEUS", handler = "gen4",
    src = "pokeplatinum src/scrcmd_mystery_gift.c (MYST_GIFT_AZURE_FLUTE, DISTRIBUTION_EVENT_ARCEUS)" },
  { id = "manaphy_egg", kind = "key", name = "Manaphy Egg", games = { "platinum", "heartgold", "soulsilver" }, price = 1500,
    event = "Pokemon Ranger Manaphy Egg (2006)", base = "manaphy_egg",
    gift = { type = 7, text = 13, label = "MANAPHY Egg" }, about = "A MANAPHY EGG -- hatches a MANAPHY", handler = "gen4",
    src = "pokeplatinum GenerateManaphyEgg; Project Pokemon EventsGallery: Gen 4/Pokemon Ranger Manaphy Egg" },
  -- HeartGold / SoulSilver (pokeheartgold: HasItem ITEM_ENIGMA_STONE, Pewter City)
  { id = "enigma_stone", kind = "key", name = "Enigma Stone", games = { "heartgold", "soulsilver" }, price = 2200,
    event = "Enigma Stone Wonder Card (Nintendo Wi-Fi, 2010)", base = "enigma_stone",
    gift = { type = 3, item = 536, text = 9 }, about = "PEWTER CITY -- LATIAS or LATIOS", handler = "gen4",
    src = "Project Pokemon EventsGallery: 054 HGSS - Item Enigma Stone (ENG).wc4 (PGT type 3, item 536)" },
  -- Black / White (Castelia's harbor: checkitem 574)
  { id = "liberty_pass", kind = "key", name = "Liberty Pass", games = { "black", "white" }, price = 2200,
    event = "Liberty Pass Wonder Card (Nintendo Wi-Fi, 2011)", itemId = 574, itemName = "Liberty Pass",
    about = "LIBERTY GARDEN -- VICTINI", handler = "gen5",
    src = "Project Pokemon EventsGallery: 2046 BW - Item Liberty Pass (ENG).pgf (item 574)" },

  -- ===================================================== EVENT POKEMON
  -- (generated from the decoded distributions; see the header)
  { id = "mew_vc", kind = "mon", name = "Mew", event = "Virtual Console 20th Anniversary Mew (2016)", games = { "red", "blue", "yellow", "gold", "silver", "crystal" }, price = 1500, src = "Project Pokemon EventsGallery: RBY - GF Mew (ENG) (UK).pk1",
    mon = { species = 151, level = 5, ot = "GF", tid = 22796, moves = { "Pound" } } },
  { id = "mew_tru", kind = "mon", name = "Mew", event = "Toys\"R\"Us Mew distribution (US, 2000)", games = { "red", "blue", "yellow", "gold", "silver", "crystal" }, price = 1400, src = "Project Pokemon EventsGallery: RBY - YOSHIBA (27869) Mew.pk1",
    mon = { species = 151, level = 5, ot = "YOSHIBA", tid = 27869, moves = { "Pound" } } },
  { id = "mew_stadium", kind = "mon", name = "Mew", event = "Pokemon Stadium Tour Mew (US, 2000)", games = { "red", "blue", "yellow", "gold", "silver", "crystal" }, price = 1400, src = "Project Pokemon EventsGallery: RBY - LINKW (01838) Mew.pk1",
    mon = { species = 151, level = 5, ot = "LINKW", tid = 1838, moves = { "Pound" } } },
  { id = "pikachu_surf", kind = "mon", name = "Surfing Pikachu", event = "Nintendo Power Surfing Pikachu (US, 1999)", games = { "red", "blue", "yellow", "gold", "silver", "crystal" }, price = 700, src = "Project Pokemon EventsGallery: RBY - YOSHIRA (05238) Pikachu.pk1",
    mon = { species = 25, level = 5, ot = "YOSHIRA", tid = 5238, moves = { "Thunder Shock", "Growl", "Surf" } } },
  { id = "celebi_ctour", kind = "mon", name = "Celebi", event = "Celebi Tour (US, 2001)", games = { "gold", "silver", "crystal" }, price = 1500, src = "Project Pokemon EventsGallery: GS - CTOUR (17142) Celebi (ENG).pk2",
    mon = { species = 251, level = 5, ot = "CTOUR", tid = 17142, moves = { "Leech Seed", "Confusion", "Recover", "Heal Bell" }, item = "PSNCureBerry", friendship = 255 } },
  { id = "pcny_lapras", kind = "mon", name = "Shiny Lapras Egg", event = "Pokemon Center New York egg (2002)", games = { "gold", "silver", "crystal" }, price = 800, src = "Project Pokemon EventsGallery: GSC - Shiny Future Sight Lapras (ENG).pk2",
    mon = { species = 131, level = 5, egg = true, dvs = 0x7aaa, moves = { "Water Gun", "Growl", "Sing", "Future Sight" }, friendship = 120 } },
  { id = "pcny_charmander", kind = "mon", name = "Shiny Charmander Egg", event = "Pokemon Center New York egg (2002)", games = { "gold", "silver", "crystal" }, price = 800, src = "Project Pokemon EventsGallery: GSC - Shiny Crunch Charmander (ENG).pk2",
    mon = { species = 4, level = 5, egg = true, dvs = 0x3aaa, moves = { "Scratch", "Growl", "Crunch" }, friendship = 126 } },
  { id = "pcny_squirtle", kind = "mon", name = "Squirtle Egg", event = "Pokemon Center New York egg (2002)", games = { "gold", "silver", "crystal" }, price = 500, src = "Project Pokemon EventsGallery: GSC - Zap Cannon Squirtle (ENG).pk2",
    mon = { species = 7, level = 5, egg = true, moves = { "Tackle", "Tail Whip", "Zap Cannon" }, friendship = 120 } },
  { id = "pcny_chikorita", kind = "mon", name = "Chikorita Egg", event = "Pokemon Center New York egg (2002)", games = { "gold", "silver", "crystal" }, price = 500, src = "Project Pokemon EventsGallery: GSC - Petal Dance Chikorita (ENG).pk2",
    mon = { species = 152, level = 5, egg = true, moves = { "Tackle", "Growl", "Petal Dance" }, friendship = 120 } },
  { id = "jirachi_wishmkr", kind = "mon", name = "Jirachi", event = "Colosseum bonus disc WISHMKR Jirachi (US, 2003)", games = { "firered", "emerald" }, price = 1500, src = "Project Pokemon EventsGallery: RSEFL - WISHMKR Jirachi (1910) (ENG).pk3",
    mon = { species = 385, level = 5, ot = "WISHMKR", tid = 20043, sid = 0, otFemale = false, pid = 0x7a0df4bc, ivs = { 26, 13, 8, 1, 4, 13 }, abilityBit = 0, moves = { "Wish", "Confusion", "Rest" }, item = "Salac Berry", ball = "Poke Ball", friendship = 70, lang = 2, metLevel = 5, metGame = 2 } },
  { id = "jirachi_channel", kind = "mon", name = "Shiny Jirachi", event = "Pokemon Channel Jirachi (EU, 2004)", games = { "firered", "emerald" }, price = 2200, src = "Project Pokemon EventsGallery: RS - Shiny CHANNEL Jirachi (3B03D5CF) (ENG).pk3",
    mon = { species = 385, level = 5, ot = "CHANNEL", tid = 40122, sid = 54611, otFemale = true, pid = 0x5eea1706, shiny = true, ivs = { 29, 30, 29, 29, 31, 28 }, abilityBit = 0, moves = { "Wish", "Confusion", "Rest" }, item = "Salac Berry", ball = "Poke Ball", friendship = 70, lang = 2, metLevel = 0, metGame = 2 } },
  { id = "mew_aura", kind = "mon", name = "Mew", event = "Aura Mew (Europe / US, 2005)", games = { "firered", "emerald" }, price = 1600, src = "Project Pokemon EventsGallery: RSEFL - Aura Mew (0E20) (ENG).pk3",
    mon = { species = 151, level = 10, ot = "Aura", tid = 20078, sid = 0, otFemale = true, pid = 0x11142243, ivs = { 26, 19, 16, 19, 11, 19 }, abilityBit = 0, moves = { "Pound", "Transform" }, ball = "Poke Ball", friendship = 100, fateful = true, ribbons3 = 0x80000000, lang = 2, metLevel = 10, metGame = 2 } },
  { id = "deoxys_doel", kind = "mon", name = "Deoxys", event = "DOEL Deoxys (Europe, 2005)", games = { "firered", "emerald" }, price = 1700, src = "Project Pokemon EventsGallery: RSEFL - DOEL Deoxys (288A) (ENG).pk3",
    mon = { species = 386, level = 70, ot = "DOEL", tid = 28606, sid = 0, otFemale = true, pid = 0x71273d46, ivs = { 21, 29, 14, 12, 8, 1 }, abilityBit = 0, moves = { "Cosmic Power", "Recover", "Psycho Boost", "Hyper Beam" }, ball = "Poke Ball", friendship = 70, fateful = true, ribbons3 = 0x80000000, lang = 2, metLevel = 70, metGame = 2 } },
  { id = "deoxys_spacec", kind = "mon", name = "Deoxys", event = "Space Center Deoxys (US, 2006)", games = { "firered", "emerald" }, price = 1700, src = "Project Pokemon EventsGallery: RSEFL - SPACE C Deoxys (027E) (ENG).pk3",
    mon = { species = 386, level = 70, ot = "SPACE C", tid = 10, sid = 0, otFemale = false, pid = 0xbf01830, ivs = { 0, 9, 13, 31, 8, 11 }, abilityBit = 0, moves = { "Cosmic Power", "Recover", "Psycho Boost", "Hyper Beam" }, ball = "Poke Ball", friendship = 70, fateful = true, ribbons3 = 0x80000000, lang = 2, metLevel = 70, metGame = 2 } },
  { id = "metang_rocks", kind = "mon", name = "Metang", event = "Pokemon Rocks America Metang (US, 2005)", games = { "firered", "emerald" }, price = 700, src = "Project Pokemon EventsGallery: RSEFL - ROCKS Metang (21C1) (ENG).pk3",
    mon = { species = 375, level = 30, ot = "ROCKS", tid = 2005, sid = 0, otFemale = false, pid = 0x269d9bfc, ivs = { 15, 20, 25, 23, 23, 30 }, abilityBit = 0, moves = { "Take Down", "Confusion", "Metal Claw", "Refresh" }, ball = "Poke Ball", friendship = 70, ribbons3 = 0x1000000, lang = 2, metLevel = 30, metGame = 2 } },
  { id = "hooh_mattle", kind = "mon", name = "Ho-Oh", event = "Pokemon Colosseum Mt. Battle Ho-Oh (2004)", games = { "firered", "emerald" }, price = 1800, src = "Project Pokemon EventsGallery: RSEFL - MATTLE Ho-Oh (ENG).pk3",
    mon = { species = 250, level = 70, ot = "MATTLE", tid = 10048, sid = 0, otFemale = false, pid = 0x2c77f0d7, ivs = { 7, 16, 26, 31, 2, 23 }, abilityBit = 0, moves = { "Recover", "Fire Blast", "Sunny Day", "Swift" }, ball = "Poke Ball", friendship = 70, lang = 2, metLevel = 70, metGame = 1 } },
  { id = "lugia_10anniv", kind = "mon", name = "Lugia", event = "10th Anniversary distribution (US, 2006)", games = { "firered", "emerald" }, price = 1800, src = "Project Pokemon EventsGallery: RSEFL - 10ANNIV Lugia (ENG).pk3",
    mon = { species = 249, level = 70, ot = "10ANNIV", tid = 6227, sid = 0, otFemale = true, pid = 0x828027a9, ivs = { 26, 19, 19, 30, 28, 17 }, abilityBit = 0, moves = { "Recover", "Hydro Pump", "Rain Dance", "Swift" }, ball = "Poke Ball", friendship = 0, lang = 2, metLevel = 70, metGame = 2 } },
  { id = "hooh_10anniv", kind = "mon", name = "Ho-Oh", event = "10th Anniversary distribution (US, 2006)", games = { "firered", "emerald" }, price = 1800, src = "Project Pokemon EventsGallery: RSEFL - 10ANNIV Ho-Oh (ENG).pk3",
    mon = { species = 250, level = 70, ot = "10ANNIV", tid = 6227, sid = 0, otFemale = false, pid = 0x63e92b5f, ivs = { 31, 27, 11, 10, 29, 11 }, abilityBit = 0, moves = { "Recover", "Fire Blast", "Sunny Day", "Swift" }, ball = "Poke Ball", friendship = 0, lang = 2, metLevel = 70, metGame = 2 } },
  { id = "pikachu_10anniv", kind = "mon", name = "Pikachu", event = "10th Anniversary distribution (US, 2006)", games = { "firered", "emerald" }, price = 600, src = "Project Pokemon EventsGallery: RSEFL - 10ANNIV Pikachu (ENG).pk3",
    mon = { species = 25, level = 70, ot = "10ANNIV", tid = 6227, sid = 0, otFemale = true, pid = 0x9dac4d51, ivs = { 1, 8, 14, 25, 26, 31 }, abilityBit = 0, moves = { "Thunderbolt", "Agility", "Thunder", "Light Screen" }, item = "Light Ball", ball = "Poke Ball", friendship = 70, lang = 2, metLevel = 70, metGame = 2 } },
  { id = "pikachu_fly", kind = "mon", name = "Flying Pikachu", event = "Party of the Decade (US, 2006)", games = { "firered", "emerald" }, price = 700, src = "Project Pokemon EventsGallery: RSEFL - 10 ANIV Fly Pikachu (9DB1) (ENG).pk3",
    mon = { species = 25, level = 70, ot = "10 ANIV", tid = 6808, sid = 0, otFemale = true, pid = 0x1835349d, ivs = { 27, 16, 17, 28, 0, 16 }, abilityBit = 0, moves = { "Thunderbolt", "Fly", "Thunder", "Light Screen" }, item = "Light Ball", ball = "Poke Ball", friendship = 70, lang = 2, metLevel = 70, metGame = 2 } },
  { id = "zigzagoon_berry", kind = "mon", name = "Shiny Zigzagoon", event = "Berry Glitch fix gift (2003)", games = { "firered", "emerald" }, price = 600, src = "Project Pokemon EventsGallery: RS - Berry Glitch Shiny Zigzagoon (0000) (ENG).pk3",
    mon = { species = 263, level = 5, ot = "RUBY", tid = 30317, sid = 0, otFemale = true, pid = 0x7669, shiny = true, ivs = { 16, 13, 12, 2, 18, 3 }, abilityBit = 0, moves = { "Tackle", "Growl", "Tail Whip" }, item = "Liechi Berry", ball = "Poke Ball", friendship = 70, lang = 2, metLevel = 5, metGame = 1 } },
  { id = "egg_zigzagoon", kind = "mon", name = "Zigzagoon Egg", event = "Pokemon Box Ruby & Sapphire egg (2004)", games = { "firered", "emerald" }, price = 450, src = "Project Pokemon EventsGallery: RSEFL - Extreme Speed Zigzagoon Egg.pk3",
    mon = { species = 263, level = 5, egg = true, pid = 0xe8dbef75, ivs = { 7, 15, 27, 9, 23, 18 }, abilityBit = 0, moves = { "Tackle", "Growl", "Tail Whip", "Extreme Speed" }, ball = "Poke Ball", friendship = 15, lang = 1, metLevel = 0, metGame = 2 } },
  { id = "egg_swablu", kind = "mon", name = "Swablu Egg", event = "Pokemon Box Ruby & Sapphire egg (2004)", games = { "firered", "emerald" }, price = 400, src = "Project Pokemon EventsGallery: RSEFL - False Swipe Swablu Egg.pk3",
    mon = { species = 333, level = 5, egg = true, pid = 0xe717b115, ivs = { 10, 16, 16, 15, 17, 19 }, abilityBit = 0, moves = { "Peck", "Growl", "False Swipe" }, ball = "Poke Ball", friendship = 20, lang = 1, metLevel = 0, metGame = 2 } },
  { id = "egg_skitty", kind = "mon", name = "Skitty Egg", event = "Pokemon Box Ruby & Sapphire egg (2004)", games = { "firered", "emerald" }, price = 400, src = "Project Pokemon EventsGallery: RSEFL - Pay Day Skitty Egg.pk3",
    mon = { species = 300, level = 5, egg = true, pid = 0x24f841ea, ivs = { 7, 2, 23, 1, 16, 19 }, abilityBit = 0, moves = { "Growl", "Tackle", "Tail Whip", "Pay Day" }, ball = "Poke Ball", friendship = 15, lang = 1, metLevel = 0, metGame = 3 } },
  { id = "egg_pichu", kind = "mon", name = "Pichu Egg", event = "Pokemon Box Ruby & Sapphire egg (2004)", games = { "firered", "emerald" }, price = 450, src = "Project Pokemon EventsGallery: RSEFL - Surf Pichu Egg.pk3",
    mon = { species = 172, level = 5, egg = true, pid = 0x761b9fd1, ivs = { 5, 11, 8, 10, 22, 8 }, abilityBit = 0, moves = { "Thunder Shock", "Charm", "Surf" }, ball = "Poke Ball", friendship = 10, lang = 1, metLevel = 0, metGame = 5 } },
  { id = "egg_kangaskhan", kind = "mon", name = "Kangaskhan Egg", event = "WISH egg, Pokemon Center New York (2004)", games = { "firered" }, price = 450, src = "Project Pokemon EventsGallery: FL - Wish Kangaskhan Egg (AFD514C).pk3",
    mon = { species = 115, level = 5, egg = true, pid = 0xd8640969, ivs = { 31, 28, 9, 8, 2, 20 }, abilityBit = 0, moves = { "Yawn", "Wish" }, ball = "Poke Ball", friendship = 20, fateful = true, ribbons3 = 0x80000000, lang = 1, metLevel = 0, metGame = 4 } },
  { id = "manaphy_tru", kind = "mon", name = "Manaphy", event = "Toys\"R\"Us Manaphy (US, 2008)", games = { "platinum", "heartgold", "soulsilver" }, price = 1500, src = "Project Pokemon EventsGallery: 001 DP - TRU Manaphy (ENG).wc4",
    mon = { species = 490, level = 50, ot = "TRU", tid = 9297, sid = 60303, otFemale = true, moves = { "Heart Swap", "Water Pulse", "Whirlpool", "Acid Armor" }, item = "Red Scarf", ball = "Cherish Ball", friendship = 70, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "darkrai_alamos", kind = "mon", name = "Darkrai", event = "The Rise of Darkrai movie event (US, 2008)", games = { "platinum", "heartgold", "soulsilver" }, price = 1800, src = "Project Pokemon EventsGallery: 007 DP - Movie Darkrai (NA) (ENG).wc4",
    mon = { species = 491, level = 50, ot = "ALAMOS", tid = 5318, sid = 10413, otFemale = true, moves = { "Roar of Time", "Spacial Rend", "Nightmare", "Hypnosis" }, item = "Enigma Berry", ball = "Cherish Ball", friendship = 0, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "deoxys_gamestop", kind = "mon", name = "Deoxys", event = "GameStop Deoxys (US, 2008)", games = { "platinum", "heartgold", "soulsilver" }, price = 1700, src = "Project Pokemon EventsGallery: 008 DP - GameStop Deoxys (ENG).wc4",
    mon = { species = 386, level = 50, ot = "Gamestp", tid = 6218, sid = 31630, otFemale = false, moves = { "Psycho Boost", "Zap Cannon", "Iron Defense", "Extreme Speed" }, item = "Never-Melt Ice", ball = "Cherish Ball", friendship = 0, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "dragonite_tru", kind = "mon", name = "Dragonite", event = "Toys\"R\"Us Dragonite (US, 2008)", games = { "platinum", "heartgold", "soulsilver" }, price = 1100, src = "Project Pokemon EventsGallery: 012 DP - TRU Dragonite (ENG).wc4",
    mon = { species = 149, level = 50, ot = "TRU", tid = 11088, sid = 47337, otFemale = false, pid = 0xe2cfbfc, moves = { "Draco Meteor", "Thunderbolt", "Outrage", "Dragon Dance" }, item = "Yache Berry", ball = "Cherish Ball", friendship = 35, fateful = true, ribbons4 = { 0x0, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "pikachu_nzone", kind = "mon", name = "Pikachu", event = "Nintendo Zone Pikachu (US, 2008)", games = { "platinum", "heartgold", "soulsilver" }, price = 600, src = "Project Pokemon EventsGallery: 013 DP - Nzone Pikachu (ENG).wc4",
    mon = { species = 25, level = 20, ot = "Nzone", tid = 10278, sid = 59322, otFemale = false, pid = 0x21acda5a, moves = { "Present", "Quick Attack", "Thunder Shock", "Tail Whip" }, item = "Light Ball", ball = "Cherish Ball", friendship = 70, fateful = true, ribbons4 = { 0x0, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "shaymin_tru", kind = "mon", name = "Shaymin", event = "Giratina & the Sky Warrior movie (US, 2009)", games = { "platinum", "heartgold", "soulsilver" }, price = 1700, src = "Project Pokemon EventsGallery: 014 DP - Movie Shaymin (NA) (ENG).wc4",
    mon = { species = 492, level = 50, ot = "TRU", tid = 2089, sid = 14103, otFemale = false, moves = { "Seed Flare", "Aromatherapy", "Substitute", "Energy Ball" }, item = "Micle Berry", ball = "Cherish Ball", friendship = 100, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "regigigas_tru", kind = "mon", name = "Regigigas", event = "Toys\"R\"Us Regigigas (US, 2009)", games = { "platinum", "heartgold", "soulsilver" }, price = 1800, src = "Project Pokemon EventsGallery: 015 DP - Movie Regigigas (NA) (ENG).wc4",
    mon = { species = 486, level = 100, ot = "TRU", tid = 3089, sid = 29347, otFemale = false, moves = { "Iron Head", "Rock Slide", "Icy Wind", "Crush Grip" }, item = "Custap Berry", ball = "Cherish Ball", friendship = 0, fateful = true, ribbons4 = { 0x0, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "arceus_tru", kind = "mon", name = "Arceus", event = "Arceus & the Jewel of Life movie (US, 2009)", games = { "platinum", "heartgold", "soulsilver" }, price = 2500, src = "Project Pokemon EventsGallery: 019 DPPt - Movie Arceus (NA) (ENG).wc4",
    mon = { species = 493, level = 100, ot = "TRU", tid = 11079, sid = 62276, otFemale = false, moves = { "Judgment", "Roar of Time", "Spacial Rend", "Shadow Force" }, item = "Rowap Berry", ball = "Cherish Ball", friendship = 0, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "pichu_gamestop", kind = "mon", name = "Shiny Pichu", event = "GameStop Pikachu-colored Pichu (US, 2009)", games = { "platinum", "heartgold", "soulsilver" }, price = 1100, src = "Project Pokemon EventsGallery: 021 DPPt - Pikachu-Colored Pichu (NA) (ENG).wc4",
    mon = { species = 172, level = 30, ot = "GAMESTP", tid = 1300, sid = 52721, otFemale = true, pid = 0x450e8dea, shiny = true, moves = { "Charge", "Volt Tackle", "Endeavor", "Endure" }, item = "Everstone", ball = "Cherish Ball", friendship = 70, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "darkrai_almia", kind = "mon", name = "Darkrai", event = "Ranger: Shadows of Almia Darkrai (2009)", games = { "platinum", "heartgold", "soulsilver" }, price = 1800, src = "Project Pokemon EventsGallery: 022 DPPtHGSS - Almia Darkrai (ENG).wc4",
    mon = { species = 491, level = 50, ot = "Almia", tid = 3208, sid = 46999, otFemale = false, moves = { "Dark Void", "Dark Pulse", "Shadow Ball", "Double Team" }, ball = "Poke Ball", friendship = 0, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "riolu_kyle", kind = "mon", name = "Riolu", event = "Ranger: Shadows of Almia Riolu (2009)", games = { "platinum", "heartgold", "soulsilver" }, price = 800, src = "Project Pokemon EventsGallery: 023 DPPtHGSS - Kyle Riolu (ENG).wc4",
    mon = { species = 447, level = 30, ot = "Kyle", tid = 3208, sid = 64847, otFemale = false, pid = 0x6a6d188, moves = { "Aura Sphere", "Shadow Claw", "Bullet Punch", "Drain Punch" }, ball = "Poke Ball", friendship = 70, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "jirachi_gamestop", kind = "mon", name = "Jirachi", event = "GameStop Jirachi (US, 2009)", games = { "platinum", "heartgold", "soulsilver" }, price = 1600, src = "Project Pokemon EventsGallery: 024 DPPt - Gamestop Jirachi (ENG).wc4",
    mon = { species = 385, level = 5, ot = "GAMESTP", tid = 2270, sid = 54369, otFemale = true, moves = { "Wish", "Confusion", "Rest", "Draco Meteor" }, item = "Liechi Berry", ball = "Cherish Ball", friendship = 100, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "mew_fal2010", kind = "mon", name = "Mew", event = "Pokemon 2010 Fall Mew (US, 2010)", games = { "heartgold", "soulsilver" }, price = 1600, src = "Project Pokemon EventsGallery: 053 HGSS - Anniversary Mew (ENG).wc4",
    mon = { species = 151, level = 5, ot = "FAL2010", tid = 10160, sid = 39598, otFemale = true, moves = { "Pound" }, ball = "Cherish Ball", friendship = 100, fateful = true, ribbons4 = { 0x8000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "eevee_vgc10", kind = "mon", name = "Shiny Eevee", event = "VGC 2010 Eevee (US, 2010)", games = { "heartgold", "soulsilver" }, price = 900, src = "Project Pokemon EventsGallery: 052 HGSS - VGC 2010 Eevee (ENG).wc4",
    mon = { species = 133, level = 50, ot = "VGC10", tid = 5080, sid = 49497, otFemale = false, pid = 0x5fef8d69, shiny = true, moves = { "Iron Tail", "Trump Card", "Flail", "Quick Attack" }, item = "Focus Sash", ball = "Cherish Ball", friendship = 70, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "raikou_gamestop", kind = "mon", name = "Shiny Raikou", event = "GameStop shiny legendary beasts (US, 2010)", games = { "platinum", "heartgold", "soulsilver" }, price = 1600, src = "Project Pokemon EventsGallery: 059 DPPtHGSS - GameStop Raikou (ENG).wc4",
    mon = { species = 243, level = 30, ot = "GAMESTP", tid = 1031, sid = 21889, otFemale = false, pid = 0x36d46750, shiny = true, moves = { "Zap Cannon", "Aura Sphere", "Extreme Speed", "Weather Ball" }, item = "Micle Berry", ball = "Cherish Ball", friendship = 35, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "entei_gamestop", kind = "mon", name = "Shiny Entei", event = "GameStop shiny legendary beasts (US, 2010)", games = { "platinum", "heartgold", "soulsilver" }, price = 1600, src = "Project Pokemon EventsGallery: 060 DPPtHGSS - GameStop Entei (ENG).wc4",
    mon = { species = 244, level = 30, ot = "GAMESTP", tid = 1171, sid = 52447, otFemale = false, pid = 0x7d5bb510, shiny = true, moves = { "Flare Blitz", "Howl", "Extreme Speed", "Crush Claw" }, item = "Custap Berry", ball = "Cherish Ball", friendship = 35, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "suicune_gamestop", kind = "mon", name = "Shiny Suicune", event = "GameStop shiny legendary beasts (US, 2010)", games = { "platinum", "heartgold", "soulsilver" }, price = 1600, src = "Project Pokemon EventsGallery: 061 DPPtHGSS - GameStop Suicune (ENG).wc4",
    mon = { species = 245, level = 30, ot = "GAMESTP", tid = 1311, sid = 64410, otFemale = false, pid = 0x42fcbc7e, shiny = true, moves = { "Sheer Cold", "Air Slash", "Extreme Speed", "Aqua Ring" }, item = "Rowap Berry", ball = "Cherish Ball", friendship = 35, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "celebi_gamestop", kind = "mon", name = "Celebi", event = "GameStop Celebi (US, 2010)", games = { "platinum", "heartgold", "soulsilver" }, price = 1600, src = "Project Pokemon EventsGallery: 062 DPPtHGSS - GameStop Celebi (ENG).wc4",
    mon = { species = 251, level = 50, ot = "GAMESTP", tid = 2271, sid = 10415, otFemale = true, moves = { "Leaf Storm", "Recover", "Nasty Plot", "Healing Wish" }, item = "Jaboca Berry", ball = "Cherish Ball", friendship = 100, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "pikachu_ash", kind = "mon", name = "Ash's Pikachu", event = "Ash's Pikachu (US, 2010)", games = { "platinum", "heartgold", "soulsilver" }, price = 900, src = "Project Pokemon EventsGallery: 065 DPPtHGSS - Ash's Pikachu (ENG).wc4",
    mon = { species = 25, level = 50, ot = "Ash", tid = 1301, sid = 35254, otFemale = false, pid = 0x37a47a8a, moves = { "Volt Tackle", "Iron Tail", "Quick Attack", "Thunderbolt" }, item = "Light Ball", ball = "Cherish Ball", friendship = 70, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 3002 } },
  { id = "victini_movie14", kind = "mon", name = "Victini", event = "Movie14 Victini, Black / White movie (US, 2012)", games = { "black", "white" }, price = 1800, src = "Project Pokemon EventsGallery: 0032 BW - Movie14 Victini (ENG).pgf",
    mon = { species = 494, level = 50, ot = "Movie14", tid = 12031, sid = 0, notShiny = true, abilityType = 0, moves = { "V-create", "Fusion Flare", "Fusion Bolt", "Searing Shot" }, item = "Fire Gem", ball = "Cherish Ball", fateful = true, ribbons5 = 0x400, metLevel = 50, metLocation = 40069 } },
  { id = "darkrai_2011win", kind = "mon", name = "Darkrai", event = "Winter 2011 Darkrai (US, 2011)", games = { "black", "white" }, price = 1800, src = "Project Pokemon EventsGallery: 0028 BW - 2011WIN Darkrai (ENG).pgf",
    mon = { species = 491, level = 50, ot = "2011WIN", tid = 11011, sid = 0, otFemale = false, notShiny = true, abilityType = 0, moves = { "Dark Void", "Ominous Wind", "Feint Attack", "Nightmare" }, item = "Enigma Berry", ball = "Cherish Ball", fateful = true, ribbons5 = 0x10, metLevel = 50, metLocation = 40059 } },
  { id = "zoroark_smr2011", kind = "mon", name = "Zoroark", event = "Summer 2011 Zoroark (US, 2011)", games = { "black", "white" }, price = 1100, src = "Project Pokemon EventsGallery: 0030 BW - SMR2011 Zoroark (ENG).pgf",
    mon = { species = 571, level = 50, ot = "SMR2011", tid = 6011, sid = 0, otFemale = false, notShiny = true, nature = 24, gender = "male", abilityType = 0, moves = { "Agility", "Embargo", "Punishment", "Snarl" }, ball = "Cherish Ball", fateful = true, ribbons5 = 0x10, metLevel = 50, metLocation = 40059 } },
  { id = "zekrom_spr2012", kind = "mon", name = "Zekrom", event = "Spring 2012 Zekrom (US, 2012)", games = { "black" }, price = 2200, src = "Project Pokemon EventsGallery: 0033 B - SPR2012 Zekrom (ENG).pgf",
    mon = { species = 644, level = 100, ot = "SPR2012", tid = 3102, sid = 0, otFemale = false, notShiny = true, abilityType = 0, moves = { "Bolt Strike", "Fusion Bolt", "Haze", "Outrage" }, item = "Dragon Gem", ball = "Cherish Ball", fateful = true, ribbons5 = 0x400, metLevel = 100, metLocation = 40069 } },
  { id = "reshiram_spr2012", kind = "mon", name = "Reshiram", event = "Spring 2012 Reshiram (US, 2012)", games = { "white" }, price = 2200, src = "Project Pokemon EventsGallery: 0033 W - SPR2012 Reshiram (ENG).pgf",
    mon = { species = 643, level = 100, ot = "SPR2012", tid = 3102, sid = 0, otFemale = false, notShiny = true, abilityType = 0, moves = { "Blue Flare", "Fusion Flare", "Mist", "Draco Meteor" }, item = "Dragon Gem", ball = "Cherish Ball", fateful = true, ribbons5 = 0x400, metLevel = 100, metLocation = 40069 } },
  { id = "mewtwo_feb2012", kind = "mon", name = "Mewtwo", event = "February 2012 Mewtwo (US, 2012)", games = { "black", "white" }, price = 2000, src = "Project Pokemon EventsGallery: 0048 BW - FEB2012 Mewtwo (ENG).pgf",
    mon = { species = 150, level = 70, ot = "FEB2012", tid = 2112, sid = 0, otFemale = false, notShiny = true, abilityType = 0, moves = { "Psystrike", "Shadow Ball", "Aura Sphere", "Electro Ball" }, item = "King's Rock", ball = "Cherish Ball", fateful = true, ribbons5 = 0x20, metLevel = 70, metLocation = 40069 } },
  { id = "keldeo_smr2012", kind = "mon", name = "Keldeo", event = "Summer 2012 Keldeo (US, 2012)", games = { "black", "white" }, price = 1700, src = "Project Pokemon EventsGallery: 0069 BW - SMR2012 Keldeo (ENG).pgf",
    mon = { species = 647, level = 15, ot = "SMR2012", tid = 8272, sid = 0, otFemale = false, notShiny = true, abilityType = 0, moves = {  }, item = "PP Max", ball = "Cherish Ball", fateful = true, ribbons5 = 0x400, metLevel = 15, metLocation = 40001 } },
  { id = "egg_axew", kind = "mon", name = "Axew Egg", event = "Trainer Egg distribution (2011)", games = { "black", "white" }, price = 500, src = "Project Pokemon EventsGallery: 0029 BW - (Trainer) Axew Egg (ENG).pgf",
    mon = { species = 610, level = 1, egg = true, notShiny = true, ivs5 = { nil, nil, nil, 31, nil, nil }, nature = 14, gender = "male", abilityType = 1, moves = { "Scratch", "Dragon Rage" }, ball = "Poke Ball", metLevel = 0, eggLocation = 40059 } },
  { id = "karrablast_smr2011", kind = "mon", name = "Karrablast", event = "Summer 2011 Karrablast (US, 2011)", games = { "black", "white" }, price = 600, src = "Project Pokemon EventsGallery: 0002 BW - SMR2011 Karrablast (ENG).pgf",
    mon = { species = 588, level = 50, ot = "SMR2011", tid = 6011, sid = 0, otFemale = false, notShiny = true, abilityType = 3, moves = { "Megahorn", "Take Down", "X-Scissor", "Flail" }, item = "Bug Gem", ball = "Cherish Ball", fateful = true, ribbons5 = 0x10, metLevel = 50, metLocation = 40059 } },
  { id = "shelmet_smr2011", kind = "mon", name = "Shelmet", event = "Summer 2011 Shelmet (US, 2011)", games = { "black", "white" }, price = 600, src = "Project Pokemon EventsGallery: 0003 BW - SMR2011 Shelmet (ENG).pgf",
    mon = { species = 616, level = 50, ot = "SMR2011", tid = 6011, sid = 0, otFemale = false, notShiny = true, abilityType = 3, moves = { "Encore", "Giga Drain", "Body Slam", "Bug Buzz" }, item = "Bug Gem", ball = "Cherish Ball", fateful = true, ribbons5 = 0x10, metLevel = 50, metLocation = 40059 } },
  { id = "pikachu_smr2012", kind = "mon", name = "Pikachu", event = "Summer 2012 Pikachu (US, 2012)", games = { "black", "white" }, price = 900, src = "Project Pokemon EventsGallery: 0071 BW - SMR2012 Pikachu (ENG).pgf",
    mon = { species = 25, level = 100, ot = "SMR2012", tid = 7012, sid = 0, otFemale = false, gender = "female", abilityType = 0, moves = { "Volt Tackle", "Thunder", "Grass Knot", "Quick Attack" }, item = "Light Ball", ball = "Cherish Ball", fateful = true, ribbons5 = 0x40, metLevel = 100, metLocation = 40059 } },
  { id = "raikou_gamestop_bw", kind = "mon", name = "Shiny Raikou", event = "GameStop shiny beasts (US, 2010), Poke Transfer", games = { "black", "white" }, price = 1600, about = "LOSTLORN FOREST -- ZOROARK", src = "Project Pokemon EventsGallery: 059 DPPtHGSS - GameStop Raikou (ENG).wc4",
    mon = { species = 243, level = 30, ot = "GAMESTP", tid = 1031, sid = 21889, otFemale = false, pid = 0x36d46750, shiny = true, moves = { "Zap Cannon", "Aura Sphere", "Extreme Speed", "Weather Ball" }, item = "Micle Berry", ball = "Cherish Ball", friendship = 35, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 30001, origin = 7, transfer = true } },
  { id = "entei_gamestop_bw", kind = "mon", name = "Shiny Entei", event = "GameStop shiny beasts (US, 2010), Poke Transfer", games = { "black", "white" }, price = 1600, about = "LOSTLORN FOREST -- ZOROARK", src = "Project Pokemon EventsGallery: 060 DPPtHGSS - GameStop Entei (ENG).wc4",
    mon = { species = 244, level = 30, ot = "GAMESTP", tid = 1171, sid = 52447, otFemale = false, pid = 0x7d5bb510, shiny = true, moves = { "Flare Blitz", "Howl", "Extreme Speed", "Crush Claw" }, item = "Custap Berry", ball = "Cherish Ball", friendship = 35, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 30001, origin = 7, transfer = true } },
  { id = "suicune_gamestop_bw", kind = "mon", name = "Shiny Suicune", event = "GameStop shiny beasts (US, 2010), Poke Transfer", games = { "black", "white" }, price = 1600, about = "LOSTLORN FOREST -- ZOROARK", src = "Project Pokemon EventsGallery: 061 DPPtHGSS - GameStop Suicune (ENG).wc4",
    mon = { species = 245, level = 30, ot = "GAMESTP", tid = 1311, sid = 64410, otFemale = false, pid = 0x42fcbc7e, shiny = true, moves = { "Sheer Cold", "Air Slash", "Extreme Speed", "Aqua Ring" }, item = "Rowap Berry", ball = "Cherish Ball", friendship = 35, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 30001, origin = 7, transfer = true } },
  { id = "celebi_gamestop_bw", kind = "mon", name = "Celebi", event = "GameStop Celebi (US, 2010), Poke Transfer", games = { "black", "white" }, price = 1600, about = "CASTELIA CITY -- ZORUA", src = "Project Pokemon EventsGallery: 062 DPPtHGSS - GameStop Celebi (ENG).wc4",
    mon = { species = 251, level = 50, ot = "GAMESTP", tid = 2271, sid = 10415, otFemale = true, moves = { "Leaf Storm", "Recover", "Nasty Plot", "Healing Wish" }, item = "Jaboca Berry", ball = "Cherish Ball", friendship = 100, fateful = true, ribbons4 = { 0x4000000, 0x0, 0x0 }, metLocation = 30001, origin = 7, transfer = true } },
}

-- what a Pokemon event OPENS, where the ROM's own scripts test for it
Ev.OPENS = {
  celebi_gamestop = { heartgold = "ILEX FOREST -- CELEBI's journey through time", soulsilver = "ILEX FOREST -- CELEBI's journey through time" },
  arceus_tru = { heartgold = "SINJOH RUINS -- DIALGA, PALKIA or GIRATINA", soulsilver = "SINJOH RUINS -- DIALGA, PALKIA or GIRATINA" },
  shaymin_tru = { heartgold = "GOLDENROD -- the GRACIDEA", soulsilver = "GOLDENROD -- the GRACIDEA" },
  pikachu_surf = { yellow = "ROUTE 19 -- PIKACHU's Beach (a Pikachu that knows SURF)" },
}
-- the HGSS Hall-of-Fame gift a Pokemon event stands for (so the port's own
-- one-per-induction offer does not hand the same event over twice)
Ev.HGSS_BASE = { celebi_gamestop = "celebi", arceus_tru = "arceus", shaymin_tru = "shaymin" }

-- --------------------------------------------------------------- helpers

local function norm(s)
  s = tostring(s or ""):gsub("\195\169", "E"):gsub("\195\137", "E"):gsub("\226\128\153", "'")
  return (s:upper():gsub("[^%w]", ""))
end
Ev.norm = norm

local function genOf(version)
  local ok, V = pcall(require, "src.core.GameVersion")
  return ok and V.generation and tonumber(V.generation(version)) or 2
end
Ev.genOf = genOf

local function has(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

local byId = {}
for _, ev in ipairs(Ev.EVENTS) do byId[ev.id] = ev end
function Ev.get(id) return byId[id] end

-- the shelf for one game, in list order (key events first)
function Ev.forGame(version)
  local out = {}
  for _, ev in ipairs(Ev.EVENTS) do
    if has(ev.games, version) then out[#out + 1] = ev end
  end
  return out
end

-- every game any event is for, in list order of first appearance
function Ev.games()
  local out, seen = {}, {}
  for _, ev in ipairs(Ev.EVENTS) do
    for _, v in ipairs(ev.games) do
      if not seen[v] then seen[v] = true; out[#out + 1] = v end
    end
  end
  return out
end

-- what an event opens in THIS game (an event Pokemon only opens something
-- where the ROM tests for it)
function Ev.about(ev, version)
  local o = Ev.OPENS[ev.id]
  return (o and o[version]) or ev.about
end

local function flagKey(n) return ("FLAG_G3_%04X"):format(n) end
Ev.flagKey = flagKey

local function invHas(save, key)
  local inv = type(save) == "table" and save.inventory
  if type(inv) ~= "table" or key == nil then return false end
  if (tonumber(inv[key]) or 0) > 0 then return true end
  if type(key) == "number" then
    return (tonumber(inv[("ITEM_%03d"):format(key)]) or 0) > 0
  end
  return false
end

local function state(save)
  save.walkerEvents = save.walkerEvents or {}
  local s = save.walkerEvents
  s.claimed = s.claimed or {}
  s.pending = s.pending or {}
  s.delivered = s.delivered or {}
  return s
end
Ev.state = state

-- Why this save cannot take this event now, or nil when it can. Reads the
-- save table only (the launcher has no dataset), so every test is on keys the
-- save itself carries.
function Ev.blocked(ev, save, version)
  if not ev then return "no such event" end
  if not has(ev.games, version) then return "not for this game" end
  if type(save) ~= "table" then return "no save" end
  local s = save.walkerEvents
  if s and s.claimed and s.claimed[ev.id] then return "claimed" end
  local flags = save.flags or {}
  if ev.handler == "gsball" then
    -- EVENT_GOT_GS_BALL_FROM_GOLDENROD_POKEMON_CENTER (832), or already sent
    if flags.EVENT_G2_0832 or tonumber(save.gen2MobileEvent) == Ev.GS_BALL_EVENT then return "owned" end
    if invHas(save, "ITEM_115") then return "owned" end
  elseif ev.handler == "tidal" then
    if invHas(save, ev.item) then return "owned" end
    if ev.received and flags[flagKey(ev.received)] then return "owned" end
  elseif ev.handler == "frlg" then
    if invHas(save, ev.item) or flags[flagKey(ev.flags[1])] then return "owned" end
    if ev.needs == "natdex" and save.nationalDex ~= true then return "needs the National Pokedex" end
  elseif ev.handler == "gen4" then
    local mg = save.gen4MysteryGift
    if mg and mg.taken and mg.taken[ev.base] then return "owned" end
    if ev.gift.item and invHas(save, ev.gift.item) then return "owned" end
  elseif ev.handler == "gen5" then
    local mg = save.gen5MysteryGift
    if (mg and mg.taken and mg.taken.liberty_pass) or invHas(save, ev.itemId) then return "owned" end
  elseif ev.kind == "mon" then
    local base = Ev.HGSS_BASE[ev.id]
    local mg = save.gen4MysteryGift
    if base and (version == "heartgold" or version == "soulsilver") and mg and mg.taken and mg.taken[base] then
      return "owned"
    end
    -- FireRed's trades refuse anything past #151 until the National Pokedex
    if version == "firered" and (ev.mon.species or 0) > 151 and save.nationalDex ~= true then
      return "needs the National Pokedex"
    end
  end
  return nil
end

-- -------------------------------------------------- the launcher's half

local function readSave(version, slotId)
  local SaveData = require("src.core.SaveData")
  -- refused while a game in another window has the slot open (see
  -- WalkerLink's readSave)
  local okO, open, age = pcall(SaveData.slotOpenElsewhere, version, slotId)
  if okO and open then
    return nil, ("that save is open in a running game -- save and quit it first"
      .. " (if no game is running, try again in %d min)")
      :format(math.max(1, math.ceil((SaveData.OPEN_FRESH - (age or 0)) / 60)))
  end
  local path = SaveData.slotDiskPath(version, slotId)
  local f = path and io.open(path, "rb")
  if not f then return nil, "no save in that slot" end
  local bytes = f:read("*a"); f:close()
  local ok, t = pcall(require("src.core.SaveSerializer").decode, bytes)
  if not (ok and type(t) == "table") then return nil, "the save does not read" end
  return t, bytes
end
Ev.readSave = readSave

local function backup(version, slotId, bytes)
  if not (bytes and love and love.filesystem) then return end
  local dir = ("pokewalker_backups/%s"):format(version)
  pcall(love.filesystem.createDirectory, dir)
  pcall(love.filesystem.write, ("%s/%s_%s_event.lua"):format(dir, slotId, os.date("%Y%m%d_%H%M%S")), bytes)
end

-- the status of every event for one save: { [id] = reason or nil }
function Ev.statusFor(version, slotId)
  local save = readSave(version, slotId)
  local out = {}
  -- (not `save and blocked(...) or "no save"`: an event that is NOT blocked
  -- answers nil, and that idiom turned every buyable one into "no save")
  for _, ev in ipairs(Ev.forGame(version)) do
    if save then out[ev.id] = Ev.blocked(ev, save, version) else out[ev.id] = "no save" end
  end
  return out
end

-- Queue one event into a save on disk. Returns true, or false and why.
function Ev.queue(version, slotId, ev)
  local save, bytes = readSave(version, slotId)
  if not save then return false, bytes end
  local why = Ev.blocked(ev, save, version)
  if why then return false, why end
  backup(version, slotId, bytes)
  local s = state(save)
  s.claimed[ev.id] = os.time()
  s.pending[#s.pending + 1] = { id = ev.id, t = os.time() }
  return require("src.core.SaveData").writeSlot(version, slotId, save)
end

-- ------------------------------------------------------ the game's half

local function findKey(tbl, name, numeric)
  local want = norm(name)
  if want == "" then return nil end
  local hit
  for k, def in pairs(tbl or {}) do
    if type(def) == "table" and norm(def.name) == want then
      if numeric == nil or (type(k) == "number") == numeric then return k end
      hit = hit or k
    end
  end
  return hit
end

local function speciesKey(data, dex)
  local p = data.pokemon or {}
  for k, def in pairs(p) do
    if type(def) == "table" and tonumber(def.dex) == dex then return k end
  end
  if p[dex] then return dex end
  for _, k in ipairs({ ("SPECIES_%03d"):format(dex), ("SPECIES_%d"):format(dex) }) do
    if p[k] then return k end
  end
  return nil
end
Ev.speciesKey = speciesKey

local function itemKey(data, name, gen)
  -- a Gen IV cache in another language: the English name's cartridge id
  return require("src.pokemon.Gen4EnglishRef").itemKey(data, name)
    or findKey(data.items, name, gen >= 4 or nil)
end

-- names a dataset spells the older way (Gen 3-5 cartridges say "Faint
-- Attack", "ExtremeSpeed", "ThunderShock" ...; norm() already drops spaces)
local MOVE_ALIAS = { ["Feint Attack"] = "Faint Attack", ["Hi Jump Kick"] = "High Jump Kick",
                     ["Smelling Salts"] = "SmellingSalt" }

local function moveList(data, names, gen)
  local out = {}
  for _, n in ipairs(names or {}) do
    local k = require("src.pokemon.Gen4EnglishRef").moveKey(data, n)
      or findKey(data.moves, n, gen >= 4 or nil)
      or (MOVE_ALIAS[n] and findKey(data.moves, MOVE_ALIAS[n], gen >= 4 or nil))
    local def = k and data.moves[k]
    if def then out[#out + 1] = { id = k, pp = def.pp or 0 } end
  end
  return out
end

local function definition(data, mon)
  local ok, Forms = pcall(require, "src.pokemon.Gen4Forms")
  local def = ok and Forms.definition and Forms.definition(data, mon)
  return def or (data.pokemon or {})[mon.species]
end

local function restat(data, mon)
  local Stats = require("src.pokemon.Stats")
  local def = definition(data, mon)
  if not def then return end
  if Stats.isGen3(def) then
    mon.stats = Stats.calc(def, mon.level or 1, mon.ivs, nil, mon.evs, mon.nature)
  else
    mon.stats = Stats.calc(def, mon.level or 1, mon.dvs, mon.statExp)
  end
  mon.hp = mon.stats.hp
end

local function makeEgg(data, mon)
  mon.isEgg = true
  local def = definition(data, mon)
  local cycles = def and tonumber(def.eggCycles) or 20
  mon.eggCycles = cycles
  mon.eggSteps = cycles * 256
  local ok, steps = pcall(function() return require("src.pokemon.DayCare").eggSteps(data, mon.species) end)
  if ok and tonumber(steps) then mon.eggSteps = steps end
end

local function u32(v) return math.floor(tonumber(v) or 0) % 4294967296 end
local function bytes32(v)
  v = u32(v)
  local b = {}
  for i = 1, 4 do b[i] = string.char(v % 256); v = math.floor(v / 256) end
  return table.concat(b)
end

-- the PGF ribbon byte pair -> the Gen 4 / 5 record's two ribbon words
-- (PK5 0x24: Event bit 19, Birthday 22, Special 23, Souvenir 24, Wishing 25,
-- Classic 26, Premier 27; 0x3C: Country 28, National 29, Earth 30, World 31)
local PGF_RIBBONS = {
  [0] = { 2, 28 }, { 2, 29 }, { 2, 30 }, { 2, 31 }, { 1, 26 }, { 1, 27 },
  { 1, 19 }, { 1, 22 }, { 1, 23 }, { 1, 24 }, { 1, 25 },
}
function Ev.pgfRibbonWords(bits)
  local w = { 0, 0, 0 }
  bits = math.floor(tonumber(bits) or 0)
  for b = 0, 10 do
    if math.floor(bits / 2 ^ b) % 2 == 1 then
      local r = PGF_RIBBONS[b]
      w[r[1]] = w[r[1]] + 2 ^ r[2]
    end
  end
  return w
end

-- a 136-byte stored record carrying only what the engine does not model --
-- the ribbons and the origin game -- for NdsSave.encodeMon to build on (its
-- species field is left 0, so the export writes the names itself)
function Ev.ndsRaw(words, origin)
  words = words or { 0, 0, 0 }
  local b = {}
  for i = 1, 136 do b[i] = "\0" end
  local function put(off, s) for i = 1, #s do b[off + i] = s:sub(i, i) end end
  put(0x24, bytes32(words[1]))
  put(0x3C, bytes32(words[2]))
  put(0x60, bytes32(words[3]))
  if origin then b[0x5F + 1] = string.char(origin % 256) end
  return table.concat(b)
end

-- Build an event Pokemon in the running game's shape. Returns the mon, or nil
-- and why.
function Ev.buildMon(data, save, ev, version)
  local m = ev.mon
  local gen = genOf(version)
  local key = speciesKey(data, m.species)
  if not key then return nil, "this game has no #" .. tostring(m.species) end
  local Pokemon = require("src.pokemon.Pokemon")
  local Stats = require("src.pokemon.Stats")
  local ok, mon = pcall(Pokemon.new, data, key, m.level or 5)
  if not (ok and type(mon) == "table") then return nil, tostring(mon) end
  mon.shiny = nil                       -- the port's own shiny dial stays out of a distribution
  local moves = moveList(data, m.moves, gen)
  if #moves > 0 then mon.moves = moves end
  if m.item then mon.item = itemKey(data, m.item, gen) end
  local order = data.constants and data.constants.natureOrder
  local player = save.player or {}
  if gen <= 2 then
    if m.dvs then
      local w = m.dvs
      local d = { attack = math.floor(w / 4096) % 16, defense = math.floor(w / 256) % 16,
                  speed = math.floor(w / 16) % 16, special = w % 16 }
      d.hp = (d.attack % 2) * 8 + (d.defense % 2) * 4 + (d.speed % 2) * 2 + (d.special % 2)
      mon.dvs = d
    else
      mon.dvs = Stats.randomDVs()
      for _ = 1, 8 do if not Stats.isShiny(mon.dvs) then break end mon.dvs = Stats.randomDVs() end
    end
    if gen == 2 and m.friendship then mon.happiness = m.friendship end
  elseif gen == 3 then
    mon.personality = u32(m.pid or mon.personality)
    local ivs = {}
    for i, k in ipairs(Stats.ORDER_GEN3) do ivs[k] = (m.ivs or {})[i] or (mon.ivs or {})[k] or 0 end
    mon.ivs = ivs
    if order then mon.nature = order[(mon.personality % 25) + 1] or mon.nature end
    local def = definition(data, mon)
    local two = def and type(def.abilities) == "table" and def.abilities[2]
    mon.abilitySlot = (two and m.abilityBit == 1) and 2 or 1
    mon.altAbility = (two and m.abilityBit == 1) or nil
    if m.ball then mon.ball = itemKey(data, m.ball, gen) end
    if m.lang then mon.gen3Language = m.lang end
    if m.metGame then mon.gen3MetGame = m.metGame end
    mon.metLevel = m.metLevel
    mon.metLocation = 255                -- the "fateful encounter" place every event carries
    if m.friendship then mon.happiness = m.friendship end
    if m.ribbons3 then
      mon.gen3Ribbons = m.ribbons3
      local names = { [23] = "country", [24] = "national", [25] = "earth", [26] = "world" }
      for bit, name in pairs(names) do
        if math.floor(m.ribbons3 / 2 ^ bit) % 2 == 1 then mon.ribbons = mon.ribbons or {}; mon.ribbons[name] = true end
      end
    end
  else
    mon.personality = u32(m.pid or mon.personality or math.random(1, 4294967295))
    if m.ivs5 then
      mon.ivs = mon.ivs or {}
      for i, k in ipairs(Stats.ORDER_GEN3) do if m.ivs5[i] then mon.ivs[k] = m.ivs5[i] end end
    end
    if m.ball then mon.ball = itemKey(data, m.ball, gen) end
    if m.friendship then mon.happiness = m.friendship end
    mon.metLevel = m.metLevel or m.level
    mon.metLocation = m.metLocation
    mon.eggLocation = m.eggLocation
    local t = os.date("*t")
    mon.metDate = { year = t.year, month = t.month, day = t.day }
    if m.gender then mon.gender = m.gender end
    -- the record's ribbons and origin, which the engine's fields do not hold
    local words = m.ribbons4 or (m.ribbons5 and Ev.pgfRibbonWords(m.ribbons5)) or nil
    local origin = m.origin or Ev.ORIGIN[version]
    mon.ndsRaw = Ev.ndsRaw(words, origin)
    mon.ndsGame = origin
  end
  -- whose it is: the event's trainer, or (an egg, a trainer gift) the player
  if m.ot then
    mon.ot = m.ot
    if gen >= 3 then
      mon.otId = (m.tid or 0) + (m.sid or 0) * 65536
      mon.secretId = m.sid or 0
    else
      mon.otId = m.tid
    end
    if gen == 3 then
      mon.gen3OtName = m.ot
      mon.gen3OtFemale = m.otFemale or nil
    elseif gen >= 4 then
      mon.otGender = m.otFemale and "girl" or "boy"
    end
  else
    mon.ot = player.name
    if gen >= 3 then
      mon.otId = (tonumber(player.id) or 0) % 65536 + (tonumber(player.secretId) or 0) * 65536
      mon.secretId = tonumber(player.secretId) or 0
    else
      mon.otId = player.id
    end
  end
  -- shininess, by the generation's own rule now that the trainer is known
  if gen >= 4 then
    local full = tonumber(mon.otId) or 0
    if m.shiny and not Stats.isShinyGen3(mon.personality, full) then
      mon.personality = Stats.shinyPersonality(mon.personality, full)
    elseif not m.shiny and not m.pid and Stats.isShinyGen3(mon.personality, full) then
      mon.personality = (mon.personality + 2 ^ 31) % 4294967296   -- moves the xor by 0x8000
    end
    if gen == 4 and order then mon.nature = order[(mon.personality % 25) + 1] or mon.nature end
    if gen == 5 and m.nature and order then mon.nature = order[m.nature + 1] or mon.nature; mon.ndsNature = m.nature end
    local def = definition(data, mon)
    local two = def and type(def.abilities) == "table" and def.abilities[2]
    if gen == 4 then
      mon.abilitySlot = two and (mon.personality % 2) + 1 or 1
    elseif m.abilityType and m.abilityType <= 2 then
      mon.abilitySlot = (m.abilityType == 1 and two) and 2 or (m.abilityType == 2 and 3) or 1
    end
    mon.shiny = Stats.isShinyGen3(mon.personality, full) or nil
  elseif gen == 3 then
    mon.shiny = Stats.isShinyGen3(mon.personality, tonumber(mon.otId) or 0) or nil
  else
    mon.shiny = Stats.isShiny(mon.dvs) or nil
  end
  if m.fateful then mon.fatefulEncounter = true; mon.fateful = true end
  if m.egg then makeEgg(data, mon) end
  restat(data, mon)
  mon.walkerEvent = ev.id
  return mon
end

-- the party when there is room (the way the cartridges handed a gift over),
-- else the PC
local function place(save, mon)
  save.party = save.party or {}
  if #save.party < 6 then table.insert(save.party, mon) return "party" end
  local Boxes = require("src.pokemon.Boxes")
  local ok, b = pcall(Boxes.deposit, save, mon)
  if ok and b then return "pc" end
  return nil
end

local function bagAdd(save, key, data)
  if key == nil then return false end
  save.inventory = save.inventory or {}
  local okB, Bag = pcall(require, "src.inventory.Bag")
  if okB and Bag and Bag.add then pcall(Bag.add, save, key, 1, data) end
  -- a key item has to exist even when a pocket refused it: the scripts
  -- check the bag
  if (tonumber(save.inventory[key]) or 0) < 1 then save.inventory[key] = 1 end
  return true
end

-- the Gen 4 deliveryman's gift for one walker event (Gen4MysteryGift.byKey
-- falls through to this for a "walker:" key)
function Ev.gen4Gift(key)
  local id = type(key) == "string" and key:match("^walker:(.+)$")
  local ev = id and byId[id]
  if not ev then return nil end
  if ev.kind == "key" then
    local g = { key = key, walker = ev.id, about = ev.about }
    for k, v in pairs(ev.gift) do g[k] = v end
    return g
  end
  local okV, V = pcall(require, "src.core.GameVersion")
  local version = okV and V.get() or "platinum"
  local hgss = version == "heartgold" or version == "soulsilver"
  return {
    key = key, walker = ev.id, type = 1, species = ev.mon.species, level = ev.mon.level,
    fateful = true, text = 7, label = ev.name, about = Ev.about(ev, version),
    -- after Pokemon.new: the distribution's own trainer, moves, item, ball,
    -- ribbons and personality (Gen4MysteryGift.give calls this)
    decorate = function(data, save, mon)
      local built = Ev.buildMon(data, save, ev, version)
      if not built then return end
      for k in pairs(mon) do mon[k] = nil end
      for k, v in pairs(built) do mon[k] = v end
    end,
    hgss = hgss,
  }
end

local HANDLERS = {}

HANDLERS.gsball = function(save)
  save.gen2MobileEvent = Ev.GS_BALL_EVENT
  return true
end

HANDLERS.tidal = function(save, data, ev)
  local MG = require("src.ui.Gen3MysteryGift")
  local game = { save = save, data = data }
  for _, row in ipairs(MG.events(game)) do
    if row.item == ev.item then
      MG.unlock(game, row)
      save.flags = save.flags or {}
      if ev.received then save.flags[flagKey(ev.received)] = true end
      local s = state(save)
      s.gen3Rows = s.gen3Rows or {}
      s.gen3Rows[ev.item] = true
      return true
    end
  end
  return false, "no SS Tidal row for " .. tostring(ev.item)
end

HANDLERS.frlg = function(save, data, ev)
  save.flags = save.flags or {}
  for _, f in ipairs(ev.flags) do save.flags[flagKey(f)] = true end
  return bagAdd(save, (data.items or {})[ev.item] and ev.item or findKey(data.items, ev.name), data)
end

-- the cartridge's own gift when the deliveryman already knows it (the Member
-- Card, Oak's Letter, the Azure Flute, the Manaphy Egg, the Enigma Stone: his
-- handlers set the distribution magic), else this module's (the Secret Key)
HANDLERS.gen4 = function(save, data, ev)
  local MG = require("src.pokemon.Gen4MysteryGift")
  local s = MG.state(save)
  s.taken[ev.base] = "walker"
  s.waiting[#s.waiting + 1] = MG.byKey(ev.base) and ev.base or ("walker:" .. ev.id)
  return true
end

HANDLERS.gen5 = function(save, data, ev)
  local key = (data.items or {})[ev.itemId] and ev.itemId or findKey(data.items, ev.itemName, true)
  bagAdd(save, key, data)
  local MG = require("src.pokemon.Gen5MysteryGift")
  MG.state(save).taken.liberty_pass = "walker"
  return true
end

HANDLERS.mon = function(save, data, ev, version)
  if genOf(version) == 4 then
    -- a Wonder Card's Pokemon waits with the deliveryman at any Poke Mart
    local MG = require("src.pokemon.Gen4MysteryGift")
    local s = MG.state(save)
    local base = Ev.HGSS_BASE[ev.id]
    if base and (version == "heartgold" or version == "soulsilver") then s.taken[base] = "walker" end
    s.waiting[#s.waiting + 1] = "walker:" .. ev.id
    return true, "deliveryman"
  end
  local mon, why = Ev.buildMon(data, save, ev, version)
  if not mon then return false, why end
  local where = place(save, mon)
  if not where then return false, "the party and the PC are full" end
  return true, where
end

-- Deliver every pending event into a loaded save. Returns the number handed
-- over (nil when there was nothing).
function Ev.apply(save, data)
  local s = type(save) == "table" and save.walkerEvents
  if not (type(s) == "table" and type(s.pending) == "table" and #s.pending > 0) then return nil end
  data = data or require("src.core.Data")
  state(save)
  local version = require("src.core.GameVersion").get()
  local n = 0
  for i = #s.pending, 1, -1 do
    local p = s.pending[i]
    local ev = byId[p.id]
    if not ev or not has(ev.games, version) then
      table.remove(s.pending, i)
    else
      local fn = HANDLERS[ev.kind == "mon" and "mon" or ev.handler]
      local ok, res, where = pcall(fn, save, data, ev, version)
      if ok and res then
        table.remove(s.pending, i)
        s.delivered[ev.id] = where or true
        n = n + 1
      else
        -- left pending (a full PC, say): tried again on the next load
        pcall(function()
          require("src.core.Logger").warn("walker event %s not delivered: %s", ev.id, tostring(ok and where or res))
        end)
      end
    end
  end
  if n > 0 then
    pcall(function() require("src.core.Logger").info("pokewalker: %d event%s delivered", n, n == 1 and "" or "s") end)
  end
  return n > 0 and n or nil
end

return Ev
