-- Adapted from Gen1Recomp 535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91.
-- Existing project rights and Gen1Recomp provenance remain applicable; see LICENSE.MD.
-- The Pokemon Center PC's whose-PC menu (engine/events/pokecenter_pc.asm
-- PokemonCenterPC).  Every Pokecenter reaches it the same way: the PC is a
-- COLL_PC tile, the A press runs PCScript (engine/events/std_scripts.asm) and
-- its `special PokemonCenterPC` opens this screen through World:openPc.
--
-- .ChooseWhichPCListToUse picks the row list:
--
--   PCPC_BEFORE_POKEDEX  BILL's PC / <PLAYER>'s PC / TURN OFF
--   PCPC_BEFORE_HOF      + PROF.OAK's PC        (CheckReceivedDex)
--   PCPC_POSTGAME        + HALL OF FAME         (wHallOfFameCount > 0)
--
-- BILL's PC opens the storage system (src/ui/gen2/PcMenu.lua, _BillsPC's own
-- five rows), <PLAYER>'s PC the item PC (src/ui/gen2/ItemPcMenu.lua,
-- PLAYERSPC_NORMAL), PROF.OAK's PC the #DEX rating (ProfOaksPC,
-- engine/events/prof_oaks_pc.asm) and HALL OF FAME the roster viewer
-- (src/ui/gen2/HallOfFame.lua "view" mode, _HallOfFamePC).

local Chrome = require("src.ui.Gen2Chrome")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")
local Specials = require("src.core.Gen2PokedexRating")
local Strings = require("src.core.Strings")
local Typer = require("src.ui.Gen2Typer")

local CenterPcMenu = {}
CenterPcMenu.__index = CenterPcMenu
-- ../pokecrystal/engine/events/pokecenter_pc.asm:15
CenterPcMenu.isOpaque = false

-- ENGINE_POKEDEX (constants/engine_flags.asm, index 11): the flag
-- CheckReceivedDex reads and Mr.Pokemon's `setflag ENGINE_POKEDEX` writes.
-- The port lands plain ENGINE_* ids on save.engineFlags
-- (World:setEngineFlag), so the same store answers here.
local ENGINE_POKEDEX = 11

-- Text owned by PokemonCenterPC/ProfOaksPC. Keep each cart message as one
-- catalog key so a translation may reflow or reorder it without inheriting
-- the English line fragments.
local TEXT = {
  -- data/text/common_2.asm:725 _PokecenterPCCantUseText ends in `cont`
  -- (\v scrolls "have a #MON to" up and lands "use this!" under it), not a
  -- third bare \n line (which pagesOf() renders as its own one-line page
  -- instead of a scroll).
  noMon = Strings.source("Bzzzzt! You must\nhave a #MON to\vuse this!"),
  turnedOn = Strings.source("{PLAYER} turned on\nthe PC."),
  billsPc = Strings.source("BILL's PC"),
  playersPc = Strings.source("%s's PC"),
  oaksPc = Strings.source("PROF.OAK's PC"),
  hallOfFame = Strings.source("HALL OF FAME"),
  turnOff = Strings.source("TURN OFF"),
  oakClosed = Strings.source("The link to PROF.\nOAK's PC closed."),
  linkClosed = Strings.source("…\nLink closed…"),
  billsOpened = Strings.source(
    "BILL's PC\naccessed.\n\n#MON Storage\nSystem opened."),
  ownOpened = Strings.source(
    "Accessed own PC.\n\nItem Storage\nSystem opened."),
  oakOpened = Strings.source(
    "PROF.OAK's PC\naccessed.\n\n#DEX Rating\nSystem opened."),
  rateDex = Strings.source("Want to get your\n#DEX rated?"),
  accessWhose = Strings.source("Access whose PC?"),
}

function CenterPcMenu:wantsFillScale() return true end

