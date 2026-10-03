-- SINNOH'S SAVE SCRIPT, ANSWERED FROM ENGINE STATE.
--
-- `scripts_common.s` does not save the game with one command.  It asks four
-- questions and branches on them, and the branch decides which of five
-- messages the player reads.  The spine is `CommonScript_TrySaveGame`:
--
--     CheckSaveType VAR_RESULT
--     GoToIfEq VAR_RESULT, SAVE_TYPE_OVERWRITE,       SaveTypeOverwrite
--     OpenSaveInfo
--     Message WouldYouLikeToSave        ShowYesNoMenu  -> CancelSave on NO
--     CheckSaveType VAR_RESULT
--     GoToIfEq VAR_RESULT, SAVE_TYPE_NO_DATA_EXISTS,  SavingALotOfData
--     GoToIfEq VAR_RESULT, SAVE_TYPE_FULL_SAVE,       FullSaveAskOverwrite
--     GoToIfEq VAR_RESULT, SAVE_TYPE_QUICK_SAVE,      QuickSaveAskOverwrite
--
-- so `checksavetype` is the whole shape of the dialogue and it has to be
-- answered honestly or the player reads the wrong thing on every save in the
-- game.  THE FOUR ARMS LIVE HERE TOGETHER, in the cartridge's own order, so
-- that nobody has to find them in four places to see that they are exhaustive.
--
-- `generated/save_types.txt` is a metang enum with no explicit values, so the
-- numbers are the file's own order from zero -- corroborated by
-- `include/script_manager.h`, which says of the result it hands back that
-- "0 here can mean overwrite or that the player canceled", and `CancelSave`
-- writes 0.
--
-- THE CARTRIDGE'S RULES (src/savedata.c, src/scrcmd.c ScrCmd_CheckSaveType):
--
--     OverwriteCheck      = isNewGameData and dataExists
--     NO_DATA_EXISTS      = not dataExists
--     FULL_SAVE           = fullSaveRequired
--     QUICK_SAVE          = otherwise
--
-- and a full save writes the NORMAL *and* BOXES blocks while a quick save
-- writes only NORMAL -- which is what `fullSaveRequired` means and why every
-- function in `pc_boxes.c` sets it.
local Gen4Save = {}

-- The cartridge's own four values, from generated/save_types.txt in order.
Gen4Save.TYPE = {
  OVERWRITE      = 0,
  NO_DATA_EXISTS = 1,
  FULL_SAVE      = 2,
  QUICK_SAVE     = 3,
}

-- TEXT_BANK_SAVE_INFO_WINDOW, line 535 of generated/text_banks.txt.
Gen4Save.INFO_BANK = 534

-- ---------------------------------------------------------------------------
-- is saving blocked outright?
-- ---------------------------------------------------------------------------

-- THE CARTRIDGE SAYS YES AND THIS PORT SAYS NO, deliberately.
--
-- `SaveData_OverwriteCheck` is `isNewGameData and dataExists`: you started a
-- new game while the card still held somebody's save, and until that save is
-- erased from the title screen you may not write at all.  The text spells out
-- the hardware it is about -- "Press Up + SELECT + B Button on the title
-- screen if you want to erase the current saved game file" -- because a DS
-- cartridge has exactly one save and the game is refusing to spend it without
-- being asked at the title.
--
-- This engine has save SLOTS, with a launcher that registers, names, selects
-- and deletes them (SaveData.createSlot / renameSlot / setActiveSlot).  The
-- question the cartridge's title screen asks has therefore already been asked
-- and answered before the game boots: the active slot IS the chosen
-- destination.  Reproducing the refusal would mean a new Platinum game started
-- on a slot that has ever been saved could never be saved again, which is not
-- the cartridge's behaviour transplanted -- it is a hardware limit transplanted
-- into an engine that does not have the hardware.
--
-- So this is false, and `CommonScript_SaveTypeOverwrite` and
-- `CommonStrings_Text_ImpossibleToSave` are decoded, reachable by the VM and
-- never reached.  Saying so here is the point: the arm exists, it is wired,
-- and the reason it is cold is written down rather than left looking like an
-- oversight.
function Gen4Save.overwriteBlocked(_save)
  return false
end

-- ---------------------------------------------------------------------------
-- does a file already exist where the next save lands?
-- ---------------------------------------------------------------------------

-- `SaveData_DataExists`.  It decides one visible thing: the FIRST save into a
-- file does not ask "There is already a saved file.  Is it OK to overwrite
-- it?" and every later one does.  The engine's version of that question is
-- whether the active slot's file is already on disk, which is exactly where
-- `SaveData.save` is about to write.
--
-- `gen4SavedOnce` is taken as evidence too, so a headless caller with no
-- filesystem still gets the right answer after its first write, and so the
-- answer can only ever go from false to true within a run.
function Gen4Save.dataExists(save)
  if type(save) == "table" and save.gen4SavedOnce == true then return true end
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if not ok or type(SaveData) ~= "table" or not SaveData.saveFileExists then
    return false
  end
  local okCall, present = pcall(SaveData.saveFileExists,
                                type(save) == "table" and save.version or nil)
  return okCall and present == true
