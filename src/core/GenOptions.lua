-- PER-GENERATION SETTINGS.
--
-- Asked for alongside the per-generation mod switches: "also allow users to
-- pick per generation settings as well".  The same reasoning applies.  COLORS
-- is the clearest case -- DMG green is the right answer for Red and an
-- obviously wrong one for Emerald -- but FAITHFUL RES, GBC FX and the frame
-- cap all mean different things on a Game Boy screen and a GBA one, and until
-- this there was one value for all three and no way to say otherwise.
--
-- THE SHAPE ON DISK IS ADDITIVE, exactly like ModGens:
--
--   options.<key>                        -- the shared value, unchanged
--   options.perGeneration[g][key]        -- what generation g uses instead
--
-- An absent generation, or an absent key inside one, falls through to the
-- shared value.  So a build that has never seen an override reads and writes
-- what it always did, and an older build handed a file with overrides in it
-- ignores a table it does not know about and keeps playing.  Nothing migrates
-- in either direction.
--
-- OVERRIDES ARE STORED, NOT FLATTENED.  Clearing one has to give the shared
-- value back, which means the shared value has to still be there -- so
-- `resolve` copies rather than edits, and `fold` (the write direction, used
-- when a game that was loaded under an override saves its options again) puts
-- a changed value back into the override it came from instead of leaking it
-- into the shared one.
--
-- SOME KEYS ARE NEVER PER-GENERATION.  The options file is also where the mod
-- enable-state, the save-slot registry and the launcher's own settings live.
-- Those describe the installation, not a playthrough, and a generation-scoped
-- copy of the mod list is a way to lose a mod list.  SHARED_ONLY names them,
-- and it is a deny-list rather than an allow-list so that a key added later
-- is per-generation-able by default -- the failure mode of forgetting to add
-- a new option here is that it becomes settable per generation, which is
-- recoverable, rather than that it silently stops being.

local GenOptions = {}

-- Gen 4 (Platinum) joins here.  `isGeneration` below is the one test the rest
-- of the app should use; COUNT is what it bounds against, so these two lines
-- are the whole change and nothing that defers to them needs touching.
GenOptions.GENERATIONS = { 1, 2, 3, 4 }
GenOptions.COUNT = 4

GenOptions.SHARED_ONLY = {
  mods = true,
  modOptions = true,
  modData = true,
  modIndexes = true,
  modIndexCache = true,
  modUpdateCache = true,
  saveSlots = true,
  touchControls = true,
  haptics = true,
  tutorials = true,
  perGeneration = true,
  dataDir = true,
  launcherTheme = true,
  launcherAccent = true,
  launcherText = true,
  launcherGeneration = true,
}

function GenOptions.isGeneration(g)
  g = tonumber(g)
  if not g then return false end
  return g >= 1 and g <= GenOptions.COUNT and g == math.floor(g)
end

function GenOptions.canOverride(key)
  if type(key) ~= "string" or key == "" then return false end
  return not GenOptions.SHARED_ONLY[key]
end

-- The whole override table for one generation, or nil.  Read-only to callers:
-- `set` is the way to change one.
function GenOptions.bucket(opts, g)
  if type(opts) ~= "table" or not GenOptions.isGeneration(g) then return nil end
  local per = opts.perGeneration
  if type(per) ~= "table" then return nil end
  local bucket = per[tonumber(g)]
  if type(bucket) ~= "table" then return nil end
  return bucket
end

-- The override for one key, or nil when there is none.  `nil` is the only
-- "no override" signal, which is why a stored false is kept as a false: OFF
-- is a perfectly ordinary thing to override a shared ON with.
function GenOptions.override(opts, key, g)
  if not GenOptions.canOverride(key) then return nil end
  local bucket = GenOptions.bucket(opts, g)
  if not bucket then return nil end
  local v = bucket[key]
  if v == nil then return nil end
  return v
end

function GenOptions.hasOverride(opts, key, g)
  return GenOptions.override(opts, key, g) ~= nil
end

-- The value generation `g` actually plays with: its override if it has one,
-- otherwise the shared value.  A nil or out-of-range `g` is the shared value,
-- so every caller can pass whatever it has without checking first.
function GenOptions.get(opts, key, g)
  if type(opts) ~= "table" then return nil end
  local v = GenOptions.override(opts, key, g)
  if v ~= nil then return v end
  return opts[key]
end

-- set(opts, key, value, g)
--
-- A nil or false `g` writes the shared value -- the pre-existing behaviour and
-- still the common one.  A generation writes that generation's override; the
-- sentinel `GenOptions.INHERIT` removes it instead, which is how a row goes
-- back to following the shared value.  Mutates `opts` in place and returns it,
-- because every caller here already holds the table it is about to save.
GenOptions.INHERIT = setmetatable({}, { __tostring = function() return "INHERIT" end })

