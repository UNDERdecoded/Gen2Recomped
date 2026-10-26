-- Native checkpoint transactions. Payloads contain progress and semantic state,
-- never controller objects, closures, options, or another service's storage.
local SaveData = require("src.core.SaveData")
local Serializer = require("src.core.SaveSerializer")
local Version = require("src.core.Version")
local Runtime = require("src.mods.Runtime")
local World = require("src.core.CheckpointWorld")
local Spinners = require("src.core.CheckpointSpinners")
local Actors = require("src.core.CheckpointActors")
local Battles = require("src.core.CheckpointBattle")
local C = {}
local MAX_NODES, MAX_DEPTH = 250000, 64

local function clone(value, seen, budget, depth)
	local kind = type(value)
	if kind == "nil" or kind == "string" or kind == "boolean" then
		return value
	end
	if kind == "number" then
		assert(value == value and value ~= math.huge and value ~= -math.huge, "nonfinite number")
		return value
	end
	assert(kind == "table" and getmetatable(value) == nil, "checkpoint requires plain data")
	seen, budget, depth = seen or {}, budget or { n = 0 }, depth or 0
	assert(not seen[value] and depth < MAX_DEPTH, "cyclic or deeply nested checkpoint")
	seen[value] = true
	local out = {}
	for k, v in pairs(value) do
		budget.n = budget.n + 1
		assert(budget.n <= MAX_NODES, "checkpoint exceeds node limit")
		assert(type(k) == "string" or type(k) == "number", "invalid checkpoint key")
		out[clone(k, seen, budget, depth + 1)] = clone(v, seen, budget, depth + 1)
	end
	seen[value] = nil
	return out
end
local function fail(code, message)
	return nil, code, message
end
local function refusal(kind, reason, message)
	return { kind = kind, canCapture = false, canRestore = false, reason = reason, message = message }
end
local function nonempty(t)
	return type(t) == "table" and next(t) ~= nil
