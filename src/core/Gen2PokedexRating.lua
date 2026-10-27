-- Adapted from Gen1Recomp 535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91.
-- Existing project rights and Gen1Recomp provenance remain applicable; see LICENSE.MD.
local Strings = require("src.core.Strings")
local OAK_PC_TEXT = {
  completion = Strings.source("Current #DEX\ncompletion level:"),
  counts = Strings.source(
    "%d #MON seen\n%d #MON owned\fPROF.OAK's\nRating:"),
}

-- OakRatings (data/events/pokedex_ratings.asm).  Each row is (cap, sfx,
-- text); FindOakRating walks the table with `cp c / jr nc, .match` against
-- ascending caps, which is "the first row whose cap covers the caught
-- count" -- exactly what findOakRating below does.  sfx is the Gold sfx
-- table's own label (audio/sfx_pointers.asm dba lines), not a pokered
-- fanfare name.
local OAK_RATINGS = {
  { max = 9, sfx = "Sfx_DexFanfareLessThan20", text = Strings.source(
    "Look for #MON\nin grassy areas!") },
  { max = 19, sfx = "Sfx_DexFanfareLessThan20", text = Strings.source(
    "Good. I see you\nunderstand how to\vuse # BALLS.") },
  { max = 34, sfx = "Sfx_DexFanfare2049", text = Strings.source(
    "You're getting\ngood at this.\fBut you have a\nlong way to go.") },
  { max = 49, sfx = "Sfx_DexFanfare2049", text = Strings.source(
    "You need to fill\nup the #DEX.\fCatch different\nkinds of #MON!") },
  { max = 64, sfx = "Sfx_DexFanfare5079", text = Strings.source(
    "You're trying--I\ncan see that.\fYour #DEX is\ncoming together.") },
  { max = 79, sfx = "Sfx_DexFanfare5079", text = Strings.source(
    "To evolve, some\n#MON grow,\fothers use the\neffects of STONES.") },
  { max = 94, sfx = "Sfx_DexFanfare80109", text = Strings.source(
    "Have you gotten a\nfishing ROD? You\fcan catch #MON\nby fishing.") },
  { max = 109, sfx = "Sfx_DexFanfare80109", text = Strings.source(
    "Excellent! You\nseem to like col-\vlecting things!") },
  { max = 124, sfx = "Sfx_CaughtMon", text = Strings.source(
    "Some #MON only\nappear during\fcertain times of\nthe day.") },
  { max = 139, sfx = "Sfx_CaughtMon", text = Strings.source(
    "Your #DEX is\nfilling up. Keep\vup the good work!") },
  { max = 154, sfx = "Sfx_DexFanfare140169", text = Strings.source(
    "I'm impressed.\nYou're evolving\f#MON, not just\ncatching them.") },
  { max = 169, sfx = "Sfx_DexFanfare140169", text = Strings.source(
    "Have you met KURT?\nHis custom #\vBALLS should help.") },
  { max = 184, sfx = "Sfx_DexFanfare170199", text = Strings.source(
    "Wow. You've found\nmore #MON than\fthe last #DEX\nresearch project.") },
  { max = 199, sfx = "Sfx_DexFanfare170199", text = Strings.source(
    "Are you trading\nyour #MON?\fIt's tough to do\nthis alone!") },
  { max = 214, sfx = "Sfx_DexFanfare200229", text = Strings.source(
    "Wow! You've hit\n200! Your #DEX\vis looking great!") },
  { max = 229, sfx = "Sfx_DexFanfare200229", text = Strings.source(
    "You've found so\nmany #MON!\fYou've really\nhelped my studies!") },
  { max = 239, sfx = "Sfx_DexFanfare230Plus", text = Strings.source(
    "Magnificent! You\ncould become a\f#MON professor\nright now!") },
  { max = 248, sfx = "Sfx_DexFanfare230Plus", text = Strings.source(
    "Your #DEX is\namazing! You're\fready to turn\nprofessional!") },
  -- The top band (251 real species, the table's cap of 255 covers it): this
  -- is the ONLY place the ROM checks "has the player finished the #DEX", and
  -- it does it here rather than handing off to anything.  The actual diploma
  -- is not this special's business -- GameFreakGameDesignerScript in
  -- Celadon Mansion 3F reads VAR_DEXCAUGHT for itself and is what runs
  -- `special Diploma` (H.Diploma below, src/ui/gen2/Diploma.lua) and
  -- then sets EVENT_ENABLE_DIPLOMA_PRINTING for the Graphic Artist's
  -- `special PrintDiploma` (H.PrintDiploma, specials/crystal_extras.lua).
  -- A finished #DEX here just means every rating after this one is this
  -- same line.
  { max = 255, sfx = "Sfx_DexFanfare230Plus", text = Strings.source(
    "Whoa! A perfect\n#DEX! I've\fdreamt about this!\nCongratulations!") },
}

-- CountSetBits over wPokedexSeen/wPokedexCaught.  The port's dex is a
-- species-keyed bool map (src/core/gen2/Save.lua), not a bitfield, so this
-- counts `true` entries the same way Save.summary counts wPokedexCaught for
-- the CONTINUE panel.
local function dexCounts(record)
  local dex = record and record.pokedex
  local seen, caught = 0, 0
  for _, has in pairs((dex and dex.seen) or {}) do
    if has then seen = seen + 1 end
  end
  for _, has in pairs((dex and dex.owned) or {}) do
    if has then caught = caught + 1 end
  end
  return seen, caught
end

-- FindOakRating.  NUM_POKEMON is 251, so `caught` never exceeds the table's
-- own top cap of 255 and this never falls off the end.
local function findOakRating(caught)
  for _, row in ipairs(OAK_RATINGS) do
    if caught <= row.max then return row end
  end
  return OAK_RATINGS[#OAK_RATINGS]
end

return {OAK_PC_TEXT=OAK_PC_TEXT,dexCounts=dexCounts,findOakRating=findOakRating}
