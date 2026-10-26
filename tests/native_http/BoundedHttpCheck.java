// Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package org.love2d.android;
import java.io.*;
import java.net.*;
import java.util.*;
import org.json.JSONObject;
public final class BoundedHttpCheck {
    static int checks=0;static final List<Connection> seen=Collections.synchronizedList(new ArrayList<>());
    static void check(boolean value,String label) {checks++;if(!value)throw new AssertionError(label);}
    static final class Connection extends HttpURLConnection {
        final ByteArrayOutputStream sent=new ByteArrayOutputStream();boolean closed;
        Connection(URL url) {super(url);seen.add(this);}
        public void connect() {} public boolean usingProxy(){return false;}
        public synchronized void disconnect(){closed=true;notifyAll();}
        public OutputStream getOutputStream(){return sent;}
        public int getResponseCode(){return url.getPath().startsWith("/redirect") || url.getPath().equals("/downgrade") ? 307:200;}
        public String getHeaderField(String name) {
            if(name.equals("Location"))return (url.getPath().equals("/downgrade")?"http":"https")+"://fixture.invalid/target";
            if(name.equals("Content-Length"))return url.getPath().equals("/partial")?"100":null;
            return null;
        }
        public InputStream getInputStream() {
            if(url.getPath().equals("/slow"))return new InputStream(){public int read()throws IOException{
                synchronized(Connection.this){while(!closed){try{Connection.this.wait(1000);}catch(InterruptedException e){throw new IOException(e);}}}
                throw new IOException("closed by deadline");
            }};
            byte[] bytes=url.getPath().equals("/post")?"private server reply".getBytes():new byte[]{0,(byte)255,13,10};
            if(url.getPath().equals("/chunked"))bytes=new byte[100];
            return new ByteArrayInputStream(bytes);
        }
    }
    static JSONObject request(String method,String path)throws Exception {
        JSONObject r=new JSONObject();r.put("boundedVersion",1);r.put("method",method);r.put("url","https://fixture.invalid"+path);
        r.put("httpsOnly",true);r.put("discardBody",method.equals("POST"));r.put("maxSeconds",1);r.put("maxBytes",1024);
        r.put("userAgent","gen2recomp-mod/native_probe");r.put("accept","*/*");r.put("contentType","text/plain; charset=utf-8");
        if(method.equals("POST"))r.put("bodyBase64",java.util.Base64.getEncoder().encodeToString(new byte[]{0,(byte)255,13,10}));
        return r;
    }
    static JSONObject run(JSONObject r)throws Exception{return new JSONObject(BoundedHttp.request(r));}
    public static void main(String[] args)throws Exception {
        URL.setURLStreamHandlerFactory(protocol -> new URLStreamHandler(){protected URLConnection openConnection(URL u){return new Connection(u);}});
        JSONObject result=run(request("GET","/binary"));
        check(result.getInt("status")==200,"GET status");
        check(Arrays.equals(java.util.Base64.getDecoder().decode(result.getString("bodyBase64")),new byte[]{0,(byte)255,13,10}),"binary response");
        result=run(request("POST","/post"));
        check(!result.has("bodyBase64") && !result.has("error"),"one-way response hidden");
        Connection post=seen.get(seen.size()-1);
        check(Arrays.equals(post.sent.toByteArray(),new byte[]{0,(byte)255,13,10}),"POST bytes");
        check(post.getRequestProperty("User-Agent").equals("gen2recomp-mod/native_probe"),"fixed identity");
        check(post.getRequestProperty("Accept-Encoding").equals("identity"),"no implicit compression");
        result=run(request("POST","/redirect-post"));check(result.has("error"),"POST redirect refused");
        check(seen.stream().noneMatch(c -> c.getURL().getPath().equals("/target")),"POST never forwarded");
        check(!run(request("GET","/redirect-get")).has("error"),"GET redirect allowed");
        check(run(request("GET","/downgrade")).has("error"),"HTTPS downgrade refused");
        for(String path:new String[]{"/chunked","/partial"}) {
            JSONObject r=request("GET",path);r.put("maxBytes",path.equals("/partial")?1024:16);result=run(r);
            check(result.has("error") && !result.has("bodyBase64"),"bounded complete response");
        }
        JSONObject slow=request("GET","/slow");slow.put("maxSeconds",0.1);long start=System.nanoTime();result=run(slow);
        check(result.has("error") && System.nanoTime()-start<700000000L,"absolute deadline closes connection");
        for(String key:new String[]{"boundedVersion","maxBytes","httpsOnly"}) {
            JSONObject bad=request("GET","/binary");bad.put(key,key.equals("httpsOnly")?1:true);
            check(run(bad).has("error"),"typed wire fields");
        }
        JSONObject bad=request("POST","/post");bad.put("url","http://fixture.invalid/post");check(run(bad).has("error"),"POST HTTPS required");
        bad=request("GET","/binary");bad.put("url","file:///secret");check(run(bad).has("error"),"local file rejected");
        System.out.println("Native HTTP Java: "+checks+" PASS; URLConnection fixture, not Android TLS");
    }
}
