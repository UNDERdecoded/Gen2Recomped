-- Original contribution by Roxas2712. See LICENSE-ROXAS2712.md.
-- Compiler provenance lives outside public command rows and engine contexts.
local M = {}
local origins = setmetatable({}, { __mode = "k" })

function M.origin(rows, data, entry, compile, generation)
	origins[rows] = {
		data = setmetatable({ data, data.map_scripts.scripts }, { __mode = "v" }),
		entry = entry,
		compile = compile,
		generation = generation,
	}
end
function M.trace()
	return { commands = {}, byKey = {}, owners = {}, labels = {}, returns = {}, returnKeys = {} }
end
function M.begin(t, label, index, ir)
	local c = { key = label .. ":" .. index, label = label, index = index, ir = ir, returns = 0 }
	t.commands[#t.commands + 1], t.byKey[c.key], t.current = c, c, c
end
function M.emit(t, row)
	t.owners[row] = t.current
end
function M.returnLabel(t, label)
	local c = t.current
	if not c then
		return
	end
	c.returns = c.returns + 1
	local key = c.key .. ":return:" .. c.returns
	t.returns[label], t.returnKeys[key] = key, label
end
function M.finish(rows, t)
	local positions = {}
	for pc, row in ipairs(rows) do
		positions[row] = pc
		local c = t.owners[row]
		if c and not c.pc then
			c.pc = pc
		end
	end
	t.starts = {}
	local nextPC
	for i = #t.commands, 1, -1 do
		local c = t.commands[i]
		local finish = assert(positions[t.labels[c.label]], "missing decoded script boundary")
		if not nextPC or c.label ~= t.commands[i + 1].label then
			nextPC = finish
		end
		c.after = nextPC
		c.pc = c.pc or nextPC
		nextPC = c.pc
	end
	for _, c in ipairs(t.commands) do
		t.starts[c.pc] = t.starts[c.pc] or {}
		t.starts[c.pc][#t.starts[c.pc] + 1] = c
	end
end
function M.prepare(rows)
	local stored = origins[rows]
	if not stored then
		return
	end
	local data = assert(stored.data[1], "decoded script source dataset has been retired")
	assert(
		data.map_scripts and data.map_scripts.scripts == stored.data[2],
		"decoded script source cohort has been retired"
	)
	-- Only an executing script borrows a strong source reference. The weak-key
	-- compiler cache and this provenance table must not keep each other alive.
	local origin = { data = data, entry = stored.entry, compile = stored.compile, generation = stored.generation }
	local trace = M.trace()
	local result = origin.compile(origin.data, origin.entry, { trace = trace })
	assert(M.same(result, rows), "decoded profile requires an unmodified native compiled script")
	return rows, trace, origin
end
-- Recompile a private overlay; never change imported IR or the ordinary cache.
function M.rewrite(origin, oldTrace, overrides, command, ir, ctx)
	overrides[command.label] = overrides[command.label] or {}
	overrides[command.label][command.index] = ir
	local scripts = {}
	for label, rows in pairs(origin.data.map_scripts.scripts) do
		if overrides[label] then
			local copy = {}
			for i, row in ipairs(rows) do
				copy[i] = overrides[label][i] or row
			end
			scripts[label] = copy
		else
			scripts[label] = rows
		end
	end
	local data, pool = {}, {}
	for k, v in pairs(origin.data) do
		data[k] = v
	end
	for k, v in pairs(origin.data.map_scripts) do
		pool[k] = v
	end
	pool.scripts, data.map_scripts = scripts, pool
	local trace = M.trace()
	local rows = origin.compile(data, origin.entry, { trace = trace, keepLabels = oldTrace.labels })
	for _, field in ipairs({ "g2Stack", "g3Stack" }) do
		for i, label in ipairs(ctx[field] or {}) do
			local key = oldTrace.returns[label]
			if key then
				ctx[field][i] = assert(trace.returnKeys[key], "rewritten command removed an active return")
			end
		end
	end
	return rows, trace, assert(trace.byKey[command.key])
end
function M.copy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local out = {}
	seen[value] = out
	for k, v in pairs(value) do
		out[k] = M.copy(v, seen)
	end
	return out
end
function M.same(a, b, seen)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	seen = seen or {}
	if seen[a] then
		return seen[a] == b
	end
	seen[a] = b
	for k, v in pairs(a) do
		if not M.same(v, b[k], seen) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end
function M.source(origin, command)
	return origin.data.map_scripts.scripts[command.label][command.index]
end
return M
