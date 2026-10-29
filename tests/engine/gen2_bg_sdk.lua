-- Native BG API first import from a real SDK entry, with no ROM or renderer.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local before=Version.get()
for _,edition in ipairs({'gold','silver','crystal'})do
  Version.set(edition)
  local data=T.fixtures.fresh();data.constants.gen=2
  local run=T.sdk.loadMods({'mods/bg_probe'},{data=data,fs=T.sdk.memfs({
    ['mods/bg_probe/manifest.json']=[[{"id":"bg_probe","name":"BG probe","version":"1.0.0","api":2,"entry":"main.lua"}]],
    ['mods/bg_probe/main.lua']=[[
      local mod=...
      local Bg=require('src.battle.gen2.BgEffects')
      local pool=Bg.new({}, {battleTurn=0})
      mod.exports.pool=pool
      mod.exports.enter=function()
        pool:queue('BATTLE_BG_EFFECT_ENTER_MON',0,1,0)
        pool:playFrame()
        return pool.picSize.player
      end
    ]],
  })})
  T.eq(#run.errors,0,'actual SDK entry can import the real engine BG module')
  local api=run.loader.exports.bg_probe
  T.check(api and api.pool~=nil,'native BG owner reaches the unmodified SDK export path')
  if api then
    T.eq(api.enter(),2,'SDK consumer runs the actual native entry state machine')
    local row=api.pool:queue(0x25,0,1,0)
    T.eq(row.func,edition=='crystal'and'BATTLE_BG_EFFECT_BODY_SLAM'or'BATTLE_BG_EFFECT_WOBBLE_MON',
      'actual native host edition resolves raw BG ids inside a mod entry')
  end
  require('src.mods.Loader').teardown();run.release()
end
Version.set(before)
T.finish('GSC background state machines through actual SDK module lookup')
