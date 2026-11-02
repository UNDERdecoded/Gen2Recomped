-- HEARTGOLD / SOULSILVER: THE POKEGEAR CALL HANDLERS FOR THE CONTACTS WHO
-- ARE NOT ROUTE TRAINERS -- and every call the ring manager puts through.
--
-- PhoneCall_GetCallScriptId (pokeheartgold overlay_101_021F1D74.c) picks a
-- handler by the phonebook TYPE; src/ui/HgssPhoneOutgoing.lua covers the
-- player ringing Mom, Elm, the Bike Shop and the route trainers. This module
-- is the rest, read function for function from
-- src/application/pokegear/phone/scripts/*.c:
--
--   * OAK       PhoneCall_GetScriptId_ProfOak / GearPhoneCall_ProfOak: 068 at
--               home, 081 / 080 once a dex is acknowledged complete, else the
--               evaluation (menus 3 / 4 / 5, bank 666 13/14, 15, 20, the
--               rating line of GetOakJohto/NationalDexRating, 21); incoming
--               068 + owned/50 (1..9)
--   * BILL      092 at home, incoming 093, else GearPhoneCall_Bill (greeting,
--               665 3/4, the active box and free spaces 5..7 / 9, then 8)
--   * KURT      083 at home, else GearPhoneCall_Kurt (643 6 / 2, then 5 / 4 /
--               3 with his ball and count)
--   * DAY-CARE  the lady (097 at home, else 660 3/4, 10 / 5, 6 per Pokemon
--               with its levels gained, 8 / 9); the man (incoming 096 / 095,
--               else 661 2, then 3 egg / 4 none / 5 one / 6 + 7..10 by their
--               compatibility, 11)
--   * BUENA     099 in the Rocket takeover, 100 while her show is on, 098 at
--               home, else GearPhoneCall_Buena (641 3 + tod*2, 10..12);
--               incoming GearPhoneCall_Buena2 (641 15 + tod*2, 36 on air, else
--               21 + rand(11 or 14), 13 -> 34/35)
--   * ETHAN / LYRA  101/102 at home; outgoing GearPhoneCall_EthanLyra (662 4
--               + tod, then the line of the map the player is on, 13 + i, or
--               10..12); incoming GearPhoneCall_EthanLyra2 (662 7 + tod, then
--               10..12 or a place line 86 + i of those the map level unlocks)
--   * GYM LEADERS  GearPhoneCall_GymLeader_Outgoing: 644-layout 1 at home,
--               else 2, then 3 (under 16 badges) / 9 (already seeking) / 4
--               (not their weekday and time) / 5 + YES-NO: 7 no, 6 yes (seeking
--               set -- isDojoFull only ever looks at Falkner, so it is always
--               "not full"); incoming 10, then 11 seeking / 12..14
--   * KENJI     086 at home; 087 / 088 while he trains (wait days); 087 while
--               active and not seeking; 091 in the evening / at night; else
--               active + seeking, 090 by day / 089 in the morning
--   * IRWIN     outgoing 156 in the takeover / 172..174; incoming the story
--               ladder ov101_021F42E4 (157..168, one-shot flags 0x99F..0x9A5,
--               only after FLAG_UNK_998), else 169 / 170 / 171
--   * BAOBA     141 scripted; incoming its trigger script (142 sets VAR 0x4057
--               4; 143..146 7); 140 at home; else 147 + VAR 0x4057
--
-- `plan(game, caller, opts)` answers a plan for src/ui/HgssPhoneCall.lua:
-- { kind = "simple", script } or { kind = "custom", build = fn(call) } (the
-- build queues the call's lines and menus), or nil when the type is not one
-- of these. opts: incoming, scripted (isScriptedCall), predefined (the ring
-- manager's script), headerId.

local S = {}

-- PhoneCallType (phone_internal.h)
local TYPE = { GENERIC = 0, MOM = 1, ELM = 2, OAK = 3, KURT = 4, BIKE_SHOP = 5, KENJI = 6, BILL = 7,
  DAYCARE_MAN = 8, DAYCARE_LADY = 9, BUENA = 10, ETHAN_LYRA = 11, GYMLEADER = 12, BAOBA = 13, IRWIN = 14 }
S.TYPE = TYPE
S.KENJI = 16

local function flag(save, id)
  return ((save or {}).flags or {})[("FLAG_G4_%04X"):format(id)] == true
end
local function var(save, id)
  local ok, C = pcall(require, "src.script.Gen4Commands")
  if ok and C.getVar then return tonumber(C.getVar(save, id)) or 0 end
  return tonumber((((save or {}).gen4Vars) or {})[id]) or 0
end
local function setVar(save, id, v)
  local ok, C = pcall(require, "src.script.Gen4Commands")
  if ok and C.setVar then C.setVar(save, id, v) end
end
local function rand(n) return math.random(0, n - 1) end
S.rand = rand

local function badgeList(game)
  local ok, B = pcall(require, "src.inventory.Badges")
  if not ok then return nil, {} end
  return B, B.list(game.data) or {}
end
-- PlayerProfile_CountBadges
function S.badges(game)
  local B = badgeList(game)
  return B and B.count(game.data, game.save) or 0
end
-- PlayerProfile_TestBadgeFlag: BADGE_ZEPHYR 0 .. BADGE_EARTH 15
function S.hasBadge(game, index)
  local B, list = badgeList(game)
  local e = list[index + 1]
  return B and e and B.has(game.save, e) and true or false
end
S.BADGE = { PLAIN = 2, FOG = 3, RISING = 7, MARSH = 13 }

-- the hour on the cartridge's RTC (the harness fakes os.date)
local function hour() return tonumber(os.date("*t").hour) or 12 end
local function weekday() return (tonumber(os.date("*t").wday) or 1) - 1 end
S.hour, S.weekday = hour, weekday
-- GF_RTC_GetTimeOfDayByHour: 0 morning (4-9), 1 day (10-16), 2 evening
-- (17-19), 3 night (20-23), 4 late night (0-3)
function S.rtcTimeOfDay(h)
  h = h or hour()
  if h >= 4 and h < 10 then return 0 elseif h >= 10 and h < 17 then return 1
  elseif h >= 17 and h < 20 then return 2 elseif h >= 20 then return 3 end
  return 4
end
-- GF_RTC_GetTimeOfDayWildParamByHour: morning 0, day / evening 1, night 2
function S.wildTimeOfDay(h)
  local t = S.rtcTimeOfDay(h)
  return (t == 0 and 0) or ((t == 1 or t == 2) and 1) or 2
end
function S.rocketTakeover(save) local v = var(save, 0x4077); return v >= 2 and v <= 4 end
function S.gameClear(save) return flag(save, 0x964) end
-- the ring manager's persistent state (PhoneCallPersistentState)
function S.state(save) return require("src.ui.HgssPhoneOutgoing").state(save) end

local function ctxOf(game) return { game = game, save = game.save } end
local function dexCount(game, region, field)
  local ok, C = pcall(require, "src.script.Gen4Commands")
  if not (ok and C.hgssDexIds) then return 0 end
  return #C.hgssDexIds(ctxOf(game), region, field)
end
local function ownedNoMythicals(game, region)
  local ok, C = pcall(require, "src.script.Gen4Commands")
  if not (ok and C.hgssOwnedNoMythicals) then return 0 end
  return C.hgssOwnedNoMythicals(ctxOf(game), region)
end
S.dexCount = dexCount
local function natDex(save) return ((save or {}).pokedex or {}).national and true or false end

local function itemName(game, id)
  local items = (game.data or {}).items or {}
  local def = items[id] or items[("ITEM_%03d"):format(tonumber(id) or 0)]
  return def and def.name or ""
end
local function monName(game, mon)
  if not mon then return "" end
  local p = (game.data or {}).pokemon or {}
  local def = p[mon.species] or p[tonumber(mon.species) or -1]
  return mon.nickname or (def and def.name) or ""
end

-- --------------------------------------------------------------- queueing
-- the items go in right after the one the call is on (inside a menu's choose)
local function after(call, items)
  local at = call.at or 0
  for i, it in ipairs(items) do table.insert(call.queue, at + i, it) end
end
local function line(call, bank, index) return { say = call:message(bank, index) } end
local function gendered(call, bank, e, l) return line(call, bank, call.girl and l or e) end
local function menu(call, first, n, choose)
  local labels = {}
  for i = 0, n - 1 do
    labels[#labels + 1] = (call.pc.texts and call.pc.texts[first + i]) or call:message(271, first + i)
  end
  return { menu = labels, choose = choose }
end
local function buf(call, slot, text)
  call.extraBuffers = call.extraBuffers or {}
  call.extraBuffers[slot + 1] = tostring(text or "")
end
-- PhoneCall_PrintGreeting (bank 640, the phonebook row's greeting set)
local function greeting(call)
  local entry = call.pc.book and call.pc.book[call.call.caller]
  local g = entry and entry.greeting
  local row = g and g ~= 0xFF and call.pc.greetings and call.pc.greetings[g]
  if not row then return nil end
  local k = S.wildTimeOfDay() * 2 + (call.call.outgoing and 0 or 6) + (call.girl and 1 or 0)
  return row[k] and line(call, 640, row[k]) or nil
end

-- ------------------------------------------------------------------- OAK
local function oakBuild(call)
  local game, save, bank = call.game, call.game.save, call.bank
  local nat = natDex(save)
  local johtoDone = ownedNoMythicals(game, "johto") >= 256 - 2
  local natDone = ownedNoMythicals(game, "national") >= 493 - 9
  call.queue[#call.queue + 1] = gendered(call, bank, 13, 14)
  call.queue[#call.queue + 1] = line(call, bank, 15)
  local which = nat and (flag(save, 0x987) and 2 or 1) or 0
  local menus = { [0] = { 10, 2 }, [1] = { 12, 3 }, [2] = { 15, 2 } }
  local m = menus[which]
  call.queue[#call.queue + 1] = menu(call, m[1], m[2], function(r)
    r = r - 1
    if r == m[2] - 1 then after(call, { line(call, bank, 21) }) return end
    local national = (r == 0 and which == 2) or (r == 1 and which == 1)
    local seen = dexCount(game, national and "national" or "johto", "seen")
    local owned = dexCount(game, national and "national" or "johto", "owned")
    buf(call, 5, seen); buf(call, 6, owned)
    local count = ownedNoMythicals(game, national and "national" or "johto")
    local msg = require("src.script.Gen4Commands").hgssOakRating(national, count, call.girl)
    local acknowledged = false
    if not national and johtoDone then call:flag(0x987, true); acknowledged = true end
    if national and natDone then call:flag(0x988, true); acknowledged = true end
    local items = { line(call, bank, 20), line(call, bank, msg) }
    if not acknowledged then items[#items + 1] = line(call, bank, 21) end
    after(call, items)
  end)
end

function S.oak(game, opts, entry, home)
  if opts.scripted == 2 then return { kind = "simple", script = 82 } end
  if opts.incoming then
    local n = math.floor(dexCount(game, "national", "owned") / 50)
    n = math.max(1, math.min(9, n))
    return { kind = "simple", script = 68 + n }
  end
  if home then return { kind = "simple", script = 68 } end
  if flag(game.save, 0x988) then return { kind = "simple", script = 81 } end
  if not natDex(game.save) and flag(game.save, 0x987) then return { kind = "simple", script = 80 } end
  return { kind = "custom", build = oakBuild }
end

-- ------------------------------------------------------------------ BILL
local function emptySpots(save)
  local ok, Boxes = pcall(require, "src.pokemon.Boxes")
  if not ok then return 0 end
  local boxes = Boxes.ensure(save)
  local n = 0
  for i = 1, Boxes.count() do
    n = n + Boxes.capacity() - Boxes.used(boxes[i])
  end
  return n
end
S.emptySpots = emptySpots
local function billBuild(call)
  local save, bank = call.game.save, call.bank
  local g = greeting(call)
  if g then call.queue[#call.queue + 1] = g end
  call.queue[#call.queue + 1] = gendered(call, bank, 3, 4)
  local n = save.currentBox or 1
  local named = save.boxNames and save.boxNames[n]
  buf(call, 10, (type(named) == "string" and #named > 0) and named or ("BOX %d"):format(n))
  local free = emptySpots(save)
  buf(call, 11, free)
  call.queue[#call.queue + 1] = line(call, bank, free == 0 and 9 or (5 + rand(3)))
  call.queue[#call.queue + 1] = line(call, bank, 8)
end
function S.bill(game, opts, entry, home)
  if opts.incoming then return { kind = "simple", script = 93 } end
  if home then return { kind = "simple", script = 92 } end
  return { kind = "custom", build = billBuild }
end

-- ------------------------------------------------------------------ KURT
local function kurtBuild(call)
  local save, bank = call.game.save, call.bank
  call.queue[#call.queue + 1] = line(call, bank, flag(save, 0x127) and 6 or 2)
  local A = require("src.world.HgssApricorns")
  local q = A.kurtQuantity(save)
  local msg
  if q == 0 then msg = 5
  elseif flag(save, 0xAA2) then msg = 4
  else
    buf(call, 10, itemName(call.game, A.kurtBall(save)))
    buf(call, 11, q)
    msg = 3
  end
  call.queue[#call.queue + 1] = line(call, bank, msg)
end
function S.kurt(game, opts, entry, home)
  if home then return { kind = "simple", script = 83 } end
  return { kind = "custom", build = kurtBuild }
end

-- -------------------------------------------------------------- DAY-CARE
local function ladyBuild(call)
  local game, bank = call.game, call.bank
  local D = require("src.pokemon.Gen4DayCare")
  local count, grown = 0, {}
  for i = 0, 1 do
    local slot = D.slot(game.save, i)
    if slot and slot.mon then count = count + 1; grown[i] = D.gainedLevels(game.data, game.save, i) else grown[i] = 0 end
  end
  local q = call.queue
  q[#q + 1] = gendered(call, bank, 3, 4)
  if count == 0 then q[#q + 1] = line(call, bank, 10) return end
  q[#q + 1] = line(call, bank, 5)
  if grown[0] == 0 and grown[1] == 0 then q[#q + 1] = line(call, bank, 9) return end
  for i = 0, 1 do
    if grown[i] ~= 0 then
      -- each line buffers its own Pokemon right before it prints
      q[#q + 1] = { run = function()
        buf(call, 10, monName(game, D.slot(game.save, i).mon)); buf(call, 11, grown[i])
      end }
      q[#q + 1] = { lazy = function() return call:message(bank, 6) end }
    end
  end
  q[#q + 1] = line(call, bank, count == 1 and 8 or 9)
end
function S.daycareLady(game, opts, entry, home)
  if home then return { kind = "simple", script = 97 } end
  return { kind = "custom", build = ladyBuild }
end
local function manBuild(call)
  local game, bank = call.game, call.bank
  local D = require("src.pokemon.Gen4DayCare")
  local n = 0
  for i = 0, 1 do
    local slot = D.slot(game.save, i)
    if slot and slot.mon then buf(call, 10 + i, monName(game, slot.mon)); n = n + 1 end
  end
  local q = call.queue
  q[#q + 1] = line(call, bank, 2)
  if D.hasEgg(game.save) then q[#q + 1] = line(call, bank, 3) return end
  if n == 0 then q[#q + 1] = line(call, bank, 4)
  elseif n == 1 then q[#q + 1] = line(call, bank, 5)
  else
    q[#q + 1] = line(call, bank, 6)
    q[#q + 1] = line(call, bank, 7 + (D.compatibilityLevel(game.data, game.save) or 3))
  end
  q[#q + 1] = line(call, bank, 11)
end
function S.daycareMan(game, opts)
  if opts.incoming then return { kind = "simple", script = flag(game.save, 0x992) and 96 or 95 } end
  return { kind = "custom", build = manBuild }
end

-- ----------------------------------------------------------------- BUENA
-- IsBuenasPasswordOnAir
function S.buenaOnAir(h)
  if h % 3 == 2 then return 3 end
  if h > 3 and h < 10 then return 0 end
  if h > 9 and h < 20 then return 1 end
  return 2
end
function S.buena(game, opts, entry, home)
  local save = game.save
  local onAir = S.buenaOnAir(hour())
  if S.rocketTakeover(save) then return { kind = "simple", script = 99 } end
  local tod = S.wildTimeOfDay()
  if opts.incoming then
    return { kind = "custom", build = function(call)
      local bank = call.bank
      call.queue[#call.queue + 1] = gendered(call, bank, 15 + tod * 2, 16 + tod * 2)
      if onAir == 3 then call.queue[#call.queue + 1] = line(call, bank, 36) return end
      local r = rand(11 + (S.gameClear(save) and 3 or 0))
      if r == 13 then call.queue[#call.queue + 1] = gendered(call, bank, 34, 35)
      else call.queue[#call.queue + 1] = line(call, bank, 21 + r) end
    end }
  end
  if onAir == 3 then return { kind = "simple", script = 100 } end
  if home then return { kind = "simple", script = 98 } end
  return { kind = "custom", build = function(call)
    call.queue[#call.queue + 1] = gendered(call, call.bank, 3 + tod * 2, 4 + tod * 2)
    call.queue[#call.queue + 1] = line(call, call.bank, 10 + rand(3))
  end }
end

-- ---------------------------------------------------------- ETHAN / LYRA
-- GearPhoneCall_GetEthanLyraMessage's 73 maps (header ids, maps.h), and
-- ov101_021F8760: which unlock each of the 73 place lines needs
S.ETHAN_MAPS = { 9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,91,92,93,27,28,29,30,31,32,33,34,35,
  36,37,38,39,40,41,42,43,94,95,44,45,46,47,48,151,152,49,50,51,52,53,54,55,56,57,58,59,60,67,73,74,75,76,
  77,78,87,88,89,90,96,113,174 }
S.ETHAN_UNLOCK = { 3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,2,2,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,1,1,3,3,3,3,3,3,3,3,3,2,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1 }
local function flypoint(save, fp) return flag(save, 0x9B0 + fp) end
function S.ethanPlaceLine(game)
  local level = tonumber(((game.save or {}).hgssPokegear or {}).mapLevel) or 0
  -- sp0[1..3] are undefined on the cartridge when their test fails; 0 here
  local ok = { [0] = true, [1] = flypoint(game.save, 25), [2] = level ~= 0, [3] = level > 1 }
  local list = {}
  for i, u in ipairs(S.ETHAN_UNLOCK) do if ok[u] then list[#list + 1] = i - 1 end end
  return 86 + list[rand(#list) + 1]
end
function S.ethanLyra(game, opts, entry, home)
  local tod = S.wildTimeOfDay()
  if opts.incoming then
    return { kind = "custom", build = function(call)
      call.queue[#call.queue + 1] = line(call, call.bank, 7 + tod)
      if rand(1000) < 500 then
        call.queue[#call.queue + 1] = line(call, call.bank, 10 + math.floor(rand(900) / 300))
      else
        call.queue[#call.queue + 1] = line(call, call.bank, S.ethanPlaceLine(game))
      end
    end }
  end
  if home then
    local girl = game.save.player and game.save.player.gender == "girl"
    return { kind = "simple", script = girl and 101 or 102 }
  end
  return { kind = "custom", build = function(call)
    call.queue[#call.queue + 1] = line(call, call.bank, 4 + tod)
    local msg
    for i, id in ipairs(S.ETHAN_MAPS) do if id == opts.headerId then msg = 13 + i - 1 break end end
    call.queue[#call.queue + 1] = line(call, call.bank, msg or (10 + rand(3)))
  end }
end

-- ----------------------------------------------------------- GYM LEADERS
function S.gymLeader(game, opts, entry, home)
  local save = game.save
  local caller = opts.caller
  local sixteen = S.badges(game) >= 16
  local seeking = S.state(save).seeking[caller] and true or false
  if opts.incoming then
    return { kind = "custom", build = function(call)
      call.queue[#call.queue + 1] = line(call, call.bank, 10)
      call.queue[#call.queue + 1] = line(call, call.bank, seeking and 11 or (12 + rand(3)))
    end }
  end
  return { kind = "custom", build = function(call)
    local bank, q = call.bank, call.queue
    if home then q[#q + 1] = line(call, bank, 1) return end
    q[#q + 1] = line(call, bank, 2)
    if not sixteen then q[#q + 1] = line(call, bank, 3) return end
    if seeking then q[#q + 1] = line(call, bank, 9) return end
    if not entry or weekday() ~= entry.rematchWeekday or S.wildTimeOfDay() ~= entry.rematchTimeOfDay then
      q[#q + 1] = line(call, bank, 4) return
    end
    q[#q + 1] = line(call, bank, 5)
    q[#q + 1] = menu(call, 18, 2, function(i)
      if i ~= 1 then after(call, { line(call, bank, 7) }) return end
      -- isDojoFull looks at Falkner alone, so "full" never comes up
      S.state(save).seeking[caller] = true
      after(call, { line(call, bank, 6) })
    end)
  end }
end

-- ----------------------------------------------------------------- KENJI
function S.kenji(game, opts, entry, home)
  local st = S.state(game.save)
  if home then return { kind = "simple", script = 86 } end
  local wait = tonumber(st.kenjiWaitDays) or 0
  if wait > 1 then return { kind = "simple", script = 87 } end
  if wait == 1 then return { kind = "simple", script = 88 } end
  local active = st.kenjiActive and true or false
  if active and not st.seeking[S.KENJI] then return { kind = "simple", script = 87 } end
  local t = S.rtcTimeOfDay()
  if t == 2 or t == 3 then return { kind = "simple", script = 91 } end
  if not active then st.kenjiActive = true; st.seeking[S.KENJI] = true end
  return { kind = "simple", script = S.wildTimeOfDay() == 1 and 90 or 89 }
end
-- sub_0202F294, the day rollover: Kenji stops, a new wait of 1..6 days
function S.kenjiNewDay(save, days)
  local st = S.state(save)
  st.kenjiActive = false
  st.gift[S.KENJI] = nil
  st.seeking[S.KENJI] = nil
  local w = tonumber(st.kenjiWaitDays) or 0
  if days > 0 and w >= days then st.kenjiWaitDays = w - days
  else st.kenjiWaitDays = rand(6) + 1 end
end

-- ----------------------------------------------------------------- IRWIN
local function irwinLadder(game, call)
  local save = game.save
  local function once(f, script)
    if flag(save, f) then return nil end
    call[#call + 1] = f
    return script
  end
  if not flag(save, 0x998) then return nil end
  call[#call + 1] = -0x998
  if S.badges(game) >= 16 then return once(0x9A4, 168) end
  if S.hasBadge(game, S.BADGE.MARSH) then return once(0x9A3, 167) end
  if flag(save, 0xF9) then return once(0x9A2, 166) end
  if flag(save, 0x87) then return once(0x9A1, 165) end
  if flypoint(save, 5) then return 164 end   -- FLYPOINT_VERMILION
  if S.gameClear(save) then return once(0x9A5, 163) end
  if S.hasBadge(game, S.BADGE.RISING) then return 162 end
  if flag(save, 0xC6) then return 161 end
  if flag(save, 0xCA) then return once(0x9A0, 160) end
  if flag(save, 0x96A) then return once(0x99F, 159) end
  if S.hasBadge(game, S.BADGE.FOG) then return 158 end
  if S.hasBadge(game, S.BADGE.PLAIN) then return 157 end
  return nil
end
function S.irwin(game, opts)
  if not opts.incoming then
    if S.rocketTakeover(game.save) then return { kind = "simple", script = 156 } end
    return { kind = "simple", script = 172 + rand(3) }
  end
  local flags = {}
  local id = irwinLadder(game, flags)
  local plan
  if id then plan = { kind = "simple", script = id }
  elseif not S.hasBadge(game, S.BADGE.PLAIN) then plan = { kind = "simple", script = 169 }
  elseif S.badges(game) < 16 then plan = { kind = "simple", script = 170 }
  else plan = { kind = "simple", script = 171 } end
  -- the ladder's flags are written as the script id is chosen
  for _, f in ipairs(flags) do
    local name = ("FLAG_G4_%04X"):format(math.abs(f))
    game.save.flags = game.save.flags or {}
    game.save.flags[name] = f > 0 or nil
  end
  return plan
end

-- ----------------------------------------------------------------- BAOBA
function S.baoba(game, opts, entry, home)
  local save = game.save
  if opts.scripted == 2 then return { kind = "simple", script = 141 } end
  if opts.incoming then
    local p = opts.predefined or 0
    local Obj = require("src.world.HgssSafariObjects")
    -- scriptType 15: GearPhoneCall_Baoba, the areas with new Pokemon
    if p == 0 then return { kind = "custom", build = Obj.reportBuild } end
    if p == 142 then setVar(save, 0x4057, 4) return { kind = "simple", script = 142 } end
    if p >= 143 and p <= 146 then
      -- 143 / 144 one more object tier and the IGT mark; 145 / 146 four
      if p <= 144 then Obj.incUnlockLevel(save, 1); Obj.markIgt(save) else Obj.incUnlockLevel(save, 4) end
      setVar(save, 0x4057, 7)
      return { kind = "simple", script = p }
    end
    return { kind = "simple", script = 154 }
  end
  if home then return { kind = "simple", script = 140 } end
  return { kind = "simple", script = 147 + var(save, 0x4057) }
end

-- ------------------------------------------------- MOM / ELM / BIKE SHOP
-- (the incoming halves; the player's own calls are HgssPhoneOutgoing's)
function S.incomingBasic(game, opts, entry, home)
  local t = entry.type
  if t == TYPE.MOM then
    if home then return { kind = "simple", script = 23 } end
    return { kind = "simple", script = opts.predefined or 0 }
  end
  if t == TYPE.ELM then return { kind = "simple", script = opts.predefined or 0 } end
  if t == TYPE.BIKE_SHOP then return { kind = "simple", script = home and 84 or 85 } end
  return nil
end

local BY_TYPE = { [TYPE.OAK] = S.oak, [TYPE.BILL] = S.bill, [TYPE.KURT] = S.kurt,
  [TYPE.DAYCARE_LADY] = S.daycareLady, [TYPE.DAYCARE_MAN] = S.daycareMan, [TYPE.BUENA] = S.buena,
  [TYPE.ETHAN_LYRA] = S.ethanLyra, [TYPE.GYMLEADER] = S.gymLeader, [TYPE.KENJI] = S.kenji,
  [TYPE.IRWIN] = S.irwin, [TYPE.BAOBA] = S.baoba }

-- the plan for `caller`; nil when no handler here covers it
function S.plan(game, caller, opts)
  opts = opts or {}
  opts.caller = caller
  local pc = (game.data or {}).gen4_hgss_phone_call or {}
  local entry = (pc.book or {})[caller]
  if not entry then return nil end
  local home = opts.headerId ~= nil and entry.mapId == opts.headerId
  if opts.incoming and (entry.type == TYPE.MOM or entry.type == TYPE.ELM or entry.type == TYPE.BIKE_SHOP) then
    return S.incomingBasic(game, opts, entry, home)
  end
  local fn = BY_TYPE[entry.type]
  if not fn then return nil end
  return fn(game, opts, entry, home)
end

return S
