-- HEARTGOLD / SOULSILVER: A SCRIPTED POKEGEAR CALL (`RunPhoneCall`).
--
-- The overworld's `PhoneCall who, 2, n` (std_phone_call, scr_seq_0003) rings
-- twice, fades to black and launches the Pokegear on its phone with the call
-- already connected (PokegearPhone_LaunchApp, isScriptedLaunch 1). What runs
-- then is overlay 101's call engine, followed here state for state:
--
--   PhoneCall_InitContext       incoming, so mainState starts at 1 -- no
--                               outgoing "......" ring
--   PhoneCall_GetCallScriptId   the contact's phonebook TYPE picks the
--                               handler; a scripted call (isScriptedCall 2)
--                               answers from the code below (Elm: his
--                               map-script table at the third operand; Oak:
--                               082; Baoba: 141; Mom: her own handler)
--   GearPhoneCall_Simple        scriptDef.msgIds[gender] from the contact's
--                               bank (sPhoneMessageGmm), after a bank-640
--                               greeting when the phonebook row has one
--   GearPhoneCall_Mother        (scripted) 22, the savings menu (271 8/9),
--                               25 or 26, FLAG_SYS_MOMS_SAVINGS
--   PhoneCall_WaitButtonBeforeHangup   A or B, SEQ_SE_DP_SELECT
--   PhoneCall_HangupTone        SEQ_SE_GS_PHONE_OFF, "Click!" / "Click!\n......"
--                               / "Click!\n...... ......", ten frames apart
--   PhoneCall_Exit              undim, back to the contact list -- the
--                               Pokegear stays open and the player closes it
--
-- THE TWO SCREENS. The call is printed on the SUB engine (the DS's top
-- screen; windows 0 and 1 on GF_BG_LYR_SUB_2: name at tiles 4,16 9x2, the
-- message at 2,19 27x4), while the MAIN engine (the touch screen) shows the
-- contact list dimmed 8/16 toward black (PokegearPhone_SetTouchscreenDimState).
-- Here the top screen is the window and the touch screen is SecondScreen.
--
-- Data: data.gen4_hgss_phone_call (src/import/Gen4HgssPhoneCall.lua) and the
-- Pokegear pictures and contact banks of data.gen4_hgss_pokegear_art.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local SecondScreen = require("src.ui.SecondScreen")
local Logger = require("src.core.Logger")

local Call = {}
Call.__index = Call
Call.isOpaque = true

local SE_SELECT, SE_PHONE_OFF = 1500, 2170
local FLAG_TALKED_TO_MOM_AFTER_NAMING_RIVAL, FLAG_SYS_MOMS_SAVINGS = 0xA7, 0x986
-- PokegearPhone phonebook TYPEs (gear_phone.h PHONECALLTYPE_*)
local TYPE_MOM, TYPE_ELM, TYPE_OAK, TYPE_BAOBA = 1, 2, 3, 13
-- the call windows, in sub-screen pixels (sWindowTemplates 0 and 1)
local MSG_X, MSG_Y, MSG_W, LINE_H = 16, 152, 216, 16
local NAME_X, NAME_Y = 32, 128
local FADE_FRAMES, HANGUP_GAP = 6, 10

function Call:uiSize() return 256, 192 end
function Call:wantsFillScale() return true end
function Call:wantsEdgeBleed() return false end

function Call.available(game)
  local d = game and game.data
  return d and type(d.gen4_hgss_phone_call) == "table" and d.gen4_hgss_phone_call.scripts ~= nil
end

local function textOf(game, bank, index)
  local T = require("src.import.Gen4Text")
  return T.resolve(game.data, bank, index, game)
end

