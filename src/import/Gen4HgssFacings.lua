-- HEARTGOLD AND SOULSILVER'S ANIMATION SEQUENCE TABLES, by name.
--
-- Platinum stores its twenty-five at the END of mmodel.narc and
-- Gen4Facings.read walks them back from there. HGSS's are seventeen members in
-- the MIDDLE -- 280..296 of /a/0/8/1, after the fourteen NSBMD models at
-- 266..279 and before the walking-partner sheets -- and pret names none of them
-- (files/data/mmodel/mmodel_00000280.json onward).
--
-- THE NAMES ARE PROVEN BY IDENTITY, not guessed: each member below is BYTE FOR
-- BYTE the Platinum table of that name (tools/gen4_hgss_import_check.lua
-- re-reads both cartridges and compares). The two games inherited them from
-- Diamond and Pearl. Members with no Platinum twin keep a neutral name.
-- (285 repeats `surf` and 286 repeats `generic_walk`; the first of each is
-- the one named.)

local Facings = require("src.import.Gen4Facings")

local F = {}

F.FIRST, F.LAST = 280, 296
F.NAMES = {
  [280] = "generic_walk", [281] = "walk_and_run", [282] = "bike", [283] = "surf",
  [284] = "spray_duck", [285] = "hgss_285", [286] = "hgss_286", [287] = "hgss_287",
  [288] = "pokecenter_nurse", [289] = "poketch", [290] = "save", [291] = "heal_pokecenter",
  [292] = "hgss_292", [293] = "hgss_293", [294] = "hgss_294", [295] = "hgss_295",
  [296] = "hgss_296",
}

-- WHICH SHEET USES A SEQUENCE THE TEXTURE COUNT CANNOT NAME. Platinum tells the
-- nurse apart by her sheet's label (Gen4Facings BY_NAME); HGSS's sheets are
-- unnamed, so the 17-texture nurse matched nothing and kept the renderer's
-- classic slots -- slot 0, "standing south", is her BACK, and every Johto
-- Pokemon Center nurse faced the wall. The cartridge's sprite table
-- (overlay 1, pret overlay_01_sprite_data.s) gives SPRITE_PCWOMAN1 /
-- MMODEL_PCWOMAN1 = member 133 her own animation, the only object that uses
-- it; it is the table byte-identical to Platinum's `pokecenter_nurse`.
F.BY_MEMBER = { [133] = "pokecenter_nurse" }

-- read(arc) -> byName, report: the same shape as Gen4Facings.read
function F.read(arc)
  local byName, report = {}, { found = 0 }
  if not arc or not arc.count then return byName, report end
  for member = F.FIRST, math.min(F.LAST, arc.count - 1) do
    local seq, why = Facings.parse(arc:get(member))
    if seq then
      seq.member = member
      seq.name = F.NAMES[member]
      byName[seq.name] = seq
      report.found = report.found + 1
    else
      report.refused = report.refused or {}
      report.refused[member] = why
    end
  end
  report.complete = report.found == F.LAST - F.FIRST + 1
  return byName, report
end

return F