-- `\f` = para (home/text.asm:403 Paragraph), `\v` = cont (home/text.asm:442
-- _ContTextNoPause); two rows to a page (constants/text_constants.asm:32).
local function pagesOf(body)
  local pages = {}
  for chunk in (tostring(body) .. "\f"):gmatch("(.-)\f") do
    local flat, pos, scrolled = {}, 1, false
    while true do
      local brk = chunk:find("[\n\v]", pos)
      local line = brk and chunk:sub(pos, brk - 1) or chunk:sub(pos)
      if line ~= "" then flat[#flat + 1] = { line, scrolled } end
      if not brk then break end
      scrolled = chunk:sub(brk, brk) == "\v"
      pos = brk + 1
    end
    local page
    for _, entry in ipairs(flat) do
      if not page then
        page = { entry[1] }
        pages[#pages + 1] = page
      elseif entry[2] then
        page = { page[#page], entry[1] }
        pages[#pages + 1] = page
      elseif #page >= 2 then
        page = { entry[1] }
        pages[#pages + 1] = page
      else
        page[#page + 1] = entry[1]
      end
    end
  end
  return pages
end

local function translatedPages(source, ...)
  return pagesOf(Strings(source, ...))
end

-- opts: save, events, items (items.lua), onClose()
function CenterPcMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, CenterPcMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.items = opts.items or (game and game.data and game.data.items)
  self.data = game and game.data
  self.events = opts.events
  self.onClose = opts.onClose or opts.onCancel or function() game.stack:pop() end
  self.index = 1
  self.message = nil
  self.confirm = nil
  self.closed = false
  self.booted = false
  self:buildEntries()
  local party = self.save and self.save.party
  if not (party and #party > 0) then
    -- PC_CheckPartyForPokemon: SFX_CHOOSE_PC_OPTION, the refusal, and the PC
    -- never boots (`ret c` before PC_PlayBootSound).
    -- data/text/common_2.asm:725 _PokecenterPCCantUseText ends in cont.
    self:playSfx("Sfx_ChoosePcOption")
    self:say(translatedPages(TEXT.noMon),
      function() self:close() end)
  else
    -- PC_PlayBootSound + _PokecenterPCTurnOnText.
    self:playSfx("Sfx_BootPc")
    -- ../pokecrystal/engine/events/pokecenter_pc.asm:22
    self:say(translatedPages(TEXT.turnedOn),
      function() self.booted = true end)
  end
  return self
end

function CenterPcMenu:playSfx(name)
  local data = self.data
  local sfx = data and data.audio and data.audio.sfx
  if sfx and sfx[name] then
    Sound.play(data, name)
  end
end

function CenterPcMenu:playerName()
  local player = self.save and self.save.player
  return (player and player.name) or "GOLD"
end

-- .WhichPC, gated the way .ChooseWhichPCListToUse gates it.  TURN OFF is
-- always last; the extra rows slot in above it in PCPCITEM_* order.
function CenterPcMenu:buildEntries()
  local save = self.save
  local hasDex = save and save.flags and save.flags.ENGINE_POKEDEX == true
  local hofCount = (save and (type(save.hallOfFame)=="table" and (save.hallOfFame.count or #save.hallOfFame) or save.hallOfFameCount or save.hallOfFame)) or 0
  local entries = {
    { id = "bills", label = Strings(TEXT.billsPc) },
    { id = "players", label = Strings(TEXT.playersPc, self:playerName()) },
  }
  if hasDex then
    entries[#entries + 1] = { id = "oaks", label = Strings(TEXT.oaksPc) }
    if hofCount > 0 then
      entries[#entries + 1] = { id = "hof", label = Strings(TEXT.hallOfFame) }
    end
  end
  entries[#entries + 1] = { id = "turnoff", label = Strings(TEXT.turnOff) }
  self.entries = entries
end

-- pages is a list of pages, each a list of lines; a page may carry `sfx`,
-- played the moment it comes up (FindOakRating hands PlaySFX its fanfare
-- right before the rating text prints).
function CenterPcMenu:say(pages, onDone)
  Typer.say(self, pages, onDone, { expand = function(line)
    return (line:gsub("{PLAYER}", self:playerName()))
  end })
  local first = pages[1]
  if first and first.sfx then self:playSfx(first.sfx) end
end

function CenterPcMenu:close()
  if self.closed then return end
  self.closed = true
  if self.onClose then self.onClose() end
end

-- .shutdown: PC_PlayShutdownSound, then the menu is gone.  The party refusal
-- never reaches this -- the PC never booted.
function CenterPcMenu:shutdown()
  self:playSfx("Sfx_ShutDownPc")
  self:close()
end

-- ProfOaksPC's `.shutdown`: _OakPCText4 either way, then back to the menu
-- loop (`jr nc, .loop` in PokemonCenterPC -- the OaksPC row answers nc).
function CenterPcMenu:oakClosed()
  self:say(translatedPages(TEXT.oakClosed))
end

-- ProfOaksPCBoot, inside a screen rather than a script: the counts, the
-- rating pick and the texts come from src/script/gen2/Specials.lua so the two
-- callers cannot drift apart.
function CenterPcMenu:oakRate()
  local seen, caught = Specials.dexCounts(self.save)
  local rating = Specials.findOakRating(caught)
  local pages = pagesOf(Strings(Specials.OAK_PC_TEXT.completion))
  for _, page in ipairs(pagesOf(
      Strings(Specials.OAK_PC_TEXT.counts, seen, caught))) do
    pages[#pages + 1] = page
  end
  local ratingPages = pagesOf(Strings(rating.text))
  if ratingPages[1] then ratingPages[1].sfx = rating.sfx end
  for _, page in ipairs(ratingPages) do pages[#pages + 1] = page end
  self:say(pages, function() self:oakClosed() end)
end

function CenterPcMenu:choose()
  local entry = self.entries[self.index]
  if not entry then return end
  local game = self.game
  if entry.id == "turnoff" then
    -- TurnOffPC: PokecenterPCOaksClosedText, then carry into .shutdown.
    self:say(translatedPages(TEXT.linkClosed),
      function() self:shutdown() end)
    return
  end
  -- PC_PlayChoosePCSound opens all four of the other rows.
  self:playSfx("Sfx_ChoosePcOption")
  if entry.id == "bills" then
    self:say(translatedPages(TEXT.billsOpened), function()
      if not (game and game.stack) then return end
      Screens.push(game, "Gen2PcMenu", {
        save = self.save,
        bills = true,
        onClose = function() game.stack:pop() end,
      })
    end)
  elseif entry.id == "players" then
    self:say(translatedPages(TEXT.ownOpened), function()
      if not (game and game.stack) then return end
      Screens.push(game, "Gen2ItemPcMenu", {
        save = self.save,
        items = self.items,
        onClose = function() game.stack:pop() end,
      })
    end)
  elseif entry.id == "oaks" then
    self:say(translatedPages(TEXT.oakOpened), function()
      -- _OakPCText1's yes/no; NO is the same `.shutdown` as a finished rating.
      self.confirm = {
        prompt = translatedPages(TEXT.rateDex)[1],
        choice = 1,
        onYes = function() self:oakRate() end,
        onNo = function() self:oakClosed() end,
      }
    end)
  elseif entry.id == "hof" then
    if not (game and game.stack) then return end
    -- HallOfFamePC: FadeToMenu, _HallOfFamePC, CloseSubmenu.
    Screens.push(game, "HallOfFame", {
      save = self.save,
      mode = "view",
      onDone = function() game.stack:pop() end,
    })
  end
end

function CenterPcMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end

  if self.message then
    Typer.step(self)
    if Typer.typing(self) then return end
    if input:wasPressed("a") or input:wasPressed("b") then
      local m = self.message
      if m.page < #m.pages then
        Typer.turn(self, m)
        local page = m.pages[m.page]
        if page and page.sfx then self:playSfx(page.sfx) end
        return
      end
      self.message = nil
      if m.onDone then m.onDone() end
    end
    return
  end

  if self.confirm then
    local c = self.confirm
    if input:wasPressed("up") or input:wasPressed("down") then
      c.choice = c.choice == 1 and 2 or 1
    elseif input:wasPressed("b") then
      -- home/menu.asm:345
      self:playSfx("Sfx_ReadText2")
      self.confirm = nil
      if c.onNo then c.onNo() end
    elseif input:wasPressed("a") then
      self:playSfx("Sfx_ReadText2")
      self.confirm = nil
      if c.choice == 1 then
        if c.onYes then c.onYes() end
      elseif c.onNo then
        c.onNo()
      end
    end
    return
  end

  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or #self.entries
  elseif input:wasPressed("down") then
    self.index = self.index < #self.entries and self.index + 1 or 1
  elseif input:wasPressed("a") then
    self:choose()
  elseif input:wasPressed("b") then
    -- DoNthMenu's carry lands straight in .shutdown, no text.
    self:shutdown()
  end
end

function CenterPcMenu:drawBottomLines(lines)
  Chrome.box(0, 12, 20, 6)
  if not lines then return end
  local name = self:playerName()
  -- constants/text_constants.asm:32 TEXTBOX_INNERY: rows 14 and 16 only.
  for i = 1, math.min(#lines, 2) do
    Chrome.print((lines[i]:gsub("{PLAYER}", name)), 1, 14 + (i - 1) * 2)
  end
end

function CenterPcMenu:drawPanel()
  if self.booted then
    -- _PokecenterPCWhoseText stays up under the menu
    -- (PC_DisplayTextWaitMenu leaves it there); the menu window is drawn on
    -- top of it, the way the cart's windows stack.
    self:drawBottomLines(translatedPages(TEXT.accessWhose)[1])
    -- .TopMenu is menu_coords 0, 0, 15, 12.
    Chrome.box(0, 0, 16, math.max(12, #self.entries * 2 + 2))
    for i, entry in ipairs(self.entries) do
      local ty = i * 2
      if i == self.index then Chrome.cursor(1, ty) end
      Chrome.print(entry.label, 2, ty)
    end
  end

  if self.message then
    -- ../pokecrystal/engine/events/pokecenter_pc.asm:652
    self:drawBottomLines(
      Typer.text(self, self.message.pages[self.message.page]))
  elseif self.confirm then
    self:drawBottomLines(self.confirm.prompt)
    Chrome.box(14, 7, 6, 5)
    Chrome.print(Strings("YES"), 16, 8)
    Chrome.print(Strings("NO"), 16, 10)
    Chrome.cursor(15, self.confirm.choice == 1 and 8 or 10)
  elseif not self.booted then
    self:drawBottomLines(nil)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

function CenterPcMenu:draw()
  self:drawPanel()
end

CenterPcMenu.ENGINE_POKEDEX = ENGINE_POKEDEX

return CenterPcMenu