-- PhoneCall_GetCallScriptId for a scripted call (isScriptedCall 2) of the
-- contacts the overworld scripts ring. Answers { kind = "simple", script } or
-- { kind = "mother" }. Any other contact or call kind goes the way every
-- handler's incoming branch does: the script id as given.
function Call.choose(data, caller, kind, id)
  local pc = data.gen4_hgss_phone_call
  local entry = pc.book and pc.book[caller]
  local t = entry and entry.type
  if kind == 2 then
    if t == TYPE_ELM then
      local row = pc.elmMapScripts and pc.elmMapScripts[id]
      if row then return { kind = row.scriptType == 0 and "simple" or "unsupported", script = row.script } end
    elseif t == TYPE_OAK then
      return { kind = "simple", script = 82 }
    elseif t == TYPE_BAOBA then
      return { kind = "simple", script = 141 }
    elseif t == TYPE_MOM then
      return { kind = "mother", sets = { FLAG_TALKED_TO_MOM_AFTER_NAMING_RIVAL } }
    end
  end
  return { kind = "simple", script = id }
end

-- the incoming plan: a route trainer's eight incoming rows of
-- sGenericPhoneCallHeaders, every other contact its handler's incoming branch
function Call.incomingPlan(game, call)
  local pc = (game.data or {}).gen4_hgss_phone_call or {}
  local entry = (pc.book or {})[call.caller]
  if not entry then return { kind = "unsupported" } end
  local headerId = call.headerId
  if headerId == nil then
    local okR, Ring = pcall(require, "src.world.HgssPhoneRing")
    if okR then headerId = Ring.headerId(game) end
  end
  if entry.type == 0 then
    local Out = require("src.ui.HgssPhoneOutgoing")
    return Out.generic(game, call.caller, entry, nil, 8) or { kind = "generic", scriptType = 0, script = 0 }
  end
  local okS, Scripts = pcall(require, "src.ui.HgssPhoneScripts")
  local plan = okS and Scripts.plan(game, call.caller,
    { incoming = true, scripted = call.kind, predefined = call.id, headerId = headerId })
  return plan or { kind = "unsupported" }
end

