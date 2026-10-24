local F = {}
function F.new(root, backend, version, mode, api, format, body, prepare)
  local T, V = require("tests.modkit"), require("src.core.GameVersion")
  V.set(version)
  local gen, J = V.generation(), require("src.link.Json")
  local names =
    { "gText_WithdrawPokemon", "gText_DepositPokemon", "gText_MovePokemon", "gText_MoveItems", "gText_SeeYa" }
  local desc = {
    "gText_WithdrawMonDescription",
    "gText_DepositMonDescription",
    "gText_MoveMonDescription",
    "gText_MoveItemsDescription",
    "gText_SeeYaDescription",
  }
  local data = backend == "gen1" and gen == 3 and T.sdk.gen3Data() or { constants = { generation = gen } }
  local label = gen == 2 and "_WokeUpText" or names[1]
  local value = gen == 2 and "{USER} is awake!" or "TAKE FRIEND"
  data.text = { _WokeUpText = "{USER} woke up!" }
  if backend == "gen1" then
    data.gen2Text = { ["55:4067"] = "SCRIPT BASE" }
  else
    data.text.TEXT_S55_4067 = "SCRIPT BASE"
  end
  if gen == 3 then
    if backend == "gen1" then
      data.gen3RomText, data.gen3Text = {}, {}
    end
    data.constants = data.constants or {}
    local storage = { rows = {}, describe = {} }
    for i in ipairs(names) do
      storage.rows[i], storage.describe[i] = "BASE" .. i, "DETAIL" .. i
    end
    data.constants.gen3PCMenu = { storage = storage }
  end
  if prepare then
    prepare(data, gen)
  end
  local name, files = "portable_rom_text", {}
  for _, path in ipairs({ "main.lua", "manifest.json" }) do
    local f = assert(io.open(root .. "/examples/" .. name .. "/" .. path, "rb"))
    files["mods/" .. name .. "/" .. path] = f:read("*a")
    f:close()
  end
  local m = J.decode(files["mods/" .. name .. "/manifest.json"])
  m.api, m.content_format, m.games, m.gen2compat = api, format, { version }, api < 3 and true or nil
  files["mods/" .. name .. "/manifest.json"] = J.encode(m)
  files["mods/" .. name .. "/case.txt"] = mode
  files["mods/" .. name .. "/label.txt"] = label
  files["mods/" .. name .. "/source.txt"] = value
  if mode == "same-label" or mode == "namespace-prefix" or mode == "empty-script" then
    files["mods/" .. name .. "/script.txt"] = mode == "empty-script" and "" or "SCRIPT ONLY"
  end
  if body then
    files["mods/" .. name .. "/main.lua"] = "local mod=...; mod.exports.api=mod; " .. body
  end
  if mode == "no-mod" then
    files = {}
  end
  local r = T.sdk.loadMods(
    mode == "no-mod" and {} or { "mods/" .. name },
    { data = data, fs = T.sdk.memfs(files), generation = gen, dev = false }
  )
  local f = {
    T = T,
    result = r,
    data = data,
    gen = gen,
    label = label,
    source = value,
    e = r.loader.exports[name],
  }
  local restore = function() end
  if backend == "gen1" and gen == 3 then
    local IR, Rom = require("src.core.game3.scripting.text_ir"), require("src.core.game3.rom_text")
    local Space = require("src.core.game3.scripting.space")
    local oldBundle, oldOverrides = Space.bundle, Rom.overrides
    local text = {}
    for i, key in ipairs(names) do
      text[key] = IR.fromAscii("BASE" .. i)
    end
    for i, key in ipairs(desc) do
      text[key] = IR.fromAscii("DETAIL" .. i)
    end
    Space.bundle, Rom.overrides = { text = text }, data.gen3RomText
    restore = function()
      Space.bundle, Rom.overrides = oldBundle, oldOverrides
    end
  end
  function f.prose()
    if gen == 2 then
      if backend == "gen1" then
        return require("src.core.RomText")(data, label, "%s fallback", "GOLD")
      end
      local b = setmetatable({ data = data }, { __index = require("src.battle.BattleState") })
      return b:romText(label, "%s fallback", "GOLD")
    elseif gen == 3 then
      if backend == "gen1" then
        local row = require("src.ui.game3.pc_menu")._storageOptions()[1]
        return row.label, row.desc
      end
      local game = { data = data, save = { player = { name = "PROBE" }, options = {} } }
      local menu = require("src.ui.Gen3StorageMenu").new(game, {})
      return menu.items[1].label, menu.items[1].describe
    end
  end
  function f.storageRows()
    local out, rows = {}, nil
    if backend == "gen1" then
      rows = require("src.ui.game3.pc_menu")._storageOptions()
    else
      local game = { data = data, save = { player = { name = "PROBE" }, options = {} } }
      rows = require("src.ui.Gen3StorageMenu").new(game, {}).items
    end
    for i, row in ipairs(rows) do
      out[i] = { label = row.label, description = row.describe or row.desc }
    end
    return out
  end
  function f.script(id)
    id = id or label
    if backend == "gen1" then
      local vm = require("src.script.gen2.Vm").new({}, data.gen2Text, nil, { showText = function() end })
      local co = coroutine.create(function()
        vm:showText(id)
      end)
      local ok, row = coroutine.resume(co)
      assert(ok, row)
      return row.text
    end
    local game = { data = data, save = { player = { name = "PROBE" }, options = {} } }
    game.stack = setmetatable({}, { __index = require("src.core.StateStack") })
    game.stack:init()
    require("src.render.Font").load(data)
    local runner = require("src.script.ScriptRunner").new(game)
    runner:run({ { "show_text", id } })
    local box = assert(game.stack:top())
    return table.concat(box.pages[1], "|")
  end
  function f.close()
    restore()
    r.release()
  end
  return f
end
return F
