-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Typed party observations share native residents, never another party/save.
local Ids=require('src.compat.gen1.BattleIds')
local M={}
local records=setmetatable({},{__mode='k'})
local environments=setmetatable({},{__mode='k'})
local Iteration=require('src.compat.gen1.TableIteration')
local stats={maxHp='hp',attack='attack',defense='defense',speed='speed',spAtk='spatk',spDef='spdef'}
local bits={PSN=8,BRN=16,FRZ=32,PAR=64}
local function uint(n,hi)return type(n)=='number'and n==n and n>=0 and n<=hi and n%1==0 end
function M.status(mon)
  if mon.status=='SLP'then return math.max(1,math.min(7,mon.sleepTurns or 1))end
  return mon.status=='PSN'and mon.toxic and 128 or bits[mon.status]or 0
end
function M.setStatus(mon,value)
  if value==nil then value=0 end
  assert(uint(value,255)and(value<=7 or({[8]=true,[16]=true,[32]=true,[64]=true,[128]=true})[value]),'invalid native status')
  mon.status=value>0 and(value<=7 and'SLP'or({[8]='PSN',[16]='BRN',[32]='FRZ',[64]='PAR',[128]='PSN'})[value])or nil
  mon.sleepTurns=value>0 and value<=7 and value or nil;mon.toxic=value==128 or nil
end
function M.new(game,valid)
  local e={game=game,data=game.data,ids=Ids.new(game.data),entries=setmetatable({},{__mode='k'}),cache=setmetatable({},{__mode='kv'}),valid=valid}
  environments[e]=true
  function e:live()
    if not self.game then return false end
    if not self.valid()or not self.ids:valid()then self:release();return false end
    return true
  end
  function e:release()
    for _,entry in pairs(self.entries)do entry.raw=nil;entry.arrays=nil end
    self.game,self.data,self.ids=nil,nil,nil;self.cache={};self.valid=function()return false end
  end
  local function vectors(d)
    if d.arrays then return d.arrays end
    local a={moves={},pp={},maxPp={},baseline={},native={}}
    for i,row in ipairs(d.raw.moves or{})do
      local def=e.data.moves[row.id]
      a.moves[i]=e.ids:read('moves',row.id);a.pp[i]=row.pp;a.baseline[i]=row.pp
      a.maxPp[i]=(def and def.pp or 0)+math.floor((def and def.pp or 0)/5)*(row.ppUps or 0)
      a.native[i]=row
    end
    d.arrays=a;return a
  end
  function e:flush()
    if not self:live()then return end
    local writes,clear={},{}
    for _,d in pairs(self.entries)do
      local a=d.arrays
      if a and d.raw then
        for i,row in ipairs(a.native)do
          assert(d.raw.moves[i]==row and e.ids:read('moves',row.id)==a.moves[i],'native moves changed during source edit')
          local def=e.data.moves[row.id];local maximum=def.pp+math.floor(def.pp/5)*(row.ppUps or 0)
          assert(a.maxPp[i]==maximum,'native maximum PP is read-only')
          assert(uint(a.pp[i],maximum),'invalid native PP')
          assert(a.pp[i]==a.baseline[i]or row.pp==a.baseline[i],'native PP changed during source edit')
          if a.pp[i]~=a.baseline[i]then writes[#writes+1]={row,a.pp[i]}end
        end
        for i in pairs(a.pp)do assert(uint(i,#a.native)and i>0,'invalid native PP slot')end
        for i,v in pairs(a.moves)do assert(a.native[i]and e.ids:read('moves',a.native[i].id)==v,'native move list is read-only')end
        for i,v in pairs(a.maxPp)do
          local row=a.native[i];local def=row and e.data.moves[row.id]
          assert(def and v==def.pp+math.floor(def.pp/5)*(row.ppUps or 0),'native maximum PP is read-only')
        end
        clear[#clear+1]=d
      end
    end
    for _,write in ipairs(writes)do write[1].pp=write[2]end
    for _,d in ipairs(clear)do d.arrays=nil end
  end
  function e:view(mon)
    if not self:live()or type(mon)~='table'then return nil end
    local old=self.cache[mon];if old then return old end
    local view={};local d={raw=mon,env=self};self.cache[mon]=view;self.entries[view]=d;records[view]=d
    setmetatable(view,{__index=function(_,key)
      if not e:live()or not d.raw then return nil end
      local m=d.raw
      if key=='species'then return e.ids:read('pokemon',m.species)end
      if key=='item'then return e.ids:read('items',m.item)end
      if key=='status'then return M.status(m)end
      if key=='friendship'or key=='happiness'then return m.happiness end
      if key=='isEgg'or key=='egg'then return require('src.pokemon.Party').isEgg(m)end
      if key=='moves'or key=='pp'or key=='maxPp'then return vectors(d)[key]end
      if stats[key]then return m.stats and m.stats[stats[key]]end
      if key=='otId'then return m.otId or m.otID end
      if key=='otSecretId'then return m.otSecretId or m.secretId end
      if key=='ivs'then
        local out={};for a,b in pairs{hp='hp',atk='attack',def='defense',spe='speed',spa='spatk',spd='spdef'}do out[a]=m.ivs and m.ivs[b]end;return out
      end
      if key=='hp'or key=='level'or key=='exp'or key=='nickname'or key=='personality'or key=='sleep'then
        return m[key=='sleep'and'sleepTurns'or key]
      end
    end,__newindex=function(_,key,value)
      assert(e:live()and d.raw,'native party view retired')
      local m=d.raw
      if key=='hp'then assert(uint(value,m.stats.hp),'invalid native HP');m.hp=value
      elseif key=='friendship'or key=='happiness'then assert(uint(value,255),'invalid native friendship');m.happiness=value
      elseif key=='nickname'then assert(type(value)=='string'and#value<=32,'invalid native nickname');m.nickname=value
      elseif key=='status'then M.setStatus(m,value)
      elseif key=='sleep'then assert(uint(value or 0,7),'invalid native sleep');m.sleepTurns=value
      elseif key=='item'then
        local item=e.ids:native('items',value);assert(value==0 or item,'unknown native item');m.item=item
      else error('native party '..tostring(key)..' belongs to its command owner',2)end
    end})
    Iteration.register(view,function(spec,source)
      assert(spec.environment and spec.environment:live(),'native party view retired')
      local out={}
      for _,key in ipairs{'species','item','hp','level','exp','nickname','personality','friendship','status','ivs','otId','otSecretId','isEgg','maxHp','attack','defense','speed','spAtk','spDef','moves','pp','maxPp'}do
        local value=source[key]
        if type(value)=='table'then local a={};for k,v in pairs(value)do a[k]=v end;value=a end
        out[key]=value
      end
      return out
    end,setmetatable({environment=e},{__mode='v'}))
    return view
  end
  return e
end
function M.resolve(view)
  local d=records[view]
  if not d then return nil,false end
  if not d.env:live()then return nil,true end
  d.env:flush();return d.raw,true,d.env.game
end
function M.flush()
  for e in pairs(environments)do e:flush()end
end
return M
