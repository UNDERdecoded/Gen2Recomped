"""Compile the production storage JNI bridge and exercise it in a real JVM.

The activity is loaded outside the system class path to reproduce an app
class that FindClass cannot see from the worker's native-call context.
No Android SDK or device is needed. Uses installed Java and C++ tools.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
native = (ROOT / 'mobile/android/love/src/jni/love/src/common/android.cpp').read_text()
java = (ROOT / 'mobile/android/love/src/main/java/org/love2d/android/GameActivity.java').read_text()


def method(source, signature):
    start = source.index(signature)
    pos = source.index('{', start)
    depth, end = 1, pos + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


bridge = method(native, 'static bool callStaticBool(')
mkdir = method(java, 'public static boolean mkdirsReal(')
javac = shutil.which('javac')
assert javac, 'javac is required'
java_home = Path(os.environ.get('JAVA_HOME', str(Path(javac).resolve().parent.parent)))
if not (java_home / 'include/jni.h').exists() and os.name == 'nt':
    java_home=Path('C:/Program Files/Java/jdk-17')
    javac=str(java_home/'bin/javac.exe')
compiler = os.environ.get('CXX') or shutil.which('clang++') or shutil.which('g++')
if not compiler and os.name == 'nt':
    compiler = str(Path('G:/2022.3.21f1/Editor/Data/PlaybackEngines/AndroidPlayer/NDK/toolchains/llvm/prebuilt/windows-x86_64/bin/clang++.exe'))
assert compiler and Path(compiler).exists(), 'Set CXX to an installed C++ compiler'

cpp = '''#include <jni.h>
static JNIEnv *activeEnv;
static jobject activeActivity;
static void *SDL_AndroidGetJNIEnv() { return activeEnv; }
static void *SDL_AndroidGetActivity() {
 return activeEnv && activeActivity ? activeEnv->NewLocalRef(activeActivity) : nullptr;
}
''' + bridge + '''
extern "C" JNIEXPORT jboolean JNICALL Java_BridgeCheck_invoke(
 JNIEnv *env, jclass, jobject activity, jstring name, jstring sig, jstring arg, jboolean noEnv) {
 activeEnv=noEnv ? nullptr : env;activeActivity=activity;
 const char *n=env->GetStringUTFChars(name,nullptr);
 const char *s=env->GetStringUTFChars(sig,nullptr);
 const char *a=arg ? env->GetStringUTFChars(arg,nullptr) : nullptr;
 bool result=callStaticBool(n,s,a);
 if(a)env->ReleaseStringUTFChars(arg,a);
 env->ReleaseStringUTFChars(sig,s);env->ReleaseStringUTFChars(name,n);
 activeEnv=nullptr;activeActivity=nullptr;
 return result;
}
extern "C" JNIEXPORT jboolean JNICALL Java_BridgeCheck_lookupFails(JNIEnv *env,jclass) {
 jclass cls=env->FindClass("org/love2d/android/GameActivity");
 bool failed=cls==nullptr && env->ExceptionCheck();
 env->ExceptionClear();if(cls)env->DeleteLocalRef(cls);
 return failed;
}
'''
activity_source = '''package org.love2d.android;
import java.io.File;
public class GameActivity {
''' + mkdir + '''
 public static boolean hasStorageAccess() {return true;}
 public static boolean requestStorageAccess() {return false;}
 public static boolean throwStorageError() {throw new SecurityException("denied");}
}
'''
test = '''import java.io.*;import java.net.*;
public class BridgeCheck {
 static native boolean invoke(Object activity,String name,String sig,String arg,boolean noEnv);
 static native boolean lookupFails();
 interface Call {boolean run();}
 static boolean worker(Call call)throws Exception {
  boolean[] result={false};Throwable[] error={null};
  Thread t=new Thread(()->{try{result[0]=call.run();}catch(Throwable e){error[0]=e;}},"ROM-import-worker");
  t.start();t.join();if(error[0]!=null)throw new AssertionError(error[0]);return result[0];
 }
 static int checks=0;
 static void check(boolean ok,String message) {checks++;if(!ok)throw new AssertionError(message);}
 public static void main(String[] args)throws Exception {
  System.load(args[0]);
  URLClassLoader loader=new URLClassLoader(new URL[]{new File(args[1]).toURI().toURL()},null);
  Object activity=loader.loadClass("org.love2d.android.GameActivity").getConstructor().newInstance();
  String sig="(Ljava/lang/String;)Z";
  check(worker(()->lookupFails()),"baseline worker FindClass did not reproduce missing app class");
  for(String layout:new String[]{"default","custom"}) {
   File nested=new File(args[2],layout+"/emerald/data/generated");
   check(worker(()->invoke(activity,"mkdirsReal",sig,nested.getAbsolutePath(),false)),"worker directory creation failed");
   check(nested.isDirectory(),"nested directory missing");
   check(worker(()->invoke(activity,"mkdirsReal",sig,nested.getAbsolutePath(),false)),"existing directory rejected");
  }
  File direct=new File(args[2],"foreground");
  check(invoke(activity,"mkdirsReal",sig,direct.getAbsolutePath(),false),"foreground bridge regressed");
  File blocked=new File(args[2],"file");blocked.createNewFile();
  check(!worker(()->invoke(activity,"mkdirsReal",sig,blocked.getAbsolutePath(),false)),"file accepted as directory");
  check(worker(()->invoke(activity,"hasStorageAccess","()Z",null,false)),"no-argument success failed");
  check(!worker(()->invoke(activity,"requestStorageAccess","()Z",null,false)),"false Java result changed");
  check(!worker(()->invoke(activity,"missing","()Z",null,false)),"missing method did not fail safely");
  check(!worker(()->invoke(activity,"mkdirsReal","()Z",null,false)),"wrong signature did not fail safely");
  check(!worker(()->invoke(activity,"throwStorageError","()Z",null,false)),"Java exception escaped bridge");
  check(!worker(()->invoke(null,"hasStorageAccess","()Z",null,false)),"missing activity did not fail safely");
  check(!worker(()->invoke(activity,"hasStorageAccess","()Z",null,true)),"missing JNI environment did not fail safely");
  check(worker(()->invoke(activity,"hasStorageAccess","()Z",null,false)),"previous failure poisoned next JNI call");
  loader.close();System.out.println("Android storage JNI: "+checks+" checks passed in a real JVM");
 }
}
'''
with tempfile.TemporaryDirectory(prefix='android-storage-jni-') as td:
    out = Path(td)
    (out / 'bridge.cpp').write_text(cpp)
    (out / 'GameActivity.java').write_text(activity_source)
    (out / 'BridgeCheck.java').write_text(test)
    includes = ['-I'+str(java_home / 'include'), '-I'+str(java_home / 'include' / ('win32' if os.name=='nt' else 'linux'))]
    if os.name == 'nt':
        # This standalone JNI DLL uses only the JVM's function table and
        # requires no C runtime. NDK clang is sufficient on this Windows host.
        headers=out/'headers';headers.mkdir();(headers/'stdio.h').write_text('#pragma once\n')
        obj=out/'bridge.obj';library=out/'bridge.dll'
        subprocess.run([compiler,'--target=x86_64-pc-windows-msvc','-std=c++11','-c',str(out/'bridge.cpp'),'-o',str(obj),'-I'+str(headers),*includes],check=True)
        linker=Path(compiler).with_name('ld.lld.exe')
        subprocess.run([str(linker),'-flavor','link','/dll','/noentry','/nodefaultlib','/out:'+str(library),str(obj)],check=True)
    else:
        library=out/'bridge.so'
        subprocess.run([compiler,'-std=c++11','-shared','-fPIC',*includes,str(out/'bridge.cpp'),'-o',str(library)],check=True)
    subprocess.run([javac,'-d',str(out/'activity'),str(out/'GameActivity.java')],check=True)
    subprocess.run([javac,'-d',str(out/'check'),str(out/'BridgeCheck.java')],check=True)
    subprocess.run([str(java_home/'bin'/('java.exe' if os.name=='nt' else 'java')),'-Xcheck:jni','-cp',str(out/'check'),'BridgeCheck',str(library),str(out/'activity'),str(out/'storage')],check=True)
