package.path='./?.lua;'..package.path
require('src.script.Gen4Commands')
local C=require('src.script.Commands')
local VM=require('src.script.Gen4ScriptVM')
local ctx={game={},save={gen4Vars={[0x4001]=7}},g4Compare=2}
for _,case in ipairs({{42,0,5,'42'},{42,1,5,'   42'},{42,2,5,'00042'},{0,2,3,'000'},{0x4001,0,2,'16385'},{4294967295,2,10,'4294967295'}}) do
 C.g4_buffer_padded_number(ctx,2,case[1],case[2],case[3])
 assert(ctx.game.stringBuffers[3]==case[4],'number formatting differs: '..ctx.game.stringBuffers[3])
end
local random=math.random;math.random=function(low,high) assert(low==0 and high==6);return 4 end
local rows=VM.lower({{name='getrandom2',args={0x4000,0x4001}}})
assert(rows[1][1]=='g4_get_random' and rows[2][1]=='wait' and rows[2][2]==1)
C[rows[1][1]](ctx,rows[1][2],rows[1][3]);assert(ctx.save.gen4Vars[0x4000]==4)
assert(ctx.g4Compare==2,'random command changed comparison state')
math.random=random
rows=VM.lower({{name='buffervaluepaddingdigits',args={2,42,2,5}}})
C[rows[1][1]](ctx,rows[1][2],rows[1][3],rows[1][4],rows[1][5])
assert(ctx.game.stringBuffers[3]=='00042')
print('Numeric dialogue padding, literal u32 values, template slots, variable random bounds and one-frame yield passed')
