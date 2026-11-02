-- Port of 3ds_port/scripts/voxel_terraces.py lines 60-1293: the constants,
-- pixel classes, twins, drawn copies, class Cells (the canvas every later
-- part reads), Offsets, runs_of, terraces, steps, solve_levels,
-- upper_levels, unknown_levels, settle.  (1294-1531 is never reached.)
-- Installed into voxel_terraces' M by voxel_terraces.lua.
--
-- Lua shapes (scratch e3ds_port/relief/PLAN.md, "TA"):
--   * a cell (x, y) is the number pyx.xy(x, y); terrace ids are cells too
--   * constants: GROUND, TOP, ROCK, UNKNOWN = "G", "T", "R", "?";
--     TOP_COLOURS, FACE_COLOURS, FLECK: plain {[packed rgb] = true};
--     BAND_WEST, BAND_EAST, BOULDER_FOOT, BOULDER_HEAD, LOOSE, CARVED_STEPS,
--     UPPER_END, LOWER_END, MOUNTAIN, ON_TOP (= gr.BOULDER): plain
--     {[m] = true}, each with <NAME>_LIST (sorted array); HEADS: plain
--     {[m] = "W" | "E"}, HEADS_LIST sorted; WORLD = {"world"} (Python's
--     ("world",): ONE table, compare by identity), MAX_FALL, ANCHOR_MIN,
--     LEVEL, N, TWIN_MATCH, HEAD_MATCH
--   * pixel_classes(art, m) -> cls[y + 1][x + 1] of "T" / "F" / "G"
--     (cached per (primary, secondary, m, gr.reading_key(art)): SHARED,
--     read only); M.class_counts(cls) -> {T = n, F = n, G4 = "G" in rows
--     0-3, F2 = "F" in rows 2-15} (cached)
--   * rim_pixels(art, m) -> int; twin(art, m) -> m; drawn_copy(art, m) -> m
--   * Cells (py.class; M.Cells(members), members an array of {lid, ox, oy}):
--       members      array of {lid, ox, oy} (a copy of the argument)
--       id           members[1][1]
--       arts         plain lid -> art (gr.terrace_art)
--       roles_of     plain lid -> voxel_cells Layout (gr.open_roles)
--       src          pyx.odict xy -> {lid, x, y} (x, y: the layout's cell)
--       kind         pyx.odict xy -> "G" | "T" | "R" | "?" (src's order)
--       band         pyx.odict xy -> "W" | "E"
--       jumps        pyx.odict xy -> array of {dx, dy} (a copy)
--       prop_of      pyx.odict xy -> {lid, k} (k 0-based, as Python; compare
--                    the fields, not the table)
--       models       what M.modelled(members) returns (pyx.odict xy -> xy;
--                    an empty pyx.odict while M.modelled is missing)
--       rim, ledges, keep, props, walked_tops, bridges, falls, puddles,
--       lone_bridge, cheeks, rough, wide_boulder
--                    pyx.xyset (CPython's order: built by the same adds and
--                    discards as Python's)
--       bridge_codes plain {[behaviour] = true}
--       mud          number or nil (MB_MUDDY_SLOPE)
--       xs, ys       {start = a, stop = b} (Python's range(a, b))
--       tree_ground  pyx.odict xy -> terrace id, set by terraces()
--       _over_water  plain xy -> boolean; _drawn_on plain string -> "T"|"F"|"G"
--     methods (cells are xy; booleans are true/false): c:art(cell),
--     is_stair, on_top, at_edge, metatile, role_id, role, water, _four(cell)
--     -> array of 4 xy, _lower(cell) -> string, crown, muddy, drawn_on,
--     tree_on_rock, walked, house; static M.Cells._top_tile(art, m),
--     M.Cells._in_face(art, x, y, both)
--   * Offsets (py.class): parent/off pyx.odict; off:find(a) -> root, offset
--     (TWO values); off:join(a, b, d) -> boolean
--   * runs_of(c) -> array of {direction, hi, cells, lo}: direction is
--     Python's STRING "S" | "E" | "W" (PLAN.md's "{dx, dy}" was a slip),
--     hi/lo xy, cells an array of xy
--   * terraces(c, runs) -> comp: pyx.odict xy -> terrace id (xy); sets
--     c.tree_ground
--   * steps(c, cells, direction) -> out (array of ints), n (two values)
--   * solve_levels(c, comp, runs, reference, meets, blocks_out) -> level
--     (pyx.odict terrace -> level), dropped (array of {{a, b, k}, n}) (two
--     values); reference: pyx.odict xy -> height or nil; meets: pyx.odict
--     xy -> {map across, meets (boolean), edge, cell across} or nil;
--     blocks_out: pyx.odict filled in place (terrace -> root: a terrace id,
--     or M.WORLD) or nil
--   * upper_levels(c, comp, level, runs) -> U: pyx.odict xy -> level
--   * unknown_levels(c, comp, level, U) -> pyx.odict xy -> level (calls
--     M.tree_card / M.small_trunk: TB's)
--   * settle(c, U, flat, fixed) -> U (mutated in place); flat pyx.odict;
--     fixed a pyx.xyset, a pyx.odict or a plain table keyed xy (membership)

local V, S = ...
local py = V.require("bake/py")
local pyx = V.require("bake/gen_voxel_relief_pyx")

return function(M)
  local gr = S.import("gen_voxel_relief")
  local vb = S.import("voxel_building")
  local vc = S.import("voxel_cells")
  local voxel_props = S.import("voxel_props")
  local xy, unxy = pyx.xy, pyx.unxy
  local floor = math.floor
  local T = {}          -- helpers (keeps the installer's upvalues few)

  local function set_of(list)
    local t = {}
    for _, v in ipairs(list) do t[v] = true end
    return t
  end
  local function sorted_keys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
  end
  local function const_set(name, list)
    M[name] = set_of(list)
    M[name .. "_LIST"] = sorted_keys(M[name])
  end

  -- ── constants (py 67-117) ──────────────────────────────────────────────
  M.LEVEL = 16
  M.N = 4
  M.TOP_COLOURS = gr._union(gr.ROCK_TOP, gr.ROCK_RIM)
  M.FACE_COLOURS = gr.ROCK_FACE
  M.FLECK = gr.ROCK_FLECK
  const_set("BAND_WEST", { 0x070, 0x073, 0x088, 0x06b, 0x080, 0x083, 0x068, 0x172, 0x175, 0x177, 0x17a })
  const_set("BAND_EAST", { 0x072, 0x075, 0x0a2, 0x08a, 0x06d, 0x082, 0x084, 0x06a, 0x174, 0x176, 0x17c, 0x0a4 })
  M.HEADS = { [0x068] = "W", [0x083] = "W", [0x080] = "W", [0x06a] = "E", [0x084] = "E", [0x082] = "E" }
  M.HEADS_LIST = sorted_keys(M.HEADS)
  M.ON_TOP = gr.BOULDER
  M.ON_TOP_LIST = sorted_keys(M.ON_TOP)
  const_set("BOULDER_FOOT", { 0x09b, 0x09c })
  const_set("BOULDER_HEAD", { 0x093, 0x094 })
  const_set("LOOSE", { 0x0df, 0x0e0, 0x0e1, 0x0e2 })
  const_set("CARVED_STEPS", { 0x0e8, 0x0e9, 0x0ea, 0x0eb })
  const_set("UPPER_END", { 0x074, 0x089 })
  const_set("LOWER_END", { 0x07d, 0x07b, 0x078, 0x092, 0x090 })
  do
    local m = {}
    for v = 0x064, 0x0bf do m[v] = true end
    for v = 0x172, 0x192 do m[v] = true end
    for _, v in ipairs({ 0x1a0, 0x1a8, 0x1b0, 0x1f0, 0x1f1 }) do m[v] = true end
    for v in pairs(gr.FACE_SOUTH) do m[v] = true end
    for v in pairs(gr.BOULDER) do m[v] = true end
    for v in pairs(gr.DIRT) do m[v] = nil end
    M.MOUNTAIN = m
    M.MOUNTAIN_LIST = sorted_keys(m)
  end
  M.GROUND, M.TOP, M.ROCK, M.UNKNOWN = "G", "T", "R", "?"
  M.WORLD = { "world" }
  M.MAX_FALL = 3 * 16
  M.ANCHOR_MIN = 12
  M.TWIN_MATCH = 0.85
  M.HEAD_MATCH = 0.6

  local GROUND, TOP, ROCK, UNKNOWN, LEVEL = "G", "T", "R", "?", 16

  -- ── per-tile caches, keyed by the art's (primary, secondary, reading) ──
  M._CLASSES, M._TWINS, M._COPIES = {}, {}, {}
  T.AK = setmetatable({}, { __mode = "k" })
  T.RGB, T.RGB0, T.STR, T.STR0, T.RIM, T.CROWN, T.ROCKSIG = {}, {}, {}, {}, {}, {}, {}
  T.COUNTS = setmetatable({}, { __mode = "k" })

  function T.akey(art)
    local k = T.AK[art]
    if k == nil then
      k = art.primary .. "|" .. tostring(art.secondary) .. "|" .. gr.reading_key(art)
      T.AK[art] = k
    end
    return k
  end
  function T.sub(cache, art)
    local ak = T.akey(art)
    local t = cache[ak]
    if t == nil then t = {}; cache[ak] = t end
    return t
  end
  -- the RGB pixels of cell_image(m[, layers]): 0-based y * 16 + x, packed
  function T.rgb(art, m, low)
    local t = T.sub(low and T.RGB0 or T.RGB, art)
    local d = t[m]
    if d == nil then
      local img = low and art:cell_image(m, { 0 }) or art:cell_image(m)
      d = {}
      for y = 0, 15 do
        for x = 0, 15 do d[y * 16 + x] = img:getrgb(x, y) end
      end
      t[m] = d
    end
    return d
  end
  -- .convert("RGB").tobytes() as a comparable string
  function T.str(art, m, low)
    local t = T.sub(low and T.STR0 or T.STR, art)
    local s = t[m]
    if s == nil then
      local d = T.rgb(art, m, low)
      local parts = {}
      for i = 0, 255 do parts[i + 1] = d[i] end
      s = table.concat(parts, ",")
      t[m] = s
    end
    return s
  end

  -- ── 1. cells ───────────────────────────────────────────────────────────

  -- memory (not in Python): the cached grids share equal rows (rows are
  -- read only once cached; only pixel_classes writes them, before that)
  T.ROWS = {}
  local function intern_rows(cls)
    local rows = T.ROWS
    for y = 1, 16 do
      local k = table.concat(cls[y])
      local r = rows[k]
      if r == nil then rows[k] = cls[y] else cls[y] = r end
    end
    return cls
  end

  function M.pixel_classes(art, m)
    local t = T.sub(M._CLASSES, art)
    local cls = t[m]
    if cls ~= nil then return cls end
    local d = T.rgb(art, m)
    cls = {}
    for y = 1, 16 do
      local row = {}
      for x = 1, 16 do row[x] = "G" end
      cls[y] = row
    end
    if m >= 0x200 then
      local c0, one = d[0], true
      for i = 1, 255 do
        if d[i] ~= c0 then one = false; break end
      end
      if one then
        if M.FACE_COLOURS[c0] then
          for y = 1, 16 do for x = 1, 16 do cls[y][x] = "T" end end
        end
        t[m] = intern_rows(cls)
        return cls
      end
    end
    local top, face, fleck = M.TOP_COLOURS, M.FACE_COLOURS, M.FLECK
    local flecks, isfleck = {}, {}
    for y = 0, 15 do
      for x = 0, 15 do
        local c = d[y * 16 + x]
        if top[c] then cls[y + 1][x + 1] = "T"
        elseif face[c] then cls[y + 1][x + 1] = "F"
        elseif fleck[c] then
          flecks[#flecks + 1] = y * 16 + x
          isfleck[y * 16 + x] = true
        end
      end
    end
    for _, p in ipairs(flecks) do
      local x, y = p % 16, floor(p / 16)
      local nT, nF, first = 0, 0, nil
      for ny = math.max(0, y - 1), math.min(16, y + 2) - 1 do
        for nx = math.max(0, x - 1), math.min(16, x + 2) - 1 do
          if not isfleck[ny * 16 + nx] then
            local v = cls[ny + 1][nx + 1]
            if v == "T" then
              nT = nT + 1
              if first == nil then first = "T" end
            elseif v == "F" then
              nF = nF + 1
              if first == nil then first = "F" end
            end
          end
        end
      end
      local r
      if nT == 0 and nF == 0 then r = "T"
      elseif nT > nF then r = "T"
      elseif nF > nT then r = "F"
      else r = first end
      cls[y + 1][x + 1] = r
    end
    t[m] = intern_rows(cls)
    return cls
  end

  -- counts over a pixel_classes grid (cached by the grid)
  function M.class_counts(cls)
    local n = T.COUNTS[cls]
    if n == nil then
      n = { T = 0, F = 0, G4 = 0, F2 = 0 }
      for y = 1, 16 do
        local row = cls[y]
        for x = 1, 16 do
          local v = row[x]
          if v == "T" then n.T = n.T + 1
          elseif v == "F" then
            n.F = n.F + 1
            if y >= 3 then n.F2 = n.F2 + 1 end
          elseif y <= 4 then n.G4 = n.G4 + 1 end
        end
      end
      T.COUNTS[cls] = n
    end
    return n
  end
  local counts = M.class_counts

  function M.rim_pixels(art, m)
    local t = T.sub(T.RIM, art)
    local n = t[m]
    if n == nil then
      local d = T.rgb(art, m)
      local rim = gr.ROCK_RIM
      n = 0
      for i = 0, 6 * 16 - 1 do
        if rim[d[i]] then n = n + 1 end
      end
      t[m] = n
    end
    return n
  end

  function M.twin(art, m)
    if m < 0x200 then return m end
    local t = T.sub(M._TWINS, art)
    local hit = t[m]
    if hit ~= nil then return hit end
    local mine = M.pixel_classes(art, m)
    local cm = counts(mine)
    local nrock = cm.T + cm.F
    local best, score = m, 0.0
    local general = art.primary == "gTileset_General"
    local exact
    if general then
      local drawing = T.str(art, m)
      for _, r in ipairs(M.MOUNTAIN_LIST) do
        if r < 0x200 and T.str(art, r) == drawing then exact = r; break end
      end
    end
    if exact ~= nil and general then
      best, score = exact, 1.0
    elseif nrock >= 64 and general then
      local img = T.rgb(art, m)
      local far
      for _, r in ipairs(M.MOUNTAIN_LIST) do
        if r < 0x200 then
          local theirs = M.pixel_classes(art, r)
          local nboth, nsame = 0, 0
          for y = 1, 16 do
            local tr, mr = theirs[y], mine[y]
            for x = 1, 16 do
              local a, b = tr[x], mr[x]
              if a ~= "G" or b ~= "G" then
                nboth = nboth + 1
                if a == b then nsame = nsame + 1 end
              end
            end
          end
          local same = nsame / nboth
          if not (same < score or same < M.TWIN_MATCH) then
            local o = T.rgb(art, r)
            local d = 0
            for i = 0, 255 do
              local p, q = img[i], o[i]
              d = d + math.abs(floor(p / 65536) - floor(q / 65536))
                + math.abs(floor(p / 256) % 256 - floor(q / 256) % 256) + math.abs(p % 256 - q % 256)
            end
            if same > score or d < far then best, score, far = r, same, d end
          end
        end
      end
    end
    if best == m and py.isinstance(art, gr.AliasArt) then
      for _, r in ipairs(M.HEADS_LIST) do
        local cls = M.pixel_classes(art, r)
        local inter, uni = 0, 0
        for y = 1, 16 do
          for x = 1, 16 do
            local a, b = mine[y][x] == "F", cls[y][x] == "F"
            if a and b then inter = inter + 1 end
            if a or b then uni = uni + 1 end
          end
        end
        if uni == 0 then uni = 1 end
        local same = inter / uni
        if same > score and same >= M.HEAD_MATCH then best, score = r, same end
      end
    end
    t[m] = best
    return best
  end

  -- {(x, y): rgb} of a tile's rock pixels, as a comparable string, and its size
  function T.rock_sig(art, m)
    local t = T.sub(T.ROCKSIG, art)
    local s = t[m]
    if s == nil then
      local d, cls = T.rgb(art, m), M.pixel_classes(art, m)
      local parts = {}
      for y = 0, 15 do
        for x = 0, 15 do
          if cls[y + 1][x + 1] ~= "G" then parts[#parts + 1] = (y * 16 + x) .. ":" .. d[y * 16 + x] end
        end
      end
      s = { table.concat(parts, ","), #parts }
      t[m] = s
    end
    return s
  end

  function M.drawn_copy(art, m)
    if m >= 0x200 or M.MOUNTAIN[m] or art.primary ~= "gTileset_General" then return m end
    local t = T.sub(M._COPIES, art)
    local hit = t[m]
    if hit ~= nil then return hit end
    local mine = T.rock_sig(art, m)
    local res = m
    if mine[2] >= 64 then
      for _, r in ipairs(M.MOUNTAIN_LIST) do
        if r < 0x200 and T.rock_sig(art, r)[1] == mine[1] then res = r; break end
      end
    end
    t[m] = res
    return res
  end

  -- ── class Cells ────────────────────────────────────────────────────────

  local Cells = py.class("Cells")
  M.Cells = Cells

  -- set((sx + i) // 2, (sy + j) // 2 ...) of voxel_props.cells_of, in its order
  function T.cells_of(name, sx, sy)
    local grid = voxel_props.OBJECTS[name].grid
    local s = pyx.xyset()
    local gw = #grid[1]
    for j = 1, #grid do
      for i = 1, gw do
        if grid[j][i] ~= false and grid[j][i] ~= nil then
          s:add(xy(floor((sx + i - 1) / 2), floor((sy + j - 1) / 2)))
        end
      end
    end
    return s
  end

  function Cells:__init(members)
    local mem = {}
    for i, m in ipairs(members) do mem[i] = m end
    self.members = mem
    self.id = mem[1][1]
    self.arts, self.roles_of = {}, {}
    self.src = pyx.odict()
    self.kind, self.band, self.rim = pyx.odict(), pyx.odict(), pyx.xyset()
    self.ledges, self.keep = pyx.xyset(), pyx.xyset()
    self.jumps = pyx.odict()
    self.props = pyx.xyset()
    self.prop_of = pyx.odict()
    self.walked_tops = pyx.xyset()
    self.models = M.modelled and M.modelled(self.members) or pyx.odict()
    self._over_water = {}
    self._drawn_on = {}
    local MB = vc.behaviours()
    local berry = MB.MB_BERRY_TREE_SOIL
    local codes = {}
    for k, v in pairs(MB) do
      if k:sub(1, 14) == "MB_BRIDGE_OVER" then codes[v] = true end
    end
    self.bridge_codes = codes
    self.bridges = pyx.xyset()
    local falls = MB.MB_WATERFALL
    self.falls = pyx.xyset()
    local puddle = MB.MB_PUDDLE
    self.puddles = pyx.xyset()
    self.mud = MB.MB_MUDDY_SLOPE
    local src, kind = self.src, self.kind
    local layouts = vb._layouts_json()
    for _, member in ipairs(mem) do
      local lid, ox, oy = member[1], member[2], member[3]
      local art = gr.terrace_art(lid)
      self.arts[lid] = art
      local roles = gr.open_roles(lid)
      self.roles_of[lid] = roles
      local ledges = gr.ledge_cells(roles)
      local entry
      for _, e in ipairs(layouts) do
        if e.id == lid then entry = e; break end
      end
      if entry == nil then error("StopIteration: no layout " .. tostring(lid)) end
      local props = voxel_props.cells_in(entry)
      for k, f in ipairs(voxel_props.find(entry)) do
        for p in T.cells_of(f[1], f[2], f[3]):iter() do
          local px, py_ = unxy(p)
          self.prop_of:set(xy(px + ox, py_ + oy), { lid, k - 1 })
        end
      end
      for y = 0, art.h - 1 do
        for x = 0, art.w - 1 do
          local cell = xy(x + ox, y + oy)
          if not src:has(cell) then
            src:set(cell, { lid, x, y })
            local m = art:metatile(x, y)
            local lk = xy(x, y)
            local isledge = ledges:has(lk)
            if isledge then
              self.ledges:add(cell)
              local copy = {}
              for i, d in ipairs(ledges:get(lk)) do copy[i] = d end
              self.jumps:set(cell, copy)
            end
            local beh = roles:behaviour(x, y)
            if codes[beh] then self.bridges:add(cell) end
            if beh == falls then self.falls:add(cell) end
            if beh == puddle then self.puddles:add(cell) end
            if isledge or beh == berry or gr.DIRT[m] then self.keep:add(cell) end
            self:_read(cell, art, roles, m, isledge, props[py.key(x, y)] ~= nil)
            if self.keep:has(cell) and kind:get(cell) == ROCK then
              kind:set(cell, GROUND)
              if self.band:has(cell) then self.band:del(cell) end
              self.rim:discard(cell)
            end
          end
        end
      end
    end
    -- a walkway of treads across the water: a deck
    self.lone_bridge = pyx.xyset()
    local keys = kind:keys()
    table.sort(keys)
    for _, cell in ipairs(keys) do
      if self:role(cell) == "stair" and not self.bridges:has(cell) then
        local x, y = unxy(cell)
        local reach = {}
        for _, side in ipairs({ -1, 1 }) do
          for d = 1, 3 do
            local n = xy(x + side * d, y)
            if self:water(n) then reach[side] = d; break end
            if not src:has(n) then break end
            local r = self:role(n)
            if r ~= "floor" and r ~= "stair" then break end
          end
        end
        if reach[-1] and reach[1] then
          for _, side in ipairs({ -1, 1 }) do
            for k = 0, reach[side] - 1 do
              local n = xy(x + side * k, y)
              self.bridges:add(n)
              kind:set(n, GROUND)
              if self.band:has(n) then self.band:del(n) end
            end
          end
        end
      end
    end
    local lone = pyx.xyset()
    for b in self.bridges:iter() do
      local x, y = unxy(b)
      if not self.bridges:has(xy(x - 1, y)) and not self.bridges:has(xy(x + 1, y)) then lone:add(b) end
    end
    self.lone_bridge = lone
    self.bridges:isub(lone)
    self.cheeks = pyx.xyset()
    self.rough = pyx.xyset()
    -- the cheeks of stairs climbing a face
    local pairs_ = {}
    for cell, k in kind:items() do pairs_[#pairs_ + 1] = { cell, k } end
    for _, ck in ipairs(pairs_) do
      local cell, k = ck[1], ck[2]
      if k == GROUND and self:role(cell) ~= "floor" then
        local x, y = unxy(cell)
        local hit = false
        for _, n in ipairs({ xy(x - 1, y), xy(x + 1, y) }) do
          if kind:get(n) == ROCK and self:is_stair(n) then hit = true; break end
        end
        if hit then
          local n = counts(M.pixel_classes(self:art(cell), self:metatile(cell)))
          if n.F + n.T >= 0.4 * 256 then
            kind:set(cell, ROCK)
            self.cheeks:add(cell)
          end
        end
      end
    end
    -- a boulder drawn wide: one with the terrace it stands in
    self.wide_boulder = pyx.xyset()
    local BH, BF = M.BOULDER_HEAD, M.BOULDER_FOOT
    for cell in kind:items() do
      if self:metatile(cell) == 0x093 then
        local x, y = unxy(cell)
        local e = x + 1
        while src:has(xy(e, y)) do
          local mt = self:metatile(xy(e, y))
          if BH[mt] or BF[mt] then break end
          e = e + 1
        end
        local ok = e ~= x + 1
        if ok then
          for _, cm in ipairs({ { xy(e, y), 0x094 }, { xy(x, y + 1), 0x09b }, { xy(e, y + 1), 0x09c } }) do
            if not src:has(cm[1]) or self:metatile(cm[1]) ~= cm[2] then ok = false; break end
          end
        end
        if ok then
          for i = x + 1, e - 1 do
            for _, j in ipairs({ y, y + 1 }) do
              local k = kind:get(xy(i, j))
              if k ~= TOP and k ~= ROCK then ok = false end
            end
          end
          if ok then
            local whole = {}
            for i = x, e do
              for _, j in ipairs({ y, y + 1 }) do whole[#whole + 1] = xy(i, j) end
            end
            for _, c in ipairs(whole) do
              kind:set(c, TOP)
              self.rim:discard(c)
            end
            self.wide_boulder:update(whole)
          end
        end
      end
    end
    local x0, x1, y0, y1
    for cell in src:items() do
      local x, y = unxy(cell)
      if x0 == nil or x < x0 then x0 = x end
      if x1 == nil or x > x1 then x1 = x end
      if y0 == nil or y < y0 then y0 = y end
      if y1 == nil or y > y1 then y1 = y end
    end
    self.xs = { start = x0, stop = x1 + 1 }
    self.ys = { start = y0, stop = y1 + 1 }
  end

  function Cells:_read(cell, art, roles, m, ledge, prop)
    local s = self.src:get(cell)
    local lx, ly = s[2], s[3]
    local MOUNTAIN = M.MOUNTAIN
    local cls = M.pixel_classes(art, m)
    local function rock_beside()
      for _, nx in ipairs({ lx - 1, lx + 1 }) do
        if 0 <= nx and nx < art.w then
          local n = counts(M.pixel_classes(art, art:metatile(nx, ly)))
          if n.F + n.T >= 128 then return true end
        end
      end
      return false
    end
    local own = m
    if not (m >= 0x200 and gr.is_warp(roles, lx, ly)) or rock_beside() then
      m = M.twin(art, m)
    end
    local cn = counts(cls)
    local t = cn.T / 256.0
    local f = cn.F / 256.0
    local role = roles:role_at(lx, ly)
    if role == "water" and roles:blocked(lx, ly) and M.drawn_copy(art, m) ~= m then
      m, role = M.drawn_copy(art, m), "cliff"
    end
    local aliased = py.isinstance(art, gr.AliasArt)
    local alien = aliased and m >= vb.NUM_PRIMARY and not MOUNTAIN[m]
    if aliased and own >= vb.NUM_PRIMARY and role == "floor" then
      alien = true
      if MOUNTAIN[m] and f < 0.08 and t >= 0.45 then
        self.walked_tops:add(cell)
      elseif f == 0 then
        local all = true
        for x = 1, 16 do
          if cls[1][x] ~= "T" then all = false; break end
        end
        if all then self.walked_tops:add(cell) end
      end
    end
    local tree = role == "tree" and not (MOUNTAIN[m] and t + f >= 0.25)
    if prop then self.props:add(cell) end
    local k
    local warp = gr.is_warp(roles, lx, ly)
    if tree or prop or M.LOOSE[m] then
      k = UNKNOWN
    elseif M.HEADS[m] and not ledge and ly + 1 < art.h and Cells._top_tile(art, art:metatile(lx, ly + 1))
        and not (aliased and M.rim_pixels(art, art:metatile(lx, ly + 1)) >= 3) then
      k = TOP
    elseif (M.BAND_WEST[m] or M.BAND_EAST[m]) and not ledge then
      k = ROCK
      self.band:set(cell, M.BAND_WEST[m] and "W" or "E")
    elseif ledge or role == "water" or role == "ledge" or self.bridges:has(cell) then
      k = GROUND
    elseif (role == "stair" or roles:behaviour(lx, ly) == self.mud
            or (role == "floor" and M.CARVED_STEPS[art:metatile(lx, ly)]))
        and Cells._in_face(art, lx, ly) then
      k = ROCK
    elseif role == "floor" and warp and Cells._in_face(art, lx, ly, true) then
      k = ROCK
    elseif role == "floor" and MOUNTAIN[m] and f >= 0.5 and not alien then
      k = warp and ROCK or TOP
    elseif role == "floor" and MOUNTAIN[m] and f < 0.08 and t >= 0.45 and not alien then
      k = TOP
    elseif role == "wall" and not MOUNTAIN[m] and t + f < 0.9 and cn.G4 <= 4 then
      k = UNKNOWN
    elseif role == "floor" or role == "stair" or role == "signpost" or (not MOUNTAIN[m] and t + f < 0.9) or alien then
      k = GROUND
    elseif M.BOULDER_FOOT[m] and ly > 0
        and (function()
          local tw = M.twin(art, art:metatile(lx, ly - 1))
          return M.BAND_WEST[tw] or M.BAND_EAST[tw]
        end)() then
      k = ROCK
    elseif M.ON_TOP[m] then
      k = TOP
    elseif t + f < 0.25 then
      k = GROUND
    elseif cn.F2 < 0.08 * 256 and t >= 0.45 then
      k = TOP
    else
      k = ROCK
    end
    self.kind:set(cell, k)
    if k == TOP or k == ROCK or (self.walked_tops:has(cell) and MOUNTAIN[m]) then
      if M.rim_pixels(art, m) >= 3 or cn.G4 >= 12 then self.rim:add(cell) end
    end
  end

  function Cells:art(cell)
    return self.arts[self.src:get(cell)[1]]
  end

  function Cells:is_stair(cell)
    return self:role(cell) == "stair" or (self.kind:get(cell) == ROCK and M.CARVED_STEPS[self:metatile(cell)] == true)
  end

  function Cells:on_top(cell)
    return M.ON_TOP[self:metatile(cell)] == true and not self.wide_boulder:has(cell)
  end

  function Cells:at_edge(cell)
    local s = self.src:get(cell)
    local art = self.arts[s[1]]
    local x, y = s[2], s[3]
    return x == 0 or x == art.w - 1 or y == 0 or y == art.h - 1
  end

  function Cells:metatile(cell)
    local s = self.src:get(cell)
    return self.arts[s[1]]:metatile(s[2], s[3])
  end

  function Cells:role_id(cell)
    local s = self.src:get(cell)
    local art = self.arts[s[1]]
    return M.twin(art, art:metatile(s[2], s[3]))
  end

  function Cells:role(cell)
    if self.puddles and self.puddles:has(cell) then return "floor" end
    local s = self.src:get(cell)
    return self.roles_of[s[1]]:role_at(s[2], s[3])
  end

  function Cells:water(cell)
    if not self.src:has(cell) then return false end
    if self:role(cell) == "water" or self.lone_bridge:has(cell) then return true end
    local v = self._over_water[cell]
    if v == nil then
      v = false
      if self:crown(cell) then
        for _, n in ipairs(self:_four(cell)) do
          if self.src:has(n) and self:role(n) == "water" and self:_lower(cell) == self:_lower(n) then
            v = true
            break
          end
        end
      end
      self._over_water[cell] = v
    end
    return v
  end

  function Cells:_four(cell)
    local x, y = unxy(cell)
    return { xy(x - 1, y), xy(x + 1, y), xy(x, y - 1), xy(x, y + 1) }
  end

  function Cells:_lower(cell)
    return T.str(self:art(cell), self:metatile(cell), true)
  end

  function Cells:crown(cell)
    if not self.src:has(cell) then return false end
    local s = self.src:get(cell)
    local lid, x, y = s[1], s[2], s[3]
    local art, roles = self.arts[lid], self.roles_of[lid]
    if y + 1 >= art.h or roles:role_at(x, y) == "tree" or roles:role_at(x, y + 1) ~= "tree" then
      return false
    end
    local m = art:metatile(x, y)
    local t = T.sub(T.CROWN, art)
    local n = t[m]
    if n == nil then
      local hi, lo = art:cell_image(m), art:cell_image(m, { 0 })
      n = 0
      for j = 0, 15 do
        for i = 0, 15 do
          local r1, g1, b1, a1 = hi:get(i, j)
          local r2, g2, b2, a2 = lo:get(i, j)
          if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 or a1 ~= a2 then n = n + 1 end
        end
      end
      t[m] = n
    end
    return n >= 64
  end

  function Cells:muddy(cell)
    if not self.src:has(cell) then return false end
    local s = self.src:get(cell)
    return self.mud ~= nil and self.roles_of[s[1]]:behaviour(s[2], s[3]) == self.mud
  end

  function Cells:drawn_on(cell)
    local art = self:art(cell)
    local m = self:metatile(cell)
    local key = T.akey(art) .. "|" .. m
    local v = self._drawn_on[key]
    if v == nil then
      local d = T.rgb(art, m, true)
      local nT, nF = 0, 0
      local top, face = M.TOP_COLOURS, M.FACE_COLOURS
      for i = 0, 255 do
        local c = d[i]
        if top[c] then nT = nT + 1 elseif face[c] then nF = nF + 1 end
      end
      v = nT >= 128 and "T" or (nF >= 128 and "F" or "G")
      self._drawn_on[key] = v
    end
    return v
  end

  function Cells:tree_on_rock(cell)
    return self.kind:get(cell) == UNKNOWN and self:role(cell) == "tree" and self:drawn_on(cell) ~= "G"
  end

  function Cells:walked(cell)
    return self.src:has(cell) and self:role(cell) == "floor" and not self.lone_bridge:has(cell)
  end

  function Cells._top_tile(art, m)
    if not M.MOUNTAIN[M.twin(art, m)] then return false end
    local n = counts(M.pixel_classes(art, m))
    return n.F < 0.08 * 256 and n.T >= 0.45 * 256
  end

  function Cells:house(cell)
    return self.models:has(cell) and self:role(cell) == "wall"
  end

  function Cells._in_face(art, x, y, both)
    local sides = {}
    for i, nx in ipairs({ x - 1, x + 1 }) do
      sides[i] = 0 <= nx and nx < art.w and counts(M.pixel_classes(art, art:metatile(nx, y))).F >= 96
    end
    if both then return sides[1] and sides[2] end
    return sides[1] or sides[2]
  end

  -- ── 2. terraces and their levels ───────────────────────────────────────

  local Offsets = py.class("Offsets")
  M.Offsets = Offsets

  function Offsets:__init()
    self.parent, self.off = pyx.odict(), pyx.odict()
  end

  function Offsets:find(a)
    local parent, off = self.parent, self.off
    if not parent:has(a) then
      parent:set(a, a)
      off:set(a, 0)
      return a, 0
    end
    local path = {}
    while parent:get(a) ~= a do
      path[#path + 1] = a
      a = parent:get(a)
    end
    local root = a
    local total = 0
    for i = #path, 1, -1 do
      local p = path[i]
      total = total + off:get(p)
      off:set(p, total)
      parent:set(p, root)
    end
    if #path > 0 then return root, off:get(path[1]) end
    return root, 0
  end

  function Offsets:join(a, b, d)
    local ra, oa = self:find(a)
    local rb, ob = self:find(b)
    if ra == rb then return oa - ob == d end
    self.parent:set(rb, ra)
    self.off:set(rb, oa - ob - d)
    return true
  end

  function M.runs_of(c)
    local kind, band = c.kind, c.band
    local function flat(cell)
      local k = kind:get(cell)
      return k == TOP or k == GROUND
    end
    local function on_top(cell)
      return c:tree_on_rock(cell) and c:drawn_on(cell) == "T"
    end
    local runs = {}
    for x = c.xs.start, c.xs.stop - 1 do
      for y = c.ys.start, c.ys.stop - 1 do
        local nxt = xy(x, y + 1)
        local hi = xy(x, y)
        local hy = y
        while on_top(hi) do
          hy = hy - 1
          hi = xy(x, hy)
        end
        if flat(hi) and kind:get(nxt) == ROCK and not band:has(nxt) and not c:water(hi) then
          local k = 1
          while kind:get(xy(x, y + 1 + k)) == ROCK and not band:has(xy(x, y + 1 + k)) do k = k + 1 end
          local e = xy(x, y + 1 + k)
          local cells = {}
          for i = 0, k - 1 do cells[#cells + 1] = xy(x, y + 1 + i) end
          if flat(e) and not c.rim:has(e) then runs[#runs + 1] = { "S", hi, cells, e } end
        end
      end
    end
    for y = c.ys.start, c.ys.stop - 1 do
      for x = c.xs.start, c.xs.stop - 1 do
        local nxt = xy(x + 1, y)
        if flat(xy(x, y)) and band:has(nxt) then
          local side = band:get(nxt)
          local k = 1
          while band:get(xy(x + 1 + k, y)) == side do k = k + 1 end
          local e = xy(x + 1 + k, y)
          if flat(e) then
            local cells = {}
            for i = 0, k - 1 do cells[#cells + 1] = xy(x + 1 + i, y) end
            if side == "E" and not c:water(xy(x, y)) then
              runs[#runs + 1] = { "E", xy(x, y), cells, e }
            elseif side == "W" and not c:water(e) then
              local rev = {}
              for i = #cells, 1, -1 do rev[#rev + 1] = cells[i] end
              runs[#runs + 1] = { "W", e, rev, xy(x, y) }
            end
          end
        end
      end
    end
    return runs
  end

  function M.terraces(c, runs)
    local kind = c.kind
    local uf, order = {}, {}
    local apart, apart_order = {}, {}
    for _, r in ipairs(runs) do
      local hi, lo = r[2], r[4]
      if apart[hi] == nil then apart[hi] = {}; apart_order[#apart_order + 1] = hi end
      apart[hi][lo] = true
      if apart[lo] == nil then apart[lo] = {}; apart_order[#apart_order + 1] = lo end
      apart[lo][hi] = true
    end
    local members = {}
    local function find(a)
      local p = uf[a]
      if p == nil then uf[a] = a; order[#order + 1] = a; return a end
      while p ~= a do
        local g = uf[p]
        uf[a] = g
        a = g
        p = uf[a]
      end
      return a
    end
    local function touches(ma, rb)
      for _, m in ipairs(ma) do
        for o in pairs(apart[m]) do
          if find(o) == rb then return true end
        end
      end
      return false
    end
    local function join(a, b)
      local ra, rb = find(a), find(b)
      if ra == rb then return end
      local ma, mb = members[ra], members[rb]
      if (ma and touches(ma, rb)) or (mb and touches(mb, ra)) then return end
      uf[rb] = ra
      if mb and #mb > 0 then
        local into = members[ra]
        if into == nil then into = {}; members[ra] = into end
        for _, v in ipairs(mb) do into[#into + 1] = v end
        members[rb] = nil
      end
    end
    for _, cell in ipairs(apart_order) do members[cell] = { cell } end
    local edges = {}
    local rim, walked_tops, falls = c.rim, c.walked_tops, c.falls
    for cell, k in kind:items() do
      if k == TOP or k == GROUND or k == UNKNOWN then
        find(cell)
        local x, y = unxy(cell)
        for dir = 1, 2 do
          local n = dir == 1 and xy(x + 1, y) or xy(x, y + 1)
          local south = dir == 2
          local nk = kind:get(n)
          local skip = false
          if k == TOP then
            if nk ~= TOP or (south and rim:has(n)) then skip = true
            elseif c:on_top(cell) ~= c:on_top(n) then skip = true end
          elseif nk ~= GROUND and nk ~= UNKNOWN then
            skip = true
          elseif south and walked_tops:has(n) and rim:has(n) then
            skip = true
          end
          if not skip and (c:tree_on_rock(cell) or c:tree_on_rock(n))
              and ((c:drawn_on(cell) == "G") ~= (c:drawn_on(n) == "G")) then
            skip = true
          end
          if not skip then
            local ma, mb = c:metatile(cell), c:metatile(n)
            local wa, wb = c:water(cell), c:water(n)
            if falls:has(cell) and not falls:has(n) and south then
              skip = true
            else
              local rank
              if (wa and wb) or (k == GROUND and nk == GROUND and c:walked(cell) and c:walked(n)) then
                rank = 0
              elseif ma < 0x200 and mb < 0x200 then
                rank = 1
              else
                rank = 2
              end
              if walked_tops:has(cell) ~= walked_tops:has(n) then rank = 3 end
              if wa ~= wb then rank = rank + 3 end
              edges[#edges + 1] = { rank, cell, n }
            end
          end
        end
      end
    end
    table.sort(edges, function(p, q)
      if p[1] ~= q[1] then return p[1] < q[1] end
      if p[2] ~= q[2] then return p[2] < q[2] end
      return p[3] < q[3]
    end)
    for _, e in ipairs(edges) do join(e[2], e[3]) end
    local tg, comp = pyx.odict(), pyx.odict()
    for _, cell in ipairs(order) do
      if kind:get(cell) == UNKNOWN then tg:set(cell, find(cell)) end
    end
    c.tree_ground = tg
    for _, cell in ipairs(order) do
      if kind:get(cell) ~= UNKNOWN then comp:set(cell, find(cell)) end
    end
    return comp
  end

  function M.steps(c, cells, direction)
    local out, n = {}, 0
    local UP, LO = M.UPPER_END, M.LOWER_END
    for i, cell in ipairs(cells) do
      if direction == "S" and i > 1 and UP[c:role_id(cells[i - 1])] and LO[c:role_id(cell)]
          and out[#out] == n - 1 then
        out[#out + 1] = out[#out]
      else
        out[#out + 1] = n
        n = n + 1
      end
    end
    return out, n
  end

  -- a Counter: pyx.odict with += (array keys canonicalised by pyx.key)
  local function inc(counter, k, by)
    counter:set(k, counter:get(k, 0) + by)
  end
  -- most_common(1)[0]: the first key with the largest count
  local function most_common(counter)
    local best, bn
    for k, n in counter:items() do
      if bn == nil or n > bn then best, bn = k, n end
    end
    return best, bn
  end
  T.inc, T.most_common = inc, most_common

  function M.solve_levels(c, comp, runs, reference, meets, blocks_out)
    local kept_runs = {}
    for _, r in ipairs(runs) do
      local a, b = comp:get(r[2]), comp:get(r[4])
      if a ~= nil and b ~= nil and a ~= b then kept_runs[#kept_runs + 1] = r end
    end
    runs = kept_runs
    local vote, hidden = pyx.odict(), pyx.odict()
    for _, r in ipairs(runs) do
      local d, hi, cells, lo = r[1], r[2], r[3], r[4]
      local head = false
      if d ~= "S" then
        for _, cell in ipairs(cells) do
          if c.rim:has(cell) then head = true; break end
        end
      end
      local _, nsteps = M.steps(c, cells, d)
      local key = { comp:get(hi), comp:get(lo), nsteps }
      inc(vote, key, head and 1 or 2)
      local hid = 0
      if d == "S" then
        local lx, ly = unxy(lo)
        if (c:role(lo) == "wall" and c:metatile(lo) >= 0x200) or c.kind:get(xy(lx, ly + 1)) == UNKNOWN then
          hid = 1
        end
      end
      inc(hidden, key, hid)
    end
    local lip = pyx.odict()
    local tg = c.tree_ground
    local function behind(n)
      local v = comp:get(n)
      if v == nil and tg ~= nil then v = tg:get(n) end
      return v
    end
    for cell in c.rim:iter() do
      local x, y = unxy(cell)
      local n = xy(x, y - 1)
      local t = comp:get(cell)
      local bn = behind(n)
      if t ~= nil and bn ~= nil and t ~= bn and c.src:get(n)[1] == c.src:get(cell)[1] then
        inc(lip, { t, bn, 1 }, 1)
      end
    end
    local off = Offsets()
    local dropped = {}
    local size = {}
    local cells_of, terr_order = {}, {}
    for cell, t in comp:items() do
      size[t] = (size[t] or 0) + 1
      local l = cells_of[t]
      if l == nil then l = {}; cells_of[t] = l; terr_order[#terr_order + 1] = t end
      l[#l + 1] = cell
    end
    local kind_of = {}
    for _, t in ipairs(terr_order) do kind_of[t] = c.kind:get(cells_of[t][1]) end
    local keep = c.keep
    if reference ~= nil then
      local sorted_t = {}
      for i, t in ipairs(terr_order) do sorted_t[i] = t end
      table.sort(sorted_t)
      for _, t in ipairs(sorted_t) do
        local cells = cells_of[t]
        if kind_of[t] == GROUND and #cells >= M.ANCHOR_MIN then
          local edge = {}
          for _, cell in ipairs(cells) do
            if c:at_edge(cell) and reference:has(cell) then
              local ok = true
              if meets ~= nil then
                local mv = meets:get(cell)
                ok = mv ~= nil and mv[2] and true or false
              end
              if ok then edge[#edge + 1] = cell end
            end
          end
          local go = #edge >= 2
          if go and meets ~= nil then
            local met, along = pyx.odict(), pyx.odict()
            for _, cell in ipairs(edge) do inc(met, meets:get(cell)[1], 1) end
            for _, cell in ipairs(cells) do
              local mv = meets:get(cell)
              if mv ~= nil then inc(along, mv[1], 1) end
            end
            local any = false
            for b, n in met:items() do
              if 2 * n >= along:get(b, 0) then any = true; break end
            end
            go = any
          end
          if go then
            local got = pyx.odict()
            for _, cell in ipairs(cells) do
              if reference:has(cell) and not keep:has(cell) then
                inc(got, LEVEL * py.round(reference:get(cell) / LEVEL), 1)
              end
            end
            if got:len() > 0 then
              local v = most_common(got)
              off:join(M.WORLD, t, 0 - v)
            end
          end
        end
      end
    end
    local src = c.src
    local function across(a, b) return src:get(a)[1] ~= src:get(b)[1] end
    local function weight(key, n)
      local w = n * (across(key[1], key[2]) and 0.5 or 1.0)
      if hidden:get(key, 0) * 2 >= n then w = w * 0.25 end
      return w
    end
    local items = {}
    for key, n in vote:items() do items[#items + 1] = { key, n, -weight(key, n) } end
    table.sort(items, function(p, q)
      if p[3] ~= q[3] then return p[3] < q[3] end
      local a, b = p[1], q[1]
      if a[3] ~= b[3] then return a[3] < b[3] end
      if a[1] ~= b[1] then return a[1] < b[1] end
      return a[2] < b[2]
    end)
    for _, it in ipairs(items) do
      local key, n = it[1], it[2]
      if not off:join(key[1], key[2], key[3] * LEVEL) then
        dropped[#dropped + 1] = { { key[1], key[2], key[3] }, n }
      end
    end
    local litems = {}
    for key, n in lip:items() do litems[#litems + 1] = { key, n } end
    table.sort(litems, function(p, q)
      if p[2] ~= q[2] then return p[2] > q[2] end
      local a, b = p[1], q[1]
      if a[1] ~= b[1] then return a[1] < b[1] end
      if a[2] ~= b[2] then return a[2] < b[2] end
      return a[3] < b[3]
    end)
    for _, it in ipairs(litems) do
      local key = it[1]
      off:join(key[1], key[2], key[3] * LEVEL)
    end
    local roots, root_order = {}, {}
    local tset = pyx.xyset()
    for _, t in comp:items() do tset:add(t) end
    for t in tset:iter() do
      local r = off:find(t)
      local l = roots[r]
      if l == nil then l = {}; roots[r] = l; root_order[#root_order + 1] = r end
      l[#l + 1] = t
    end
    local level = pyx.odict()
    local world_root = off:find(M.WORLD)
    for _, r in ipairs(root_order) do
      local mem = roots[r]
      if blocks_out ~= nil then
        for _, t in ipairs(mem) do blocks_out:set(t, r) end
      end
      local rel = {}
      for _, t in ipairs(mem) do
        local _, o = off:find(t)
        rel[t] = o
      end
      local grounds = {}
      for _, t in ipairs(mem) do
        if kind_of[t] == GROUND then grounds[#grounds + 1] = t end
      end
      local pool = #grounds > 0 and grounds or mem
      local lift
      if r == world_root then
        local _, o = off:find(M.WORLD)
        lift = 0 - o
      elseif reference ~= nil then
        local diffs = pyx.odict()
        for _, t in ipairs(pool) do
          for _, cell in ipairs(cells_of[t]) do
            if reference:has(cell) and not keep:has(cell) then
              inc(diffs, LEVEL * py.round((reference:get(cell) - rel[t]) / LEVEL), 1)
            end
          end
        end
        local bk, bn
        for k, n in diffs:items() do
          if bn == nil or n > bn or (n == bn and -math.abs(k) > -math.abs(bk)) then bk, bn = k, n end
        end
        if bn ~= nil then lift = bk end
      end
      if lift == nil then
        local ref, rs
        for _, t in ipairs(pool) do
          if rs == nil or size[t] > rs or (size[t] == rs and t > ref) then ref, rs = t, size[t] end
        end
        lift = 0 - rel[ref]
      end
      for _, t in ipairs(mem) do level:set(t, rel[t] + lift) end
    end
    return level, dropped
  end

  -- ── 3. the level each rock cell hangs from ─────────────────────────────

  function M.upper_levels(c, comp, level, runs)
    local U = pyx.odict()
    local band, kind = c.band, c.kind
    local function lv(cell) return level:get(comp:get(cell)) end
    for _, r in ipairs(runs) do
      local side, hi, cells, lo = r[1], r[2], r[3], r[4]
      if comp:has(hi) and comp:has(lo) then
        local top, bottom = lv(hi), lv(lo)
        if top > bottom then
          local idx = M.steps(c, cells, side)
          for j = 1, math.min(#idx, #cells) do
            local i, cell = idx[j], cells[j]
            local u = math.max(top - LEVEL * i, bottom + LEVEL)
            local cur = U:get(cell)
            if cur == nil or u > cur then U:set(cell, u) end
          end
        end
      end
    end
    local crests = {}
    for y = c.ys.start, c.ys.stop - 1 do
      for x = c.xs.start, c.xs.stop - 1 do
        if comp:has(xy(x, y)) and band:has(xy(x + 1, y)) and band:get(xy(x + 1, y)) == "W" then
          local k = 1
          while band:get(xy(x + 1 + k, y)) == "W" do k = k + 1 end
          if band:get(xy(x + 1 + k, y)) == "E" then
            local j = 1
            while band:get(xy(x + 1 + k + j, y)) == "E" do j = j + 1 end
            local e = xy(x + 1 + k + j, y)
            if comp:has(e) then
              local lo_w, lo_e = lv(xy(x, y)), lv(e)
              local crest = math.max(lo_w + LEVEL * k, lo_e + LEVEL * j)
              for i = 0, k - 1 do
                U:setdefault(xy(x + 1 + i, y), crest - LEVEL * (k - 1 - i))
                crests[xy(x + 1 + i, y)] = true
              end
              for i = 0, j - 1 do
                U:setdefault(xy(x + 1 + k + i, y), crest - LEVEL * i)
                crests[xy(x + 1 + k + i, y)] = true
              end
            end
          end
        end
      end
    end
    for y = c.ys.start, c.ys.stop - 1 do
      for x = c.xs.start, c.xs.stop - 1 do
        if comp:has(xy(x, y)) then
          for _, ss in ipairs({ { "W", 1 }, { "E", -1 } }) do
            local side, step = ss[1], ss[2]
            local k, run = 1, {}
            while band:get(xy(x + step * k, y)) == side do
              run[#run + 1] = xy(x + step * k, y)
              k = k + 1
            end
            if #run > 0 and not c.src:has(xy(x + step * k, y)) then
              for i, cell in ipairs(run) do
                if not U:has(cell) then
                  U:set(cell, lv(xy(x, y)) + LEVEL * i)
                  crests[cell] = true
                end
              end
            end
          end
        end
      end
    end
    local changed = true
    while changed do
      changed = false
      for cell, side in band:items() do
        if not U:has(cell) then
          local x, y = unxy(cell)
          for _, n in ipairs({ xy(x, y - 1), xy(x, y + 1) }) do
            if band:get(n) == side and U:has(n) then
              U:set(cell, U:get(n))
              changed = true
              break
            end
          end
        end
      end
    end
    local todo = {}
    for cell, k in kind:items() do
      if k == ROCK and not U:has(cell) then todo[#todo + 1] = cell end
    end
    for _ = 1, 16 do
      local left = {}
      for _, cell in ipairs(todo) do
        local x, y = unxy(cell)
        local side = band:get(cell)
        local high
        if side == "E" then high = xy(x - 1, y)
        elseif side == "W" then high = xy(x + 1, y)
        else high = xy(x, y - 1) end
        local under = (side or band:has(xy(x, y - 1))) and 0 or -LEVEL
        local tier2 = { { xy(x - 1, y), 0, 0 }, { xy(x + 1, y), 0, 0 } }
        if side then
          tier2[3] = { xy(x, y - 1), 0, 0 }
          tier2[4] = { xy(x, y + 1), 0, 0 }
        end
        local tiers = { { { high, 0, under } }, tier2, { { xy(x, y + 1), LEVEL, LEVEL } } }
        local got
        for _, tier in ipairs(tiers) do
          local best
          for _, e in ipairs(tier) do
            local n = e[1]
            local v
            if comp:has(n) then v = lv(n) + e[2]
            elseif U:has(n) then v = U:get(n) + e[3] end
            if v ~= nil and (best == nil or v > best) then best = v end
          end
          if best ~= nil then got = best; break end
        end
        if got == nil then left[#left + 1] = cell else U:set(cell, got) end
      end
      if #left == #todo then break end
      todo = left
    end
    for _, cell in ipairs(todo) do U:set(cell, LEVEL) end
    local counted = {}
    for _, r in ipairs(runs) do
      for _, cell in ipairs(r[3]) do counted[cell] = true end
    end
    for k in pairs(crests) do counted[k] = true end
    local rest = {}
    for cell, k in kind:items() do
      if k == ROCK and not counted[cell] then rest[#rest + 1] = cell end
    end
    for _, cell in ipairs(rest) do
      local x, y = unxy(cell)
      local lo, hi
      for dx = -2, 2 do
        for dy = -2, 2 do
          local n = xy(x + dx, y + dy)
          if comp:has(n) then
            local v = lv(n)
            if lo == nil or v < lo then lo = v end
            if hi == nil or v > hi then hi = v end
          end
        end
      end
      if lo ~= nil then U:set(cell, math.max(lo, math.min(hi, U:get(cell)))) end
    end
    return U
  end

  local function minl(t)
    local m = t[1]
    for i = 2, #t do if t[i] < m then m = t[i] end end
    return m
  end
  local function maxl(t)
    local m = t[1]
    for i = 2, #t do if t[i] > m then m = t[i] end end
    return m
  end

  function M.unknown_levels(c, comp, level, U)
    local out = pyx.odict()
    local seen = {}
    local kind, band, rim, prop_of = c.kind, c.band, c.rim, c.prop_of
    local function lv(cell) return level:get(comp:get(cell)) end
    local function prop_eq(a, b)
      if a == nil or b == nil then return a == b end
      return a[1] == b[1] and a[2] == b[2]
    end
    local function backs(cell, n)
      local x, y = unxy(cell)
      return n == xy(x, y + 1) and rim:has(n) and kind:get(n) == TOP
    end
    local starts = {}
    for cell, k in kind:items() do
      if k == UNKNOWN then starts[#starts + 1] = cell end
    end
    table.sort(starts)
    for _, start in ipairs(starts) do
      if not seen[start] then
        local patch, todo = {}, { start }
        seen[start] = true
        while #todo > 0 do
          local cell = todo[#todo]
          todo[#todo] = nil
          patch[#patch + 1] = cell
          local mine = prop_of:get(cell)
          for _, n in ipairs(c:_four(cell)) do
            if kind:get(n) == UNKNOWN and not seen[n] and prop_eq(prop_of:get(n), mine) then
              seen[n] = true
              todo[#todo + 1] = n
            end
          end
        end
        local cand, wet, feet, behind = {}, {}, {}, {}
        for _, cell in ipairs(patch) do
          local x, y = unxy(cell)
          local south = xy(x, y + 1)
          for _, n in ipairs(c:_four(cell)) do
            if comp:has(n) and not backs(cell, n) then
              local w = c:water(n)
              if w then wet[#wet + 1] = lv(n) else cand[#cand + 1] = lv(n) end
              if n ~= south and not w then behind[#behind + 1] = lv(n) end
            end
          end
          local north = xy(x, y - 1)
          if U:has(north) then feet[#feet + 1] = U:get(north) - LEVEL end
        end
        local modelled = true
        for _, cell in ipairs(patch) do
          if not c.props:has(cell) then modelled = false; break end
        end
        if #cand > 0 and modelled then
          feet = {}
          if #behind > 0 then cand = behind end
        end
        local use_wet = #wet > #cand + #feet
        local done = false
        if use_wet and not modelled then
          local tops, ntops, one = {}, 0, nil
          for _, cell in ipairs(patch) do
            local x, y = unxy(cell)
            local run = {}
            while kind:get(xy(x, y + 1 + #run)) == ROCK and not band:has(xy(x, y + 1 + #run)) do
              run[#run + 1] = xy(x, y + 1 + #run)
            end
            local foot = xy(x, y + 1 + #run)
            local fk = kind:get(foot)
            if #run > 0 and comp:has(foot) and (fk == TOP or fk == GROUND) then
              local _, n = M.steps(c, run, "S")
              local v = lv(foot) + LEVEL * n
              if not tops[v] then tops[v] = true; ntops = ntops + 1; one = v end
            end
          end
          if ntops == 1 then
            for _, cell in ipairs(patch) do out:set(cell, one) end
            done = true
          end
        end
        if not done then
          local ground = use_wet and wet or cand
          local floor_ = #ground > 0 and minl(ground) or nil
          if #ground > 0 and not use_wet and maxl(ground) - minl(ground) < 0.5 then
            local all = true
            for _, cell in ipairs(patch) do
              if not (M.tree_card(c, cell) and not M.small_trunk(c, cell)) then all = false; break end
            end
            if all then
              for _, cell in ipairs(patch) do out:set(cell, ground[1]) end
              done = true
            end
          end
          if not done then
            for i, f in ipairs(feet) do
              if floor_ ~= nil then feet[i] = math.max(f, floor_) end
            end
            if use_wet then cand = wet
            else
              local cf = {}
              for _, v in ipairs(cand) do cf[#cf + 1] = v end
              for _, v in ipairs(feet) do cf[#cf + 1] = v end
              cand = #cf > 0 and cf or wet
            end
            local v = #cand > 0 and minl(cand) or 0
            local own, own_order, spread = {}, {}, {}
            local smin, smax
            for _, cell in ipairs(patch) do
              local x, y = unxy(cell)
              local mine = {}
              local in_face = kind:get(xy(x - 1, y)) == ROCK and kind:get(xy(x + 1, y)) == ROCK
                and kind:get(xy(x, y + 1)) == UNKNOWN
              local top = not M.tree_card(c, cell) and c.src:has(xy(x, y + 1)) and M.small_trunk(c, xy(x, y + 1))
              local bh = {}
              local north = xy(x, y - 1)
              for _, n in ipairs(c:_four(cell)) do
                if not ((in_face and n == north) or backs(cell, n)) then
                  if comp:has(n) and c:water(n) == use_wet then
                    if top and n == north then bh[#bh + 1] = lv(n) else mine[#mine + 1] = lv(n) end
                  end
                end
              end
              if U:has(north) and not band:has(north) and not (modelled and #mine > 0) then
                local f = U:get(north) - LEVEL
                mine[#mine + 1] = floor_ == nil and f or math.max(f, floor_)
              end
              if #mine > 0 then
                own[cell] = minl(mine)
                own_order[#own_order + 1] = cell
              end
              if #mine > 0 or #bh > 0 then
                local s = #mine > 0 and minl(mine) or nil
                if #bh > 0 then
                  local b = minl(bh)
                  if s == nil or b < s then s = b end
                end
                spread[cell] = s
                if smin == nil or s < smin then smin = s end
                if smax == nil or s > smax then smax = s end
              end
            end
            if smin == nil or smax - smin <= LEVEL + 0.5 then
              for _, cell in ipairs(patch) do out:set(cell, v) end
            else
              local dist, res = {}, {}
              local front = {}
              for _, cell in ipairs(own_order) do
                dist[cell] = 0
                res[cell] = own[cell]
                front[#front + 1] = cell
              end
              while #front > 0 do
                local nxt = {}
                for _, cell in ipairs(front) do
                  for _, n in ipairs(c:_four(cell)) do
                    if kind:get(n) == UNKNOWN and seen[n] then
                      local d = dist[cell] + 1
                      if dist[n] == nil then
                        dist[n] = d
                        res[n] = res[cell]
                        nxt[#nxt + 1] = n
                      elseif dist[n] == d then
                        res[n] = math.min(res[n], res[cell])
                      end
                    end
                  end
                end
                front = nxt
              end
              local by_y = py.sorted(patch, function(cl)
                local _, cy = unxy(cl)
                return -cy
              end)
              for _, cell in ipairs(by_y) do
                local x, y = unxy(cell)
                local s = xy(x, y + 1)
                if not M.tree_card(c, cell) and res[s] ~= nil and M.small_trunk(c, s) then
                  res[cell] = res[s]
                end
              end
              for _, cell in ipairs(patch) do
                local r = res[cell]
                if r == nil then r = v end
                out:set(cell, r)
              end
            end
          end
        end
      end
    end
    return out
  end

  function M.settle(c, U, flat, fixed)
    local kind = c.kind
    local inset
    if fixed == nil then inset = function() return false end
    elseif pyx.is_set(fixed) then inset = function(k) return fixed.pos[k] ~= nil end
    elseif pyx.is_odict(fixed) then inset = function(k) return fixed:has(k) end
    else inset = function(k) return fixed[k] ~= nil and fixed[k] ~= false end end
    local function score(x, y)
      local n = 0
      for g = 0, 3 do
        local gx, gy = x + g % 2, y + floor(g / 2)
        local started, c1, c2 = false, nil, nil       -- common: up to two values
        for q = 0, 3 do
          local cell = xy(gx - 1 + q % 2, gy - 1 + floor(q / 2))
          if kind:has(cell) then
            local o1, o2
            local fv = flat:get(cell)
            if fv ~= nil then o1 = fv
            else
              local u = U:get(cell)
              o1, o2 = u, u - LEVEL
            end
            if not started then
              started, c1, c2 = true, o1, o2
            else
              local k1 = c1 ~= nil and (c1 == o1 or c1 == o2)
              local k2 = c2 ~= nil and (c2 == o1 or c2 == o2)
              c1, c2 = k1 and c1 or nil, k2 and c2 or nil
            end
          end
        end
        if started and (c1 ~= nil or c2 ~= nil) then n = n + 1 end
      end
      return n
    end
    local rock = {}
    for cell, k in kind:items() do
      if k == ROCK and not c.band:has(cell) then rock[#rock + 1] = cell end
    end
    table.sort(rock)
    for _ = 1, 8 do
      local moved = 0
      for _, cell in ipairs(rock) do
        local here = U:get(cell)
        local x, y = unxy(cell)
        local best, best_score = here, score(x, y)
        local isfixed = inset(cell)
        for _, u in ipairs({ here + LEVEL, here - LEVEL }) do
          U:set(cell, u)
          local sc = score(x, y)
          local need = isfixed and 2 or 1
          local held = false
          if u > here and not isfixed then
            for _, n in ipairs({ xy(x, y - 1), xy(x - 1, y), xy(x + 1, y) }) do
              if U:get(n) == u or flat:get(n) == u then held = true; break end
            end
          end
          if sc >= best_score + need or (sc == best_score and held) then
            best, best_score = u, sc
          end
        end
        U:set(cell, best)
        if best ~= here then moved = moved + 1 end
      end
      if moved == 0 then break end
    end
    return U
  end
end
