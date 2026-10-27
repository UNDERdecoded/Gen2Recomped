-- LeafGreen is its own cartridge; only FRLG gameplay/UI contracts are shared.
package.path = './?.lua;./?/init.lua;' .. package.path
love = love or require('tests.love_stub')
local T = require('tests.harness')
local V = require('src.core.GameVersion')
local R = require('src.import.RomRevisions')
local Bag = require('src.inventory.Bag')
local previous = V.get()
local leaf = V.info('leafgreen')
T.eq(leaf.sha1, '574fa542ffebb14be69902d1d36f1ec0a4afd71e', 'canonical LeafGreen Rev 0 hash')
T.eq(leaf.importable, true, 'LeafGreen import enabled')
T.eq(leaf.generation, 3, 'LeafGreen native generation')
T.eq(leaf.cachePrefix, 'leafgreen/', 'independent cartridge cache')
T.eq(leaf.saveSuffix, '_leafgreen', 'independent cartridge save')
T.eq(R.acceptedRow(leaf.sha1), 'leafgreen', 'revision explanation agrees with importer')
T.eq(R.acceptedRow('7862c67bdecbe21d1d69ce082ce34327e1c6ed5e'), nil, 'unmapped Rev 1 is still rejected')
for _, id in ipairs{'firered','leafgreen'} do
  V.set(id)
  T.eq(V.isFRLG(), true, id .. ' uses FRLG contracts')
  local save = { inventory = {}, bagOrder = {} }
  local data = {constants={gen3Bag={pockets={ITEM=42,KEY_ITEM=30,BALL=13,TM_HM=58,BERRIES=43}}},
    items={TM39={pocket='TM_HM',machine={kind='TM',move='ROCK_TOMB'}},TM_CASE={pocket='KEY_ITEM',keyItem=true}}}
  T.eq(Bag.add(save,'TM39',1,data),true,id .. ' accepts native TM')
  T.eq(save.inventory.TM_CASE,1,id .. ' creates the native TM CASE')
end
V.set('emerald')
T.eq(V.isFRLG(),false,'Hoenn does not inherit Kanto rules')
local order={};for i,id in ipairs(V.ORDER)do order[id]=i end
T.eq(order.leafgreen,order.firered+1,'LeafGreen is reachable beside FireRed')
local gen3Between=order.emerald>order.leafgreen
for i=order.leafgreen+1,order.emerald-1 do
  gen3Between=gen3Between and V.info(V.ORDER[i]).generation==3
end
T.check(gen3Between,'Emerald follows the Kanto pair with only Gen3 siblings between')
V.set(previous)
T.finish('LeafGreen registration and FRLG contracts')
