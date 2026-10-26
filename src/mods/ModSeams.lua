-- WHAT A MOD CHANGED ON THE ENGINE, SO IT CAN BE TAKEN BACK OFF.
--
-- One process can load the mods more than once.  EXIT GAME goes back to the
-- launcher IN PROCESS (main.lua returnToLauncher), the launcher's backdrop
-- boots the plain game behind it, and the next Play runs Game:load -- and so
-- every mod's main.lua -- again.  Android does the same thing without the
-- launcher: backing out leaves the process resident.
--
-- The loader's own buses (events, hooks, registries) are per-loader and come
-- back fresh.  What does NOT come back fresh is everything a mod did directly
-- to the engine's module tables, which live in package.loaded for the life of
-- the process:
--
--   * an unguarded wrap (`X.f = function(...) ... orig(...) end`) is applied
--     again on top of itself, so it runs twice per call on the second boot,
--     three times on the third;
--   * a wrap guarded by a flag (`if X.wrapped then return end`) sees the flag
--     the FIRST load left and skips -- so the wrapper still on the engine is
--     the first load's, talking to a mod instance nothing drives any more
--     (DRAMATIC_SHAPE's white battle screen; its lib/Rewrap.lua exists
--     because of exactly this, and it is the only mod that has one);
--   * package.preload entries, `mods.*` modules in package.loaded and
--     globals keep the first load's closures.
--
-- Reproduced by tools/mod_double_load_check (launcher -> Play -> EXIT GAME ->
-- Play): a probe mod's unguarded wrap ran twice per call on the second boot,
-- and its flag-guarded wrap belonged to boot 1.
--
-- So the loader brackets every piece of mod code it runs at load time -- each
-- entry chunk, and the lifecycle events mods do their late installs in
-- (mods.loaded, game.ready) -- with a shallow snapshot of the engine's tables,
-- and keeps what changed.  `unwindAll` puts it back, newest first, and only
-- where the value is still the one the mod put there: a wrap something else
-- stacked on top since is left alone rather than torn out from under it.
--
-- WHAT IS PUT BACK: a function that was replaced, and a key that did not
-- exist before (a flag, a global, a preload entry, a `mods.*` module).  A
-- plain value the mod changed from one thing to another (a tuning number) is
-- left as it is -- the next load sets it again, and guessing that a number is
-- mod residue rather than engine state is how a teardown corrupts a game.
--
-- WHAT IS NOT SEEN: anything a mod changes later, during play (a wrap made on
-- the first battle), and fields below the top level of a table.  Those are
-- still the mod's to guard; this takes away the common case, not the need.

local ModSeams = {}

-- every change, oldest first: { tbl, key, before, after, owner }
local journal = {}
ModSeams._journal = journal

