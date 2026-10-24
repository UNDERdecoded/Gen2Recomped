local F = {}
function F.new(root, backend, version, api, format, mode, id, source, body, prepare, configure)
  local T, V = require("tests.modkit"), require("src.core.GameVersion")
  V.set(version)
  local gen, J = V.generation(), require("src.link.Json")
  local data = backend == "gen1" and gen == 3 and T.sdk.gen3Data() or { constants = { generation = gen } }
  if backend == "gen1" and gen == 1 then
    data = T.fixtures.fresh()
  end
  local raw = { PORTABLE_TEXT = "BASE", KEEP = "KEEP" }
  if gen == 2 then
    raw[backend == "gen1" and "55:4067" or "TEXT_S55_4067"] = "SCRIPT BASE"
  end
  if backend == "gen1" and gen == 2 then
    data.text, data.gen2Text = { ENGINE_ONLY = "ENGINE" }, raw
  elseif backend == "gen1" and gen == 3 then
    local IR = require("src.core.game3.scripting.text_ir")
    local native = {}
    for key, value in pairs(raw) do
      native[key] = IR.fromAscii(value)
    end
    data.gen3Text = native
  else
    data.text = raw
  end
  if prepare then
    prepare(data, gen)
  end
  local name, files = "portable_text_sources", {}
  for _, path in ipairs({ "manifest.json", "main.lua" }) do
    local f = assert(io.open(root .. "/examples/" .. name .. "/" .. path, "rb"))
    files["mods/" .. name .. "/" .. path] = f:read("*a")
    f:close()
  end
  local manifest = J.decode(files["mods/" .. name .. "/manifest.json"])
  manifest.api, manifest.games, manifest.content_format = api, { version }, format
  manifest.gen2compat = api < 3 and true or nil
  files["mods/" .. name .. "/manifest.json"] = J.encode(manifest)
  files["mods/" .. name .. "/case.txt"] = mode
  files["mods/" .. name .. "/id.txt"] = id
  files["mods/" .. name .. "/source.txt"] = source
  if body then
    files["mods/" .. name .. "/main.lua"] = "local mod=...; mod.exports.api=mod; " .. body
  end
  files["mods/" .. name .. "/enumerate.txt"] = "yes"
  if configure then
    configure(files, name, J)
  end
  if mode == "corpus" then
    for i, value in ipairs(dofile(root .. "/tests/text_sources/corpus.lua")) do
      files["mods/" .. name .. "/corpus/" .. i] = value
    end
  end
  if mode == "no-mod" then
    files = {}
  end
  local r = T.sdk.loadMods(
    mode == "no-mod" and {} or { "mods/" .. name },
    { data = data, fs = T.sdk.memfs(files), generation = gen, dev = false }
  )
  local f = { T = T, result = r, data = data, gen = gen, e = r.loader.exports[name] }
  function f.raw(key)
    if backend == "gen1" and gen == 3 then
      return data.gen3Text[key]
    end
    if backend == "gen1" and gen == 2 then
      return data.gen2Text[key]
    end
    if gen == 2 then
      local b, a = key:match("^(%x%x):(%x%x%x%x)$")
      if b and key == key:lower() then
        key = ("TEXT_S%02X_%04X"):format(tonumber(b, 16), tonumber(a, 16))
      end
    end
    return data.text[key]
  end
  function f.source(key)
    local value = f.raw(key)
    if backend == "gen1" and gen == 3 and value then
      local IR = require("src.core.game3.scripting.text_ir")
      local dialect = IR.dialect(version == "emerald" and "rse" or "frlg")
      local parts = {}
      for _, row in ipairs(value) do
        if row.t == "eos" then
          break
        elseif row.t == "text" then
          parts[#parts + 1] = row.s
        elseif row.t == "tag" then
          parts[#parts + 1] = row.tag
        elseif row.t == "player" then
          parts[#parts + 1] = "{PLAYER}"
        elseif row.t == "rival" then
          parts[#parts + 1] = "{RIVAL}"
        elseif row.t == "strvar" then
          parts[#parts + 1] = "{STR_VAR_" .. row.n .. "}"
        elseif row.t == "ph" then
          parts[#parts + 1] = "{" .. (row.name or dialect.PH_NAMES[row.code]) .. "}"
        elseif row.t == "bph" then
          parts[#parts + 1] = "{" .. dialect.B_TXT[row.code] .. "}"
        else
          parts[#parts + 1] = assert(({ nl = "\n", para = "\f", scroll = "\v" })[row.t], row.t)
        end
      end
      return table.concat(parts)
    end
    if gen == 3 and value then
      local parts, i = {}, 1
      while i <= #value do
        if value:sub(i, i) == "\\" and i < #value then
          parts[#parts + 1] = value:sub(i, i + 1)
          i = i + 2
        else
          local slot = value:sub(i):match("^{VAR([123])}")
          if slot then
            parts[#parts + 1] = "{STR_VAR_" .. slot .. "}"
            i = i + 6
          else
            parts[#parts + 1] = value:sub(i, i)
            i = i + 1
          end
        end
      end
      return table.concat(parts)
    end
    return value
  end
  function f.dialogue(key)
    if backend == "gen1" and gen == 2 then
      local vm = require("src.script.gen2.Vm").new({}, data.gen2Text, nil, { showText = function() end })
      local co = coroutine.create(function()
        vm:showText(key)
      end)
      local ok, row = coroutine.resume(co)
      assert(ok, row)
      return row.text
    elseif backend == "gen1" and gen == 3 then
      local vm = require("src.core.game3.scripting.vm").new({ text = data.gen3Text })
      return require("src.core.game3.scripting.text_ir").toAscii(
        vm:getText(key),
        { playerName = "PROBE", rivalName = "RIVAL", stringVars = { "ONE", "TWO", "THREE" } }
      )
    end
    local game = {
      data = data,
      save = { player = { name = "PROBE", rival = "RIVAL" }, options = {} },
      stringBuffers = { "ONE", "TWO", "THREE" },
      input = {
        wasPressed = function()
          return false
        end,
      },
    }
    game.stack = setmetatable({}, { __index = require("src.core.StateStack") })
    game.stack:init()
    require("src.render.Font").load(data)
    local runner = require("src.script.ScriptRunner").new(game)
    if gen == 2 then
      local b, a = key:match("^(%x%x):(%x%x%x%x)$")
      if b and key == key:lower() then
        key = ("TEXT_S%02X_%04X"):format(tonumber(b, 16), tonumber(a, 16))
      end
    end
    local script = { { "show_text", key } }
    if gen == 2 then
      data.map_scripts = { scripts = { probe = { { "writetext", key }, { "end" } } } }
      script = assert(require("src.script.Gen2ScriptVM").compile(data, "probe"))
    elseif gen == 3 then
      script = { { "g3_show_text", key } }
    end
    runner:run(script)
    local box = assert(game.stack:top(), "native script did not open a textbox")
    local lines = {}
    for _, page in ipairs(box.pages) do
      for _, line in ipairs(page) do
        lines[#lines + 1] = line
      end
    end
    return table.concat(lines, "|")
  end
  function f.close()
    r.release()
  end
  return f
end
return F
