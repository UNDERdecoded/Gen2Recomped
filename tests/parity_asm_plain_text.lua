-- Parity test: text_asm entries that wrap nothing but a string still print.
--
-- A handful of pokered's text labels are plain `text_far _Label / text_end`
-- wrappers with no logic at all: BoulderText (home/overworld_text.asm:16)
-- prints _BoulderText, "This requires STRENGTH to move!", and the mart and
-- Pokemon Center signs work the same way.  The extractor cannot follow asm,
-- so it records those pointers as `asm = true` with a label and no text,
-- and Data:resolveText used to return nil for them -- every boulder and
-- every mart/center sign in the game answered an A press with silence
-- (#318).
--
-- The fallback is keyed on the extractor having recovered a _Label string,
-- which is exactly the set of wrappers that carry no behavior.  Labels whose
-- asm really does branch (Agatha's pre-battle script, the mansion switch)
-- have no such string, so they still resolve to nil and still fall through
-- to their hand-ported script in data/scripts/.
--
-- Self-contained; run via `luajit tests/parity_asm_plain_text.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity asm plain text")
local check, eq = S.check, S.eq

local Data = require("src.core.Data")
if not Data.maps then Data:load() end

-- the plain wrappers: a string comes back, and needsAsm is false because
-- there is no script left to port
local PLAIN = {
  { "SeafoamIslands1F", "TEXT_SEAFOAMISLANDS1F_BOULDER1", "STRENGTH" },
  { "SeafoamIslands1F", "TEXT_SEAFOAMISLANDS1F_BOULDER2", "STRENGTH" },
  { "CinnabarIsland",   "TEXT_CINNABARISLAND_POKECENTER_SIGN", nil },
  { "Route10",          "TEXT_ROUTE10_POKECENTER_SIGN",        nil },
  { "CinnabarIsland",   "TEXT_CINNABARISLAND_MART_SIGN",       nil },
  { "ViridianCity",     "TEXT_VIRIDIANCITY_MART_SIGN",         nil },
}
for _, row in ipairs(PLAIN) do
  local mapLabel, const, fragment = row[1], row[2], row[3]
  local text, needsAsm = Data:resolveText(mapLabel, const)
  check(type(text) == "string" and text ~= "",
        mapLabel .. "/" .. const .. " resolves to a string")
  check(not needsAsm,
        mapLabel .. "/" .. const .. " needs no hand-ported script")
  if fragment then
    check(text:find(fragment, 1, true) ~= nil,
          mapLabel .. "/" .. const .. " is the real text (" .. fragment .. ")")
  end
end

eq(Data:resolveText("SeafoamIslands1F", "TEXT_SEAFOAMISLANDS1F_BOULDER1"),
   Data.text._BoulderText,
   "the boulder prints _BoulderText verbatim")

-- a wrapper whose asm really branches stays unresolved, so showMapText
-- keeps preferring the hand-ported script
local agatha, agathaAsm = Data:resolveText("AgathasRoom", "TEXT_AGATHASROOM_AGATHA")
eq(agatha, nil, "a logic-bearing text_asm entry still resolves to nil")
check(agathaAsm, "and is still reported as needing asm")

-- an entry the extractor gave a real text field keeps taking that path
local entry = Data:textEntry("PalletTown", "TEXT_PALLETTOWN_SIGN")
if entry and entry.text then
  eq(Data:resolveText("PalletTown", "TEXT_PALLETTOWN_SIGN"),
     Data.text[entry.text], "a plain text entry is unaffected")
end

S.finish()
