-- The tree sheet: Emerald 3DS's own tree art (original art by the Emerald
-- 3DS author, MIT -- see LICENSE-EMERALD3DS.md; not shipped with the mod,
-- fetched by bake/bake.py into generated/trees/) packed into one
-- 128x128 texture at the coordinates gen_voxel_trees.py packs them at, with
-- the crowns brightened by 1.12 as voxel_tree.c does at load.  The 1.30
-- saturation grade every world texture gets is the shader's.

local V = ...

local Trees = {}

local PACK = {
  { "tree_crown.png", 0, 0, true },
  { "tree_trunk.png", 32, 0 },
  { "tree_small_crown.png", 32, 32, true },
  { "tree_small_trunk.png", 48, 32 },
  { "tree_2_small_crown.png", 64, 0, true },
  { "tree_2_small_trunk.png", 80, 0 },
}

function Trees.U(px) return px / 128 end

local image
function Trees.image()
  if image ~= nil then return image or nil end
  local sheet = love.image.newImageData(128, 128)
  for _, e in ipairs(PACK) do
    local bytes = V.mod:read("generated/trees/" .. e[1])
    if not bytes and love.filesystem.getInfo("e3ds_voxel/trees/" .. e[1]) then
      bytes = love.filesystem.read("e3ds_voxel/trees/" .. e[1])
    end
    if bytes then
      local ok, src = pcall(love.image.newImageData, love.filesystem.newFileData(bytes, e[1]))
      if ok then
        local w, h = src:getDimensions()
        for y = 0, h - 1 do
          for x = 0, w - 1 do
            local r, g, b, a = src:getPixel(x, y)
            if e[4] then
              r, g, b = math.min(1, r * 1.12), math.min(1, g * 1.12), math.min(1, b * 1.12)
            end
            sheet:setPixel(e[2] + x, e[3] + y, r, g, b, a >= 0.5 and 1 or 0)
          end
        end
      end
    end
  end
  local ok, img = pcall(love.graphics.newImage, sheet)
  image = ok and img or false
  if image then
    image:setFilter("nearest", "nearest")
    image:setWrap("clamp", "clamp")
  end
  return image or nil
end

-- build the sheet again on next use (an in-game bake fetched the art)
function Trees.reset()
  image = nil
end

return Trees
