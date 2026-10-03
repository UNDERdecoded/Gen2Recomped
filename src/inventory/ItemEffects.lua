-- Item use effects, ported from engine/items/item_effects.asm.
-- Heal amounts and behaviors match Gen 1; TMs/HMs teach their machine
-- move when the species' tmhm list allows it.
--
-- ItemEffects.use returns:
--   "consumed", messages            item used up
--   "kept", messages                used but not consumed (TM kept? no --
--                                   HMs and key items)
--   "failed", messages              no effect ("It won't have any effect.")
--   "ball"                          caller must throw it (battle only)
--   "learn", moveId                 caller must run the learn-move flow

local Flags = require("src.script.Flags")
local Strings = require("src.core.Strings")

local ItemEffects = {}

-- ITEM_USE_FUNC_EXPLORER_KIT, the index of the Explorer Kit's row in
-- `sItemUseFuncs` (item_use_functions.c).  A Platinum item record names its
-- row in `fieldUseFunc`; the Explorer Kit's is 3.
local ITEM_USE_FUNC_EXPLORER_KIT = 3


local HEAL_AMOUNT = {
  POTION = 20, SUPER_POTION = 50, HYPER_POTION = 200,
  FRESH_WATER = 50, SODA_POP = 60, LEMONADE = 80,
  -- Gen2 additions (data/items/attributes.asm): the two healing berries and
  -- the Moomoo Milk / Berry Juice drinks.
  BERRY = 10, GOLD_BERRY = 30, BERRY_JUICE = 20, MOOMOO_MILK = 100,
  RAGECANDYBAR = 20,
}

local STATUS_HEAL = {
  ANTIDOTE = { PSN = true }, BURN_HEAL = { BRN = true },
  ICE_HEAL = { FRZ = true }, AWAKENING = { SLP = true },
  PARLYZ_HEAL = { PAR = true },
  FULL_HEAL = { PSN = true, BRN = true, FRZ = true, SLP = true, PAR = true },
  -- Gen2 status berries.  BITTER BERRY cures confusion, which is a volatile
  -- rather than a status byte, so it is handled alongside FULL HEAL below.
  PSNCUREBERRY = { PSN = true }, BURNT_BERRY = { FRZ = true },
  ICE_BERRY = { BRN = true }, MINT_BERRY = { SLP = true },
  PRZCUREBERRY = { PAR = true },
  BITTER_BERRY = {},
  MIRACLEBERRY = { PSN = true, BRN = true, FRZ = true, SLP = true,
                   PAR = true },
}

-- Items that also clear the confusion volatile (FULL HEAL, MIRACLEBERRY and
-- BITTER BERRY -- item_effects.asm .curestatus / .bitterberry).
local CURES_CONFUSION = {
  FULL_HEAL = true, MIRACLEBERRY = true, BITTER_BERRY = true,
}

local BALLS = {
  POKE_BALL = true, GREAT_BALL = true, ULTRA_BALL = true,
  MASTER_BALL = true, SAFARI_BALL = true,
  -- Gen2 balls
  LEVEL_BALL = true, LURE_BALL = true, MOON_BALL = true,
  FRIEND_BALL = true, FAST_BALL = true, HEAVY_BALL = true,
  LOVE_BALL = true, PARK_BALL = true,
}

local STONES = {
  FIRE_STONE = true, WATER_STONE = true, THUNDER_STONE = true,
  LEAF_STONE = true, MOON_STONE = true,
  -- Gen2 spells Thunderstone as one word and adds the Sun Stone
  THUNDERSTONE = true, SUN_STONE = true,
}

-- vitamins: stat-exp boosters (ItemUseVitamin)
local VITAMINS = { HP_UP = "hp", PROTEIN = "attack", IRON = "defense",
                   CARBOS = "speed", CALCIUM = "special" }

ItemEffects.BALLS = BALLS

-- Gen2 items are ITEM_nnn; every table in this file is keyed by Gen1's
-- name-derived ids, which the Gen2 extractor stamps on as `key`.
local function alias(id, itemDef)
  if itemDef and itemDef.key then return itemDef.key end
  local Data = require("src.core.Data")
  local def = Data.items and Data.items[id]
  return (def and def.key) or id
end
ItemEffects.alias = alias

-- IS THIS A BALL?  The name list above is Gen 1's and Gen 2's, and Hoenn has
-- seven balls that are not on it -- DIVE, LUXURY, NEST, NET, PREMIER, REPEAT
-- and TIMER.  Reported as items that simply did nothing when thrown, which is
-- what an unrecognised ball does: `use` falls past the ball branch and ends
-- at the refusal.
--
-- The dataset already knows.  Every ball on the cartridge is in the BALL
-- POCKET and has no field-use function at all -- you cannot use one from the
-- bag, only throw it -- so the pocket is the cartridge's own answer and a
-- Gen 4 ball added by a mod gets it for free.  The name list stays as the
-- answer for Gen 1 and Gen 2, whose items carry no pocket.
--
-- ...AND SINNOH SPELLS THAT POCKET DIFFERENTLY.
--
-- Reported from play: "pokeballs arent working in platinum they give an error
-- not the place this item should be used".  Every one of Platinum's sixteen
-- balls carries `pocket = "POKE_BALLS"` -- `Gen4Items` writes the
-- cartridge's own eight pocket names, and slot 2 is POKE_BALLS -- while
-- Emerald's twelve carry `"BALL"`.  This line knew one spelling, so no
-- Sinnoh ball was ever a ball: `use` fell past the ball branch and ended at
-- the refusal, which is the message that was reported.
--
-- The knowledge was already in the tree and in the wrong place for this:
-- `Gen3BagMenu` normalises POKE_BALLS to BALL for its own pocket tabs and
-- nothing else ever saw it.  THE SAME THING UNDER TWO NAMES IN TWO FILES
-- THAT NEVER MEET is the shape that cost Sinnoh its whole type chart and
-- every one of its abilities; the answer is the same one -- ask once, here,
-- and accept both spellings rather than teaching each caller.
local BALL_POCKETS = { BALL = true, POKE_BALLS = true, BALLS = true }
ItemEffects.BALL_POCKETS = BALL_POCKETS

function ItemEffects.isBall(id, itemDef)
  if BALLS[alias(id, itemDef)] then return true end
  local def = itemDef
  if def == nil then
    local Data = require("src.core.Data")
    def = Data.items and Data.items[id]
  end
  return (type(def) == "table" and BALL_POCKETS[def.pocket] == true)
    or false
end
function ItemEffects.isStone(id) return STONES[alias(id)] or false end

