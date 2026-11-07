-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S MAP REPLACEMENTS: winter's Icirrus, the seasons' chunks,
-- White's own pieces and the story's swaps.
--
-- The records are src/import/Gen5MapVariants.lua's (/a/0/1/0). READ FROM
-- CODE (Black, ov10):
--   * the answers (0x02159E8C): [0] the field's season (0x0202E83C), [1] 0
--     in Black / 1 in White (0x0215843C != 21), [2] White ? season + 1 : 0,
--     [3..12] event var == value for the ten rows of 0x02170FB0
--     ({cond, row, var, value}: 3 0x4031 = 0x1220 ... 12 0x403A = 0x1028)
--   * a record whose answer picks a value other than its base (0x02159E00):
--     kind 1 -> the zone's matrix is the chosen one (0x02159C86); kind 0 ->
--     every cell of the matrix holding the base chunk holds the chosen
--     chunk (0x02159C9A); both on every map load (0x02159CC4)
-- Here the ground's grid (Gen4Ground.forMap) and the def's collision
-- (MapLoader) are rebuilt the way Gen4HiddenPaths rebuilds Sinnoh's paths:
-- the drawn chunks and their permission blocks both swap.
-- A swapped chunk walks on its OWN heights (constants.gen5MapVariants.chunks,
-- READ FROM THE DATA: the field reads a chunk's heights from that chunk's
-- permission tiles, and 194..196 / 200..203 differ from the chunks they
-- replace): the def's gen4HeightEdits / gen5SlopeTiles are rebuilt over the
-- swapped cells. INFERRED: the matrix swaps keep the zone's own size (both
-- matrices are read as the same grid).

-- THE STORY CONDITIONS (3..12): no script names vars 0x4031..0x403A
-- directly -- op 0x0DA <id, on, apply> writes them by the row of ov10's
-- table 0x02170FB0 (READ, 0x0215AE34; src/script/Gen5StorySwaps.lua), at ten
-- sites (the bedroom after the first battle, the castle rising at the
-- League, ...). An earlier reading missed that op and called these
-- unreachable. Nothing else may write them (OverworldState:gen4CountAmityStep
-- used to count 0x403A on BW maps).
local M = {}

M.CONDITION_VARS = { [3] = { 0x4031, 0x1220 }, [4] = { 0x4032, 0x0224 }, [5] = { 0x4033, 0x0206 },
  [6] = { 0x4034, 0x1209 }, [7] = { 0x4035, 0x0316 }, [8] = { 0x4036, 0x1227 },
  [9] = { 0x4037, 0x0830 }, [10] = { 0x4038, 0x0408 }, [11] = { 0x4039, 0x0120 },
  [12] = { 0x403A, 0x1028 } }

local CHUNK, BLOCKED, COLLISION = 32, 255, 0x8000

local function records(data)
  local c = data and data.constants
  local v = c and c.gen5MapVariants
  return v and v.records
end

function M.answer(save, cond)
  if cond == 0 then return require("src.world.Gen5FieldRules").season(save) end
  local white = require("src.core.GameVersion").get() == "white"
  if cond == 1 then return white and 1 or 0 end
  if cond == 2 then return white and (require("src.world.Gen5FieldRules").season(save) + 1) or 0 end
  local cv = M.CONDITION_VARS[cond]
  if cv then
    local vars = save and save.gen4Vars
    local v = vars and (vars[cv[1]] or vars[tostring(cv[1])]) or 0
    return v == cv[2] and 1 or 0
  end
  return 0
end

-- the replacements in force for matrix `layout`: newMatrix, { [base] = chunk }
function M.plan(data, save, layout)
  local recs = records(data)
  if not recs then return nil end
  local matrix, chunks = nil, nil
  for _, r in ipairs(recs) do
    if r.matrix == layout then
      local v = r.values[M.answer(save, r.cond) + 1]
      local base = r.values[1]
      if v and v ~= base and v ~= 0 and v ~= 0xFFFF then
        if r.kind == 1 then matrix = v
        else chunks = chunks or {}; chunks[base] = v end
      end
    end
  end
  return matrix, chunks
end

