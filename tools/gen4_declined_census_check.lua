-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE CENSUS THAT CHOOSES THE PASSES, WITH THE TWO FAULTS IT HAD TAKEN OUT.
--
-- `claude/gen4_declined_subjects.md` ranks every command lowered onto a
-- `g4_noop` or a `g4_no_feature` by how much of the cartridge's script corpus
-- asks for it.  Five passes have been chosen off that ranking.  It was wrong
-- in two ways, and both ways were invisible from the numbers themselves.
--
-- FAULT ONE: THE WALK COUNTS DECODES, NOT POSITIONS.  The corpus walk queues
-- every entry point and every jump target, and a block entered at one address
-- is decoded again from a second address inside it -- so an instruction in an
-- overlapping tail is counted once per path that reaches it.  Measured here:
-- 78,189 decodes over 57,333 distinct byte positions, 36% inflation across
-- 132 of the bands.  Per subject it ran as high as 5x (`the seal case`, five
-- decodes of one position) and 80% of the TV system's 41.
--
-- Neither number is wrong; they answer different questions.  Decodes weight a
-- subject by how many reachable paths lead to it, positions by how much of the
-- corpus names it.  The doc presented decodes as "invocations", which reads as
-- the second, so this tool reports BOTH and the ranking uses positions.
--
-- FAULT TWO: A SUBJECT SPLIT ACROSS SEVERAL SPELLINGS RANKS AS SEVERAL
-- SUBJECTS.  The census reads each row's subject out of the prose in its
-- `g4_noop` row, and the eight `initpersistedmapfeaturesfor*` commands name
-- eight different subjects -- "the Distortion World persisted map feature",
-- "the Eterna Gym persisted map feature", and so on.  They are one mechanism
-- behind nine thin wrappers over `PersistedMapFeatures_InitFor*`.  Ranked
-- apart they came out 11, 9, 4, 3, 1, 1, 1, 1 and the largest sat eleventh;
-- ranked together, with the gym buttons and the flower clock that write the
-- same state, they are the second-largest open subject in the whole census.
--
-- That is this project's recurring bug -- the same thing spelled differently
-- in two places that never meet -- eating the measurement that is supposed to
-- find it.
--
-- So the classification is checked rather than inferred: every subject this
-- tool sees must be either in KNOWN or named by MERGES, and an unclassified
-- one FAILS with its own name and count.  A new stub row therefore cannot
-- enter the ranking until somebody has said what it belongs to, and a MERGES
-- entry that no row uses any more fails as well, so the table cannot rot.
--
-- Run:  texlua tools/gen4_declined_census_check.lua <rom> [pokeplatinum]

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local ROM  = arg and arg[1]
local PRET = arg and arg[2]

