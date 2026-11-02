-- HEARTGOLD / SOULSILVER: WHICH CALL A CONTACT ANSWERS WITH WHEN THE PLAYER
-- RINGS THEM from the Pokegear's phone list (PhoneCall_InitContext with
-- incoming FALSE, then PhoneCall_GetCallScriptId by the phonebook TYPE).
-- The answer is a plan for src/ui/HgssPhoneCall.lua.
--
-- READ FROM CODE (pokeheartgold src/application/pokegear/phone/scripts):
--   * out of area: MapHeader_CanPlacePhoneCalls (the map header's
--     outgoingCalls) false -> "......" x3, the hang-up tone and bank 271 37
--   * the contact at home (phoneBookEntry->mapId == the player's map): the
--     type's local script -- Mom 023, Elm 001, Oak 068, Bike Shop 084,
--     Kurt 083, Bill 092, Baoba 140, a trainer its phoneScriptIfLocal
--   * MOM (PhoneCall_GetScriptId_Mother): 025 before the rival's name is given
--     to the officer, 026 before Mom has been talked to after it, else her
--     own handler (GearPhoneCall_Mother: the intro by location, bank 664
--     7 + momCallIntro, then the savings prompt and menu)
--   * ELM (PhoneCall_GetScriptId_ProfElm): the flag ladder 008 / 009 / 010 /
--     011, then by badges, the Togepi egg, the Everstone, the Rocket takeover
--     (var 0x4077 2..4), the S.S. Ticket and Pokerus, 012 .. 022
--   * BIKE SHOP: 085
--   * a TRAINER (PhoneCall_GetScriptId_Generic): its eight outgoing rows of
--     sGenericPhoneCallHeaders in order, the first whose condition holds and
--     whose percent roll passes -- RAND (any time), FIGHTPOSTROCKETS (not
--     already seeking a rematch or holding a gift; a rematch script only
--     after FLAG_BEAT_RADIO_TOWER_ROCKETS 0xC6), POSTROCKETWEEKTIME (after
--     0xC6, on the contact's rematch weekday and time of day),
--     BUGCONTESTDAYS (Tue / Thu / Sat), DURINGROCKETS (the takeover),
--     FIGHTPOSTROCKETSNOTBUGCONTEST (after 0xC6, seeking, not National Park
--     during the contest), GIFTNOTBUGCONTEST (holding a gift); none passing,
--     the last row tried. Its scriptType picks the handler (0 simple, 1
--     generic: their Pokemon and a wild one, 2 generic2: one of eleven)
--   * the rematch / gift state those rows read is kept in
--     save.hgssPhoneState (the cartridge's PhoneCallPersistentState)
-- The other contacts (Oak, Bill, Kurt, the Day-Care couple, Buena, Ethan /
-- Lyra, the gym leaders, Kenji, Irwin, Baoba) are src/ui/HgssPhoneScripts.lua.

local Out = {}

-- PhoneCallType (phone_internal.h)
local TYPE = { GENERIC = 0, MOM = 1, ELM = 2, OAK = 3, KURT = 4, BIKE_SHOP = 5, KENJI = 6, BILL = 7,
  DAYCARE_MAN = 8, DAYCARE_LADY = 9, BUENA = 10, ETHAN_LYRA = 11, GYMLEADER = 12, BAOBA = 13, IRWIN = 14 }
Out.TYPE = TYPE
local LOCAL = { [TYPE.MOM] = 23, [TYPE.ELM] = 1, [TYPE.OAK] = 68, [TYPE.KURT] = 83, [TYPE.BIKE_SHOP] = 84,
  [TYPE.BILL] = 92, [TYPE.BAOBA] = 140 }

local function flag(save, id)
  return ((save or {}).flags or {})[("FLAG_G4_%04X"):format(id)] == true
end

local function badges(save)
  local n = 0
  for _, yes in pairs((save or {}).badges or {}) do if yes then n = n + 1 end end
  return n
end

local function var(save, id)
  local ok, C = pcall(require, "src.script.Gen4Commands")
  if ok and C.getVar then return tonumber(C.getVar(save, id)) or 0 end
  return tonumber((((save or {}).gen4Vars) or {})[id]) or 0
end

-- PhoneCall_GetScriptId_ProfElm, outgoing
function Out.elm(save, rnd)
  rnd = rnd or math.random
  if not flag(save, 0xEE) then return 8 end            -- FLAG_GOT_ELMS_PANIC_CALL
  if not flag(save, 0x79) then return 9 end            -- FLAG_GAVE_RIVAL_NAME_TO_OFFICER
  if not flag(save, 0x9F) then return 10 end           -- FLAG_GOT_PICK_UP_EGG_CALL_FROM_ELM
  if not flag(save, 0x70) then return 11 end           -- FLAG_GOT_EGG_FROM_ELMS_ASSISTANT
  local hatched, everstone = flag(save, 0x983), flag(save, 0x11A)
  local n = badges(save)
  if n < 7 then
    if not hatched then return 12 end
    if everstone then return 14 + (rnd(2) - 1) end
    return 13
  end
  local takeover = var(save, 0x4077)
  if takeover >= 2 and takeover <= 4 then return 16 end
  if n < 8 then return 17 end
  if not flag(save, 0x964) then return 18 end          -- FLAG_GAME_CLEAR
  if not flag(save, 0xF2) then return 19 end           -- FLAG_GOT_SS_TICKET_FROM_ELM
  if not everstone then return hatched and 13 or 12 end
  if flag(save, 0x65) then return 20 + (rnd(3) - 1) end -- FLAG_WAS_TOLD_ABOUT_POKERUS
  return 20 + (rnd(2) - 1)
end

local function timeOfDay()
  -- GF_RTC_GetTimeOfDayWildParamByHour: morning 0, day / evening 1, night 2
  local ok, E = pcall(require, "src.import.Gen4Encounters")
  local band = ok and E.timeOfDayForHour and E.timeOfDayForHour(tonumber(os.date("%H")) or 12) or 1
  return (band == 0 and 0) or ((band == 1 or band == 2) and 1) or 2
end

function Out.state(save)
  save.hgssPhoneState = save.hgssPhoneState or {}
  local st = save.hgssPhoneState
  st.seeking, st.gift = st.seeking or {}, st.gift or {}
  return st
end

-- PhoneCall_GetScriptId_Generic / PhoneScriptGeneric_GetScriptIdInternal
-- `base` 8 reads the contact's eight INCOMING rows (PhoneCall_GetScriptId_Generic)
function Out.generic(game, caller, entry, rnd, base)
  rnd = rnd or math.random
  local save = game.save
  local data = game.data or {}
  local rows = ((data.gen4_hgss_pokegear_art or {}).genericHeaders or {})[caller]
  if not rows then return nil end
  local scripts = (data.gen4_hgss_phone_call or {}).scripts or {}
  local st = Out.state(save)
  local beatRT = flag(save, 0xC6)
  local contestNP = entry.mapId == 96 and flag(save, 0x996)
  local takeover = var(save, 0x4077)
  local function roll(chance) return (rnd(100) - 1) <= chance end
  local last
  for k = 0, 7 do
    local h = rows[k + (base or 0)]
    if not h or h.type == 0 or h.type == 255 then break end
    local ok
    if h.type == 2 then
      ok = not st.seeking[caller] and not st.gift[caller]
      local def = scripts[h.script]
      if ok and not beatRT and h.scriptType == 0 and def and def.kind == 3 then ok = false end
      ok = ok and roll(h.chance)
    elseif h.type == 7 then
      ok = beatRT and not contestNP and st.seeking[caller] and roll(h.chance)
    elseif h.type == 8 then
      ok = not contestNP and st.gift[caller] and roll(h.chance)
    elseif h.type == 3 then
      local wday = (tonumber(os.date("%w")) or 0)
      ok = beatRT and wday == entry.rematchWeekday and timeOfDay() == entry.rematchTimeOfDay and roll(h.chance)
    elseif h.type == 4 then
      local wday = (tonumber(os.date("%w")) or 0)
      ok = (wday == 2 or wday == 4 or wday == 6) and roll(h.chance)
    elseif h.type == 5 then
      ok = takeover >= 2 and takeover <= 4 and roll(h.chance)
    else
      ok = roll(h.chance)
    end
    if ok then return { kind = "generic", scriptType = h.scriptType, script = h.script } end
    last = h
  end
  if not last then return { kind = "generic", scriptType = 0, script = 0 } end
  return { kind = "generic", scriptType = last.scriptType, script = last.script }
end

-- choose(game, caller, header, headerId) -> plan
function Out.choose(game, caller, header, headerId)
  local data = game.data or {}
  local save = game.save
  local pc = data.gen4_hgss_phone_call or {}
  local entry = (pc.book or {})[caller]
  if header and header.outgoingCalls == false then return { kind = "outofarea" } end
  if not entry then return { kind = "unsupported" } end
  local t = entry.type
  local home = headerId ~= nil and entry.mapId == headerId
  if home then
    if t == TYPE.GENERIC then return { kind = "simple", script = entry.localScript } end
    if LOCAL[t] then return { kind = "simple", script = LOCAL[t] } end
  end
  if t == TYPE.MOM then
    if not flag(save, 0x79) then return { kind = "simple", script = 25 } end
    if not flag(save, 0xA7) then return { kind = "simple", script = 26 } end
    return { kind = "mother", outgoing = true, intro = header and header.momCallIntro }
  end
  if t == TYPE.ELM then return { kind = "simple", script = Out.elm(save) } end
  if t == TYPE.BIKE_SHOP then return { kind = "simple", script = 85 } end
  if t == TYPE.GENERIC then return Out.generic(game, caller, entry) or { kind = "unsupported" } end
  -- the other contacts' handlers: src/ui/HgssPhoneScripts.lua
  local okS, Scripts = pcall(require, "src.ui.HgssPhoneScripts")
  local plan = okS and Scripts.plan(game, caller, { headerId = headerId, header = header })
  return plan or { kind = "unsupported" }
end

return Out
