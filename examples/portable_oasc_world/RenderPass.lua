-- Portable world-pass host adapter. The default is a static terrain proof;
-- OASC can supply drawScene(scene, frame, resources) for its own geometry.
local Adapter, Atlas = ...
local P = {}
function P.new(data, drawScene)
  local adapter, reason = Adapter.new(data)
  if not adapter then
    return nil, reason
  end
  local self = { atlases = {} }
  local function release(row)
    if not row then
      return
    end
    for _, image in pairs(row.images or {}) do
      image:release()
    end
    for _, quad in pairs(row.quads or {}) do
      quad:release()
    end
  end
  function self:invalidate()
    for _, row in pairs(self.atlases) do
      release(row)
    end
    self.atlases = {}
    if self.canvas then
      if love.graphics.getCanvas() == self.canvas then
        love.graphics.setCanvas()
      end
      self.canvas:release()
      self.canvas = nil
    end
  end
  local function build(graphics)
    local g = love.graphics
    local mids, slots = {}, {}
    local split = graphics.layout.metatilesInPrimary
    local function add(first, count)
      for mid = first, first + count - 1 do
        slots[mid] = #mids
        mids[#mids + 1] = mid
      end
    end
    add(0, math.min(split, #graphics.primary.metatileEntriesLE16 / 16))
    add(split, math.min(1024 - split, #graphics.secondary.metatileEntriesLE16 / 16))
    local row = { source = graphics, slots = slots, images = {}, quads = {} }
    local w, h = 256, math.max(16, math.ceil(#mids / 16) * 16)
    local pixels = { under = {}, over = {}, middle = {} }
    local ok, err = pcall(function()
      for _, mid in ipairs(mids) do
        local decoded = assert(Atlas.decode(graphics, mid))
        local slot = slots[mid]
        for name, bytes in pairs(decoded) do
          local rows = pixels[name]
          for y = 0, 15 do
            local at = (math.floor(slot / 16) * 16 + y) * 16 + slot % 16 + 1
            rows[at] = bytes:sub(y * 64 + 1, y * 64 + 64)
          end
        end
      end
      local clear = string.rep(string.char(0), 64)
      for name, rows in pairs(pixels) do
        for i = 1, h * 16 do
          if not rows[i] then
            rows[i] = clear
          end
        end
        local imageData = love.image.newImageData(w, h, "rgba8", table.concat(rows))
        local made, image = pcall(g.newImage, imageData)
        imageData:release()
        if not made then
          error(image)
        end
        row.images[name] = image
        image:setFilter("nearest", "nearest")
      end
      for mid, slot in pairs(slots) do
        row.quads[mid] = g.newQuad(slot % 16 * 16, math.floor(slot / 16) * 16, 16, 16, w, h)
      end
    end)
    if not ok then
      release(row)
      return nil, err
    end
    return row
  end
  local function terrain(scene, frame, resources)
    local g = love.graphics
    g.scale(frame.pixelWidth / frame.viewWidth, frame.pixelHeight / frame.viewHeight)
    g.translate(-frame.camera.x, -frame.camera.y)
    for _, layer in ipairs({ "under", "over" }) do
      for _, map in ipairs(scene.maps) do
        local atlas = resources.atlases[map.tilesetId]
        for _, grid in ipairs(map.regions) do
          local r = grid.region
          for y = 0, r.height - 1 do
            for x = 0, r.width - 1 do
              local mid = grid.metatiles[y * r.width + x + 1]
              local quad = assert(atlas.quads[mid], "metatile absent from source atlas")
              g.draw(atlas.images[layer], quad, (map.ox + r.x + x) * 16, (map.oy + r.y + y) * 16)
            end
          end
        end
      end
    end
    return true
  end
  function self:drawWorld(frame)
    local scene, err = adapter:capture(frame, self.options)
    if not scene then
      self:invalidate()
      self.lastError = err
      return nil
    end
    for id, row in pairs(self.atlases) do
      if not scene.tilesets[id] then
        release(row)
        self.atlases[id] = nil
      end
    end
    for id, graphics in pairs(scene.tilesets) do
      local old = self.atlases[id]
      if not old or not Atlas.equal(old.source, graphics) then
        local row, why = build(graphics)
        if not row then
          self:invalidate()
          self.lastError = why
          return nil
        end
        release(old)
        self.atlases[id] = row
      end
    end
    local g = love.graphics
    local w, h = frame.pixelWidth, frame.pixelHeight
    local limit = g.getSystemLimits().texturesize
    if w % 1 ~= 0 or h % 1 ~= 0 or w > limit or h > limit then
      self:invalidate()
      self.lastError = "world target exceeds driver limits"
      return nil
    end
    if not self.canvas or self.canvas:getWidth() ~= w or self.canvas:getHeight() ~= h then
      local ok, canvas = pcall(g.newCanvas, w, h, { dpiscale = 1 })
      if not ok then
        self:invalidate()
        self.lastError = canvas
        return nil
      end
      if self.canvas then
        self.canvas:release()
      end
      self.canvas = canvas
      canvas:setFilter("nearest", "nearest")
    end
    g.setCanvas(self.canvas)
    g.origin()
    g.setShader()
    g.setScissor()
    g.setDepthMode()
    g.setColor(1, 1, 1, 1)
    g.setBlendMode("alpha", "alphamultiply")
    local first = scene.maps[1] and scene.tilesets[scene.maps[1].tilesetId]
    local backdrop = first and first.primary.palettes[1][1] or { 0, 0, 0 }
    g.clear(backdrop[1] / 255, backdrop[2] / 255, backdrop[3] / 255, 1)
    local ok, result = pcall(drawScene or terrain, scene, frame, self)
    if not ok or result ~= true then
      self:invalidate()
      self.lastError = ok and "scene declined" or result
      return nil
    end
    self.lastError = nil
    return self.canvas
  end
  return self
end
return P
