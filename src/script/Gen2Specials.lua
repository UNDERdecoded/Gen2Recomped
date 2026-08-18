-- The rest of the Gen2 SpecialsPointers table.
--
-- Gen2Commands.lua carries the specials the port grew handlers for one at a
-- time -- the phone, the Day-Care, the Bug Contest, the Battle Tower.  This
-- file is the remainder, taken in one pass: every label that Gen2ScriptVM's
-- `L.special` was still falling through to `g2_special` on any of the three
-- cartridges the port imports (Crystal, Gold, Prism).
--
-- Why the fall-through mattered, and not just for the log line: g2_special
-- answers `ctx.lastCheck = false` and leaves `ctx.g2Var` HOLDING WHATEVER THE
-- LAST ROW PUT THERE.  A special standing between a checkevent and its iftrue
-- therefore flipped the branch, and one standing between a `setval` and an
-- `ifequal` let a stale value through.  Roughly half the call sites counted
-- here are the cable club and the mobile adapter, which the port cannot have
-- at all; those now answer a definite 0/false (g2_unavailable) rather than a
-- stale one.
--
-- Loaded for its side effects on the Commands table, like Gen2Commands.

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local Gen2Specials = {}

-- wScriptVar plus the `iftrue`/`iffalse` companion the ROM reads off it.
local function answer(ctx, value)
  value = math.floor(value or 0) % 256
  ctx.g2Var = value
  ctx.lastCheck = value ~= 0
  return value
end

local function speciesKey(n)
  return string.format("SPECIES_%03d", math.floor(n or 0) % 256)
end

local function speciesNumber(mon)
  if not mon then return 0 end
  if type(mon.species) == "number" then return mon.species end
  return tonumber(tostring(mon.species or ""):match("(%d+)$")) or 0
end

local function speciesName(ctx, species)
  local def = species and (ctx.game.data.pokemon or {})[species]
  return (def and def.name) or tostring(species)
end

local function monName(ctx, mon)
  if not mon then return "POKéMON" end
  return mon.nickname or speciesName(ctx, mon.species)
end

-- A ROM text label if the cartridge actually carries it, otherwise a literal.
-- show_text falls back to printing its argument verbatim when the label
-- misses, so handing it a label the dataset lacks prints the LABEL.
local function line(ctx, label, fallback)
  local text = ctx.game.data and ctx.game.data.text
  if label and text and text[label] then return label end
  return fallback
end

local function say(ctx, label, fallback, subs)
  Commands.show_text(ctx, line(ctx, label, fallback), subs)
end

-- text_ram tokens, filled POSITIONALLY.
--
-- `{RAM:D073}` is wStringBuffer1 -- on CRYSTAL.  Gold's WRAM map is shifted,
-- so the same buffer decodes to a different address and a hard-coded token
-- name matches on one cartridge and silently misses on the other (the
-- Magikarp record sign, which carries two of them, printed the raw token in
-- Gold).  The ROM fills these buffers in the order the line reads them, so
-- filling them in the order they appear is both correct and portable.
local function sayRam(ctx, label, fallback, values)
  local id = line(ctx, label, fallback)
  local text = (ctx.game.data.text or {})[id]
  if type(text) ~= "string" then return Commands.show_text(ctx, id) end
  local index, subs = 0, {}
  for token in text:gmatch("{(RAM:[%w_]+)}") do
    index = index + 1
    if values[index] ~= nil and subs[token] == nil then
      subs[token] = tostring(values[index])
    end
  end
  Commands.show_text(ctx, id, next(subs) and subs or nil)
end

-- opentext/yesorno without the script rows: used by the specials that ask
-- their own question (the tutors, the bank, Buena's prizes).
local function confirm(ctx, label, fallback, subs)
  local runner = ctx.runner
  Commands.show_text(ctx, line(ctx, label, fallback), subs, {
    choice = function(yes) ctx.lastCheck = yes runner:resume() end,
  })
  return ctx.lastCheck
end

-- A blocking list menu.
--
-- Menu:update POPS the menu and only THEN runs the row's onSelect, and it
-- calls opts.onCancel on B alone -- so a script that pushes a Menu and yields
-- has to resume from BOTH paths or it hangs with the menu already gone.  Rows
-- are { label, right, value }; the chosen value comes back, nil for B.
local function menuPick(ctx, rows, opts)
  local runner = ctx.runner
  local chosen, done
  local function finish()
    if done then return end
    done = true
    runner:resume()
  end
  local items = {}
  for index, row in ipairs(rows) do
    items[index] = { label = row.label, right = row.right, onSelect = function()
      chosen = row.value
      finish()
    end }
  end
  opts = opts or {}
  opts.onCancel = finish
  require("src.ui.Screens").push(ctx.game, "Menu", items, opts)
  runner:yield()
  return chosen
end

-- SelectMonFromParty (engine/pokemon/party_menu.asm): the party list in
-- "pick one" mode.  nil means the player backed out with B.
local function pickMon(ctx)
  local game, runner = ctx.game, ctx.runner
  if not (game and runner) then return nil end
  local picked
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onCancel = function() runner:resume() end,
    onSwitch = function(mon) picked = mon runner:resume() end,
  })
  runner:yield()
  return picked
end

