-- Gen2's public screen/model boundary over the shared native battle engine.
-- The screen owns execution, wrappers and presentation clocks; readers of
-- screen.battle get the actual party Pokemon, including after a queued switch.
local View = {}
local Hp = require('src.battle.Gen2HpPresentation')

local function partyOf(screen)
  return screen.playerParty or screen.game.save.party or {}
end

local function battler(screen, side)
  if side == "player" or side == "enemy" then return screen[side] end
end

local function indexOf(party, mon)
  for index, candidate in ipairs(party or {}) do
    if candidate == mon then return index end
  end
end

function View.bind(screen)
  -- Bind once; callers read the current native catalog without copying a
  -- move, caching a definition, or switching the controller's moveset.
  local function moveDef(_, move)
    if type(move) == "string" then return screen.data.moves[move] end
    if move == nil then return nil end
    return screen:moveDef(move)
  end
  local readers = {
    moveDef = function() return moveDef end,
    player = function() return screen.player and screen.player.mon end,
    enemy = function() return screen.enemy and screen.enemy.mon end,
    party = function() return partyOf(screen) end,
    enemyParty = function() return screen.enemyParty end,
    save = function() return screen.game.save end,
    data = function() return screen.data end,
    wild = function() return screen.kind == "wild" end,
    playerIndex = function() return indexOf(partyOf(screen), screen.player and screen.player.mon) end,
    enemyIndex = function() return indexOf(screen.enemyParty, screen.enemy and screen.enemy.mon) end,
    over = function() return screen.result ~= nil or screen.dead == true end,
    outcome = function() return screen.result end,
    battleType = function() return screen.battleType end,
    trainer = function() return screen.trainer end,
    tutorial = function() return screen.demo or screen.dudeDemo or screen.pokedudeDemo end,
    contest = function() return screen.contest end,
    safari = function() return screen.safari and true or false end,
    link = function() return screen.kind == "link" end,
  }
  screen.battle = setmetatable({}, {
    __index = function(_, key) local read = readers[key]; if read then return read() end end,
    __newindex = function(model, key, value)
      if readers[key] then error("native Gen2 battle view is read-only", 2) end
      -- Native combat fields stay owned by the engine. Presentation consumers
      -- may attach and release their own transient owners, as on the native
      -- Gen2 model; these extensions never write to a battler or save.
      rawset(model, key, value)
    end,
  })
  Hp.bind(screen)
end

function View.activeMon(screen, side)
  local b = battler(screen, side)
  return b and b.mon
end

local function owner(screen, mon)
  for _, side in ipairs({ "player", "enemy" }) do
    local b = battler(screen, side)
    if b and b.mon == mon then return b, side end
  end
end

-- These are drawing operations, not another battle controller. In particular
-- front-art captures of the player keep the REAL battler as the key for blink,
-- substitute, faint and grow-in effects, and never replace its native rear.
function View.install(Screen, images)
  Screen.activeMon = View.activeMon

  -- Older/restored native Pokemon need not carry a stamped gender field.
  -- Read the existing identity authority rather than changing the live mon
  -- merely to paint a HUD. It also owns explicit overrides and PID editions.
  function Screen:genderSymbol(mon)
    local gender = require("src.pokemon.Pokemon").genderOf(self.data, mon)
    if gender == "male" then return "\226\153\130" end
    if gender == "female" then return "\226\153\128" end
  end

  function Screen:pic(mon, back)
    if not mon then return nil end
    local b = owner(self, mon)
    if b and b.isPlayer == back then
      return self:picImage(b.sprite), images.trueColor(b.sprite), images.path(b.sprite)
    end
    local species = b and b.species or mon.species
    if b and species ~= mon.species then
      local image = self:speciesSprite(species, back)
      return self:picImage(image), images.trueColor(image), images.path(image)
    end
    local path, trueColor = require("src.pokemon.Sprites").path(self.data, species,
      back and "back" or "front", { mon = mon, kind = "battle" })
    local image = images.load(path, images.palette(self.data, species,
      require("src.pokemon.Pokemon").isShiny(mon)), trueColor)
    return self:picImage(image), trueColor, path
  end

  function Screen:picScale(path, mon, back)
    return Screen.resolveBattleScale(self.data, back and "back" or "front",
      path, mon and mon.species)
  end

  function Screen:frontAnimFrame(mon)
    local b = owner(self, mon)
    -- The shared engine owns the entrance runner. Reading a capture does not
    -- advance its clock, restart it, or animate a player's unrelated rear.
    if not (b and not b.isPlayer and b.picAnim and b.picAnim:frame() > 0) then return nil end
    local image = self:battlerPic(b)
    if not image then return nil end
    return image, nil, image:getWidth()
  end

  function Screen:animPicState(side)
    local b = battler(self, side)
    if not b then return nil end
    local pf = self.picFx and self.picFx[b]
    return {
      hidden = (side == "enemy" and (self.enemyHidden or self.enemySendingOut))
        or (side == "player" and self.sendingOut) or self:fxHidden(b)
        or (b.fainted and not self:fxFaintActive(b)) or (pf and pf.hidden) or false,
      pic = b.substituteHP and "substitute" or nil,
      slide = pf and pf.ox or 0,
    }
  end

  function Screen:drawPic(mon, back)
    local b, side = owner(self, mon)
    if not b then return end
    local state = self:animPicState(side)
    if state and state.hidden then return end
    if (back and self.slidingBackpic) or (self.picHidden and self.picHidden[side]) then return end
    local trainer = back and self.showPlayerBack and self.playerBackPic
      or (not back and self.showEnemyTrainer and self.trainerPic)
    local image, _, path = self:pic(mon, back)
    if trainer then image, path = self:picImage(trainer), images.path(trainer) end
    if not image then return end
    local frame = not trainer and not back and self:frontAnimFrame(mon)
    if frame then image = frame end
    local scale = self:picScale(path, not trainer and mon or nil, back)
    local grow = not trainer and self:growInScale(b)
    if grow then scale = scale * grow end
    if scale <= 0 then return end
    local w, h = image:getDimensions()
    local x = (back and 16 or 96) + math.max(0, math.floor(((back and 48 or 56) - w) / 2))
    local y = (back and 96 or 56) - h
    x, y = x + math.floor(w * (1 - scale) / 2), y + math.floor(h * (1 - scale))
    if trainer then love.graphics.draw(image, x, y, 0, scale, scale); return end
    local screen = self
    local capture = setmetatable({
      -- This isolated window owns the clip below. The native effect drawer's
      -- rear-side window would erase a front capture of the SAME player.
      wideRegion = true,
      battlerPic = function() return image end,
      -- Sprite extraction must stay a sprite even with native Stadium enabled.
      drawStadiumBattlerPic = function() return false end,
      drawSubstituteDoll = function(_, actual)
        local g = love.graphics
        local dx = (back and 32 or 112) - (actual.isPlayer and 32 or 112)
        local dy = (back and 72 or 32) - (actual.isPlayer and 72 or 32)
        g.push(); g.translate(dx, dy)
        local ok, err = pcall(screen.drawSubstituteDoll, screen, actual)
        g.pop(); if not ok then error(err, 0) end
      end,
    }, { __index = self })
    local g = love.graphics
    g.push("all")
    if g.intersectScissor then
      g.intersectScissor(back and 16 or 96, back and 48 or 0,
        back and 48 or 56, back and 48 or 56)
    end
    local ok, err = pcall(capture.drawBattlerPic, capture, b, x, y, scale)
    g.pop()
    if not ok then error(err, 0) end
  end
end

return View
