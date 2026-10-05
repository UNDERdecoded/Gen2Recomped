-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE "!" OVER A TRAINER WHO HAS SEEN YOU, and the "!!" of a Vs. Seeker
-- rematch.
--
-- `MovementAction_EmoteExclamationMark` (pokeplatinum src/unk_020655F4.c)
-- starts the emote field effect (src/overlay005/ov5_021F5A10.c), which loads
-- its billboard out of `/data/mmodel/fldeff.narc`: model member 85 for the
-- "!" -- texture `sisen_ef`, "line of sight" -- and 108 for the "!!",
-- `saisen_ef`, "rematch". Each is a 16x16 white speech bubble with the mark
-- in red, and each model carries its own TEX0, so the picture comes straight
-- out of the model as the player's shadow does (see `extractField`).
--
-- Stored as raw RGBA rather than a PNG so a cache can gain it without LOVE:
-- 1 KB each, and the runtime turns them into images when first drawn.

local Gen4Emotes = {}

Gen4Emotes.ARCHIVE = "/data/mmodel/fldeff.narc"
Gen4Emotes.MEMBERS = { exclamation = 85, double = 108 }

-- Where it hangs and how it moves (ov5_021F5A10.c): the billboard's plane
-- spans 0..16 up from its anchor (measured off model 85), and the anchor is
-- the owner's drawn position + 32 units -- the top of a 32-unit character.
-- It rises 6, 10, 12, 12, 10, 6, 0 over seven frames (velocity 6, less 2 a
-- frame, stopping at 0), then holds 30.
Gen4Emotes.LIFT = 32
Gen4Emotes.BOUNCE = { 6, 10, 12, 12, 10, 6, 0 }
Gen4Emotes.HOLD = 30
Gen4Emotes.FRAMES = #Gen4Emotes.BOUNCE + Gen4Emotes.HOLD

function Gen4Emotes.extract(arc)
  local Nsbmd = require("src.import.Gen4Nsbmd")
  local Models = require("src.import.Gen4Models")
  local out = {}
  for key, member in pairs(Gen4Emotes.MEMBERS) do
    local bytes = arc and member < arc.count and arc:get(member)
    local sections = bytes and Nsbmd.sections(bytes)
    local parsed = sections and sections.TEX0 and Models.parse(bytes, sections.TEX0)
    local image = parsed and Models.decode(parsed, bytes, 1, 1)
    if image then
      out[key] = { width = image.width, height = image.height, rgba = image.rgba,
                   member = member,
                   texture = parsed.textures[1] and parsed.textures[1].name or nil }
    end
  end
  if not out.exclamation then return nil, "fldeff member 85 would not decode" end
  return out
end

-- The bounce offset, in units, `age` frames after the emote appeared.
function Gen4Emotes.bounce(age)
  age = math.floor(tonumber(age) or 0)
  if age < 1 then return 0 end
  return Gen4Emotes.BOUNCE[age] or 0
end

return Gen4Emotes
