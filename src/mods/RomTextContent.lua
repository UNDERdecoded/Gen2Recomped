-- Separate engine prose from VM text. The registry is virtual so the native
-- VM addresses retain their original storage. Known Gen-2 prose labels also
-- project into the legacy table so existing native UI readers consume them.
local Copy = require("src.mods.Merge").deepCopy
local Source = require("src.mods.TextContent")
local Labels = require("src.mods.RomTextLabels")
local V = require("src.core.GameVersion")
local M = {}
local previous = setmetatable({}, { __mode = "k" })
local function same(a, b)
  for key, value in pairs(a) do
    if b[key] ~= value then
      return false
    end
  end
  for key, value in pairs(b) do
    if a[key] ~= value then
      return false
    end
  end
  return true
end
function M.prepare(loader, data)
  local old = data and previous[data]
  if old then
    if data.romText == old.value then
      if same(old.value, old.snapshot) then
        data.romText, data._romTextGeneration, data._romTextTouched =
          old.before, old.beforeGeneration, old.beforeTouched
      else
        -- Preserve intervening external edits while retiring untouched keys.
        for id in pairs(old.touched) do
          if old.value[id] == old.snapshot[id] then
            old.value[id] = old.before and old.before[id] or nil
            data._romTextTouched[id] = old.beforeTouched and old.beforeTouched[id] or nil
          end
        end
      end
    end
    for _, row in ipairs(old.projections or {}) do
      if data.text == row.target and row.target[row.key] == row.value then
        row.target[row.key] = row.before
      end
    end
    previous[data] = nil
  end
  local base, gen = {}, loader:_generation()
  loader._romTextNativeIds = {}
  loader._romTextLabels = nil
  loader._privateScriptTextPrefix = "__portable_script_text__:"
  if gen == 2 then
    -- Reserve an unused prefix, and escape authored IDs beginning with it.
    -- This keeps internal registry keys disjoint from native base records.
    local occupied = true
    while occupied do
      occupied = false
      for id in pairs(data and data.text or {}) do
        if
          type(id) == "string"
          and id:sub(1, #loader._privateScriptTextPrefix) == loader._privateScriptTextPrefix
        then
          loader._privateScriptTextPrefix = loader._privateScriptTextPrefix .. "_"
          occupied = true
          break
        end
      end
    end
    local known = Labels.forVersion(V.get())
    loader._romTextLabels = Copy(known or {})
    if known then
      for id in pairs(known) do
        local value = data and data.text and data.text[id]
        if type(value) == "string" then
          base[id] = value
          loader._romTextNativeIds[id] = true
        end
      end
    end
  end
  for id, value in pairs(data and data.romText or {}) do
    base[id] = value
    loader._romTextNativeIds[id] = nil
    if gen == 2 then
      loader._romTextLabels[id] = true
    end
  end
  loader._romTextBase = base
  loader.content.rom_text.base = function()
    return base
  end
end

-- Stable semantic bindings for the native Pokemon-storage actions. Each row
-- is read from sPokemonStorageActions by the importer; no word matching is used.
local STORAGE_LABELS = {
  "gText_WithdrawPokemon",
  "gText_DepositPokemon",
  "gText_MovePokemon",
  "gText_MoveItems",
  "gText_SeeYa",
}
local STORAGE_DESCRIPTIONS = {
  "gText_WithdrawMonDescription",
  "gText_DepositMonDescription",
  "gText_MoveMonDescription",
  "gText_MoveItemsDescription",
  "gText_SeeYaDescription",
}
function M.storageView(game, base)
  local data = game and game.data
  local overrides = data and data._romTextGeneration == 3 and data.romText
  if not overrides then
    return base
  end
  local out
  for field, labels in pairs({ rows = STORAGE_LABELS, describe = STORAGE_DESCRIPTIONS }) do
    for i, label in ipairs(labels) do
      local value = overrides[label]
      if value ~= nil then
        out = out or Copy(base)
        out[field] = out[field] or {}
        local text = require("src.render.TextBox").substitute(game, value)
        out[field][i] = text:gsub("[\f\v]", "\n\n")
      end
    end
  end
  return out or base
end
function M.apply(loader, data)
  if not data then
    return
  end
  -- Private script records for labels that also exist in the engine-prose
  -- namespace never remain as synthetic keys in the legacy text table.
  for physical, logical in pairs(loader._privateScriptTextIds or {}) do
    if loader.content.text.ops[physical] then
      data._portableScriptText = data._portableScriptText or {}
      data._portableScriptText[logical] = assert(loader._privateScriptTextRows[physical])
      data.text[physical] = nil
    end
  end
  local gen, registry = loader:_generation(), loader.content.rom_text
  if (gen ~= 2 and gen ~= 3) or next(registry.ops) == nil then
    return
  end
  if gen == 2 then
    for id in pairs(loader._romTextNativeIds) do
      if not registry.ops[id] then
        loader._romTextBase[id] = data.text and data.text[id]
        registry.cache[id] = nil
      end
    end
  end
  local values, touched = Copy(loader._romTextBase), {}
  for id in pairs(registry.ops) do
    values[id], touched[id] = registry:get(id), true
  end
  local undo = {
    before = data.romText,
    beforeGeneration = data._romTextGeneration,
    beforeTouched = data._romTextTouched,
    value = values,
    snapshot = Copy(values),
    touched = touched,
    projections = {},
  }
  if gen == 2 then
    local known = Labels.forVersion(V.get()) or {}
    for id in pairs(touched) do
      if known[id] then
        data.text = data.text or {}
        undo.projections[#undo.projections + 1] =
          { target = data.text, key = id, before = data.text[id], value = values[id] }
        data.text[id] = values[id]
      end
    end
  end
  data.romText, data._romTextGeneration, data._romTextTouched = values, gen, touched
  previous[data] = undo
end

function M.api(loader, mod, native, generation, unified)
  local version = V.get()
  local available = generation == 2 or generation == 3
  local reason = not available and "unsupported: rom_text has no native target in this generation" or nil
  local out = {
    available = available,
    supports = function()
      return available, reason
    end,
  }
  function out:get(id)
    if not available then
      return nil, reason
    end
    assert(type(id) == "string" and id ~= "", "rom_text: registry id is required")
    local value = native:get(id)
    if value ~= nil and unified then
      return Source.source(value, generation, version, true)
    end
    return value
  end
  function out:has(id)
    return out:get(id) ~= nil
  end
  function out:each()
    if not available then
      return function() end
    end
    local nextRow = native:each()
    return function()
      local id = nextRow()
      if id then
        return id, out:get(id)
      end
    end
  end
  for _, verb in ipairs({ "register", "override", "patch", "remove" }) do
    out[verb] = function(_, id, value)
      if not available then
        return nil, reason
      end
      assert(not loader.content.rom_text.frozen, "rom_text: content is frozen after load")
      local ok, result = pcall(function()
        local payload = value
        if unified and verb ~= "remove" then
          payload = Source.write(value, generation, version)
        end
        native[verb](native, id, payload)
        return out:get(id)
      end)
      if ok then
        return result
      end
      if type(result) == "string" and result:sub(1, 13) == "unsupported: " then
        return nil, result
      end
      error(result, 0)
    end
  end
  return out
end
return M
