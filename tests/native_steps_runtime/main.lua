-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
function love.load()
  local count=0
  local function check(ok,why)count=count+1;assert(ok,why)end
  local Steps=require('src.mods.Steps')
  local J=require('src.core.StepJournal')
  local Json=require('src.link.Json')
  -- Only the sensor capability is synthetic. Reads, staged writes, native
  -- atomic replacement and receipt reload use this real LÖVE identity.
  love.system.stepJournalVersion=function()return 1 end
  love.system.syncHealthSteps=function()return false end
  local function publish(total)
    assert(love.filesystem.write(J.FILE,Json.encode({version=1,epoch='nativeReceiptProbe',
      source='healthkit',total=total,from='2026-10-25T10:00:00Z',to='2026-10-25T11:00:00Z'})))
  end
  local function mod(id)return {manifest={id=id,permissionSet={steps=true}}}end
  local loader={};local a=Steps.forMod(loader,mod('a'));local b=Steps.forMod(loader,mod('b'))
  publish(123);local before=love.filesystem.read(J.FILE)
  check(a:poll().steps==123,'first real filesystem delivery')
  check(b:poll().steps==123,'independent real receipt')
  check(love.filesystem.read(J.FILE)==before,'native journal remains unchanged')
  check(a:poll()==nil,'persisted receipt prevents duplicate')
  a=Steps.forMod(loader,mod('a'))
  check(a:poll()==nil,'replacement reads the committed receipt')
  publish(200);check(a:poll().steps==77,'actual atomic replacement retains the right cursor')
  local write=love.filesystem.write
  love.filesystem.write=function(path,bytes)
    if path==J.RECEIPTS..'.tmp' then return nil,'injected full disk' end
    return write(path,bytes)
  end
  publish(250);check(a:poll()==nil,'failed staging cannot consume a delivery')
  love.filesystem.write=write
  check(a:poll().steps==50,'real receipt retry retains the missed delta')
  check(b:poll().steps==127,'one consumer never consumes another receipt')
  check(love.filesystem.getInfo(J.RECEIPTS,'file')~=nil,'committed receipt exists in the native identity')
  check(love.filesystem.getInfo(J.RECEIPTS..'.tmp')==nil,'atomic publication leaves no staging file')
  Steps.unloadAll();check(not a:available(),'teardown retires real filesystem facades')
  print('Native steps LOVE: '..count..' PASS')
  love.event.quit(0)
end
function love.errorhandler(why)
  print(tostring(why));love.event.quit(1)
  return function()return 1 end
end
