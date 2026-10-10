local P={}
function P.open(executable,request)
 if love.system.getOS()~="Windows"then
  local shell=require("src.core.HostShell")
  return shell.popen(shell.quote(executable).." --request "..shell.quote(request),"r")
 end
 local ffi=require("ffi")
 ffi.cdef[[
 typedef unsigned short TR_WCHAR;
 typedef struct {unsigned long nLength;void *lpSecurityDescriptor;int bInheritHandle;} TR_SECURITY;
 typedef struct {unsigned long cb;TR_WCHAR *lpReserved,*lpDesktop,*lpTitle;
 unsigned long dwX,dwY,dwXSize,dwYSize,dwXCountChars,dwYCountChars,dwFillAttribute,dwFlags;
 unsigned short wShowWindow,cbReserved2;unsigned char *lpReserved2;
 void *hStdInput,*hStdOutput,*hStdError;} TR_STARTUP;
 typedef struct {void *hProcess,*hThread;unsigned long dwProcessId,dwThreadId;} TR_PROCESS;
 int __stdcall MultiByteToWideChar(unsigned int,unsigned long,const char*,int,TR_WCHAR*,int);
 int __stdcall CreatePipe(void**,void**,TR_SECURITY*,unsigned long);
 int __stdcall SetHandleInformation(void*,unsigned long,unsigned long);
 int __stdcall CreateProcessW(const TR_WCHAR*,TR_WCHAR*,void*,void*,int,unsigned long,void*,const TR_WCHAR*,TR_STARTUP*,TR_PROCESS*);
 int __stdcall CloseHandle(void*);
 int __stdcall ReadFile(void*,void*,unsigned long,unsigned long*,void*);
 unsigned long __stdcall WaitForSingleObject(void*,unsigned long);
 int __stdcall GetExitCodeProcess(void*,unsigned long*);
 ]]
 local k=ffi.load("kernel32")
 local function wide(text)
  local n=k.MultiByteToWideChar(65001,8,text,#text,nil,0)
  assert(n>0,"Invalid translator path encoding")
  local out=ffi.new("TR_WCHAR[?]",n+1)
  assert(k.MultiByteToWideChar(65001,8,text,#text,out,n)>0)
  return out
 end
 assert(not executable:find('"',1,true) and not request:find('"',1,true),"Invalid translator path")
 local reader,writer=ffi.new("void *[1]"),ffi.new("void *[1]")
 local security=ffi.new("TR_SECURITY");security.nLength=ffi.sizeof(security);security.bInheritHandle=1
 assert(k.CreatePipe(reader,writer,security,0)~=0,"Could not create translation output pipe")
 k.SetHandleInformation(reader[0],1,0)
 local startup=ffi.new("TR_STARTUP");startup.cb=ffi.sizeof(startup);startup.dwFlags=256
 startup.hStdOutput=writer[0];startup.hStdError=writer[0]
 local process=ffi.new("TR_PROCESS")
 local exe=wide(executable)
 local command=wide('"'..executable..'" --request "'..request..'"')
 local started=k.CreateProcessW(exe,command,nil,nil,1,0x08000000,nil,nil,startup,process)
 k.CloseHandle(writer[0])
 if started==0 then k.CloseHandle(reader[0]);return nil end
 k.CloseHandle(process.hThread)
 local pipe={buffer="",eof=false}
 function pipe:lines()
  local block=ffi.new("char[4096]");local count=ffi.new("unsigned long[1]")
  return function()
   while true do
    local at=self.buffer:find("\n",1,true)
    if at then local line=self.buffer:sub(1,at-1):gsub("\r$","");self.buffer=self.buffer:sub(at+1);return line end
    if self.eof then
     if #self.buffer==0 then return nil end
     local last=self.buffer;self.buffer="";return last
    end
    if k.ReadFile(reader[0],block,4096,count,nil)==0 or count[0]==0 then self.eof=true
    else self.buffer=self.buffer..ffi.string(block,count[0])end
   end
  end
 end
 function pipe:close()
  k.CloseHandle(reader[0]);k.WaitForSingleObject(process.hProcess,5000)
  local exit=ffi.new("unsigned long[1]");k.GetExitCodeProcess(process.hProcess,exit);k.CloseHandle(process.hProcess)
  return exit[0]==0
 end
 return pipe
end
return P
