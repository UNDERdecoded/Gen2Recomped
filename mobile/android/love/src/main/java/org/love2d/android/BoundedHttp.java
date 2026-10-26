// Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package org.love2d.android;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.Semaphore;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import org.json.JSONObject;

/** Worker-only bounded transport; the existing cloud transport is unchanged. */
final class BoundedHttp {
    static final int MAX_BODY = 512 * 1024, MAX_BYTES = 16 * 1024 * 1024;
    private static final Semaphore slots = new Semaphore(16);
    private static final ScheduledThreadPoolExecutor deadlines = new ScheduledThreadPoolExecutor(3, new ThreadFactory() {
        public Thread newThread(Runnable task) {
            Thread t = new Thread(task, "bounded-http-deadline"); t.setDaemon(true); return t;
        }
    });
    static { deadlines.setRemoveOnCancelPolicy(true); }
    private static String string(JSONObject req, String key, int maximum) throws Exception {
        Object value = req.get(key);
        if (!(value instanceof String)) throw new Exception("invalid field");
        String text = (String) value;
        if (text.length() > maximum) throw new Exception("field too large");
        for (int i=0;i<text.length();i++) if (text.charAt(i)<32 || text.charAt(i)==127) throw new Exception("control character");
        return text;
    }
    private static double number(JSONObject req, String key, double minimum, double maximum) throws Exception {
        Object value=req.get(key);
        if (!(value instanceof Number)) throw new Exception("invalid number");
        double n=((Number)value).doubleValue();
        if (Double.isNaN(n) || Double.isInfinite(n) || n<minimum || n>maximum) throw new Exception("invalid bounds");
        return n;
    }
    private static boolean flag(JSONObject req,String key) throws Exception {
        Object value=req.get(key);if (!(value instanceof Boolean)) throw new Exception("invalid flag");return (Boolean)value;
    }
    private static URL url(String value, boolean secure) throws Exception {
        if (value.length()>8192) throw new Exception("URL too long");
        for (int i=0;i<value.length();i++) if (Character.isWhitespace(value.charAt(i)) || value.charAt(i)<32) throw new Exception("invalid URL");
        URL url=new URL(value);String scheme=url.getProtocol();
        if (!("https".equalsIgnoreCase(scheme) || (!secure && "http".equalsIgnoreCase(scheme))) || url.getHost().isEmpty())
            throw new Exception("unsupported protocol");
        return url;
    }
    private static int remaining(long deadline) throws Exception {
        long nanos=deadline-System.nanoTime();if (nanos<=0) throw new Exception("deadline");
        return (int)Math.min(30000,Math.max(1,TimeUnit.NANOSECONDS.toMillis(nanos)));
    }
    static String request(JSONObject req) {
        JSONObject result=new JSONObject();
        AtomicReference<HttpURLConnection> current=new AtomicReference<>();
        ScheduledFuture<?> timeout=null;boolean acquired=false;
        try {
            if (req.toString().length()>1024*1024 || number(req,"boundedVersion",1,1)!=1) throw new Exception("invalid protocol");
            String method=string(req,"method",4);
            if (!method.equals("GET") && !method.equals("POST")) throw new Exception("unsupported method");
            boolean secure=flag(req,"httpsOnly") || method.equals("POST");
            boolean discard=flag(req,"discardBody");
            URL target=url(string(req,"url",8192),secure);
            String agent=string(req,"userAgent",512),accept=string(req,"accept",512),mime=string(req,"contentType",128);
            double limit=number(req,"maxBytes",1,MAX_BYTES);
            if (Math.floor(limit)!=limit) throw new Exception("invalid byte bound");
            int maximum=(int)limit;
            double seconds=number(req,"maxSeconds",0.001,30);
            byte[] body=null;
            if (method.equals("POST")) {
                Object encoded=req.get("bodyBase64");
                if (!(encoded instanceof String) || ((String)encoded).length()>((MAX_BODY+2)/3)*4) throw new Exception("request too large");
                body=android.util.Base64.decode((String)encoded,android.util.Base64.DEFAULT);
                if (body.length>MAX_BODY) throw new Exception("request too large");
            }
            if (!slots.tryAcquire()) throw new Exception("transport busy");acquired=true;
            final long deadline=System.nanoTime()+(long)(seconds*1000000000L);
            timeout=deadlines.schedule(new Runnable() {
                public void run() { HttpURLConnection c=current.get();if(c!=null)c.disconnect(); }
            },Math.max(1,(long)Math.ceil(seconds*1000)),TimeUnit.MILLISECONDS);
            int redirects=0;
            while (true) {
                HttpURLConnection conn=(HttpURLConnection)target.openConnection();current.set(conn);
                conn.setInstanceFollowRedirects(false);conn.setConnectTimeout(Math.min(10000,remaining(deadline)));
                conn.setUseCaches(false);
                conn.setReadTimeout(remaining(deadline));conn.setRequestMethod(method);
                conn.setRequestProperty("User-Agent",agent);conn.setRequestProperty("Accept",accept);
                conn.setRequestProperty("Accept-Encoding","identity");
                if (body!=null) {
                    conn.setRequestProperty("Content-Type",mime);conn.setDoOutput(true);conn.setFixedLengthStreamingMode(body.length);
                    try (OutputStream out=conn.getOutputStream()) { out.write(body); }
                }
                remaining(deadline);int status=conn.getResponseCode();result.put("status",status);
                if (status==301 || status==302 || status==303 || status==307 || status==308) {
                    String location=conn.getHeaderField("Location");
                    if (!method.equals("GET") || location==null || ++redirects>5) throw new Exception("redirect refused");
                    target=url(new URL(target,location).toString(),secure);conn.disconnect();current.set(null);continue;
                }
                if (status<200 || status>=300) throw new Exception("HTTP status");
                if (!discard) {
                    long declared=-1;String length=conn.getHeaderField("Content-Length");
                    if (length!=null) {try {declared=Long.parseLong(length);} catch(NumberFormatException bad) {throw new Exception("invalid length");}}
                    if (declared>maximum) throw new Exception("response too large");
                    ByteArrayOutputStream bytes=new ByteArrayOutputStream(Math.min(maximum,65536));
                    try (InputStream in=conn.getInputStream()) {
                        byte[] chunk=new byte[8192];int n;
                        while (true) {
                            conn.setReadTimeout(remaining(deadline));n=in.read(chunk);if(n<0)break;
                            if (n>maximum-bytes.size()) throw new Exception("response too large");bytes.write(chunk,0,n);
                        }
                    }
                    if (declared>=0 && declared!=bytes.size()) throw new Exception("partial response");
                    result.put("bodyBase64",android.util.Base64.encodeToString(bytes.toByteArray(),android.util.Base64.NO_WRAP));
                }
                remaining(deadline);return result.toString();
            }
        } catch (Exception error) {
            try {result.remove("bodyBase64");result.put("error","bounded HTTP request failed");} catch(Exception ignored){}
            return result.toString();
        } finally {
            if (timeout!=null)timeout.cancel(false);
            try {HttpURLConnection conn=current.get();if(conn!=null)conn.disconnect();}
            finally {if(acquired)slots.release();}
        }
    }
}
