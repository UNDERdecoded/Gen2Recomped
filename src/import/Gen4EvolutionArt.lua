-- PLATINUM'S EVOLUTION SCENE PARTICLES (src/evolution.c, src/unk_0207C63C.c).
--
-- sub_0207C894 loads member 0 of NARC 124 --
-- /demo/shinka/data/particle/shinka_demo_particle.narc -- as the scene's one
-- particle resource, and the scene fires its emitters by id (0 at the start
-- fade; 1, 2, 7, 8, 9, 11 when the clamp closes; 3, 4, 5, 6, 10 when the two
-- forms stop alternating; 12 on the final white-out), each placed by
-- sub_0207C854 at (0, 8 * 172, 0) in fx32 units.
--
-- Pictures: `particle_<i>`, the SPA file's textures in file order. Data
-- (`gen4_evolution_ink`): `emitters`, Gen4Particle's decode of the same file,
-- which Gen4ParticleSystem.fromEmitters / .resource simulate.

local Gen4EvolutionArt = {}

Gen4EvolutionArt.PATH = "/demo/shinka/data/particle/shinka_demo_particle.narc"
Gen4EvolutionArt.MEMBER = 0

local function file(rom)
  local bytes = rom:read(Gen4EvolutionArt.PATH)
  if not bytes then return nil end
  local narc = require("src.import.NarcArchive").parse(bytes)
  return narc and narc:get(Gen4EvolutionArt.MEMBER)
end

function Gen4EvolutionArt.images(rom)
  local P = require("src.import.Gen4Particle")
  local data = file(rom)
  local list = data and P.textures(data)
  if not list then return nil, "shinka particle file missing" end
  local out = {}
  for i, texture in ipairs(list) do out[("particle_%d"):format(i - 1)] = P.rgba(texture) end
  return out
end

function Gen4EvolutionArt.data(rom)
  local data = file(rom)
  if not data then return nil end
  local emitters = require("src.import.Gen4Particle").emitters(data)
  return { emitters = emitters, count = emitters and #emitters or 0 }
end

return Gen4EvolutionArt
