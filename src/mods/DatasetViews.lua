-- Read-only version datasets. Generated modules are parsed as bounded data.
local Version = require("src.core.GameVersion")
local Literal = require("src.import.DataLiteral")
local Files = require("src.import.VersionFiles")
local Registry = require("src.mods.Registry")
local Schemas = require("src.mods.Schemas")
local Unified = require("src.mods.UnifiedContent")
local Merge = require("src.mods.Merge")
local D = {}
local CORE = {
  pokemon = true,
  moves = true,
  items = true,
  maps = true,
  trainers = true,
  encounters = true,
  type_chart = true,
  constants = true,
}
local MAX_TOTAL = 48 * 1024 * 1024
local function dataOnly(value, seen)
  if type(value) ~= "table" then
    return type(value) ~= "function" and type(value) ~= "userdata" and type(value) ~= "thread"
  end
  if getmetatable(value) ~= nil then
    return false
  end
  seen = seen or {}
  if seen[value] then
    return false
  end
  seen[value] = true
  for k, v in pairs(value) do
    if not dataOnly(k, seen) or not dataOnly(v, seen) then
      return false
    end
  end
  seen[value] = nil
  return true
end
local function asset(path)
  if
    type(path) ~= "string"
    or #path > 1024
    or path:sub(1, 17) ~= "assets/generated/"
    or path:find("[%c\\]")
  then
    error("dataset asset requires a generated relative path", 0)
  end
  for segment in path:gmatch("[^/]+") do
    if segment == "." or segment == ".." or segment:find(":", 1, true) then
      error("dataset asset path traversal", 0)
    end
  end
  return path
