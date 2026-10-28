package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local read=require('tools.native-atlas.cpu-gpu').install(love)
local T=require('tests.harness')
require('tools.native-atlas.resources').run(T,read)
T.finish('native atlas resource lifecycle')
