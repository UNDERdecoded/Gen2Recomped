-- Resolve portable names through this boot's own data, never a hard-coded
-- National Dex/item-number table (ROM hacks can assign entirely different IDs).
local Ids = {}
local function slug(name)
  if type(name) ~= "string" then return nil end
  name = name:gsub("é", "e"):gsub("É", "E"):gsub("♀", "_F"):gsub("♂", "_M")
    :gsub("['’]", ""):upper():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  name = name:gsub("^(TM)(%d+)$", "%1_%2"):gsub("^(HM)(%d+)$", "%1_%2")
  return name ~= "" and name or nil
end
local aliases = { FARFETCH_D = "FARFETCHD", MR__MIME = "MR_MIME" }
local function canonical(key, row, kind)
  if kind == "pokemon" or kind == "moves" or kind == "items" then
    if type(key) ~= "string" or key:match("^SPECIES_%d+$")
        or key:match("^MOVE_%d+$") or key:match("^ITEM_%d+$") then
      return aliases[slug(row.name)] or slug(row.name)
    end
    return aliases[key] or key
  end
  -- Trainer classes, individual trainers and map IDs are game-specific.
  return type(key) == "number" and tostring(key) or key
end

function Ids.new(loader)
  local indexes = {}
  local function index(kind)
    if indexes[kind] then return indexes[kind] end
    local out = { public = {}, native = {} }
    indexes[kind] = out
    local registry = assert(loader.content[kind], "unknown registry " .. tostring(kind))
    -- Preserve identity/name metadata before the loader merges alias keys
    -- into separate result tables. Presentation-name patches cannot rename IDs.
    loader._unifiedIdBase = loader._unifiedIdBase or {}
    local base = loader._unifiedIdBase[kind]
    if not base then
      base = {}
      for key, row in pairs(registry.base and registry.base() or {}) do
        if type(row) == "table" then
          base[key] = { identity = row, id = canonical(key, row, kind) }
        end
      end
      loader._unifiedIdBase[kind] = base
    end
    local groups = {}
    for key, row in registry:each() do
      if type(row) == "table" and (row.name or kind == "encounters") and key ~= 0 then
        -- Aliases pointing at one pristine record form one identity even
        -- after an earlier native mod patched only one of its keys.
        local identity = base[key] and base[key].identity or row
        local group = groups[identity]
        if not group then
          local id = base[key] and base[key].id or canonical(key, row, kind)
          if id then
            group = { id = id, key = key, keys = {} }
            groups[identity] = group
            local previous = out.public[id]
            -- false is an ambiguity marker, never last-writer-wins.
            if previous ~= nil then out.public[id] = false else out.public[id] = group end
          end
        end
        if group then
          group.keys[#group.keys + 1] = key
          out.native[key] = group
          if type(key) == "number" then group.key = key end
        end
      end
    end
    return out
  end
  return {
    resolve = function(_, kind, id)
      local found = index(kind).public[id]
      if found == false then return nil, "ambiguous " .. kind .. " ID: " .. tostring(id) end
      if not found then return nil, "unknown " .. kind .. " ID: " .. tostring(id) end
      return found
    end,
    read = function(_, kind, id)
      if id == nil or id == false or id == 0 or id == "" then return nil end
      local found = index(kind).native[id]
      return found and found.id or tostring(id)
    end,
    entries = function(_, kind) return index(kind).public end,
  }
end
return Ids
