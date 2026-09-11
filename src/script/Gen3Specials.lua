-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHAT EMERALD'S SPECIALS ARE CALLED.
--
-- A Gen 3 `special` is an INDEX into gSpecials, and a retail cartridge ships
-- no symbol table, so for a long time this port could only say "special 306
-- is not implemented" -- which names the problem in a language nobody can
-- read.  Gen3Commands identified two dozen of them the hard way, by matching
-- the SHAPE of the script around each call against pokeemerald's source, and
-- its own comment warned that pret's list "cannot be indexed into safely".
--
-- IT CAN, AND HERE IS THE PROOF, which is the only reason this file exists.
--
-- The cartridge's own table has THREE PAIRS OF ENTRIES THAT POINT AT THE SAME
-- FUNCTION.  The importer's discovery pass finds them without knowing any
-- names, by comparing pointers, and reports them at indices (277, 348),
-- (409, 410) and (470, 508).  pokeemerald's data/specials.inc has exactly
-- three repeated names, and they sit at exactly those indices:
-- ShowGlassWorkshopMenu at 277 and 348, ShowMapNamePopup at 409 and 410, and
-- Script_DoRayquazaScene at 470 and 508.  Three coincidences, spread over
-- four hundred entries, would each have to be luck.
--
-- And the alignment agrees with every one of the specials Gen3Commands had
-- already named by shape -- HealPlayerParty at 0, PlayerHasBerries at 52,
-- StorePlayerCoordsInVars at 146, StartWallClock at 157, ChooseStarter at
-- 159, GetBattleOutcome at 183, GetLeadMonFriendshipScore at 233,
-- FieldShowRegionMap at 254, SpawnCameraObject at 278, GetPlayerFacingDirection
-- at 289, ShakeCamera at 312, IsSelectedMonEgg at 330 -- twelve independent
-- derivations, none of which used this list.  gen3_specials_test asserts all
-- of that rather than trusting the paragraph.
--
-- These are NAMES, not behaviour.  Nothing here implements anything: the
-- table turns "special 306 is not implemented" into "special 306
-- (ScriptCheckFreePokemonStorageSpace) is not implemented", which is the
-- difference between a number and a piece of work.  Handlers live in
-- Gen3Commands.SPECIALS, and the ones that matter are added there.
--
-- The importer counts 530 entries where pret's file has 527 names.  The last
-- three are read past the end of the table -- the same overshoot the object
-- graphics table has -- and nothing calls them: the highest index any script
-- in Hoenn asks for is 520.

local Gen3Specials = {}

