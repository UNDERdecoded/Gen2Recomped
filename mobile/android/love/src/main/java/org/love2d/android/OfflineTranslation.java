package org.love2d.android;

import com.google.android.gms.tasks.Tasks;
import com.google.mlkit.common.model.DownloadConditions;
import com.google.mlkit.nl.translate.TranslateLanguage;
import com.google.mlkit.nl.translate.Translation;
import com.google.mlkit.nl.translate.Translator;
import com.google.mlkit.nl.translate.TranslatorOptions;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/** Called only by the LOVE translation worker, never the Android UI thread. */
public final class OfflineTranslation {
    private static Translator client;
    private static String pair;
    public static synchronized byte[] translate(String source, String target, byte[] input) throws Exception {
        if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper())
            throw new IllegalStateException("Translation must run on a worker thread");
        if (source.equals(target)) return input;
        String from = TranslateLanguage.fromLanguageTag(source.equals("nb") ? "no" : source);
        String to = TranslateLanguage.fromLanguageTag(target.equals("nb") ? "no" : target);
        if (from == null || to == null) throw new IllegalArgumentException("Unsupported translation language");
        String requested = from + ":" + to;
        if (!requested.equals(pair)) {
            if (client != null) client.close();
            client = Translation.getClient(new TranslatorOptions.Builder()
                    .setSourceLanguage(from).setTargetLanguage(to).build());
            pair = null;
            Tasks.await(client.downloadModelIfNeeded(new DownloadConditions.Builder().requireWifi().build()),
                    5, TimeUnit.MINUTES);
            pair = requested;
        }
        String translated = Tasks.await(client.translate(new String(input, StandardCharsets.UTF_8)),
                60, TimeUnit.SECONDS);
        return translated.getBytes(StandardCharsets.UTF_8);
    }
    public static synchronized void close() {
        if (client != null) client.close();
        client = null;
        pair = null;
    }
}
