-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- The Gold source vocabulary over the shared engine's real encounter rows.
-- Slot arrays remain native. This is a read view, never a second encounter
-- picker, RNG, clock or copy of the merged dataset.
local Version = require('src.core.GameVersion')
local Encounter = require('src.world.Encounter')
local Views = {}
local owners = setmetatable({}, { __mode = 'kv' })

local function readonly()
  error('Gen2 encounter views are read-only; use the encounters registry', 2)
end

function Views.forData(data)
  if not Version.isGen2() or type(data) ~= 'table' then return nil end
  local cached = owners[data]
  if cached then return cached end
  local edition = Version.get()
  local function terrain(id, kind)
    if Version.get() ~= edition then return nil end
    local all = data.encounters or {}
    local row = all[id]
    if row == nil then
      local map = data.maps and data.maps[id]
      local source = type(map) == 'table' and map.sourceId
      if type(source) == 'string' and data.maps[source] == map then
        row = all[source]
      end
    end
    local value = type(row) == 'table' and row[kind]
    if type(value) == 'table' and type(value.slots) == 'table'
        and #value.slots > 0 then return value end
  end
  local function maps(kind)
    local rows = {}
    local function row(id)
      if type(id) ~= 'string' or not terrain(id, kind) then return nil end
      return setmetatable({}, {
        __index = function(_, key)
          local native = terrain(id, kind)
          if not native then return nil end
          if kind == 'water' then return native[key] end
          if key == 'rates' or key == 'slots' then
            local out = {}
            for _, tod in ipairs({'MORN', 'DAY', 'NITE'}) do
              local band = Encounter.atTime(native, tod)
              out[tod] = key == 'slots' and band.slots or band.rate
            end
            return out
          end
        end,
        __newindex = readonly,
      })
    end
    -- Enumerate actual source and published map names, including aliases
    -- proven by a shared native record. No spelling guesses for authored maps.
    for id in pairs(data.encounters or {}) do rows[id] = row(id) end
    for id in pairs(data.maps or {}) do rows[id] = row(id) end
    return setmetatable(rows, { __index = function(_, id) return row(id) end })
  end
  cached = { grass = maps('grass'), water = maps('water') }
  owners[data] = cached
  return cached
end

function Views.publish(data)
  if not Version.isGen2() or type(data) ~= 'table' then return false end
  -- Republish after a registry merge so enumeration includes added maps.
  owners[data] = nil
  data.gen2Encounters = Views.forData(data)
  return true
end

return Views