-- a key that changes whenever the plan does (for the caches)
function M.key(data, save, layout)
  local matrix, chunks = M.plan(data, save, layout)
  local parts = { tostring(matrix) }
  if chunks then
    local t = {}
    for b, v in pairs(chunks) do t[#t + 1] = b .. ">" .. v end
    table.sort(t)
    parts[#parts + 1] = table.concat(t, ",")
  end
  return table.concat(parts, "|")
end

-- the ground's grid with the plan applied (a copy)
function M.grid(data, save, layout, terrain, grid, altitudes)
  local matrix, chunks = M.plan(data, save, layout)
  if not (matrix or chunks) then return grid, altitudes end
  local src = grid
  if matrix and terrain and terrain.matrices and terrain.matrices[matrix]
     and terrain.matrices[matrix].land then
    src = terrain.matrices[matrix]
    altitudes = src.altitudes or altitudes
  end
  local land = {}
  for i, v in ipairs(src.land) do land[i] = (chunks and chunks[v]) or v end
  local out = {}
  for k, v in pairs(src) do out[k] = v end
  out.land = land
  return out, altitudes
end

-- the cell of one swapped chunk, whose map-local corner is (x0, y0): its
-- tiles take the chunk's own heights -- a raised tile its height, a slope
-- its ramp, and a flat 0 an explicit 0 beside a raised tile (Gen5Field's
-- rule: the floor beside a table does not take the table's height). A cache
-- imported before the heights were carried (no `ch`) keeps the def's.
function M.swapHeights(edits, slopes, ch, x0, y0, w, h)
  if not ch then return end
  local hs, ss = ch.h or {}, ch.s or {}
  local function hAt(t) return hs[t] or hs[tostring(t)] end
  local function sAt(t) return ss[t] or ss[tostring(t)] end
  local zeros = {}
  for t = 0, CHUNK * CHUNK - 1 do
    local tx, ty = t % CHUNK, math.floor(t / CHUNK)
    local x, y = x0 + tx, y0 + ty
    if x >= 0 and y >= 0 and x < w and y < h then
      local key = x .. "," .. y
      local v = hAt(t)
      edits[key], slopes[key] = nil, nil
      if v then edits[key] = v
      elseif sAt(t) then slopes[key] = true
      else zeros[#zeros + 1] = { x, y } end
    end
  end
  -- (in Gen5Field's order: a 0 written earlier counts as a neighbour, so the
  -- zeros spread along the floor the way the import's own pass spreads them)
  for _, z in ipairs(zeros) do
    local x, y = z[1], z[2]
    if edits[(x - 1) .. "," .. y] or edits[(x + 1) .. "," .. y]
       or edits[x .. "," .. (y - 1)] or edits[x .. "," .. (y + 1)] then
      edits[x .. "," .. y] = 0
    end
  end
end

-- the def's collision for this plan, from a pristine snapshot
function M.applyToDef(data, def, save)
  if not (def and def.gen5 and type(def.blocks) == "string" and type(def.behaviorCells) == "string") then return false end
  local terrain = data and data.gen4_terrain
  local grid = terrain and terrain.matrices and terrain.matrices[def.layout]
  if not (grid and grid.land) then return false end
  local key = M.key(data, save, def.layout)
  if def.gen5VariantKey == key then return false end
  def.gen5VariantBase = def.gen5VariantBase or { blocks = def.blocks, behaviorCells = def.behaviorCells,
    edits = def.gen4HeightEdits, slopes = def.gen5SlopeTiles }
  local base = def.gen5VariantBase
  def.gen5VariantKey = key
  local now = M.grid(data, save, def.layout, terrain, grid, nil)
  if now == grid then
    def.blocks, def.behaviorCells = base.blocks, base.behaviorCells
    def.gen4HeightEdits, def.gen5SlopeTiles = base.edits, base.slopes
    return true
  end
  local variants = data.constants and data.constants.gen5MapVariants
  local chunkHeights = variants and variants.chunks
  local edits, slopes = {}, {}
  for k, v in pairs(base.edits or {}) do edits[k] = v end
  for k, v in pairs(base.slopes or {}) do slopes[k] = v end
  local perms = data.gen4_map_permissions
  local w, h = def.width or 0, def.height or 0
  local ox, oy = def.originX or 0, def.originY or 0
  local cells, bytes = {}, {}
  for i = 1, w * h do
    cells[i] = base.blocks:sub(i * 2 - 1, i * 2)
    bytes[i] = base.behaviorCells:sub(i, i)
  end
  for gi, chunk in ipairs(now.land) do
    if chunk ~= grid.land[gi] then
      local cx, cy = (gi - 1) % grid.width, math.floor((gi - 1) / grid.width)
      local block = perms and (perms[chunk] or perms[tostring(chunk)])
      if type(block) == "string" then
        for ty = 0, CHUNK - 1 do
          for tx = 0, CHUNK - 1 do
            local mx, my = cx * CHUNK + tx - ox, cy * CHUNK + ty - oy
            if mx >= 0 and my >= 0 and mx < w and my < h then
              local at = (ty * CHUNK + tx) * 2
              local lo, hi = block:byte(at + 1, at + 2)
              local word = lo and hi and (lo + hi * 256) or nil
              local v = (word == nil or word >= COLLISION) and BLOCKED or (word % 256)
              local i = my * w + mx + 1
              cells[i] = string.char(v % 256, math.floor(v / 256))
              bytes[i] = string.char(word and word % 256 or 255)
            end
          end
        end
      end
      M.swapHeights(edits, slopes, chunkHeights and (chunkHeights[chunk] or chunkHeights[tostring(chunk)]),
        cx * CHUNK - ox, cy * CHUNK - oy, w, h)
    end
  end
  def.blocks, def.behaviorCells = table.concat(cells), table.concat(bytes)
  def.gen4HeightEdits = next(edits) and edits or nil
  def.gen5SlopeTiles = next(slopes) and slopes or nil
  return true
end

return M
