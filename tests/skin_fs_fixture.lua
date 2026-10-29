-- Memory PhysFS fixture for archive-member tests; no real ZIP/GPU acceptance.
local function fixture()
  local fs, files, mounts = {}, {}, {}
  local function resolve(path)
    if files[path] then return path end
    for i=#mounts,1,-1 do
      local m=mounts[i]
      if path==m.point then return m.archive end
      if path:sub(1,#m.point+1)==m.point..'/' then
        return m.archive..'/'..path:sub(#m.point+2)
      end
    end
    return path
  end
  function fs.read(path) return files[resolve(path)] end
  function fs.write(path,data) files[path]=data; return true end
  function fs.remove(path) files[path]=nil; return true end
  function fs.getInfo(path)
    path=resolve(path)
    if files[path] then return {type='file'} end
    for key in pairs(files) do
      if key:sub(1,#path+1)==path..'/' then return {type='directory'} end
    end
  end
  function fs.getDirectoryItems(path)
    path=resolve(path)
    local out,seen={},{}
    for key in pairs(files) do
      if key:sub(1,#path+1)==path..'/' then
        local name=key:sub(#path+2):match('^[^/]+')
        if name and not seen[name] then seen[name]=true;out[#out+1]=name end
      end
    end
    table.sort(out);return out
  end
  function fs.mount(archive,point)
    if not files[archive] then return false end
    for _,m in ipairs(mounts) do if m.archive==archive then return false end end
    mounts[#mounts+1]={archive=archive,point=point};return true
  end
  function fs.unmount(archive)
    for i=#mounts,1,-1 do if mounts[i].archive==archive then table.remove(mounts,i);return true end end
    return false
  end
  function fs.createDirectory() return true end
  function fs.newFileData(bytes,name) return {contents=bytes,name=name} end
  function fs.getSaveDirectory() return '/memory-only-skin-fixture' end
  return fs
end
return fixture
