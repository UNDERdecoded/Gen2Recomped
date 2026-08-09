-- BikeShop (BIKE_SHOP) flavor dialogue
-- Source: pokered/scripts/BikeShop.asm, pokered/text/BikeShop.asm
--
-- TEXT_BIKESHOP_CLERK lives in data/scripts/story2.lua (M.BIKE_SHOP): the
-- voucher exchange and the BICYCLE/CANCEL price window need more than
-- command rows (#568).

return {
  BIKE_SHOP = {
    talk = {
      -- BikeShopMiddleAgedWomanText (pokered/scripts/BikeShop.asm):
      -- always shows the same flavor line, no branching.
      TEXT_BIKESHOP_MIDDLE_AGED_WOMAN = {
        { "face_player" },
        { "show_text", "_BikeShopMiddleAgedWomanText" },
      },

      -- BikeShopYoungsterText (pokered/scripts/BikeShop.asm):
      -- CheckEvent EVENT_GOT_BICYCLE ; jr nz, .gotBike
      -- before the player owns a bike -> TheseBikesAreExpensiveText
      -- after the player owns a bike  -> CoolBikeText
      -- The check reads the bag, not the event: the port hands out the
      -- BICYCLE itself (a key item, so it cannot be tossed), and that also
      -- reads right on saves written before the clerk set the event (#567).
      TEXT_BIKESHOP_YOUNGSTER = {
        { "face_player" },                                            -- 1
        { "check_item", "BICYCLE" },                                  -- 2
        { "jump_if_true", 6 },                                        -- 3
        { "show_text", "_BikeShopYoungsterTheseBikesAreExpensiveText" }, -- 4
        { "jump", "end" },                                            -- 5
        { "show_text", "_BikeShopYoungsterCoolBikeText" },            -- 6
      },
    },
  },
}
