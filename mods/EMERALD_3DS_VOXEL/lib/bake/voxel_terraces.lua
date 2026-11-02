-- Port of 3ds_port/scripts/voxel_terraces.py: mountains read as the General
-- tileset builds them, whole levels, one tile a level (gen_voxel_relief's
-- main runs apply_file over relief.bin).
--
-- Four files, one module (S.import("voxel_terraces") is the whole of it):
--   voxel_terraces.lua    this: imports gen_voxel_relief (Python's
--                         top-level `import gen_voxel_relief as gr`) and
--                         installs the parts
--   voxel_terraces_a.lua  Python 60-1293 (constants, pixel classes, twin,
--                         Cells, Offsets, runs_of ... settle)
--   voxel_terraces_b.lua  Python 1532-3058 (FIN ... blocks, pieces,
--                         staircases, level_bands ... rough fields)
--   voxel_terraces_c.lua  Python 3059-4950 (ledges, solve, solve_auto,
--                         finish, marks, records, merge, region_ties,
--                         chosen_layouts, apply_file)
-- Not ported (never reached by gen_voxel_relief --output): corner_pixel_top,
-- default_high, corners, piece_cost, lattice, init_of, shape (1294-1531),
-- foot_of, seam_meets, cracks, overlay, main.
-- Each part is `local V, S = ...; return function(M) ... end`; every Python
-- module-level name is M.<same name>.  Shapes: scratch
-- e3ds_port/relief/PLAN.md (cells are pyx.xy numbers; dicts pyx.odict; sets
-- pyx.xyset / pyx.set).

local V, S, M = ...
M = M or {}
S.import("gen_voxel_relief")

local function install(name)
  local ok, inst = pcall(S.import, name)
  if ok then inst(M)
  elseif not tostring(inst):find(name .. ".lua is missing", 1, true) then error(inst, 0) end
end
install("voxel_terraces_a")
install("voxel_terraces_b")
install("voxel_terraces_c")

return M
