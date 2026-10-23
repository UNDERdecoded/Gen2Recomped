-- Mod-side terrain adapter: the only host dependency is mod.renderData v1.
-- Maps use OASC's spatial units (ox/oy in 16px cells), not native map handles.
local A = {}
local function number(v)
  return type(v) == "number" and v == v and math.abs(v) < math.huge
end
function A.new(data)
  if not data or not data:supports(1) then
    return nil, "render data v1 unavailable"
  end
  local self = {}
  function self:capture(frame, options)
    if options == nil then
      options = {}
    end
    if type(options) ~= "table" then
      return nil, "invalid world options"
    end
    if type(frame) ~= "table" or frame.version ~= 1 or frame.generation ~= 3 then
      return nil, "unsupported world frame"
    end
    local camera = frame.camera or {}
    local b = options.bounds
      or { x = camera.x, y = camera.y, width = frame.viewWidth, height = frame.viewHeight }
    if
      not (
        number(b.x)
        and number(b.y)
        and number(b.width)
        and number(b.height)
        and b.width > 0
        and b.height > 0
      )
    then
      return nil, "invalid world bounds"
    end
    local budget = options.maxCells or 16384
    if not (number(budget) and budget % 1 == 0 and budget >= 1 and budget <= 16384) then
      return nil, "invalid world cell budget"
    end
    local root, err = data:snapshot(1, frame.mapId, { region = { x = 0, y = 0, width = 1, height = 1 } })
    if not root then
      return nil, err
    end
    local out = { version = 1, mapId = root.activeMapId, cellSize = 16, maps = {}, tilesets = {} }
    local count = 0
    for _, p in ipairs(root.placements) do
      if p.active or options.neighbors ~= false then
        local x1 = math.max(0, math.floor(b.x / 16) - p.x)
        local y1 = math.max(0, math.floor(b.y / 16) - p.y)
        local x2 = math.min(p.width, math.ceil((b.x + b.width) / 16) - p.x)
        local y2 = math.min(p.height, math.ceil((b.y + b.height) / 16) - p.y)
        if x2 > x1 and y2 > y1 then
          count = count + (x2 - x1) * (y2 - y1)
          if count > budget then
            return nil, "world cell budget exceeded"
          end
          local row = {
            id = p.mapId,
            ox = p.x,
            oy = p.y,
            active = p.active,
            width = p.width,
            height = p.height,
            tilesetId = p.tilesetId,
            regions = {},
          }
          -- Chunk large visible grids without ever exceeding the v1 read cap.
          local width = x2 - x1
          local step = math.max(1, math.floor(4096 / width))
          for y = y1, y2 - 1, step do
            local grid, why = data:snapshot(
              1,
              frame.mapId,
              { mapId = p.mapId, region = { x = x1, y = y, width = width, height = math.min(step, y2 - y) } }
            )
            if not grid then
              return nil, why
            end
            if grid.activeMapId ~= root.activeMapId or grid.tilesetId ~= p.tilesetId then
              return nil, "world changed during capture"
            end
            row.regions[#row.regions + 1] = grid
          end
          if not out.tilesets[p.tilesetId] then
            local graphics, why = data:tileset(1, frame.mapId, p.mapId)
            if not graphics then
              return nil, why
            end
            if graphics.id ~= p.tilesetId then
              return nil, "world changed during capture"
            end
            out.tilesets[p.tilesetId] = graphics
          end
          out.maps[#out.maps + 1] = row
        end
      end
    end
    -- Recheck the active map after all observations. No partial scene escapes
    -- if a host reports a warp while a connected layout is being sampled.
    local tail, why = data:snapshot(1, frame.mapId, { region = { x = 0, y = 0, width = 1, height = 1 } })
    if not tail then
      return nil, why
    end
    if tail.activeMapId ~= root.activeMapId then
      return nil, "world changed during capture"
    end
    if #out.maps == 0 then
      return nil, "no resident terrain in view"
    end
    out.cells = count
    return out
  end
  return self
end
return A
