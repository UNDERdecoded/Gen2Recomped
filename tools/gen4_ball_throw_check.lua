-- tools/gen4_ball_throw_check.lua
--
-- Every throwable ball must resolve to a complete set of throw frames, both in
-- the `gen4_graphics` cache and on disk.
--
-- WHY THIS EXISTS.  The ball throw art has been extracted for a long time --
-- `ball_throws/` is a declared family in `Gen4Battle.OBJ_FAMILIES` -- and
-- nothing named which set belonged to which ball, so nothing could use it and
-- nothing noticed if a set went missing.  `Gen4Battle.ballThrowFor` names them
-- now, and this is what keeps that naming honest against a real install: the
-- container this was derived in only ever sees one cache.
--
--   lua tools/gen4_ball_throw_check.lua [path/to/platinum/data/generated]
--
-- Exits non-zero if any ball is short a frame.

local root = arg and arg[1] or "platinum/data/generated"
local dataRoot = root:gsub("data/generated/?$", "")

package.path = "./?.lua;" .. package.path
local Gen4Battle = require("src.battle.Gen4Battle")

local function load(name)
  local path = root .. "/" .. name .. ".lua"
  local chunk = loadfile(path)
  if not chunk then
    io.stderr:write(("cannot read %s\n"):format(path))
    os.exit(2)
  end
  return chunk()
end

local graphics = load("gen4_graphics")
local items = load("items")
local objects = graphics.battleObjects or {}

-- FRAMES PER BALL IS NOT ASSUMED.  Ten is what every ball but `mud` carries,
-- and `mud` carries seven -- so the count comes from the cache rather than from
-- a constant that would quietly turn a missing frame into an expected one.
local function frameCount(name)
  local n = 0
  while objects[Gen4Battle.ballThrowFrame(name, n)] do n = n + 1 end
  return n
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local problems, checked = 0, 0
local report = {}

-- ONE ROUTINE FOR BOTH LISTS.  The first version of this checked the disk for
-- the sixteen ball items and not for the three Safari throws, which meant the
-- Safari rows reported "ok" on a cache whose frames were never written -- a
-- check that passes where it does not look.
local tested, found = 0, 0
local function check(label, name)
  checked = checked + 1
  local n = frameCount(name)
  if n == 0 then
    problems = problems + 1
    report[#report + 1] = ("  MISSING  %-16s -> %-14s no frames at all"):format(label, name)
    return
  end
  local absent = 0
  for f = 0, n - 1 do
    local entry = objects[Gen4Battle.ballThrowFrame(name, f)]
    local path = type(entry) == "table" and entry.path
    if path then
      tested = tested + 1
      if exists(dataRoot .. path) then found = found + 1
      else absent = absent + 1 end
    end
  end
  if absent > 0 then
    problems = problems + 1
    report[#report + 1] =
      ("  ON DISK  %-16s -> %-14s %d of %d frames named but not written"):format(label, name, absent, n)
  else
    report[#report + 1] = ("  ok       %-16s -> %-14s %d frames"):format(label, name, n)
  end
end

-- Every ball ITEM, by the id space `ballThrowFor` reads.
for id = 1, 16 do
  local item = items[id]
  check((type(item) == "table" and item.name) or ("item " .. id),
        Gen4Battle.ballThrowFor(id))
end

-- The Safari throws have no item id and are reached by name.
for _, name in ipairs({ "park_ball", "mud", "bait" }) do
  check("(safari)", name)
end

print(table.concat(report, "\n"))
print(("\n%d ball throw sets checked, %d with problems"):format(checked, problems))

-- THE CHECK HAS TO BE ABLE TO FAIL, and this is what shows it can: a name that
-- is not in the cache must come back with no frames.  If this line ever prints
-- a non-zero count the check itself is broken and its passes mean nothing.
local controlFrames = frameCount("definitely_not_a_ball")
print(("control: a ball that does not exist resolves to %d frames (must be 0)"):format(controlFrames))
if controlFrames ~= 0 then
  io.stderr:write("the control found frames for a ball that does not exist -- "
                  .. "this check cannot fail and its result means nothing\n")
  os.exit(3)
end

-- HOW COMPLETE THE ASSET TREE IS, stated before the verdict, because the two
-- ways this check fails look identical in a count of problems: a real install
-- missing frames, and a working copy that was never given the art. The second
-- is not a fault in the port and must not read like one.
io.write(("frames on disk: %d of %d\n"):format(found, tested))
if tested > 0 and found == 0 then
  io.write("no ball art on disk at all -- this is not a complete install, so\n"
           .. "there is nothing here to check\n")
  os.exit(2)
end

-- THE VERDICT IN THE SHAPE EVERY OTHER CHECK USES, so a suite runner can read
-- it. Without this line `tools/run_checks.py` had nothing to parse and filed a
-- plain failure as an ERROR -- which reads as "the check is broken" rather
-- than "the check found something".
io.write(("\n%d checks, %d failed\n"):format(checked, problems))
os.exit(problems > 0 and 1 or 0)
