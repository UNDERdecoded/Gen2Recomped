-- Native owners open a scope; source base calls can consume its body once.
-- Queries made between native phases cannot advance another script clock.
local M={}
local scopes={}
local unpack=table.unpack or unpack
local function pack(...)return {n=select('#',...),...}end
function M.invoke(name)
  local s=scopes[name]
  if not s then return nil,'script operation belongs to its native phase'end
  if s.failed then error(s.failed,0)end
  if not s.called then
    s.called=true
    local r=pack(pcall(s.body))
    if not r[1]then s.failed=r[2];error(r[2],0)end
    s.result={n=r.n-1};for i=2,r.n do s.result[i-1]=r[i]end
  end
  if not s.result then return nil,'native script phase is already executing' end
  return unpack(s.result,1,s.result.n)
end
function M.dispatch(name,body,source,...)
  local previous=scopes[name]
  local s={body=body};scopes[name]=s
  local result=pack(pcall(source,...));scopes[name]=previous
  -- A wrapper cannot swallow a failing native command and retry it.
  if s.failed then error(s.failed,0)end
  if not result[1]then error(result[2],0)end
  return unpack(result,2,result.n)
end
function M.active(name)return scopes[name]~=nil end
return M
