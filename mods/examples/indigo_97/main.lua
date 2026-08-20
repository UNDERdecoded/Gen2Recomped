-- INDIGO//97
--
-- transforms.lua writes full-colour versions of the player's own imported
-- sheets under save/mod-derived/indigo_97. Keeping the original image paths
-- lets the asset resolver select those derived copies automatically.
return function(mod)
  for _, id in ipairs({ "SPRITE_RED", "SPRITE_RED_BIKE" }) do
    if mod.content.sprites:get(id) then
      -- Patch only the colour contract. Image, frame count, walker metadata
      -- and ROM-hack-specific fields remain whatever the merged game supplied.
      mod.content.sprites:patch(id, { trueColor = true })
    else
      mod.log:warn("%s is unavailable; import a supported Gen 2 ROM and reload", id)
    end
  end
end

