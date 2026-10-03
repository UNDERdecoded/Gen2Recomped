-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A CHARACTER THE CARTRIDGE'S FONT DOES NOT HAVE DRAWS NOTHING, SILENTLY.
--
-- Reported from play: "Gen2 games are missing the symbol next to the selected
-- options in the menus specific for gen2".  The Pokegear's phone list drew its
-- cursor as `Font.draw("> " .. name)`, and Gen 2's charmap has 92 sequences
-- and ">" is not one of them.  `Font.split` finds no glyph, `blitCode` returns
-- early, and the arrow is two blank columns -- on every Game Boy cartridge the
-- screen runs on, since the first build that had it.
--
-- Nothing could have caught that at runtime either: no exception, no wrong
-- pixel, just an absence.  The cartridge is unambiguous --
-- `PokegearPhone_UpdateCursor` (pokecrystal engine/pokegear/pokegear.asm)
-- writes the '\xED' glyph into column 1 of the cursor's row -- so the fix is
-- the glyph the rest of the port already uses, and this is the sweep that
-- stops the next one.
--
-- THE RULE IS DERIVED FROM THE FILENAME, NOT FROM A LIST.  A screen whose name
-- starts with Gen3 or Gen4 draws through a cartridge font that really does
-- have ASCII; everything else in src/ui is reachable from a Game Boy
-- generation, where the charmap is letters, digits, space and fourteen pieces
-- of punctuation -- verified against the extracted Crystal charmap, which has
-- `- : ( ) [ ] ; ' / .` and does NOT have `< > *`.
--
-- Run:  texlua tools/gen2_glyph_literals_check.lua

package.path = (function()
  local here = (arg and arg[0] or ""):gsub("[^/\\]*$", "")
  local root = (here ~= "") and (here .. "../") or "./"
  return root .. "?.lua;./?.lua;" .. package.path
end)()

