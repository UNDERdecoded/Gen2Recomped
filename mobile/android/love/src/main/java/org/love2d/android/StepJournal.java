// Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package org.love2d.android;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;
import java.util.UUID;
import org.json.JSONObject;

/** Cumulative native snapshot: publishing the count also commits its anchor. */
final class StepJournal {
    static final String NAME = "steps_journal.json";
    private static final long MAX_TOTAL = 9007199254740991L;
    private static final int MAX_BYTES = 8192;

    private static JSONObject read(File path) throws Exception {
        long length = path.length();
        if (length <= 0 || length > MAX_BYTES) throw new IOException("invalid step file size");
        byte[] bytes = new byte[(int) length];
        try (FileInputStream in = new FileInputStream(path)) {
            int offset = 0;
            while (offset < bytes.length) {
                int n = in.read(bytes, offset, bytes.length - offset);
                if (n <= 0) throw new IOException("short step file");
                offset += n;
            }
            if (in.read() != -1) throw new IOException("step file grew while reading");
        }
        return new JSONObject(new String(bytes, StandardCharsets.UTF_8));
    }

    private static long integer(JSONObject value, String name) throws Exception {
        Object raw = value.get(name);
        if (!(raw instanceof Number)) throw new IOException("invalid " + name);
        double d = ((Number) raw).doubleValue();
        if (Double.isNaN(d) || Double.isInfinite(d) || d < 0 || d > MAX_TOTAL || Math.floor(d) != d)
            throw new IOException("invalid " + name);
        return ((Number) raw).longValue();
    }

    static String iso(long millis) {
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
        f.setTimeZone(TimeZone.getTimeZone("UTC"));
        return f.format(new Date(millis));
    }
    private static boolean text(String value) {
        if (value.getBytes(StandardCharsets.UTF_8).length > 64) return false;
        for (int i = 0; i < value.length(); i++)
            if (value.charAt(i) < 32 || value.charAt(i) == 127) return false;
        return true;
    }
    private static String string(JSONObject value, String key) throws Exception {
        Object raw = value.get(key);
        if (!(raw instanceof String)) throw new IOException("invalid " + key);
        return (String) raw;
    }

    private static JSONObject load(File dir, long fallbackCounter, long fallbackTime) throws Exception {
        File path = new File(dir, NAME);
        if (path.exists()) {
            JSONObject state = read(path);
            if (integer(state, "version") != 1 || !string(state, "source").equals("android-counter")
                    || !string(state, "epoch").matches("[a-zA-Z0-9_-]{1,64}")
                    || !text(string(state, "from")) || !text(string(state, "to")))
                throw new IOException("invalid step journal");
            integer(state, "total"); integer(state, "anchor"); integer(state, "anchorTime");
            if (!(state.get("anchorKnown") instanceof Boolean)) throw new IOException("invalid anchor state");
            return state;
        }
        long total = 0;
        String from = iso(fallbackTime);
        File legacy = new File(dir, "steps_pending.json");
        if (legacy.exists()) {
            JSONObject previous = read(legacy);
            total = integer(previous, "steps");
            if (previous.has("from") && text(previous.getString("from")))
                from = previous.getString("from");
        }
        JSONObject state = new JSONObject();
        state.put("version", 1); state.put("source", "android-counter");
        state.put("epoch", UUID.randomUUID().toString().replace("-", ""));
        state.put("total", total); state.put("anchor", Math.max(0, fallbackCounter));
        state.put("anchorKnown", fallbackCounter >= 0);
        state.put("anchorTime", fallbackTime); state.put("from", from); state.put("to", from);
        return state;
    }

    // One writer across overlapping sensor callbacks and activity instances.
    static synchronized void deliver(File dir, long counterNow, long now,
                                     long fallbackCounter, long fallbackTime) throws Exception {
        if (counterNow < 0 || counterNow > MAX_TOTAL || now < 0 || now > MAX_TOTAL)
            throw new IOException("invalid sensor reading");
        JSONObject state = load(dir, fallbackCounter, fallbackTime);
        long anchor = state.getLong("anchor");
        // A reboot resets the hardware counter; it starts a new measurement
        // window while preserving the cumulative journal and consumer receipts.
        long delta = state.getBoolean("anchorKnown") ? Math.max(0, counterNow - anchor) : 0;
        long total = integer(state, "total");
        if (delta > MAX_TOTAL - total) throw new IOException("step journal overflow");
        state.put("total", total + delta); state.put("anchor", counterNow);
        state.put("anchorKnown", true);
        state.put("anchorTime", now); state.put("to", iso(now));
        publish(dir, state);
    }

    // Migration is completed before a permission sheet or sensor query can
    // defer the first reading; the Lua side leaves the legacy file alone.
    static synchronized void initialize(File dir, long fallbackCounter, long fallbackTime) throws Exception {
        if (fallbackCounter < -1 || fallbackCounter > MAX_TOTAL || fallbackTime < 0 || fallbackTime > MAX_TOTAL)
            throw new IOException("invalid legacy anchor");
        JSONObject state = load(dir, fallbackCounter, fallbackTime);
        if (!new File(dir, NAME).exists()) publish(dir, state);
    }

    private static void publish(File dir, JSONObject state) throws Exception {
        byte[] bytes = state.toString().getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_BYTES) throw new IOException("step journal oversized");
        if (!dir.isDirectory() && !dir.mkdirs()) throw new IOException("cannot create step directory");
        File stage = new File(dir, NAME + ".tmp");
        try {
            try (FileOutputStream out = new FileOutputStream(stage)) {
                out.write(bytes); out.getFD().sync();
            }
            // Android's POSIX rename replaces the snapshot atomically. Lua
            // readers never modify the snapshot or its staging file.
            android.system.Os.rename(stage.getAbsolutePath(), new File(dir, NAME).getAbsolutePath());
        } finally {
            if (stage.exists()) stage.delete();
        }
    }
}
