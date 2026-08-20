-- INDIGO//97
--
-- transforms.lua writes full-colour versions of the player's own imported
-- sheets under save/mod-derived/indigo_97. Keeping the original image paths
-- lets the asset resolver select those derived copies automatically.
return function(mod)
  local sprites = {
    { id = "SPRITE_RED", required = true },
    { id = "SPRITE_RED_BIKE", required = true },
    { id = "SPRITE_KRIS", required = false },
    { id = "SPRITE_KRIS_BIKE", required = false },
  }

  for _, sprite in ipairs(sprites) do
    if mod.content.sprites:get(sprite.id) then
      -- Patch only the colour contract. Image, frame count, walker metadata
      -- and ROM-hack-specific fields remain whatever the merged game supplied.
      mod.content.sprites:patch(sprite.id, { trueColor = true })
    elseif sprite.required then
      mod.log:warn("%s is unavailable; import a supported Gen 2 ROM and reload",
        sprite.id)
    end
  end
end

