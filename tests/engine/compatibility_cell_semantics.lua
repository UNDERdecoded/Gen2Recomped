package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local MB = require('src.compat.gen1.MetatileBehavior')
local Class = require('src.compat.gen1.CollisionClass')
local fr, em = Class.impl('frlg'), Class.impl('rse')
T.eq(MB.fromRaw('firered', 17), 17, 'Kanto raw byte retains meaning')
T.eq(MB.fromRaw('emerald', 17), MB.INTERIOR_DEEP_WATER, 'Hoenn byte 17 is not Kanto fast water')
T.check(MB.fromRaw('emerald', 17) ~= MB.FAST_WATER, 'families do not share behavior byte meanings')
for _, game in ipairs({'emerald', 'ruby', 'sapphire'}) do
 local translator = MB.translator(game)
 for raw = 0, 255 do T.eq(translator.canon(translator.raw(translator.canon(raw))), translator.canon(raw)) end
 T.eq(translator.canon(.5), nil, 'fractional input is not silently truncated')
 T.eq(MB.fromRaw(game, .5), nil, 'failed conversion does not fall back to raw')
 local copy = translator.table(); copy[0] = -1
 T.check(translator.table()[0] ~= -1, 'conversion snapshots cannot corrupt shared metadata')
end
local copy = MB.all(); copy.NORMAL = -1
T.eq(MB.id('MB_NORMAL'), 0, 'name snapshots cannot corrupt IDs')
T.eq(fr.fromCell(0, 0, MB.POND_WATER, 'route'), 0x29, 'water is classified, not raw collision zero')
T.eq(fr.fromCell(0, 1, MB.POND_WATER, 'route'), 7, 'blocked water stays blocked')
T.eq(fr.fromCell(0, 0, MB.TALL_GRASS, 'route'), 0x18)
T.eq(fr.fromCell(0, 0, MB.JUMP_NORTH, 'route'), 0xa2)
T.eq(fr.fromCell(0, 0, MB.WARP_DOOR, 'indoor'), 0x72, 'indoor warp retains facing')
T.eq(fr.fromCell(0, 0, MB.WARP_DOOR, 'town'), 0x71, 'outdoor door retains original arrival contract')
T.eq(fr.fromCell(10, nil, nil, 'route'), 7, 'nil collision differs from zero in Kanto terrain fallback')
T.eq(fr.fromCell(10, 0, nil, 'route'), 0)
T.eq(fr.fromCell(10, 1, nil, 'indoor'), 7, 'indoor reused metatile is not an outdoor tree')
T.eq(fr.fromCell(646, 0, 0, 'route'), 0, 'dead shrub guard does not become new foliage')
local bits = {[MB.POND_WATER] = 2, [MB.TALL_GRASS] = 2}
em.setTileBits(bits)
T.eq(em.fromCell(0, 0, MB.POND_WATER, 'route'), 0x29)
T.eq(em.fromCell(0, 1, MB.POND_WATER, 'route'), 7)
T.eq(em.fromCell(0, 0, MB.TALL_GRASS, 'route'), 0x29, 'actual surf flag precedes static category')
bits[MB.TALL_GRASS] = 0
T.eq(em.fromCell(0, 0, MB.TALL_GRASS, 'route'), 0x18, 'borrowed flag mutation is visible immediately')
bits[MB.POND_WATER] = nil
T.eq(em.fromCell(0, nil, MB.POND_WATER, 'route'), 0, 'Hoenn fallback accepts nil collision')
T.eq(fr.fromCell(0, 0, MB.POND_WATER, 'route'), 0x29, 'Hoenn flags do not change Kanto classification')
em.setTileBits(nil)
T.eq(em._tileBits, nil, 'flag owner can retire its source')
T.eq(em.fromCell(0, 0, MB.POND_WATER, 'route'), 0, 'no invented surfability without source flags')
local classify, seed = em.classify, em.seed
em.classify = function() return 'LEDGE', 'W' end
T.eq(em.fromCell(0, 0, 0, 'route'), 0xa1, 'replacement classifier bypasses fixed rows')
em.classify = classify
em.seed = function(category) return category == 'TALL_GRASS' and 123 or 456 end
T.eq(em.fromCell(0, 0, MB.TALL_GRASS, 'route'), 123, 'replacement seed bypasses fixed rows')
em.seed = seed
T.eq(em.fromCell(0, 0, MB.TALL_GRASS, 'route'), 0x18, 'restoring extension functions restores dispatch')
local Class=require('src.compat.gen1.CollisionClass')
local a=Class.new('rse',{[16]=2});local b=Class.new('rse',{})
T.eq(a.fromCell(0,0,16,'route'),0x29);T.eq(b.fromCell(0,0,16,'route'),0)
b.setTileBits({[16]=2});T.eq(b.fromCell(0,0,16,'route'),0x29)
a.setTileBits(nil);T.eq(a.fromCell(0,0,16,'route'),0);T.eq(b.fromCell(0,0,16,'route'),0x29,'contexts do not share flag state')
T.finish('compatibility cell semantics')
