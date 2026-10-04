-- Run:  texlua tools/editor_models_check.lua
--
-- The map editor's Gen 4 model overlay: that a prop edit is STORED, that it
-- survives being applied back onto a freshly extracted map, and that the
-- renderer reads it in preference to the cartridge's own prop list.
--
-- IT HAD NO INVOCATION LINE, so `run_checks.py` reported it NOSPEC and never
-- ran it -- the suite could not see the one check covering the model overlay,
-- and stage 1 of the Gen 3/4 editor work leaned on it for Gen 1/2/3 evidence
-- by running it BY HAND. A check nobody can invoke is not a check. It also
-- printed a sentence and no verdict, so even when run it was classified as a
-- REPORT rather than a pass or a failure; it counts its assertions now.
--
-- No cartridge and no cache: every record here is built in place.

package.path = 'tools/save-editor/?.lua;' .. package.path

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local Edits = require('tools.map-editor.MapEdits')
local Map = require('src.world.Map')

-- A packed Gen 3/4 block string: the metatile id is the low ten bits of a u16,
-- so writing one must leave the top six (collision and elevation) alone.
local def = { width = 2, height = 1, blocks = string.char(5, 240, 6, 160) }
Map.blockArray(def)
check(Edits.writePackedBlock(def, 0, 0, 777),
      'writePackedBlock accepts an in-bounds coordinate on a packed map')
check(def.blocks:byte(2) == 243,
      'and leaves the top six bits of the word alone (240 -> 243 is the id, '
      .. 'not the flags)')
check(Map.blockArray(def)[1] == 777,
      'and the block array re-reads the id it wrote')

local S = { version = 'platinum', mapId = 'T01',
            data = { maps = { T01 = { id = 'T01', generation = 4,
                                      width = 32, height = 32 } } },
            mapEdits = { games = {} } }
local list = { { model = 12, x = 16, y = 8, z = 32,
                 scaleX = 1.5, scaleY = 2, scaleZ = 1 } }
require('tools.map-editor.panels.Models').commit(S, 0, list)
check(S.mapEditsDirty == true, 'committing a prop marks the store dirty')
check(S.mapEdits.games.platinum.maps.T01.map.gen4ModelEdits['0'][1].model == 12,
      'and the prop lands in the store under its chunk id -- gen4ModelEdits is '
      .. 'the one Gen 4 field MAP_FIELDS allows, so this is the one Gen 4 edit '
      .. 'that is not dropped by typedCopy')

local reloaded = { id = 'T01', width = 32, height = 32, objects = {} }
Edits.applyToMap(S.mapEdits, 'platinum', 'T01', reloaded)
check(reloaded.gen4ModelEdits['0'][1].scaleY == 2,
      'and it comes back onto a freshly extracted def, which is what makes a '
      .. 'ROM re-import non-destructive')

local ground = setmetatable({ def = reloaded, signpostsFor = function() return {} end },
                            require('src.render.Gen4Ground'))
check(ground:objectsFor(0, { objects = { { model = 99 } } })[1].model == 12,
      'and the renderer prefers the edited list over the chunk\'s own props')

local Catalog = require('Catalog')
check(Catalog.mapLabel({ maps = { T01 = { label = 'Twinleaf Town' } } }, 'T01')
      == 'Twinleaf Town',
      'and a Platinum map still shows its cartridge label in the picker')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
