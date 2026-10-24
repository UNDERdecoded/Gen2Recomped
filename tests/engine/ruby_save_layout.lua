package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local J=require('src.link.Json')
local f=assert(io.open('tools/rom_manifest_ruby.json'));local m=J.decode(f:read('*a'));f:close()
local S=require('src.save_convert.Gen3Save')
S.setLayout(m.save,m.substructOrders,m.saveFields,'ruby')
T.eq(S.defaultMetGame,2,'Ruby origin remains Ruby')
T.eq(S.encryptionKey(string.rep('\255',m.save.saveBlock2Size)),0,'RS bag and money are unencrypted')
local image=S.blank()
local blocks=assert(S.readBlocks(image))
T.eq(#blocks.block1,15040,'Ruby SaveBlock1 assembled')
T.eq(#blocks.block2,2192,'Ruby SaveBlock2 assembled')
T.eq(#blocks.storage,33744,'all fourteen boxes assembled')
-- Patterned nonzero blocks catch offset/chunk/rotation errors that empty
-- templates cannot expose. No player or cartridge save is involved.
local function pattern(n,seed)
  local out={};for i=1,n do out[i]=string.char((i*17+seed)%256) end
  return table.concat(out)
end
blocks.block1=pattern(#blocks.block1,3)
blocks.block2=pattern(#blocks.block2,79)
blocks.storage=pattern(#blocks.storage,211)
for _,counter in ipairs{2,13,14,29} do
  local encoded=S.writeSlot(image,counter%2,blocks,counter)
  local decoded=assert(S.readBlocks(encoded))
  T.check(decoded.block1==blocks.block1,'rotated block1 '..counter)
  T.check(decoded.block2==blocks.block2,'rotated block2 '..counter)
  T.check(decoded.storage==blocks.storage,'rotated storage '..counter)
end
T.eq(m.saveFields.saveBlock1.flags+m.saveFields.flagBytes,m.saveFields.saveBlock1.vars,'own flags meet own vars')
T.eq(m.saveFields.bag.capacities[1],20,'Ruby item pocket is 20, not Emerald 30')
T.eq(m.saveFields.bag.capacities[2],20,'Ruby key item pocket is 20')
S.setLayout(m.save,m.substructOrders,m.saveFields,'sapphire')
T.eq(S.defaultMetGame,1,'shared codec retains Sapphire origin')
T.finish('Ruby save layout and unencrypted codec')
