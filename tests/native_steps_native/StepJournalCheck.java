// Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package org.love2d.android;
import java.nio.file.Files;
import java.nio.file.Path;
import java.io.File;
import java.util.Arrays;
import org.json.JSONObject;
public final class StepJournalCheck {
    static int checks = 0;
    static void check(boolean ok, String message) {
        checks++; if (!ok) throw new AssertionError(message);
    }
    interface Action { void run() throws Exception; }
    static void refused(Action action) throws Exception {
        checks++; try { action.run(); } catch (Exception expected) { return; }
        throw new AssertionError("invalid transaction was accepted");
    }
    static JSONObject state(Path root) throws Exception {
        return new JSONObject(Files.readString(root.resolve(StepJournal.NAME)));
    }
    public static void main(String[] args) throws Exception {
        Path root = Path.of(args[0]); Files.createDirectories(root); File dir = root.toFile();
        Files.writeString(root.resolve("steps_pending.json"), "{\"steps\":17}");
        StepJournal.initialize(dir, -1, 1000);
        check(state(root).getLong("total") == 17, "migration is visible before sensor consent");
        check(!state(root).getBoolean("anchorKnown"), "first migration does not invent a sensor anchor");
        StepJournal.deliver(dir, 100, 1000, -1, 1000);
        check(state(root).getLong("total") == 17, "first counter anchors without fictitious credit");
        StepJournal.deliver(dir, 75100, 2000, -1, 1000);
        check(state(root).getLong("total") == 75017, "complete backlog retained");
        String epoch = state(root).getString("epoch");
        StepJournal.deliver(dir, 75100, 2100, -1, 1000);
        check(state(root).getLong("total") == 75017, "duplicate reading does not replay");
        check(state(root).getLong("anchorTime") == 2100, "empty windows update the native anchor");
        byte[] before = Files.readAllBytes(root.resolve(StepJournal.NAME));
        android.system.Os.failRename = true;
        refused(() -> StepJournal.deliver(dir, 75200, 2200, -1, 1000));
        check(Arrays.equals(before, Files.readAllBytes(root.resolve(StepJournal.NAME))), "failed publish preserves count and anchor");
        android.system.Os.failRename = false;
        StepJournal.deliver(dir, 75200, 2200, -1, 1000);
        check(state(root).getLong("total") == 75117, "retry retains the missed walk");
        StepJournal.deliver(dir, 5, 2300, -1, 1000);
        check(state(root).getLong("total") == 75117, "reboot reanchors without negative or invented credit");
        StepJournal.deliver(dir, 10, 2400, -1, 1000);
        check(state(root).getLong("total") == 75122, "post-reboot delta credited");
        check(state(root).getString("epoch").equals(epoch), "reboot retains consumer epoch");
        Thread[] threads = new Thread[8];
        java.util.concurrent.atomic.AtomicReference<Throwable> failure = new java.util.concurrent.atomic.AtomicReference<>();
        for (int i = 0; i < threads.length; i++) {
            threads[i] = new Thread(() -> {
                try { StepJournal.deliver(dir, 20, 2500, -1, 1000); }
                catch (Exception error) { failure.set(error); }
            }); threads[i].start();
        }
        for (Thread thread : threads) thread.join();
        check(failure.get() == null, "all concurrent callbacks completed");
        check(state(root).getLong("total") == 75132, "concurrent duplicate callbacks retain one delta");
        before = Files.readAllBytes(root.resolve(StepJournal.NAME));
        refused(() -> StepJournal.deliver(dir, -1, 2600, -1, 1000));
        check(Arrays.equals(before, Files.readAllBytes(root.resolve(StepJournal.NAME))), "invalid reading preserves snapshot");
        Files.writeString(root.resolve(StepJournal.NAME), "{unfinished");
        refused(() -> StepJournal.deliver(dir, 30, 2700, -1, 1000));
        Files.write(root.resolve(StepJournal.NAME), before);
        for (String key : new String[]{"version", "anchor", "total", "epoch"}) {
            JSONObject bad = new JSONObject(new String(before, java.nio.charset.StandardCharsets.UTF_8));
            bad.put(key, key.equals("epoch") ? 1 : true);
            Files.writeString(root.resolve(StepJournal.NAME), bad.toString());
            refused(() -> StepJournal.deliver(dir, 30, 2700, -1, 1000));
        }
        Files.write(root.resolve(StepJournal.NAME), before);
        check(Files.readString(root.resolve("steps_pending.json")).equals("{\"steps\":17}"), "migration preserves legacy source");
        System.out.println("Native steps Java: " + checks + " PASS");
    }
}
