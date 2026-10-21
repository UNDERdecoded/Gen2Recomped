return function(mod)
  mod.log:info("Loaded: 251 All Catchable Mod")

  -- Helper to inject species into all time slots of a map
  local function injectAllTimes(mapEncounters, slotIndex, speciesId, level)
    if not mapEncounters or not mapEncounters.grass then return end
    local g = mapEncounters.grass

    -- Day / Default slots
    if g.slots and g.slots[slotIndex] then
      g.slots[slotIndex].species = speciesId
      if level then g.slots[slotIndex].level = level end
    end

    -- Morning and Night sub-tables
    if g.byTime then
      if g.byTime.morn and g.byTime.morn.slots and g.byTime.morn.slots[slotIndex] then
        g.byTime.morn.slots[slotIndex].species = speciesId
        if level then g.byTime.morn.slots[slotIndex].level = level end
      end
      if g.byTime.nite and g.byTime.nite.slots and g.byTime.nite.slots[slotIndex] then
        g.byTime.nite.slots[slotIndex].species = speciesId
        if level then g.byTime.nite.slots[slotIndex].level = level end
      end
    end
  end

  mod.events:on("data.loaded", function(data)
    local enc = data.encounters
    if not enc then return end

    -- 1. Johto Starters (Route 29, 30, 31 - Slot 7 in all timeframes)
    injectAllTimes(enc.MAP_ROUTE_29 or enc.ROUTE_29, 7, "SPECIES_152", 4) -- Chikorita
    injectAllTimes(enc.MAP_ROUTE_30 or enc.ROUTE_30, 7, "SPECIES_155", 4) -- Cyndaquil
    injectAllTimes(enc.MAP_ROUTE_31 or enc.ROUTE_31, 7, "SPECIES_158", 4) -- Totodile

    -- 2. Kanto Starters (Route 2, 3, 24)
    injectAllTimes(enc.MAP_ROUTE_2 or enc.ROUTE_2, 7, "SPECIES_001", 10)  -- Bulbasaur
    injectAllTimes(enc.MAP_ROUTE_3 or enc.ROUTE_3, 7, "SPECIES_004", 10)  -- Charmander
    injectAllTimes(enc.MAP_ROUTE_24 or enc.ROUTE_24, 7, "SPECIES_007", 10) -- Squirtle

    -- 3. Version Exclusives & Missing Crystal Mons
    injectAllTimes(enc.MAP_ROUTE_32 or enc.ROUTE_32, 6, "SPECIES_179", 7) -- Mareep
    injectAllTimes(enc.MAP_ROUTE_36 or enc.ROUTE_36, 6, "SPECIES_037", 14) -- Vulpix
    injectAllTimes(enc.MAP_ROUTE_42 or enc.ROUTE_42, 6, "SPECIES_056", 16) -- Mankey
    injectAllTimes(enc.MAP_ROUTE_38 or enc.ROUTE_38, 6, "SPECIES_203", 16) -- Girafarig

    -- 4. Eevee near Daycare
    injectAllTimes(enc.MAP_ROUTE_34 or enc.ROUTE_34, 7, "SPECIES_133", 12) -- Eevee

    -- 5. Fossils in Ruins of Alph Outside
    injectAllTimes(enc.MAP_RUINS_OF_ALPH_OUTSIDE or enc.RUINS_OF_ALPH_OUTSIDE, 5, "SPECIES_138", 20) -- Omanyte
    injectAllTimes(enc.MAP_RUINS_OF_ALPH_OUTSIDE or enc.RUINS_OF_ALPH_OUTSIDE, 6, "SPECIES_140", 20) -- Kabuto
    injectAllTimes(enc.MAP_RUINS_OF_ALPH_OUTSIDE or enc.RUINS_OF_ALPH_OUTSIDE, 7, "SPECIES_142", 22) -- Aerodactyl
  end)
end