-- CheckOwnMonAnywhere (engine/pokemon/search_owned.asm): party OR any box,
-- and the mon has to carry the player's own OT name and ID -- a traded one
-- does not count.  Eggs are skipped: their slot species is the hatchling's.
local function ownsAnywhere(ctx, key)
  local save = ctx.save
  local Party = require("src.pokemon.Party")
  local player = save.player or {}
  local function match(mon)
    if not mon or mon.species ~= key then return false end
    if Party.isEgg(mon) then return false end
    local ownName = mon.ot == nil or mon.ot == player.name
    local ownId = mon.otId == nil or mon.otId == player.id
    return ownName and ownId
  end
  for _, mon in ipairs(save.party or {}) do
    if match(mon) then return true end
  end
  local Boxes = require("src.pokemon.Boxes")
  for _, box in ipairs(Boxes.ensure(save)) do
    for _, mon in ipairs(box) do
      if match(mon) then return true end
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- The link cable, the mobile adapter, and Mystery Gift
--
-- Two Game Boys is the one thing a single-player recompilation cannot fake, so
-- every row here is a definite "no".  That is also what the cartridge answers
-- when nothing is plugged in: CheckLinkTimeout_Receptionist, AskMobileOrCable
-- and CheckMobileAdapterStatusSpecial all write 0 to wScriptVar on failure,
-- and the receptionist scripts branch straight back to "please come again".
--
-- 110-odd call sites across Crystal and Gold reach this, so it is by a wide
-- margin the biggest single group in the table.
-- ---------------------------------------------------------------------------

function Commands.g2_unavailable(ctx)
  answer(ctx, 0)
end

-- ---------------------------------------------------------------------------
-- Party and box checks
-- ---------------------------------------------------------------------------

-- CheckFirstMonIsEgg (engine/events/happiness_egg.asm).  Elm's aide and the
-- Day-Care both open with this; unlowered they took the "you're not carrying
-- an EGG" arm even with one in the lead slot.  It also fills the name buffer,
-- which is what the line right after it prints.
function Commands.g2_check_first_mon_egg(ctx)
  local Party = require("src.pokemon.Party")
  local first = (ctx.save.party or {})[1]
  local egg = first ~= nil and Party.isEgg(first)
  ctx.game.stringBuffer = egg and "EGG" or (first and speciesName(ctx, first.species))
  answer(ctx, egg and 1 or 0)
end

-- MonCheck (engine/pokemon/search_owned.asm): does the player own the species
-- in wScriptVar, anywhere, raised themselves?  Seven call sites, all of them
-- NPCs who react to a particular mon.
function Commands.g2_mon_check(ctx)
  answer(ctx, ownsAnywhere(ctx, speciesKey(ctx.g2Var)) and 1 or 0)
end

-- BeastsCheck: Raikou, Entei AND Suicune, all three, same ownership rule.
-- (Eusine in Celadon.)
function Commands.g2_beasts_check(ctx)
  local all = ownsAnywhere(ctx, "SPECIES_243")
    and ownsAnywhere(ctx, "SPECIES_244")
    and ownsAnywhere(ctx, "SPECIES_245")
  answer(ctx, all and 1 or 0)
end

-- FindPartyMonThatSpecies: the party only, and ownership does not matter --
-- the "...YourTrainerID" variant next door is the strict one, and the port
-- already has that as g2_find_party_species_own.
function Commands.g2_find_party_species(ctx)
  local Party = require("src.pokemon.Party")
  local want = speciesKey(ctx.g2Var)
  for _, mon in ipairs(ctx.save.party or {}) do
    if mon.species == want and not Party.isEgg(mon) then return answer(ctx, 1) end
  end
  answer(ctx, 0)
end

-- FindPartyMonAboveLevel / FindPartyMonAtLeastThatHappy: the same shape, and
-- listed here because Prism's scripts reach them under Special_ names.
function Commands.g2_find_party_above_level(ctx)
  local Party = require("src.pokemon.Party")
  local level = ctx.g2Var or 0
  for _, mon in ipairs(ctx.save.party or {}) do
    if not Party.isEgg(mon) and (mon.level or 0) >= level then return answer(ctx, 1) end
  end
  answer(ctx, 0)
end

function Commands.g2_find_party_happy(ctx)
  local Party = require("src.pokemon.Party")
  local want = ctx.g2Var or 0
  for _, mon in ipairs(ctx.save.party or {}) do
    if not Party.isEgg(mon) and (mon.happiness or 0) >= want then return answer(ctx, 1) end
  end
  answer(ctx, 0)
end

-- GameCornerPrizeMonCheckDex (engine/events/specials.asm): the prize corner
-- hands the mon over with `givepoke` and then runs this, which is what shows
-- the "new POKéDEX data" page for a species the player has never met.  The
-- variable is 1-BASED (`dec a` before CheckCaughtMon), and it is read after
-- the mon is already in the party, so the dex marks are the point.
-- Fifteen call sites -- every prize in both game corners.
function Commands.g2_prize_mon_dex(ctx)
  local key = speciesKey(ctx.g2Var)
  local dex = ctx.save.pokedex
  if not dex then return end
  dex.seen, dex.owned = dex.seen or {}, dex.owned or {}
  if dex.owned[key] then return end
  dex.seen[key], dex.owned[key] = true, true
  -- NewPokedexEntry: the entry page, then back to the script.  Pushed rather
  -- than yielded on, exactly like g2_card_flip -- the calling script has
  -- nothing after it but closetext/end.
  require("src.ui.Screens").push(ctx.game, "DexEntryMenu", key)
end

-- ---------------------------------------------------------------------------
-- Small state pokes
-- ---------------------------------------------------------------------------

-- GameboyCheck: 0 = DMG, 1 = SGB, 2 = CGB.  The port renders the CGB build,
-- so the honest answer is 2 -- and the scripts that ask are the ones deciding
-- whether to offer colour content at all.
function Commands.g2_gameboy_check(ctx)
  answer(ctx, 2)
end

