-- INDIGO//97 asset transform
--
-- Runs once inside Gen2Recomped's restricted transform sandbox. It reads the
-- player sheets from the player's private ROM cache and writes only the
-- recoloured result to save/mod-derived/indigo_97. No cartridge pixels ship in
-- this repository or its release ZIP.

local SHEETS = {
  { path = "sprites/chris.png", bike = false, style = "indigo" },
  { path = "sprites/chrisbike.png", bike = true, style = "indigo" },
  { path = "sprites/kris.png", bike = false, style = "cerulean" },
  { path = "sprites/krisbike.png", bike = true, style = "cerulean" },
}

local FISHING_POSES = {
  -- Gold and Silver expose the shared Chris strips through the original
  -- field-effect paths. Crystal additionally exposes the per-character paths
  -- below so its boy/girl selection can swap fishing art with the player form.
  { path = "fx/gen2_fish_down.png", direction = "down", style = "indigo" },
  { path = "fx/gen2_fish_up.png", direction = "up", style = "indigo" },
  { path = "fx/gen2_fish_side.png", direction = "side", style = "indigo" },
  { path = "fx/chris_fish_down.png", direction = "down", style = "indigo" },
  { path = "fx/chris_fish_up.png", direction = "up", style = "indigo" },
  { path = "fx/chris_fish_side.png", direction = "side", style = "indigo" },
  { path = "fx/kris_fish_down.png", direction = "down", style = "cerulean" },
  { path = "fx/kris_fish_up.png", direction = "up", style = "cerulean" },
  { path = "fx/kris_fish_side.png", direction = "side", style = "cerulean" },
}

local C = {
  ink = { 20, 23, 31 },
  hair = { 38, 34, 42 },
  hair_hi = { 78, 65, 68 },
  hair_dark = { 25, 24, 31 },
  auburn = { 126, 51, 31 },
  orange = { 230, 96, 35 },
  orange_hi = { 255, 151, 55 },
  red = { 211, 43, 47 },
  red_hi = { 246, 78, 65 },
  red_dark = { 131, 30, 39 },
  white = { 246, 239, 213 },
  white_shadow = { 191, 198, 194 },
  white_dark = { 125, 132, 132 },
  skin = { 232, 164, 101 },
  skin_shadow = { 181, 101, 64 },
  blue = { 38, 105, 177 },
  blue_hi = { 71, 143, 211 },
  navy = { 24, 53, 102 },
  denim = { 118, 172, 202 },
  denim_hi = { 165, 207, 222 },
  denim_dark = { 61, 105, 137 },
  yellow = { 239, 185, 40 },
  yellow_hi = { 255, 224, 92 },
  yellow_dark = { 157, 105, 27 },
  teal = { 34, 139, 129 },
  teal_hi = { 77, 184, 168 },
  teal_dark = { 18, 76, 75 },
  green = { 52, 132, 65 },
  green_hi = { 88, 171, 83 },
  green_dark = { 28, 79, 45 },
  steel = { 105, 119, 128 },
  steel_hi = { 180, 190, 188 },
}

local DIRECTIONS = { "down", "up", "side", "down", "up", "side" }

local function shadeIndex(r, a)
  if a == 0 or r > 0.83 then return 0 end -- OBJ colour 0 is transparent
  if r > 0.5 then return 1 end
  if r > 0.17 then return 2 end
  return 3
end

local function put(image, x, y, colour)
  image:setPixel(x, y,
    colour[1] / 255, colour[2] / 255, colour[3] / 255, 1)
end

local function toned(shade, highlight, base)
  if shade == 3 then return C.ink end
  return shade == 1 and highlight or base
end

local function region(shade, boundary, highlight, base, shadow)
  if boundary then return C.ink end
  if shade == 1 then return highlight end
  if shade == 2 then return base end
  return shadow
end

local function sourceShade(source, x, y, frameY)
  if x < 0 or x >= 16 or y < frameY or y >= frameY + 16 then return 0 end
  local r, _, _, a = source:getPixel(x, y)
  return shadeIndex(r, a)
end

local function poseShade(source, x, y)
  if x < 0 or x >= 16 or y < 0 or y >= 8 then return 0 end
  local r, _, _, a = source:getPixel(x, y)
  return shadeIndex(r, a)
end

-- The pose is only the lower eight pixels of the 16x16 standing frame. Its
-- top edge meets the ordinary walking sheet, so absence above row zero is not
-- an outline; all other exposed edges are.
local function isPoseBoundary(source, x, y)
  return poseShade(source, x - 1, y) == 0
    or poseShade(source, x + 1, y) == 0
    or (y > 0 and poseShade(source, x, y - 1) == 0)
    or poseShade(source, x, y + 1) == 0
end

local function isBoundary(source, x, y, frameY)
  return sourceShade(source, x - 1, y, frameY) == 0
    or sourceShade(source, x + 1, y, frameY) == 0
    or sourceShade(source, x, y - 1, frameY) == 0
    or sourceShade(source, x, y + 1, frameY) == 0
end

