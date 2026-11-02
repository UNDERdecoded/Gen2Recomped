-- Port of 3ds_port/scripts/gen_voxel_regions.py: what every cell of every
-- layout is, for the console's signposts.
--
-- OUTPUT  3ds_port/romfs/voxel/regions.bin  (VXR5)

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local tree = S.tree
local voxel_cells = S.import("voxel_cells")

local PORT = "3ds_port"

-- VOXEL_ROLE_* from voxel_regions.h, so the two never drift apart
function M.load_roles_enum(header)
  local text = tree:must(header)
  local out, any = {}, false
  for name, value in text:gmatch("#define%s+VOXEL_ROLE_([%w_]+)%s+(%d+)") do
    if name ~= "COUNT" then
      out[name:lower()] = tonumber(value)
      any = true
    end
  end
  if not any then error("gen_voxel_regions: no VOXEL_ROLE_* in " .. header, 0) end
  return out
end

-- the role of every cell of the layout, row major, as a string of bytes
function M.roles_of(layout, roles_enum)
  local out = {}
  local schar = string.char
  for y = 0, layout.h - 1 do
    for x = 0, layout.w - 1 do
      out[#out + 1] = schar(roles_enum[layout:role_at(x, y)])
    end
  end
  return table.concat(out)
end

function M.main()
  local roles_enum = M.load_roles_enum(PORT .. "/src/voxel/voxel_regions.h")
  local events = voxel_cells.MapEvents()
  local layouts = voxel_cells.load_layouts()

  local entries, blobs, skipped = {}, {}, 0
  local payload = 0
  local nl = #layouts
  for index, entry in ipairs(layouts) do
    if index % 16 == 0 then S:progress(index / nl, "map regions") end
    if not tree:isfile(entry.blockdata_filepath) then
      skipped = skipped + 1
    else
      local layout = voxel_cells.Layout(entry, events)
      if #layout.blocks < layout.w * layout.h then
        skipped = skipped + 1
      else
        local role_bytes = M.roles_of(layout, roles_enum)
        entries[#entries + 1] = { index, layout.w, layout.h, payload }
        blobs[#blobs + 1] = role_bytes
        payload = payload + #role_bytes
      end
    end
  end

  local parts = { "VXR5", py.pack("<HH", #entries, 0) }
  local table_bytes = 4 + 4 + #entries * 12
  for _, e in ipairs(entries) do
    parts[#parts + 1] = py.pack("<HHHHI", e[1], e[2], e[3], 0, table_bytes + e[4])
  end
  for _, b in ipairs(blobs) do parts[#parts + 1] = b end
  tree:write(PORT .. "/romfs/voxel/regions.bin", table.concat(parts))
  if V.log then V.log("gen_voxel_regions: %d layouts, %d skipped", #entries, skipped) end
end

return M
