-- Edition claims shared by manifest validation, runtime loading and mod UIs.
local GameVersion = require("src.core.GameVersion")
local Targets = {}
local function family(id)
  local info = GameVersion.info(id)
  if info and info.layout then return info.layout end
  if id == "firered" or id == "leafgreen" then return "frlg" end
  if id == "ruby" or id == "sapphire" or id == "emerald" then return "rse" end
  return info and info.family
end

function Targets.expand(token)
  if type(token) ~= "string" then return nil end
  local key = token:lower():match("^%s*(.-)%s*$")
  local generation = tonumber(key:match("^gen%s*(%d+)$"))
  local out = {}
  for _, id in ipairs(GameVersion.ORDER) do
    if key == "all" or key == id
        or (generation and GameVersion.generation(id) == generation)
        or family(id) == key then
      out[#out + 1] = id
    end
  end
  return #out > 0 and out or nil
end

function Targets.normalize(tokens)
  local selected, unknown = {}, {}
  for _, token in ipairs(tokens or {}) do
    local expanded = Targets.expand(token)
    if expanded then
      for _, id in ipairs(expanded) do selected[id] = true end
    else
      unknown[#unknown + 1] = tostring(token)
    end
  end
  local out = {}
  for _, id in ipairs(GameVersion.ORDER) do
    if selected[id] then out[#out + 1] = id end
  end
  return out, unknown
end

-- No edition declaration retains the host's existing generation policy.
-- A present legacy flag is an explicit first/second-generation declaration.
function Targets.parse(raw)
  if raw.games == nil and raw.gen2compat == nil then return nil end
  assert(raw.games == nil or type(raw.games) == "table", "games must be an array")
  local count = 0
  for key in pairs(raw.games or {}) do
    count = count + 1
    assert(type(key) == "number" and key % 1 == 0 and key >= 1
      and key <= #raw.games, "games must be an array")
  end
  assert(count == #(raw.games or {}), "games must be an array")
  local games, unknown = Targets.normalize(raw.games)
  if #games == 0 then games = Targets.expand("gen1") or {} end
  if raw.gen2compat == true then
    local tokens = {}
    for _, id in ipairs(games) do tokens[#tokens + 1] = id end
    tokens[#tokens + 1] = "gen2"
    games = Targets.normalize(tokens)
  end
  return games, unknown
end

function Targets.supports(manifest, version, generation)
  if not manifest or manifest.games == nil then return true end
  for _, id in ipairs(manifest.games) do
    if version and id == version then return true end
    if not version and generation and GameVersion.generation(id) == generation then
      return true
    end
  end
  return false
end

-- With an exact edition, another edition in the same generation does not
-- satisfy the scope. A context-free catalogue may inspect all potential edges.
function Targets.specApplies(spec, version, generation, engineVersion)
  if spec.games and (version or generation) and not Targets.supports(spec, version, generation) then
    return false
  end
  if spec.game_version then
    return require("src.mods.Semver").satisfies(engineVersion or require("src.core.Version").engine, spec.game_version)
  end
  return true
end

function Targets.generations(manifest)
  if not manifest or manifest.games == nil then return nil end
  local seen, out, restriction = {}, {}, nil
  if type(manifest.generations) == "table" and manifest.generations[1] then
    restriction = {}
    for _, gen in ipairs(manifest.generations) do restriction[gen] = true end
  end
  for _, id in ipairs(manifest.games) do seen[GameVersion.generation(id)] = true end
  for gen in pairs(seen) do
    if not restriction or restriction[gen] then out[#out + 1] = gen end
  end
  table.sort(out)
  return out
end

function Targets.label(manifest)
  if not manifest or manifest.games == nil then return nil end
  local selected, allowed, total, counts = {}, {}, {}, {}
  for _, gen in ipairs(Targets.generations(manifest)) do allowed[gen] = true end
  for _, id in ipairs(manifest.games) do
    if allowed[GameVersion.generation(id)] then selected[id] = true end
  end
  for _, id in ipairs(GameVersion.ORDER) do
    local gen = GameVersion.generation(id)
    total[gen] = (total[gen] or 0) + 1
    if selected[id] then counts[gen] = (counts[gen] or 0) + 1 end
  end
  local labels, emitted = {}, {}
  for _, id in ipairs(GameVersion.ORDER) do
    local gen = GameVersion.generation(id)
    if selected[id] then
      if counts[gen] == total[gen] then
        if not emitted[gen] then labels[#labels + 1] = "Gen " .. gen; emitted[gen] = true end
      else
        local info = GameVersion.info(id)
        labels[#labels + 1] = info and info.label or id
      end
    end
  end
  return #labels > 0 and table.concat(labels, "/") or "No game"
end

function Targets.detail(manifest, version)
  local info = version and GameVersion.info(version)
  return ("For %s, not %s"):format(Targets.label(manifest) or "declared games",
    info and info.label or tostring(version))
end

function Targets.forced(options, id, version)
  if not GameVersion.VERSIONS[version] then return false end
  local overrides = options and options.modsGames
  local value = type(overrides) == "table" and overrides[id]
  if type(value) == "table" and value[version] ~= nil then
    return value[version] == true
  end
  -- Preserve an imported per-game preference without widening it.
  local legacy = options and options.modsGen2
  value = type(legacy) == "table" and legacy[id]
  if type(value) == "table" then return value[version] == true end
  return value == true and GameVersion.generation(version) == 2
end

function Targets.setForced(options, id, version, want)
  if not (type(options) == "table" and type(id) == "string" and GameVersion.VERSIONS[version]) then return false end
  options.modsGames = type(options.modsGames) == "table" and options.modsGames or {}
  local values = options.modsGames[id]
  if type(values) ~= "table" then values = {}; options.modsGames[id] = values end
  values[version] = want == true
  return true
end

return Targets
