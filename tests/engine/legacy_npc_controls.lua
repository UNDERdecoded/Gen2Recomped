local T = require("tests.harness")
love = require("tests.love_stub")
local Contract = require("tests.api3_contract.npcs")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local function fixture(version)
	local f = Contract.fixture("tests/fixtures/legacy_npc_controls", "gen2", version, "legacy")
	-- API 2 materializes its legacy world lazily; the fixture already owns a
	-- constructed game by the time the exported lookup is called.
	f.loader._game = function()
		return f.live
	end
	f.legacy = f.loader
	f.handle = assert(f.loader.exports.legacy.npc(f.home, "IMPORTED"))
	return f
end
for _, version in ipairs({ "red", "gold", "firered" }) do
	local f = fixture(version)
	local h, actor = f.handle, f.imported
	T.eq(h.ow, f.ow, "legacy world field remains the native world")
	T.eq(h.npc, actor, "legacy actor field retains its original identity")
	T.eq(h.id, actor.id, "legacy public identity is preserved")
	T.eq(h:isMoving(), false, "new motion query reads native state")
	T.eq(h:placeAt(1, 1, "right"), true, "immediate placement is available to API 2")
	T.eq(actor.px, 16, "placement synchronizes native pixel coordinates")
	T.eq(actor.py, 16, "placement synchronizes native pixel coordinates")
	T.eq(h:canStep("right"), true, "query uses actual native map collision")
	local queue = #f.ow.scriptMoves
	T.eq(h:stepNow("right"), true, "immediate stepping starts native motion")
	T.eq(#f.ow.scriptMoves, queue, "immediate step creates no script queue entry")
	T.eq(actor.targetX, 2, "native target follows the requested direction")
	T.eq(h:isMoving(), true, "motion query sees the started step")
	T.eq(h:stepNow("down"), nil, "an active step cannot be overwritten")
	for _ = 1, 16 do
		actor:update(f.ow.map, f.ow.entities)
	end
	T.eq(actor.cellX, 2, "actual NPC updates complete the step")
	T.eq(h:isMoving(), false, "actual NPC updates clear native motion")
	T.eq(h:stepNow("right"), true, "another native step starts")
	T.eq(h:placeAt(3, 4, "up"), true, "placement cancels an in-flight step")
	T.eq(actor.targetX, nil, "placement clears the old native target")
	T.eq(actor.progress, 0, "placement clears the old step phase")
	T.eq(actor.moving, false, "placement clears the old movement flag")
	T.eq(actor.facing, "up", "placement applies optional facing")
	local peer =
		f:make(f.home, { index = 2, name = "PEER", sprite = "PROBE", x = 4, y = 4, movement = "STAY", range = "DOWN" })
	f.ow.npcs[#f.ow.npcs + 1] = peer
	f.ow.entities[#f.ow.entities + 1] = peer
	T.eq(h:canStep("right"), false, "collision query sees a native peer")
	local other = assert(f.legacy.exports.legacy.npc(f.home, "PEER"))
	T.eq(other:setPassable(true), true, "API-2 passability control reaches the native actor")
	T.eq(h:canStep("right"), true, "native collision honors the changed peer passability")
	T.eq(other:setPassable(false), true, "passability can be restored")
	T.eq(h:canStep("right"), false, "restored passability restores native blocking")
	local def = actor.def
	T.eq(h:setAppearance("ALT"), true, "appearance resolves through the native sprite path")
	T.eq(actor.appearance, "ALT", "native appearance identity updates")
	T.eq(actor.def.sprite, "ALT", "native actor definition uses the chosen sprite")
	T.eq(def.sprite, "PROBE", "imported shared template is retained")
	local changed = actor.def
	T.eq(h:setAppearance("MISSING"), nil, "missing appearance is declined")
	T.eq(actor.def, changed, "a declined appearance cannot half-change the actor")
	T.eq(h:stepNow("north"), nil, "bad directions are declined")
	T.eq(h:placeAt(0 / 0, 2), nil, "non-finite coordinates are declined")
	T.eq(actor.cellX, 3, "invalid input leaves the native cell unchanged")
	local x, y = h:position()
	T.eq(x, 3, "existing position method remains available")
	T.eq(y, 4, "existing position method retains its returns")
	T.eq(h:face("left"), true, "existing facing method remains available")
	T.eq(actor.facing, "left", "existing facing method retains its native effect")
	Runtime.currentMod = "legacy"
	T.eq(h:isMoving(), false, "new control is callable under mod attribution")
	T.eq(Runtime.currentMod, "legacy", "new control restores caller attribution")
	Runtime.currentMod = nil
	f.game.save = {}
	T.eq(h:placeAt(0, 0), nil, "retained new controls decline a replacement save")
	T.eq(actor.cellX, 3, "stale control cannot change the previous native actor")
	f.restoreRenderer()
end
for _, change in ipairs({ "rollback", "disabled", "map", "map_id", "fast_world", "removed", "version", "bus" }) do
	local f = fixture("gold")
	local h = f.handle
	if change == "rollback" then
		f.legacy:_rollback("legacy")
	elseif change == "disabled" then
		f.legacy.mods.legacy.enabled = false
	elseif change == "map" then
		f.ow.map = { id = "CHANGED" }
	elseif change == "map_id" then
		f.ow.map.id = "CHANGED"
	elseif change == "fast_world" then
		f.game.overworld = {}
	elseif change == "removed" then
		f.ow.npcs = {}
	elseif change == "version" then
		Version.set("silver")
	else
		Runtime.install(require("src.mods.Events").new(), require("src.mods.Hooks").new(), {})
	end
	T.eq(h:setPassable(true), nil, change .. " retires new controls")
	T.eq(f.imported.passable, nil, change .. " does not change the old native actor")
	f.restoreRenderer()
end

do
	local f = fixture("gold")
	local Renderer = require("src.render.SpriteRenderer")
	local old = Renderer.new
	local def, sprite = f.imported.def, f.imported.sprite
	Renderer.new = function()
		error("owned sprite failure")
	end
	Runtime.currentMod = "legacy"
	local ok, why = f.handle:setAppearance("ALT")
	T.eq(ok, nil, "native sprite failures are contained")
	T.check(why:find("owned sprite failure", 1, true) ~= nil, "native sprite failure remains diagnosable")
	T.eq(Runtime.currentMod, "legacy", "failed native control restores caller attribution")
	T.eq(f.imported.def, def, "failed native sprite resolution retains the old definition")
	T.eq(f.imported.sprite, sprite, "failed native sprite resolution retains the old renderer")
	Runtime.currentMod = nil
	Renderer.new = old
	f.restoreRenderer()
end

do
	local f = fixture("gold")
	f.ow.map = nil
	local h = assert(f.legacy.exports.legacy.npc(f.home, "IMPORTED"))
	local value, why = h:isMoving()
	T.eq(value, nil, "legacy lookup without a map cannot grant new controls")
	T.eq(why, "NPC handle is stale", "missing-map control has a stable refusal")
	f.restoreRenderer()
end
T.finish()
