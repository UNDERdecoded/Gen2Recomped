local T = require("tests.harness")
love = require("tests.love_stub")
local Version = require("src.core.GameVersion")
local Hooks = require("src.mods.Hooks")
local Events = require("src.mods.Events")
local Runtime = require("src.mods.Runtime")
local Runner = require("src.script.ScriptRunner")
local Decoded = require("src.script.DecodedScript")
local C2 = require("src.script.Gen2ScriptVM")
local C3 = require("src.script.Gen3ScriptVM")
local function fixture(gen, scripts)
	Version.set(gen == 2 and "gold" or "firered")
	local data = require("tests.fixtures.upstream_mods.data").fresh()
	data.map_scripts = { source = gen == 3 and "RomExtractorGen3" or "RomExtractorGen2", scripts = scripts, maps = {} }
	local game = { data = data, save = { flags = {}, party = {}, gen3Vars = {} } }
	local world = { map = { id = "NATIVE" } }
	local runner = Runner.new(game, world)
	local hooks, decoded = Hooks.new(), Hooks.new()
	hooks._decodedHooks = decoded
	Runtime.install(Events.new(), hooks, {})
	return game, runner, (gen == 2 and C2 or C3).compile(data, "ENTRY"), hooks, decoded
end
for _, gen in ipairs({ 2, 3 }) do
	local set, finish = gen == 2 and "setval" or "setvar", gen == 2 and "endall" or "end"
	local row = gen == 2 and { set, 4 } or { set, 0x4002, 4 }
	local game, runner, rows, native, decoded = fixture(gen, { ENTRY = { row, { finish } } })
	local calls, order, expected = 0, {}, 4
	native:wrap("script.command", function(next, ctx, op, args)
		order[#order + 1] = op
		T.eq(ctx.script, rows, "native callback retains the original compiled script identity")
		return next(ctx, op, args)
	end)
	runner:exec(rows, runner:makeContext())
	T.eq(calls, 0, "native-only runs never dispatch decoded callbacks")
	local baseline = table.concat(order, ",")
	order = {}
	decoded:wrap("script.command", function(next, ctx, op, ir)
		calls = calls + 1
		local result = next(ctx, op, ir)
		if op == set then
			T.eq(
				gen == 2 and ctx.g2Var or ctx.save.gen3Vars[0x4002],
				expected,
				"post-next observes the native command effects"
			)
		end
		return result
	end)
	runner:exec(rows, runner:makeContext())
	T.eq(calls, 2, "one decoded callback per source command")
	T.eq(table.concat(order, ","), baseline, "native command order is unchanged with a transparent profile")
	local prepared = Decoded.prepare(rows)
	T.same(prepared, rows, "transparent compiler trace preserves every native row and argument")
	native:removeOwner(nil) -- no changes: test-owned native callback remains installed
	local replacement = Hooks.new()
	replacement._decodedHooks = decoded
	Runtime.install(Events.new(), replacement, {})
	decoded:wrap("script.command", function(next, ctx, op, ir)
		if op == set then
			local copy = {}
			for k, v in pairs(ir) do
				copy[k] = v
			end
			copy[gen == 2 and 2 or 3] = 151
			return next(ctx, op, copy)
		end
		return next(ctx, op, ir)
	end, 100)
	expected = 151
	local editedContext = runner:makeContext()
	runner:exec(rows, editedContext)
	T.eq(
		gen == 2 and editedContext.g2Var or game.save.gen3Vars[0x4002],
		151,
		"edited decoded operands reach native execution"
	)
	T.eq(row[gen == 2 and 2 or 3], 4, "hook rewrites never mutate imported source rows")
end
-- Calls lower to several rows; a wrapper surrounds the complete command once.
local game, runner, rows, native, decoded = fixture(3, {
	ENTRY = { { "call", "SUB" }, { "setvar", 0x4010, 7 }, { "end" } },
	SUB = { { "setvar", 0x4011, 8 }, { "return" } },
})
local seen = {}
decoded:wrap("script.command", function(next, ctx, op, ir)
	seen[#seen + 1] = op
	if op == "setvar" and ir[2] == 0x4011 then
		return next(ctx, "addvar", { "addvar", 0x4011, 9 })
	end
	return next(ctx, op, ir)
end)
runner:exec(rows, runner:makeContext())
T.same(
	seen,
	{ "call", "setvar", "return", "setvar", "end" },
	"multi-row call, edited opcode and return keep decoded order"
)
T.eq(game.save.gen3Vars[0x4011], 9, "opcode replacements execute their own lowering")
T.eq(game.save.gen3Vars[0x4010], 7, "recompilation retains active call return addresses")
-- Zero-row loadword supplies a later std. A veto skips the entire grouped command.
local game2, run2, rows2, _, dec2 =
	fixture(3, { ENTRY = {
		{ "nop" },
		{ "loadword", 0, "TEXT_A" },
		{ "setvar", 0x4020, 3 },
		{ "end" },
	} })
local count = 0
dec2:wrap("script.command", function(next, ctx, op, ir)
	count = count + 1
	if op == "setvar" then
		return
	end
	if op == "loadword" then
		ir[3] = "TEXT_B"
	end
	return next(ctx, op, ir)
end)
run2:exec(rows2, run2:makeContext())
T.eq(count, 4, "zero-row operations are visible exactly once")
T.eq(game2.save.gen3Vars[0x4020], nil, "veto skips native effects")
-- The actual Loader routes only the explicitly selected mod onto the decoded bus.
local SDK = require("tests.modkit.sdk")
local Json = require("src.link.Json")
local Loader = require("src.mods.Loader")
Version.set("firered")
local fs = SDK.memfs({
	["options.lua"] = 'return {mods={probe=true},modCallbackProfiles={probe="decoded"}}',
	["mods/probe/manifest.json"] = Json.encode({ id = "probe", name = "Probe", version = "1.0.0", entry = "main.lua" }),
	["mods/probe/main.lua"] = [[return function(mod)
   mod.hooks:wrap('script.command',function(next,ctx,op,row)
     if op=='setvar' then row.value=99 end
     return next(ctx,op,row)
   end)
   mod.events:on('pokemon.before_give',function(gift)
     mod.exports.map=gift.ctx.overworld.map.id
     gift.level=20;gift.nickname='PROFILE'
   end)
 end]],
})
local data = require("tests.fixtures.upstream_mods.data").fresh()
data.maps.MAP_G04_N03 = { id = "MAP_G04_N03", group = 4, number = 3 }
local loader = Loader.new({ fs = fs, dev = false })
T.eq(loader:load(data), true, "actual Loader accepts an external per-mod profile")
T.eq(loader.hooks.chains["script.command"], nil, "selected hook does not alter the native chain")
T.check(loader._decodedHooks.chains["script.command"] ~= nil, "selected hook registers on its private bus")
data.map_scripts =
	{ source = "RomExtractorGen3", scripts = { ENTRY = { { "setvar", 0x4002, 4 }, { "end" } } }, maps = {} }
local g = { data = data, save = { flags = {}, party = {}, gen3Vars = {} }, mods = loader }
local world = { map = { id = "MAP_G04_N03", def = data.maps.MAP_G04_N03 } }
local r = Runner.new(g, world)
r:exec(C3.compile(data, "ENTRY"), r:makeContext())
T.eq(g.save.gen3Vars[0x4002], 99, "named row edit travels through Loader and compiler to native state")
local gift = { ctx = r:makeContext(), species = "CHARMANDER", level = 5 }
loader.events:emit("pokemon.before_give", gift)
T.eq(loader.exports.probe.map, "OAKS_LAB", "profile translates the verified native lab slot")
T.eq(world.map.id, "MAP_G04_N03", "native map identity is never renamed")
T.eq(gift.level, 20, "profile gift edits reach the existing gift event")
T.eq(gift.nickname, "PROFILE", "profile nickname edits commit")
loader:_rollback("probe")
T.eq(loader._decodedHooks.chains["script.command"], nil, "rollback retires the per-mod decoded registration")

-- Every visit starts from original IR, even when an earlier visit rewrote it.
do
	local g, r, program, _, bus = fixture(3, {
		ENTRY = { { "setvar", 0x4030, 0 }, { "goto", "LOOP" } },
		LOOP = {
			{ "addvar", 0x4030, 1 },
			{ "setvar", 0x4031, 4 },
			{ "compare_var_to_value", 0x4030, 3 },
			{ "goto_if", 0, "LOOP" },
			{ "end" },
		},
	})
	local values = {}
	bus:wrap("script.command", function(next, ctx, op, ir)
		if op == "setvar" and ir[2] == 0x4031 then
			values[#values + 1] = ir[3]
			if #values == 1 then
				ir[3] = 151
			elseif #values == 2 then
				return
			end
		end
		return next(ctx, op, ir)
	end)
	r:exec(program, r:makeContext())
	T.same(values, { 4, 4, 4 }, "loops offer original source operands after both rewrites and vetoes")
	T.eq(g.save.gen3Vars[0x4030], 3, "rewritten loop retains its branch and completion")
	T.eq(g.save.gen3Vars[0x4031], 4, "transparent later visit restores the original command")
end
-- A vetoed compile-time text load must not leak into a later callstd.
do
	local g, r, program, _, bus = fixture(3, { ENTRY = { { "loadword", 0, "TEXT_A" }, { "callstd", 4 }, { "end" } } })
	local shown = 0
	local Commands = require("src.script.Commands")
	local old = Commands.g3_show_text
	Commands.g3_show_text = function()
		shown = shown + 1
	end
	bus:wrap("script.command", function(next, ctx, op, ir)
		if op == "loadword" then
			return
		end
		return next(ctx, op, ir)
	end)
	r:exec(program, r:makeContext())
	Commands.g3_show_text = old
	T.eq(shown, 0, "veto removes compile-time text state from subsequent lowering")
end
-- Gen-2 selected profile keeps the fourth decoded row and lossless byte edits.
do
	Version.set("gold")
	local files = {
		["options.lua"] = "return {mods={probe=true}}",
		["mods/probe/manifest.json"] = Json.encode({
			id = "probe",
			name = "Probe",
			version = "1.0.0",
			entry = "main.lua",
		}),
		["mods/probe/main.lua"] = [=[return function(mod)
   mod.hooks:wrap('script.command',function(next,ctx,op,args,cmd)
    if op=='setval' then
     assert(cmd.op=='setval' and cmd.value==4 and args[1]==4)
     args[1]=77
     mod.exports.retained=next
    end
    return next(ctx,op,args,cmd)
   end)
   mod.events:once('pokemon.before_give',function(gift)mod.exports.gifts=(mod.exports.gifts or 0)+1 end)
  end]=],
	}
	local d = require("tests.fixtures.upstream_mods.data").fresh()
	local l = Loader.new({ fs = SDK.memfs(files), dev = false, callbackProfiles = { probe = "decoded" } })
	T.eq(l:load(d), true, "constructor profile works without editing a manifest or options file")
	d.map_scripts = { source = "RomExtractorGen2", scripts = { ENTRY = { { "setval", 4 }, { "endall" } } }, maps = {} }
	local g = { data = d, save = { flags = {}, party = {} } }
	local r = Runner.new(g, {})
	local ctx = r:makeContext()
	r:exec(C2.compile(d, "ENTRY"), ctx)
	T.eq(ctx.g2Var, 77, "Gen-2 raw byte edits are decoded before native lowering")
	T.raises(function()
		l.exports.probe.retained()
	end, "only valid during", "retained next cannot replay a completed command")
	l.events:emit("pokemon.before_give", { ctx = ctx, species = "CHARMANDER", level = 5 })
	l.events:emit("pokemon.before_give", { ctx = ctx, species = "CHARMANDER", level = 5 })
	T.eq(l.exports.probe.gifts, 1, "profiled once subscription retires on the original native event bus")
end
-- Deep source operands never escape into a retained callback record.
do
	local g, r, program, _, bus = fixture(3, { ENTRY = { { "nop", { nested = 1 } }, { "end" } } })
	bus:wrap("script.command", function(next, ctx, op, ir)
		if op == "nop" then
			ir[2].nested = 2
		end
		return next(ctx, op, ir)
	end)
	r:exec(program, r:makeContext())
	T.eq(g.data.map_scripts.scripts.ENTRY[1][2].nested, 1, "nested source operands remain unchanged")
end

-- Gift records include the cartridge species number without changing native
-- event records; numeric edits and variable-backed gifts resolve through data.
do
	Version.set("firered")
	local d = require("tests.fixtures.upstream_mods.data").fresh()
	d.constants.speciesOrder = { [4] = "CHARMANDER", [151] = "MEW" }
	local files = {
		["options.lua"] = 'return {mods={probe=true},modCallbackProfiles={probe="decoded"}}',
		["mods/probe/manifest.json"] = Json.encode({
			id = "probe",
			name = "Probe",
			version = "1.0.0",
			entry = "main.lua",
		}),
		["mods/probe/main.lua"] = [=[return function(mod)
   mod.events:on('pokemon.before_give',function(gift)
    assert(gift.speciesId==4)
    gift.species=151;gift.level=120;gift.nickname='NUMERIC'
   end)
  end]=],
	}
	local l = Loader.new({ fs = SDK.memfs(files), dev = false })
	assert(l:load(d))
	local g = { data = d, save = { gen3Vars = { [0x4002] = 4 } } }
	local ctx = { game = g, save = g.save, script = { { "g3_give_pokemon", 0x4002, 5, 0 } }, pc = 1 }
	local gift = { ctx = ctx, species = "CHARMANDER", level = 5 }
	local nativeSeen
	l.events:on("pokemon.before_give", function(row)
		nativeSeen = row
	end, -100, "native")
	l.events:emit("pokemon.before_give", gift)
	T.eq(gift.species, "MEW", "numeric profiled gift species resolves through this dataset")
	T.eq(gift.level, 100, "decoded gift level stays in the supported range")
	T.eq(g.save.gen3Vars[0x4002], 151, "variable-backed native gift retains the edited species number")
	T.eq(nativeSeen, gift, "native listeners retain the exact original gift record")
	T.eq(gift.speciesId, nil, "profile-only species metadata never leaks into native event records")
end

-- Hook and group scopes survive a real runner suspension across updates.
do
	local g, r, program, _, bus = fixture(3, { ENTRY = { { "delay", 2 }, { "setvar", 0x4050, 9 }, { "end" } } })
	local phases = {}
	bus:wrap("script.command", function(next, ctx, op, ir)
		if op == "delay" then
			phases[#phases + 1] = "before"
		end
		local value = next(ctx, op, ir)
		if op == "delay" then
			phases[#phases + 1] = "after"
		end
		return value
	end)
	r:run(program)
	T.eq(r:isRunning(), true, "profiled native delay suspends the actual runner")
	T.same(phases, { "before" }, "hook remains before next while native command is suspended")
	T.eq(g.save.gen3Vars[0x4050], nil, "later operation cannot run during the delay")
	r:update()
	r:update()
	T.eq(r:isRunning(), false, "native updates finish the profiled delay")
	T.same(phases, { "before", "after" }, "post-next executes exactly once after resumption")
	T.eq(g.save.gen3Vars[0x4050], 9, "native continuation executes after resumption")
end

-- Provenance must not keep a retired dataset alive through the compiler cache.
local weak, retained
local function retired(keepRows)
	local g, r, program = fixture(3, { ENTRY = { { "setvar", 0x4060, 1 }, { "end" } } })
	local refs = setmetatable({ g.data, program }, { __mode = "v" })
	return refs, keepRows and program or nil
end
weak = retired(false)
collectgarbage("collect")
collectgarbage("collect")
T.eq(weak[1], nil, "private provenance releases an unowned dataset")
T.eq(weak[2], nil, "private provenance releases an unowned compiled program")
weak, retained = retired(true)
collectgarbage("collect")
collectgarbage("collect")
T.eq(weak[1], nil, "a retained native row list cannot retain the entire source dataset")
T.raises(function()
	Decoded.prepare(retained)
end, "retired", "decoded execution refuses a retired source cohort")

do
	local g, r, program = fixture(3, { ENTRY = { { "setvar", 0x4060, 1 }, { "end" } } })
	g.data.map_scripts = { source = "RomExtractorGen3", scripts = { ENTRY = { { "end" } } }, maps = {} }
	T.raises(function()
		Decoded.prepare(program)
	end, "retired", "a replaced source pool retires old compiled provenance")
end
-- Swallowing an error below next cannot retry partial native side effects.
do
	local g, r, program, _, bus = fixture(3, { ENTRY = { { "setvar", 0x4060, 1 }, { "end" } } })
	local Commands = require("src.script.Commands")
	local original, count = Commands.g3_setvar, 0
	Commands.g3_setvar = function()
		count = count + 1
		error("owned native failure")
	end
	bus:wrap("script.command", function(next, ctx, op, ir)
		pcall(next, ctx, op, ir)
	end)
	T.raises(function()
		r:exec(program, r:makeContext({ source = { strict = true } }))
	end, "did not complete", "a mod cannot swallow a failing native group and restart it")
	Commands.g3_setvar = original
	T.eq(count, 1, "native side effects occur at most once across a swallowed failure")
end

for _, gen in ipairs({ 2, 3 }) do
	local compiler = gen == 2 and C2 or C3
	local g, r, program, _, bus = fixture(
		gen,
		{ ENTRY = gen == 2 and { { "setval", 4 }, { "endall" } } or { { "setvar", 0x4070, 4 }, { "end" } } }
	)
	T.eq(compiler.compile(g.data, "ENTRY", true), program, "public compiler continues to ignore surplus arguments")
	local original, calls = compiler.compile, 0
	compiler.compile = function(data, entry)
		calls = calls + 1
		return original(data, entry)
	end
	program = compiler.compile(g.data, "ENTRY")
	bus:wrap("script.command", function(next, ctx, op, ir)
		if op == "setval" then
			ir[2] = 7
		elseif op == "setvar" then
			ir[3] = 7
		end
		return next(ctx, op, ir)
	end)
	local ctx = r:makeContext()
	r:exec(program, ctx)
	T.eq(
		gen == 2 and ctx.g2Var or g.save.gen3Vars[0x4070],
		7,
		"a transparent public compiler wrapper cannot suppress decoded callbacks"
	)
	T.eq(calls, 1, "private tracing does not replay public compiler wrappers")
	compiler.compile = original
end

-- The decoded Gen-2 call contract runs its subroutine before post-next code.
do
	local g, r, program, _, bus = fixture(2, {
		ENTRY = { { "scall", "SUB" }, { "setval", 7 }, { "endall" } },
		SUB = { { "setval", 9 }, { "pause", 2 }, { "end" } },
	})
	local observed
	bus:wrap("script.command", function(next, ctx, op, ir)
		local result = next(ctx, op, ir)
		if op == "scall" then
			observed = ctx.g2Var
		end
		return result
	end)
	r:run(program)
	T.eq(observed, nil, "Gen-2 call hook remains suspended with its subroutine")
	T.eq(r:isRunning(), true, "nested native wait keeps the caller suspended")
	r:update()
	r:update()
	local ctx = r.ctx
	T.eq(observed, 9, "Gen-2 post-next sees the completed subroutine state")
	T.eq(ctx.g2Var, 7, "the caller continues after its decoded call hook closes")
end
T.finish()