end

-- ---------------------------------------------------------------------------
-- is this a full save or a quick one?
-- ---------------------------------------------------------------------------

-- `fullSaveRequired` IS DERIVED, NOT HOOKED, and that is the whole reason this
-- function exists in this shape.
--
-- The cartridge sets the flag by hand from ten places in `pc_boxes.c`, one in
-- the box application, one in `clear_game.c` and two in the GTS.  Porting
-- it as a flag would mean finding every place this engine moves a boxed
-- Pokemon and setting a bit there -- and the bug this port keeps finding is
-- exactly that: the same thing spelled in two files that never meet, with the
-- one nobody remembered left wrong.  A list of call sites is a list; a
-- fingerprint of the boxes is an invariant, and it cannot be missed by a new
-- piece of box code that nobody thought to hook.
--
-- So: stamp the boxes at save time, and "the boxes changed since the last
-- save" is a comparison rather than a promise.  Deposits, withdrawals,
-- releases, moves between boxes and renames all move the stamp; walking
-- around, battling and healing do not.
--
-- No stamp at all means full, which is also what the cartridge does: both
-- `SaveData_Init` with nothing to load and `SaveData_Clear` set the flag TRUE.
local STAMP_MOD = 2147483647 -- 2^31 - 1, prime; keeps the hash inside a double

local function mixNumber(h, n)
  return (h * 131 + (tonumber(n) or 0)) % STAMP_MOD
end