function Call.new(game, call, onDone, ctx)
  local self = setmetatable({ game = game, call = call, onDone = onDone, ctx = ctx,
    cache = {}, t = 0, phase = "fadein", queue = {}, lines = {}, menuIndex = 1, scroll = 0 }, Call)
  local data = game.data
  self.pc = data.gen4_hgss_phone_call
  self.skin = (tonumber((game.save.hgssPokegear or {}).skin) or 0) % 6
  self.girl = game.save.player and game.save.player.gender == "girl"
  local contact = ((data.gen4_hgss_pokegear_art or {}).contacts or {})[call.caller]
  self.bank = contact and contact.bank
  self.name = (self.bank and textOf(game, self.bank, 0)) or (contact and contact.name) or ""
  self.plan = Call.choose(data, call.caller, call.kind, call.id)
  -- AN OUTGOING CALL (the player rang them from the Pokegear's list):
  -- src/ui/HgssPhoneOutgoing.lua picks the script, the open Pokegear stays
  -- under the call, and PhoneCall_InitialRing rings first
  if call.outgoing then
    self.plan = require("src.ui.HgssPhoneOutgoing").choose(game, call.caller, call.header, call.headerId)
    if self.plan.kind ~= "outofarea" then self.phase = "ring" end
  end
  -- A CALL THE RING MANAGER PUT THROUGH (src/world/HgssPhoneRing.lua): a
  -- random call (isScriptedCall 0) or a trigger's (3), connected when the
  -- player opened the Pokegear while it rang, or forced through scr_seq_0003
  -- 047; the handler's incoming branch picks the script
  if call.ring then self.plan = Call.incomingPlan(game, call) end
  if call.gear then
    self.gear = call.gear
  else
    local ok, Gear = pcall(require, "src.ui.HgssPokegear")
    if ok then self.gear = Gear.new(game, { app = "phone", silent = true }) end
  end
  self:script()
  return self
end

-- the message's lines from the contact's bank, with the call's own string
-- template (PhoneCall_InitMsgDataAndBufferNames: 0 the player, 1 the
-- contact) -- spliced into a copy of the buffers, so the script's own slots
-- are what they were when the call ends
function Call:message(bank, index)
  local game = self.game
  local saved = game.stringBuffers
  game.stringBuffers = {}
  for k, v in pairs(saved or {}) do game.stringBuffers[k] = v end
  game.stringBuffers[1] = tostring(game.save.player and game.save.player.name or "")
  game.stringBuffers[2] = self.name
  for k, v in pairs(self.extraBuffers or {}) do game.stringBuffers[k] = v end
  local text = textOf(game, bank, index)
  game.stringBuffers = saved
  if not text then
    Logger.warn("hgss phone: bank %s entry %s is not in this cache", tostring(bank), tostring(index))
  end
  return text or ""
end

function Call:say(bank, index) self.queue[#self.queue + 1] = { say = self:message(bank, index) } end
function Call:step(fn) self.queue[#self.queue + 1] = { run = fn } end

-- the handler's script, as a queue of lines and actions
function Call:script()
  local plan, pc = self.plan, self.pc
  if plan.kind == "outofarea" then
    -- PhoneCall_Main 255..258: "......" x3 with no tone, the hang-up tone,
    -- then bank 271 37 "That number is out of the area."
    self:step(function() self.outOfArea = true end)
    self.queue[#self.queue + 1] = { say = (pc.texts and pc.texts[37]) or self:message(271, 37) }
    return
  end
  if plan.kind == "custom" then
    -- a handler of src/ui/HgssPhoneScripts.lua queues its own lines and menus
    plan.build(self)
    return
  end
  if plan.kind == "unsupported" then
    Logger.warn("hgss phone: calling contact %s is not ported yet (its handler picks the script)",
      tostring(self.call.caller))
    return
  end
  if plan.kind == "mother" and plan.outgoing then
    -- GearPhoneCall_Mother, the player calling: the intro by where the
    -- player is (bank 664 7 + momCallIntro), then the savings prompt --
    -- 23 / 27 saving (with / without a balance), 24 / 28 not -- and the menu
    local balance = tonumber(self.game.save.hgssMomSavings) or 0
    local saving = (self.game.save.flags or {})[("FLAG_G4_%04X"):format(FLAG_SYS_MOMS_SAVINGS)] == true
    self.extraBuffers = { [11] = tostring(balance) }
    self:say(self.bank, 7 + (tonumber(plan.intro) or 0))
    -- state 1: her gift queue full (MomGiftQueue_IsFull) -- 21, and the call ends
    local q = self.game.save.hgssMomGifts
    if type(q) == "table" and #q >= 5 then
      self:say(self.bank, 21)
      return
    end
    self:say(self.bank, saving and (balance ~= 0 and 23 or 27) or (balance ~= 0 and 24 or 28))
    self.queue[#self.queue + 1] = { menu = { pc.texts and pc.texts[8] or "", pc.texts and pc.texts[9] or "" },
      choose = function(i)
        self:flag(FLAG_SYS_MOMS_SAVINGS, i == 1)
        table.insert(self.queue, self.at + 1, { say = self:message(self.bank, i == 1 and 25 or 26) })
      end }
    return
  end
  if plan.kind == "mother" then
    for _, f in ipairs(plan.sets or {}) do self:flag(f, true) end
    -- scripted: straight to MomCallGetSaveMoneyPromptMsg's 22, then the menu
    self:say(self.bank, 22)
    self.queue[#self.queue + 1] = { menu = { pc.texts and pc.texts[8] or "", pc.texts and pc.texts[9] or "" },
      choose = function(i)
        self:flag(FLAG_SYS_MOMS_SAVINGS, i == 1)
        table.insert(self.queue, self.at + 1, { say = self:message(self.bank, i == 1 and 25 or 26) })
      end }
    return
  end
  local def = pc.scripts and pc.scripts[plan.script]
  if (plan.kind ~= "simple" and plan.kind ~= "generic") or not def then
    Logger.warn("hgss phone: no script %s for contact %s (%s, %s)", tostring(plan.script),
      tostring(self.call.caller), tostring(self.call.kind), tostring(self.call.id))
    return
  end
  self:sideEffect(def)
  local handler = plan.kind == "generic" and (plan.scriptType or 0) or 0
  if handler == 1 then
    -- GearPhoneCall_Generic: slot 10 one of their Pokemon, slot 11 a wild
    -- one from their route at this time of day
    self.extraBuffers = self.extraBuffers or {}
    self.extraBuffers[11] = self:speciesName(self:trainerMon()) or ""
    self.extraBuffers[12] = self:speciesName(self:wildMon()) or ""
  end
  local entry = pc.book and pc.book[self.call.caller]
  local greet = entry and entry.greeting
  if greet and greet ~= 0xFF and pc.greetings and pc.greetings[greet] then
    -- PhoneCall_PrintGreeting: timeOfDay * 2 + incoming * 6, Ethan / Lyra
    -- GF_RTC_GetTimeOfDayWildParamByHour: morning 0, day / evening 1, night 2
    local band = require("src.import.Gen4Encounters").timeOfDayForHour(tonumber(os.date("%H")))
    local tod = (band == 0 and 0) or ((band == 1 or band == 2) and 1) or 2
    local row = pc.greetings[greet]
    local k = tod * 2 + (self.call.outgoing and 0 or 6) + (self.girl and 1 or 0)
    if row[k] then self:say(640, row[k]) end
  end
  if handler == 2 then
    -- GearPhoneCall_Generic2: one of eleven lines from the script's first
    local r = math.random(0, 10)
    if def[1] == def[2] then self:say(self.bank, def[1] + r)
    else self:say(self.bank, self.girl and (def[2] + 2 * r + 1) or (def[1] + 2 * r)) end
    return
  end
  self:say(self.bank, def[self.girl and 2 or 1])
end

-- PhoneCall_ApplyGenericNPCcallSideEffect by the script's kind: 1 / 2 a flag,
-- 3 a rematch the contact now seeks, 4 a gift they now hold (a Cheri Berry
-- is any of the ten berries, a Poke Ball any of three balls from the Ultra
-- Ball), 5 a word from their bank into slot 4 -- the rematch / gift kept in
-- save.hgssPhoneState (the field reads them: GetPhoneBookRematch, the trainer
-- script's GetPhoneContactGiftItem)
function Call:sideEffect(def)
  local caller = self.call.caller
  if def.kind == 1 or def.kind == 2 then
    self:flag(def.param1, def.param0 ~= 0)
  elseif def.kind == 3 or def.kind == 4 then
    local st = require("src.ui.HgssPhoneOutgoing").state(self.game.save)
    if def.kind == 3 then st.seeking[caller] = true
    else
      local item = def.param1
      if item == 149 then item = 149 + math.random(0, 9)
      elseif item == 4 then item = 2 + math.random(0, 2) end
      st.gift[caller] = item
    end
  elseif def.kind == 5 and (def.param0 or 0) > 0 then
    self.extraBuffers = self.extraBuffers or {}
    self.extraBuffers[5] = self:message(self.bank, def.param1 + math.random(0, def.param0 - 1))
  end
end

function Call:speciesName(id)
  local def = id and ((self.game.data or {}).pokemon or {})[id]
  return def and def.name
end

-- getRandomTrainerMon: one of the contact's trainer's party (Rattata when
-- the trainer is not known)
function Call:trainerMon()
  local entry = ((self.pc or {}).book or {})[self.call.caller]
  local tr = entry and ((self.game.data or {}).trainers or {})[entry.trainerId]
  local party = tr and tr.party or {}
  if #party == 0 then return 19 end
  return tonumber(party[math.random(1, #party)].species) or 19
end

-- getRandomEncounterSlot: a Good Rod slot for a Fisherman (class 0x? by the
-- book), else one of the twelve land slots of the time of day, on the
-- contact's home map; Rattata where it has no wild encounters
function Call:wildMon()
  local data = self.game.data or {}
  local entry = ((self.pc or {}).book or {})[self.call.caller]
  if not entry then return 19 end
  local def
  for _, m in pairs(data.maps or {}) do
    if type(m) == "table" and tonumber(m.header) == entry.mapId then def = m break end
  end
  local area = def and def.encounters and (data.encounters or {})[def.encounters]
  if not area then return 19 end
  local band = require("src.import.Gen4Encounters").timeOfDayForHour(tonumber(os.date("%H")))
  local tod = (band == 0 and "morning") or ((band == 1 or band == 2) and "day") or "night"
  local className = ((data.trainers or {})[entry.trainerId] or {}).className
  if className == "Fisherman" and area.goodRod and area.goodRod.slots then
    local slot = area.goodRod.slots[math.random(1, 5)]
    return slot and tonumber(slot.species) or 19
  end
  local slots = area.timed and area.timed[tod]
  local pick = slots and slots[math.random(1, 12)]
  if (tonumber(pick) or 0) == 0 then return 19 end
  return tonumber(pick)
end

function Call:flag(id, on)
  local ctx = self.ctx or { save = self.game.save, game = self.game }
  local C = require("src.script.Commands")
  local name = ("FLAG_G4_%04X"):format(id)
  if on then C.set_flag(ctx, name) else C.clear_flag(ctx, name) end
end

-- ---------------------------------------------------------------- printing
local function speed(game)
  local d = game.save.options and game.save.options.textSpeed or 3
  if d ~= 1 and d ~= 3 and d ~= 5 then d = 3 end
  return d
end

function Call:begin(text)
  self.spans = Font.split(text)
  self.text, self.pos, self.timer = text, 0, 0
  self.lines, self.row = { "" }, 1
  self.wait, self.scroll = nil, 0
end

-- one glyph; answers false when the message is done
function Call:advance()
  self.pos = self.pos + 1
  local span = self.spans[self.pos]
  if not span then return false end
  local ch = self.text:sub(span.from, span.to)
  if ch == "\n" then  -- strings: comparing against a control code
    self.row = self.row + 1
    self.lines[self.row] = ""
  elseif ch == "\v" then
    self.wait = "clear"       -- 0x25BC: wait, clear, back to the top
  elseif ch == "\f" then  -- strings: comparing against a control code
    self.wait = "scroll"      -- 0x25BD: wait, scroll one line, same row
  else
    self.lines[self.row] = (self.lines[self.row] or "") .. ch
  end
  return true
end

-- answers true when the current message has printed through
function Call:printing()
  local input = self.game.input
  if self.scroll > 0 then
    -- ScrollWindow 4 pixels a frame
    self.scroll = self.scroll - 4
    if self.scroll <= 0 then
      -- everything moved up a line; printing goes on at the same row
      self.scroll = 0
      table.remove(self.lines, 1)
      for i = #self.lines, self.row, -1 do self.lines[i] = nil end
      self.lines[self.row] = ""
    end
    return false
  end
  if self.wait then
    if input:wasPressed("a") or input:wasPressed("b") then
      require("src.core.Sound").play(self.game.data, SE_SELECT)
      if self.wait == "clear" then self.lines, self.row = { "" }, 1
      else self.scroll = LINE_H end
      self.wait = nil
    end
    return false
  end
  local delay = speed(self.game)
  if input:isDown("a") or input:isDown("b") then delay = 1 end
  self.timer = self.timer + 1
  while self.timer >= delay do
    self.timer = self.timer - delay
    if not self:advance() then return true end
    if self.wait then return false end
  end
  return false
end

-- ---------------------------------------------------------------- the beat
function Call:update(dt)
  self.t = self.t + 1
  local input = self.game.input
  if self.phase == "ring" then
    -- PhoneCall_InitialRing: SEQ_SE_GS_PHONE0 and "......", again with
    -- "...... ......", then the handler (a ring is about 40 frames here)
    self.ringT = (self.ringT or 0) + 1
    local n = self.ringT == 1 and 1 or (self.ringT == 41 and 2 or nil)
    if n then
      local ok, Sound = pcall(require, "src.core.Sound")
      if ok and Sound.playSe then pcall(Sound.playSe, self.game.data, "SEQ_SE_GS_PHONE0") end
      self.lines = { (self.pc.texts and self.pc.texts[29 + n]) or "......" }
    end
    if self.ringT >= 80 then
      self.lines = {}
      self.phase, self.at = "run", 0
      self:next()
    end
  elseif self.phase == "fadein" then
    if self.t >= FADE_FRAMES then self.phase, self.at = "run", 0; self:next() end
  elseif self.phase == "say" then
    if self:printing() then self:next() end
  elseif self.phase == "menu" then
    local item = self.queue[self.at]
    -- TouchscreenListMenu: wraps round; B is the last row (Quit / No)
    local n = #(self.menu or {})
    if input:wasPressed("up") then
      self.menuIndex = (self.menuIndex - 2) % n + 1
    elseif input:wasPressed("down") then
      self.menuIndex = self.menuIndex % n + 1
    elseif input:wasPressed("a") or input:wasPressed("b") then
      require("src.core.Sound").play(self.game.data, SE_SELECT)
      local pick = input:wasPressed("a") and self.menuIndex or n
      self.menu = nil
      item.choose(pick)
      self:next()
    end
  elseif self.phase == "hangupwait" then
    if input:wasPressed("a") or input:wasPressed("b") then
      require("src.core.Sound").play(self.game.data, SE_SELECT)
      require("src.core.Sound").play(self.game.data, SE_PHONE_OFF)
      self.phase, self.t, self.click = "hangup", 0, 0
      self.lines = { self.pc.texts and self.pc.texts[33] or "Click!" }
    end
  elseif self.phase == "hangup" then
    if self.t > HANGUP_GAP then
      self.t = 0
      self.click = self.click + 1
      if self.click >= 3 then return self:finish() end
      self.lines = {}
      for line in ((self.pc.texts and self.pc.texts[33 + self.click]) or "Click!"):gmatch("[^\n]+") do
        self.lines[#self.lines + 1] = line
      end
    end
  end
end

function Call:next()
  self.at = self.at + 1
  local item = self.queue[self.at]
  if not item then
    self.phase = "hangupwait"
    return
  end
  if item.lazy then item.say = item.lazy(self); item.lazy = nil end
  if item.say then
    self.phase = "say"
    self:begin(item.say)
  elseif item.menu then
    self.phase, self.menu, self.menuIndex = "menu", item.menu, 1
  elseif item.run then
    item.run(self)
    return self:next()
  end
end

-- PhoneCall_Exit: back to the contact list, which is the Pokegear itself
function Call:finish()
  if self.done then return end
  self.done = true
  local game, onDone = self.game, self.onDone
  if self.call.outgoing then
    game.stack:pop()
    if onDone then onDone() end
    return
  end
  game.stack:pop()
  local ok, Gear = pcall(require, "src.ui.HgssPokegear")
  if ok and Gear then
    -- PhoneCall_Exit: the contact list, the cursor in it (not on the bar)
    game.stack:push(Gear.new(game, { onCancel = onDone, app = "phone", zone = false, silent = true }))
  elseif onDone then
    onDone()
  end
end

-- ---------------------------------------------------------------- drawing
function Call:picture(key)
  local rec = (self.game.data.gen4_hgss_pokegear_art or {})[key .. "_" .. self.skin]
  if not rec then return end
  local path = type(rec) == "table" and rec.path or rec
  if self.cache[path] == nil then self.cache[path] = Assets.image(path) or false end
  if self.cache[path] then love.graphics.setColor(1, 1, 1, 1); love.graphics.draw(self.cache[path], 0, 0) end
end

local function rgb(c, fallback)
  if type(c) ~= "table" then return fallback end
  return { (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255 }
end

function Call:ink()
  local ink = self.pc.ink and self.pc.ink[self.skin] or {}
  return { text = rgb(ink.text, { 1, 1, 1 }), shadow = rgb(ink.shadow, { 0.48, 0.48, 0.48 }) }
end

function Call:drawMenu(x, y)
  local g = love.graphics
  local items = self.menu
  local w, h = 176, #items * 16 + 8
  g.setColor(1, 1, 1, 1); g.rectangle("fill", x, y, w, h)
  g.setColor(0.2, 0.2, 0.2, 1); g.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.75, 0.75, 0.75 } })
  for i, label in ipairs(items) do
    Font.draw(label, x + 14, y + 4 + (i - 1) * 16)
  end
  Font.popStyle()
  local cy = y + 4 + (self.menuIndex - 1) * 16 + 4
  g.setColor(0.25, 0.25, 0.25, 1)
  g.polygon("fill", x + 5, cy, x + 5, cy + 8, x + 10, cy + 4)
  g.setColor(1, 1, 1, 1)
end

-- the sub engine: the call
function Call:subPanel()
  local g = love.graphics
  g.setColor(1, 1, 1, 1); g.rectangle("fill", 0, 0, 256, 192)
  self:picture("frame_bottom")
  self:picture("phone_bottom")
  -- the shell's clock stays up through the call (its OBJ is on SUB)
  if self.gear and self.gear.drawClock then pcall(self.gear.drawClock, self.gear) end
  Font.pushStyle(self:ink())
  if self.phase ~= "fadein" then Font.draw(self.name, NAME_X, NAME_Y) end
  g.setScissor(MSG_X, MSG_Y, MSG_W, LINE_H * 2)
  local lift = (self.scroll > 0) and (LINE_H - self.scroll) or 0
  for i = 1, 2 do
    local line = self.lines and self.lines[i]
    if line and line ~= "" then Font.draw(line, MSG_X, MSG_Y + (i - 1) * LINE_H - lift) end
  end
  g.setScissor()
  Font.popStyle()
  if self.phase == "say" and self.wait and math.floor(self.t / 8) % 2 == 0 then
    local ink = self:ink().text
    g.setColor(ink[1], ink[2], ink[3], 1)
    local ax, ay = MSG_X + MSG_W - 10, MSG_Y + LINE_H + 5
    g.polygon("fill", ax, ay, ax + 7, ay, ax + 3.5, ay + 5)
    g.setColor(1, 1, 1, 1)
  end
end

-- the main engine: the contact list, dimmed while the call is up
function Call:mainPanel(withMenu)
  local g = love.graphics
  if self.gear then self.gear:panel(false) else g.setColor(0, 0, 0, 1); g.rectangle("fill", 0, 0, 256, 192) end
  g.setColor(0, 0, 0, 0.5); g.rectangle("fill", 0, 0, 256, 192)
  g.setColor(1, 1, 1, 1)
  if withMenu and self.menu then self:drawMenu(7 * 8, 11 * 8) end
end

function Call:draw()
  local g = love.graphics
  local dual = SecondScreen.separate(self.game)
  self:subPanel()
  if dual then
    SecondScreen.draw(self.game, function() self:mainPanel(true) end)
  elseif self.menu then
    -- no touch screen in view: the savings menu comes up over the call
    self:drawMenu(40, 88)
  end
  if self.phase == "fadein" then
    g.setColor(0, 0, 0, 1 - math.min(1, self.t / FADE_FRAMES))
    g.rectangle("fill", 0, 0, 256, 192)
    g.setColor(1, 1, 1, 1)
  end
end

return Call