-- Does using this item take item_effects.asm's .healHP path, the one that
-- plays SFX_HEAL_HP and lengthens the party HP bar with UpdateHPBar2 before
-- the message (item_effects.asm .doneHealing)?  The status-only cures branch
-- to .playStatusAilmentCuringSound instead and never touch the bar.  BagMenu
-- keeps the party picker open for these so the fill has something to draw
-- on (#252).
-- The Gen 3 record, reachable from the two predicates below -- which run
-- before `use` and decide whether a party picker opens at all.  Declared here
-- rather than beside gen3Use because a `local function` is only in scope
-- below its own declaration, and these two are above it.
function ItemEffects.gen3RecordFor(id, data)
  local Data = data
  if Data == nil then
    local ok, mod = pcall(require, "src.core.Data")
    Data = ok and mod or nil
  end
  local c = Data and Data.constants
  local all = c and c.gen3ItemEffects
  return type(all) == "table" and all[id] or nil
end

-- ---------------------------------------------------------------------------
-- SINNOH'S MEDICINE, WHICH IS A TWENTY-BYTE STRUCT AND NOT A NAME.
--
-- Reported from play: "make sure all items are cabable of being used
-- properly", alongside the Poke Balls above.
--
-- WHY NOTHING WORKED.  Everything below this point in the file dispatches on a
-- NAME -- POTION, FULL_RESTORE, ETHER -- which `alias` resolves from the item
-- record's `key`.  A Platinum item record has no `key`: the cache is 446 rows
-- keyed 0..445 and `Data` publishes them again as ITEM_000..ITEM_445 because
-- the bag's keys are strings.  So `alias` answered "ITEM_017" for a Potion,
-- every name test below failed, and `use` fell all the way through to the
-- refusal -- which is the message that was reported, for EVERY medicine in the
-- game and not only for the balls.
--
-- THE CARTRIDGE STATES IT, PER ITEM, AND THE CACHE ALREADY CARRIES IT.
-- `ItemData.partyUseParam` (pokeplatinum include/item.h) is an
-- `ItemPartyParam`: a twenty-byte bitfield naming every effect using the item
-- has on a party member.  The extractor writes it out verbatim, so the answer
-- has been sitting in `items.lua` the whole time with nothing reading it.
--
-- Matching a name table against a second cartridge's spellings is the trap
-- that has already cost this port its Gen 4 type chart, its abilities and its
-- move effects; the struct cannot drift and does not need a translation table.
--
-- THE LAYOUT, and it is not guessed -- four independent facts in the shipped
-- data land exactly where the struct says they should:
--
--   byte 0  healSleep .. guardSpec, one bit each in that order
--   byte 1  revive(0) reviveAll(1) levelUp(2) evolve(3) atkStages(4..7)
--   byte 2  defStages(0..3) spatkStages(4..7)
--   byte 3  spdefStages(0..3) speedStages(4..7)
--   byte 4  accStages(0..3) critStages(4..5) ppUp(6) ppMax(7)
--   byte 5  ppRestore(0) ppRestoreAll(1) hpRestore(2) then the five EV bits
--   byte 6  giveSpDefEVs(0) and the three friendship bits(1..3)
--   7..12   hpEVs atkEVs defEVs speedEVs spatkEVs spdefEVs, SIGNED
--   13      hpRestored   (255 = all, 254 = half)
--   14      ppRestored   (127 = all)
--   15..17  friendshipLow friendshipMed friendshipHigh, SIGNED
--
-- The four that confirm it: Potion/Super/Hyper read 20/50/200 at byte 13;
-- Revive reads 254 and Max Revive 255 with the revive bit set; Rare Candy and
-- PP Up carry +5/+3/+2 at bytes 15..17, which are Gen 4's friendship steps;
-- and the Energy Root reads -10/-10/-15 there, which is why those bytes have
-- to be signed.
--
-- IT ANSWERS IN THE GEN 3 RECORD'S SHAPE ON PURPOSE.  `gen3Use` below already
-- runs every one of these effects -- the HP fill, the status clear, the PP
-- restore, the EV ceilings, the friendship steps -- against a record with
-- these field names. Emitting that shape means Sinnoh's medicine is run by
-- code Hoenn's has been exercising for months, rather than by a second copy
-- of it that will drift.
local GEN4_PARTY_PARAM_BYTES = 20
local GEN4_HP_ALL, GEN4_HP_HALF = 255, 254
local GEN4_PP_ALL = 127
-- byte 0, in the struct's own order
local GEN4_CURE = { [0] = "SLP", [1] = "PSN", [2] = "BRN", [3] = "FRZ",
                    [4] = "PAR" }
-- byte 5 bit 3 upward, then byte 6 bit 0: the six EV bits and the stat each
-- one names, in the order the struct declares them
local GEN4_EV_BITS = {
  { byte = 5, bit = 3, stat = "hp",    at = 7 },
  { byte = 5, bit = 4, stat = "atk",   at = 8 },
  { byte = 5, bit = 5, stat = "def",   at = 9 },
  { byte = 5, bit = 6, stat = "speed", at = 10 },
  { byte = 5, bit = 7, stat = "spatk", at = 11 },
  { byte = 6, bit = 0, stat = "spdef", at = 12 },
}

local function signed8(v)
  v = math.floor(tonumber(v) or 0) % 256
  return v > 127 and (v - 256) or v
end

function ItemEffects.gen4RecordFor(id, data)
  local def = nil
  if type(id) == "table" then
    def = id
  else
    local Data = data
    if Data == nil then
      local ok, mod = pcall(require, "src.core.Data")
      Data = ok and mod or nil
    end
    def = Data and Data.items and Data.items[id] or nil
  end
  -- THE STRUCT IS ONLY A STRUCT WHEN `partyUse` SAYS SO.
  --
  -- `ItemData` declares it as `union { u8 dummy; ItemPartyParam
  -- partyUseParam; }`, and `Item_Get` (src/item.c) switches on `partyUse`:
  -- TRUE reads the struct, FALSE reads `dummy` and every party question
  -- answers from that one byte.  So for the 287 items that are not party
  -- items, those twenty bytes are NOT a party param -- byte 0 is `dummy`
  -- and the rest is whatever follows in the file.
  --
  -- Read without the gate, a Great Ball's `dummy` of 2 came back as
  -- healPoison and a Good Rod's 1 as healSleep: twenty-eight items that
  -- would have opened a party picker and cured a status.  The gate is one
  -- line and it is the cartridge's own.
  if (tonumber(type(def) == "table" and def.partyUse) or 0) ~= 1 then
    return nil
  end
  local blob = type(def) == "table" and def.partyUseParam
  if type(blob) ~= "string" or #blob < GEN4_PARTY_PARAM_BYTES then
    return nil
  end
  local b = {}
  for i = 0, GEN4_PARTY_PARAM_BYTES - 1 do b[i] = blob:byte(i + 1) end
  local function bit(byteIndex, shift)
    return math.floor(b[byteIndex] / 2 ^ shift) % 2 == 1
  end

  local r = { source = "cartridge:ItemData.partyUseParam" }

  -- ---- the friendship steps, which every medicine may carry --------------
  local friendship = {}
  for i, at in ipairs({ 15, 16, 17 }) do
    if bit(6, i) then friendship[#friendship + 1] = signed8(b[at]) end
  end
  if #friendship > 0 then r.friendship = friendship end

  -- ---- A RARE CANDY IS NOT A REVIVE, whatever the bits say ---------------
  --
  -- Rare Candy's byte 1 is 0x05: levelUp AND revive. The second bit is the
  -- cartridge saying the item may be used on a fainted Pokemon, not that it
  -- brings one back -- `gen3Use`'s revive arm would fill its HP and stop
  -- there, and the level would never happen. So a record that levels up says
  -- only that, and the level-up arm in `use` is what claims it.
  if bit(1, 2) then
    r.levelUp = true
    r.amount = "levelUp"
    return r
  end

  -- ---- status ------------------------------------------------------------
  local cures, all = {}, true
  for shift = 0, 4 do
    if bit(0, shift) then cures[#cures + 1] = GEN4_CURE[shift]
    else all = false end
  end
  -- CURE_ALL is Gen 3's own name for the five majors together, and `gen3Use`
  -- reads it as "and the confusion volatile too" -- which is exactly what a
  -- Full Heal does here, and its confusion bit is set alongside the five.
  if all then r.cureAll = true
  elseif #cures > 0 then table.sort(cures) r.cures = cures end
  -- CONFUSION AND INFATUATION ARE NOT STATUSES, they are volatiles, and
  -- they have bits of their own.  The Persim Berry sets ONLY the
  -- confusion one, so without this it decoded to nothing at all and a
  -- berry the cartridge gives an effect did nothing -- which is the same
  -- shape as the medicine it is sitting next to in the bag.
  if bit(0, 5) then r.confusion = true end
  if bit(0, 6) then r.attract = true end

  -- ---- HP, and the two sentinels -----------------------------------------
  if bit(1, 1) then
    -- reviveAll: the Sacred Ash, which takes no target
    r.sacredAsh = true
    r.revive = true
    r.heal = true
    r.amount = "all"
  elseif bit(5, 2) then
    r.heal = true
    if bit(1, 0) then r.revive = true end
    local hp = b[13]
    r.amount = (hp == GEN4_HP_ALL and "all")
      or (hp == GEN4_HP_HALF and "half") or hp
  elseif bit(1, 0) then
    r.revive = true
    r.amount = "half"
  end

  -- ---- PP ----------------------------------------------------------------
  if bit(5, 0) or bit(5, 1) then
    r.pp = bit(5, 0) and "one" or "all"
    local pp = b[14]
    r.amount = (pp == GEN4_PP_ALL) and "all" or pp
  end
  if bit(4, 6) then r.ppUp = true end
  if bit(4, 7) then r.ppMax = true end

  -- ---- effort values ------------------------------------------------------
  for _, e in ipairs(GEN4_EV_BITS) do
    if bit(e.byte, e.bit) then
      r.ev = e.stat
      r.amount = signed8(b[e.at])
      break
    end
  end

  -- ---- and the ones that are RECORDED AND NOT RUN -------------------------
  -- The stat-stage items (X Attack and the rest), GUARD SPEC and the evolution
  -- stones are battle or menu flows of their own; the record says so rather
  -- than pretending the item did nothing.  Same arrangement as the Gen 3
  -- extractor's `effect.battle`.
  if bit(0, 7) then r.guardSpec = true end
  if bit(1, 3) then r.evolve = true end
  -- EVERY stage field, and the accuracy one is why this is spelled out.
  -- The first draft tested byte 4's crit bits and not its low nibble, so
  -- X ACCURACY -- the one item whose only bit is `accStages` -- decoded to
  -- nothing and was the last row in the audit's "an effect is being
  -- dropped" list.  atk is byte 1's high nibble, def/spatk are byte 2,
  -- spdef/speed are byte 3, acc is byte 4's low nibble and crit its next
  -- two bits.
  if math.floor(b[1] / 16) > 0 or b[2] > 0 or b[3] > 0
     or (b[4] % 16) > 0 or math.floor(b[4] / 16) % 4 > 0 then
    r.stages = true
  end

  -- NOTHING AT ALL is not a record.  446 of Sinnoh's items carry this struct
  -- and most of them are all zeroes -- a Poke Ball, a TM, a Key Item -- and
  -- answering with an empty table would open a party picker for every one of
  -- them.
  -- A RECORD IS ANY BIT AT ALL, not only the ones `use` can run today.
  -- An evolution stone, a Dire Hit and a Guard Spec all state real
  -- effects; leaving them out of the record would make "the cartridge
  -- says nothing" and "this port does not run it yet" the same answer,
  -- and `tools/gen4_item_use_check.lua` counts the second one.
  if not (r.heal or r.revive or r.cures or r.cureAll or r.confusion
          or r.attract or r.pp or r.ev or r.ppUp or r.ppMax
          or r.sacredAsh or r.levelUp or r.evolve or r.guardSpec
          or r.stages) then
    return nil
  end
  return r
end

-- ONE ACCESSOR.  Hoenn's table first -- it is read straight off the ROM and
-- verified there -- then Sinnoh's per-item struct.  Every caller that used to
-- ask `gen3RecordFor` asks this instead, so the party picker, the heal path
-- and `use` all agree about what an item does on every cartridge.
function ItemEffects.recordFor(id, data)
  return ItemEffects.gen3RecordFor(id, data)
      or ItemEffects.gen4RecordFor(id, data)
end

function ItemEffects.healsHP(id)
  local r = ItemEffects.recordFor(id)
  if r then return (r.heal or r.revive) and true or false end
  id = alias(id)
  return HEAL_AMOUNT[id] ~= nil or id == "MAX_POTION" or id == "FULL_RESTORE"
      or id == "REVIVE" or id == "MAX_REVIVE"
end

-- Does this item need a party-member target?

-- A PLATINUM TM HAS NO `machine` RECORD, AND THAT IS WHY NONE OF THEM COULD BE
-- TAUGHT.
--
-- Reported from play, with a screenshot of HM01 in the bag: "This isn't the
-- time to use that!".
--
-- `BagMenu.useItem` gates the whole machine flow -- the boot-up lines, the
-- party picker in TM/HM mode, the ABLE/UNABLE word -- on `def.machine`, and
-- `ItemEffects.needsTarget` never answers true without one either.  Across the
-- 446 items in a Platinum cache, **zero** carry it: Gen 1, 2 and 3 extractors
-- write `machine = { move, kind }` and the Gen 4 one never has, because the
-- cartridge does not store it that way.
--
-- So every piece of work the TM-teaching pass did -- the party alias's `tmhm`
-- key, the 128-bit learnset mask, bank 453's ABLE!/UNABLE! -- was correct and
-- unreachable, because the one field that triggers it was absent.
--
-- WHAT THE CARTRIDGE STORES INSTEAD, and it is better than a name match:
--
--   * `fieldUseFunc` is an index into `sItemUseFuncs`
--     (src/item_use_functions.c), and `ITEM_USE_FUNC_TM_HM` is **6**
--     (include/constants/items.h).  Exactly 100 items carry it.
--   * `constants.tmhmMoves` is the 100-entry `sTMHMMoves` array in the
--     cartridge's own order: TM01..TM92 then HM01..HM08.
--
-- TWO INDEPENDENT SOURCES, AND THEY MUST AGREE.  `Item_MoveForTMHM` is three
-- lines of src/item.c and it does not look at a name at all:
--
--     item -= ITEM_TM01;
--     return sTMHMMoves[item];
--
-- The ITEM ID IS THE INDEX, which is only true because ITEM_TM01..ITEM_HM08 is
-- one unbroken run.  So that is the mechanism here too -- and the run being
-- unbroken is asserted rather than assumed, because the cartridge gets to
-- assume it and a cache does not.
--
-- The NAMES are then the check on the ids instead of a second mechanism: TM01
-- must land on index 1 and HM01 on index 92 + 1, and if any name disagrees
-- with where its id put it, nothing is stamped.  A wrong split point does not
-- fail, it teaches Rock Climb where it should teach Focus Punch.
--
-- `kind` is the TM/HM half the index falls in.  The cartridge asks
-- `Item_IsHMMove(move)` -- it scans the last NUM_HMS entries of the array for
-- the MOVE -- which is the same answer only while no move sits in both halves.
-- Measured on Platinum: none does.  The half is used because it is what the
-- wording and the party picker actually want to know, and the check carries
-- the cartridge's question as its own assertion so a cache where the two
-- diverge fails loudly instead of printing "Booted up a TM." for an HM.
--
-- Stamped at LOAD rather than in the extractor, the way
-- `Sprites.markFormsTrueColor` is and for the same reason: an existing cache
-- is fixed without a re-import.  Only `nil` is filled in, so a mod that
-- supplies its own machine record keeps it.
--
-- Returns the number stamped, or 0 with the reason logged.
ItemEffects.ITEM_USE_FUNC_TM_HM = 6

function ItemEffects.markGen4Machines(data)
  local items = data and data.items
  local moves = data and data.constants and data.constants.tmhmMoves
  if type(items) ~= "table" or type(moves) ~= "table" then return 0 end

  -- KEYED BY ID, which is also what collapses the dual publication: `Data`
  -- puts every Gen 4 item in the table under both its numeric id and
  -- `ITEM_nnn`, pointing at one table.  Walking the values counts each machine
  -- twice; walking the ids cannot.
  local byId, lo, hi, n = {}, nil, nil, 0
  for key, def in pairs(items) do
    local id = tonumber(key) or tonumber(tostring(key):match("^ITEM_(%d+)$"))
    if id and type(def) == "table" and byId[id] == nil
       and def.fieldUseFunc == ItemEffects.ITEM_USE_FUNC_TM_HM then
      byId[id] = def
      n = n + 1
      if not lo or id < lo then lo = id end
      if not hi or id > hi then hi = id end
    end
  end
  -- ZERO IS NOT A QUIET ANSWER HERE.  This is only ever called on the Gen 4
  -- branch, and a Platinum cache has a hundred machines; none at all means the
  -- items were imported without `fieldUseFunc`, which looks exactly like the
  -- bug this function exists to fix and would otherwise be reported as it.
  local Logger = require("src.core.Logger")
  if n == 0 then
    Logger.warn("gen4 machines: no item carries use function %d, so the TM/HM "
      .. "flow has nothing to trigger it -- re-import the cache",
      ItemEffects.ITEM_USE_FUNC_TM_HM)
    return 0
  end

  local function refuse(fmt, ...)
    Logger.warn("gen4 machines: " .. fmt
      .. " -- no machine record was stamped", ...)
    return 0
  end

  if n ~= #moves then
    return refuse("%d items carry the TM/HM use function but tmhmMoves has "
      .. "%d entries, so the TM/HM split cannot be placed", n, #moves)
  end
  if hi - lo + 1 ~= n then
    return refuse("the %d machine item ids run %d..%d, which is not one "
      .. "unbroken run, so an id is not an index into tmhmMoves", n, lo, hi)
  end

  -- The TM run's length, read off the names rather than assumed to be 92.
  local tmCount = 0
  for id in pairs(byId) do
    if tostring(byId[id].name or ""):match("^TM%d+$") then
      tmCount = tmCount + 1
    end
  end

  -- IN ID ORDER, so a refusal names the FIRST item that disagrees.  `pairs`
  -- made the message depend on hash order: the same planted fault reported a
  -- different item run to run, which is a diagnostic nobody can act on.
  local ids = {}
  for id in pairs(byId) do ids[#ids + 1] = id end
  table.sort(ids)

  -- The names against the ids, every one of them.
  for _, id in ipairs(ids) do
    local def = byId[id]
    local index = id - lo + 1
    local kind, number = tostring(def.name or ""):match("^([TH]M)(%d+)$")
    if not kind then
      return refuse("item %d carries the TM/HM use function but is named %q",
        id, tostring(def.name))
    end
    local want = (kind == "HM") and (tmCount + tonumber(number))
                 or tonumber(number)
    if want ~= index then
      return refuse("%s is item %d, which is index %d of the machine run, "
        .. "but its name puts it at %d", def.name, id, index, want)
    end
    if (index > tmCount) ~= (kind == "HM") then
      return refuse("%s falls in the %s half of the machine run",
        def.name, index > tmCount and "HM" or "TM")
    end
  end

  local stamped = 0
  for _, id in ipairs(ids) do
    local def = byId[id]
    if def.machine == nil then
      local index = id - lo + 1
      local move = moves[index]
      if move then
        def.machine = { move = move,
                        kind = (index > tmCount) and "HM" or "TM" }
        stamped = stamped + 1
      end
    end
  end
  return stamped
end

function ItemEffects.needsTarget(id, itemDef)
  -- HOENN ASKS FIRST, and this is what opens the party picker.
  --
  -- The list below is Gen 1's and Gen 2's, so an ORAN BERRY answered "no
  -- target needed" and was then used on nobody -- which is a medicine that
  -- silently does nothing however correct the effect behind it is.  A SACRED
  -- ASH is the one that really does not want one: it revives the whole party.
  local r = ItemEffects.recordFor(id)
  if r then
    if r.sacredAsh then return false end
    -- `levelUp` is in the list because Sinnoh's Rare Candy has no name to
    -- match on further down and would otherwise open no party picker --
    -- an item used on nobody.  Hoenn's candy already answered true from
    -- the name list, so this changes nothing there.
    if r.heal or r.revive or r.cures or r.cureAll or r.pp or r.ev
       or r.ppUp or r.ppMax or r.levelUp or r.confusion or r.attract
       or r.evolve then
      return true
    end
  end
  id = alias(id, itemDef)
  return HEAL_AMOUNT[id] or STATUS_HEAL[id] or id == "MAX_POTION"
      or id == "FULL_RESTORE" or id == "REVIVE" or id == "MAX_REVIVE"
      or id == "RARE_CANDY" or STONES[id]
      or (itemDef and itemDef.machine) or id == "ETHER"
      or id == "MAX_ETHER" or id == "ELIXER" or id == "MAX_ELIXER"
      or id == "MYSTERYBERRY"
      or VITAMINS[id] or id == "PP_UP"
end

local function monName(data, mon)
  return mon.nickname or data.pokemon[mon.species].name
end

-- Curing the ACTIVE battler clears its Toxic escalation flag
-- (.cureStatusAilment / trainer_ai.asm AICureStatus both do
-- `res BADLY_POISONED`); the raw w*ToxicCounter is NOT reset by item
-- cures in Gen 1, so battle.sideToxic is deliberately left alone.
local function cureActiveToxic(battle, target)
  if not battle then return end
  for _, b in ipairs({ battle.player, battle.enemy }) do
    if b and b.mon == target then b.toxicCounter = nil end
  end
end

-- battle-only stat boosters (engine/items/item_effects.asm ItemUseXStat)
local X_ITEMS = {
  X_ATTACK = "attack", X_DEFEND = "defense", X_SPEED = "speed",
  X_SPECIAL = "special", X_ACCURACY = "accuracy",
}

-- The two static Snorlax encounters (scripts/Route12.asm, Route16.asm).
-- ItemUsePokeFlute only wakes one when the player is on its route, hasn't
-- beaten it yet, and is standing in one of the four cells orthogonally
-- adjacent to it (Route12SnorlaxFluteCoords/Route16SnorlaxFluteCoords are
-- exactly Snorlax's four neighbors, so a Manhattan distance of 1 from the
-- NPC matches them without hand-listing map coordinates here).
local SNORLAX_ROUTES = {
  ROUTE_12 = { obj = "ROUTE12_SNORLAX", beatFlag = "EVENT_BEAT_ROUTE12_SNORLAX" },
  ROUTE_16 = { obj = "ROUTE16_SNORLAX", beatFlag = "EVENT_BEAT_ROUTE16_SNORLAX" },
}

-- Is the player adjacent to a not-yet-beaten Snorlax on the current map?
-- Returns the map id and NPC to wake it, or nil.
local function adjacentSleepingSnorlax(save, ow)
  local route = ow and ow.map and SNORLAX_ROUTES[ow.map.id]
  if not route or Flags.get(save, route.beatFlag) then return nil end
  local p = ow.player
  if not p then return nil end
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.def and npc.def.name == route.obj then
      if math.abs(p.cellX - npc.cellX) + math.abs(p.cellY - npc.cellY) == 1 then
        return ow.map.id, npc
      end
      return nil
    end
  end
  return nil
end

-- Use an item on a target party mon (target may be nil for targetless
-- items).  data = generated data tables; battle = BattleState when used
-- mid-battle; ow = the overworld (OverworldState), needed only to check
-- Snorlax adjacency for a field-used POKé FLUTE.
-- ---------------------------------------------------------------------------
-- WHAT AN ITEM DOES IN HOENN, off the cartridge rather than off a name
--
-- Every table in this file is Gen 1's and Gen 2's, keyed by a name-derived
-- id.  Emerald's items carry no such key, so they matched by ACCIDENT
-- wherever the slug happened to agree: POTION worked, and ORAN BERRY, SITRUS
-- BERRY, the five status berries, ENERGY POWDER, ENERGY ROOT, HEAL POWDER,
-- REVIVAL HERB, LAVA COOKIE and ZINC did nothing at all.  CALCIUM was worse
-- than nothing -- the Gen 1 table sends it to "special", a stat a Gen 3
-- Pokemon does not have.
--
-- extractItemEffects reads gItemEffectTable into a record a line of code can
-- act on: what it heals, what it cures, which EV it moves and by how much,
-- and what it does to friendship.  This runs that record.
--
-- WHAT IT DELIBERATELY DOES NOT TAKE: an item whose record says only `stone`
-- or only `battle` falls through to the branches below, because the stones
-- already work by name and the X items belong to the battle side.  A RARE
-- CANDY falls through too.  The point is to add Hoenn's items, not to take
-- Johto's away.
-- ---------------------------------------------------------------------------
local GEN3_EV_MAX = 255            -- per stat
local GEN3_EV_TOTAL = 510          -- across the six
local GEN3_EV_ORDER = { "hp", "attack", "defense", "speed", "spatk", "spdef" }

local function gen3Record(data, itemId)
  local c = data and data.constants
  local all = c and c.gen3ItemEffects
  local r = type(all) == "table" and all[itemId] or nil
  if r then return r end
  -- ...and Sinnoh's, decoded from the item's own struct (gen4RecordFor).
  return ItemEffects.gen4RecordFor(itemId, data)
end

-- The friendship a medicine moves, which is a third of the record the port
-- had no way to know about.  Three deltas, chosen by how much the Pokemon
-- already likes you, and the bitter herbs are why they can be negative.
local function gen3Friendship(target, deltas)
  if not (target and type(deltas) == "table" and #deltas > 0) then return end
  local now = math.floor(tonumber(target.happiness) or 0)
  local band = (now < 100) and 1 or ((now < 200) and 2 or 3)
  local delta = deltas[math.min(band, #deltas)]
  if not delta then return end
  target.happiness = math.max(0, math.min(255, now + delta))
end

local function gen3EvTotal(evs)
  local total = 0
  for _, key in ipairs(GEN3_EV_ORDER) do
    total = total + math.floor(tonumber(evs[key]) or 0)
  end
  return total
end

local function gen3Use(data, save, itemId, target, battle, moveIndex)
  local r = gen3Record(data, itemId)
  if not r then return nil end
  -- a stone, an X item or a rare candy is somebody else's branch
  if r.evolve then return nil end
  if not (r.heal or r.revive or r.cures or r.cureAll or r.pp or r.ev
          or r.ppUp or r.ppMax or r.sacredAsh or r.confusion
          or r.attract) then
    return nil
  end
  if r.levelUp then return nil end
  local fail = { Strings("It won't have\nany effect.") }

  -- ---- SACRED ASH: the whole party, not one of them ----------------------
  if r.sacredAsh then
    local woke = false
    for _, mon in ipairs((save and save.party) or {}) do
      if mon and mon.species and (tonumber(mon.hp) or 0) <= 0 then
        mon.hp = (mon.stats and mon.stats.hp) or 1
        mon.status = nil
        woke = true
      end
    end
    if not woke then return "failed", fail end
    return "consumed", { Strings("All of your POKeMON\nwere revived!") }
  end

  if not target then return "failed", fail end
  local fainted = (tonumber(target.hp) or 0) <= 0
  local maxHP = (target.stats and tonumber(target.stats.hp)) or 1

  -- ---- reviving, and the rule that keeps a REVIVE off a healthy one ------
  if r.revive then
    if not fainted then return "failed", fail end
    local before = target.hp or 0
    target.hp = (r.amount == "half") and math.max(1, math.floor(maxHP / 2))
                or maxHP
    target.status = nil
    gen3Friendship(target, r.friendship)
    require("src.core.Sound").play(data, "Heal_HP")
    return "consumed",
           { Strings("%s is\nrevitalized!", monName(data, target)) },
           { healedFrom = before }
  end

  -- ---- healing ------------------------------------------------------------
  if r.heal then
    -- a cure-all that also heals (FULL RESTORE) still works on a Pokemon at
    -- full health, as long as it is carrying something
    local full = target.hp >= maxHP
    if fainted or (full and not ((r.cureAll or r.cures) and target.status)) then
      return "failed", fail
    end
    local before = target.hp
    if not full then
      local by = r.amount
      if by == "all" then
        target.hp = maxHP
      elseif by == "half" then
        target.hp = math.min(maxHP, target.hp + math.floor(maxHP / 2))
      else
        target.hp = math.min(maxHP, target.hp + (tonumber(by) or 0))
      end
    end
    local msgs = { Strings("%s's HP\nwas restored!", monName(data, target)) }
    if r.cureAll or r.cures then
      target.status = nil
      cureActiveToxic(battle, target)
      -- ...AND THE CONFUSION WITH IT.  A FULL RESTORE's effect[3] is $3F --
      -- the whole cure mask, whose bit 0 is ITEM3_CONFUSION -- so the item
      -- that clears the status clears the confusion too.  The cure-only
      -- branch below has always done this; the healing branch was dropping
      -- it, so a FULL RESTORE left a confused Pokemon confused.
      local clears = r.cureAll
      if not clears then
        for _, name in ipairs(r.cures or {}) do
          if name == "CONFUSION" then clears = true end
        end
      end
      if clears and battle then
        for _, b in ipairs({ battle.player, battle.enemy }) do
          if b and b.mon == target then b.confusedTurns = nil end
        end
      end
    end
    gen3Friendship(target, r.friendship)
    require("src.core.Sound").play(data, "Heal_HP")
    return "consumed", msgs, { healedFrom = before }
  end

  -- ---- curing, and nothing else -------------------------------------------
  -- `r.confusion` and `r.attract` are Sinnoh's own bits (gen4RecordFor).
  -- A Persim Berry sets only the first of them, and on a Gen 3 record
  -- neither is ever set, so this arm behaves for Hoenn exactly as before.
  if r.cureAll or r.cures or r.confusion or r.attract then
    local status = target.status
    local confused = nil
    if battle then
      for _, b in ipairs({ battle.player, battle.enemy }) do
        if b and b.mon == target and b.confusedTurns then confused = b end
      end
    end
    local wanted = r.cureAll and status ~= nil
    if not wanted and status then
      for _, name in ipairs(r.cures or {}) do
        if name == status then wanted = true end
      end
    end
    local clearsConfusion = r.cureAll or r.confusion
    if not clearsConfusion then
      for _, name in ipairs(r.cures or {}) do
        if name == "CONFUSION" then clearsConfusion = true end
      end
    end
    if not (wanted or (clearsConfusion and confused)) then
      return "failed", fail
    end
    if wanted then target.status = nil end
    cureActiveToxic(battle, target)
    if clearsConfusion and confused then confused.confusedTurns = nil end
    gen3Friendship(target, r.friendship)
    require("src.core.Sound").play(data, "Heal_Ailment")
    return "consumed",
           { Strings("%s's\nstatus returned\nto normal!",
                     monName(data, target)) }
  end

  -- ---- PP, on one move or on all of them ----------------------------------
  if r.pp then
    local moves = target.moves or {}
    local list = {}
    if r.pp == "one" then
      list[1] = moves[moveIndex or 1]
    else
      for _, mv in ipairs(moves) do list[#list + 1] = mv end
    end
    local moved = false
    for _, mv in ipairs(list) do
      local def = mv and data.moves and data.moves[mv.id]
      local max = def and tonumber(def.pp)
      if max then
        max = max + math.floor(max / 5) * (tonumber(mv.ppUps) or 0)
        if (tonumber(mv.pp) or 0) < max then
          mv.pp = (r.amount == "all") and max
                  or math.min(max, (tonumber(mv.pp) or 0)
                                   + (tonumber(r.amount) or 0))
          moved = true
        end
      end
    end
    if not moved then return "failed", fail end
    gen3Friendship(target, r.friendship)
    return "consumed",
           { Strings("%s's PP\nwas restored!", monName(data, target)) }
  end

  -- ---- PP UP and PP MAX ---------------------------------------------------
  if r.ppUp or r.ppMax then
    local mv = (target.moves or {})[moveIndex or 1]
    local def = mv and data.moves and data.moves[mv.id]
    if not (def and tonumber(def.pp)) then return "failed", fail end
    local ups = math.floor(tonumber(mv.ppUps) or 0)
    if ups >= 3 then return "failed", fail end
    local step = math.floor(tonumber(def.pp) / 5)
    if r.ppMax then
      mv.pp = (tonumber(mv.pp) or 0) + step * (3 - ups)
      mv.ppUps = 3
    else
      mv.pp = (tonumber(mv.pp) or 0) + step
      mv.ppUps = ups + 1
    end
    gen3Friendship(target, r.friendship)
    return "consumed", { Strings("%s's PP\nincreased!", def.name) }
  end

  -- ---- and the effort values, which is where CALCIUM was going wrong ------
  if r.ev then
    target.evs = target.evs or {}
    local now = math.floor(tonumber(target.evs[r.ev]) or 0)
    local by = math.floor(tonumber(r.amount) or 0)
    local want
    if by >= 0 then
      -- the two ceilings: 255 in one stat and 510 across the six
      local room = math.min(GEN3_EV_MAX - now,
                            GEN3_EV_TOTAL - gen3EvTotal(target.evs))
      want = now + math.max(0, math.min(by, room))
    else
      want = math.max(0, now + by)
    end
    if want == now then return "failed", fail end
    target.evs[r.ev] = want
    local okStats, Stats = pcall(require, "src.pokemon.Stats")
    if okStats and data.pokemon and data.pokemon[target.species] then
      pcall(function()
        target.stats = Stats.calc(require('src.pokemon.Gen4Forms').definition(data,target),
                                  target.level,target.ivs,nil,target.evs,target.nature)
        target.hp = math.min(target.hp, target.stats.hp)
      end)
    end
    gen3Friendship(target, r.friendship)
    local label = (r.ev == "hp" and "HP")
                  or (r.ev == "spatk" and "SP. ATK")
                  or (r.ev == "spdef" and "SP. DEF")
                  or r.ev:upper()
    return "consumed",
           { Strings("%s's %s\n%s!", monName(data, target), label,
                     by >= 0 and "rose" or "fell") }
  end

  return nil
end

ItemEffects.gen3Use = gen3Use

function ItemEffects.use(data, save, itemId, target, battle, moveIndex, ow)
  local itemDef = data.items[itemId]
  local name = itemDef and itemDef.name or itemId
  local rawItemId = itemId
  itemId = alias(itemId, itemDef)
  -- SINNOH'S RARE CANDY HAS NO NAME TO MATCH ON.  `alias` answers
  -- "ITEM_050" for it, so the branch that raises a level -- which is
  -- already written, already uses the Gen 3 stat formula and already fires
  -- the follower's happiness step -- was unreachable.  The cartridge's own
  -- struct says the item levels up; that is what opens the same door.
  local gen4LevelUp = false
  do
    local g4 = ItemEffects.gen4RecordFor(itemDef, data)
    gen4LevelUp = (g4 and g4.levelUp) or false
  end

  -- ItemUseVitamin / ItemUsePPUp / ItemUseEvoStone / ItemUseCoinCase /
  -- ItemUseTMHM all refuse mid-battle (jp nz, ItemUseNotTime)
  if battle and (VITAMINS[itemId] or STONES[itemId] or itemId == "PP_UP"
                 or itemId == "RARE_CANDY" or gen4LevelUp
                 or itemId == "COIN_CASE"
                 or (itemDef and itemDef.machine)) then
    return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!",
                               save.player.name) }
  end

  if ItemEffects.isBall(itemId, itemDef) or ItemEffects.isBall(rawItemId, itemDef) then
    return "ball"
  end

  -- HOENN'S OWN ANSWER FIRST, when the cartridge gave one.  Everything below
  -- is Gen 1's and Gen 2's, keyed by a name Emerald's items do not carry.
  do
    local kind, msgs, extra = gen3Use(data, save, rawItemId, target, battle,
                                      moveIndex)
    if kind then return kind, msgs, extra end
  end


  -- The POKé FLUTE wakes every sleeping Pokémon on both sides
  -- (ItemUsePokeFlute, engine/items/item_effects.asm); never consumed.
  if itemId == "POKE_FLUTE" then
    if not battle then
      -- standing next to a not-yet-beaten Snorlax: this is the ONLY way
      -- Snorlax wakes -- using the flute from the item-use menu, never
      -- just talking to it with the flute in the bag (see
      -- data/scripts/story.lua's snorlaxWake)
      local mapId, npc = adjacentSleepingSnorlax(save, ow)
      if npc then
        return "flute_wake", { data.text._PlayedFluteHadEffectText
          or Strings("{PLAYER} played the\nPOKé FLUTE.") },
          { mapId = mapId, npc = npc }
      end
      -- otherwise: play the tune, nothing happens (ItemUsePokeFlute's
      -- PlayedFluteNoEffectText branch)
      return "flute_field", { Strings("Played the POKé\nFLUTE.\fNow, that's a\ncatchy tune!") }
    end
    local woke = false
    local function wake(mon)
      if mon and mon.status == "SLP" then
        mon.status = nil
        woke = true
      end
    end
    for _, mon in ipairs(save.party) do wake(mon) end
    wake(battle.player and battle.player.mon)
    wake(battle.enemy and battle.enemy.mon)
    -- WakeUpEntireParty runs on the enemy's bench too
    for _, mon in ipairs(battle.enemyParty or {}) do wake(mon) end
    if not woke then
      return "failed", { Strings("Played the POKé\nFLUTE.\fNow, that's a\ncatchy tune!") }
    end
    return "flute", { Strings("%s played the\nPOKé FLUTE.", save.player.name),
                      Strings("All sleeping\nPOKéMON woke up!") }
  end

  -- battle-only items
  if X_ITEMS[itemId] or itemId == "DIRE_HIT" or itemId == "GUARD_SPEC"
     or itemId == "POKE_DOLL" then
    if not battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    local b = battle.player
    -- PIKAHAPPY_USEDXITEM (item_effects.asm ItemUseXAccuracy /
    -- GuardSpec / DireHit / XStat) on the active companion
    if itemId ~= "POKE_DOLL" then
      require("src.world.PikachuFollower")
        .modifyHappiness(save, "USEDXITEM", b and b.mon)
    end
    if itemId == "X_ACCURACY" then
      -- ItemUseXAccuracy sets USING_X_ACCURACY: moves never miss
      -- (not an accuracy stage)
      b.xAccuracy = true
      return "consumed", { Strings("%s's\nhits will never\nmiss!", b.name) }
    end
    if X_ITEMS[itemId] then
      local stat = X_ITEMS[itemId]
      local cur = b.stages[stat] or 0
      -- ItemUseXStat removes the item BEFORE running the stat-up
      -- effect, so at +6 it is still consumed and StatModifierUpEffect
      -- just prints "Nothing happened!"
      if cur >= 6 then
        return "consumed", { Strings("Nothing happened!") }
      end
      b.stages[stat] = cur + 1
      return "consumed", { Strings("%s's\n%s rose!", b.name, stat:upper()) }
    end
    -- ItemUseDireHit/ItemUseGuardSpec always set the bit and consume
    -- the item, even when it is already active
    if itemId == "DIRE_HIT" then
      b.focusEnergy = true
      return "consumed", { Strings("%s's\ngetting pumped!", b.name) }
    end
    if itemId == "GUARD_SPEC" then
      b.mist = true
      return "consumed", { Strings("%s's\nprotected against\nstat changes!", b.name) }
    end
    if itemId == "POKE_DOLL" then
      if battle.kind ~= "wild" then
        -- ItemUsePokeDoll jumps to ItemUseNotTime in trainer battles
        return "failed", { Strings(
          "OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
      end
      return "consumed_escape", { Strings("The wild POKéMON\nran away!") }
    end
  end

  -- PP restores.  The ETHERs restore the move the player picked
  -- (moveIndex, from the ItemUsePPRestore move menu); the ELIXERs
  -- restore every move with no menu.
  if itemId == "ETHER" or itemId == "MAX_ETHER"
     or itemId == "ELIXER" or itemId == "MAX_ELIXER"
     or itemId == "MYSTERYBERRY" then
    if not target then return "failed", { Strings("It won't have\nany effect.") } end
    local restored = false
    local full = itemId == "MAX_ETHER" or itemId == "MAX_ELIXER"
    local allMoves = itemId == "ELIXER" or itemId == "MAX_ELIXER"
    -- MYSTERYBERRY is a 5 PP single-move restore (data/items/attributes.asm)
    local amount = itemId == "MYSTERYBERRY" and 5 or 10
    local function restore(mv)
      local mdef = data.moves[mv.id]
      local maxPP = mdef and (mdef.pp + (mv.ppUps or 0) * math.floor(mdef.pp / 5))
      if maxPP and mv.pp < maxPP then
        mv.pp = full and maxPP or math.min(maxPP, mv.pp + amount)
        return true
      end
      return false
    end
    if allMoves then
      for _, mv in ipairs(target.moves) do
        restored = restore(mv) or restored
      end
    else
      local mv = target.moves[moveIndex or 1]
      restored = mv and restore(mv) or false
    end
    if not restored then
      return "failed", { Strings("It won't have\nany effect.") }
    end
    return "consumed", { Strings("%s's PP\nwas restored!", monName(data, target)) }
  end

  -- PIKAHAPPY_USEDITEM (item_effects.asm ItemUseMedicine, item id up to
  -- CALCIUM): fires once a medicine has a target, before the effect
  -- resolves -- potions, status cures, revives and vitamins all count,
  -- RARE_CANDY does not (its success is a LEVELUP bump instead)
  if target and (HEAL_AMOUNT[itemId] or STATUS_HEAL[itemId]
                 or itemId == "MAX_POTION" or itemId == "FULL_RESTORE"
                 or itemId == "REVIVE" or itemId == "MAX_REVIVE"
                 or VITAMINS[itemId]) then
    require("src.world.PikachuFollower")
      .modifyHappiness(save, "USEDITEM", target)
  end

  local heal = HEAL_AMOUNT[itemId]
  if heal or itemId == "MAX_POTION" or itemId == "FULL_RESTORE" then
    -- a FULL RESTORE on a statused mon already at full HP acts as a
    -- Full Heal: cured, consumed, ailment sound (item_effects.asm
    -- swaps wCurItem to FULL_HEAL and jumps to .cureStatusAilment)
    if itemId == "FULL_RESTORE" and target and target.hp > 0
       and target.hp >= target.stats.hp and target.status then
      target.status = nil
      cureActiveToxic(battle, target)
      require("src.core.Sound").play(data, "Heal_Ailment")
      return "consumed", { Strings("%s's\nstatus returned\nto normal!", monName(data, target)) }
    end
    if not target or target.hp <= 0 or target.hp >= target.stats.hp then
      return "failed", { Strings("It won't have\nany effect.") }
    end
    -- wHPBarOldHP: the bar animation starts from the HP the mon had BEFORE
    -- the item landed (item_effects.asm latches it with the party menu still
    -- up), so latch it here and hand it back as extra.healedFrom for the
    -- party-menu fill (#252)
    local before = target.hp
    if itemId == "MAX_POTION" or itemId == "FULL_RESTORE" then
      target.hp = target.stats.hp
    else
      target.hp = math.min(target.stats.hp, target.hp + heal)
    end
    local msgs = { Strings("%s's HP\nwas restored!", monName(data, target)) }
    if itemId == "FULL_RESTORE" then
      target.status = nil
      cureActiveToxic(battle, target)
    end
    require("src.core.Sound").play(data, "Heal_HP")
    return "consumed", msgs, { healedFrom = before }
  end

  local cures = STATUS_HEAL[itemId]
  if cures then
    -- BITTER BERRY / MIRACLEBERRY / FULL HEAL also clear the confusion
    -- volatile, which lives on the battler rather than the party mon.
    local confused = nil
    if battle and CURES_CONFUSION[itemId] then
      for _, b in ipairs({ battle.player, battle.enemy }) do
        if b and b.mon == target and b.confusedTurns then confused = b end
      end
    end
    if not target or ((not target.status or not cures[target.status])
                      and not confused) then
      return "failed", { Strings("It won't have\nany effect.") }
    end
    if confused then confused.confusedTurns = nil end
    target.status = nil
    cureActiveToxic(battle, target)
    require("src.core.Sound").play(data, "Heal_Ailment")
    return "consumed", { Strings("%s's\nstatus returned\nto normal!", monName(data, target)) }
  end

  if itemId == "REVIVE" or itemId == "MAX_REVIVE" then
    if not target or target.hp > 0 then
      return "failed", { Strings("It won't have\nany effect.") }
    end
    target.status = nil
    target.hp = itemId == "REVIVE" and math.floor(target.stats.hp / 2) or target.stats.hp
    require("src.core.Sound").play(data, "Heal_HP")
    -- a revive takes the same .healHP -> .doneHealing route, animating up
    -- from the fainted mon's 0 HP (#252)
    return "consumed", { Strings("%s\nis revitalized!", monName(data, target)) },
           { healedFrom = 0 }
  end

  if itemId == "RARE_CANDY" or gen4LevelUp then
    if not target or target.level >= 100 then
      return "failed", { Strings("It won't have\nany effect.") }
    end
    local Growth = require("src.pokemon.Growth")
    local Stats = require("src.pokemon.Stats")
    local speciesDef = require('src.pokemon.Gen4Forms').definition(data,target)
    target.level = target.level + 1
    target.exp = Growth.expForLevel(speciesDef.growthRate, target.level)
    local old = target.stats
    -- A Gen 3 party mon carries six IVs, six EVs and a nature.  Passing its
    -- (non-existent) DV/stat-exp fields through the legacy helper recalculated
    -- a Rare Candy level with zero IVs/EVs and no nature, even though battle
    -- level-ups already use the proper Gen 3 path.  Keep item level-ups on the
    -- same formula as every other FireRed level-up.
    if Stats.isGen3(speciesDef) then
      target.stats = Stats.calcGen3(speciesDef, target.level, target.ivs,
                                    target.evs, target.nature)
    else
      target.stats = Stats.calc(speciesDef, target.level, target.dvs,
                                target.statExp)
    end
    target.hp = math.min(target.stats.hp, target.hp + (target.stats.hp - old.hp))
    -- PIKAHAPPY_LEVELUP on a candy level (item_effects.asm:1540)
    require("src.world.PikachuFollower")
      .modifyHappiness(save, "LEVELUP", target)
    return "consumed", { Strings("%s grew\nto level %d!", monName(data, target), target.level) },
           { leveledTo = target.level, beforeStats = old,
             afterStats = target.stats }
  end

  -- ...AND SINNOH'S STONES HAVE NO NAME TO MATCH ON EITHER.  `STONES` is a
  -- list of Gen 1/2 spellings; a Platinum Fire Stone answers "ITEM_082".
  -- Its record carries `evolve`, which is the cartridge's own word for
  -- exactly this branch -- the Dawn, Dusk, Shiny and Oval stones come with
  -- it, and they are four evolution families Sinnoh could not reach.
  local gen4Stone = false
  do
    local g4 = ItemEffects.gen4RecordFor(itemDef, data)
    gen4Stone = (g4 and g4.evolve) or false
  end
  if STONES[itemId] or gen4Stone then
    if not target then return "failed", { Strings("It won't have\nany effect.") } end
    -- Yellow's starter Pikachu never evolves: ItemUseEvoStone runs
    -- IsThisPartyMonStarterPikachu (OT identity match) before
    -- TryEvolvingMon and bails with the voiced cry + RefusingText.
    -- The stone is NOT consumed on the refuse path.
    if target.species == "PIKACHU"
       and require("src.core.GameVersion").isYellow()
       and target.ot == save.player.name
       and target.otId == save.player.id then
      require("src.core.Sound").playCry(data, "PIKACHU")
      local raw = data.text and data.text._RefusingText
      local line = raw and raw:gsub("{RAM:[^}]*}", monName(data, target))
        or Strings("%s\nis refusing!", monName(data, target))
      return "failed", { line }
    end
    local speciesDef = require('src.pokemon.Gen4Forms').definition(data,target)
    for _, evo in ipairs(speciesDef.evolutions) do
      if evo.method == "ITEM" and (evo.item == itemId or evo.item == rawItemId) then
        return "consumed", nil, { evolveTo = evo.species }
      end
    end
    return "failed", { Strings("It won't have\nany effect.") }
  end

  -- vitamins: +2560 stat exp, refused at 25600+ (ItemUseVitamin,
  -- engine/items/item_effects.asm)
  local vitaminStat = VITAMINS[itemId]
  if vitaminStat then
    if not target then return "failed", { Strings("It won't have\nany effect.") } end
    target.statExp = target.statExp or {}
    local cur = target.statExp[vitaminStat] or 0
    if cur >= 25600 then
      return "failed", { Strings("It won't have\nany effect.") }
    end
    target.statExp[vitaminStat] = math.min(65535, cur + 2560)
    local Stats = require("src.pokemon.Stats")
    target.stats = Stats.calc(data.pokemon[target.species], target.level,
                              target.dvs, target.statExp)
    target.hp = math.min(target.hp, target.stats.hp)
    return "consumed", { Strings("%s's %s\nrose!", monName(data, target),
      vitaminStat == "hp" and "HP" or vitaminStat:upper()) }
  end

  -- PP UP boosts the move the player picked (ItemUsePPUp's move menu)
  if itemId == "PP_UP" then
    if not target then return "failed", { Strings("It won't have\nany effect.") } end
    local mv = target.moves[moveIndex or 1]
    local mdef = mv and data.moves[mv.id]
    if mdef and (mv.ppUps or 0) < 3 then
      mv.ppUps = (mv.ppUps or 0) + 1
      -- each PP UP adds maxPP/5 uses on top of the base maximum
      mv.pp = mv.pp + math.floor(mdef.pp / 5)
      return "consumed", { Strings("%s's PP\nincreased!", mdef.name) }
    end
    return "failed", { Strings("It won't have\nany effect.") }
  end

  if itemDef and itemDef.machine then
    if not target then return "failed", { Strings("It won't have\nany effect.") } end
    local speciesDef = require('src.pokemon.Gen4Forms').definition(data,target)
    local ok = false
    -- `or {}` BECAUSE A CACHE CAN ARRIVE WITHOUT THE LIST, and this line
    -- raised when one did. Every Platinum cache written before the Gen 4
    -- extractor learned to unpack the 128-bit machine mask has `tmLearnset`
    -- and no `tmhm`, so `ipairs(nil)` took the game down the moment a TM was
    -- used in Sinnoh. The fallback answer is "cannot learn", which is the safe
    -- half of the two: a machine that refuses is a stale cache, a machine that
    -- teaches off an empty list would be teaching anything to anything.
    for _, m in ipairs((speciesDef and speciesDef.tmhm) or {}) do
      if m == itemDef.machine.move then ok = true break end
    end
    if not ok then
      -- the only item-use refusal with a sound in pokered: item_effects.asm
      -- plays SFX_DENIED before MonCannotLearnMachineMoveText (the generic
      -- ItemUseNotTime/NoCyclingAllowedHere paths are silent)
      require("src.core.Sound").play(data, "Denied")
      return "failed", { Strings("%s can't\nlearn that move!", monName(data, target)) }
    end
    for _, mv in ipairs(target.moves) do
      if mv.id == itemDef.machine.move then
        return "failed", { Strings("It knows that\nmove already!") }
      end
    end
    -- HMs are never consumed; TMs are single-use
    return (itemDef.machine.kind == "HM" and "learnkept" or "learn"), itemDef.machine.move
  end

  if itemId == "OLD_ROD" or itemId == "GOOD_ROD" or itemId == "SUPER_ROD" then
    if battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    -- FishingInit (engine/items/item_effects.asm): cp wWalkBikeSurfState, 2
    -- (surfing) sets carry, and every ItemUseXRod does jp c, ItemUseNotTime
    -- on that carry -- surfing refuses the rod with the same OAK text as
    -- the mid-battle case above, no rod-specific message (#533)
    if ow and ow.player and ow.player.surfing then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    return "fish", itemId
  end

  -- HOENN HAS TWO BIKES, AND THE BAG KNEW NEITHER.
  --
  -- Everything the Acro Bike needs was already written -- Collision's five
  -- obstacle behaviours, acroTrickPasses, the extractor's bikeBehaviours --
  -- and that rule's own comment said it was "already here and already
  -- tested, instead of a `return false` nobody remembers to revisit".  What
  -- was missing was smaller and further out: this line knew only the Game
  -- Boy's item id, so the two bikes Rydel gives you did nothing when used.
  --
  -- With no Acro Bike, Jagged Pass's bumpy-slope cells are a wall, and past
  -- them are Mt. Chimney and the Magma Hideout.
  if itemId == "BICYCLE" or itemId == "MACH_BIKE" or itemId == "ACRO_BIKE" then
    if battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    -- WHICH one, so the overworld can set the rider's own rules: the Mach
    -- Bike climbs muddy slopes at speed, and the Acro Bike hops and
    -- wheelies over what stops everyone else
    return "bicycle", (itemId == "ACRO_BIKE" and "acro")
                      or (itemId == "MACH_BIKE" and "mach") or nil
  end

  if itemId == "ESCAPE_ROPE" then
    return "escape_rope"
  end
  -- THE POKeBLOCK CASE, which is the only way into the condition system from
  -- the bag.  It is a key item like the bike and the map, and it opens a
  -- screen rather than doing anything to the world.
  if itemId == "POKEBLOCK_CASE" then
    if battle then
      return "failed", { Strings("This isn't the time to use that!") }
    end
    return "pokeblock_case"
  end
  -- THE EXPLORER KIT, and it is found by the cartridge's own dispatch index
  -- rather than by item 428.  A Platinum item record carries `fieldUseFunc`,
  -- which indexes `sItemUseFuncs` (item_use_functions.c), and slot 3 is
  -- `ITEM_USE_FUNC_EXPLORER_KIT` = { UseExplorerKitFromMenu,
  -- UseExplorerKitInField, CanUseExplorerKit }.  Keying on the number is what
  -- the cartridge does, it survives a re-extraction that renumbers nothing,
  -- and it cannot match in Gen 1, 2 or 3 -- no item record in those datasets
  -- has the field at all, so this arm is unreachable there by construction
  -- rather than by a version test bolted on the front.
  --
  -- Whether the kit may be used HERE is eight separate questions and they live
  -- with the Underground (Gen4Underground.canUse), not here: this line only
  -- says which item was used.
  if itemDef and itemDef.fieldUseFunc == ITEM_USE_FUNC_EXPLORER_KIT then
    if battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!",
                                 save.player.name) }
    end
    return "explorer_kit"
  end
  if itemId == "TOWN_MAP" then
    if battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    return "townmap"
  end
  if itemId == "ITEMFINDER" then
    if battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    return "itemfinder"
  end
  if itemId == "VS_SEEKER" then
    if battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    return "vs_seeker"
  end
  -- FireRed's TEACHY TV is a real key-item screen, not an inert key item.
  -- ItemUseOutOfBattle_TeachyTv switches main callbacks to teachy_tv.c; the
  -- bag only needs to identify that request and let the UI own the tutorial.
  if itemId == "TEACHY_TV" then
    if battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
    end
    return "teachy_tv"
  end
  if itemId == "COIN_CASE" then
    return "failed", { Strings("Coin count:\n%d", save.coins or 0) }
  end
  if itemId == "REPEL" or itemId == "SUPER_REPEL" or itemId == "MAX_REPEL" then
    local steps = itemId == "REPEL" and 100 or itemId == "SUPER_REPEL" and 200 or 250
    save.repelSteps = steps
    return "consumed", { Strings("%s used\n%s!", save.player.name, name) }
  end

  return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!", save.player.name) }
end

return ItemEffects
