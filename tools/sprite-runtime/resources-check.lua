package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local read,asset=require('tools.sprite-runtime.cpu-gpu').install(love)
T.eq(package.loaded['src.core.Game'],nil)
require('tools.sprite-runtime.resources').run(T,read,asset)
T.finish('owned sprite resources')