-- tables of the engine's that the mods' state lives on
local function watched()
  local out = {}
  local seen = {}
  local function add(t, label)
    if type(t) == "table" and not seen[t] then
      seen[t] = true
      out[#out + 1] = { t = t, label = label }
    end
  end
  for name, value in pairs(package.loaded) do
    if type(name) == "string" and name:match("^src%.")
        and name ~= "src.mods.ModSeams" and name ~= "src.mods.Runtime" then
      add(value, name)
    end
  end
  add(_G, "_G")
  add(package.preload, "package.preload")
  add(package.loaded, "package.loaded")
  if type(love) == "table" then
    add(love, "love")
    for key, sub in pairs(love) do
      if type(sub) == "table" and type(key) == "string" then add(sub, "love." .. key) end
    end
  end
  return out
end

local function copyOf(t)
  local c = {}
  local k, v = next(t)
  while k ~= nil do
    c[k] = v
    k, v = next(t, k)
  end
  return c
end

-- package.loaded is watched for MOD modules only: an engine module required
-- for the first time inside a mod's window is a real module the engine goes
-- on using, and evicting it would split its identity in two.
local function keepKey(entry, key)
  if entry.t == package.loaded then
    return type(key) == "string" and (key:match("^mods[%./]") ~= nil)
  end
  return true
end

local function restorable(before, after)
  if before == nil then return true end
  return type(before) == "function" or type(after) == "function"
end

-- open a window.  Returns a token for close().  Never throws.
function ModSeams.open(owner)
  local ok, token = pcall(function()
    local snap = {}
    for _, entry in ipairs(watched()) do
      snap[#snap + 1] = { t = entry.t, label = entry.label, before = copyOf(entry.t) }
    end
    -- an engine module required for the FIRST time inside this window is
    -- snapshotted the moment it loads, before the mod gets it back to wrap
    local fresh = {}
    local real = rawget(_G, "require")
    local function require2(name, ...)
      local had = package.loaded[name]
      local result = real(name, ...)
      if name=='src.core.game3.battle' then
        local facade=package.loaded['src.core.Game3'] or real('src.core.Game3')
        if facade and facade._observeMod then facade._observeMod(owner)end
        local watched=false
        for _,entry in ipairs(snap)do if entry.t==facade then watched=true;break end end
        if type(facade)=='table'and not watched and not fresh[facade]then
          fresh[facade]=true
          snap[#snap+1]={t=facade,label='src.core.Game3',before=copyOf(facade)}
        end
      end
      if had == nil and type(name) == "string" and name:match("^src%.")
          and type(result) == "table" and not fresh[result] then
        fresh[result] = true
        snap[#snap + 1] = { t = result, label = name, before = copyOf(result) }
      end
      return result
    end
    rawset(_G, "require", require2)
    return { owner = owner, snap = snap, require2 = require2, real = real }
  end)
  return ok and token or nil
end

-- close a window and journal what changed in it.  Returns the number of
-- changes recorded.
function ModSeams.close(token)
  if not token then return 0 end
  local ok, count = pcall(function()
    if rawget(_G, "require") == token.require2 then
      rawset(_G, "require", token.real)
    end
    local n = 0
    for _, s in ipairs(token.snap) do
      local before, t = s.before, s.t
      local entry = { t = t }
      local k, v = next(t)
      while k ~= nil do
        local was = before[k]
        if was ~= v and keepKey(entry, k) and restorable(was, v)
            and not (t == _G and k == "require") then
          journal[#journal + 1] = { tbl = t, key = k, before = was, after = v,
                                    owner = token.owner, label = s.label }
          n = n + 1
        end
        k, v = next(t, k)
      end
      -- a function the mod removed outright
      for key, was in pairs(before) do
        if rawget(t, key) == nil and type(was) == "function" and keepKey(entry, key) then
          journal[#journal + 1] = { tbl = t, key = key, before = was, after = nil,
                                    owner = token.owner, label = s.label }
          n = n + 1
        end
      end
    end
    return n
  end)
  return ok and count or 0
end

-- run fn(...) inside a window for owner; returns pcall-style results
function ModSeams.run(owner, fn, ...)
  local token = ModSeams.open(owner)
  local results = { pcall(fn, ...) }
  ModSeams.close(token)
  return unpack(results)
end

local function unwind(filter)
  local undone, kept = 0, 0
  for i = #journal, 1, -1 do
    local e = journal[i]
    if not filter or filter(e) then
      if rawget(e.tbl, e.key) == e.after then
        rawset(e.tbl, e.key, e.before)
        undone = undone + 1
      else
        kept = kept + 1
      end
      table.remove(journal, i)
    end
  end
  return undone, kept
end

-- take back everything one mod did (a failed entry chunk's residue)
function ModSeams.unwindOwner(owner)
  return unwind(function(e) return e.owner == owner end)
end

-- take back everything every mod did, newest first: the start of a fresh
-- load, and the way back to the launcher
function ModSeams.unwindAll()
  local n = #journal
  local undone, kept = unwind(nil)
  if n > 0 then
    pcall(function()
      require("src.core.Logger").info(
        "mods: took back %d engine change(s) a previous load made (%d left "
          .. "in place: something else replaced them since)", undone, kept)
    end)
  end
  return undone, kept
end

-- what is journaled, per owner -- for a diagnostic line and the check tool
function ModSeams.summary()
  local by = {}
  for _, e in ipairs(journal) do
    local owner = tostring(e.owner)
    by[owner] = (by[owner] or 0) + 1
  end
  return by
end

return ModSeams
