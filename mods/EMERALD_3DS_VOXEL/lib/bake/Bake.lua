-- The Lua bake: Emerald 3DS's voxel generators run on the player's ROM,
-- with no Python.  Mirrors mods/EMERALD_3DS_VOXEL/bake/bake.py's
-- `bake_from_checkout` path:
--
--   1. vtree.build_tree(rom, recipe) -> an in-memory Tree (lib/bake/Tree.lua)
--   2. install the generator assets into tree/3ds_port (Bake.install_assets:
--      fetched from the pinned Emerald 3DS commit, cached in the save dir)
--   3. the steps of emerald3ds_builder/voxel.py STEPS (gen_intro_margins is
--      not voxel data and is skipped)
--   4. layouts.lua from data/layouts/layouts.json (Bake.layouts_lua)
--
-- Plain Lua + `bit`; love.* only through what the caller passes in (an
-- inflate function, an HTTP getter, a cache, an output opener), so it can
-- run in a love.thread.  See ARCHITECTURE.md.

local V = ...
local json = V.require("bake/json")

local Bake = {}

-- ── the assets the generators read ───────────────────────────────────────
-- Emerald 3DS's own files (MIT, its author's), never shipped with the mod:
-- fetched at bake time from the dev checkout's commit the port follows.
Bake.ASSET_COMMIT = "3a1afea3409e44715d5b3a36dde6d4410b587341"
Bake.ASSET_BASE = "https://raw.githubusercontent.com/ZallaxDev/emerald-3ds/"
-- tree-relative paths (the repository's own layout)
Bake.ASSETS = {
  -- the relief fixes the relief and building generators read
  -- (voxel_relief_fixes.py; ~880 KB of JSON)
  "3ds_port/assets/voxel/relief_fixes.json",
  -- VOXEL_ROLE_* numbers gen_voxel_regions.py parses (2 KB)
  "3ds_port/src/voxel/voxel_regions.h",
}
-- The six tree pictures the mod draws (not read by the generators): as
-- bake.py fetch_trees, at its pinned commit.
Bake.TREE_COMMIT = "b198c08defb94081ae995796cf75ab8cdb51f2d0"
Bake.TREES = { "tree_crown.png", "tree_trunk.png", "tree_small_crown.png", "tree_small_trunk.png",
               "tree_2_small_crown.png", "tree_2_small_trunk.png" }
Bake.TREE_DIR = "3ds_port/assets/voxel/trees/"

function Bake.asset_url(commit, rel)
  return Bake.ASSET_BASE .. commit .. "/" .. rel
end

-- A fetcher(rel) -> bytes | nil, err for the generator assets, from
--   opts.http(url) -> bytes | nil, err      (the in-game HTTP path)
--   opts.cache_read(key) -> bytes | nil     (e.g. save-dir e3ds_voxel/cache)
--   opts.cache_write(key, bytes)
-- The cache key is "<commit>/<rel>", so a newer pin never reads stale files.
function Bake.fetcher(opts)
  return function(rel, commit)
    commit = commit or Bake.ASSET_COMMIT
    local key = commit .. "/" .. rel
    if opts.cache_read then
      local hit = opts.cache_read(key)
      if hit then return hit end
    end
    if not opts.http then return nil, "no HTTP and not cached: " .. rel end
    local bytes, err = opts.http(Bake.asset_url(commit, rel))
    if not bytes then return nil, err end
    if opts.cache_write then opts.cache_write(key, bytes) end
    return bytes
  end
end

-- Step 2: the assets into the tree.  fetch(rel, commit) -> bytes | nil, err
function Bake.install_assets(tree, fetch)
  for _, rel in ipairs(Bake.ASSETS) do
    local bytes, err = fetch(rel, Bake.ASSET_COMMIT)
    if not bytes then
      error(("Bake: could not fetch %s (%s)"):format(rel, tostring(err)), 0)
    end
    -- CPython's text mode reads CRLF as LF: store the generators' view
    if rel:match("%.json$") or rel:match("%.h$") then bytes = bytes:gsub("\r\n", "\n") end
    tree:write(rel, bytes)
  end
end

-- ── the steps (voxel.py STEPS, in order) ─────────────────────────────────
Bake.STEPS = {
  { module = "gen_voxel_regions", out = "3ds_port/romfs/voxel/regions.bin", label = "map regions" },
  { module = "gen_voxel_sign_masks", out = "3ds_port/romfs/voxel/signposts.bin", label = "signposts" },
  { module = "gen_voxel_relief", out = "3ds_port/romfs/voxel/relief.bin", label = "terrain relief" },
  { module = "gen_voxel_buildings", out = "3ds_port/romfs/voxel/buildings.bin", label = "buildings" },
}

-- One generator in a fresh Session (its own "process"): module = the
-- generator's name ("gen_voxel_regions"); progress(fraction, label) optional;
-- output(path) -> writer | nil optional (Session:output)
function Bake.run_step(tree, module, progress, output)
  local Session = V.require("bake/Session")
  local S = Session.new(tree, { progress = progress, output = output })
  S.import(module).main()
  return S
end

-- Between steps: give the finished Session's memory back before the next
-- one starts.  JIT traces hold their constants (the modules' tables, hence
-- every memo cache) until flushed: without the flush hundreds of MB of a
-- finished step stay reachable (JIT on only; a no-op with the JIT off).
function Bake.release()
  if jit and jit.status() then jit.flush() end
  collectgarbage("collect")
  collectgarbage("collect")
end

-- ── step 4: layouts.lua (bake.py write_layouts) ──────────────────────────
local function lua_string(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

function Bake.layouts_lua(tree)
  local entries = json.decode(tree:must("data/layouts/layouts.json")).layouts
  local lines = { "-- generated by bake/bake.py from the ROM's own layout table; do not edit", "return {" }
  for i, e in ipairs(entries) do
    if e.primary_tileset ~= nil then
      lines[#lines + 1] = ("  [%d] = { id = %s, w = %d, h = %d, primary = %s, secondary = %s },"):format(
        i, lua_string(e.id or ""), e.width or 0, e.height or 0,
        lua_string(e.primary_tileset or ""), lua_string(e.secondary_tileset or ""))
    end
  end
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n") .. "\n"
end

-- ── the whole bake ───────────────────────────────────────────────────────
-- Bake.run{ rom = bytes, recipe_blob = bytes (lib/bake/recipes/<code>.vtree),
--           inflate = fn, fetch = fn, steps = {names} (default all),
--           progress = fn(fraction, label),
--           open = fn(name) -> writer (optional) }
-- (opts.rom and opts.recipe_blob are cleared: the bake keeps no ROM copy)
-- -> { ["regions.bin"] = bytes, ..., ["layouts.lua"] = text }, tree
--
-- With `open`, the outputs are streamed instead of returned: open(name)
-- ("regions.bin", ..., "layouts.lua") gives an object with :write(chunk)
-- and :close() that raise on failure (BakeThread wraps a love File), each
-- output goes through one in chunks as it is made -- buildings.bin is never
-- one string (gen_voxel_buildings export) -- and the result maps each name
-- to its size in bytes instead.  Every writer is closed before its output's
-- step ends; on an error the ones opened may hold partial files (the caller
-- writes to temporary names and renames once Bake.run returns; BakeThread).
function Bake.run(opts)
  local Tree = V.require("bake/Tree")
  local recipe = V.require("bake/recipe")
  local vtree = V.require("bake/vtree")
  local progress = opts.progress or function() end
  local rom, blob = opts.rom, opts.recipe_blob
  -- memory: the caller's references to the ROM can go (16 MB for the bake)
  opts.rom, opts.recipe_blob = nil, nil
  if #rom < 16 * 1024 * 1024 then
    -- a trimmed dump (rom.py): the cartridge's trailing 0xFF fill cut off
    rom = rom .. string.rep("\255", 16 * 1024 * 1024 - #rom)
  end
  local rcp = recipe.load(blob, opts.inflate)
  local tree = Tree.new()
  progress(0, "Preparing the generators' input tree")
  vtree.build_tree(rom, rcp, tree, function(f) progress(0.1 * f, "Preparing the generators' input tree") end)
  rom, rcp, blob = nil, nil, nil   -- memory: the tree holds what the steps read
  Bake.install_assets(tree, opts.fetch)
  local want = {}
  for _, n in ipairs(opts.steps or { "regions", "signposts", "relief", "buildings" }) do want[n] = true end
  local names = { "regions", "signposts", "relief", "buildings" }
  local out = {}
  -- a writer over opts.open's that counts its bytes (the size returned)
  local function open(name)
    local w = opts.open(name)
    if not w then error("Bake: could not open " .. name .. " for writing", 0) end
    local n, closed = 0, false
    return {
      write = function(_, chunk) n = n + #chunk; w:write(chunk) end,
      close = function()
        if closed then return end
        closed = true
        w:close()
        out[name] = n
      end,
    }
  end
  local function emit(name, bytes)
    if opts.open then
      local w = open(name)
      w:write(bytes)
      w:close()
    else
      out[name] = bytes
    end
  end
  for i, step in ipairs(Bake.STEPS) do
    if want[names[i]] then
      local name = step.out:match("[^/]+$")
      progress(0.1 + 0.9 * (i - 1) / #Bake.STEPS, step.label)
      local output
      if opts.open then
        output = function(path) if path == step.out then return open(name) end end
      end
      Bake.run_step(tree, step.module, function(f, label)
        progress(0.1 + 0.9 * (i - 1 + f) / #Bake.STEPS, label)
      end, output)
      -- a generator that streamed its file left it out of the tree
      local bytes = tree:read(step.out)
      if bytes then
        emit(name, bytes)
      elseif out[name] == nil then
        error("Bake: the generators did not make " .. step.out, 0)
      end
      bytes = nil
      Bake.release()
    end
  end
  emit("layouts.lua", Bake.layouts_lua(tree))
  progress(1, "done")
  return out, tree
end

return Bake
