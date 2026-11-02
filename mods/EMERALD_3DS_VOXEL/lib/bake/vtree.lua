-- emerald3ds_builder/vtree.py: rebuild, from the player's ROM, the files the
-- voxel generators read, into a Tree (lib/bake/Tree.lua).
--
-- * binary inputs come from the recipe's `inputs` entries (ROM copies and
--   LZ77 streams, each checked against its CRC);
-- * layouts.json and every map.json are read back from the ROM's own
--   MapLayout and MapHeader structures, whose offsets the recipe names;
-- * metatiles.h, headers.h and metatile_behaviors.h are reduced to the lines
--   the generators parse.
--
-- Text files are written with '\n' line ends (vtree.py's write_text gives
-- CRLF on Windows only; the generators read both alike).

local V = ...
local json = V.require("bake/json")
local recipe = V.require("bake/recipe")
local py = V.require("bake/py")
local sbyte = string.byte

local vtree = {}

local ROM_BASE = 0x08000000
-- BgEvent kinds 0-4 are signs (read from any side or from one); the others
-- are hidden items and secret bases.
local BG_EVENT_SIGN_LAST = 4

local function u32(rom, off)
  local a, b, c, d = sbyte(rom, off + 1, off + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end

local function ptr(rom, off)
  local value = u32(rom, off)
  if value == 0 then return nil end
  if not (ROM_BASE <= value and value < ROM_BASE + #rom) then
    error(("BuilderError: The ROM does not have the expected structure (bad pointer at %#x)."):format(off), 0)
  end
  return value - ROM_BASE
end

local function read_layout(rom, off, tilesets)
  local v = py.unpack_from("<ii", rom, off)
  local primary = ptr(rom, off + 16)
  local secondary = ptr(rom, off + 20)
  return v[1], v[2], (primary and tilesets[primary]) or "NULL", (secondary and tilesets[secondary]) or "NULL"
end

local function read_map(rom, off, meta, maps_by_group, record)
  local events = ptr(rom, off + 4)
  local connections = ptr(rom, off + 12)
  local layout_id = py.unpack_from("<H", rom, off + 0x12)[1]
  local map_type = sbyte(rom, off + 0x17 + 1)
  local layouts = meta.layouts
  local function keys(t, ...) t[json.KEYS] = { ... }; return t end
  record.layout = (layout_id > 0 and layout_id <= #layouts) and layouts[layout_id].id or "LAYOUT_NONE"
  record.map_type = meta.map_types[tostring(map_type)] or "MAP_TYPE_NONE"
  local warps_out, bgs_out, conns_out = json.array({}), json.array({}), json.array({})
  record.warp_events, record.bg_events, record.connections = warps_out, bgs_out, conns_out
  if events ~= nil then
    local warp_count = sbyte(rom, events + 1 + 1)
    local warps = ptr(rom, events + 8)
    for i = 0, warp_count - 1 do
      local w = py.unpack_from("<hhBBBB", rom, warps + i * 8)
      warps_out[#warps_out + 1] = keys({
        x = w[1], y = w[2], elevation = w[3],
        dest_map = maps_by_group[w[6] * 256 + w[5]] or "MAP_NONE",
        dest_warp_id = w[4],
      }, "x", "y", "elevation", "dest_map", "dest_warp_id")
    end
    local bg_count = sbyte(rom, events + 3 + 1)
    local bgs = ptr(rom, events + 16)
    for i = 0, bg_count - 1 do
      local b = py.unpack_from("<HHBB", rom, bgs + i * 12)
      if b[4] <= BG_EVENT_SIGN_LAST then
        bgs_out[#bgs_out + 1] = keys({ type = "sign", x = b[1], y = b[2], elevation = b[3] },
          "type", "x", "y", "elevation")
      end
    end
  end
  if connections ~= nil then
    local count = py.unpack_from("<i", rom, connections)[1]
    local tbl = ptr(rom, connections + 4)
    for i = 0, count - 1 do
      local c = py.unpack_from("<B3xiBB2x", rom, tbl + i * 12)
      conns_out[#conns_out + 1] = keys({
        map = maps_by_group[c[3] * 256 + c[4]] or "MAP_NONE",
        offset = c[2],
        direction = meta.connection_directions[tostring(c[1])] or tostring(c[1]),
      }, "map", "offset", "direction")
    end
  end
end

-- vtree.build_tree(rom, rcp, tree, progress): rcp from recipe.load;
-- progress(fraction) optional; yield() optional, called between files so a
-- coroutine/thread can report progress.
function vtree.build_tree(rom, rcp, tree, progress)
  local meta = rcp.vtree
  if not meta or not rcp.inputs or #rcp.inputs == 0 then
    error("BuilderError: This release's recipe does not describe the voxel inputs.", 0)
  end
  local total = #rcp.inputs
  for i, entry in ipairs(rcp.inputs) do
    local data = recipe.build_entry(entry, rom, rcp.literals, rcp.bitmaps)
    tree:write(entry.path, data)
    if progress and (i - 1) % 50 == 0 then progress((i - 1) / total) end
  end

  -- {off: name for name, off in tilesets.items()}: later names win
  local tilesets = {}
  for _, pair in ipairs(meta.tilesets) do tilesets[pair[2]] = pair[1] end
  local layouts = json.array({})
  for _, item in ipairs(meta.layouts) do
    if item.name == nil then
      layouts[#layouts + 1] = json.object("id", item.id)
    else
      local w, h, p, s = read_layout(rom, item.rom, tilesets)
      layouts[#layouts + 1] = json.object("id", item.id, "name", item.name, "width", w, "height", h,
        "primary_tileset", p, "secondary_tileset", s,
        "border_filepath", item.border_filepath, "blockdata_filepath", item.blockdata_filepath)
    end
  end
  tree:write("data/layouts/layouts.json", json.encode(
    json.object("layouts_table_label", meta.layouts_table_label, "layouts", layouts), 2))

  local maps_by_group = {}
  for _, m in ipairs(meta.maps) do maps_by_group[m.group * 256 + m.num] = m.id end
  for _, item in ipairs(meta.maps) do
    local record = { id = item.id, name = item.name }
    record[json.KEYS] = { "id", "name", "layout", "map_type", "warp_events", "bg_events", "connections" }
    read_map(rom, item.rom, meta, maps_by_group, record)
    tree:write("data/maps/" .. item.folder .. "/map.json", json.encode(record, 2))
  end

  local lines = {}
  for _, nm in ipairs(meta.metatiles_h) do
    lines[#lines + 1] = ('const u16 %s[] = INCBIN_U16("%s");\n'):format(nm[1], nm[2])
  end
  tree:write("src/data/tilesets/metatiles.h", table.concat(lines))
  lines = {}
  for _, nm in ipairs(meta.headers_h) do
    lines[#lines + 1] = ("const struct Tileset %s =\n{\n    .metatiles = %s,\n};\n\n"):format(nm[1], nm[2])
  end
  tree:write("src/data/tilesets/headers.h", table.concat(lines))
  local behaviors = meta.metatile_behaviors
  if not behaviors or #behaviors == 0 then
    error("BuilderError: This release's recipe does not name the metatile behaviours.", 0)
  end
  lines = { "enum {\n" }
  for _, nv in ipairs(behaviors) do lines[#lines + 1] = ("    %s = %d,\n"):format(nv[1], nv[2]) end
  lines[#lines + 1] = "};\n"
  tree:write("include/constants/metatile_behaviors.h", table.concat(lines))
  if progress then progress(1.0) end
end

return vtree
