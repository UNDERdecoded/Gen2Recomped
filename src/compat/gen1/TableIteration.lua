-- LuaJIT's Lua-5.1 pairs/next do not consult __pairs. Only registered typed
-- views opt into snapshots; all ordinary tables keep their original C path.
-- Load this infrastructure before opening any mod mutation journal.
local nativePairs,nativeNext=pairs,next
local views=setmetatable({},{__mode='k'})
local M={rawPairs=nativePairs,rawNext=nativeNext}
function M.register(view,reader,state,nextReader)
  assert(type(view)=='table'and type(reader)=='function','invalid typed table view')
  views[view]={reader=reader,state=state,nextReader=nextReader}
  return view
end
function M.unregister(view)views[view]=nil end
function M.snapshot(view)
  local spec=views[view]
  if not spec then return nil end
  local result=spec.reader(spec.state,view)
  assert(type(result)=='table'and result~=view,'invalid typed table snapshot')
  return result
end
local function viewPairs(value)
  local spec=views[value]
  if not spec then return nativePairs(value)end
  return nativePairs(M.snapshot(value))
end
local function viewNext(value,key)
  local spec=views[value]
  if not spec then return nativeNext(value,key)end
  if spec.nextReader then return spec.nextReader(spec.state,key)end
  return nativeNext(M.snapshot(value),key)
end
-- Installed once at module load, before Loader's entry/lifecycle snapshots.
-- Later mod wrappers remain free to forward to these just like normal pairs.
pairs,next=viewPairs,viewNext
return M
