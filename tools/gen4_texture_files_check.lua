-- gen4_texture_files_check.lua -- which terrain textures are NAMED but not ON DISK.
--
-- `Assets.image` returns a placeholder for a missing path and says nothing, so a
-- texture that is correctly named, correctly in its set and simply never written
-- produces "some areas draw placeholder tile art" with no error anywhere.  This
-- resolves every path the terrain cache references and reports the misses.
--
--   texlua tools/gen4_texture_files_check.lua [game root]
--
-- IT TAKES A GAME ROOT NOW, and before it did not -- which is why the check
-- suite could never run it.  It resolved `data/generated/gen4_terrain.lua`
-- against the CURRENT DIRECTORY and nothing else, so it only worked when you
-- happened to be standing in a game root; `tools/run_checks.py` has no way to
-- stand anywhere, so this check reported SKIP on every suite run since it was
-- written, and a check that is permanently skipped is a check that does not
-- exist.  Run by hand from a real install it passes 3,693 of 3,693.
--
-- The argument is optional and the old behaviour is the default, so an
-- existing invocation keeps working.
--
-- Exit status is 1 when anything is missing, so it can gate a build; 2 when it
-- could not run, or when NOTHING is present (see below).

local GAME = (arg and arg[1] or "."):gsub("[/\\]+$", "")
-- A caller who passes the data directory itself, or the assets directory, means
-- the install above it -- the same courtesy `gen4_battlescene_check` extends,
-- and for the same reason: those are the two paths a person naturally has to
-- hand.
GAME = GAME:gsub("[/\\]data[/\\]generated$", "")
           :gsub("[/\\]assets[/\\]generated$", "")

local ROOTS = { GAME .. "/", GAME .. "/assets/", "", "assets/", "../", "data/" }

local function exists(path)
  for _, root in ipairs(ROOTS) do
    local f = io.open(root .. path, "rb")
    if f then f:close() return true, root .. path end
  end
  return false
end

local terrain
for _, candidate in ipairs({ GAME .. "/data/generated/gen4_terrain.lua",
                             "data/generated/gen4_terrain.lua" }) do
  local loaded, value = pcall(dofile, candidate)
  if loaded and type(value) == "table" then terrain = value break end
end
if not terrain then
  io.stderr:write("could not load data/generated/gen4_terrain.lua -- pass a "
                  .. "game root (the platinum/ directory) as the first "
                  .. "argument, or run me from one\n")
  os.exit(2)
end

-- Which sets each map uses, so a miss can be reported as "N maps affected"
-- rather than as a set number nobody can place.
local mapsPerSet = {}
for _, def in pairs(terrain.maps or {}) do
  if def.texture then mapsPerSet[def.texture] = (mapsPerSet[def.texture] or 0) + 1 end
end

local sets, checked, missing = 0, 0, 0
local rows = {}
for id, set in pairs(terrain.sets or {}) do
  sets = sets + 1
  local gone, total = {}, 0
  for name, tex in pairs(set.textures or {}) do
    if tex.path then
      total = total + 1
      checked = checked + 1
      if not exists(tex.path) then
        missing = missing + 1
        gone[#gone + 1] = name
      end
    end
  end
  if #gone > 0 then
    table.sort(gone)
    rows[#rows + 1] = { id, #gone, total, mapsPerSet[id] or 0, gone }
  end
end

table.sort(rows, function(a, b) return a[4] > b[4] end)

print(("terrain texture sets: %d   texture files referenced: %d   MISSING: %d (%.1f%%)")
  :format(sets, checked, missing, checked > 0 and 100 * missing / checked or 0))

-- ZERO OF THEM PRESENT IS NOT "EVERYTHING IS BROKEN", IT IS "NO ASSET TREE
-- HERE" -- and the two are worth different exit codes.
--
-- This printed `MISSING: 3693 (100.0%)` against a complete, freshly imported
-- cache whose asset tree simply had not been copied into the container it was
-- run in, and then listed all 74 sets as broken. That reads exactly like a
-- catastrophic extraction fault and is not one: with the 74 texture folders
-- actually present the same run reports 3,693 of 3,693 on disk.
--
-- `gen4_ball_throw_check` had the identical flaw and the identical cause (18
-- of 19 ball sets "broken" against a partial mirror), and was given this guard
-- in pass 166. This is the same guard, for the same reason: a check that
-- cannot tell a missing input from a failing subject will be believed the
-- first time and switched off the second.
--
-- 100% is the tell. A real fault takes out a set or a family, not every
-- single file that every one of the 74 sets refers to.
if checked > 0 and missing == checked then
  print("")
  print(("no terrain textures are present at all (%d of %d referenced files missing) --"):format(missing, checked))
  print("this looks like an install with no asset tree rather than broken art;")
  print("point me at a platinum/ that has assets/generated/gen4/terrain/tex.")
  os.exit(2)
end

if missing == 0 then
  print("every referenced texture is on disk.")
  os.exit(0)
end

print("")
print(("%-6s %-14s %-8s %s"):format("set", "missing/total", "maps", "first few names"))
for _, r in ipairs(rows) do
  local shown = {}
  for i = 1, math.min(#r[5], 6) do shown[i] = r[5][i] end
  print(("%-6s %-14s %-8d %s%s"):format(
    tostring(r[1]), ("%d/%d"):format(r[2], r[3]), r[4],
    table.concat(shown, ", "), (#r[5] > 6) and (" ... +" .. (#r[5] - 6)) or ""))
end

print("")
print("A set with misses draws placeholder art on every map that uses it.")
os.exit(1)
