-- Native Gen2 party-result presentation over the real shared party screen.
-- Contract/HP stepping adapted from Gen1Recomp 535a5ec0
-- src/ui/gen2/PartyMenu.lua and src/battle/gen2/HpBar.lua.
-- Existing project rights/licences remain applicable. Contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
local Chrome = require('src.ui.Gen2Chrome')
local M = {}
local function maximum(mon)
  return mon and (mon.maxHp or mon.stats and mon.stats.hp) or 0
end
function M.install(Screen)
  Screen.ACTION_TEXT_DELAY = 50
  function Screen:playSfx(name)
    local data = self.game and self.game.data
    -- The importer already owns native cue aliases. Do not invent a second
    -- resolver (the shared Sound service has no Sound.resolve method).
    if data and data.audio and data.audio.sfx and data.audio.sfx[name] then
      return require('src.core.Sound').play(data, name)
    end
  end
  function Screen:showItemResult(slot, opts)
    opts = opts or {}
    local mon = slot and self.party[slot]
    local result = {slot=slot,mon=mon,from=opts.fromHp,shown=opts.fromHp,
      target=opts.toHp,text=opts.text,delay=opts.delay or Screen.ACTION_TEXT_DELAY,
      onDone=opts.onDone,auto=opts.auto,holdSlot=opts.holdSlot,holdHp=opts.holdHp,
      lines=Chrome.wrap(opts.text,18),line=1}
    self.itemResult = result
    -- The shared party screen's existing display hold and the Gen2 result
    -- are this same owner. Neither path may advance a second HP clock.
    self.heal = result
    if opts.sfx then self:playSfx(opts.sfx) end
  end
  function Screen:itemResultClimbing()
    local r = self.itemResult
    return r ~= nil and r.shown ~= nil and r.target ~= nil and r.shown ~= r.target
  end
  function Screen:shownHpFor(slot, mon)
    local r = self.itemResult
    if r then
      if r.slot == slot and r.shown ~= nil then return r.shown end
      if r.holdSlot == slot and r.holdHp ~= nil then return r.holdHp end
    end
    return mon and mon.hp
  end
  function Screen:updateItemResult(input)
    local r = self.itemResult
    if not r then return end
    if self:itemResultClimbing() then
      local maxHp = maximum(self.party[r.slot])
      local step = maxHp >= 48 and math.max(1, math.ceil(maxHp / 48)) or 1
      if r.shown < r.target then r.shown = math.min(r.target, r.shown + step)
      else r.shown = math.max(r.target, r.shown - step) end
      return
    end
    if not r.auto then
      if r.delay > 0 then r.delay = r.delay - 1; return end
      if not (input:wasPressed('a') or input:wasPressed('b')) then return end
      -- Shared effects can produce more than the cartridge panel's two
      -- rows. Keep their complete native text instead of dropping a tail.
      if r.line + 1 < #r.lines then
        r.line = r.line + 2
        r.delay = Screen.ACTION_TEXT_DELAY
        return
      end
    end
    self.itemResult = nil
    if self.heal == r then self.heal = nil end
    if r.onDone then r.onDone() end
  end
  function Screen:wantsNativeOverlay()
    return self.itemResult ~= nil and self.itemResult.text ~= nil
      and not self:itemResultClimbing()
  end
  function Screen:drawNativeOverlay(width, height)
    if not self:wantsNativeOverlay() then return end
    local function draw()
      Chrome.textbox(0, 12, 18, 4)
      local r = self.itemResult
      for row=0,1 do
        local text = r.lines[r.line+row]
        if text then Chrome.print(text, 1, 14+row*2) end
      end
    end
    if width and height then
      love.graphics.origin()
      return Chrome.withOverlayPanel(width, height, draw)
    end
    local w, h = 160, 144
    if self.uiSize then w, h = self:uiSize() end
    if w ~= 160 or h ~= 144 then return Chrome.withOverlayPanel(w, h, draw) end
    return draw()
  end
end
return M