local function capColour(direction, x, localY, shade, boundary)
  local whitePanel = (direction == "down" and x >= 6 and x <= 9
      and localY >= 1 and localY <= 3)
    or (direction == "side" and x >= 8 and x <= 12
      and localY >= 2 and localY <= 4)

  if whitePanel then
    if not boundary and shade == 3 and x >= 7 and x <= 9 then
      return C.green_dark
    end
    return region(shade, boundary, C.white, C.white_shadow, C.white_dark)
  end
  return region(shade, boundary, C.red_hi, C.red, C.red_dark)
end

-- This is the 1.0.0 boy transform. Keep its logic unchanged: existing users
-- must get exactly the same generated pixels after upgrading.
local function colourBoySheet(ctx, source, bike)
  local width, height = source:getDimensions()
  if width ~= 16 or height < 96 then return nil end
  local out = ctx.blank(width, height)

  for y = 0, 95 do
    local frame = math.floor(y / 16)
    local frameY = frame * 16
    local top = (not bike and frame >= 3) and 1 or 0
    local direction = DIRECTIONS[frame + 1]
    local localY = (y - frameY) - top

    for x = 0, 15 do
      local r, _, _, a = source:getPixel(x, y)
      local shade = shadeIndex(r, a)
      if shade ~= 0 then
        local boundary = isBoundary(source, x, y, frameY)
        local colour

        if localY <= 4 then
          colour = capColour(direction, x, localY, shade, boundary)
        elseif localY <= 9 then
          if direction == "up" then
            colour = region(shade, boundary, C.hair_hi, C.hair, C.hair_dark)
          else
            colour = toned(shade, C.skin, C.skin_shadow)
            if direction == "side" and x >= 9 then
              colour = region(shade, boundary, C.hair_hi, C.hair, C.hair_dark)
            end
          end
        else
          colour = C.ink
        end

        if bike and localY >= 10 then
          if direction == "up" then
            colour = region(shade, boundary, C.green_hi, C.green, C.green_dark)
          else
            colour = region(shade, boundary, C.blue_hi, C.blue, C.navy)
          end
          if localY <= 11 and (x <= 3 or x >= 12) then
            colour = region(shade, boundary, C.green_hi, C.green, C.green_dark)
          end
          if localY >= 12 then
            local sideWheel = direction == "side" and (x <= 4 or x >= 11)
            if shade == 3 then
              colour = C.ink
            elseif sideWheel then
              colour = shade == 1 and C.steel_hi or C.steel
            elseif shade == 1 then
              colour = C.steel_hi
            else
              colour = C.red
            end
          end
        elseif not bike and localY >= 10 then
          if direction == "up" then
            colour = region(shade, boundary, C.green_hi, C.green, C.green_dark)
          else
            colour = region(shade, boundary, C.blue_hi, C.blue, C.navy)
          end
          if localY <= 12 and (x <= 3 or x >= 12) then
            colour = region(shade, boundary, C.green_hi, C.green, C.green_dark)
          end
          if y - frameY >= 13 then
            colour = region(shade, boundary, C.denim_hi, C.denim, C.denim_dark)
          end
          if y - frameY >= 14 then
            colour = region(shade, boundary, C.white, C.red, C.red_dark)
          end
        end

        if direction == "down" and not bike
            and (localY == 10 or localY == 11) and x >= 7 and x <= 8 then
          colour = shade == 3 and C.ink or C.navy
        end

        put(out, x, y, colour)
      end
    end
  end

  return out
end

local function accent(shade, highlight, base, dark)
  if shade == 1 then return highlight end
  if shade == 2 then return base end
  return dark
end

local function girlHairColour(shade, boundary)
  if boundary or shade == 3 then return C.auburn end
  return shade == 1 and C.orange_hi or C.orange
end

local function girlHeadColour(direction, x, localY, shade, boundary)
  if direction == "up" then
    return girlHairColour(shade, boundary)
  end

  local face = direction == "down"
      and localY >= 3 and localY <= 6 and x >= 5 and x <= 10
    or direction == "side"
      and localY >= 3 and localY <= 8 and x >= 5 and x <= 8

  if face then return toned(shade, C.skin, C.skin_shadow) end
  return girlHairColour(shade, boundary)
end

local function girlBodyColour(direction, x, localY, shade, boundary)
  if direction == "up" then
    if localY <= 9 and (x <= 3 or x >= 12) then
      return toned(shade, C.skin, C.skin_shadow)
    end
    return region(shade, boundary, C.teal_hi, C.teal, C.teal_dark)
  end

  if direction == "side" then
    if localY <= 10 and x <= 5 then
      return toned(shade, C.skin, C.skin_shadow)
    end
    if x >= 10 then
      return region(shade, boundary, C.teal_hi, C.teal, C.teal_dark)
    end
    if x == 7 then
      return accent(shade, C.red_hi, C.red, C.red_dark)
    end
    return region(shade, boundary, C.yellow_hi, C.yellow, C.yellow_dark)
  end

  if localY <= 9 and (x <= 3 or x >= 12) then
    return toned(shade, C.skin, C.skin_shadow)
  end
  -- The red suspenders start on the torso.  Beginning them at localY 7 put
  -- two red pixels directly against the bottom of Kris's face, which read as
  -- tears in the enlarged voxel view.
  if (x == 5 or x == 10) and localY >= 9 and localY <= 12 then
    return accent(shade, C.red_hi, C.red, C.red_dark)
  end
  return region(shade, boundary, C.yellow_hi, C.yellow, C.yellow_dark)
