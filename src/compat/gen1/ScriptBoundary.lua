-- Native owners open a scope; source base calls can consume its body once.
-- Queries made between native phases cannot advance another script clock.
local M={}
local scopes=require('src.compat.gen1.CoroutineScopes').new()
local BODY={}
local unpack=table.unpack or unpack
local function pack(...)return {n=select('#',...),...}end
function M.invoke(name)
  local s=scopes:find(name)
  if not s then return nil,'script operation belongs to its native phase'end
  if s.failed then error(s.failure,0)end
  if not s.called then
    s.called=true
    local claim=scopes:push(BODY,nil,s)
    local r=pack(pcall(s.body))
    local retired=s.closed or claim.closed
    scopes:close(claim)
    s.body=nil
    if not r[1]then s.failed=true;s.failure=r[2];error(r[2],0)end
    if retired then error('native script phase retired while suspended',0)end
    s.result={n=r.n-1};for i=2,r.n do s.result[i-1]=r[i]end
  end
  if not s.result then return nil,'native script phase is already executing' end
  return unpack(s.result,1,s.result.n)
end
function M.dispatch(name,body,source,...)
  local s=scopes:push(name);s.body=body
  local result=pack(pcall(source,...))
  local retired,failed,failure=s.closed,s.failed,s.failure
  scopes:close(s)
  -- A wrapper cannot swallow a failing native command and retry it.
  if failed then error(failure,0)end
  if retired then error('native script phase retired while suspended',0)end
  if not result[1]then error(result[2],0)end
  return unpack(result,2,result.n)
end
function M.active(name)return scopes:find(name)~=nil end
return M
