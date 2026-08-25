-- The player's own OBJ palette in Prism, mixed by the character customiser.
--
-- Prism does not ship a sprite per appearance. It ships one sheet per model
-- and recolours it: PlayerCust_SetPalettes writes the chosen SkinTonePalettes
-- entry and the RGB15 the player mixed on the outfit sliders into the player's
-- OBJ palette, and every player sprite in the game -- walking, biking,
-- surfing, the trainer pic -- is drawn through it.
--
-- A Gen 2 OBJ palette is four colours and the sheets are four-shade art, so
-- the mapping is fixed and readable straight off any player sheet's own
-- gen2ObjPal (SPRITE_PLAYER0's is the canonical one):
--
--   [1]  index 0   -- transparent on hardware, never drawn
--   [2]  the SKIN
--   [3]  the OUTFIT
--   [4]  the outline, black
--
-- so customisation is entries 2 and 3, and 1 and 4 are inherited from whatever
-- sheet is being worn. That is the whole feature: the screen was already
-- writing save.player.skinTone and save.player.clothes, and nothing in the
-- game read either of them, so the choices were stored and never shown.

local PlayerPalette = {}

local MAX_LEVEL = 31

-- RGB15 (0-31 per channel, what the ROM stores and the sliders mix) to the
-- 0-255 triples getObpImage bakes with.
local function rgb8(c)
  if type(c) ~= "table" then return nil end
  local function ch(v)
    v = tonumber(v) or 0
    if v < 0 then v = 0 elseif v > MAX_LEVEL then v = MAX_LEVEL end
    return math.floor(v * 255 / MAX_LEVEL + 0.5)
  end
  return { ch(c.r), ch(c.g), ch(c.b) }
end
PlayerPalette.rgb8 = rgb8

local function tones(data)
  local field = data and data.field
  local cust = field and field.playerCustomization
  return cust and cust.skinTones or nil
end

-- Does this dataset recolour its player at all? Only Prism ships the table.
function PlayerPalette.available(data)
  local list = tones(data)
  return type(list) == "table" and list[1] ~= nil
end

-- The four colours to bake `base`'s sheet with, plus a cache key that changes
-- whenever they do. `base` is the sheet's own gen2ObjPal, which supplies the
-- two entries customisation does not own.
--
-- Returns nil when there is nothing to apply -- not Prism, no choice recorded
-- yet, or a sheet with no palette of its own to inherit the other two from --
-- and the caller then draws exactly as it always did.
function PlayerPalette.of(data, save, base)
  if not PlayerPalette.available(data) then return nil end
  if type(base) ~= "table" or #base < 4 then return nil end
  local player = save and save.player
  if type(player) ~= "table" then return nil end

  local list = tones(data)
  local index = tonumber(player.skinTone)
  local skin = index and list[index] and rgb8(list[index]) or nil
  local clothes = rgb8(player.clothes)
  if not (skin or clothes) then return nil end

  local colors = { base[1], skin or base[2], clothes or base[3], base[4] }
  -- The key carries the SHEET as well as the mix: two models wearing the same
  -- colours are still two different bakes, and one model in two mixes must not
  -- collide either.
  local key = string.format("%s|%d,%d,%d|%d,%d,%d",
    tostring(index or "-"),
    colors[2][1], colors[2][2], colors[2][3],
    colors[3][1], colors[3][2], colors[3][3])
  return colors, key
end

-- IS THIS SHEET THE PLAYER'S TO RECOLOUR?
--
-- The customised palette belongs to the CHARACTER, not to whatever sheet the
-- player object happens to be wearing. Prism's Pokemon mode makes that
-- distinction load-bearing: with ENGINE_POKEMON_MODE set the player wears a
-- species sheet (SPRITE_MON_246 and the like), and that sheet's palette is the
-- Pokemon's own -- Larvitar's green. Painting the player's skin tone and
-- outfit over entries 2 and 3 of it turns Larvitar red.
--
-- So the test is membership: a sheet is customisable when the dataset names it
-- as part of a player FORM (walk / bike / surf / back / ...). A species sheet
-- is not in that table, and neither is any fallback the sprite picker reached
-- for, so both keep the colours they shipped with.
local formSheets = nil
local formSheetsFor = nil
function PlayerPalette.ownsSheet(data, spriteId)
  if type(spriteId) ~= "string" then return false end
  local field = data and data.field
  local forms = field and field.playerForms
  if type(forms) ~= "table" then return false end
  if formSheets == nil or formSheetsFor ~= forms then
    formSheets, formSheetsFor = {}, forms
    for _, form in pairs(forms) do
      if type(form) == "table" then
        for _, v in pairs(form) do
          if type(v) == "string" then formSheets[v] = true end
        end
      end
    end
  end
  return formSheets[spriteId] == true
end

-- Apply it to a SpriteRenderer, or clear the override when this dataset does
-- not customise, or when the sheet is not the character's. Safe on a nil
-- sprite so callers need no guard of their own.
function PlayerPalette.apply(sprite, data, save)
  if not (sprite and sprite.setPalette) then return false end
  local id = sprite.def and sprite.def.id
  if not PlayerPalette.ownsSheet(data, id) then
    sprite:setPalette(nil, nil)
    return false
  end
  local colors, key = PlayerPalette.of(data, save, sprite.def and sprite.def.gen2ObjPal)
  if colors then
    sprite:setPalette(colors, (sprite.def and sprite.def.id or "?") .. "|" .. key)
    return true
  end
  sprite:setPalette(nil, nil)
  return false
end

return PlayerPalette
