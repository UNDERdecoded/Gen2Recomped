-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Observe the admitted native preview; it owns its input, flags and clock.
local Native = require('src.compat.gen1.NativeSession')
local Preview = require('src.world.Gen3MapPreviewFRLG')
local M = {}
local function observed()
 local game = Native.game()
 local states = game and game.stack and game.stack.states
 for i = #(states or {}), 1, -1 do
  local state = states[i]
  if getmetatable(state) == Preview and state.game == game then return state end
 end
end
function M.isActive() return observed() ~= nil end
function M.isForestActive()
 local state = observed()
 local rec = state and Preview.record(state.game, state.section)
 return rec ~= nil and rec.type == 'forest'
end
function M.mapsec() local state = observed(); return state and state.section end
return M
