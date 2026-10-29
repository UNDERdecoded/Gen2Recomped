-- Copyright (c) 2026 Roxas2712. See the offered contribution licence.
-- Separate live Gen2 model over the existing shared native controller.
local View = {}
local Model = require('src.battle.gen2.Battle')
local function partyOf(screen)
  return screen.playerParty or screen.game.save.party or {}
end

local function indexOf(party, mon)
  for index, candidate in ipairs(party or {}) do
    if candidate == mon then return index end
  end
end

function View.bind(screen)
  -- Bind once; callers read the current native catalog without copying a
  -- move, caching a definition, or switching the controller's moveset.
  local readers = {
    player = function() return screen.player and screen.player.mon end,
    enemy = function() return screen.enemy and screen.enemy.mon end,
    party = function() return partyOf(screen) end,
    enemyParty = function() return screen.enemyParty end,
    save = function() return screen.game.save end,
    data = function() return screen.data end,
    rng = function() return rawget(screen.battle, '_nativeLoveRng') end,
    random = function() return rawget(screen.battle, '_nativeRandom') end,
    wild = function() return screen.kind == "wild" end,
    playerIndex = function() return indexOf(partyOf(screen), screen.player and screen.player.mon) end,
    enemyIndex = function() return indexOf(screen.enemyParty, screen.enemy and screen.enemy.mon) end,
    over = function() return screen.result ~= nil or screen.dead == true or screen._gen2Complete == true end,
    outcome = function() return screen.result end,
    -- The controller increments once per actual round, before turn-start
    -- observers, including link participants and spectators. A source query
    -- must not start a round or initialize checkpoint/persistent state.
    turn = function() return screen.turnCount or 0 end,
    battleType = function() return screen.battleType end,
    trainer = function() return screen.trainer end,
    tutorial = function() return screen.demo or screen.dudeDemo or screen.pokedudeDemo end,
    contest = function() return screen.contest end,
    safari = function() return screen.safari and true or false end,
    link = function() return screen.kind == "link" end,
    kind = function() return screen.kind end,
    inBattleTowerBattle = function() return screen.battleTower == true end,
  }
  screen.battle = Model.bind(setmetatable({}, {
    __index = function(_, key)
      local read = readers[key]
      if read then return read() end
      return Model[key]
    end,
    __newindex = function(model, key, value)
      if readers[key] or Model[key] ~= nil then error("native Gen2 battle view is read-only", 2) end
      -- Native combat fields stay owned by the engine. Presentation consumers
      -- may attach and release their own transient owners, as on the native
      -- Gen2 model; these extensions never write to a battler or save.
      rawset(model, key, value)
    end,
  }), screen)
end

function View.install(Screen)
  function Screen:completeBattle()
    assert(require('src.core.GameVersion').isGen2(), 'Gen2 completion requires a Gen2 battle')
    return self:finish()
  end
end
return View
