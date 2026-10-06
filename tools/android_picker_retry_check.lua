package.path='./?.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Android completed picker retry')
local files={['pick_done.flag']='picked_rom.gb'}
love.filesystem.getInfo=function(path) return files[path] and {type='file'} or nil end
love.filesystem.read=function(path) return files[path] end
love.filesystem.remove=function(path) files[path]=nil;return true end
love.filesystem.getDirectoryItems=function() return {} end
local I=require('src.import.RomImporter');local V=require('src.core.GameVersion')
local ready={};for _,id in ipairs(V.ORDER) do ready[id]=true end
local launcher=setmetatable({android=true,ready=ready,failedRoms={['picked_rom.gb']=true,other=true},workState='idle'},{__index=I})
launcher:focus(true)
T.eq(launcher.failedRoms['picked_rom.gb'],nil,'new completed pick can retry same native basename')
T.check(launcher.failedRoms.other,'unrelated failed files stay skipped');T.eq(files['pick_done.flag'],nil,'completion acknowledgement consumed once')
files['pick_done.flag']='picked_rom.gb';launcher.pickPending=true;launcher.pickTimer=0;launcher.focus=function() files['pick_done.flag']=nil;launcher.notified=true end
launcher:_pollPickedFiles(0.6);T.check(launcher.notified and not launcher.pickPending,'completion wakes Lua after Android copy thread finishes')
T.finish()
