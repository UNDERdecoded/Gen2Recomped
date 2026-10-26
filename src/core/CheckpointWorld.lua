-- Private native reconstruction transaction. Rollback retains original object
-- graphs and GPU ownership; none of these tokens are serializable/public data.
local Maps = require("src.world.MapLoader")
local Palette = require("src.render.PaletteFX")
local V = require("src.core.GameVersion")
local Spinners = require("src.core.CheckpointSpinners")
local Actors = require("src.core.CheckpointActors")
local W = {}
local active = setmetatable({}, { __mode = "k" })
local function fields(object)
	local out = {}
	for k, v in pairs(object) do
		out[k] = v
	end
	return out
end
local function replace(object, values)
	for k in pairs(object) do
		object[k] = nil
	end
	for k, v in pairs(values) do
		object[k] = v
	end
end
function W.available(game)
	local info = game and game.save and V.info(game.save.version)
	local world = game and (game.overworld or package.loaded["src.world.OverworldController"])
	return game == package.loaded["src.core.Game"]
		and info
		and info.generation <= 5
		and game.save.version == V.get()
		and world
		and type(world._checkpointRebuild) == "function"
end
function W.begin(game, loaded, runtime, clone)
  local position,spinners,actors=runtime.overworld,runtime.spinners,runtime.actors
	assert(W.available(game), "native checkpoint world backend is unavailable")
	assert(not active[game], "checkpoint reconstruction already active")
	local world, stack = game.overworld or require("src.world.OverworldController"), assert(game.stack)
	local token = {
		save = game.save,
		session = game.session,
		worldAlias = game.world,
		overworld = game.overworld,
		controller = world,
		ownerWorld = stack.worldOwner and stack.worldOwner.world,
		world = fields(world),
    movement = require("src.world.Gen4MovementTypes")._checkpointState(),
		stack = fields(stack),
		modSave = game.mods and game.mods.modSave,
		dark = Palette.darkWorld(),
		palette = Palette.gen2MapPalette(),
		tod = Palette.gen2Tod(),
		boundsW = game.renderer and game.renderer.worldBoundsW,
		boundsH = game.renderer and game.renderer.worldBoundsH,
	}
	token.maps = Maps._checkpointBegin()
	active[game] = token
	local ok, why = pcall(function()
		-- Native enter resets its own transient fields. Unknown mod fields retain
		-- their identity; their owners can refresh them after checkpoint.restored.
		game.save = loaded
		if game.session == token.save then
			game.session = loaded
		end
		if game.mods then
			game.mods.modSave = loaded.modData or {}
		end

    -- Enter may derive fresh resources using progress, but must not commit its
    -- ordinary map-entry resets, journal/fly unlocks, weather or bag changes.
    local canonical={}
    for key,value in pairs(loaded) do if key~='options' then canonical[key]=value end end
    canonical=clone(canonical)
    local options=loaded.options
    Actors.detach(world)
    world:_checkpointRebuild(position)
    replace(loaded,canonical);loaded.options=options
    if game.mods then game.mods.modSave=loaded.modData or {} end
    if actors then Actors.apply(game, actors, clone) else Spinners.apply(world, spinners) end
		game.world = world
		if stack.worldOwner then
			stack.worldState = world
			stack.worldOwner.world = world
			stack.states = {}
		else
			stack.states = { world }
		end
		stack._modalTracker, stack._sceneStack = nil, nil
    if runtime.battle then
      stack.states[#stack.states+1]=require("src.core.CheckpointBattle").apply(game,runtime.battle,clone)
    end
	end)
	if not ok then
		W.rollback(game, token)
		error(why, 0)
	end
	return token
end
function W.rollback(game, token)
	assert(active[game] == token, "invalid native checkpoint transaction")
	replace(token.controller, token.world)
	replace(game.stack, token.stack)
	game.overworld = token.overworld
	game.save, game.session, game.world = token.save, token.session, token.worldAlias
	if game.stack.worldOwner then
		game.stack.worldOwner.world = token.ownerWorld
	end
	if game.mods then
		game.mods.modSave = token.modSave
	end
	if game.renderer then
		game.renderer.worldBoundsW, game.renderer.worldBoundsH = token.boundsW, token.boundsH
	end
	Palette.setDarkWorld(token.dark)
	Palette.setGen2MapPalette(token.palette)
	Palette.setGen2Tod(token.tod)
	require("src.world.Gen4MovementTypes")._checkpointRollback(token.movement)
	Maps._checkpointRollback(token.maps)
	active[game] = nil
end
function W.commit(game, token)
	assert(active[game] == token, "invalid native checkpoint transaction")
	Maps._checkpointCommit(token.maps)
	active[game] = nil
end
function W.busy(game)
	return active[game] ~= nil
end
return W
