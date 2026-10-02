/*
 * Copyright (c) 2026 Cedric. All rights reserved.
 * Source-available under the Gen2Recomped License (see LICENSE.md).
 *
 * THE BOTTOM SCREEN, ON HARDWARE THAT HAS ONE.
 *
 * The AYN Thor has a second panel. Android exposes it as a presentation
 * display; LOVE does not, and teaching LOVE would mean patching and rebuilding
 * the engine's NDK tree for every release. This is the other way round: an
 * ordinary Java class in the app module, no native code, talking to Lua
 * through three files in the save directory.
 *
 * It deliberately lives at mobile/second-display/ rather than inside
 * mobile/android/, because mobile/android/ is a vendored love-android checkout
 * that gets deleted and re-cloned. scripts/build_android.sh copies this file in
 * and patches the manifest; see install_second_display_host() there.
 *
 * WHY A ContentProvider AND NOT AN Application SUBCLASS.
 * A provider is instantiated before Application.onCreate and is handed a
 * Context, which is all this needs -- and registering one ADDS an element to
 * love-android's manifest, where <application android:name> would REPLACE
 * whatever that vendored manifest already declares. The provider serves
 * nothing; query/insert/etc. are stubs.
 *
 * THE PROTOCOL is defined in src/render/SecondScreen.lua and repeated here
 * because the two ends never meet. tools/gen4_second_display_protocol_check.lua
 * reads both files and fails if they drift.
 *
 *   second_display/host.txt   written HERE, once a second:
 *                             "<version> <displays> <width> <height>"
 *                             Lua offers `display` mode only while this says
 *                             a matching version and displays >= 2.
 *   second_display/frame.bin  written by LUA: "G2SD", then version, width,
 *                             height, sequence as little-endian u16 -- twelve
 *                             bytes -- then width*height*4 bytes of RGBA.
 *   second_display/touch.txt  appended HERE, read and truncated by Lua:
 *                             "<down|move|up> <id> <x> <y>" a line.
 */

package org.love2d.android;

import android.app.Activity;
import android.app.Application;
import android.app.Presentation;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.hardware.display.DisplayManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Display;
import android.view.MotionEvent;
import android.view.View;

import java.io.File;
import java.io.FileOutputStream;
import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.Charset;

public class SecondDisplayHost extends ContentProvider {

  private static final String TAG = "G2SecondDisplay";

  /* --- the protocol. Must match src/render/SecondScreen.lua. --- */
  public static final int PROTOCOL = 1;
  public static final String MAGIC = "G2SD";
  public static final int HEADER_BYTES = 12;
  public static final String DIR = "second_display";
  public static final String HOST_FILE = "host.txt";
  public static final String FRAME_FILE = "frame.bin";
  public static final String TOUCH_FILE = "touch.txt";
  /* conf.lua pins the Android identity to "pokemon-love2d" and sets
   * t.externalstorage, so LOVE's save directory is
   * getExternalFilesDir(null)/save/pokemon-love2d. The internal path is
   * checked too rather than assumed away: a build with externalstorage off
   * would use it, and writing the handshake into both costs one file. */
  public static final String IDENTITY = "pokemon-love2d";

  private static final int HOST_INTERVAL_MS = 1000;
  private static final int FRAME_POLL_MS = 16;

  private Context appContext;
  private final Handler ui = new Handler(Looper.getMainLooper());
  private volatile boolean running = false;
  private Thread pump;
  private volatile Activity activeActivity;
  private volatile PanelPresentation presentation;
  private File[] roots = new File[0];
  private volatile File frameFile, touchFile;

  private volatile int lastSeq = -1;
  private volatile int frameW = 0, frameH = 0;

  /* ------------------------------------------------------------------ *
   * Provider plumbing: exists to be constructed early, serves nothing.
   * ------------------------------------------------------------------ */

  @Override
  public boolean onCreate() {
    appContext = getContext();
    if (appContext == null) return false;
    appContext = appContext.getApplicationContext();
    roots = saveRoots(appContext);
    if (roots.length == 0) {
      Log.w(TAG, "no save directory found; second display inactive");
      return true;
    }
    Log.i(TAG, "SecondDisplayHost created");
    for (File root : roots) Log.i(TAG, "save root: " + root.getAbsolutePath());

    if (appContext instanceof Application) {
      ((Application) appContext).registerActivityLifecycleCallbacks(
          new Lifecycle());
    }
    return true;
  }

