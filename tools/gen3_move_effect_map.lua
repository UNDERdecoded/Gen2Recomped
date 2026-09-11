-- Re-derive GEN3_MOVE_EFFECTS, the map from Emerald's battle-effect NUMBERS
-- to the effect NAMES this engine dispatches on.
--
--   luajit tools/gen3_move_effect_map.lua <emerald.gba> <gen2 moves.lua>
--
-- gBattleMoves gives every move an effect number and src/battle/MoveEffects
-- keys its records by name, so the two have to be joined before a Gen 3 move
-- can do anything at all.  Nothing on either cartridge carries the join --
-- but the MOVE NAMES do: Gen 2 and Gen 3 share about 250 of them, and a Gen 2
-- import already names an effect for each, so every shared move casts a vote
-- for what its Gen 3 number means.
--
-- A number is taken when every move that uses it agrees.  Three do not, and
-- those three are not disagreements: Gen 1 and Gen 2 put the ODDS in the
-- effect name -- BURN_SIDE_EFFECT1 is the one in ten, BURN_SIDE_EFFECT2 the
-- three in ten -- while Gen 3 has one effect and a chance byte beside it.
-- Those come out as a PAIR and the extractor picks between them with the
-- cartridge's own byte.
--
-- The second argument is a REAL Gen 2 dataset -- the moves.lua an import
-- writes, not the placeholder stub in data/generated_gen2_crystal.  Any of
-- Gold, Silver or Crystal will do; they name the same effects.
--
-- Prints the table body, ready to paste into RomExtractorGen3.lua.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local romPath, gen2Path = arg[1], arg[2]
if not (romPath and gen2Path) then
  io.stderr:write("usage: gen3_move_effect_map.lua <emerald.gba> <gen2 moves.lua>\n")
  os.exit(2)
end

local fh = assert(io.open(romPath, "rb"))
local romData = fh:read("*a")
fh:close()
local manifestFile = assert(io.open("tools/rom_manifest_emerald.json"))
local manifest = require("src.link.Json").decode(manifestFile:read("*a"))
manifestFile:close()

local captured = {}
local LuaWriter = require("src.import.LuaWriter")
LuaWriter.write = function(path, value)
  captured[path:match("([^/]+)%.lua$")] = value
end
local Gen3 = require("src.import.RomExtractorGen3")
local x = Gen3.new(romData, "emerald", manifest, nil)
x.saveImage = function() end
for _, stage in ipairs({ "extractConstants", "extractMoves" }) do
  pcall(x[stage], x)
end
local gen3 = captured.moves
local gen2 = assert(dofile(gen2Path))

-- gen3Effect is kept beside the name the extractor already resolved, so this
-- re-derivation reads the NUMBER rather than whatever it was mapped to
local votes, shared = {}, 0
for id, def in pairs(gen3) do
  local other = type(def) == "table" and gen2[id]
  local number = type(def) == "table" and (def.gen3Effect or def.effect)
  if other and other.effect and type(number) == "number" then
    shared = shared + 1
    votes[number] = votes[number] or {}
    votes[number][other.effect] = (votes[number][other.effect] or 0) + 1
  end
end

local numbers = {}
for number in pairs(votes) do numbers[#numbers + 1] = number end
table.sort(numbers)

local lines, unanimous, split, refused = {}, 0, 0, 0
for _, number in ipairs(numbers) do
  local tally = votes[number]
  local names = {}
  for name, n in pairs(tally) do names[#names + 1] = { name = name, n = n } end
  table.sort(names, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.name < b.name
  end)
  if #names == 1 then
    unanimous = unanimous + 1
    lines[#lines + 1] = ("  [%d] = { %q, votes = %d },")
      :format(number, names[1].name, names[1].n)
  else
    local low, high
    for _, entry in ipairs(names) do
      if entry.name:sub(-1) == "1" then low = entry
      elseif entry.name:sub(-1) == "2" then high = entry end
    end
    if low and high and #names == 2 then
      split = split + 1
      lines[#lines + 1] = ("  [%d] = { %q, %q, votes = %d },")
        :format(number, low.name, high.name, low.n + high.n)
    else
      refused = refused + 1
      local parts = {}
      for _, entry in ipairs(names) do
        parts[#parts + 1] = ("%s x%d"):format(entry.name, entry.n)
      end
      lines[#lines + 1] = ("  -- [%d] REFUSED, the votes disagree: %s")
        :format(number, table.concat(parts, ", "))
    end
  end
end

io.write(table.concat(lines, "\n"), "\n")
io.stderr:write(("\n%d shared moves; %d effect numbers covered -- %d unanimous, "
                 .. "%d odds pairs, %d refused\n")
                :format(shared, #numbers, unanimous, split, refused))
