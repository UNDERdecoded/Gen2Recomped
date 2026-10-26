-- Removing exact owners under a screen must preserve screens opened on exit.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness');local Stack=require('src.core.StateStack')
local world,cover,replacement={name='world'},{name='cover'},{name='replacement'}
local stack=setmetatable({states={}},{__index=Stack});local exits={}
local a={name='a',exit=function()exits[#exits+1]='a'end}
local b={name='b',exit=function()exits[#exits+1]='b';stack:push(replacement)end}
stack.states={world,a,cover,b}
T.eq(stack:removeAll({a,b,a}),2);T.eq(#stack.states,3);T.eq(stack.states[1],world);T.eq(stack.states[2],cover);T.eq(stack:top(),replacement)
T.eq(table.concat(exits,','),'b,a');T.eq(stack:removeAll({a,b}),0);T.eq(#exits,2)
-- A failing exit cannot leave the remaining selected states installed.
local bad={name='bad',exit=function()error('selected exit failure')end};local good={name='good',exit=function()exits[#exits+1]='good'end}
stack.states={world,good,cover,bad};T.raises(function()stack:removeAll({good,bad})end,'selected exit failure','propagate failure after retiring all selected owners')
T.eq(#stack.states,2);T.eq(stack:top(),cover);T.eq(exits[#exits],'good')
T.finish('native exact-state retirement preserves covering and replacement screens')