local fails, checks, reports = 0, 0, 0
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
local function section(n) io.write(("\n-- %s\n"):format(n)) end
local function slurp(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

-- Characters no Game Boy charmap in this port carries.  Deliberately narrow:
-- the point is to be certain of every one, not to guess at the boundary.
-- `%` is excluded because it only ever appears as a format specifier, which
-- is consumed before anything is drawn; the stripping below removes those.
local FORBIDDEN = "<>*+#~=@^{}|`$"

-- A FILE LIST THAT DERIVES ITSELF.  No hand-maintained set of screens: a new
-- Game Boy screen is in scope the moment it is added, and a new Gen 3 or Gen 4
-- one is out of it, because the name says which.
local function gameBoyReachable(name)
  return not (name:match("^Gen3") or name:match("^Gen4"))
end

local function listDir(dir)
  local out = {}
  local p = io.popen('ls "' .. dir .. '" 2>/dev/null')
  if not p then return out end
  for line in p:lines() do
    if line:match("%.lua$") then out[#out + 1] = line end
  end
  p:close()
  return out
end

-- ---------------------------------------------------------------------------
section("1. the sweep can see a fault")
-- ---------------------------------------------------------------------------
-- The canary, first, because this check's whole output is an ABSENCE of
-- findings -- and a scanner that matches nothing reports a clean sweep over
-- nothing at all.  (claude/check_design_lessons: every "is X zero?" assertion
-- wants a floor on the comparison itself.)
local function literalsIn(src)
  local found = {}
  for line in src:gmatch("[^\r\n]+") do
    -- comments are prose about the code, not code: a paragraph explaining why
    -- ">" is wrong must not be reported as a use of it
    local code = line:gsub("%-%-.*$", "")
    for call in code:gmatch('Font%.draw%s*%(([^\n]*)') do
      for lit in call:gmatch('"([^"]*)"') do
        -- format specifiers are consumed by Strings() before anything draws
        local text = lit:gsub("%%[%-%+ #0]*%d*%.?%d*[a-zA-Z%%]", "")
        for i = 1, #text do
          local ch = text:sub(i, i)
          if FORBIDDEN:find(ch, 1, true) then
            found[#found + 1] = { ch = ch, line = line:match("^%s*(.-)%s*$") }
          end
        end
      end
    end
  end
  return found
end

do
  local probe = [[  Font.draw(Strings("> " .. name), 18, ty * 8)]]
  local hits = literalsIn(probe)
  ok(#hits == 1 and hits[1].ch == ">",
     "the scanner found %d forbidden character(s) in the exact line this check "
     .. "was written for; it cannot see the fault it exists to catch", #hits)
  -- ...and does not fire on the things that are fine
  for _, fine in ipairs({
      [[  Font.draw(Strings("COINS %4d", n), 8, 16)]],
      [[  Font.draw(Strings("PLAYER %s", who), 8, 16)]],
      [[  -- Font.draw("> " .. name) is what this replaced]],
      [[  Font.drawCode(Theme.cursor, 8, ty * 8)]],
  }) do
    ok(#literalsIn(fine) == 0,
       "the scanner fired on a line that is fine: %s", fine)
  end
end

-- ---------------------------------------------------------------------------
section("2. no Game Boy screen draws a glyph its font does not have")
-- ---------------------------------------------------------------------------
-- TWO ACCEPTED FINDINGS, each argued, because the sweep finds them and a
-- sweep whose findings are merely printed gets ignored.  Note the shape: the
-- SUBJECTS are derived from the filesystem, so a new screen is covered the day
-- it is written; only the EXCEPTIONS are enumerated, and each one says why.
--
--   * Diploma.lua's `<Diploma>` -- the Gen 2 diploma's title is not text at
--     all (`DiplomaPage1Tilemap` + `DiplomaGFX`, engine/events/diploma.asm);
--     the brackets are this port's own decoration around a stand-in, not a
--     cartridge glyph that went missing.
--   * SlotMachine.lua's `>` and `<` -- inside `drawPlain`, which the file
--     itself calls the "fallback layout for stale builds without the extracted
--     machine frame".  There is also no left-pointing arrow anywhere in the
--     Game Boy font sheet, so `<` has no faithful glyph to be.
--
-- Neither is the reported bug and neither is on a path a current build draws.
-- Both are one line to fix the day somebody wants them fixed; until then they
-- are listed rather than hidden.
local ACCEPTED = {
  ["src/ui/Diploma.lua"] = 2,
  ["src/ui/SlotMachine.lua"] = 2,
}

local scanned, offenders, accepted = 0, {}, {}
for _, dir in ipairs({ "src/ui", "src/world", "src/render" }) do
  for _, name in ipairs(listDir(dir)) do
    if gameBoyReachable(name) then
      local src = slurp(dir .. "/" .. name)
      if src then
        scanned = scanned + 1
        local path = dir .. "/" .. name
        for _, hit in ipairs(literalsIn(src)) do
          local row = ("%s draws %q: %s"):format(path, hit.ch, hit.line)
          if ACCEPTED[path] then
            accepted[path] = (accepted[path] or 0) + 1
            accepted[#accepted + 1] = row
          else
            offenders[#offenders + 1] = row
          end
        end
      end
    end
  end
end
-- A FLOOR ON THE SWEEP ITSELF.  If the directory walk ever answered nothing --
-- a renamed folder, an `ls` that is not there -- this section would report a
-- clean result over an empty set, which is the same green as a clean port.
ok(scanned >= 40,
   "only %d Game Boy screens were scanned; the sweep is not reaching src/ui "
   .. "and its clean result means nothing", scanned)
io.write(("   scanned %d Game Boy-reachable files\n"):format(scanned))
for _, o in ipairs(accepted) do io.write("   (accepted) ", o, "\n") end
for _, o in ipairs(offenders) do io.write("   ", o, "\n") end
ok(#offenders == 0,
   "%d literal(s) are drawn that a Game Boy charmap cannot render, so they "
   .. "come out blank on Gen 1 and Gen 2 (listed above)", #offenders)
-- AND THE EXCEPTIONS ARE EXACT, NOT A CEILING.  An accepted file that stops
-- producing its findings has been fixed and should lose its entry; one that
-- produces MORE has grown a new fault behind an old pardon.  Either way the
-- list is wrong and should be made to say so rather than quietly absorb it.
for path, want in pairs(ACCEPTED) do
  if type(path) == "string" then
    ok((accepted[path] or 0) == want,
       "%s has %d accepted finding(s), not %d -- the pardon in ACCEPTED is "
       .. "stale, so it is either hiding something new or outliving its fix",
       path, accepted[path] or 0, want)
  end
end

-- ---------------------------------------------------------------------------
section("3. the Pokegear's cursor is the cartridge's glyph")
-- ---------------------------------------------------------------------------
do
  local src = slurp("src/ui/PokegearMenu.lua") or ""
  ok(#src > 0, "src/ui/PokegearMenu.lua did not open")
  local code = src:gsub("%-%-[^\r\n]*", "")
  ok(code:find("Font.drawCode(Theme.cursor", 1, true) ~= nil,
     "the Pokegear phone list no longer draws Theme.cursor; the cartridge's "
     .. "PokegearPhone_UpdateCursor writes a glyph into column 1 of the "
     .. "selected row and this screen is the one that reported it missing")
  ok(code:find('require("src.ui.Theme")', 1, true) ~= nil,
     "PokegearMenu uses Theme.cursor without requiring Theme")
  -- the cursor sits in its own column, so the names do not shift as it moves
  -- (UpdateDisplayList writes names from column 2, UpdateCursor the arrow at 1)
  ok(code:find('Font.draw%(Strings%("> "') == nil,
     "the \">\" prefix is back on the selected contact")
end

-- ---------------------------------------------------------------------------
section("4. the glyph itself, in the extracted Gen 2 font")
-- ---------------------------------------------------------------------------
-- `Theme.cursor` is 0xED, which is Gen 1's charmap code, and Gen 2 keeps its
-- own font.  They happen to agree -- the Gen 2 sheet is 16 glyphs per row from
-- base 128, so 0xED lands at index 109, row 6 column 13, and that tile is the
-- filled right triangle with the hollow one beside it at 0xEC and the down
-- arrow at 0xEE.  Asserted so that a font reload that changes the bases is not
-- silently allowed to move the cursor off its glyph.
do
  local Theme = require("src.ui.Theme")
  ok(Theme.cursor == 0xED, "Theme.cursor is %s, not 0xED",
     tostring(Theme.cursor))
  ok(Theme.cursorHollow == 0xEC, "Theme.cursorHollow is %s, not 0xEC",
     tostring(Theme.cursorHollow))
  ok(Theme.moreArrow == 0xEE, "Theme.moreArrow is %s, not 0xEE",
     tostring(Theme.moreArrow))
  -- the three are consecutive and in the cartridge's order, which is what
  -- makes "row 6, columns 12-14" a single statement rather than three
  ok(Theme.cursorHollow + 1 == Theme.cursor
     and Theme.cursor + 1 == Theme.moreArrow,
     "the three cursor glyphs are no longer consecutive (%s, %s, %s), so they "
     .. "are not the run this check measured in the font sheet",
     tostring(Theme.cursorHollow), tostring(Theme.cursor),
     tostring(Theme.moreArrow))
end

io.write(("\n%d checks, %d failed, %d reported\n"):format(checks, fails, reports))
os.exit(fails == 0 and 0 or 1)