end

local function girlBikeColour(direction, x, localY, shade, boundary)
  if localY <= 11 then
    return girlBodyColour(direction, x, localY, shade, boundary)
  end

  local sideWheel = direction == "side" and (x <= 4 or x >= 11)
  if shade == 3 then return C.ink end
  if sideWheel then return shade == 1 and C.steel_hi or C.steel end
  if shade == 1 then return C.steel_hi end
  return C.red
end

local function colourGirlSheet(ctx, source, bike)
  local width, height = source:getDimensions()
  if width ~= 16 or height < 96 then return nil end
  local out = ctx.blank(width, height)

  for y = 0, 95 do
    local frame = math.floor(y / 16)
    local frameY = frame * 16
    local top = (not bike and frame >= 3) and 1 or 0
    local direction = DIRECTIONS[frame + 1]
    local localY = (y - frameY) - top
    local headEnd = direction == "side" and 9 or 6

    for x = 0, 15 do
      local r, _, _, a = source:getPixel(x, y)
      local shade = shadeIndex(r, a)
      if shade ~= 0 then
        local boundary = isBoundary(source, x, y, frameY)
        local colour

        if localY <= headEnd then
          colour = girlHeadColour(direction, x, localY, shade, boundary)
        elseif bike then
          colour = girlBikeColour(direction, x, localY, shade, boundary)
        elseif localY >= 14 then
          colour = accent(shade, C.red_hi, C.red, C.red_dark)
        elseif localY >= 12 then
          colour = region(shade, boundary,
            C.denim_hi, C.denim, C.denim_dark)
        else
          colour = girlBodyColour(direction, x, localY, shade, boundary)
        end

        put(out, x, y, colour)
      end
    end
  end

  return out
end

local function boyFishingColour(direction, x, localY, shade, boundary)
  local colour

  if localY <= 9 then
    if direction == "up" then
      colour = region(shade, boundary, C.hair_hi, C.hair, C.hair_dark)
    else
      colour = toned(shade, C.skin, C.skin_shadow)
      if direction == "side" and x >= 9 then
        colour = region(shade, boundary, C.hair_hi, C.hair, C.hair_dark)
      end
    end
  else
    if direction == "up" then
      colour = region(shade, boundary, C.green_hi, C.green, C.green_dark)
    else
      colour = region(shade, boundary, C.blue_hi, C.blue, C.navy)
    end
    if localY <= 12 and (x <= 3 or x >= 12) then
      colour = region(shade, boundary, C.green_hi, C.green, C.green_dark)
    end
    if localY >= 13 then
      colour = region(shade, boundary, C.denim_hi, C.denim, C.denim_dark)
    end
    if localY >= 14 then
      colour = region(shade, boundary, C.white, C.red, C.red_dark)
    end
  end

  if direction == "down" and (localY == 10 or localY == 11)
      and x >= 7 and x <= 8 then
    colour = shade == 3 and C.ink or C.navy
  end

  return colour
end

local function girlFishingColour(direction, x, localY, shade, boundary)
  local headEnd = direction == "side" and 9 or 6
  if localY <= headEnd then
    return girlHeadColour(direction, x, localY, shade, boundary)
  end
  if localY >= 14 then
    return accent(shade, C.red_hi, C.red, C.red_dark)
  end
  if localY >= 12 then
    return region(shade, boundary, C.denim_hi, C.denim, C.denim_dark)
  end
  return girlBodyColour(direction, x, localY, shade, boundary)
end

local function colourFishingPose(ctx, source, style, direction)
  local width, height = source:getDimensions()
  if width ~= 16 or height ~= 8 then return nil end
  local out = ctx.blank(width, height)

  for y = 0, 7 do
    local localY = y + 8
    for x = 0, 15 do
      local r, _, _, a = source:getPixel(x, y)
      local shade = shadeIndex(r, a)
      if shade ~= 0 then
        local boundary = isPoseBoundary(source, x, y)
        local colour = style == "cerulean"
          and girlFishingColour(direction, x, localY, shade, boundary)
          or boyFishingColour(direction, x, localY, shade, boundary)
        put(out, x, y, colour)
      end
    end
  end

  return out
end

return function(ctx)
  for _, sheet in ipairs(SHEETS) do
    if ctx.exists(sheet.path) then
      local colour = sheet.style == "cerulean"
        and colourGirlSheet or colourBoySheet
      local result = colour(ctx, ctx.readImage(sheet.path), sheet.bike)
      if result then ctx.writeImage(result, sheet.path) end
    end
  end

  for _, pose in ipairs(FISHING_POSES) do
    if ctx.exists(pose.path) then
      local result = colourFishingPose(ctx, ctx.readImage(pose.path),
        pose.style, pose.direction)
      if result then ctx.writeImage(result, pose.path) end
    end
  end
end
