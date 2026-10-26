local M = {}
function M.run(root, backend, version)
  local native, rows = backend == "gen1", {}
  local f =
    dofile(root .. "/tests/enemy_actions/party_codec.lua").fixture(root, backend, version, "translated")
  local P, calls, policy = require("src.link.Protocol"), {}, "none"
  local function number(id)
    if not native then
      return f.data.pokemon[id].index
    end
    -- API 3 names source species by canonical text ID; the ROM codec uses numbers.
    return type(id) == "number" and id or assert(tonumber(id:match("SPECIES_(%d+)$")))
  end
  local function hook(nextGender, c)
    calls[#calls + 1] = {
      species = number(c.species),
      definition = number(c.def.id),
      ratio = c.ratio,
      personality = c.personality,
    }
    if policy == "female" then
      return "female"
    end
    if policy == "invalid" then
      return "invalid"
    end
    if policy == "threshold" then
      c.def.genderRatio = 0
    end
    return nextGender(c)
  end
  for _, mode in ipairs({ "none", "delegate", "female", "invalid", "threshold" }) do
    policy = mode
    local stop = mode ~= "none" and f.e.api.hooks:wrap("gender.roll", hook) or nil
    for _, pid in ipairs({ 0, 1, 127, 128, 255, 65535, 4294967295 }) do
      local ivs, evs = {}, {}
      for _, k in
        ipairs(
          native and { "hp", "atk", "def", "spe", "spa", "spd" }
            or { "hp", "attack", "defense", "speed", "spatk", "spdef" }
        )
      do
        ivs[k], evs[k] = 0, 0
      end
      local mon = {
        species = native and 60 or f.codecIds[60],
        speciesNumbering = native and "internal" or nil,
        level = 20,
        exp = 8000,
        personality = pid,
        ivs = ivs,
        evs = evs,
        hp = 1,
        moves = native and { 33 } or { { id = f.ids.TACKLE, pp = 1, ppUps = 0 } },
        pp = native and { 1 } or nil,
        ability = native and 11 or nil,
        abilitySlot = 1,
      }
      calls = {}
      local packed = native and P.packMon3(mon) or P.packMon(mon)
      local restored, why
      if native then
        restored, why = P.unpackMon3(f.data, packed, { strict = true })
      else
        restored, why = P.unpackMon(f.data, packed, { strict = true })
      end
      f.T.check(restored ~= nil, "public gender policy survives the codec: " .. tostring(why))
      assert(restored, why)
      f.T.eq(#calls, mode == "none" and 0 or 2, "pack and unpack retain public hook entry points")
      rows[#rows + 1] = {
        mode = mode,
        pid = pid,
        calls = calls,
        gender = native and ({ M = "male", F = "female", U = "unknown" })[restored.gender] or restored.gender,
      }
    end
    if stop then
      stop()
    end
  end
  f.close()
  return rows
end
return M
