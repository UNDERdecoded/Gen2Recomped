-- Pure image-table pose rules. Observing a pose never advances a game clock.
local P={}
local Version=require('src.core.GameVersion')
local axis={down=0,up=1,left=2,right=2}
local function number(v,default)
  v=tonumber(v);return v and v==v and math.abs(v)<math.huge and v or default
end
local function sequence(rows,t,loop)
  t=math.max(0,math.floor(number(t,0)))
  local total=0;for _,r in ipairs(rows)do total=total+r[2]end
  if loop then t=t%total end
  for _,r in ipairs(rows)do if t<r[2]then return r[1],false end;t=t-r[2]end
  return rows[#rows][1],true
end
local field={{0,4},{1,4},{2,4},{3,4},{4,8}}
local seeker={{0,4},{1,4},{5,4},{6,4}}
local bike={{0,4},{1,4},{2,4},{3,4}}
for _=1,7 do seeker[#seeker+1]={7,4};seeker[#seeker+1]={8,4};bike[#bike+1]={4,4};bike[#bike+1]={5,4}end
for _,r in ipairs({{6,4},{1,4},{0,4}})do seeker[#seeker+1]=r end
for _,r in ipairs({{3,4},{2,4},{1,4},{0,4}})do bike[#bike+1]=r end
local take={{0,4},{1,4},{2,4},{3,4}}
local put={{3,4},{2,6},{1,6},{0,6}}
local sidePut={{3,4},{2,4},{1,4},{0,4}}
local hooked={{2,6},{3,6},{2,6},{3,6},{3,30}}
function P.fieldMoveFrame(t,kind)
  local frame=sequence(kind=='vs_seeker'and seeker or kind=='vs_seeker_bike'and bike or field,t)
  return frame
end
function P.fishingFrame(facing,anim,t)
  return sequence(anim=='hooked'and hooked or anim=='putaway'and((facing=='left'or facing=='right')and sidePut or put)or take,t,anim=='hooked')
end
function P.fishingAbsFrame(facing,frame)
  return (facing=='left'or facing=='right')and number(frame,3)or(facing=='up'and 4 or 8)+number(frame,3)
end
function P.fishingOffset(frame,facing)
  return (frame==1 or frame==2 or frame==3)and(facing=='left'and -8 or 8)or 0,
    frame==5 and -8 or(frame==10 or frame==11)and 8 or 0
end
function P.pose(sprite,facing,phase,flip,opts)
  if not sprite then return 0,false end
  local n=sprite.frameCount or 1;local a=axis[facing]or 0;local mirrored=facing=='right';opts=opts or{}
  if opts.fishing and n>=12 then return P.fishingAbsFrame(facing,math.max(0,math.min(3,number(opts.fishFrame,3)))),mirrored end
  if opts.frame~=nil then return math.max(0,math.min(n-1,number(opts.frame,0))),mirrored end
  if n<=1 or sprite.inanimate then return 0,false end
  if opts.bow and n>9 then return 9,false end
  if opts.fieldMove and n>=5 then local f=number(opts.fieldMoveFrame,4);return f>=n and 0 or f,false end
  if opts.running~=nil and n>=18 then
    local profile=package.loaded['src.core.game3.profile']
    local ok,row
    if profile and profile.forSession then ok,row=pcall(profile.forSession)end
    local frames=ok and row and row.field and row.field.runFrames
    local r=frames and frames[opts.running==1 and 2 or 1];r=r and r[flip and'a'or'b']
    if r and r[facing]then return r[facing],mirrored end
    local id=Version.get()
    if id=='emerald'or id=='ruby'or id=='sapphire'then
      return opts.running==1 and 9+a or 12+a*2+(flip and 0 or 1),mirrored
    end
    return 9+a*3+(opts.running==1 and(flip and 1 or 2)or 0),mirrored
  end
  if sprite.nativeStandOrder and sprite.nativeWalker==false then return sprite.nativeStandOrder[a+1]or 0,mirrored end
  if (phase==1 or phase==true)and n>=9 then return 3+a*2+(flip and 0 or 1),mirrored end
  return math.min(a,n-1),mirrored
end
function P.avatarState(player)
  if not player then return 'NORMAL'end
  if number(player.fieldMoveAnim,0)>0 then return 'FIELD_MOVE'end
  if player.underwater then return 'UNDERWATER'end
  if player.fishing then return 'FISHING'end
  if player.surfing and not player.dismounting or player.flyRide or player.surfJumpFrame and player.surfJumpFrame()then return 'SURFING'end
  if player.biking then return player.bikeType=='acro'and'ACRO_BIKE'or'MACH_BIKE'end
  return player.watering and'WATERING'or'NORMAL'
end
function P.avatarGraphicsId(state,female,avatars,who)
  local rows=avatars and avatars[who or'player'];if not rows then return nil end
  local key=female and'female'or'male';local normal
  for _,r in ipairs(rows)do if r.state==state then return r[key]end;if r.state=='NORMAL'then normal=r[key]end end
  return normal
end
return P
