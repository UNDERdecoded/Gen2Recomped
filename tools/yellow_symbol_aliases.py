"""Red→Yellow symbol / label remaps for make_yellow_manifest.py.

Names present in both pokered and pokeyellow.sym are remapped by address
only.  This table covers Red symbol names that do not exist in Yellow:
either an equivalent Yellow label, or None to drop the symbol (and strip
text.labels / metadata references).
"""

from __future__ import annotations

# Red symbol name -> Yellow symbol name, or None to omit.
SYMBOL_ALIASES: dict[str, str | None] = {
    # Map header
    "CeruleanTradeHouse_h": "CeruleanMelaniesHouse_h",

    # Cerulean City Slowbro -> Electrode
    "_CeruleanCityCooltrainerF1SlowbroPunchText":
        "_CeruleanCityCooltrainerF1ElectrodePunchText",
    "_CeruleanCityCooltrainerF1SlowbroUseSonicboomText":
        "_CeruleanCityCooltrainerF1ElectrodeUseSonicboomText",
    "_CeruleanCityCooltrainerF1SlowbroWithdrawText":
        "_CeruleanCityCooltrainerF1ElectrodeWithdrawText",
    "_CeruleanCitySlowbroIgnoredOrdersText":
        "_CeruleanCityElectrodeIgnoredOrdersText",
    "_CeruleanCitySlowbroIsLoafingAroundText":
        "_CeruleanCityElectrodeIsLoafingAroundText",
    "_CeruleanCitySlowbroTookASnoozeText":
        "_CeruleanCityElectrodeTookASnoozeText",
    "_CeruleanCitySlowbroTurnedAwayText":
        "_CeruleanCityElectrodeTurnedAwayText",

    # Cerulean Trade House granny -> Melanie house
    "_CeruleanTradeHouseGrannyText": "MelanieText1",

    # Game Corner clerk / NPC renames
    "_GameCornerClerk1CantAffordTheCoinsText":
        "_GameCornerClerkCantAffordTheCoinsText",
    "_GameCornerClerk1CoinCaseIsFullText":
        "_GameCornerClerkCoinCaseIsFullText",
    "_GameCornerClerk1DoYouNeedSomeGameCoinsText":
        "_GameCornerClerkDoYouNeedSomeGameCoinsText",
    "_GameCornerClerk1DontHaveCoinCaseText":
        "_GameCornerClerkDontHaveCoinCaseText",
    "_GameCornerClerk1PleaseComePlaySometimeText":
        "_GameCornerClerkPleaseComePlaySometimeText",
    "_GameCornerClerk1ThanksHereAre50CoinsText":
        "_GameCornerClerkThanksHereAre50CoinsText",
    "_GameCornerClerk2INeedMoreCoinsText":
        "_GameCornerMiddleAgedMan2INeedMoreCoinsText",
    "_GameCornerClerk2Received20CoinsText":
        "_GameCornerMiddleAgedMan2Received20CoinsText",
    "_GameCornerClerk2WantSomeCoinsText":
        "_GameCornerMiddleAgedMan2WantSomeCoinsText",
    "_GameCornerClerk2YouHaveLotsOfCoinsText":
        "_GameCornerMiddleAgedMan2YouHaveLotsOfCoinsText",
    "_GameCornerFishingGuruDontNeedMyCoinsText":
        "_GameCornerFishingGuru1DontNeedMyCoinsText",
    "_GameCornerFishingGuruReceived10CoinsText":
        "_GameCornerFishingGuru1Received10CoinsText",
    "_GameCornerFishingGuruWantToPlayText":
        "_GameCornerFishingGuru1WantToPlayText",
    "_GameCornerFishingGuruWinsComeAndGoText":
        "_GameCornerFishingGuru1WinsComeAndGoText",
    "_GameCornerGentlemanCloselyWatchTheReelsText":
        "_GameCornerFishingGuru2CloselyWatchTheReelsText",
    "_GameCornerGentlemanReceived20CoinsText":
        "_GameCornerFishingGuru2Received20CoinsText",
    "_GameCornerGentlemanThrowingMeOffText":
        "_GameCornerFishingGuru2ThrowingMeOffText",
    "_GameCornerGentlemanYouGotYourOwnCoinsText":
        "_GameCornerFishingGuru2YouGotYourOwnCoinsText",

    # Link / cable-club prompts (Yellow folds these into Colosseum texts)
    "_LinkCanceledText": "_ColosseumCanceledText",
    "_PleaseWaitText": "_ColosseumPleaseWaitText",
    "_WhereWouldYouLikeText": "_ColosseumWhereToText",

    # Mt. Moon Rocket1 -> Jessie/James
    "_MtMoonB2FRocket1AfterBattleText": "_MtMoonJessieJamesText4",
    "_MtMoonB2FRocket1BattleText": "_MtMoonJessieJamesText1",
    "_MtMoonB2FRocket1EndBattleText": "_MtMoonJessieJamesText3",

    # Oak's Lab starter-choice texts -> Yellow Pikachu/Eevee flow
    "_OaksLabLastMonText": None,
    "_OaksLabMonEnergeticText": None,
    "_OaksLabOak1RaiseYourYoungPokemonText":
        "_OaksLabOak1YouShouldTalkToIt",
    "_OaksLabOak1WhichPokemonDoYouWantText":
        "_OaksLabOak1GoAheadItsYours",
    "_OaksLabReceivedMonText": "_OaksLabReceivedText",
    "_OaksLabRivalGoAheadAndChooseText": None,
    "_OaksLabRivalIllTakeThisOneText": "_OaksLabRivalTakesText1",
    "_OaksLabRivalReceivedMonText": None,
    "_OaksLabRivalWhatDidYouCallMeForText":
        "_OaksLabRivalWhatAboutMeText",
    "_OaksLabThoseArePokeBallsText": "_OaksLabThatsAPokeball",
    "_OaksLabYouWantBulbasaurText": None,
    "_OaksLabYouWantCharmanderText": None,
    "_OaksLabYouWantSquirtleText": None,

    # Pallet Town Oak
    "_PalletTownOakItsUnsafeText": "_PalletTownOakHeyWaitDontGoOutText",

    # Fan Club: Pikachu fan -> Clefairy fan; signs removed in Yellow
    "_PokemonFanClubPikachuFanBetterText":
        "_PokemonFanClubClefairyFanBetterText",
    "_PokemonFanClubPikachuFanNormalText":
        "_PokemonFanClubClefairyFanNormalText",
    "_PokemonFanClubPikachuText": "_PokemonFanClubClefairyText",
    "_PokemonFanClubSign1Text": None,
    "_PokemonFanClubSign2Text": None,

    # Pokemon Tower 7F Rockets -> Jessie/James
    "_PokemonTower7FRocket1AfterBattleText":
        "_PokemonTowerJessieJamesText4",
    "_PokemonTower7FRocket1BattleText":
        "_PokemonTowerJessieJamesText1",
    "_PokemonTower7FRocket1EndBattleText":
        "_PokemonTowerJessieJamesText3",
    "_PokemonTower7FRocket2AfterBattleText":
        "_PokemonTowerJessieJamesText4",
    "_PokemonTower7FRocket2BattleText":
        "_PokemonTowerJessieJamesText2",
    "_PokemonTower7FRocket2EndBattleText":
        "_PokemonTowerJessieJamesText3",
    "_PokemonTower7FRocket3AfterBattleText":
        "_PokemonTowerJessieJamesText4",
    "_PokemonTower7FRocket3BattleText":
        "_PokemonTowerJessieJamesText1",
    "_PokemonTower7FRocket3EndBattleText":
        "_PokemonTowerJessieJamesText3",

    # Rocket Hideout B4F: Rocket1/2 -> Jessie/James; Rocket3 -> remaining Rocket
    "_RocketHideoutB4FRocket1AfterBattleText":
        "_RocketHideoutJessieJamesText4",
    "_RocketHideoutB4FRocket1BattleText":
        "_RocketHideoutJessieJamesText1",
    "_RocketHideoutB4FRocket1EndBattleText":
        "_RocketHideoutJessieJamesText3",
    "_RocketHideoutB4FRocket2AfterBattleText":
        "_RocketHideoutJessieJamesText4",
    "_RocketHideoutB4FRocket2BattleText":
        "_RocketHideoutJessieJamesText2",
    "_RocketHideoutB4FRocket2EndBattleText":
        "_RocketHideoutJessieJamesText3",
    "_RocketHideoutB4FRocket3AfterBattleText":
        "_RocketHideoutB4FRocketAfterBattleText",
    "_RocketHideoutB4FRocket3BattleText":
        "_RocketHideoutB4FRocketBattleText",
    "_RocketHideoutB4FRocket3EndBattleText":
        "_RocketHideoutB4FRocketEndBattleText",

    # Route 6 shared after-battle -> M1-specific (F1 updated in manifest)
    "_Route6CooltrainerAfterBattleText":
        "_Route6CooltrainerM1AfterBattleText",

    # Route 9 CooltrainerM1 -> AJ
    "_Route9CooltrainerM1AfterBattleText": "_Route9AJAfterBattleText",
    "_Route9CooltrainerM1BattleText": "_Route9AJBattleText",
    "_Route9CooltrainerM1EndBattleText": "_Route9AJEndBattleText",

    # Silph Co. unreferenced Porygon text
    "_SilphCo10FPorygonText": None,

    # Silph Co. 11F Rocket1 -> Jessie/James
    "_SilphCo11FRocket1AfterBattleText": "_SilphCoJessieJamesText4",
    "_SilphCo11FRocket1BattleText": "_SilphCoJessieJamesText1",
    "_SilphCo11FRocket1EndBattleText": "_SilphCoJessieJamesText3",

    # Viridian City old man post-training lines
    "_ViridianCityOldManKnowHowToCatchPokemonText":
        "_ViridianCityOldManHadMyCoffeeNowText",
    "_ViridianCityOldManTimeIsMoneyText":
        "_ViridianCityOldManLosingMyTouchText",

    # Viridian Forest Youngster5 is a trainer in Yellow (no talk far-text)
    "_ViridianForestYoungster5Text": None,

    # Celadon Mansion granny (Yellow uses happiness-gated Text2..)
    "_CeladonMansion1FGrannyText": "_CeladonMansion1Text2",
}

