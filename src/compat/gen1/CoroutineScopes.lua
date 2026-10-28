-- Dynamic native scopes may be borrowed by an actively resumed child. A
-- suspended child cannot lend its scope to an unrelated native operation.
local M={}
local MAIN={}
-- Retirement crosses phase/attribution registries. A source coroutine that
-- outlives a borrowed native phase cannot acquire another caller's authority.
local revoked=setmetatable({},{__mode='k'})
local function thread()
  local co,main=coroutine.running()
  return main and MAIN or co or MAIN
end
function M.retired()return revoked[thread()]==true end
local function visible(frame,co)
  if frame.closed then return false end
  local creator=frame.creator
  return creator==co or creator==MAIN or coroutine.status(creator)=='normal'
end
local function previous(frame,key)
  repeat frame=frame and frame[key] until not frame or not frame.closed
  return frame
end
local function within(frame,ancestor)
  while frame do
    if frame==ancestor then return true end
    frame=frame.parent
  end
  return false
end
local function selectFrame(head,key,co)
  local frame=head
  -- A resumed coroutine's own phase wins over an unrelated caller's newer
  -- phase. Creation order alone does not describe coroutine ancestry.
  while frame do
    if not frame.closed and frame.creator==co then return frame end
    frame=frame[key]
  end
  local selected
  frame=head
  while frame do
    if visible(frame,co)then
      if not selected or within(frame,selected)then selected=frame
      elseif not within(selected,frame)then
        -- Lua exposes running/suspended status, not a resumer ancestry API.
        -- Independent native roots cannot safely lend a phase to this child.
        return nil,'ambiguous native coroutine scope'
      end
    end
    frame=frame[key]
  end
  return selected
end
function M.new()
  -- Weak heads do not keep an abandoned suspended coroutine (and the native
  -- body on its stack) alive. Live dispatch calls retain their own frame.
  local names=setmetatable({},{__mode='v'})
  local latest=setmetatable({},{__mode='v'})
  local locals=setmetatable({},{__mode='kv'})
  local stack={}
  function stack:find(name)
    local co=thread()
    if revoked[co] or locals[co]and locals[co].closed then return nil,'native coroutine scope retired'end
    return selectFrame(names[name],'previousName',co)
  end
  function stack:push(name,value,parent)
    local co=thread()
    assert(not revoked[co]and not(locals[co]and locals[co].closed),'native coroutine scope retired')
    parent=parent or selectFrame(latest[1],'previousAll',co)
    assert(not parent or not parent.closed,'native coroutine scope retired')
    local frame={name=name,value=value,creator=co,parent=parent,
      previousName=names[name],previousAll=latest[1],previousLocal=locals[co]}
    if parent then
      parent.children=parent.children or setmetatable({},{__mode='k'})
      parent.children[frame]=true
    end
    names[name],latest[1],locals[co]=frame,frame,frame
    return frame
  end
  local function retire(frame,forced)
    if frame.closed then return end
    frame.closed=true
    if forced and frame.creator~=MAIN and frame.creator~=thread()then revoked[frame.creator]=true end
    -- A parent returning retires nested dispatches that yielded in a child.
    -- Their later finally blocks cannot restore an expired native phase.
    if frame.children then for child in pairs(frame.children)do retire(child,true)end end
    if frame.parent then frame.parent.children[frame]=nil end
    if names[frame.name]==frame then names[frame.name]=previous(frame,'previousName')end
    if latest[1]==frame then latest[1]=previous(frame,'previousAll')end
    frame.value,frame.body,frame.result=nil,nil,nil
  end
  function stack:close(frame)
    retire(frame,false)
    if locals[frame.creator]==frame then locals[frame.creator]=frame.previousLocal end
  end
  return stack
end
return M