-- data/specials.inc, in order.  Index 0 is the first entry, so NAMES[n + 1]
-- is the name of `special n`; use Gen3Specials.name(n) rather than indexing.
Gen3Specials.NAMES = {
  "HealPlayerParty", "SetCableClubWarp", "DoCableClubWarp", "ReturnFromLinkRoom",
  "CleanupLinkRoomState", "ExitLinkRoom", "SetPlayerSecretBase", "CheckPlayerHasSecretBase",
  "EnterSecretBase", "ClearAndLeaveSecretBase", "MoveOutOfSecretBase",
  "IsCurSecretBaseOwnedByAnotherPlayer", "GetCurSecretBaseRegistrationValidity",
  "ToggleCurSecretBaseRegistry", "ShowSecretBaseDecorationMenu", "ShowSecretBaseRegistryMenu",
  "PrepSecretBaseBattleFlags", "GetSecretBaseOwnerAndState", "InitSecretBaseDecorationSprites",
  "SetDecoration", "GetObjectEventLocalIdByFlag", "GetSecretBaseTypeInFrontOfPlayer",
  "SetSecretBaseOwnerGfxId", "PutAwayDecorationIteration", "EnterNewlyCreatedSecretBase",
  "SetBattledOwnerFromResult", "DoSecretBasePCTurnOffEffect", "RecordMixingPlayerSpotTriggered",
  "TryBattleLinkup", "TryTradeLinkup", "TryRecordMixLinkup", "ValidateMixingGameLanguage",
  "CloseLink", "ColosseumPlayerSpotTriggered", "PlayerEnteredTradeSeat",
  "Script_StartWiredTrade", "CableClubSaveGame", "TryBerryBlenderLinkup",
  "GetLinkPartnerNames", "SpawnLinkPartnerObjectEvent", "SavePlayerParty",
  "LoadPlayerParty", "ChooseHalfPartyForBattle", "Script_ShowLinkTrainerCard",
  "ObjectEventInteractionGetBerryTreeData", "ObjectEventInteractionGetBerryName",
  "ObjectEventInteractionGetBerryCountString", "Bag_ChooseBerry",
  "ObjectEventInteractionPlantBerryTree", "ObjectEventInteractionPickBerryTree",
  "ObjectEventInteractionRemoveBerryTree", "ObjectEventInteractionWaterBerryTree",
  "PlayerHasBerries", "IsEnigmaBerryValid", "GetTrainerBattleMode",
  "ShowTrainerIntroSpeech", "ShowTrainerCantBattleSpeech", "GetTrainerFlag",
  "DoTrainerApproach", "PlayTrainerEncounterMusic", "ShouldTryRematchBattle",
  "IsTrainerReadyForRematch", "BattleSetup_StartRematchBattle", "ShowPokemonStorageSystemPC",
  "HasEnoughMonsForDoubleBattle", "TurnOffTVScreen", "DoTVShow", "DoPokeNews",
  "GetRandomActiveShowIdx", "GetSelectedTVShow", "InterviewBefore",
  "InterviewAfter", "IsLeadMonNicknamedOrNotEnglish", "SetContestCategoryStringVarForInterview",
  "GetNextActiveShowIfMassOutbreak", "IsTVShowAlreadyInQueue", "CheckForPlayersHouseNews",
  "GetMomOrDadStringForTVMessage", "ResetTVShowState", "GetContestWinnerId",
  "GetContestPlayerId", "GetNpcContestantLocalId", "BufferContestWinnerTrainerName",
  "BufferContestWinnerMonName", "BufferContestTrainerAndMonNames",
  "GetContestMonConditionRanking", "SetContestTrainerGfxIds", "TryEnterContestMon",
  "GetContestantNamesAtRank", "SetLinkContestPlayerGfx", "GetContestMonCondition",
  "HasMonWonThisContestBefore", "GiveMonContestRibbon", "IsContestDebugActive",
  "GiveMonArtistRibbon", "TryContestGModeLinkup", "SaveGame", "DoWateringBerryTreeAnim",
  "ShowEasyChatScreen", "ShowEasyChatProfile", "Script_GetCurrentMauvilleMan",
  "HasBardSongBeenChanged", "SaveBardSongLyrics", "HasHipsterTaughtWord",
  "SetHipsterTaughtWord", "HipsterTryTeachWord", "PlayBardSong", "SetMauvilleOldManObjEventGfx",
  "GenerateGiddyLine", "GiddyShouldTellAnotherTale", "StorytellerGetFreeStorySlot",
  "Script_StorytellerDisplayStory", "StorytellerStoryListMenu", "StorytellerUpdateStat",
  "Script_StorytellerInitializeRandomStat", "HasStorytellerAlreadyRecorded",
  "TraderMenuGetDecoration", "GetTraderTradedFlag", "DoesPlayerHaveNoDecorations",
  "IsDecorationCategoryFull", "TraderShowDecorationMenu", "TraderDoDecorationTrade",
  "GetSeedotSizeRecordInfo", "CompareSeedotSize", "GetLotadSizeRecordInfo",
  "CompareLotadSize", "TryPutNameRaterShowOnTheAir", "BufferMonNickname",
  "IsMonOTIDNotPlayers", "BufferTrendyPhraseString", "IsTrendyPhraseBoring",
  "BufferDeepLinkPhrase", "GetDewfordHallPaintingNameIndex", "SwapRegisteredBike",
  "CalculatePlayerPartyCount", "CountPartyNonEggMons", "CountPartyAliveNonEggMons_IgnoreVar0x8004Slot",
  "ShouldReadyContestArtist", "SaveMuseumContestPainting", "DoesContestCategoryHaveMuseumPainting",
  "CountPlayerMuseumPaintings", "ShowContestPainting", "MauvilleGymSetDefaultBarriers",
  "MauvilleGymPressSwitch", "ShowFieldMessageStringVar4", "DrawWholeMapView",
  "StorePlayerCoordsInVars", "MauvilleGymDeactivatePuzzle", "PetalburgGymSlideOpenRoomDoors",
  "PetalburgGymUnlockRoomDoors", "GetPlayerTrainerIdOnesDigit", "GetPlayerBigGuyGirlString",
  "GetRivalSonDaughterString", "SetHiddenItemFlag", "CableCarWarp",
  "CableCar", "Overworld_PlaySpecialMapMusic", "StartWallClock", "Special_ViewWallClock",
  "ChooseStarter", "StartWallyTutorialBattle", "ChangePokemonNickname",
  "ChoosePartyMon", "GetFirstFreePokeblockSlot", "DoBerryBlending",
  "PlayRoulette", "IsFanClubMemberFanOfPlayer", "GetNumFansOfPlayerInTrainerFanClub",
  "BufferFanClubTrainerName", "TryLoseFansFromPlayTimeAfterLinkBattle",
  "TryLoseFansFromPlayTime", "SetPlayerGotFirstFans", "UpdateTrainerFanClubGameClear",
  "Script_TryGainNewFanFromCounter", "RockSmashWildEncounter", "GabbyAndTyGetBattleNum",
  "GabbyAndTyAfterInterview", "GabbyAndTyBeforeInterview", "DoTVShowInSearchOfTrainers",
  "IsGabbyAndTyShowOnTheAir", "GabbyAndTyGetLastQuote", "GabbyAndTyGetLastBattleTrivia",
  "GetGabbyAndTyLocalIds", "GetBattleOutcome", "GetDaycareMonNicknames",
  "GetDaycareState", "RejectEggFromDayCare", "GiveEggFromDaycare",
  "SetDaycareCompatibilityString", "GetSelectedMonNicknameAndSpecies",
  "StoreSelectedPokemonInDaycare", "ChooseSendDaycareMon", "ShowDaycareLevelMenu",
  "GetNumLevelsGainedFromDaycare", "GetDaycareCostAndPrepareString",
  "TakePokemonFromDaycare", "ScriptHatchMon", "EggHatch", "CheckDaycareMonReceivedMail",
  "ShowLinkBattleRecords", "IsEnoughForCostInVar0x8005", "SubtractMoneyFromVar0x8005",
  "TryFieldPoisonWhiteOut", "SetCB2WhiteOut", "RotatingGate_InitPuzzle",
  "RotatingGate_InitPuzzleAndGraphics", "SetSSTidalFlag", "ResetSSTidalFlag",
  "EnterSafariMode", "ExitSafariMode", "GetPokeblockFeederInFront",
  "OpenPokeblockCaseOnFeeder", "IsMirageIslandPresent", "UpdateShoalTideFlag",
  "InitBirchState", "ScriptGetPokedexInfo", "ShowPokedexRatingMessage",
  "DoPCTurnOnEffect", "DoPCTurnOffEffect", "SetDeptStoreFloor", "DoLotteryCornerComputerEffect",
  "EndLotteryCornerComputerEffect", "ChooseMonForMoveRelearner", "MoveDeleterChooseMoveToForget",
  "MoveDeleterForgetMove", "BufferMoveDeleterNicknameAndMove", "GetNumMovesSelectedMonHas",
  "TeachMoveRelearnerMove", "GetRecordedCyclingRoadResults", "Special_BeginCyclingRoadChallenge",
  "GetPlayerAvatarBike", "FinishCyclingRoadChallenge", "UpdateCyclingRoadState",
  "GetLeadMonFriendshipScore", "CallFrontierUtilFunc", "CallBattleTowerFunc",
  "CallBattleDomeFunction", "CallBattlePalaceFunction", "CopyEReaderTrainerGreeting",
  "DoSpecialTrainerBattle", "CallBattleArenaFunction", "CallBattleFactoryFunction",
  "CallBattlePikeFunction", "CallBattlePyramidFunction", "StopMapMusic",
  "CallVerdanturfTentFunction", "CallFallarborTentFunction", "CallSlateportTentFunction",
  "ChoosePartyForBattleFrontier", "ValidateEReaderTrainer", "GetBattleTowerSinglesStreak",
  "ReducePlayerPartyToSelectedMons", "BedroomPC", "PlayerPC", "FieldShowRegionMap",
  "GetInGameTradeSpeciesInfo", "CreateInGameTradePokemon", "DoInGameTradeScene",
  "GetTradeSpecies", "GetWeekCount", "RetrieveLotteryNumber", "PickLotteryCornerTicket",
  "ShowBerryBlenderRecordWindow", "ResetTrickHouseNuggetFlag", "SetTrickHouseNuggetFlag",
  "ScriptMenu_CreatePCMultichoice", "AccessHallOfFamePC", "Special_ShowDiploma",
  "CheckLeadMonCool", "CheckLeadMonBeauty", "CheckLeadMonCute", "CheckLeadMonSmart",
  "CheckLeadMonTough", "LookThroughPorthole", "DoSoftReset", "GameClear",
  "MoveElevator", "ShowGlassWorkshopMenu", "SpawnCameraObject", "RemoveCameraObject",
  "GetPokeblockNameByMonNature", "GetSecretBaseNearbyMapName", "CheckRelicanthWailord",
  "ShouldDoBrailleRegirockEffectOld", "DoOrbEffect", "FadeOutOrbEffect",
  "WaitWeather", "BufferEReaderTrainerName", "GetSlotMachineId", "GetPlayerFacingDirection",
  "FoundAbandonedShipRoom1Key", "FoundAbandonedShipRoom2Key", "FoundAbandonedShipRoom4Key",
  "FoundAbandonedShipRoom6Key", "LeadMonHasEffortRibbon", "GiveLeadMonEffortRibbon",
  "Special_AreLeadMonEVsMaxedOut", "Script_FacePlayer", "Script_ClearHeldMovement",
  "InitRoamer", "TryUpdateRusturfTunnelState", "IsGrassTypeInParty",
  "DoContestHallWarp", "LoadWallyZigzagoon", "IsStarterInParty", "CopyCurSecretBaseOwnerName_StrVar1",
  "ScriptCheckFreePokemonStorageSpace", "DoSealedChamberShakingEffect_Long",
  "ShowDeptStoreElevatorFloorSelect", "InteractWithShieldOrTVDecoration",
  "IsPokerusInParty", "SetSootopolisGymCrackedIceMetatiles", "ShakeCamera",
  "StartGroudonKyogreBattle", "BattleSetup_StartLegendaryBattle",
  "StartRegiBattle", "SetTrainerFacingDirection", "DoSealedChamberShakingEffect_Short",
  "FoundBlackGlasses", "StartDroughtWeatherBlend", "DoDiveWarp", "DoFallWarp",
  "ShowContestEntryMonPic", "HideContestEntryMonPic", "SetEReaderTrainerGfxId",
  "BattleSetup_StartLatiBattle", "SetRoute119Weather", "SetRoute123Weather",
  "GetContestMultiplayerId", "ScriptGetPartyMonSpecies", "IsSelectedMonEgg",
  "TryInitBattleTowerAwardManObjectEvent", "MoveOutOfSecretBaseFromOutside",
  "LoadPlayerBag", "Script_FadeOutMapMusic", "SetPacifidlogTMReceivedDay",
  "GetDaysUntilPacifidlogTMAvailable", "HasAllHoennMons", "MonOTNameNotPlayer",
  "BufferLottoTicketNumber", "TryHideBattleTowerReporter", "DoesPartyHaveEnigmaBerry",
  "GenerateContestRand", "SetChampionSaveWarp", "TryPutTreasureInvestigatorsOnAir",
  "TryPutLotteryWinnerReportOnAir", "TryPutTrainerFanClubOnAir", "ShouldHideFanClubInterviewer",
  "ShowGlassWorkshopMenu", "PutFanClubSpecialOnTheAir", "IncrementDailyPlantedBerries",
  "IncrementDailyPickedBerries", "InitSecretBaseVars", "CheckInteractedWithFriendsSandOrnament",
  "DeclinedSecretBaseBattle", "DrewSecretBaseBattle", "WonSecretBaseBattle",
  "LostSecretBaseBattle", "CheckInteractedWithFriendsDollDecor", "CheckInteractedWithFriendsCushionDecor",
  "CheckInteractedWithFriendsFurnitureBottom", "CheckInteractedWithFriendsFurnitureMiddle",
  "CheckInteractedWithFriendsFurnitureTop", "CheckInteractedWithFriendsPosterDecor",
  "SetLilycoveLadyGfx", "Script_GetLilycoveLadyId", "GetFavorLadyState",
  "BufferFavorLadyRequest", "HasAnotherPlayerGivenFavorLadyItem",
  "BufferFavorLadyItemName", "BufferFavorLadyPlayerName", "DidFavorLadyLikeItem",
  "Script_FavorLadyOpenBagMenu", "Script_DoesFavorLadyLikeItem", "IsFavorLadyThresholdMet",
  "FavorLadyGetPrize", "SetFavorLadyState_Complete", "GetQuizLadyState",
  "GetQuizAuthor", "IsQuizLadyWaitingForChallenger", "QuizLadyShowQuizQuestion",
  "QuizLadyGetPlayerAnswer", "IsQuizAnswerCorrect", "BufferQuizPrizeItem",
  "SetQuizLadyState_Complete", "BufferQuizAuthorNameAndCheckIfLady",
  "SetQuizLadyState_GivePrize", "ClearQuizLadyPlayerAnswer", "Script_QuizLadyOpenBagMenu",
  "ClearQuizLadyQuestionAndAnswer", "QuizLadySetCustomQuestion", "QuizLadyTakePrizeForCustomQuiz",
  "GetMysteryGiftCardStat", "QuizLadyRecordCustomQuizData", "QuizLadySetWaitingForChallenger",
  "BufferQuizCorrectAnswer", "BufferQuizPrizeName", "QuizLadyPickNewQuestion",
  "ShouldContestLadyShowGoOnAir", "HasPlayerGivenContestLadyPokeblock",
  "Script_BufferContestLadyCategoryAndMonName", "OpenPokeblockCaseForContestLady",
  "SetContestLadyGivenPokeblock", "GetContestLadyMonSpecies", "GetContestLadyCategory",
  "PutLilycoveContestLadyShowOnTheAir", "CloseBattlePikeCurtain",
  "CallApprenticeFunction", "ShouldTryGetTrainerScript", "ShowMapNamePopup",
  "ShowMapNamePopup", "DoMirageTowerCeilingCrumble", "SetMirageTowerVisibility",
  "StartPlayerDescendMirageTower", "BufferTMHMMoveName", "IsWirelessAdapterConnected",
  "TryBecomeLinkLeader", "TryJoinLinkGroup", "RunUnionRoom", "ShowWirelessCommunicationScreen",
  "InitUnionRoom", "BufferUnionRoomPlayerName", "WonderNews_GetRewardInfo",
  "ChooseMonForWirelessMinigame", "Script_ResetUnionRoomTrade", "IsBadEggInParty",
  "ValidateSavedWonderCard", "HasAtLeastOneBerry", "IsPokemonJumpSpeciesInParty",
  "ShowPokemonJumpRecords", "IsDodrioInParty", "ShowDodrioBerryPickingRecords",
  "OffsetCameraForBattle", "GetDeptStoreDefaultFloorChoice", "BufferVarsForIVRater",
  "LinkContestWaitForConnection", "GetWirelessCommType", "LinkContestTryShowWirelessIndicator",
  "LinkContestTryHideWirelessIndicator", "IsWirelessContest", "ShowRankingHallRecordsWindow",
  "ScrollRankingHallRecordsWindow", "ShowFrontierManiacMessage", "IsContestWithRSPlayer",
  "ClearLinkContestFlags", "TryContestEModeLinkup", "ShowScrollableMultichoice",
  "ScrollableMultichoice_TryReturnToList", "BufferBattleTowerElevatorFloors",
  "TryStoreHeldItemsInPyramidBag", "ChooseItemsToTossFromPyramidBag",
  "DoBattlePyramidMonsHaveHeldItem", "BattlePyramidChooseMonHeldItems",
  "SetBattleTowerLinkPlayerGfx", "ShowNatureGirlMessage", "ShowBattlePointsWindow",
  "UpdateBattlePointsWindow", "CloseBattlePointsWindow", "GiveFrontierBattlePoints",
  "TakeFrontierBattlePoints", "GetFrontierBattlePoints", "ShowFrontierExchangeCornerItemIconWindow",
  "CloseFrontierExchangeCornerItemIconWindow", "DisplayBerryPowderVendorMenu",
  "RemoveBerryPowderVendorMenu", "HasEnoughBerryPowder", "TakeBerryPowder",
  "PrintPlayerBerryPowderAmount", "ShowFrontierGamblerLookingMessage",
  "ShowFrontierGamblerGoMessage", "Script_DoRayquazaScene", "OpenPokenavForTutorial",
  "ScriptMenu_CreateStartMenuForPokenavTutorial", "CountPlayerTrainerStars",
  "BufferBattleFrontierTutorMoveName", "CloseBattleFrontierTutorWindow",
  "ScrollableMultichoice_RedrawPersistentMenu", "ChooseMonForMoveTutor",
  "GetBattleFrontierTutorMoveIndex", "ScrollableMultichoice_ClosePersistentMenu",
  "DoDeoxysRockInteraction", "SetDeoxysRockPalette", "CreateEnemyEventMon",
  "StartMirageTowerDisintegration", "StartMirageTowerShake", "StartMirageTowerFossilFallAndSink",
  "ChangeBoxPokemonNickname", "GetPCBoxToSendMon", "ShouldShowBoxWasFullMessage",
  "SetMatchCallRegisteredFlag", "DoDomeConfetti", "CreateAbnormalWeatherEvent",
  "GetAbnormalWeatherMapNameAndType", "GetMartEmployeeObjectEventId",
  "SaveForBattleTowerLink", "Unused_SetWeatherSunny", "SetUnlockedPokedexFlags",
  "IsTrainerRegistered", "ShouldDoBrailleRegicePuzzle", "EnableNationalPokedex",
  "ScriptMenu_CreateLilycoveSSTidalMultichoice", "GetLilycoveSSTidalSelection",
  "TurnOnTVScreen", "SetMewAboveGrass", "ShouldDistributeEonTicket",
  "LinkRetireStatusWithBattleTowerPartner", "BattleTowerReconnectLink",
  "CallTrainerHillFunction", "Script_DoRayquazaScene", "LoopWingFlapSE",
  "DestroyMewEmergingGrassSprite", "ShowBerryCrushRankings", "TryBufferWaldaPhrase",
  "DoWaldaNamingScreen", "TryGetWallpaperWithWaldaPhrase", "PlayerNotAtTrainerHillEntrance",
  "GetBattlePyramidHint", "LoadLinkContestPlayerPalettes", "ShowTrainerHillRecords",
  "PlayerFaceTrainerAfterBattle", "ResetHealLocationFromDewford",
  "IsLastMonThatKnowsSurf", "CountPartyAliveNonEggMons", "TryPrepareSecondApproachingTrainer",
  "RemoveRecordsWindow", "CloseDeptStoreElevatorWindow", "TrySetBattleTowerLinkType",
}

-- The three indices the importer independently finds sharing a pointer, kept
-- here so the suite can check the list against the cartridge rather than
-- against itself.
Gen3Specials.SHARED = { { 277, 348 }, { 409, 410 }, { 470, 508 } }

-- The name of `special n`, or nil past the end of pret's list.
function Gen3Specials.name(n)
  n = tonumber(n)
  if not n then return nil end
  return Gen3Specials.NAMES[n + 1]
end

-- "306 (ScriptCheckFreePokemonStorageSpace)", or just "306" for an index with
-- no name.  For log lines and for the audit.
function Gen3Specials.label(n)
  local name = Gen3Specials.name(n)
  if not name then return tostring(n) end
  return ("%s (%s)"):format(tostring(n), name)
end

return Gen3Specials