local function mixString(h, s)
  s = tostring(s or "")
  h = mixNumber(h, #s)
  for i = 1, #s do h = mixNumber(h, s:byte(i)) end
  return h
end

-- Identity only.  HP is deliberately not in here: a Pokemon Center heal is not
-- a box edit, and a stamp that moved on one would promise "a lot of data" after
-- every visit to a nurse.
function Gen4Save.boxStamp(save)
  local boxes = type(save) == "table" and save.boxes or nil
  if type(boxes) ~= "table" then return 0 end
  local h = mixNumber(2166136261 % STAMP_MOD, #boxes)
  for i = 1, #boxes do
    local box = boxes[i]
    h = mixNumber(h, i)
    if type(box) ~= "table" then
      h = mixNumber(h, 0)
    else
      h = mixNumber(h, #box)
      for j = 1, #box do
        local mon = box[j]
        h = mixNumber(h, j)
        if type(mon) ~= "table" then
          h = mixNumber(h, 0)
        else
          h = mixString(h, mon.species)
          h = mixNumber(h, mon.level)
          h = mixString(h, mon.nickname)
          h = mixNumber(h, (tonumber(mon.personality or mon.otId) or 0) % STAMP_MOD)
        end
      end
    end
  end
  return h
end

function Gen4Save.fullSaveRequired(save)
  if type(save) ~= "table" then return true end
  local stamp = save.gen4BoxStamp
  if stamp == nil then return true end
  return stamp ~= Gen4Save.boxStamp(save)
end

-- ---------------------------------------------------------------------------
-- the answer
-- ---------------------------------------------------------------------------

-- `ScrCmd_CheckSaveType`'s if/else chain, in its order.  Reading it as four
-- lines is the point: they are mutually exclusive and they are exhaustive.
function Gen4Save.typeFor(save)
  local T = Gen4Save.TYPE
  if Gen4Save.overwriteBlocked(save) then return T.OVERWRITE end
  if not Gen4Save.dataExists(save) then return T.NO_DATA_EXISTS end
  if Gen4Save.fullSaveRequired(save) then return T.FULL_SAVE end
  return T.QUICK_SAVE
end

-- After a write that landed.  `SaveDataState_Save`'s success arm sets
-- dataExists TRUE, isNewGameData FALSE and fullSaveRequired FALSE; this is the
-- same three facts in this engine's terms, and re-stamping the boxes is what
-- turns the next save into a quick one.
function Gen4Save.markSaved(save)
  if type(save) ~= "table" then return end
  save.gen4SavedOnce = true
  save.gen4BoxStamp = Gen4Save.boxStamp(save)
end

-- ---------------------------------------------------------------------------
-- the extra save blocks
-- ---------------------------------------------------------------------------

-- `SaveDataExtra_Init` (savedata.c:896) walks `gExtraSaveTable`, skips the
-- Hall of Fame entry, zeroes and initialises every other extra block, saves
-- each one, and sets the misc-save init flag.  It returns immediately if the
-- flag is already set, so it runs at most once per file.
--
-- The extra blocks are the Battle Frontier records, the battle videos and the
-- Hall of Fame -- separate sectors on the card because they are too big to
-- rewrite on an ordinary save.  This engine serialises one table, so there is
-- no second sector to zero and nothing to initialise that is not already
-- "absent means empty".  WHAT SURVIVES THE PORT IS THE FLAG, because the
-- script branches on it: `QuickSaveCheckMiscFlag` turns a quick save into a
-- full one the first time, which is the cartridge paying for those sectors
-- once.  Keeping the flag keeps that beat; inventing blocks to zero would not.
--
-- Returns true when this call is the one that set it, matching the C's
-- early-out.
function Gen4Save.initMiscSave(save)
  if type(save) ~= "table" then return false end
  if save.gen4MiscSaveInit == true then return false end
  save.gen4MiscSaveInit = true
  return true
end

function Gen4Save.miscSaveInit(save)
  return type(save) == "table" and save.gen4MiscSaveInit == true
end

-- ---------------------------------------------------------------------------
-- the save info panel
-- ---------------------------------------------------------------------------

-- `OpenSaveInfo` draws the panel the player reads before answering, and
-- `SaveInfoWindow_PrintText` (overlay005/save_info_window.c) is five rows:
-- the location on its own, then four label/value pairs with the label flush
-- left and the value flush right in a thirteen-tile window.
--
-- THE LABELS ARE THE CARTRIDGE'S.  Bank 534 is
--
--     0  {COLOR 1}{STRVAR_1 4 0 0}{COLOR 0}   5  {STRVAR_1 3 1 0}
--     1  PLAYER:                              6  {STRVAR_1 50 2 0}
--     2  BADGES:                              7  {STRVAR_1 52 3 0}
--     3  POKeDEX:                             8  {STRVAR_1 52 4 0}:{STRVAR_1 51 5 0}
--     4  TIME:
--
-- -- entry 0 and entries 5-8 are nothing but placeholders, so the values come
-- from engine state and only rows 1-4 are text, read out of the extracted
-- bank rather than typed here.
--
-- TWO DETAILS THAT ARE EASY TO GET WRONG, both from the C:
--   * the dex count is `Pokedex_CountSeen`, NOT owned -- the engine's own Gen 1
--     save panel counts owned, and copying that would have been the obvious
--     and wrong thing to do;
--   * the dex row is dropped entirely when the player has no Pokedex yet
--     (`Pokedex_IsObtained`), and `SaveInfoWindow_Height` takes two tiles off
--     the window when it is, so the panel is 13x10 with it and 13x8 without.
Gen4Save.PANEL_TILES_W = 13
Gen4Save.PANEL_TILES_H = 10

-- (the lookup moved to `Gen4Text.resolve` when the bag needed the same three
-- steps for its own bank; this is the one caller's name for it.)
local function bankText(game, index)
  return require("src.import.Gen4Text")
           .resolve(game and game.data, Gen4Save.INFO_BANK, index, game)
end

-- { rows = { {label=, value=}, ... }, heading = <location>, tilesH = 10|8 }
-- nil when there is no save to describe.
function Gen4Save.infoPanel(game, save)
  save = save or (game and game.save)
  if type(save) ~= "table" then return nil end
  local def = game.overworld and game.overworld.map and game.overworld.map.def
  local Badges = require("src.inventory.Badges")
  local SaveData = require("src.core.SaveData")
  local Flags = require("src.script.Flags")

  local seen = 0
  if Flags.hasPokedex(save) then
    for _ in pairs((save.pokedex and save.pokedex.seen) or {}) do
      seen = seen + 1
    end
  end

  local secs = math.floor(SaveData.playSeconds(save) or 0)
  -- Badges.count reaches the data tables, which a headless caller may not
  -- have; the panel is worth drawing with a zero in it rather than not at all.
  local okBadges, badges = pcall(Badges.count, game.data, save)
  if not okBadges then badges = 0 end

  local rows = {
    { label = bankText(game, 1) or "PLAYER:",
      value = tostring((save.player and save.player.name) or "") },
    { label = bankText(game, 2) or "BADGES:",
      value = ("%d"):format(tonumber(badges) or 0) },
  }
  -- Pokedex_IsObtained false -> the row is not drawn and the window loses two
  -- tiles.  `seen == 0` is the C's own test: it forces the count to zero when
  -- the dex has not been obtained and then skips the row on a zero count.
  if seen > 0 then
    rows[#rows + 1] = { label = bankText(game, 3) or "POKeDEX:",
                        value = ("%d"):format(seen) }
  end
  rows[#rows + 1] = { label = bankText(game, 4) or "TIME:",
                      value = ("%d:%02d"):format(math.floor(secs / 3600),
                                                 math.floor(secs / 60) % 60) }
  return {
    heading = (def and def.label) or "",
    rows = rows,
    tilesW = Gen4Save.PANEL_TILES_W,
    tilesH = seen > 0 and Gen4Save.PANEL_TILES_H or (Gen4Save.PANEL_TILES_H - 2),
  }
end

return Gen4Save