-- ActivateFishingSwarm: stores wScriptVar in wFishingSwarmFlag.  The port has
-- no swarm tables (see g2_swarm), so record it the same way rather than lose
-- the request -- a save that armed a swarm keeps reporting it.
function Commands.g2_activate_fishing_swarm(ctx)
  ctx.save.g2FishSwarm = ctx.g2Var or 0
end

-- SampleKenjiBreakCountdown (engine/overworld/time.asm): a random 3-6 that
-- decides how many days until the Route 39 trainer takes his break.
function Commands.g2_kenji_countdown(ctx)
  ctx.save.g2KenjiBreak = math.random(3, 6)
end

-- CheckCaughtCelebi: reads the battle-result bit the Celebi encounter sets.
function Commands.g2_check_caught_celebi(ctx)
  answer(ctx, ctx.save.g2CaughtCelebi and 1 or 0)
end

-- ---------------------------------------------------------------------------
-- GiveDratini (engine/events/dratini.asm)
--
-- The Dragon's Den elder's gift.  wScriptVar picks the moveset: 0 is the
-- Extremespeed reward for answering his quiz well, 1 the ordinary level-15
-- set.  It rewrites the LAST Dratini in the party, searching backwards, which
-- matters because the script gives the mon first and calls this after.
-- ---------------------------------------------------------------------------

local DRATINI_MOVESETS = {
  [0] = { "WRAP", "THUNDER_WAVE", "TWISTER", "EXTREMESPEED" },
  [1] = { "WRAP", "THUNDER_WAVE", "TWISTER", "DRAGON_RAGE" },
}