end
local function top(game)
	local stack = game and game.stack
	if not stack then
		return nil
	end
	local state = stack.top and stack:top() or stack.states and stack.states[#stack.states]
	return state or stack.worldState
end
local function atTitle(game)
	local state = top(game)
	return state and state.screenId == "TitleState"
end
local function busy(world)
	if world.runner and world.runner.isRunning and world.runner:isRunning() then
		return true
	end
	return nonempty(world.parallelRunners)
		or nonempty(world.pendingScripts)
		or nonempty(world.parallelQueue)
		or nonempty(world.scriptMoves)
end
local ANIMATIONS = {
	"tileAnimOverride",
	"engaging",
	"emote",
	"teleportOut",
	"dustAnim",
	"cutAnim",
	"fishPose",
	"fishing",
	"flyAnim",
	"healAnim",
	"waterAnim",
	"ssAnne",
	"fadeOverlay",
	"g3MirageTower",
	"g3Orb",
  "hgssFollowTalk",
  "g2MomCallPending",
}
-- Native stationary spinners carry a qualified semantic continuation. Other
-- moving/scripted actors still require their own reconstruction backend.
local function canonicalActors(world)
	if world.follower or world.strengthActive or world.noWildEncounters then
		return false
	end
	local known = {}
	local function admit(actor)
		if known[actor] then
			return true
		end
		local def = actor and actor.def
		if not def or getmetatable(actor) ~= package.loaded["src.world.NPC"] then
			return false
		end
		if
			actor.moving
			or actor.frozen
			or actor.wanders
			or ((actor.spins or def.movement == "SPIN") and not Spinners.admit(actor, world))
			or actor.turns
			or actor.looksAround
			or actor.rotates
			or actor.sequence
		then
			return false
		end
		if
			actor.cellX ~= def.x
			or actor.cellY ~= def.y
			or (not actor.spins and actor.facing ~= actor.spawnFacing)
			or actor.px ~= actor.cellX * 16
			or actor.py ~= actor.cellY * 16
			or actor.fixedFrame ~= def.frame
			or actor.hidden
			or actor.shakeFrames or actor.shakeDone or actor.hopFrames
			or actor.targetX or actor.targetY or actor.marching
		then
			return false
		end
		known[actor] = true
		return true
	end
	for _, actor in pairs(world.npcPool or {}) do
		if not admit(actor) then
			return false
		end
	end
	for _, actor in ipairs(world.npcs or {}) do
		if not admit(actor) then
			return false
		end
	end
	for _, actor in ipairs(world.entities or {}) do
		if actor ~= world.player and not known[actor] then
			return false
		end
	end
	return true
end
function C.inspect(game, internal, fs)
	local save = game and game.save
	if type(save) ~= "table" or type(save.version) ~= "string" then
		return refusal("unknown", "not_in_playthrough", "Choose an existing playthrough.")
	end
	if World.busy(game) and not internal then
		return refusal("unknown", "restore_busy", "Checkpoint reconstruction is active.")
	end
	local world = game.overworld
	if type(world) ~= "table" or not world.map or not world.player then
		return refusal("unknown", "not_overworld", "No native overworld is active.")
	end
  local active=top(game)
  local battle=active and active.isBattleState and active
  if active~=world and not battle then
    return refusal("overworld", "screen_busy", "Close the active screen first.")
  end
  if battle and not pcall(Battles.capture,game,battle,clone) then
    return refusal("battle", "unsupported_battle", "This battle has no safe native decision continuation.")
  end
	if world.transitioning then
		return refusal("overworld", "transition_busy", "Wait for the map transition.")
	end
	if busy(world) and not battle then
		return refusal("overworld", "script_busy", "Wait for running or queued scripts.")
	end
	for _, name in ipairs(ANIMATIONS) do
		if world[name] and not (battle and name=="engaging") then
			return refusal("overworld", "animation_busy", "Wait for the active world animation.")
		end
	end
	if world.player.moving or world.player.spinning or world.player.jumping then
		return refusal("overworld", "movement_busy", "Wait for player movement.")
	end
	if game.linkSession or (game.linkNet and not game.linkNet.closed) then
		return refusal("overworld", "unsupported_runtime", "Multiplayer checkpoint reconstruction is unavailable.")
	end
  local mapDef = world.map.def or {}
  for _, name in ipairs({ "gen4DynamicPlate", "gen4Canalave", "gen4EternaClock",
    "gen4HearthomeWarps", "gen4PastoriaGates", "gen4SunyshoreAngles",
    "gen4VeilstoneHooked", "gen4GymFx", "gen4PropControl", "gen5IcirrusIce",
    "gen5RailLayers" }) do
    if mapDef[name] then
      return refusal("overworld", "unsupported_runtime", "This native dynamic-map controller is not a qualified checkpoint continuation.")
    end
  end
	if not pcall(Actors.capture, game, clone) then
		return refusal("overworld", "unsupported_actor_runtime", "This actor runtime contains an opaque or unsupported continuation.")
	end
	if not World.available(game) then
		return refusal("overworld", "unsupported_runtime", "This world has no qualified native reconstruction backend.")
	end
	if not (love and love.math and love.math.getRandomState and love.math.setRandomState) then
		return refusal("overworld", "rng_unavailable", "Gameplay RNG state cannot be captured and restored.")
	end
	if not SaveData.ensurePlaythroughId(save, fs) then
		return refusal("overworld", "not_in_playthrough", "No persistent playthrough identity is available.")
	end
	return { canCapture = true, canRestore = true, kind = battle and "battle" or "overworld" }
end
local function rng()
	if love and love.math and love.math.getRandomState then
		return { love = love.math.getRandomState() }
	end
end
local function restoreRng(state)
	if state then
		assert(love and love.math and love.math.setRandomState, "RNG restoration unavailable")
		love.math.setRandomState(state.love)
	end
end
local function progress(game)
	local source = {}
	for key, value in pairs(game.save) do
		if key ~= "options" then
			source[key] = value
		end
	end
	local out = clone(source)
	game.overworld:captureSave(out)
	return out
end
function C.capture(game, internal, fs)
	local capability = C.inspect(game, internal, fs)
	if not capability.canCapture then
		return fail(capability.reason, capability.message)
	end
	local ok, result = pcall(function()
		local save = progress(game)
		local p = save.player
		local cp = {
			format = 1,
			kind = capability.kind,
			identity = {
				engineVersion = Version.engine,
				gameVersion = save.version,
				playthroughId = save.meta.playthroughId,
			},
			save = save,
			runtime = {
				actors = Actors.capture(game, clone),
        battle = capability.kind=="battle" and Battles.capture(game,top(game),clone) or nil,
				overworld = {
					map = p.map,
					x = p.x,
					y = p.y,
					facing = p.facing,
					surfing = p.surfing and true or false,
				},
			},
			rng = rng(),
		}
		return clone(cp)
	end)
	if not ok then
		return fail("invalid_runtime", tostring(result))
	end
	return result
end
local function validContent(game, save)
	local data = game.data or {}
	local function mon(value)
		if type(value) ~= "table" or not (data.pokemon and data.pokemon[value.species]) then
			return false
		end
		for _, move in ipairs(value.moves or {}) do
			local id = type(move) == "table" and (move.id or move.move) or move
			if id and not (data.moves and data.moves[id]) then
				return false
			end
		end
		return true
	end
	local function party(list)
		for _, value in pairs(list or {}) do
			if not mon(value) then
				return false
			end
		end
		return true
	end
	if not party(save.party) or not party(save.box) then
		return false
	end
	for _, box in pairs(save.boxes or {}) do
		if not party(box) then
			return false
		end
	end
	for _, field in ipairs({ "inventory", "pcItems" }) do
		for id, count in pairs(save[field] or {}) do
			if not (data.items and data.items[id]) or type(count) ~= "number" or count < 0 or count % 1 ~= 0 then
				return false
			end
		end
	end
	return true
end
local FACING = { up = true, down = true, left = true, right = true }
local function validateData(game, value, fs, resuming)
	local ok, cp = pcall(clone, value)
	if not ok then
		return fail("invalid_checkpoint", tostring(cp))
	end
	if type(cp) ~= "table" or cp.format ~= 1 then
		return fail("unsupported_format", "Unsupported checkpoint format.")
	end
	if cp.kind ~= "overworld" and cp.kind ~= "battle" then
		return fail("unsupported_kind", "Unsupported checkpoint runtime.")
	end
	local id = cp.identity
	if type(id) ~= "table" or not game.save or id.gameVersion ~= game.save.version then
		return fail("wrong_game", "Checkpoint belongs to a different game.")
	end
	if id.engineVersion ~= Version.engine then
		return fail("wrong_engine", "Checkpoint engine revision differs.")
	end
	local selected = resuming and SaveData.selectedPlaythroughId(game.save, fs)
		or game.save.meta and game.save.meta.playthroughId
	if type(selected) ~= "string" or selected ~= id.playthroughId then
		return fail("wrong_playthrough", "Checkpoint belongs to a different playthrough.")
	end
	local save, p = cp.save, cp.runtime and cp.runtime.overworld
	if
		type(save) ~= "table"
		or type(p) ~= "table"
		or not save.meta
		or save.meta.playthroughId ~= selected
		or save.version ~= id.gameVersion
	then
		return fail("invalid_checkpoint", "Progress identity is inconsistent.")
	end
	if save.options ~= nil then
		return fail("invalid_checkpoint", "Global options do not belong in progress checkpoints.")
	end
	local map = game.data and game.data.maps and game.data.maps[p.map]
	if not map then
		return fail("invalid_map", "Checkpoint map is not installed.")
	end
	local tileset = require("src.world.MapLoader").tilesetFor(game.data, map)
	if not tileset then
		return fail("invalid_content", "Checkpoint map has no installed native tileset.")
	end
	local cells = tileset and tonumber(tileset.blockCells) or 2
	if
		type(p.x) ~= "number"
		or p.x % 1 ~= 0
		or type(p.y) ~= "number"
		or p.y % 1 ~= 0
		or p.x < 0
		or p.y < 0
		or p.x >= (map.width or 0) * cells
		or p.y >= (map.height or 0) * cells
		or not FACING[p.facing]
	then
		return fail("invalid_position", "Checkpoint position is outside the native map.")
	end
	local player = save.player
	if
		not player
		or player.map ~= p.map
		or player.x ~= p.x
		or player.y ~= p.y
		or player.facing ~= p.facing
		or (player.surfing and true or false) ~= p.surfing
	then
		return fail("invalid_position", "Runtime and progress positions disagree.")
	end
	if cp.kind=="battle" and not Battles.validate(game,cp.runtime.battle,save,cp.runtime.actors) then
    return fail("invalid_battle_state", "Battle relationships or continuation are invalid.")
  end
  if cp.kind=="overworld" and cp.runtime.battle~=nil then return fail("invalid_battle_state", "Unexpected battle continuation.") end
	if not validContent(game, save) then
		return fail("invalid_content", "Checkpoint references unavailable native content.")
	end
	if (cp.runtime.actors and not Actors.validate(game, cp.runtime.actors))
    or not Spinners.validate(game.data, cp.runtime.spinners)
    or (cp.runtime.actors and (cp.runtime.actors.player.cellX ~= p.x
      or cp.runtime.actors.player.cellY ~= p.y or cp.runtime.actors.player.facing ~= p.facing)) then
		return fail("invalid_actor_state", "Checkpoint spinner state is invalid or references unavailable native actors.")
	end
	if cp.rng ~= nil and (type(cp.rng) ~= "table" or type(cp.rng.love) ~= "string" or cp.rng.love == "") then
		return fail("invalid_rng", "Checkpoint RNG state is invalid.")
	end
	if cp.rng and love and love.math and love.math.newRandomGenerator then
		local accepted = pcall(function()
			love.math.newRandomGenerator():setState(cp.rng.love)
		end)
		if not accepted then
			return fail("invalid_rng", "Checkpoint RNG state cannot be decoded.")
		end
	end
	return cp
end
local function validate(...)
	local ok, cp, code, message = pcall(validateData, ...)
	if not ok then
		return fail("invalid_checkpoint", tostring(cp))
	end
	return cp, code, message
end
local function equal(a, b)
	return Serializer.encode(a) == Serializer.encode(b)
end
local function rebuild(game, cp)
	local options = game.save.options
	local loaded = clone(cp.save)
	loaded.options = options
	return World.begin(game, loaded, cp.runtime, clone)
end
local function verify(game, cp, priorRng)
	restoreRng(cp.rng or priorRng)
	local verified, code, message = C.capture(game, true)
	assert(verified, message or code)
	if cp.rng == nil then
		verified.rng = nil
	end
  if cp.runtime.actors == nil then
    assert(canonicalActors(game.overworld), "legacy checkpoint cannot represent this actor runtime")
    verified.runtime.actors = nil
    verified.runtime.spinners = Spinners.capture(game.overworld)
  end
	assert(equal(verified, cp), "native checkpoint recapture differs")
end

local function commit(game, token, cp, priorRng)
	World.commit(game, token)
	-- Entry scripts stay suppressed. Once committed, select the native map's
	-- music so title/cross-map reconstruction does not keep the old theme.
	local ok, message = pcall(function()
    local Music=require("src.core.Music")
    if cp.kind=="battle" then
      local battle=top(game)
      Music.playBattle(game.data,battle.musicKind or battle.kind)
    else
      Music.playMap(game.data,game.overworld.map.id,game.save.onBike,game.overworld.player.surfing)
    end
	end)
	restoreRng(cp.rng or priorRng)
	if not ok then
		require("src.core.Logger").warn("checkpoint music: %s", tostring(message))
	end
	Runtime.emit("checkpoint.restored", { game = game, kind = cp.kind })
end

function C.restore(game, value, fs)
	local capability = C.inspect(game, nil, fs)
	if not capability.canRestore then
		return false, capability.reason, capability.message
	end
	local cp, code, message = validate(game, value, fs)
	if not cp then
		return false, code, message
	end
	local backup, why, detail = C.capture(game)
	if not backup then
		return false, why, detail
	end
	local token
	local priorRng = rng()
	local ok, err = pcall(function()
		token = rebuild(game, cp)
		verify(game, cp, priorRng)
	end)
	if not ok then
		local rolled, rollback = pcall(function()
			if token then
				World.rollback(game, token)
			end
			restoreRng(priorRng)
			local recaptured = assert(C.capture(game))
			assert(equal(recaptured, backup), "rollback verification differs")
		end)
		if not rolled then
			return false, "rollback_failed", tostring(err) .. "; " .. tostring(rollback)
		end
		return false, "restore_failed", tostring(err)
	end
	commit(game, token, cp, priorRng)
	return true
end
function C.resume(game, value, fs)
	if not atTitle(game) then
		return false, "not_at_title", "Resume requires the native title screen."
	end
	if not World.available(game) then
		return false, "unsupported_runtime", "No qualified native reconstruction backend is installed."
	end
	local cp, code, message = validate(game, value, fs, true)
	if not cp then
		return false, code, message
	end
	local token
	local priorRng = rng()
	local ok, err = pcall(function()
		token = rebuild(game, cp)
		verify(game, cp, priorRng)
	end)
	if not ok then
		if token then
			World.rollback(game, token)
		end
		restoreRng(priorRng)
		return false, "resume_failed", tostring(err)
	end
	commit(game, token, cp, priorRng)
	return true
end
function C.ensureNormalSave(game, value, fs)
	local cp, code, message = validate(game, value, fs)
	if not cp then
		return false, code, message
	end
	local current, why, detail = C.capture(game)
	if not current then
		return false, why, detail
	end
	if not equal(current, cp) then
		return false, "runtime_changed", "Checkpoint is not the exact current runtime."
	end
	local normal, why, detail = SaveData.selectedNormalSaveInfo(game.save, fs)
	if not normal then
		return false, why, detail
	end
	if normal.exists then
		return true, "already_exists"
	end
	-- Only the real game's normal save boundary may write progress. An injected
	-- filesystem used for observation must never silently redirect that write.
	if fs and love and fs ~= love.filesystem then
		return false, "storage_unavailable", "Normal-save anchoring requires the live persistence backend."
	end
	local exists = SaveData.saveFileExists(game.save.version)
	if exists == nil then
		return false, "storage_unavailable", "The normal-save destination is unavailable."
	end
	if exists then
		return false, "wrong_playthrough", "The normal-save destination belongs to another playthrough."
	end
	local ran, saved = pcall(function()
		return game:writeSave()
	end)
	if not ran or saved ~= true then
		return false, "save_failed", "Normal progress could not be anchored."
	end
	return true, "saved"
end
function C.new(fs)
	return {
		inspect = function(_, game)
			return C.inspect(game, nil, fs)
		end,
		capture = function(_, game)
			return C.capture(game, nil, fs)
		end,
		restore = function(_, game, cp)
			return C.restore(game, cp, fs)
		end,
		resume = function(_, game, cp)
			return C.resume(game, cp, fs)
		end,
		ensureNormalSave = function(_, game, cp)
			return C.ensureNormalSave(game, cp, fs)
		end,
	}
end
return C