end
function D.new(fs, req, trust)
  req = req or require
  trust = trust or function(fn, ...)
    return fn(...)
  end
  local files = Files.new(fs)
  local function descriptor(version)
    local importer = req("src.import.RomImporter")
    return importer.datasetContract(version)
  end
  local function inspect(version)
    if type(version) ~= "string" or not Version.VERSIONS[version] then
      return nil, "unknown_version"
    end
    if Version.generation(version) > 3 then
      return nil, "unsupported_generation"
    end
    local contract = descriptor(version)
    local paths, names, total = {}, {}, 0
    for _, name in ipairs(contract.modules) do
      names[name] = true
    end
    for _, spec in pairs(Schemas.REGISTRIES) do
      local root = spec.target and spec.target:match("^[^%.]+")
      if root then
        names[root] = true
      end
    end
    local marker = files.read(version, "rom-cache.complete", 65536)
    if marker and (#marker > 65536 or marker:match("^[^\r\n]*") ~= contract.marker) then
      return nil, "not_imported"
    end
    local absent = {}
    for line in (marker or ""):gmatch("[^\r\n]+") do
      local name = line:match("^absent:data/generated/(.+)%.lua$")
      if name then
        absent[name] = true
      end
    end
    local mandatory = {}
    for _, name in ipairs(contract.modules) do
      if CORE[name] or not absent[name] then
        mandatory[name] = true
      end
    end
    for name in pairs(CORE) do
      mandatory[name] = true
    end
    for name in pairs(names) do
      local path = "data/generated/" .. name .. ".lua"
      local info = files.info(version, path)
      if info and (info.type == nil or info.type == "file") then
        if info.size and (info.size < 0 or info.size > Literal.LIMITS.bytes) then
          return nil, "invalid_cache"
        end
        total = total + (info.size or 0)
        if total > MAX_TOTAL then
          return nil, "invalid_cache"
        end
        paths[name] = path
      elseif mandatory[name] then
        return nil, "not_imported"
      end
    end
    local required = {}
    for name in pairs(mandatory) do
      required[#required + 1] = "data/generated/" .. name .. ".lua"
    end
    if not marker and not files.source(version, required) then
      return nil, "not_imported"
    end
    return {
      paths = paths,
      marker = marker,
      identity = files.identity(),
      source = not marker,
      required = required,
    }
  end
  local function open(version)
    local plan, why = inspect(version)
    if not plan then
      return nil, why
    end
    local view = { version = version, generation = Version.generation(version) }
    local cache, decodedBytes, revision = {}, 0, 0
    local registries, handles, invalid
    local function reject(reason)
      invalid = reason or "invalid_cache"
      return nil
    end
    local function safe(fn, ...)
      local function pack(...)
        return { n = select("#", ...), ... }
      end
      local r = pack(trust(pcall, fn, ...))
      if not r[1] then
        return reject("invalid_cache")
      end
      return (table.unpack or unpack)(r, 2, r.n)
    end
    local function ready()
      if invalid then
        return false
      end
      local nextPlan = inspect(version)
      if not nextPlan or nextPlan.identity ~= plan.identity or nextPlan.marker ~= plan.marker then
        return reject("not_imported")
      end
      for name, path in pairs(plan.paths) do
        if nextPlan.paths[name] ~= path then
          return reject("not_imported")
        end
      end
      local changed = false
      for name in pairs(nextPlan.paths) do
        if not plan.paths[name] then
          changed = true
        end
      end
      for name, old in pairs(cache) do
        local source = files.read(version, plan.paths[name], Literal.LIMITS.bytes)
        if type(source) ~= "string" then
          return reject("invalid_cache")
        end
        if source ~= old.source then
          changed = true
        end
      end
      if changed then
        cache = {}
        decodedBytes = 0
        registries = nil
        handles = nil
        revision = revision + 1
      end
      plan = nextPlan
      return true
    end
    local function module(name)
      if cache[name] then
        return cache[name].value
      end
      local path = plan.paths[name]
      if not path then
        return nil
      end
      local source = files.read(version, path, Literal.LIMITS.bytes)
      if type(source) ~= "string" or #source > Literal.LIMITS.bytes then
        return reject("invalid_cache")
      end
      decodedBytes = decodedBytes + #source
      if decodedBytes > MAX_TOTAL then
        return reject("invalid_cache")
      end
      local value = Literal.decode(source)
      if not value then
        return reject("invalid_cache")
      end
      cache[name] = { source = source, value = value }
      return value
    end
    local function build()
      if handles then
        return handles
      end
      local data = setmetatable({}, {
        __index = function(t, key)
          local value = module(key)
          if value ~= nil then
            rawset(t, key, value)
          end
          return value
        end,
      })
      local constants = data.constants
      if constants and constants.generation ~= nil and constants.generation ~= view.generation then
        return reject("invalid_cache")
      end
      registries = {}
      for name, spec in pairs(Schemas.REGISTRIES) do
        local shape = Merge.deepCopy(spec)
        if name == "pokemon" and view.generation > 1 then
          for _, key in ipairs({ "spatk", "spdef" }) do
            shape.fields.baseStats.fields[key] = Schemas.f.opt(Schemas.f.int(1, 255))
          end
        end
        local r = Registry.new(name, shape)
        if spec.target then
          local target = spec.target
          r.base = function()
            local node = data
            for key in target:gmatch("[^%.]+") do
              node = type(node) == "table" and node[key] or nil
            end
            return node
          end
        end
        registries[name] = r
      end
      -- Seed engine data descriptors in isolated registries; function-bearing
      -- runtime records are filtered from every public read below.
      req("src.mods.Builtins").install(registries, data)
      if invalid then
        return nil
      end
      for _, r in pairs(registries) do
        r:freeze()
      end
      local raw = {}
      for name, r in pairs(registries) do
        raw[name] = {
          get = function(_, id)
            return r:get(id)
          end,
          has = function(_, id)
            return r:get(id) ~= nil
          end,
          each = function()
            return r:each()
          end,
        }
      end
      handles = Unified.new({ content = registries }, { manifest = { id = "dataset" } }, raw, view.generation)
      return handles
    end
    local function rawValid(name, id)
      local r = registries[name]
      local raw = r:get(id)
      if raw == nil or not dataOnly(raw) then
        return false
      end
      local ok = Schemas.check(r.spec, name, id, raw, "override")
      if not ok then
        reject("invalid_cache")
        return false
      end
      return true
    end
    local function current(name)
      if not ready() then
        return nil
      end
      local all = build()
      if invalid then
        return nil
      end
      return all and all[name]
    end
    local function get(name, id, prepared)
      if type(id) ~= "string" or id == "" then
        return nil
      end
      local handle = prepared and handles[name] or current(name)
      if not handle then
        return nil
      end
      local value = handle:get(id)
      if invalid or value == nil or not dataOnly(value) then
        return nil
      end
      -- Unified core IDs may have native aliases; validate all rows involved
      -- through the native registry, not just the normalized projection.
      if require("src.mods.UnifiedSchemas")[name] then
        local group = require("src.mods.UnifiedIds").new({ content = registries }):resolve(name, id)
        if not group or not rawValid(name, group.key) then
          return nil
        end
      elseif not rawValid(name, id) then
        return nil
      end
      return Merge.deepCopy(value)
    end
    view.content = {}
    for name in pairs(Schemas.REGISTRIES) do
      local registryName = name
      view.content[name] = {
        get = function(_, id)
          return safe(get, registryName, id)
        end,
        has = function(_, id)
          return safe(get, registryName, id) ~= nil
        end,
        each = function()
          return safe(function()
            local handle = current(registryName)
            local rows = {}
            if handle then
              for id in handle:each() do
                local value = get(registryName, id, true)
                if invalid then
                  rows = {}
                  break
                end
                if value ~= nil then
                  rows[#rows + 1] = { id, value }
                end
              end
            end
            local initial, index = revision, 0
            return function()
              return safe(function()
                if
                  invalid
                  or revision ~= initial
                  or files.identity() ~= plan.identity
                  or files.read(version, "rom-cache.complete", 65536) ~= plan.marker
                then
                  return nil
                end
                index = index + 1
                local row = rows[index]
                if row then
                  return row[1], Merge.deepCopy(row[2])
                end
              end)
            end
          end) or function() end
        end,
      }
    end
    for alias, name in pairs(Schemas.ALIASES) do
      view.content[alias] = view.content[name]
    end
    view.assets = {
      path = function(_, path)
        path = asset(path)
        return safe(function()
          if not ready() then
            return nil
          end
          return files.path(version, path)
        end)
      end,
      info = function(_, path)
        path = asset(path)
        return safe(function()
          if not ready() then
            return nil
          end
          local info = files.info(version, path)
          return info and (info.type == nil or info.type == "file") and { type = "file", size = info.size }
            or nil
        end)
      end,
    }
    return view
  end
  return {
    open = function(_, version)
      local ok, view, why = trust(pcall, open, version)
      if not ok then
        return nil, "invalid_cache"
      end
      return view, why
    end,
  }
end
return D