# Red FightIntro Gengar/Nidorino 2bpp labels — Yellow uses a different intro.
# Omitted from symbols; RomExtractor must skip (see field.intro paths).
OMIT_INTRO_SYMBOLS = (
    "FightIntroBackMon",
    "FightIntroFrontMon",
    "FightIntroFrontMon2",
    "FightIntroFrontMon3",
)

# Map-constant / label renames applied throughout the manifest.
MAP_CONST_RENAMES = {
    "CERULEAN_TRADE_HOUSE": "CERULEAN_MELANIES_HOUSE",
}
MAP_LABEL_RENAMES = {
    "CeruleanTradeHouse": "CeruleanMelaniesHouse",
}

# Game Corner object / text-pointer id renames (Yellow single clerk + gurus).
GAME_CORNER_ID_RENAMES = {
    "TEXT_GAMECORNER_CLERK1": "TEXT_GAMECORNER_CLERK",
    "TEXT_GAMECORNER_CLERK2": "TEXT_GAMECORNER_MIDDLE_AGED_MAN2",
    "TEXT_GAMECORNER_FISHING_GURU": "TEXT_GAMECORNER_FISHING_GURU1",
    "TEXT_GAMECORNER_GENTLEMAN": "TEXT_GAMECORNER_FISHING_GURU2",
    "GAMECORNER_CLERK1": "GAMECORNER_CLERK",
    "GAMECORNER_CLERK2": "GAMECORNER_MIDDLE_AGED_MAN2",
    "GAMECORNER_FISHING_GURU": "GAMECORNER_FISHING_GURU1",
    "GAMECORNER_GENTLEMAN": "GAMECORNER_FISHING_GURU2",
    "GameCornerClerk1Text": "GameCornerClerkText",
    "GameCornerClerk2Text": "GameCornerMiddleAgedMan2Text",
    "GameCornerFishingGuruText": "GameCornerFishingGuru1Text",
    "GameCornerGentlemanText": "GameCornerFishingGuru2Text",
}

FAN_CLUB_ID_RENAMES = {
    "TEXT_POKEMONFANCLUB_PIKACHU_FAN": "TEXT_POKEMONFANCLUB_CLEFAIRY_FAN",
    "TEXT_POKEMONFANCLUB_PIKACHU": "TEXT_POKEMONFANCLUB_CLEFAIRY",
    "POKEMONFANCLUB_PIKACHU_FAN": "POKEMONFANCLUB_CLEFAIRY_FAN",
    "POKEMONFANCLUB_PIKACHU": "POKEMONFANCLUB_CLEFAIRY",
    "PokemonFanClubPikachuFanText": "PokemonFanClubClefairyFanText",
    "PokemonFanClubPikachuText": "PokemonFanClubClefairyText",
}
