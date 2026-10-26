-- Original contribution by Roxas2712. See LICENSE-ROXAS2712.md.
-- Selected by the host per mod; imported mod bytes and native buses stay intact.
local M = {}
local unpack = table.unpack or unpack
local function pack(...)
	return { n = select("#", ...), ... }
end
local fields = {
	setvar = { "var", "value" },
	addvar = { "var", "value" },
	subvar = { "var", "value" },
	copyvar = { "var", "src" },
	setorcopyvar = { "var", "value" },
	compare_var_to_value = { "var", "value" },
	loadword = { "dest", "value" },
	setflag = { "flag" },
	clearflag = { "flag" },
	checkflag = { "flag" },
	callstd = { "id" },
	jumpstd = { "id" },
	gotostd = { "std" },
	["goto"] = { "target" },
	call = { "target" },
	goto_if = { "cond", "target" },
	call_if = { "cond", "target" },
	setval = { "value" },
	addval = { "value" },
	writebyte = { "value" },
	setevent = { "event" },
	clearevent = { "event" },
	checkevent = { "event" },
	scall = { "script" },
	farscall = { "script" },
	sjump = { "script" },
	farsjump = { "script" },
	iftrue = { "script" },
	iffalse = { "script" },
	ifequal = { "value", "script" },
	ifnotequal = { "value", "script" },
	ifgreater = { "value", "script" },
	ifless = { "value", "script" },
	writetext = { "text" },
	jumptext = { "text" },
	farwritetext = { "text" },
	givepoke = { "species", "level", "item", "trainer", "name", "otName" },
	giveegg = { "species", "level" },
	givemon = { "species", "level", "item" },
	sdefer = { "script" },
	stopandsjump = { "script" },
	jumptextfaceplayer = { "text" },
	farjumptext = { "text" },
	pause = { "frames" },
	setscene = { "scene" },
	setmapscene = { "group", "map", "scene" },
	turnobject = { "object", "facing" },
	applymovement = { "object", "movement" },
	applymovementlasttalked = { "movement" },
	special = { "id" },
	playmusic = { "id" },
	playsound = { "id" },
	cry = { "id" },
	getmonname = { "species", "buffer" },
	getitemname = { "item", "buffer" },
	gettrainername = { "group", "trainer", "buffer" },
	loadtrainer = { "class", "member" },
	loadwildmon = { "species", "level" },
	winlosstext = { "winText", "lossText" },
	trainertext = { "index" },
	trainerflagaction = { "action" },
	setlasttalked = { "object" },
	showemote = { "emote", "object", "frames" },
	giveitem = { "item", "quantity" },
	verbosegiveitem = { "item", "quantity" },
	addcellnum = { "phone" },
	delcellnum = { "phone" },
	checkcellnum = { "phone" },
	readvar = { "var" },
	writevar = { "var" },
	follow = { "a", "b" },
	faceobject = { "a", "b" },
	follownotexact = { "a", "b" },
	trade = { "trade" },
	describedecoration = { "decoration" },
}
local function copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end
-- Only lossless numeric byte layouts can be reconstructed from native IR.
-- Decoded pointers/text use named fields; normalized hack layouts are not bytes.
local function rawOperands(op, ir)
	local version = require("src.core.GameVersion").get()
	if version ~= "gold" and version ~= "silver" and version ~= "crystal" then
		return {}, nil
	end
	local spec
	for _, command in ipairs(require("src.import.Gen2ScriptOps").commandsFor(version)) do
		if command[1] == op then
			spec = command[2]
			break
		end
	end
	if not spec or spec:find("[^bwm]") or #spec ~= #ir - 1 then
		return {}, nil
	end
	local out = {}
	for i = 1, #spec do
		local value, width = ir[i + 1], ({ b = 1, w = 2, m = 3 })[spec:sub(i, i)]
		if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value >= 256 ^ width then
			return {}, nil
		end
		for _ = 1, width do
			out[#out + 1] = value % 256
			value = math.floor(value / 256)
		end
	end
	return out, spec
end
local function context(ctx)
	local world, map = ctx.overworld, ctx.overworld and ctx.overworld.map
	if not map then
		return ctx
	end
	local data = ctx.game and ctx.game.data
	local maps = data and data.maps
	local version = require("src.core.GameVersion").get()
	local id = map.id
	if maps and (version == "firered" or version == "leafgreen") then
		local def = maps[map.id]
		local verified = def and map.def == def and def.group == 4 and def.number == 3
		if verified then
			for _, other in pairs(maps) do
				if type(other) == "table" and other ~= def and other.group == 4 and other.number == 3 then
					verified = false
					break
				end
			end
		end
		-- One explicit callback alias, qualified against this world's native
		-- definition. Similar spellings or an unbound slot are not evidence.
		if verified then
			id = "OAKS_LAB"
		end
	end
	local publicMap = setmetatable({ id = id }, { __index = map })
	local publicWorld = setmetatable({ map = publicMap }, {
		__index = world,
		__newindex = function(_, k, v)
			world[k] = v
		end,
	})
	return setmetatable({ overworld = publicWorld }, {
		__index = ctx,
		__newindex = function(_, k, v)
			ctx[k] = v
		end,
	})
end
function M.install(loader, api, owner, generation)
	if generation ~= 2 and generation ~= 3 then
		return
	end
	local aliases = copy(fields)
	if generation == 3 then
		aliases.callstd = { "std" }
		aliases.special = { "id" }
		aliases.applymovement = { "localId", "movement" }
	end
	local wrap, on, once = api.hooks.wrap, api.events.on, api.events.once
	local ids = require("src.mods.UnifiedIds").new(loader)
	ids:entries("pokemon")
	api.hooks.wrap = function(self, name, callback, priority)
		if name ~= "script.command" then
			return wrap(self, name, callback, priority)
		end
		return loader._decodedHooks:wrap(name, function(nextFn, ctx, op, ir)
			local row = { op = op }
			for i = 2, #ir do
				row[i - 1] = ir[i]
			end
			for i, field in ipairs(aliases[op] or {}) do
				row[field] = row[i]
			end
			local original = copy(row)
			local public = context(ctx)
			local args, byteSpec = {}, nil
			if generation == 2 then
				args, byteSpec = rawOperands(op, ir)
				row.args = args
			end
			local originalArgs = copy(args)
			local active = true
			local function nextPublic(hctx, hname, hrow, hcmd)
				assert(active, "decoded next is only valid during its callback")
				assert(hctx == nil or hctx == public, "decoded next must retain its script context")
				local edited = generation == 2 and (hcmd or row) or (hrow or row)
				local raw = copy(ir)
				for i = 1, math.max(#row, #edited) do
					raw[i + 1] = edited[i]
				end
				for i, field in ipairs(aliases[op] or {}) do
					if edited[field] ~= original[field] then
						raw[i + 1] = edited[field]
					end
				end
				if generation == 2 then
					local bytes = hrow or edited.args or args
					local changed = #bytes ~= #originalArgs
					for k, v in pairs(bytes) do
						if originalArgs[k] ~= v then
							changed = true
						end
					end
					if changed then
						assert(
							byteSpec,
							"raw Gen-2 byte rewrite is unavailable for this normalized command; use decoded fields"
						)
						assert(#bytes == #originalArgs, "Gen-2 operand byte width changed")
						local at = 1
						for i = 1, #byteSpec do
							local value, width = 0, ({ b = 1, w = 2, m = 3 })[byteSpec:sub(i, i)]
							for n = 0, width - 1 do
								local byte = bytes[at]
								at = at + 1
								assert(
									type(byte) == "number" and byte % 1 == 0 and byte >= 0 and byte < 256,
									"invalid Gen-2 operand byte"
								)
								value = value + byte * 256 ^ n
							end
							raw[i + 1] = value
						end
					end
				end
				raw[1] = hname or edited.op or op
				return nextFn(ctx, raw[1], raw)
			end
			local result
			if generation == 2 then
				result = pack(pcall(callback, nextPublic, public, op, args, row))
			else
				result = pack(pcall(callback, nextPublic, public, op, row))
			end
			active = false
			if not result[1] then
				error(result[2], 0)
			end
			return unpack(result, 2, result.n)
		end, priority, owner)
	end
	local function subscribe(register, self, name, callback, priority)
		if name ~= "pokemon.before_give" then
			return register(self, name, callback, priority)
		end
		return register(self, name, function(gift)
			local view = copy(gift)
			view.ctx = context(gift.ctx)
			view.species = ids:read("pokemon", gift.species)
			local order = gift.ctx.game and gift.ctx.game.data.constants and gift.ctx.game.data.constants.speciesOrder
				or {}
			local function numberFor(species)
				for number, id in pairs(order) do
					if id == species then
						return number
					end
				end
			end
			view.speciesId = numberFor(gift.species)
			local before = view.species
			callback(view)
			local species = gift.species
			if view.species ~= before then
				if type(view.species) == "number" then
					species = assert(order[view.species], "unknown decoded gift species number")
				else
					species = assert(ids:resolve("pokemon", view.species)).key
				end
			end
			local level = tonumber(view.level)
			level = level and math.max(1, math.min(100, math.floor(level))) or gift.level
			local nickname = type(view.nickname) == "string" and view.nickname ~= "" and view.nickname or gift.nickname
			-- A variable-backed Gen-3 gift keeps the requested species in that same
			-- native variable for the rest of the starter/story script.
			local ctx, number = gift.ctx, numberFor(species)
			local command = ctx.script and ctx.script[ctx.pc]
			if
				generation == 3
				and species ~= gift.species
				and number
				and command
				and command[1] == "g3_give_pokemon"
				and type(command[2]) == "number"
				and command[2] >= 0x4000
			then
				ctx.save.gen3Vars = ctx.save.gen3Vars or {}
				ctx.save.gen3Vars[command[2]] = number
			end
			gift.species, gift.level, gift.nickname = species, level, nickname
		end, priority)
	end
	api.events.on = function(self, ...)
		return subscribe(on, self, ...)
	end
	api.events.once = function(self, ...)
		return subscribe(once, self, ...)
	end
end
return M