  @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { return null; }
  @Override public String getType(Uri u) { return null; }
  @Override public Uri insert(Uri u, ContentValues v) { return null; }
  @Override public int delete(Uri u, String s, String[] a) { return 0; }
  @Override public int update(Uri u, ContentValues v, String s, String[] a) { return 0; }

  /* ------------------------------------------------------------------ *
   * Where LOVE keeps its save directory.
   * ------------------------------------------------------------------ */

  private static File[] saveRoots(Context ctx) {
    java.util.ArrayList<File> out = new java.util.ArrayList<File>();
    File ext = ctx.getExternalFilesDir(null);
    if (ext != null) out.add(new File(new File(ext, "save"), IDENTITY));
    File in = ctx.getFilesDir();
    if (in != null) out.add(new File(new File(in, "save"), IDENTITY));
    java.util.ArrayList<File> dirs = new java.util.ArrayList<File>();
    for (File base : out) {
      File d = new File(base, DIR);
      // Lua's love.filesystem.write creates the directory itself, but the
      // handshake has to be readable BEFORE Lua has ever written anything --
      // that is what makes the option appear in the menu at all.
      if (d.isDirectory() || d.mkdirs()) dirs.add(d);
    }
    return dirs.toArray(new File[0]);
  }

  /* ------------------------------------------------------------------ *
   * Follow the game's own activity: a Presentation belongs to one.
   * ------------------------------------------------------------------ */

  private final class Lifecycle implements Application.ActivityLifecycleCallbacks {
    @Override public void onActivityResumed(Activity a) { attach(a); }
    @Override public void onActivityPaused(Activity a) { detach(); }
    @Override public void onActivityCreated(Activity a, Bundle b) { }
    @Override public void onActivityStarted(Activity a) { }
    @Override public void onActivityStopped(Activity a) { }
    @Override public void onActivitySaveInstanceState(Activity a, Bundle b) { }
    @Override public void onActivityDestroyed(Activity a) { }
  }

