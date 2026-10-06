from pathlib import Path
import subprocess,tempfile
source=Path('mobile/android/love/src/main/java/org/love2d/android/GameActivity.java').read_text()
def method(signature):
 start=source.index(signature);at=source.index('{',start);depth=1;end=at+1
 while depth:
  depth+= (source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end]
code='''import java.io.*;import java.nio.file.*;import java.util.concurrent.*;
public class PickPublicationCheck {
 static class Log {static void d(String a,String b){} static void e(String a,String b,Throwable t){}}
'''+method('boolean publishPickedFile(')+method('boolean copyAssetFile(')+'''
 static void check(boolean b,String m) {if(!b)throw new AssertionError(m);}
 public static void main(String[] args)throws Exception {
  PickPublicationCheck p=new PickPublicationCheck();File root=new File(args[0]);
  for(String name:new String[]{"default","custom"}) {
   File dir=new File(root,name);dir.mkdirs();File dest=new File(dir,"picked_rom.gb");
   CountDownLatch begun=new CountDownLatch(1),go=new CountDownLatch(1);
   byte[] bytes=new byte[16*1024*1024];bytes[bytes.length-1]=99;
   InputStream stream=new ByteArrayInputStream(bytes) {public synchronized int read(byte[] b,int o,int l) {begun.countDown();try{go.await();}catch(InterruptedException e){throw new RuntimeException(e);}return super.read(b,o,l);}};
   boolean[] result={false};Thread t=new Thread(()->result[0]=p.publishPickedFile(stream,dest));t.start();begun.await();
   check(!dest.exists(),"partial ROM was visible to Lua");go.countDown();t.join();check(result[0],"full file publication failed");
   byte[] read=Files.readAllBytes(dest.toPath());check(read.length==bytes.length && read[read.length-1]==99,"published bytes differ");
   check(!new File(dir,"picked_rom.gb.part").exists(),"staging residue");
   check(!p.publishPickedFile(new InputStream(){public int read()throws IOException{throw new IOException("provider interrupted");}},dest),"failed stream published");
   check(Files.size(dest.toPath())==bytes.length,"failure destroyed previous complete file");
   check(!new File(dir,"picked_rom.gb.part").exists(),"failure staging residue");
   check(p.publishPickedFile(new ByteArrayInputStream(new byte[]{4,5,6}),dest),"retry failed");check(Files.size(dest.toPath())==3,"retry did not replace complete file");
  }
  System.out.println("Android picker: atomic 16 MiB publication, failed streams and retries pass in default/custom folders");
 }
}
'''
with tempfile.TemporaryDirectory(prefix='gen2-picker-') as tmp:
 path=Path(tmp,'PickPublicationCheck.java');path.write_text(code)
 subprocess.run(['javac',str(path)],check=True)
 subprocess.run(['java','-cp',tmp,'PickPublicationCheck',tmp],check=True)