function GenOptions.set(opts, key, value, g)
  if type(opts) ~= "table" or type(key) ~= "string" then return opts end
  if not GenOptions.isGeneration(g) then
    if value ~= GenOptions.INHERIT then opts[key] = value end
    return opts
  end
  if not GenOptions.canOverride(key) then
    -- Silently shared rather than an error: this is reached from a click
    -- handler, and the row for such a key is simply never offered per
    -- generation, so arriving here at all means something upstream is wrong
    -- in a way a crash on a mouse press would not help anyone diagnose.
    opts[key] = value
    return opts
  end
  g = tonumber(g)
  local per = type(opts.perGeneration) == "table" and opts.perGeneration or {}
  local bucket = type(per[g]) == "table" and per[g] or {}
  if value == GenOptions.INHERIT then
    bucket[key] = nil
  else
    bucket[key] = value
  end
  -- An emptied bucket is removed rather than left as `{}`: the launcher asks
  -- "does this generation override anything" by looking, and an empty table
  -- that answers yes is a row that says OVERRIDDEN with nothing behind it.
  if next(bucket) == nil then
    per[g] = nil
  else
    per[g] = bucket
  end
  if next(per) == nil then
    opts.perGeneration = nil
  else
    opts.perGeneration = per
  end
  return opts
end

function GenOptions.clearKey(opts, key, g)
  return GenOptions.set(opts, key, GenOptions.INHERIT, g)
end

-- Drop every override for one generation, or for all of them when `g` is nil.
function GenOptions.clear(opts, g)
  if type(opts) ~= "table" then return opts end
  if not GenOptions.isGeneration(g) then
    opts.perGeneration = nil
    return opts
  end
  local per = opts.perGeneration
  if type(per) ~= "table" then return opts end
  per[tonumber(g)] = nil
  if next(per) == nil then opts.perGeneration = nil end
  return opts
end

-- How many keys generation `g` overrides -- what the launcher puts on the
-- section heading so a player can see at a glance that GEN 1 is not simply
-- following the shared settings.
function GenOptions.count(opts, g)
  local bucket = GenOptions.bucket(opts, g)
  if not bucket then return 0 end
  local n = 0
  for key in pairs(bucket) do
    if GenOptions.canOverride(key) then n = n + 1 end
  end
  return n
end

-- A flat options table as generation `g` sees it: a shallow copy of the
-- shared table with that generation's overrides laid over it.  A COPY, always
-- -- the caller hands this to a running game, which will edit it, and editing
-- the launcher's table through it is how a playthrough's text speed ends up
-- as everybody's text speed.
--
-- perGeneration itself rides along untouched so that a game which saves its
-- options back (Game:writeOptions) does not erase everyone else's overrides;
-- `fold` below is what puts the changed values in the right place.
function GenOptions.resolve(opts, g)
  if type(opts) ~= "table" then return opts end
  local out = {}
  for k, v in pairs(opts) do out[k] = v end
  local bucket = GenOptions.bucket(opts, g)
  if not bucket then return out end
  for key, value in pairs(bucket) do
    if GenOptions.canOverride(key) then out[key] = value end
  end
  return out
end

-- The write direction of `resolve`.
--
-- `live` is a table a game has been playing with, resolved for generation `g`
-- and then edited by the in-game OPTIONS menu.  `stored` is what is on disk.
-- A key generation `g` overrides takes the new value INTO THAT OVERRIDE; every
-- other key takes it shared, exactly as before per-generation settings existed.
--
-- Which means: change COLORS in-game while playing Emerald, with a Gen 3
-- override in place, and Emerald's override changes -- not Red's screen.
-- Without an override in place the shared value changes, which is what a
-- player who never opened the per-generation rows expects and gets.
function GenOptions.fold(stored, live, g)
  if type(live) ~= "table" then return stored end
  if type(stored) ~= "table" then stored = {} end
  if not GenOptions.isGeneration(g) then
    for k, v in pairs(live) do stored[k] = v end
    return stored
  end
  local bucket = GenOptions.bucket(stored, g)
  for k, v in pairs(live) do
    if bucket and bucket[k] ~= nil and GenOptions.canOverride(k) then
      bucket[k] = v
    else
      stored[k] = v
    end
  end
  -- `live` carried perGeneration through resolve untouched, and assigning it
  -- back above would have replaced the table we just edited with the copy's
  -- reference to the same one -- harmless, but re-pointing it here keeps the
  -- edited bucket authoritative whatever `live` happened to hold.
  if bucket then
    local per = type(stored.perGeneration) == "table" and stored.perGeneration or {}
    per[tonumber(g)] = bucket
    stored.perGeneration = per
  end
  return stored
end

return GenOptions