  private Display secondaryDisplay() {
    DisplayManager dm =
        (DisplayManager) appContext.getSystemService(Context.DISPLAY_SERVICE);
    if (dm == null) {
      Log.w(TAG, "DisplayManager unavailable");
      return null;
    }
    Display[] all = dm.getDisplays();
    if (all != null) {
      for (Display d : all) {
        Log.d(TAG, "display id=" + d.getDisplayId()
            + " name=" + d.getName()
            + " flags=" + d.getFlags()
            + " state=" + d.getState());
      }
    }
    Display[] ds = dm.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION);
    if (ds != null && ds.length > 0) return ds[0];
    if (all != null) {
      for (Display d : all) {
        if (d.getDisplayId() != Display.DEFAULT_DISPLAY) return d;
      }
    }
    return null;
  }

  private void attach(Activity activity) {
    activeActivity = activity;
    if (!running) startPump();
    ensurePresentation();
  }

  private void ensurePresentation() {
    if (Looper.myLooper() != Looper.getMainLooper()) {
      ui.post(new Runnable() {
        @Override public void run() { ensurePresentation(); }
      });
      return;
    }
    if (!running || presentation != null) return;
    Activity activity = activeActivity;
    if (activity == null || activity.isFinishing()) return;

    Display d = secondaryDisplay();
    if (d == null) {
      writeHost(1, 0, 0);
      return;
    }

    android.graphics.Point size = new android.graphics.Point();
    d.getSize(size);
    Log.i(TAG, "using secondary display id=" + d.getDisplayId()
        + " name=" + d.getName() + " size=" + size.x + "x" + size.y);
    PanelPresentation p = new PanelPresentation(activity, d);
    try {
      p.show();
      presentation = p;
      lastSeq = -1;
      writeHost(2, size.x, size.y);
      Log.i(TAG, "Presentation.show succeeded");
      Log.i(TAG, "second display attached: " + size.x + "x" + size.y);
    } catch (Throwable t) {
      Log.e(TAG, "presentation refused", t);
      try { p.dismiss(); } catch (Throwable ignored) { }
      presentation = null;
      writeHost(1, 0, 0);
    }
  }

  private void detach() {
    running = false;
    activeActivity = null;
    if (pump != null) { pump.interrupt(); pump = null; }
    final PanelPresentation p = presentation;
    presentation = null;
    if (p != null) ui.post(new Runnable() {
      @Override public void run() { try { p.dismiss(); } catch (Throwable ignored) { } }
    });
  }

  /* ------------------------------------------------------------------ *
   * The handshake, and the frames.
   * ------------------------------------------------------------------ */

  private void writeHost(int displays, int w, int h) {
    byte[] line = (PROTOCOL + " " + displays + " " + w + " " + h + "\n")
        .getBytes(Charset.forName("UTF-8"));
    for (File dir : roots) {
      FileOutputStream os = null;
      try {
        os = new FileOutputStream(new File(dir, HOST_FILE), false);
        os.write(line);
      } catch (Throwable ignored) {
      } finally {
        if (os != null) try { os.close(); } catch (Throwable ignored) { }
      }
    }
  }

  private void startPump() {
    running = true;
    pump = new Thread(new Runnable() {
      @Override public void run() {
        long lastHost = 0;
        long lastDiscovery = 0;
        while (running) {
          long now = android.os.SystemClock.uptimeMillis();
          PanelPresentation panel = presentation;

          if (panel == null && now - lastDiscovery >= HOST_INTERVAL_MS) {
            lastDiscovery = now;
            ui.post(new Runnable() {
              @Override public void run() { ensurePresentation(); }
            });
          }

          if (now - lastHost >= HOST_INTERVAL_MS) {
            lastHost = now;
            panel = presentation;
            if (panel == null) writeHost(1, 0, 0);
            else writeHost(2, panel.panelWidth(), panel.panelHeight());
          }

          panel = presentation;
          if (panel != null) readFrameOnce(panel);
          try { Thread.sleep(FRAME_POLL_MS); }
          catch (InterruptedException e) { return; }
        }
      }
    }, "g2-second-display");
    pump.setDaemon(true);
    pump.start();
  }

  /** The twelve bytes  /** The twelve bytes, or null if they are not a frame this end can draw.
   *  Extracted so tools/gen4_second_display_protocol_check.lua can feed it a
   *  header the LUA end actually wrote, rather than one a test made up to
   *  match. The two ends never meet anywhere else. */
  public static int[] decodeHeader(byte[] head) {
    if (head == null || head.length < HEADER_BYTES) return null;
    if (head[0] != 'G' || head[1] != '2' || head[2] != 'S' || head[3] != 'D') {
      return null;
    }
    ByteBuffer hb = ByteBuffer.wrap(head).order(ByteOrder.LITTLE_ENDIAN);
    int version = hb.getShort(4) & 0xFFFF;
    int w = hb.getShort(6) & 0xFFFF;
    int h = hb.getShort(8) & 0xFFFF;
    int seq = hb.getShort(10) & 0xFFFF;
    if (version != PROTOCOL || w <= 0 || h <= 0) return null;
    return new int[] { version, w, h, seq };
  }

  /** A point on the panel, in the bottom screen's own pixels -- or null when
   *  it landed in the letterbox, which is not a tap on anything. */
  public static int[] mapPoint(float px, float py, int dl, int dt, int dw, int dh,
                        int sw, int sh) {
    if (dw <= 0 || dh <= 0 || sw <= 0 || sh <= 0) return null;
    int x = (int) Math.floor((px - dl) / (float) dw * sw);
    int y = (int) Math.floor((py - dt) / (float) dh * sh);
    if (x < 0 || y < 0 || x >= sw || y >= sh) return null;
    return new int[] { x, y };
  }

  private File findFrameFile() {
    File newest = null;
    for (File root : roots) {
      File f = new File(root, FRAME_FILE);
      if (!f.isFile()) continue;
      if (newest == null || f.lastModified() > newest.lastModified()) newest = f;
    }
    if (newest != null && (frameFile == null || !newest.equals(frameFile))) {
      frameFile = newest;
      touchFile = new File(newest.getParentFile(), TOUCH_FILE);
      Log.i(TAG, "active frame root: " + newest.getParentFile().getAbsolutePath());
    }
    return newest;
  }

  private long lastRejectLog = 0;

  private int lastVisibleReject = -1;
  private boolean haveAcceptedFrame = false;

  private void rejectLog(final PanelPresentation panel, final int code, String reason) {
    long now = android.os.SystemClock.uptimeMillis();
    if (now - lastRejectLog >= 1000) {
      lastRejectLog = now;
      Log.w(TAG, "FRAME REJECT: " + reason);
    }
    if (!haveAcceptedFrame && lastVisibleReject != code && panel != null && panel.view != null) {
      lastVisibleReject = code;
      final PanelView v = panel.view;
      ui.post(new Runnable() {
        @Override public void run() { v.showTransportStatus(code); }
      });
    }
  }

  private void readFrameOnce(PanelPresentation panel) {
    File f = findFrameFile();
    if (f == null || !f.isFile()) {
      rejectLog(panel, 1, "no frame.bin found in save roots");
      return;
    }
    long len = f.length();
    if (len < HEADER_BYTES) {
      rejectLog(panel, 2, "short file len=" + len);
      return;
    }
    RandomAccessFile raf = null;
    try {
      raf = new RandomAccessFile(f, "r");
      byte[] head = new byte[HEADER_BYTES];
      raf.readFully(head);
      int[] hdr = decodeHeader(head);
      if (hdr == null) {
        rejectLog(panel, 3, "invalid G2SD header len=" + len);
        return;
      }
      int w = hdr[1], h = hdr[2], seq = hdr[3];
      if (seq == lastSeq) return;
      long want = (long) HEADER_BYTES + (long) w * h * 4L;
      boolean legacyTrailer = len == want + 6L;
      if (len != want && !legacyTrailer) {
        // love.filesystem.write truncates/replaces frame.bin while this pump is
        // polling it. A temporary length mismatch is therefore expected and
        // must never replace the last good frame with an error screen. Leave
        // lastSeq untouched and retry on the next pump.
        long now = android.os.SystemClock.uptimeMillis();
        if (now - lastRejectLog >= 1000) {
          lastRejectLog = now;
          Log.w(TAG, "FRAME RETRY: transient size mismatch seq=" + seq
              + " got=" + len + " want=" + want + " dimensions=" + w + "x" + h);
        }
        return;
      }

      byte[] rgba = new byte[w * h * 4];
      raf.readFully(rgba);

      // One diagnostic build appended "G2OK" + sequence. Accept those files
      // too so an old frame left in the save directory cannot permanently
      // block a newer APK from reaching the renderer.
      if (legacyTrailer) {
        byte[] tail = new byte[6];
        raf.readFully(tail);
        int tailSeq = (tail[4] & 0xff) | ((tail[5] & 0xff) << 8);
        if (tail[0] != 'G' || tail[1] != '2' || tail[2] != 'O' || tail[3] != 'K'
            || tailSeq != seq) {
          rejectLog(panel, 2, "invalid legacy trailer seq=" + seq);
          return;
        }
      }

      raf.seek(0);
      byte[] verifyHead = new byte[HEADER_BYTES];
      raf.readFully(verifyHead);
      int[] verify = decodeHeader(verifyHead);
      if (verify == null || verify[3] != seq || verify[1] != w || verify[2] != h) {
        rejectLog(panel, 4, "header changed during read seq=" + seq);
        return;
      }

      lastSeq = seq;
      frameW = w; frameH = h;
      lastVisibleReject = 5;
      haveAcceptedFrame = true;
      panel.post(w, h, rgba);
      Log.i(TAG, "FRAME ACCEPT seq=" + seq + " size=" + w + "x" + h
          + " bytes=" + len + " path=" + f.getAbsolutePath());
    } catch (Throwable t) {
      Log.e(TAG, "readFrameOnce failed", t);
    } finally {
      if (raf != null) try { raf.close(); } catch (Throwable ignored) { }
    }
  }

  private void appendTouch(String kind, int id, int x, int y) {
    File f = touchFile;
    if (f == null) return;
    FileOutputStream os = null;
    try {
      os = new FileOutputStream(f, true);
      os.write((kind + " " + id + " " + x + " " + y + "\n")
          .getBytes(Charset.forName("UTF-8")));
    } catch (Throwable ignored) {
    } finally {
      if (os != null) try { os.close(); } catch (Throwable ignored) { }
    }
  }

  /* ------------------------------------------------------------------ *
   * The panel itself.
   * ------------------------------------------------------------------ */

  private final class PanelPresentation extends Presentation {
    private PanelView view;

    PanelPresentation(Context outer, Display display) { super(outer, display); }

    @Override protected void onCreate(Bundle state) {
      super.onCreate(state);
      view = new PanelView(getContext());
      setContentView(view);
      view.showDiagnosticPattern();
    }

    int panelWidth() { return view == null ? 0 : Math.max(view.getWidth(), 1); }
    int panelHeight() { return view == null ? 0 : Math.max(view.getHeight(), 1); }

    void post(final int w, final int h, final byte[] rgba) {
      final PanelView v = view;
      if (v == null) return;
      ui.post(new Runnable() {
        @Override public void run() { v.accept(w, h, rgba); }
      });
    }
  }

  private final class PanelView extends View {
    private Bitmap bitmap;
    private final Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG);
    private final Rect dst = new Rect();
    private int srcW = 0, srcH = 0;

    PanelView(Context c) {
      super(c);
      setBackgroundColor(Color.BLACK);
    }

    void showSizeMismatch(final long actual, final long expected,
                          final int frameWidth, final int frameHeight, final int seq) {
      final int w = 512, h = 384;
      Bitmap status = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
      Canvas cc = new Canvas(status);
      cc.drawColor(0xffffff00);
      Paint tp = new Paint(Paint.ANTI_ALIAS_FLAG);
      tp.setColor(0xff000000);
      tp.setTextSize(38f);
      tp.setTypeface(android.graphics.Typeface.MONOSPACE);
      cc.drawText("FRAME SIZE MISMATCH", 22, 55, tp);
      tp.setTextSize(32f);
      cc.drawText("FILE     = " + actual, 22, 115, tp);
      cc.drawText("EXPECTED = " + expected, 22, 160, tp);
      cc.drawText("DIFF     = " + (actual - expected), 22, 205, tp);
      cc.drawText("W x H    = " + frameWidth + " x " + frameHeight, 22, 250, tp);
      cc.drawText("SEQ      = " + seq, 22, 295, tp);
      tp.setTextSize(22f);
      cc.drawText("Send a photo of these numbers", 22, 350, tp);
      if (bitmap != null) bitmap.recycle();
      bitmap = status;
      srcW = w; srcH = h;
      invalidate();
    }

    void showTransportStatus(final int code) {
      // Visible debugger for devices where logcat is unavailable:
      // 1=red no frame, 2=yellow short/size, 3=magenta bad header,
      // 4=cyan frame changed during read, 5=green valid frame accepted.
      final int w = 256, h = 192;
      int color;
      switch (code) {
        case 1: color = 0xffff0000; break;
        case 2: color = 0xffffff00; break;
        case 3: color = 0xffff00ff; break;
        case 4: color = 0xff00ffff; break;
        case 5: color = 0xff00ff00; break;
        default: color = 0xff202020; break;
      }
      int[] pixels = new int[w * h];
      java.util.Arrays.fill(pixels, color);
      // Black border plus code bars: count the vertical white bars if color
      // reproduction itself is questionable.
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          if (x < 4 || x >= w - 4 || y < 4 || y >= h - 4)
            pixels[y * w + x] = 0xff000000;
        }
      }
      for (int n = 0; n < code; n++) {
        int x0 = 18 + n * 28;
        for (int y = 70; y < 122; y++)
          for (int x = x0; x < x0 + 12; x++)
            pixels[y * w + x] = 0xffffffff;
      }
      if (bitmap != null) bitmap.recycle();
      bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
      bitmap.setPixels(pixels, 0, w, 0, 0, w, h);
      srcW = w; srcH = h;
      invalidate();
    }

    void showDiagnosticPattern() {
      final int w = 256, h = 192;
      int[] pixels = new int[w * h];
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          int color;
          if (y < h / 2) color = x < w / 2 ? 0xffff0000 : 0xff00ff00;
          else color = x < w / 2 ? 0xff0000ff : 0xffffffff;
          if (x == 0 || x == w - 1 || y == 0 || y == h - 1
              || x == w / 2 || y == h / 2) color = 0xff000000;
          pixels[y * w + x] = color;
        }
      }
      if (bitmap != null) bitmap.recycle();
      bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
      bitmap.setPixels(pixels, 0, w, 0, 0, w, h);
      srcW = w; srcH = h;
      invalidate();
      Log.i(TAG, "DIAG: Java color-quadrant pattern posted");
    }

    void accept(int w, int h, byte[] rgba) {
      if (bitmap == null || srcW != w || srcH != h) {
        if (bitmap != null) bitmap.recycle();
        bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        srcW = w; srcH = h;
      }

      // LOVE's ImageData string is packed RGBA. Convert explicitly instead of
      // relying on Bitmap's native raw-buffer byte order.
      int count = w * h;
      int[] pixels = new int[count];
      for (int p = 0, off = 0; p < count; p++, off += 4) {
        int r = rgba[off] & 0xff;
        int g = rgba[off + 1] & 0xff;
        int bl = rgba[off + 2] & 0xff;
        int alpha = rgba[off + 3] & 0xff;
        pixels[p] = (alpha << 24) | (r << 16) | (g << 8) | bl;
      }
      bitmap.setPixels(pixels, 0, w, 0, 0, w, h);
      invalidate();
    }

    @Override protected void onDraw(Canvas canvas) {
      canvas.drawColor(Color.BLACK);
      Bitmap b = bitmap;
      if (b == null || b.isRecycled()) return;
      // Letterboxed, integer-agnostic: the panel is rarely 4:3, and stretching
      // a 256x192 bottom screen to fill it would skew every Poketch dial.
      int vw = getWidth(), vh = getHeight();
      if (vw <= 0 || vh <= 0) return;
      float s = Math.min((float) vw / srcW, (float) vh / srcH);
      int dw = Math.max(1, Math.round(srcW * s));
      int dh = Math.max(1, Math.round(srcH * s));
      dst.set((vw - dw) / 2, (vh - dh) / 2, (vw - dw) / 2 + dw, (vh - dh) / 2 + dh);
      canvas.drawBitmap(b, null, dst, paint);
    }

    @Override public boolean onTouchEvent(MotionEvent e) {
      if (srcW <= 0 || srcH <= 0 || dst.width() <= 0) return false;
      int action = e.getActionMasked();
      String kind;
      switch (action) {
        case MotionEvent.ACTION_DOWN:
        case MotionEvent.ACTION_POINTER_DOWN: kind = "down"; break;
        case MotionEvent.ACTION_MOVE:         kind = "move"; break;
        case MotionEvent.ACTION_UP:
        case MotionEvent.ACTION_POINTER_UP:
        case MotionEvent.ACTION_CANCEL:       kind = "up";   break;
        default: return false;
      }
      if ("move".equals(kind) || action == MotionEvent.ACTION_CANCEL) {
        for (int i = 0; i < e.getPointerCount(); i++) emit(kind, e, i);
      } else {
        emit(kind, e, e.getActionIndex());
      }
      return true;
    }

    private void emit(String kind, MotionEvent e, int index) {
      // MAPPED INTO THE BOTTOM SCREEN'S OWN COORDINATES, not the panel's.
      // Lua rejects anything outside 0..w/0..h, so a tap in the letterbox
      // must land outside that range rather than being clamped onto the edge
      // -- a clamped tap is a button press the player did not make.
      int[] p = mapPoint(e.getX(index), e.getY(index), dst.left, dst.top,
                         dst.width(), dst.height(), srcW, srcH);
      if (p == null) return;
      appendTouch(kind, e.getPointerId(index), p[0], p[1]);
    }
  }
}