local fails, checks, reports, skips = 0, 0, 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end
local function report(fmt, ...)
  reports = reports + 1
  io.write("REPORT: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function skip(fmt, ...)
  skips = skips + 1
  io.write("SKIP: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
end
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(p)
  if not p then return nil end
  local f = io.open(p, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
local function loadTable(dir, name)
  if not dir then return nil end
  local f = loadfile(dir .. "/" .. name .. ".lua")
  if not f then return nil end
  local okRun, t = pcall(f)
  return okRun and t or nil
end
local function code(src)
  if not src then return "" end
  return (src:gsub("%-%-%[%[.-%]%]", " "):gsub("%-%-[^\r\n]*", " "))
end
local function cdefn(src, name)
  return src and src:match("[%w_%*%s]-" .. name .. "%s*%b()%s*\n{(.-)\n}")
end


local Script = require("src.import.Gen4Script")
local NdsRom = require("src.import.NdsRom")
local Narc   = require("src.import.NarcArchive")

-- ---------------------------------------------------------------------------
-- The classification.  MERGES names the prose variants that are one subject;
-- KNOWN is everything else the census currently sees.  Both are argued lists
-- rather than guesses, and section 3 fails on anything in neither.
-- ---------------------------------------------------------------------------
local MERGES = {
  -- ELEVEN OF THESE TWELVE ENTRIES ARE GONE, and the stale-entry assertion in
  -- section 3 is what took them out.
  --
  -- The merge did its job: it made "persisted map features" a top-two subject
  -- at 53 sites, pass 189 built the slot behind it, and the eleven rows that
  -- used to lower to `g4_noop` now lower to `g4_map_feature_init`,
  -- `g4_pastoria_button`, `g4_sunyshore_gear_button` and
  -- `g4_eterna_clock_advance`.  They name no subject any more, so their merge
  -- entries named prose no row used -- which this tool FAILED on, by design,
  -- the moment the rows changed.  A merge table is a claim about the present.
  --
  -- `platform lift` stays: `triggerplatformlift` is still a declared no-op
  -- (the nine Stark Mountain and League rooms are walkable without it), and
  -- it is now the subject's only row.
  ["platform lift"]                          = "persisted map features",
  -- ONE JOURNAL. Two rows, one word of prose apart.
  ["journal entry"] = "journal",
  -- ("shard move tutor" -> "move tutor" is gone: the shard tutors and
  -- Route 210's Draco Meteor tutor both lower to real commands now.)
  -- ONE APPEARANCE SYSTEM, which the trainer card derives a class from.
  ["trainer appearance variants"] = "trainer appearance",
  ["trainer appearance system"]   = "trainer appearance",
  -- (The two "spear pillar" entries that used to live here are gone: pass 182
  -- found that three of those four rows were named after the map they appear
  -- on rather than what they do -- two ordinary object operations and a hang --
  -- and renamed them. This check's stale-entry assertion is what flagged the
  -- merge table the moment that happened, which is the whole point of it.)
}

local KNOWN = {
  ["a bgm fade"] = true, ["a cartridge no-op"] = true,
  ["a distortion world cast member"] = true, ["a hidden location marker"] = true,
  ["a sequence volume"] = true, ["a subscene change"] = true,
  ["a wait for a or b"] = true, ["a weather task"] = true,
  ["an object query"] = true, ["an object status flag"] = true,
  ["stored exit location"] = true,
  -- pass 182: named for the mechanism, and both argued in Gen4ScriptVM
  ["object-vs-object solidity"] = true,
  ["a full-screen child application"] = true,
  ["amity square accessories"] = true, ["amity square step count"] = true,
  ["boat cutscene"] = true, ["canalave library tv"] = true,
  ["contest accessories"] = true, ["contest backdrops"] = true,
  ["contest photos"] = true, ["cycling bgm override"] = true,
  ["daily random level"] = true, ["daily swarms"] = true,
  ["deoxys forms"] = true, ["distortion world camera angles"] = true,
  ["distortion world warp"] = true, ["door animation's wait"] = true,
  ["elevator animation"] = true,
  ["field map teardown, which the warp owns here"] = true,
  ["giratina shadow event"] = true, ["giratina's forms"] = true,
  ["great marsh lookout"] = true, ["great marsh safari game"] = true,
  ["hall of fame healing animation"] = true, ["journal"] = true,
  ["jubilife lottery"] = true, ["lake guardian containment units"] = true,
  ["lift's current-floor window"] = true, ["mailbox"] = true,
  ["menu anchor side"] = true, ["move tutor"] = true, ["slot machine"] = true, ["contest camera flashes"] = true, ["contest attire"] = true,
  ["mystery gift distribution events"] = true, ["national dex diploma"] = true,
  ["persisted map features"] = true, ["player-state latch"] = true,
  -- pass 189, both named rather than left on the unknown-command path, and
  -- both argued in Gen4ScriptVM: the player's dynamic height calculation is
  -- twelve sites in ONE member (497, the Great Marsh tram) and has nothing to
  -- disable in a port with no player height; the Hearthome lift is Diamond
  -- and Pearl's gym, left in Platinum's overlay with two callers.
  ["player's dynamic height calculation"] = true,
  ["hearthome gym lift, which is diamond and pearl's gym"] = true,
  ["poffin case"] = true, ["pokemon news press"] = true,
  ["prop animations"] = true, ["scripted blackout"] = true,
  ["scripted start-menu prompt"] = true, ["seal case"] = true,
  ["sinnoh diploma"] = true, ["size contest record"] = true,
  ["spiritomb counter"] = true, ["step-counter freeze"] = true,
  ["trainer appearance"] = true, ["trainer card"] = true,
  ["trainer encounter jingle"] = true, ["trainer score records"] = true,
  ["tv broadcast system"] = true, ["underground"] = true,
}

-- ---------------------------------------------------------------------------
section("1. the subjects, read out of the VM rather than from a list")
-- ---------------------------------------------------------------------------
local vmSrc = slurp("src/script/Gen4ScriptVM.lua")
            or slurp("../src/script/Gen4ScriptVM.lua")
ok(vmSrc ~= nil, "could not read Gen4ScriptVM.lua; nothing below means anything")
if not vmSrc then
  io.write(("\n%d checks, %d failed, %d reported, %d skipped\n")
             :format(checks, fails, reports, skips))
  os.exit(1)
end

local function normalise(prose)
  local p = prose:lower()
  p = p:gsub("%s*%b()%s*$", "")
  p = p:gsub("^the%s+", "")
  p = p:gsub("%s+", " ")
  return (p:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Walk `L.<name> = ...` rows and keep the ones whose body names a stub verb,
-- following `L.x = L.y` aliases. Asking the source is the only way to see the
-- subject prose, which lives nowhere else -- but the SET of lowered commands
-- is asked of the real table below, because a textual census of a behavioural
-- table under-reports (the berry-tree loop).
--
-- THE ROW IS SLICED BETWEEN CONSECUTIVE `L.<name> =` BOUNDARIES, not matched
-- as `function.-\nend`. Many rows are one-liners with no `\nend` of their own,
-- so a lazy match ran past them and attributed the NEXT row's subject to them:
-- the first draft of this tool found 77 rows instead of 105 and reported a
-- one-row subject at 179 sites, having swallowed a whole block of other rows.
-- That is this file's own shape 3a -- a pattern that matched the wrong thing
-- and therefore graded a subject it never located.
local stub, subject, unnamed = {}, {}, 0
do
  local body = code(vmSrc)
  -- BOTH SPELLINGS. `L.name =` and `L["name"] =` are the same table, and a
  -- scan that reads only the dotted one silently drops every row whose opcode
  -- has no name (`L["338"]`, `L["0a8"]`) -- five of them, which is harmless
  -- for a "no holes" assertion and wrong for a ranking, exactly as shape 3 of
  -- claude/check_design_lessons.md has it.
  local starts = {}
  local pos = 1
  while true do
    local a, b, name = body:find("\nL%.([a-z0-9_]+)%s*=", pos)
    local a2, b2, name2 = body:find('\nL%["([a-z0-9_]+)"%]%s*=', pos)
    if a2 and (not a or a2 < a) then a, b, name = a2, b2, name2 end
    if not a then break end
    starts[#starts + 1] = { at = a, after = b, name = name }
    pos = b
  end
  table.sort(starts, function(x, y) return x.at < y.at end)
  for i = 1, #starts do
    local name = starts[i].name
    local stop = (starts[i + 1] and starts[i + 1].at) or #body
    local rest = body:sub(starts[i].after + 1, stop)
    local alias = rest:match("^%s*L%.([a-z0-9_]+)")
    if alias then
      subject[name] = alias  -- resolved after the sweep
      stub[name] = "alias"
    elseif rest:find("g4_noop", 1, true) or rest:find("g4_no_feature", 1, true) then
      stub[name] = true
      local prose = rest:match('"g4_noop"[^}]-"([^"]+)"')
                 or rest:match('"g4_no_feature"[^}]-"([^"]+)"')
      if prose and #prose >= 4 then subject[name] = normalise(prose)
      else subject[name] = ""; unnamed = unnamed + 1 end
    end
  end
  -- resolve aliases, dropping the ones that point at a row with no stub
  for name, kind in pairs(stub) do
    if kind == "alias" then
      local target = subject[name]
      if stub[target] == true then subject[name] = subject[target]
      else stub[name] = nil; subject[name] = nil end
    end
  end
end
local stubCount = 0
for _ in pairs(stub) do stubCount = stubCount + 1 end
-- A FLOOR ON THE SCAN'S OWN INPUT. A pattern that stops matching reports a
-- clean zero over nothing at all, and an empty census ranks nothing and says
-- the backlog is clear.
-- (90 until the move tutors, Move Reminder and Move Deleter were lowered;
-- the floor follows the backlog down, it is not a target.)
ok(stubCount >= 60,
   "only %d commands were found on a stub verb; the census has been reading "
   .. "an empty set, which looks like an empty backlog", stubCount)
report("%d commands on g4_noop/g4_no_feature, %d of them naming no subject",
       stubCount, unnamed)

-- AND THE SET IS CONFIRMED AGAINST THE REAL TABLE, not just the source.
local VM = require("src.script.Gen4ScriptVM")
ok(type(VM.lowered) == "function",
   "Gen4ScriptVM.lowered is missing, so the set cannot be confirmed")
if type(VM.lowered) == "function" then
  local missing = {}
  for name in pairs(stub) do
    if VM.lowered(name) ~= true then missing[#missing + 1] = name end
  end
  table.sort(missing)
  ok(#missing == 0,
     "%d command(s) the source says are lowered are not lowered according to "
     .. "the table: %s", #missing, table.concat(missing, ", "))
  -- the canary: the detector must say no to something, and its no must be
  -- `false` rather than nil
  ok(VM.lowered("thiscommanddoesnotexist") == false,
     "VM.lowered answers %s for a command that does not exist; nil is what an "
     .. "inert stub answers, and a detector that never says no reports no "
     .. "holes anywhere",
     tostring(VM.lowered("thiscommanddoesnotexist")))
end

-- ---------------------------------------------------------------------------
section("2. the walk, counted both ways")
-- ---------------------------------------------------------------------------
local raw, sites, corpusRaw, corpusSites, overlapBands = {}, {}, 0, 0, 0
-- ...AND THE SAME WALK COUNTS WHAT IS NOT LOWERED AT ALL, which is the hole
-- pass 189 fell into.  See section 5.
local unlowered = {}
if not ROM then
  skip("no cartridge path, so the corpus is not walked this run")
else
  local rom = NdsRom.open(ROM)
  ok(rom ~= nil, "could not open %s", tostring(ROM))
  local arc = rom and Narc.parse(rom:read("/fielddata/script/scr_seq.narc"))
  ok(arc ~= nil, "no /fielddata/script/scr_seq.narc in the cartridge")
  if arc then
    for m = 0, arc.count - 1 do
      local bytes = arc:get(m)
      if bytes and #bytes >= 6 then
        local queue, seen, at_seen = {}, {}, {}
        for _, at in ipairs(Script.entries(bytes)) do
          if not seen[at] then seen[at] = true; queue[#queue + 1] = at end
        end
        local before, positions = corpusRaw, 0
        local i = 1
        while i <= #queue do
          local at = queue[i]; i = i + 1
          for _, op in ipairs(Script.decode(bytes, at)) do
            corpusRaw = corpusRaw + 1
            if op.target and not seen[op.target] then
              seen[op.target] = true; queue[#queue + 1] = op.target
            end
            local key = op.at
            if key and not at_seen[key] then
              at_seen[key] = true; positions = positions + 1
              if op.name and stub[op.name] then
                sites[op.name] = (sites[op.name] or 0) + 1
              end
              -- A DISTINCT POSITION keyed by `op.at` alone would under-count
              -- here: two decodes at one byte can be two different commands
              -- when a tail is read twice, and the declined census can live
              -- with that because a stub row is one command.  The unlowered
              -- count is over every command, so the key carries the name.
              if op.name and not VM.lowered(op.name) then
                unlowered[op.name] = (unlowered[op.name] or 0) + 1
              end
            end
            if op.name and stub[op.name] then
              raw[op.name] = (raw[op.name] or 0) + 1
            end
          end
        end
        corpusSites = corpusSites + positions
        if (corpusRaw - before) ~= positions then
          overlapBands = overlapBands + 1
        end
      end
    end
    -- THE TWO NUMBERS, AND THE GAP BETWEEN THEM, asserted rather than
    -- described. If a later decoder change removes the overlap the gap goes to
    -- zero and this fails -- which is the right outcome, because the doc's
    -- explanation of the two metrics would then be wrong.
    ok(corpusSites >= 57333,
       "the corpus walks %d distinct instruction positions, down from 57,333; "
       .. "the decoder's reach has shrunk", corpusSites)
    ok(corpusRaw > corpusSites,
       "decodes (%d) no longer exceed distinct positions (%d), so the "
       .. "overlapping-tail inflation this tool exists to separate has gone -- "
       .. "re-read the comment at the top before changing this",
       corpusRaw, corpusSites)
    ok(overlapBands > 0,
       "no band overlaps any more, same reason")
    report("%d decodes over %d positions (%.1f%% inflation) in %d band(s)",
           corpusRaw, corpusSites,
           (corpusRaw - corpusSites) / corpusSites * 100, overlapBands)
  end
end

-- ---------------------------------------------------------------------------
section("3. the classification, which is the half that was silently wrong")
-- ---------------------------------------------------------------------------
local function keyFor(name)
  local s = subject[name] or ""
  return MERGES[s] or s
end
do
  local unclassified, usedMerge = {}, {}
  for name in pairs(stub) do
    local s = subject[name] or ""
    if s ~= "" then
      if MERGES[s] then usedMerge[s] = true end
      local key = MERGES[s] or s
      if not KNOWN[key] then
        unclassified[key] = (unclassified[key] or 0) + (sites[name] or 0)
      end
    end
  end
  local list = {}
  for key, n in pairs(unclassified) do
    list[#list + 1] = ("%s (%d site(s))"):format(key, n)
  end
  table.sort(list)
  ok(#list == 0,
     "%d subject(s) are in neither KNOWN nor MERGES, so they enter the "
     .. "ranking unclassified and a split like the persisted map features "
     .. "would be invisible again: %s", #list, table.concat(list, "; "))
  -- AND NO DEAD MERGE ENTRY, so the table cannot quietly stop applying.
  local dead = {}
  for from in pairs(MERGES) do
    if not usedMerge[from] then dead[#dead + 1] = from end
  end
  table.sort(dead)
  ok(#dead == 0,
     "%d MERGES entr(ies) name prose no row uses any more, so the merge is "
     .. "not happening: %s", #dead, table.concat(dead, "; "))
  -- THE MERGE MUST ACTUALLY MERGE. A table whose every entry maps a subject to
  -- itself would satisfy both assertions above.
  local collapsed = 0
  for from, to in pairs(MERGES) do
    if from ~= to then collapsed = collapsed + 1 end
  end
  ok(collapsed == (function() local n = 0 for _ in pairs(MERGES) do n = n + 1 end
                   return n end)(),
     "a MERGES entry maps a subject to itself, which merges nothing")
end

-- ---------------------------------------------------------------------------
section("4. the ranking")
-- ---------------------------------------------------------------------------
if ROM and corpusSites > 0 then
  local agg = {}
  for name in pairs(stub) do
    local key = keyFor(name)
    if key ~= "" then
      local a = agg[key] or { raw = 0, sites = 0, rows = 0 }
      a.raw = a.raw + (raw[name] or 0)
      a.sites = a.sites + (sites[name] or 0)
      a.rows = a.rows + 1
      agg[key] = a
    end
  end
  local rows = {}
  for key, a in pairs(agg) do rows[#rows + 1] = { key, a } end
  table.sort(rows, function(x, y)
    if x[2].sites ~= y[2].sites then return x[2].sites > y[2].sites end
    return x[1] < y[1]
  end)
  -- THE MERGE PAID FOR ITSELF AND IS NOW MOSTLY RETIRED, asserted the other
  -- way round: pass 189 implemented eleven of the twelve rows, so the subject
  -- must have SHRUNK to the one row that is still declined.  Pinned in this
  -- direction on purpose -- the old assertion demanded twelve rows and 30
  -- sites, which is a pin on a state the work was supposed to change, and it
  -- failed on a correct tree the moment the rows were lowered.  An assertion
  -- that fails when the thing it measures gets FIXED is a bad assertion; this
  -- one fails if a persisted-feature row goes back to being a no-op.
  local pmf = agg["persisted map features"]
  ok(pmf ~= nil and pmf.rows == 1,
     "the persisted map features aggregate %s declined row(s); after pass 189 "
     .. "only `triggerplatformlift` should still be one, so a second row means "
     .. "a feature's state write was lost", pmf and tostring(pmf.rows) or "no")
  for _, gone in ipairs({
    "pastoria gym water level", "canalave gym sliding floor",
    "pastoria gym water-level button", "sunyshore gym gear button",
    "sunyshore gym persisted map feature", "hearthome gym persisted map feature",
    "veilstone gym persisted map feature", "eterna gym flower clock",
    "eterna gym persisted map feature", "distortion world persisted map feature",
    "platform lift persisted map feature",
  }) do
    ok(agg[gone] == nil,
       "'%s' is a declared no-op again; pass 189 lowered it onto the persisted "
       .. "map feature slot, so a stub here means the slot write was reverted "
       .. "or renamed", gone)
  end
  io.write("\n")
  io.write(("    %-42s %6s %6s %5s\n"):format("subject", "sites", "raw", "rows"))
  for n = 1, math.min(#rows, 14) do
    local key, a = rows[n][1], rows[n][2]
    io.write(("    %-42s %6d %6d %5d\n"):format(key:sub(1, 42), a.sites, a.raw, a.rows))
  end
  report("%d subjects ranked; the top is '%s' at %d site(s)",
         #rows, rows[1] and rows[1][1] or "?", rows[1] and rows[1][2].sites or 0)
end

-- ---------------------------------------------------------------------------
section("5. the blind spot: what is not lowered at all")
-- ---------------------------------------------------------------------------
--
-- THIS TOOL RANKED A SUBJECT AT 53 SITES THAT IS 82, and the gap was not
-- arithmetic.  Sections 1-4 read their subjects out of the PROSE in `g4_noop`
-- and `g4_no_feature` rows -- which is the right place, because the subject
-- exists nowhere else -- but a command with no lowering emits neither row and
-- therefore names no subject.  It cannot enter the ranking, cannot be
-- classified, and cannot be reported: the tool built to stop a subject hiding
-- had a blind spot shaped exactly like the worst case, since an unlowered
-- command is strictly worse than a declared one.  It does not merely fail to
-- act -- it is stepped over, so an operand it was meant to write keeps
-- whatever the last script left there.
--
-- The persisted map features were 24 unlowered sites over six commands, and
-- one of them -- `checkgreatmarshtramlocation` -- writes a var that six
-- script sites branch on against the literal 6.
--
-- So the walk now counts BOTH, and the two rankings sit side by side. The
-- unlowered one is reported rather than classified: it is dominated by the
-- large absent systems (the Battle Tower, the union room, communications, the
-- contests), which are declined wholesale rather than row by row, and an
-- argued list of 300 names would rot faster than it informed.
--
-- WHAT IS FAIL-CLOSED is the family this pass fixed. Every command that
-- touches the persisted map feature slot must be lowered, for ever: the slot
-- exists now, so an unlowered one is a write that silently does not happen to
-- state another command WILL read back.
local FEATURE_FAMILY = {
  "initpersistedmapfeaturesforpastoriagym", "presspastoriagymbutton",
  "initpersistedmapfeaturesforhearthomegym", "movehearthomegymdplift",
  "initpersistedmapfeaturesforcanalavegym",
  "initpersistedmapfeaturesforveilstonegym",
  "initpersistedmapfeaturesforsunyshoregym", "presssunyshoregymbutton",
  "initpersistedmapfeaturesforplatformlift", "triggerplatformlift",
  "checkplatformliftnotusedwhenenteredmap",
  "initpersistedmapfeaturesforeternagym", "advanceeternagymclock",
  "initpersistedmapfeaturesforvilla",
  "initpersistedmapfeaturesfordistortionworld",
  "initgreatmarshtram", "movegreatmarshtram", "checkgreatmarshtramlocation",
  "setplayerheightcalculationenabled",
}
do
  local notLowered = {}
  for _, name in ipairs(FEATURE_FAMILY) do
    if VM.lowered(name) ~= true then notLowered[#notLowered + 1] = name end
  end
  table.sort(notLowered)
  ok(#notLowered == 0,
     "%d persisted-map-feature command(s) have no lowering: %s. An unlowered "
     .. "one is stepped over, so the slot write does not happen and whatever "
     .. "reads it back gets another feature's state or a stale var",
     #notLowered, table.concat(notLowered, ", "))
  -- ...and the family is the WHOLE family, checked against the opcode table
  -- rather than against this list, so a command that exists and is not named
  -- here fails too. The names are the ones whose `ScrCmd_*` reaches
  -- `PersistedMapFeatures_*`, `DynamicMapFeatures_*` or `GreatMarshTram_*`.
  local Ops = require("src.import.Gen4ScriptOps")
  -- `Gen4ScriptOps.COMMANDS` by its real name, not a guess at it.  The first
  -- draft of this read `Ops.OPS or Ops.ops or Ops`, fell through to the module
  -- table itself, found no `{ name, spec }` rows in it and passed -- so a
  -- plant that deleted `checkgreatmarshtramlocation` from the family list left
  -- it green.  Shape 3b again: a lookup that matched nothing and reported
  -- agreement.  Asserted first, so the table being renamed fails loudly
  -- instead of quietly emptying the check.
  local table_ = Ops.COMMANDS
  ok(type(table_) == "table" and next(table_) ~= nil,
     "Gen4ScriptOps.COMMANDS is %s; the family completeness test below reads "
     .. "it, and an empty table makes that test pass over everything",
     type(table_))
  table_ = (type(table_) == "table") and table_ or {}
  local seen, missing = {}, {}
  for _, name in ipairs(FEATURE_FAMILY) do seen[name] = true end
  for _, spec in pairs(table_) do
    local name = type(spec) == "table" and spec[1] or nil
    if type(name) == "string"
       and (name:find("persistedmapfeatures", 1, true)
            or name:find("greatmarshtram", 1, true))
       and not seen[name] then
      missing[#missing + 1] = name
    end
  end
  table.sort(missing)
  ok(#missing == 0,
     "%d command(s) in the opcode table name a persisted map feature or the "
     .. "Great Marsh tram and are not in this tool's family list, so they are "
     .. "neither lowered-checked nor counted: %s",
     #missing, table.concat(missing, ", "))
end

if not ROM then
  skip("no cartridge path, so the unlowered ranking is not built this run")
else
  local rows, total = {}, 0
  for name, n in pairs(unlowered) do
    rows[#rows + 1] = { name, n }
    total = total + n
  end
  table.sort(rows, function(x, y)
    if x[2] ~= y[2] then return x[2] > y[2] end
    return x[1] < y[1]
  end)
  -- A COUNT THAT CANNOT BE ZERO WOULD SAY NOTHING, so this is asserted
  -- against the declined census rather than against a literal: the corpus has
  -- both kinds and a walk that found no unlowered command at all would mean
  -- the detector, not the backlog, had changed.
  ok(#rows > 0,
     "the walk found no unlowered command in the whole corpus, which would "
     .. "mean every one of Sinnoh's commands is lowered -- more likely "
     .. "`VM.lowered` has started answering true for everything")
  ok(total > 0 and total < corpusSites,
     "unlowered sites (%d) are not a strict subset of the corpus (%d)",
     total, corpusSites)
  io.write("\n")
  io.write(("    %-42s %6s\n"):format("unlowered command", "sites"))
  for n = 1, math.min(#rows, 10) do
    io.write(("    %-42s %6d\n"):format(rows[n][1]:sub(1, 42), rows[n][2]))
  end
  report("%d unlowered commands over %d sites, invisible to the ranking in "
         .. "section 4; the largest is '%s' at %d",
         #rows, total, rows[1][1], rows[1][2])
end

io.write(("\n%d checks, %d failed, %d reported, %d skipped\n")
           :format(checks, fails, reports, skips))
os.exit(fails == 0 and 0 or 1)
