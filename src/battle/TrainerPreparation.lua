-- A synchronous hook can retain this one-shot native admission continuation.
local Runtime = require("src.mods.Runtime")
local M = { CANCEL_SCRIPT = {} }
local pending = setmetatable({}, { __mode = "k" })
local unpack = table.unpack or unpack
local function pack(...)
  return { n = select("#", ...), ... }
end
local function defaultGate()
  return false
end
function M.active(game)
  return pending[game] ~= nil
end
function M.prepare(game, context, startBattle, cancelBattle, valid, retireBattle)
  if not Runtime.wantsHook("trainer.before_battle") then
    startBattle()
    return false
  end
  if pending[game] then
    return true
  end
  local hooks, events = Runtime.hooks, Runtime.events
  local save, data, stack, session = game.save, game.data, game.stack, game.sessionStartedAt
  local world, overworld = game.world, game.overworld
  local party = save and save.party
  local members = {}
  for i, mon in ipairs(party or {}) do
    members[i] = mon
  end
  local entries = {}
  for _, entry in ipairs(hooks.chains["trainer.before_battle"] or {}) do
    entries[#entries + 1] = entry
  end
  local token, finished, unsubscribe = {}, false
  pending[game] = token
  local function current()
    if
      game.save ~= save
      or game.data ~= data
      or game.stack ~= stack
      or game.sessionStartedAt ~= session
      or game.world ~= world
      or game.overworld ~= overworld
      or (save and save.party ~= party)
    then
      return false
    end
    if #(party or {}) ~= #members then
      return false
    end
    for i, mon in ipairs(members) do
      if party[i] ~= mon then
        return false
      end
    end
    return not valid or valid()
  end
  local function live()
    if Runtime.hooks ~= hooks or Runtime.events ~= events then
      return false
    end
    for _, original in ipairs(entries) do
      local found = false
      for _, entry in ipairs(hooks.chains["trainer.before_battle"] or {}) do
        if entry == original then
          found = true
          break
        end
      end
      if not found then
        return false
      end
    end
    return true
  end
  local function discard()
    finished = true
    if pending[game] == token then
      pending[game] = nil
    end
    if unsubscribe then
      unsubscribe()
      unsubscribe = nil
    end
  end
  local function continueBattle(options)
    if finished or pending[game] ~= token then
      return false
    end
    local eligible = current()
    if not eligible or not live() then
      discard()
      if eligible and cancelBattle then
        cancelBattle()
      elseif retireBattle then
        retireBattle()
      end
      return false
    end
    discard()
    if type(options) == "table" and options.cancel == true then
      if cancelBattle then
        cancelBattle()
      end
    else
      startBattle(options)
    end
    return true
  end
  unsubscribe = hooks:wrap("core.update", function(next, ...)
    local results = pack(next(...))
    if not finished and (not current() or not live()) then
      continueBattle({ cancel = true })
    end
    return unpack(results, 1, results.n)
  end, -1000, "base")
  local deferred = Runtime.call("trainer.before_battle", defaultGate, game, context, continueBattle)
  if deferred ~= true and not finished then
    continueBattle()
  end
  return deferred == true
end
return M