function Commands.g2_give_dratini(ctx)
  local set = DRATINI_MOVESETS[ctx.g2Var or 0]
  if not set then return end
  local moves = ctx.game.data.moves or {}
  for index = #(ctx.save.party or {}), 1, -1 do
    local mon = ctx.save.party[index]
    if mon and speciesNumber(mon) == 147 then -- DRATINI
      mon.moves = {}
      for _, id in ipairs(set) do
        local def = moves[id]
        if def then
          mon.moves[#mon.moves + 1] = { id = id, pp = def.pp or 5, ppUps = 0 }
        end
      end
      return
    end
  end
end

-- ---------------------------------------------------------------------------
-- CheckPartyFullAfterContest (engine/pokemon/caught_data.asm)
--
-- The Bug Contest's one caught mon goes to the party, or to a box when the
-- party is full, or nowhere when every box is full too.  wScriptVar reports
-- which: 0 BUGCONTEST_CAUGHT_MON, 1 BUGCONTEST_BOXED_MON, 2 BUGCONTEST_NO_CATCH.
-- Six call sites -- the gate scripts branch on all three.
-- ---------------------------------------------------------------------------

function Commands.g2_contest_party_full(ctx)
  local BugContest = require("src.world.BugContest")
  local mon = BugContest.caught(ctx.save)
  if not mon then return answer(ctx, 2) end
  local Party = require("src.pokemon.Party")
  ctx.game.stringBuffer = monName(ctx, mon)
  if Party.add(ctx.save.party, mon) then
    BugContest.setCaught(ctx.save, nil)
    return answer(ctx, 0)
  end
  if require("src.pokemon.Boxes").deposit(ctx.save, mon) then
    BugContest.setCaught(ctx.save, nil)
    return answer(ctx, 1)
  end
  answer(ctx, 2)
end

-- ---------------------------------------------------------------------------
-- The Magikarp length guru  (engine/events/magikarp.asm)
--
-- CalcMagikarpLength derives the length in millimetres from the mon's DVs and
-- its ORIGINAL TRAINER ID, then converts to feet and inches.  Reproduced
-- byte-for-byte below, INCLUDING the .BCLessThanDE bug: that routine does
-- `cp d / ret c / ret nc`, so it returns on the high byte alone and the low
-- byte is never compared.  Fixing it here would give lengths the cartridge
-- never prints, and the record the player is chasing is the cartridge's.
-- ---------------------------------------------------------------------------

local MAGIKARP_LENGTHS = {
  { 110, 1 }, { 310, 2 }, { 710, 4 }, { 2710, 20 }, { 7710, 50 },
  { 17710, 100 }, { 32710, 150 }, { 47710, 150 }, { 57710, 100 },
  { 62710, 50 }, { 64710, 20 }, { 65210, 5 }, { 65410, 2 }, { 65510, 1 },
}

local function rotateRight(byte, count)
  byte = math.floor(byte or 0) % 256
  for _ = 1, count do
    byte = math.floor(byte / 2) + (byte % 2) * 128
  end
  return byte
end

local function magikarpLength(mon, otId)
  local dvs = mon.dvs or {}
  local dv0 = (dvs.attack or 0) * 16 + (dvs.defense or 0)
  local dv1 = (dvs.speed or 0) * 16 + (dvs.special or 0)
  otId = math.floor(otId or 0) % 65536
  -- bc = rrc(dv[0]) ++ rrc(dv[1]) ^ rrc(id), with the dv bytes rotated twice
  local bxor = require("bit").bxor
  local b = bxor(rotateRight(dv0, 2), rotateRight(math.floor(otId / 256), 1))
  local c = bxor(rotateRight(dv1, 2), rotateRight(otId % 256, 1))
  local bc = b * 256 + c
  local mm
  if b == 0 and c < 10 then
    mm = bc + 190
  else
    local index = 2
    for _, row in ipairs(MAGIKARP_LENGTHS) do
      local threshold, divisor = row[1], row[2]
      -- the bug: only the high bytes are compared
      if b < math.floor(threshold / 256) then
        mm = 100 * index + math.floor((bc - threshold) % 65536 / divisor)
        break
      end
      index = index + 1
    end
    if not mm then
      mm = (bc - MAGIKARP_LENGTHS[#MAGIKARP_LENGTHS][1]) % 65536 + 1600
    end
  end
  -- mm -> inches -> feet + inches, by the ROM's own repeated subtraction
  local inches = math.floor(mm * 10 / 254)
  return math.floor(inches / 12), inches % 12
end

local function lengthText(feet, inches)
  return string.format("%d'%02d\"", feet, inches)
end

local function magikarpRecord(save)
  save.g2Magikarp = save.g2Magikarp or { feet = 0, inches = 0, ot = "" }
  return save.g2Magikarp
end

-- 3 beat the record, 2 too short, 1 backed out, 0 not a MAGIKARP.
function Commands.g2_magikarp_length(ctx)
  local picked = pickMon(ctx)
  if not picked then return answer(ctx, 1) end
  if speciesNumber(picked) ~= 129 then return answer(ctx, 0) end
  local feet, inches = magikarpLength(picked,
    picked.otId or (ctx.save.player and ctx.save.player.id) or 0)
  local shown = lengthText(feet, inches)
  sayRam(ctx, "CheckMagikarpLength.MagikarpGuruMeasureText",
      Strings("Let me measure\nthat MAGIKARP.\f…Hm, it measures\n%s.", shown),
      { shown })
  local record = magikarpRecord(ctx.save)
  if feet * 12 + inches <= record.feet * 12 + record.inches then
    return answer(ctx, 2)
  end
  record.feet, record.inches = feet, inches
  record.ot = (ctx.save.player and ctx.save.player.name) or record.ot
  answer(ctx, 3)
end

-- The sign in the guru's house: the standing record and who set it.
function Commands.g2_magikarp_sign(ctx)
  local record = magikarpRecord(ctx.save)
  local shown = lengthText(record.feet, record.inches)
  sayRam(ctx, "MagikarpHouseSign.KarpGuruRecordText",
      Strings("CURRENT RECORD\f%s caught by\n%s", shown,
              record.ot ~= "" and record.ot or "-"),
      { shown, record.ot ~= "" and record.ot or "-" })
end

-- ---------------------------------------------------------------------------
-- Buena's Password  (engine/events/buena.asm)
--
-- The Blue Card game: Buena reads a password out on the radio each evening and
-- the player repeats it back at the studio for a point, which buys prizes.
--
-- DIVERGENCE, stated plainly: the port does not extract Buena's password
-- table, so there is no password for the player to have heard and no honest
-- four-way menu to show.  BuenasPassword therefore answers "correct" (1) and
-- the point is awarded, rather than answering 0 and locking the Blue Card out
-- of the game entirely.  Everything downstream -- the balance, the one point
-- a day, the prize list and its costs -- is real.
-- ---------------------------------------------------------------------------

local BUENA_PRIZES = {
  -- BuenaPrizes (data/events/buena_prizes.asm): item, cost in points
  { item = "ITEM_105", cost = 1 },  -- ULTRA_BALL
  { item = "ITEM_053", cost = 2 },  -- FULL_RESTORE
  { item = "ITEM_073", cost = 3 },  -- NUGGET
  { item = "ITEM_051", cost = 4 },  -- RARE_CANDY
  { item = "ITEM_045", cost = 5 },  -- PROTEIN
}

-- wBlueCardBalance.  The script awards the point itself -- RadioTower2F does
-- `readvar VAR_BLUECARDBALANCE / addval 1 / writevar` -- so this reads the
-- same byte those rows write (see g2_readvar / g2_writevar), it does not keep
-- a second tally of its own.
local function blueCard(save)
  save.g2BlueCard = save.g2BlueCard or 0
  return save.g2BlueCard
end

function Commands.g2_buenas_password(ctx)
  answer(ctx, 1)
end

-- AskRememberPassword: "shall I remind you of today's password?"  With no
-- password table there is nothing to remind them of, so decline politely.
function Commands.g2_ask_remember_password(ctx)
  answer(ctx, 0)
end

function Commands.g2_buena_prize(ctx)
  local save = ctx.save
  local points = blueCard(save)
  say(ctx, "BuenaPrize.BuenaAskWhichPrizeText",
      Strings("Which prize would\nyou like?"))
  local game = ctx.game
  local rows = {}
  for _, prize in ipairs(BUENA_PRIZES) do
    local def = (game.data.items or {})[prize.item]
    if def then
      rows[#rows + 1] = { label = def.name or prize.item,
                          right = tostring(prize.cost), value = prize }
    end
  end
  rows[#rows + 1] = { label = Strings("CANCEL") }
  local pick = menuPick(ctx, rows, { tx = 8, ty = 0, tw = 12 })
  if not pick then
    return say(ctx, "BuenaPrize.BuenaComeAgainText",
               Strings("Oh. Please come\nback again!"))
  end
  if points < pick.cost then
    return say(ctx, "BuenaPrize.BuenaNotEnoughPointsText",
               Strings("You don't have\nenough points.\f"))
  end
  if not require("src.inventory.Bag").add(save, pick.item, 1, game.data) then
    return say(ctx, "BuenaPrize.BuenaNoRoomText",
               Strings("You have no room\nfor it.\f"))
  end
  save.g2BlueCard = points - pick.cost
  say(ctx, "BuenaPrize.BuenaHereYouGoText", Strings("Here you go!\f"))
end

-- ---------------------------------------------------------------------------
-- The Poké Seer  (engine/events/poke_seer.asm)
--
-- Reads a mon's caught data back: where it was met, at what level, at what
-- time of day, and -- for a traded one -- who caught it.  The routine has a
-- documented branch for a mon whose caught-data bytes are ZERO
-- (ReadCaughtData's .error arm): SEERACTION_CANT_TELL_1, "I can't tell".
--
-- The port does not record caught data on a Pokémon, so every mon takes that
-- arm.  That is the cartridge's own answer for a mon it has no record of, not
-- an invention -- a Gen 1 time-capsule import gets exactly this line.
-- ---------------------------------------------------------------------------

function Commands.g2_poke_seer(ctx)
  say(ctx, "PokeSeer.SeerIntroText",
      Strings("I can tell you\nwhere a #MON\nwas caught.\fShall I take a\nlook?"))
  local picked = pickMon(ctx)
  if not picked then
    return say(ctx, "PokeSeer.SeerCancelText",
               Strings("Come see me\nanytime."))
  end
  local Party = require("src.pokemon.Party")
  ctx.game.stringBuffer = monName(ctx, picked)
  if Party.isEgg(picked) then
    return say(ctx, "PokeSeer.SeerEggText",
               Strings("An EGG? I can't\ntell a thing about\nit."))
  end
  say(ctx, "PokeSeer.SeerCantTellText",
      Strings("Hm… I can't tell\nanything about\nthis #MON."))
end

-- ---------------------------------------------------------------------------
-- The PCs
--
-- PokemonCenterPC (engine/events/pokecenter_pc.asm) is the boot menu, not a
-- storage system of its own: BILL's PC is Bill's PC (BoxMenu), <PLAYER>'s PC
-- is the item store (PlayerPC), PROF.OAK's PC is the dex rating, and HALL OF
-- FAME replays the credits roll.  Which rows appear depends on progress --
-- no Pokédex hides Oak's, no Hall of Fame entry hides the last one -- which
-- is .ChooseWhichPCListToUse, reproduced here.
--
-- PlayersHousePC is the bedroom PC: the item store alone, plus the decoration
-- menu the port does not model.  It answers through wScriptVar (`ld a, c`),
-- and the only value the calling script tests is 0.
-- ---------------------------------------------------------------------------

local function pcRows(ctx, finish)
  local game = ctx.game
  local save = game.save
  local hasDex = require("src.script.Flags").hasPokedex(save)
  local rows = {
    { label = Strings("BILL's PC"), keepOpen = true, onSelect = function()
        require("src.ui.Screens").push(game, "BoxMenu")
      end },
    { label = Strings("%s's PC", (save.player and save.player.name) or "PLAYER"),
      keepOpen = true, onSelect = function()
        require("src.ui.Screens").push(game, "PlayerPC")
      end },
  }
  if hasDex then
    rows[#rows + 1] = { label = Strings("PROF.OAK's PC"), keepOpen = true,
      onSelect = function() Commands.g2_oaks_pc(ctx) end }
  end
  if (save.hallOfFame or 0) > 0 or (save.hallOfFameCount or 0) > 0 then
    rows[#rows + 1] = { label = Strings("HALL OF FAME"), keepOpen = true,
      onSelect = function() require("src.ui.Screens").push(game, "HallOfFame") end }
  end
  -- TURN OFF is the only row without keepOpen, so it is the one that pops the
  -- menu -- and Menu:update does not call onCancel on that path, which is why
  -- it needs its own resume.
  rows[#rows + 1] = { label = Strings("TURN OFF"), onSelect = finish }
  return rows
end

function Commands.g2_pokemon_center_pc(ctx)
  -- PC_CheckPartyForPokemon: a player with no party gets nothing at all
  if #(ctx.save.party or {}) == 0 then return answer(ctx, 0) end
  local runner = ctx.runner
  local done
  local function finish()
    if done then return end
    done = true
    runner:resume()
  end
  require("src.ui.Screens").push(ctx.game, "Menu", pcRows(ctx, finish), {
    tx = 0, ty = 0, tw = 16, noSound = true, onCancel = finish,
  })
  runner:yield()
  answer(ctx, 0)
end

-- PlayerPC is a Menu of its own, so it closes on its LOG OFF row and on B.
-- Neither reaches this script, so there is nothing to wait on: push it and
-- answer, exactly as g2_card_flip does.
function Commands.g2_players_house_pc(ctx)
  require("src.ui.Screens").push(ctx.game, "PlayerPC")
  answer(ctx, 0)
end

-- ---------------------------------------------------------------------------
-- Teaching moves: the Goldenrod tutor, Prism's Move Relearner, and Prism's
-- happiness tutor.
--
-- All three end in the same place -- LearnMove, with the four-move menu when
-- the mon is full -- which the port already has as MoveLearnMenu.  What
-- differs is the gate in front: the Goldenrod tutor charges 4000 coins and
-- offers one of three fixed moves; the relearner charges a HEART SCALE and
-- offers what the mon could have learnt by level; the happiness tutor is free
-- but wants happiness of at least 200 and teaches a per-species move.
-- ---------------------------------------------------------------------------

local function moveKey(data, name)
  local moves = data.moves or {}
  if moves[name] then return name end
  -- Prism's ROM move list spells a few of pret's names with the underscore
  -- (BUBBLE_BEAM for BUBBLEBEAM); try both shapes before giving up.
  local spaced = name:gsub("BEAM$", "_BEAM"):gsub("BOILED$", "_BOILED")
  if moves[spaced] then return spaced end
  local squashed = name:gsub("_", "")
  for id in pairs(moves) do
    if id:gsub("_", "") == squashed then return id end
  end
  return nil
end

local function knowsMove(mon, id)
  for _, mv in ipairs(mon.moves or {}) do
    if mv.id == id then return true end
  end
  return false
end

local function canLearn(ctx, mon, id)
  local def = (ctx.game.data.pokemon or {})[mon.species]
  for _, m in ipairs((def and def.tmhm) or {}) do
    if m == id then return true end
  end
  return false
end

-- LearnMove: straight in when there is a free slot, otherwise the "which move
-- should be forgotten?" menu.  Returns true when the move was learnt.
local function teachMove(ctx, mon, id)
  local game, runner = ctx.game, ctx.runner
  local def = (game.data.moves or {})[id]
  if not def then return false end
  local learned = false
  require("src.ui.Screens").push(game, "MoveLearnMenu", mon, id, function(ok)
    learned = ok and true or false
    runner:resume()
  end)
  runner:yield()
  return learned
end

-- MoveTutor (engine/events/move_tutor.asm).  wScriptVar arrives as
-- MOVETUTOR_FLAMETHROWER / _THUNDERBOLT / _ICE_BEAM (1/2/3) and leaves as
-- FALSE when the move was taught, or -1 ($FF) when the player backed out --
-- which is why the Goldenrod script refunds the coins on $FF and not on 0.
local MOVE_TUTOR_MOVES = { [1] = "FLAMETHROWER", [2] = "THUNDERBOLT", [3] = "ICE_BEAM" }

function Commands.g2_move_tutor(ctx)
  local id = moveKey(ctx.game.data, MOVE_TUTOR_MOVES[ctx.g2Var or 0] or "ICE_BEAM")
  if not id then return answer(ctx, 0xFF) end
  ctx.game.stringBuffer = (ctx.game.data.moves[id] or {}).name or id
  while true do
    local picked = pickMon(ctx)
    if not picked then return answer(ctx, 0xFF) end
    if not canLearn(ctx, picked, id) then
      require("src.core.Sound").play(ctx.game.data, "Denied")
      say(ctx, nil, Strings("%s can't\nlearn that move!", monName(ctx, picked)))
    elseif knowsMove(picked, id) then
      say(ctx, nil, Strings("%s already\nknows that move.", monName(ctx, picked)))
    else
      teachMove(ctx, picked, id)
      return answer(ctx, 0)
    end
  end
end

-- Special_GoldenrodHappinessMoveTutor (Prism, event/happiness_tutor.asm): one
-- move per species, from a 256-entry table, gated on happiness >= 200.  The
-- table is data rather than code and carries no symbol the importer can reach,
-- so it is transcribed here from the disassembly, indexed by species number.
local HAPPINESS_MOVES = {
  "BURNING_MIST", "BURNING_MIST", "BURNING_MIST", "MORNING_SUN", "MORNING_SUN", "MORNING_SUN",
  "POWER_GEM", "POWER_GEM", "POWER_GEM", "X_SCISSOR", "X_SCISSOR", "X_SCISSOR",
  "METEOR_MASH", "METEOR_MASH", "MIASMA", "DRILL_PECK", "DRILL_PECK", "DRILL_PECK",
  "POWER_BALLAD", "POWER_BALLAD", "HAZE", "HAZE", "PAIN_SPLIT", "PAIN_SPLIT",
  "FLY", "METEOR_MASH", "EXTREMESPEED", "EXTREMESPEED", "EXTREMESPEED", "FIRE_BLAST",
  "FIRE_BLAST", "PERISH_SONG", "PERISH_SONG", "PERISH_SONG", "MOONBLAST", "MOONBLAST",
  "FUTURE_SIGHT", "FUTURE_SIGHT", "MOONLIGHT", "MOONLIGHT", "OUTRAGE", "OUTRAGE",
  "THUNDER_FANG", "THUNDER_FANG", "THUNDER_FANG", "CONFUSE_RAY", "CONFUSE_RAY", "MOONBLAST",
  "MOONBLAST", "STORM_FRONT", "STORM_FRONT", "FOCUS_ENERGY", "FOCUS_ENERGY", "DRAIN_PUNCH",
  "DRAIN_PUNCH", "ROLLOUT", "ROLLOUT", "DRAGON_DANCE", "DRAGON_DANCE", "SPITE",
  "SPITE", "SPITE", "AMNESIA", "AMNESIA", "AMNESIA", "DRAIN_PUNCH",
  "DRAIN_PUNCH", "SWORDS_DANCE", "MIASMA", "MIASMA", "MIASMA", "VAPORIZE",
  "VAPORIZE", "METEOR_MASH", "METEOR_MASH", "METEOR_MASH", "NASTY_PLOT", "NASTY_PLOT",
  "GROWTH", "GROWTH", "BASS_TREMOR", "BASS_TREMOR", "BASS_TREMOR", "FLAMETHROWER",
  "FLAMETHROWER", "DRAGON_PULSE", "DRAGON_PULSE", "POWER_BALLAD", "POWER_BALLAD", "PERISH_SONG",
  "PERISH_SONG", "MOONBLAST", "MOONBLAST", "MOONBLAST", "RAPID_SPIN", "METEOR_MASH",
  "METEOR_MASH", "DRAGON_DANCE", "DRAGON_DANCE", "SPIKES", "SPIKES", "SOFTBOILED",
  "SOFTBOILED", "EARTH_POWER", "EARTH_POWER", "DESTINY_BOND", "GHOST_HAMMER", "DRAGON_DANCE",
  "CRUNCH", "CRUNCH", "DRAGON_DANCE", "DRAGON_DANCE", "HAZE", "BARRIER",
  "HEAD_SMASH", "BARRIER", "HEAD_SMASH", "AQUA_JET", "AQUA_JET", "AQUA_JET",
  "AQUA_JET", "AQUA_JET", "CRUNCH", "BASS_TREMOR", "BULLET_PUNCH", "BUBBLEBEAM",
  "BULLET_PUNCH", "BUBBLEBEAM", "VAPORIZE", "VAPORIZE", "WILD_CHARGE", "DISABLE",
  "EARTH_POWER", "AQUA_JET", "BASS_TREMOR", "WILD_CHARGE", "METALLURGY", "PAIN_SPLIT",
  "RAPID_SPIN", "RAPID_SPIN", "HEAD_SMASH", "HEAD_SMASH", "MINIMIZE", "AEROBLAST",
  "SHOCK_SMOG", "SACRED_FIRE", "AURA_SPHERE", "AURA_SPHERE", "AURA_SPHERE", "GROWTH",
  "GROWTH", "GROWTH", "GROWTH", "GROWTH", "FEINT_ATTACK", "FEINT_ATTACK",
  "FEINT_ATTACK", "FOCUS_ENERGY", "FOCUS_ENERGY", "FOCUS_ENERGY", "RECOVER", "RECOVER",
  "AURA_SPHERE", "AURA_SPHERE", "AURA_SPHERE", "AURA_SPHERE", "POISON_GAS", "POISON_GAS",
  "OUTRAGE", "AQUA_JET", "AQUA_JET", "SWEET_SCENT", "PERISH_SONG", "MOONLIGHT",
  "AGILITY", "AGILITY", "MOONBLAST", "MOONBLAST", "PURSUIT", "PURSUIT",
  "PURSUIT", "AGILITY", "FOCUS_ENERGY", "FOCUS_ENERGY", "MIASMA", "MIASMA",
  "AQUA_JET", "AQUA_JET", "DRAGON_DANCE", "DRAGON_DANCE", "CROSS_CHOP", "CROSS_CHOP",
  "DRAGON_DANCE", "DRAGON_DANCE", "SPRING_BUDS", "AURA_SPHERE", "AURA_SPHERE", "HYDRO_PUMP",
  "GROWTH", "SLUDGE_BOMB", "SLUDGE_BOMB", "MIASMA", "MIASMA", "SMOKESCREEN",
  "SMOKESCREEN", "DRAGON_DANCE", "SPIKES", "RAPID_SPIN", "SPIKES", "AQUA_JET",
  "AQUA_JET", "METALLURGY", "MACH_PUNCH", "MACH_PUNCH", "CRUNCH", "QUICK_ATTACK",
  "QUICK_ATTACK", "ACID_ARMOR", "ACID_ARMOR", "HEAD_SMASH", "HEAD_SMASH", "NIGHT_SLASH",
  "NIGHT_SLASH", "NIGHT_SLASH", "NIGHT_SLASH", "NIGHT_SLASH", "NIGHT_SLASH", "MIASMA",
  "MIASMA", "HEAD_SMASH", "METALLURGY", "METALLURGY", "METALLURGY", "METALLURGY",
  "CRUNCH", "DRAIN_PUNCH", "DRAIN_PUNCH", "BASS_TREMOR", "BULLET_PUNCH", "BUBBLEBEAM",
  "SWEET_KISS", "HAZE", "FLARE_BLITZ", "AQUA_JET", "AEROBLAST", "CROSS_CHOP",
  "CROSS_CHOP", "CROSS_CHOP", "AURA_SPHERE", "LAVA_POOL", "GROWTH", "BULLET_PUNCH",
  "TACKLE", "MIASMA", "TACKLE", "TACKLE",
}

function Commands.g2_happiness_tutor(ctx)
  if not confirm(ctx, nil, Strings(
      "I can teach a move\nto a #MON that\nreally likes you.\fWould you like me\nto take a look?")) then
    return say(ctx, nil, Strings("Oh… Come back\nany time."))
  end
  local picked = pickMon(ctx)
  if not picked then return say(ctx, nil, Strings("Oh… Come back\nany time.")) end
  local Party = require("src.pokemon.Party")
  ctx.game.stringBuffer = monName(ctx, picked)
  if Party.isEgg(picked) then
    return say(ctx, nil, Strings("An EGG can't\nlearn anything!"))
  end
  if (picked.happiness or 0) < 200 then
    return say(ctx, nil, Strings("%s doesn't\nlike you enough\nyet.", monName(ctx, picked)))
  end
  local name = HAPPINESS_MOVES[speciesNumber(picked)]
  local id = name and moveKey(ctx.game.data, name)
  if not id then
    return say(ctx, nil, Strings("There's nothing I\ncan teach it."))
  end
  if knowsMove(picked, id) then
    return say(ctx, nil, Strings("It already knows\nthat move!"))
  end
  local moveName = (ctx.game.data.moves[id] or {}).name or id
  if not confirm(ctx, nil, Strings("I could teach it\n%s.\fWould you like me\nto do that?", moveName)) then
    return say(ctx, nil, Strings("Oh… Come back\nany time."))
  end
  teachMove(ctx, picked, id)
end

-- MoveRelearner (Prism, event/move_relearner.asm): one HEART SCALE per move,
-- and the list is the mon's own learnset up to its current level minus what it
-- already knows.  The scale is taken only when a move is actually learnt.
local HEART_SCALE = "ITEM_093"

function Commands.g2_move_relearner(ctx)
  local save, data = ctx.save, ctx.game.data
  local scale = (data.items or {})[HEART_SCALE] and HEART_SCALE
  if not (scale and (save.inventory or {})[scale]) then
    return say(ctx, nil, Strings("Bring me a HEART\nSCALE and I'll\nteach a move."))
  end
  if not confirm(ctx, nil, Strings(
      "I can make a #MON\nremember a move,\nfor one HEART\nSCALE.\fInterested?")) then
    return say(ctx, nil, Strings("Come again!"))
  end
  local picked = pickMon(ctx)
  if not picked then return say(ctx, nil, Strings("Come again!")) end
  local Party = require("src.pokemon.Party")
  if Party.isEgg(picked) then
    return say(ctx, nil, Strings("An EGG can't\nremember anything!"))
  end
  local def = (data.pokemon or {})[picked.species]
  local rows = {}
  for _, entry in ipairs((def and def.learnset) or {}) do
    local id = entry.move or entry[2]
    local level = entry.level or entry[1] or 1
    if id and level <= (picked.level or 1) and not knowsMove(picked, id)
       and not rows[id] then
      rows[id] = true
      rows[#rows + 1] = id
    end
  end
  if #rows == 0 then
    return say(ctx, nil, Strings("%s has no\nmoves to remember.", monName(ctx, picked)))
  end
  local menu = {}
  for _, moveId in ipairs(rows) do
    menu[#menu + 1] = { label = (data.moves[moveId] or {}).name or moveId,
                        value = moveId }
  end
  menu[#menu + 1] = { label = Strings("CANCEL") }
  local id = menuPick(ctx, menu, { tx = 8, ty = 0, tw = 12, maxVisible = 4 })
  if not id then return say(ctx, nil, Strings("Come again!")) end
  if teachMove(ctx, picked, id) then
    require("src.inventory.Bag").remove(save, scale, 1)
    say(ctx, nil, Strings("Thanks! I'll take\nthat HEART SCALE."))
  end
end

-- ---------------------------------------------------------------------------
-- Prism's three remaining features
-- ---------------------------------------------------------------------------

-- Special_FossilPuzzle (Prism, engine/specials.asm): a sliding-tile picture of
-- the fossil, and wSolvedFossilPuzzle -- which the script reads back -- is the
-- only thing that leaves it.  The port has no tile-puzzle screen; solving it
-- for the player is the one option that does not strand the fossil.
function Commands.g2_fossil_puzzle(ctx)
  Logger.warn("g2_fossil_puzzle: no puzzle screen -- answering solved")
  answer(ctx, 1)
end

-- Special_MemoryGame (Prism, event/memory_game.asm): a Game Corner concentration
-- game.  Like the slots and card flip it checks the coin case first and refuses
-- outright without coins, which is the part the script branches on.
function Commands.g2_memory_game(ctx)
  local save = ctx.save
  if (save.coins or 0) <= 0 then
    require("src.core.Sound").play(ctx.game.data, "Denied")
    say(ctx, nil, Strings("You don't have\nany coins."))
    return answer(ctx, 0)
  end
  Logger.warn("g2_memory_game: no memory-game screen -- skipped")
  say(ctx, nil, Strings("The machine is\nout of order."))
  answer(ctx, 0)
end

-- Special_SpurgeMartBank (Prism, event/bank.asm): an ATM.  Deposit, withdraw,
-- and a direct-deposit switch that skims up to 25% of battle winnings into the
-- account.  All three are plain money moves, so all three are real here; the
-- skim itself is applied wherever prize money is paid, off save.g2Bank.
local function bankState(save)
  save.g2Bank = save.g2Bank or { balance = 0, direct = false, opened = false }
  return save.g2Bank
end
Gen2Specials.bankState = bankState

function Commands.g2_spurge_bank(ctx)
  local save, game, runner = ctx.save, ctx.game, ctx.runner
  local bank = bankState(save)
  say(ctx, nil, Strings("Welcome to the\nSpurge Bank ATM."))
  if not bank.opened then
    bank.opened = true
    bank.direct = confirm(ctx, nil, Strings(
      "We offer direct\ndeposit of battle\nwinnings.\fUp to 25 percent\nof what you win\nis sent here.\fEnable it?"))
    say(ctx, nil, Strings("Your account has\nbeen created."))
  end
  while true do
    local choice = menuPick(ctx, {
      { label = Strings("DEPOSIT"), value = "in" },
      { label = Strings("WITHDRAW"), value = "out" },
      { label = Strings("BALANCE"), value = "bal" },
      { label = bank.direct and Strings("DD: ON") or Strings("DD: OFF"),
        value = "dd" },
      { label = Strings("EXIT") },
    }, { tx = 9, ty = 0, tw = 11 })
    if not choice then break end
    if choice == "bal" then
      say(ctx, nil, Strings("Your balance is\n$%d.", bank.balance))
    elseif choice == "dd" then
      bank.direct = not bank.direct
      say(ctx, nil, bank.direct and Strings("Direct deposit is\nnow ON.")
                                or Strings("Direct deposit is\nnow OFF."))
    else
      local cap = choice == "in" and (save.money or 0) or bank.balance
      if cap <= 0 then
        say(ctx, nil, Strings("There's nothing\nto move."))
      else
        local amount
        require("src.ui.Screens").push(game, "MoneyEntry", {
          max = cap,
          onDone = function(value) amount = value runner:resume() end,
        })
        runner:yield()
        amount = math.max(0, math.min(cap, math.floor(amount or 0)))
        if amount > 0 then
          if choice == "in" then
            save.money = (save.money or 0) - amount
            bank.balance = bank.balance + amount
          else
            save.money = (save.money or 0) + amount
            bank.balance = bank.balance - amount
          end
          say(ctx, nil, Strings("Your balance is\n$%d.", bank.balance))
        end
      end
    end
  end
  say(ctx, nil, Strings("Logging out…"))
end

return Gen2Specials
