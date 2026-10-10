/**
 * Copyright (c) 2006-2023 LOVE Development Team
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 **/

package org.love2d.android;

import org.libsdl.app.SDLActivity;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import android.Manifest;
import android.app.AlarmManager;
import android.app.AlertDialog;
import android.app.PendingIntent;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.content.pm.ApplicationInfo;
import android.content.res.AssetManager;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.media.AudioManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.os.StatFs;
import android.os.Vibrator;
import android.os.storage.StorageManager;
import android.os.storage.StorageVolume;
import android.provider.DocumentsContract;
import android.provider.Settings;
import android.util.Log;
import android.util.DisplayMetrics;
import android.view.*;
import android.content.pm.PackageManager;

import androidx.annotation.Keep;
import androidx.core.app.ActivityCompat;

public class GameActivity extends SDLActivity {
    private static DisplayMetrics metrics = null;
    private static String gamePath = "";
    private static Vibrator vibrator = null;
    protected final int[] externalStorageRequestDummy = new int[1];
    protected final int[] recordAudioRequestDummy = new int[1];
    public static final int EXTERNAL_STORAGE_REQUEST_CODE = 2;
    public static final int RECORD_AUDIO_REQUEST_CODE = 3;
    public static final int FILE_PICKER_REQUEST_CODE = 4;
    public static final int FILE_CREATE_REQUEST_CODE = 5;
    public static final int STEP_PERMISSION_REQUEST_CODE = 6;
    public static final int RESTART_REQUEST_CODE = 7;
    public static final int FOLDER_PICKER_REQUEST_CODE = 8;
    /** @deprecated Prefer FILE_PICKER_REQUEST_CODE; kept for older call sites. */
    public static final int ROM_PICKER_REQUEST_CODE = FILE_PICKER_REQUEST_CODE;
    // Mirrors conf.lua's t.identity ("pokemon-love2d"): where the picked file
    // is dropped so RomImporter's existing folder scan finds it -- see
    // src/import/RomImporter.lua and Filesystem::setIdentity (sets Android's
    // save directory to getExternalFilesDir()/save/<identity>).
    private static final String ROM_SAVE_IDENTITY = "pokemon-love2d";
    private static final String PICKED_ROM_FILENAME = "picked_rom.gb";
    private static final String PICKED_MOD_FILENAME = "picked_mod.zip";
    private static final String PICKED_SAVE_FILENAME = "picked_save.sav";
    private static final String PICKED_IMAGE_FILENAME = "picked_sky.png";
    private static final String PENDING_EXPORT_FILENAME = "pending_export.sav";
    private static final String EXPORT_DONE_FILENAME = "export_done.flag";
    private static final String PICKED_FOLDER_FILENAME = "picked_folder.txt";
    // App-owned subdirectory under each getExternalFilesDir volume: mods and
    // imported games land here so they are not competing with saves for the
    // identity folder's space.
    private static final String GAME_DATA_SUBDIR = "gamedata";
    // Written when a SAF pick cannot be read at all, with the destination
    // basename as its body, so RomImporter:focus can say so in the launcher
    // instead of leaving the player on "No ROM imported" (issue #442).
    private static final String PICK_ERROR_FILENAME = "pick_error.flag";
    // Step bridge (love.system.syncHealthSteps): pending-steps delivery
    // consumed by the Pokéwalker mod, same contract as the iOS
    // GRHealthBridge. Steps come from the hardware TYPE_STEP_COUNTER
    // (cumulative since boot, counted by the OS whether or not any app is
    // running), anchored in SharedPreferences so a walk is never credited
    // twice.
    private static final String PENDING_STEPS_FILENAME = "steps_pending.json";
    private static final String STEP_PREFS = "pokewalker_steps";
    private static final String STEP_PREF_ANCHOR = "anchor";
    private static final String STEP_PREF_ANCHOR_WALLTIME = "anchor_walltime";
    private static final long STEP_MAX_PER_SYNC = 50000;
    // Destination basename for the in-flight SAF pick (set by showFilePicker).
    // Saved/restored across instance state: the picker is a separate activity
    // and Android may destroy this one while it is up (memory pressure, or
    // "Don't keep activities"). A recreated instance still receives
    // onActivityResult, so without this a mod or save pick came back with the
    // field reset and was filed as picked_rom.gb, which Lua then rejected as a
    // bad ROM instead of installing it (#553).
    private String pendingPickFilename = PICKED_ROM_FILENAME;
    /**
     * One-shot: has this pick already been retried through ACTION_GET_CONTENT?
     *
     * ACTION_OPEN_DOCUMENT can SUCCEED as an activity launch and still hand
     * back a URI this app cannot read -- an OEM shell offers a third-party
     * file manager in the chooser, that manager returns its own provider URI
     * with no grant attached, and the launch-time try/catch in showFilePicker
     * never fires because nothing threw. The pick simply comes back dead.
     *
     * GET_CONTENT is the recovery: a manager serving it is expected to hand
     * over something readable (most copy the file to a temp of their own), so
     * an unreadable OPEN_DOCUMENT result is retried through it once before
     * anything is reported as a failure. Once, because a device where both
     * routes fail must end in a message rather than a picker that reopens
     * forever.
     */
    private boolean pickRetried = false;
    private static final String STATE_PENDING_PICK = "pendingPickFilename";
    // Absolute save directory physfs actually mounted, as reported by the
    // native bridge call that opened the picker (love/src/common/android.cpp,
    // bridgeSaveDirectory).  This activity used to recompute
    // getExternalFilesDir(null)/save/<identity> on its own at result time; on
    // merged / adopted-SD storage that can name a different volume than the
    // one LOVE mounted, so the copied pick (and pick_error.flag) landed where
    // Lua never scans -- the launcher then "did nothing" after a pick (#604)
    // and the folders a file manager can browse stayed empty while the game
    // saved fine elsewhere (#839).  Empty string means "not told yet": fall
    // back to the historical computation.
    private String pendingPickSaveDir = "";
    private static final String STATE_PENDING_PICK_DIR = "pendingPickSaveDir";
    private static final String STATE_PENDING_CREATE = "pendingCreateSuggestedName";
    // Suggested download name for the in-flight SAF create (set by showCreateDocument).
    private String pendingCreateSuggestedName = "export.sav";
    private static boolean immersiveActive = false;
    private static boolean needToCopyGameInArchive = false;
    private boolean storagePermissionUnnecessary = false;
    private boolean shortEdgesMode = false;
    public boolean embed = false;
    public int safeAreaTop = 0;
    public int safeAreaLeft = 0;
    public int safeAreaBottom = 0;
    public int safeAreaRight = 0;

    private static native void nativeSetDefaultStreamValues(int sampleRate, int framesPerBurst);

    @Override
    protected String[] getLibraries() {
        return new String[] {
            "c++_shared",
            "mpg123",
            "openal",
            "love",
        };
    }

    @Override
    protected String getMainSharedObject() {
        String[] libs = getLibraries();
        String libname = "lib" + libs[libs.length - 1] + ".so";

        // Since Lollipop, you can simply pass "libname.so" to dlopen
        // and it will resolve correct paths and load correct library.
        // This is mandatory for extractNativeLibs=false support in
        // Marshmallow.
        if (android.os.Build.VERSION.SDK_INT >= 21) {
            return libname;
        } else {
            return getContext().getApplicationInfo().nativeLibraryDir + "/" + libname;
        }
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        Log.d("GameActivity", "started");

        int res = checkCallingOrSelfPermission(Manifest.permission.VIBRATE);
        if (res == PackageManager.PERMISSION_GRANTED) {
            vibrator = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        } else {
            Log.d("GameActivity", "Vibration disabled: could not get vibration permission.");
        }

        // These 2 variables must be reset or it will use the existing value.
        gamePath = "";
        storagePermissionUnnecessary = false;
        embed = getResources().getBoolean(R.bool.embed);
        needToCopyGameInArchive = embed;

        if (!embed) {
            Intent intent = getIntent();
            handleIntent(intent);
            intent.setData(null);
        }

        super.onCreate(savedInstanceState);
        if (savedInstanceState != null) {
            // Restore the in-flight SAF destinations, so a pick that returns to
            // a recreated activity still lands under the basename it asked for.
            String pick = savedInstanceState.getString(STATE_PENDING_PICK);
            if (pick != null) pendingPickFilename = pick;
            String pickDir = savedInstanceState.getString(STATE_PENDING_PICK_DIR);
            if (pickDir != null) pendingPickSaveDir = pickDir;
            String create = savedInstanceState.getString(STATE_PENDING_CREATE);
            if (create != null) pendingCreateSuggestedName = create;
        }
        metrics = getResources().getDisplayMetrics();

        // Set low-latency audio values
        nativeSetDefaultStreamValues(getAudioFreq(), getAudioSMP());

        if (android.os.Build.VERSION.SDK_INT >= 28) {
            getWindow().getAttributes().layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_NEVER;
            shortEdgesMode = false;
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        Log.d("GameActivity", "onNewIntent() with " + intent);
        if (!embed) {
            handleIntent(intent);
            resetNative();
            startNative();
        }
    }

    protected void handleIntent(Intent intent) {
        Uri game = intent.getData();

        if (!embed && game != null) {
            String scheme = game.getScheme();
            String path = game.getPath();
            // If we have a game via the intent data we we try to figure out how we have to load it. We
            // support the following variations:
            // * a main.lua file: set gamePath to the directory containing main.lua
            // * otherwise: set gamePath to the file
            if (scheme.equals("file")) {
                Log.d("GameActivity", "Received file:// intent with path: " + path);
                // If we were given the path of a main.lua then use its
                // directory. Otherwise use full path.
                List<String> path_segments = game.getPathSegments();
                if (path_segments.get(path_segments.size() - 1).equals("main.lua")) {
                    gamePath = path.substring(0, path.length() - "main.lua".length());
                } else {
                    gamePath = path;
                }
            } else if (scheme.equals("content")) {
                Log.d("GameActivity", "Received content:// intent with path: " + path);
                try {
                    String filename = "game.love";
                    String[] pathSegments = path.split("/");
                    if (pathSegments.length > 0) {
                        filename = pathSegments[pathSegments.length - 1];
                    }

                    // Sanitize filename to prevent PhysFS complaining later.
                    filename = filename.replaceAll("[^a-zA-Z0-9_\\\\-\\\\.]", "_");

                    String destination_file = this.getCacheDir().getPath() + "/" + filename;
                    InputStream data = getContentResolver().openInputStream(game);

                    // copyAssetFile automatically closes the InputStream
                    if (copyAssetFile(data, destination_file)) {
                        gamePath = destination_file;
                        storagePermissionUnnecessary = true;
                    }
                } catch (Exception e) {
                    Log.d("GameActivity", "could not read content uri " + game.toString() + ": " + e.getMessage());
                }
            } else {
                Log.e("GameActivity", "Unsupported scheme: '" + game.getScheme() + "'.");

                AlertDialog.Builder alert_dialog = new AlertDialog.Builder(this);
                alert_dialog.setMessage("Could not load LÖVE game '" + path
                        + "' as it uses unsupported scheme '" + game.getScheme()
                        + "'. Please contact the developer.");
                alert_dialog.setTitle("LÖVE for Android Error");
                alert_dialog.setPositiveButton("Exit",
                        new DialogInterface.OnClickListener() {
                            @Override
                            public void onClick(DialogInterface dialog, int id) {
                                finish();
                            }
                        });
                alert_dialog.setCancelable(false);
                alert_dialog.create().show();
            }
        }

        Log.d("GameActivity", "new gamePath: " + gamePath);
    }

    private void copyGameInsideArchive() {
        try {
            // If we have a game.love in our assets folder copy it to the cache folder
            // so that we can load it from native LÖVE code
            AssetManager assetManager = getAssets();
            InputStream gameStream = assetManager.open("game.love");
            String destinationFile = this.getCacheDir().getPath() + "/game.love";

            if (copyAssetFile(gameStream, destinationFile))
                gamePath = destinationFile;
            else
                gamePath = "game.love";
            storagePermissionUnnecessary = true;
        } catch (IOException e) {
            // There's no game.love in our assets
            Log.d("GameActivity", "Could not open game.love from assets: " + e.getMessage());
        }
    }

    protected void checkLovegameFolder() {
        // If no game.love was found and embed flavor is not used, fall back to the game in
        // <external storage>/Android/data/<package name>/games/lovegame
        if (!embed) {
            Log.d("GameActivity", "fallback to lovegame folder");
            File ext = getExternalFilesDir("games");
            if ((new File(ext, "/lovegame/main.lua")).exists()) {
                gamePath = ext.getPath() + "/lovegame/";
                storagePermissionUnnecessary = true;
            } else if (android.os.Build.VERSION.SDK_INT <= 28) {
                // Try to fallback to /sdcard/lovegame in Android 9 and earlier too.
                if (hasExternalStoragePermission()) {
                    ext = Environment.getExternalStorageDirectory();
                    if ((new File(ext, "/lovegame/main.lua")).exists()) {
                        gamePath = ext.getPath() + "/lovegame/";
                        storagePermissionUnnecessary = false;
                    }
                } else {
                    Log.d("GameActivity", "Cannot load game from /sdcard/lovegame: permission not granted");
                }
            }

            Log.d("GameActivity", "lovegame directory: " + gamePath);
        }
    }

    @Override
    protected void onDestroy() {
        if (vibrator != null) {
            Log.d("GameActivity", "Cancelling vibration");
            vibrator.cancel();
        }
        super.onDestroy();
    }

    @Override
    protected void onPause() {
        if (vibrator != null) {
            Log.d("GameActivity", "Cancelling vibration");
            vibrator.cancel();
        }
        teardownSecondaryDisplay();
        super.onPause();
    }

    @Override
    public void onResume() {
        super.onResume();
        setupSecondaryDisplay();
    }

    /**
     * SDL decides the activity's requested orientation at window creation
     * (SDLActivity.setOrientationBis). With a resizable window and no
     * SDL_HINT_ORIENTATIONS -- exactly what conf.lua produces on Android --
     * it asks for SCREEN_ORIENTATION_FULL_SENSOR, and that request overrides
     * the android:screenOrientation="fullUser" set in the manifest. The
     * *_SENSOR constants follow the accelerometer even when the player has
     * turned auto-rotate off, so the game kept rotating on a device whose
     * rotation was locked.
     *
     * Remap SDL's choice onto the matching *_USER constant, which allows the
     * same orientations but defers to the system rotation setting. Applied
     * after super so SDL keeps deciding *which* orientations the window may
     * take; this only changes who breaks the tie, the sensor or the player.
     */
    @Override
    public void setOrientationBis(int w, int h, boolean resizable, String hint) {
        super.setOrientationBis(w, h, resizable, hint);

        // The *_USER constants only exist from API 18; below that the sensor
        // ones are all there is, so leave SDL's request alone.
        if (android.os.Build.VERSION.SDK_INT < 18) {
            return;
        }

        int requested = getRequestedOrientation();
        int userRequested;
        switch (requested) {
            case ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR:
                userRequested = ActivityInfo.SCREEN_ORIENTATION_FULL_USER;
                break;
            case ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE:
                userRequested = ActivityInfo.SCREEN_ORIENTATION_USER_LANDSCAPE;
                break;
            case ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT:
                userRequested = ActivityInfo.SCREEN_ORIENTATION_USER_PORTRAIT;
                break;
            default:
                // SENSOR / plain LANDSCAPE / PORTRAIT etc: either already
                // explicit or never produced by setOrientationBis.
                return;
        }

        Log.d("GameActivity", "requestedOrientation " + requested + " -> " + userRequested
            + " (honour the device rotation lock)");
        setRequestedOrientation(userRequested);
    }

    @Keep
    public void setImmersiveMode(boolean immersive_mode) {
        if (android.os.Build.VERSION.SDK_INT >= 28) {
            getWindow().getAttributes().layoutInDisplayCutoutMode = immersive_mode ?
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES :
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_NEVER;
            shortEdgesMode = immersive_mode;
        }

        immersiveActive = immersive_mode;
    }

    @Keep
    public boolean getImmersiveMode() {
        return immersiveActive;
    }

    @Keep
    public static String getGamePath() {
        GameActivity self = (GameActivity) mSingleton; // use SDL provided one
        Log.d("GameActivity", "called getGamePath(), game path = " + gamePath);

        if (gamePath.length() > 0) {
            if (self.storagePermissionUnnecessary || self.hasExternalStoragePermission()) {
                return gamePath;
            } else {
                Log.d("GameActivity", "cannot open game " + gamePath + ": no external storage permission given!");
            }
        } else if (needToCopyGameInArchive) {
            self.copyGameInsideArchive();
        } else {
            self.checkLovegameFolder();
        }

        return gamePath;
    }

    public static DisplayMetrics getMetrics() {
        return metrics;
    }

    @Keep
    public static void vibrate(double seconds) {
        if (vibrator != null) {
            vibrator.vibrate((long) (seconds * 1000.));
        }
    }

    @Keep
    public static boolean openURLFromLOVE(String url) {
        Log.d("GameActivity", "opening url = " + url);
        return openURL(url) == 0;
    }

    /**
     * Shows the system document picker (Storage Access Framework) so the
     * player can pick a ROM / mod / save from anywhere (Downloads, Drive,
     * etc.) without needing to know where the app's external files folder
     * is. The picked file (if any) arrives later in onActivityResult, not
     * synchronously here.
     *
     * API 21+ uses ACTION_OPEN_DOCUMENT; API 16-20 uses an ACTION_GET_CONTENT
     * chooser instead. Below 19 OPEN_DOCUMENT does not exist, and on 19/20
     * the stock DocumentsUI is unreliable -- it launches and then hands back
     * RESULT_CANCELED with no data, which onActivityResult cannot tell apart
     * from the player cancelling (#584). GET_CONTENT lets any installed file
     * manager serve the pick, and both intents return the same content:// or
     * file:// URI shapes, so the result path in onActivityResult stays
     * picker-agnostic and unchanged.
     *
     * @param destFilename basename under the app save identity (e.g.
     *                     picked_rom.gb, picked_mod.zip, picked_save.sav)
     */
    /** Legacy single-argument entry; resolves the save dir itself. */
    @Keep
    public static boolean showFilePicker(String destFilename) {
        return showFilePicker(destFilename, null);
    }

    @Keep
    public static boolean showFilePicker(String destFilename, String saveDir) {
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        if (destFilename == null || destFilename.length() == 0) {
            destFilename = PICKED_ROM_FILENAME;
        }
        // Remember where LOVE's filesystem is really mounted so
        // onActivityResult copies the pick there, not into a recomputed
        // (possibly different-volume) root (#604, #839).
        self.pendingPickSaveDir = (saveDir != null) ? saveDir : "";
        // Reject path separators so a hostile JNI caller cannot escape the
        // save identity directory.
        if (destFilename.indexOf('/') >= 0 || destFilename.indexOf('\\') >= 0) {
            Log.d("GameActivity", "refusing unsafe picker dest: " + destFilename);
            return false;
        }

        self.pendingPickFilename = destFilename;
        self.pickRetried = false;
        // Only bridge-owned inbox files, never the user's selected source.
        // A previous ready ROM must not wake Lua before this new copy lands.
        try {
            File inbox = self.saveIdentityDir();
            new File(inbox, destFilename).delete();
            new File(inbox, "pick_done.flag").delete();
        } catch (RuntimeException error) {
            Log.e("GameActivity", "could not prepare picker inbox", error);
            return false;
        }
        if (android.os.Build.VERSION.SDK_INT >= 21) {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("*/*");
            // ASK FOR THE READ GRANT OUT LOUD. ACTION_OPEN_DOCUMENT grants it
            // implicitly when the system documents UI serves the pick, but a
            // third-party provider answering the same intent decides for
            // itself, and some only attach a grant when one was requested.
            // Persistable so the grant survives the activity being recreated
            // while the picker is up, which is the common case on low-memory
            // devices -- the pick lands in a new Activity instance that was
            // never granted anything.
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            if (android.os.Build.VERSION.SDK_INT >= 19) {
                intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
            }
            try {
                self.startActivityForResult(intent, FILE_PICKER_REQUEST_CODE);
                return true;
            } catch (Exception e) {
                // Some OEM / TV builds ship without DocumentsUI; fall through
                // to the GET_CONTENT chooser below instead of giving up (#584).
                Log.d("GameActivity", "could not open document picker: " + e.getMessage());
            }
        }
        return self.launchGetContentPicker();
    }

    /**
     * The ACTION_GET_CONTENT half of the picker, as its own method so the
     * result path can reach it too -- see {@link #pickRetried}.
     *
     * @return true when a picker was actually put on screen
     */
    private boolean launchGetContentPicker() {
        Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            startActivityForResult(
                Intent.createChooser(intent, "Choose a file"),
                FILE_PICKER_REQUEST_CODE);
            return true;
        } catch (Exception e) {
            Log.d("GameActivity", "could not open file picker: " + e.getMessage());
            return false;
        }
    }

    /** ROM convenience wrapper; prefer showFilePicker with an explicit name. */
    @Keep
    public static boolean showRomFilePicker() {
        return showFilePicker(PICKED_ROM_FILENAME);
    }

    /** Mod .zip convenience wrapper used by love.system.pickFile("mod"). */
    @Keep
    public static boolean showModFilePicker() {
        return showFilePicker(PICKED_MOD_FILENAME);
    }

    /** Battery .sav convenience wrapper used by love.system.pickFile("sav"). */
    @Keep
    public static boolean showSaveFilePicker() {
        return showFilePicker(PICKED_SAVE_FILENAME);
    }

    /** Image picker convenience wrapper used for skybox selection. */
    @Keep
    public static boolean showImageFilePicker() {
        if (android.os.Build.VERSION.SDK_INT < 19) return false;
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;

        self.pendingPickFilename = PICKED_IMAGE_FILENAME;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("image/*");
        try {
            self.startActivityForResult(intent, FILE_PICKER_REQUEST_CODE);
            return true;
        } catch (Exception e) {
            Log.d("GameActivity", "could not open image picker: " + e.getMessage());
            return false;
        }
    }

    /**
     * App-owned volumes where io.* / PhysFS can actually write: each
     * getExternalFilesDir plus a gamedata/ subdirectory. Phone storage is
     * the first row; a removable SD card (when present) is the rest.
     * Returned as "label\\tpath" lines for love.system.getExternalDataDirs.
     */
    @Keep
    public static String getExternalDataDirs() {
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return "";
        StringBuilder sb = new StringBuilder();
        File[] dirs = self.getExternalFilesDirs(null);
        if (dirs == null) return "";
        for (int i = 0; i < dirs.length; i++) {
            File dir = dirs[i];
            if (dir == null) continue;
            File gameData = new File(dir, GAME_DATA_SUBDIR);
            if (!gameData.exists() && !gameData.mkdirs()) {
                Log.d("GameActivity", "could not create " + gameData);
                continue;
            }
            if (sb.length() > 0) sb.append('\n');
            sb.append(self.volumeLabel(dir, i)).append('\t')
                .append(gameData.getAbsolutePath());
        }
        return sb.toString();
    }

    /**
     * True when POSIX fopen / PhysFS can use shared storage (Downloads, a
     * user-picked tree, the SD card root). App-owned dirs never need this.
     */
    @Keep
    public static boolean hasStorageAccess() {
        if (android.os.Build.VERSION.SDK_INT >= 30) {
            return Environment.isExternalStorageManager();
        }
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        if (android.os.Build.VERSION.SDK_INT < 23) return true;
        return ActivityCompat.checkSelfPermission(self,
            Manifest.permission.WRITE_EXTERNAL_STORAGE)
            == PackageManager.PERMISSION_GRANTED;
    }

    /** True when path is under this app's files / external-files dirs. */
    @Keep
    public static boolean pathIsAppOwned(String path) {
        if (path == null || path.length() == 0) return false;
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        String norm = path.replace('\\', '/');
        if (!norm.endsWith("/")) norm = norm + "/";
        File internal = self.getFilesDir();
        if (internal != null && under(norm, internal)) return true;
        File[] dirs = self.getExternalFilesDirs(null);
        if (dirs != null) {
            for (int i = 0; i < dirs.length; i++) {
                if (dirs[i] != null && under(norm, dirs[i])) return true;
            }
        }
        return false;
    }

    private static boolean under(String normPathWithSlash, File dir) {
        String base = dir.getAbsolutePath().replace('\\', '/');
        if (!base.endsWith("/")) base = base + "/";
        return normPathWithSlash.equals(base) || normPathWithSlash.startsWith(base);
    }

    /**
     * Opens the system "all files access" screen (API 30+) or the legacy
     * write-storage prompt. Does not block: Lua retries on the next focus.
     */
    @Keep
    public static boolean requestStorageAccess() {
        if (hasStorageAccess()) return true;
        final GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        self.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (android.os.Build.VERSION.SDK_INT >= 30) {
                    try {
                        Intent intent = new Intent(
                            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
                        intent.setData(Uri.parse("package:" + self.getPackageName()));
                        self.startActivity(intent);
                    } catch (Exception e) {
                        try {
                            self.startActivity(new Intent(
                                Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION));
                        } catch (Exception e2) {
                            Log.d("GameActivity", "could not open storage settings: "
                                + e2.getMessage());
                        }
                    }
                } else if (android.os.Build.VERSION.SDK_INT >= 23) {
                    ActivityCompat.requestPermissions(self, new String[] {
                        Manifest.permission.WRITE_EXTERNAL_STORAGE,
                        Manifest.permission.READ_EXTERNAL_STORAGE
                    }, EXTERNAL_STORAGE_REQUEST_CODE);
                }
            }
        });
        return true;
    }

    /** Java mkdirs for a game-data tree; FFI mkdir often EACCES on shared storage. */
    @Keep
    public static boolean mkdirsReal(String path) {
        if (path == null || path.length() == 0) return false;
        File dir = new File(path);
        return dir.isDirectory() || dir.mkdirs();
    }

    /**
     * Volume dialog (phone / SD) plus optional ACTION_OPEN_DOCUMENT_TREE.
     * The chosen absolute path is written to picked_folder.txt in the
     * mounted save identity so RomImporter can apply it on the next poll
     * (an AlertDialog does not steal activity focus the way SAF does).
     */
    @Keep
    public static boolean showFolderPicker(String saveDir) {
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        self.pendingPickSaveDir = (saveDir != null) ? saveDir : "";
        self.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                self.showFolderPickerDialog();
            }
        });
        return true;
    }

    private String volumeLabel(File dir, int index) {
        String name = index == 0 ? "Phone storage" : "SD card";
        boolean removable = index > 0;
        if (android.os.Build.VERSION.SDK_INT >= 24) {
            try {
                StorageManager sm = (StorageManager) getSystemService(Context.STORAGE_SERVICE);
                if (sm != null) {
                    StorageVolume vol = sm.getStorageVolume(dir);
                    if (vol != null) {
                        String desc = vol.getDescription(this);
                        if (desc != null && desc.length() > 0) name = desc;
                        removable = vol.isRemovable();
                    }
                }
            } catch (Exception e) {
                // keep the index-based fallback
            }
        }
        long free = bytesFree(dir);
        String extra = free >= 0 ? " · " + formatBytes(free) : "";
        if (removable && index == 0) name = name + " (removable)";
        return name + extra;
    }

    private static long bytesFree(File dir) {
        try {
            StatFs stat = new StatFs(dir.getAbsolutePath());
            if (android.os.Build.VERSION.SDK_INT >= 18) {
                return stat.getAvailableBytes();
            }
            return (long) stat.getAvailableBlocks() * (long) stat.getBlockSize();
        } catch (Exception e) {
            return -1;
        }
    }

    private static String formatBytes(long bytes) {
        double gb = bytes / (1024.0 * 1024.0 * 1024.0);
        if (gb >= 1) {
            return String.format(java.util.Locale.US, "%.1f GB free", gb);
        }
        double mb = bytes / (1024.0 * 1024.0);
        return String.format(java.util.Locale.US, "%.0f MB free", mb);
    }

    private void showFolderPickerDialog() {
        final ArrayList<String> labels = new ArrayList<String>();
        final ArrayList<String> paths = new ArrayList<String>();
        String listing = getExternalDataDirs();
        if (listing != null && listing.length() > 0) {
            String[] lines = listing.split("\n");
            for (int i = 0; i < lines.length; i++) {
                String line = lines[i];
                int tab = line.indexOf('\t');
                if (tab <= 0 || tab >= line.length() - 1) continue;
                labels.add(line.substring(0, tab));
                paths.add(line.substring(tab + 1));
            }
        }
        final boolean canBrowse = android.os.Build.VERSION.SDK_INT >= 21;
        if (canBrowse) labels.add("Browse…");
        if (labels.isEmpty()) {
            writeSaveDirFlag(PICK_ERROR_FILENAME, PICKED_FOLDER_FILENAME
                + "\nno writable storage volume was found");
            return;
        }
        CharSequence[] items = labels.toArray(new CharSequence[labels.size()]);
        new AlertDialog.Builder(this)
            .setTitle("Where to install games and mods")
            .setItems(items, new DialogInterface.OnClickListener() {
                @Override
                public void onClick(DialogInterface dialog, int which) {
                    if (canBrowse && which == labels.size() - 1) {
                        launchTreePicker();
                        return;
                    }
                    if (which >= 0 && which < paths.size()) {
                        acceptPickedFolder(paths.get(which));
                    }
                }
            })
            .setNegativeButton(android.R.string.cancel, null)
            .show();
    }

    private void launchTreePicker() {
        if (android.os.Build.VERSION.SDK_INT < 21) return;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
            | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        if (android.os.Build.VERSION.SDK_INT >= 19) {
            intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        }
        try {
            startActivityForResult(intent, FOLDER_PICKER_REQUEST_CODE);
        } catch (Exception e) {
            Log.d("GameActivity", "could not open folder picker: " + e.getMessage());
            writeSaveDirFlag(PICK_ERROR_FILENAME, PICKED_FOLDER_FILENAME
                + "\ncould not open the system folder picker");
        }
    }

    private void acceptPickedFolder(String path) {
        if (path == null || path.length() == 0) {
            writeSaveDirFlag(PICK_ERROR_FILENAME, PICKED_FOLDER_FILENAME
                + "\nno folder chosen");
            return;
        }
        File dir = new File(path);
        if (!dir.exists() && !dir.mkdirs()) {
            writeSaveDirFlag(PICK_ERROR_FILENAME, PICKED_FOLDER_FILENAME
                + "\ncould not create that folder");
            return;
        }
        if (!pathIsAppOwned(path) && !hasStorageAccess()) {
            requestStorageAccess();
        }
        if (!folderIsWritable(path)) {
            writeSaveDirFlag(PICK_ERROR_FILENAME, PICKED_FOLDER_FILENAME
                + "\nthat folder could not be written to. Grant All files access "
                + "when Android asks, or pick Phone storage / SD card from the list.");
            return;
        }
        writeSaveDirFlag(PICKED_FOLDER_FILENAME, path);
    }

    private boolean folderIsWritable(String path) {
        File dir = new File(path);
        if (!dir.exists() && !dir.mkdirs()) return false;
        File probe = new File(dir, ".gen2recomp-write-test");
        try {
            FileOutputStream fos = new FileOutputStream(probe, false);
            fos.write("gen2recomp".getBytes("UTF-8"));
            fos.close();
            probe.delete();
            return true;
        } catch (Exception e) {
            Log.d("GameActivity", "folder not writable " + path + ": " + e);
            return false;
        }
    }

    /**
     * Best-effort filesystem path for a tree URI. App-owned dirs and some
     * primary-storage trees still resolve; Downloads / Drive usually do
     * not, and folderIsWritable then rejects them instead of pretending.
     */
    private String pathFromTreeUri(Uri uri) {
        if (uri == null) return null;
        if ("file".equals(uri.getScheme()) && uri.getPath() != null) {
            return uri.getPath();
        }
        if (android.os.Build.VERSION.SDK_INT < 21) return null;
        String docId;
        try {
            docId = DocumentsContract.getTreeDocumentId(uri);
        } catch (Exception e) {
            return null;
        }
        if (docId == null || docId.length() == 0) return null;
        String volume;
        String rel = "";
        int colon = docId.indexOf(':');
        if (colon >= 0) {
            volume = docId.substring(0, colon);
            rel = docId.substring(colon + 1);
        } else {
            volume = docId;
        }
        File root;
        if ("primary".equalsIgnoreCase(volume)) {
            root = Environment.getExternalStorageDirectory();
        } else {
            root = new File("/storage/" + volume);
            if (!root.exists()) {
                File alt = new File("/mnt/media_rw/" + volume);
                if (alt.exists()) root = alt;
            }
        }
        if (root == null) return null;
        if (rel == null || rel.length() == 0) return root.getAbsolutePath();
        return new File(root, rel.replace("/", File.separator)).getAbsolutePath();
    }

    /**
     * Relaunches the whole app for love.system.restartApp, used by
     * src/core/HostShell.lua when a mod toggle needs a cold boot (#575).
     * love.event.quit("restart") re-runs LOVE's boot inside the same
     * process, and the second love.filesystem.init throws once physfs
     * failed to deinit ("already initialized"), killing the app. Instead
     * we hand our launch intent to AlarmManager and then exit the process:
     * the alarm lives in system_server, so it survives our death and
     * cannot race the exit the way a plain startActivity right before
     * Runtime.exit can on some OEMs, and the dead process guarantees no
     * native (physfs / SDL / JNI) state leaks into the fresh run.
     */
    @Keep
    public static boolean restartApp() {
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        try {
            Context context = self.getApplicationContext();
            Intent intent = context.getPackageManager()
                .getLaunchIntentForPackage(context.getPackageName());
            if (intent == null) return false;
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
            int pendingFlags = PendingIntent.FLAG_CANCEL_CURRENT;
            if (android.os.Build.VERSION.SDK_INT >= 23) {
                // Mandatory mutability flag on API 31+; harmless from 23 up.
                pendingFlags |= PendingIntent.FLAG_IMMUTABLE;
            }
            PendingIntent pending = PendingIntent.getActivity(
                context, RESTART_REQUEST_CODE, intent, pendingFlags);
            AlarmManager alarm = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
            if (alarm == null) return false;
            alarm.set(AlarmManager.RTC, System.currentTimeMillis() + 250, pending);
        } catch (Exception e) {
            Log.d("GameActivity", "could not schedule restart: " + e.getMessage());
            return false;
        }
        Runtime.getRuntime().exit(0);
        return true; // unreachable, but keeps the JNI signature honest
    }

    /**
     * Blocking HTTPS GET into destPath, exposed as love.system.httpDownload
     * and used by src/core/HostShell.lua. Android ships no curl binary, so
     * every remote fetch the desktop builds do with curl (mod index feeds,
     * mod release lists, mod zips, thumbnails) comes through here (#597).
     * Runs on LOVE's Lua thread, never the UI thread, so the platform's
     * network-on-main-thread rule is not in play and a blocking call matches
     * the curl semantics the Lua callers already expect.
     *
     * Redirects are followed by hand because HttpURLConnection silently drops
     * a redirect that changes protocol, and only https is accepted: the feeds
     * live on GitHub Pages / raw and a downgrade to http must fail, not fetch.
     * The body lands in a .part file and is renamed only once complete, so a
     * dropped connection can never leave a half file the caller trusts.
     */
    @Keep
    public static boolean httpDownload(String url, String destPath, String userAgent, String accept) {
        if (url == null || destPath == null) return false;
        HttpURLConnection conn = null;
        File tmp = new File(destPath + ".part");
        try {
            String current = url;
            for (int hop = 0; hop < 5; hop++) {
                URL parsed = new URL(current);
                if (!"https".equalsIgnoreCase(parsed.getProtocol())) return false;
                conn = (HttpURLConnection) parsed.openConnection();
                conn.setInstanceFollowRedirects(false);
                conn.setConnectTimeout(15000);
                conn.setReadTimeout(60000);
                conn.setRequestProperty("User-Agent",
                    userAgent == null ? "gen1recomp" : userAgent);
                if (accept != null) conn.setRequestProperty("Accept", accept);
                int code = conn.getResponseCode();
                if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
                    String next = conn.getHeaderField("Location");
                    conn.disconnect();
                    conn = null;
                    if (next == null) return false;
                    current = new URL(parsed, next).toString();
                    continue;
                }
                if (code < 200 || code > 299) return false;
                InputStream in = new BufferedInputStream(conn.getInputStream());
                OutputStream out = new BufferedOutputStream(new FileOutputStream(tmp));
                try {
                    byte[] buf = new byte[16384];
                    int n;
                    while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                } finally {
                    try { out.close(); } catch (IOException ignored) {}
                    try { in.close(); } catch (IOException ignored) {}
                }
                File dest = new File(destPath);
                dest.delete();
                if (!tmp.renameTo(dest)) return false;
                return dest.length() > 0;
            }
            return false;
        } catch (Exception e) {
            Log.d("GameActivity", "httpDownload failed: " + e.getMessage());
            return false;
        } finally {
            if (conn != null) conn.disconnect();
            if (tmp.exists()) tmp.delete();
        }
    }

    /**
     * Shows ACTION_CREATE_DOCUMENT so the player can save a staged export
     * (pending_export.sav in the app save identity) to Downloads / Drive /
     * etc. Suggested name is the dialog's default filename.
     *
     * CREATE_DOCUMENT does not exist below API 19 and has no pre-SAF
     * equivalent, so unlike showFilePicker this stays 19+ (#584); the false
     * return degrades on the Lua side (RomImporter export) to "Exported
     * inside the app folder", which is the correct pre-KitKat behavior.
     */
    /** Legacy single-argument entry; resolves the save dir itself. */
    @Keep
    public static boolean showCreateDocument(String suggestedName) {
        return showCreateDocument(suggestedName, null);
    }

    @Keep
    public static boolean showCreateDocument(String suggestedName, String saveDir) {
        if (android.os.Build.VERSION.SDK_INT < 19) return false;
        // (see showFilePicker for why the import side got a pre-19 path)
        GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        if (suggestedName == null || suggestedName.length() == 0) {
            suggestedName = "export.sav";
        }
        if (suggestedName.indexOf('/') >= 0 || suggestedName.indexOf('\\') >= 0) {
            Log.d("GameActivity", "refusing unsafe create name: " + suggestedName);
            return false;
        }
        // Route through the mounted save dir (#604, #839): Lua staged
        // pending_export.sav where physfs writes, which is not necessarily
        // where a fresh getExternalFilesDir(null) points on merged /
        // adopted-SD storage.
        self.pendingPickSaveDir = (saveDir != null) ? saveDir : "";
        File source = new File(self.saveIdentityDir(), PENDING_EXPORT_FILENAME);
        if (!source.isFile()) {
            Log.d("GameActivity", "no pending export at " + source);
            return false;
        }

        self.pendingCreateSuggestedName = suggestedName;
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/octet-stream");
        intent.putExtra(Intent.EXTRA_TITLE, suggestedName);
        try {
            self.startActivityForResult(intent, FILE_CREATE_REQUEST_CODE);
            return true;
        } catch (Exception e) {
            Log.d("GameActivity", "could not open create-document picker: " + e.getMessage());
            return false;
        }
    }

    private File saveIdentityDir() {
        // Prefer the mounted save dir the last bridge call reported: the
        // recomputation below can name a different volume than the one LOVE
        // mounted on merged / adopted-SD storage (#604, #839).
        if (pendingPickSaveDir != null && pendingPickSaveDir.length() > 0) {
            return new File(pendingPickSaveDir);
        }
        File ext = getExternalFilesDir(null);
        if (ext == null) {
            // Shared storage unavailable (ejected / mid-adoption): without
            // this guard File(null, "save") silently built the RELATIVE
            // path save/<identity>, mkdirs() failed against "/", and the
            // pick was dropped with no message at all (#604).
            ext = getFilesDir();
        }
        return new File(new File(ext, "save"), ROM_SAVE_IDENTITY);
    }

    /** Drops a small flag file in the save identity for Lua to consume on focus. */
    private void writeSaveDirFlag(String name, String body) {
        try {
            FileOutputStream fos = new FileOutputStream(new File(saveIdentityDir(), name), false);
            fos.write(body.getBytes("UTF-8"));
            fos.close();
        } catch (IOException e) {
            Log.d("GameActivity", "could not write " + name + ": " + e.getMessage());
        }
    }

    /**
     * Step sync, called from Lua as love.system.syncHealthSteps()
     * (see modules/system/wrap_System.cpp). Asynchronous like the picker:
     * returns whether a sync could be started; the result lands later as
     * steps_pending.json in the save identity dir, where the Pokéwalker
     * mod's poll consumes it.
     *
     * Android 10+ gates the step counter behind the ACTIVITY_RECOGNITION
     * runtime permission; the first call shows the system prompt and a later
     * sync (the mod retries on save load / option change) delivers.
     */
    @Keep
    public static boolean syncHealthSteps() {
        final GameActivity self = (GameActivity) mSingleton;
        if (self == null) return false;
        if (android.os.Build.VERSION.SDK_INT >= 29
                && ActivityCompat.checkSelfPermission(self,
                    Manifest.permission.ACTIVITY_RECOGNITION)
                    != PackageManager.PERMISSION_GRANTED) {
            self.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    ActivityCompat.requestPermissions(self,
                        new String[]{Manifest.permission.ACTIVITY_RECOGNITION},
                        STEP_PERMISSION_REQUEST_CODE);
                }
            });
            return true;
        }
        self.startStepSensorRead();
        return true;
    }

    /**
     * One-shot read of the cumulative hardware step counter. The sensor
     * usually reports its cached value moments after registration; some
     * devices hold the event until the next physical step, so the listener
     * is given 20 seconds before being torn down (the next sync retries).
     */
    private void startStepSensorRead() {
        final SensorManager manager =
            (SensorManager) getSystemService(Context.SENSOR_SERVICE);
        if (manager == null) return;
        Sensor counter = manager.getDefaultSensor(Sensor.TYPE_STEP_COUNTER);
        if (counter == null) {
            Log.d("GameActivity", "no step counter sensor on this device");
            return;
        }
        final SensorEventListener listener = new SensorEventListener() {
            private boolean delivered = false;

            @Override
            public void onSensorChanged(SensorEvent event) {
                if (delivered || event.values.length == 0) return;
                delivered = true;
                manager.unregisterListener(this);
                deliverSteps((long) event.values[0]);
            }

            @Override
            public void onAccuracyChanged(Sensor sensor, int accuracy) {
            }
        };
        if (!manager.registerListener(listener, counter,
                SensorManager.SENSOR_DELAY_NORMAL)) {
            Log.d("GameActivity", "step counter listener registration failed");
            return;
        }
        new Handler(Looper.getMainLooper()).postDelayed(new Runnable() {
            @Override
            public void run() {
                // No-op if the listener already delivered and unregistered.
                manager.unregisterListener(listener);
            }
        }, 20000);
    }

    /**
     * Convert a cumulative counter reading into pending steps. The counter
     * resets to zero on reboot: a reading below the stored anchor re-anchors
     * without crediting (steps walked between the reboot and this sync are
     * lost, which errs on the honest side).
     */
    private void deliverSteps(long counterNow) {
        SharedPreferences prefs = getSharedPreferences(STEP_PREFS, MODE_PRIVATE);
        long anchor = prefs.getLong(STEP_PREF_ANCHOR, -1);
        long now = System.currentTimeMillis();
        if (anchor < 0 || counterNow < anchor) {
            prefs.edit()
                .putLong(STEP_PREF_ANCHOR, counterNow)
                .putLong(STEP_PREF_ANCHOR_WALLTIME, now)
                .apply();
            Log.d("GameActivity", "step anchor set at " + counterNow);
            return;
        }
        long steps = Math.min(counterNow - anchor, STEP_MAX_PER_SYNC);
        long fromWalltime = prefs.getLong(STEP_PREF_ANCHOR_WALLTIME, now);
        if (steps <= 0) return;
        prefs.edit()
            .putLong(STEP_PREF_ANCHOR, counterNow)
            .putLong(STEP_PREF_ANCHOR_WALLTIME, now)
            .apply();

        File dir = saveIdentityDir();
        if (!dir.isDirectory() && !dir.mkdirs()) {
            Log.d("GameActivity", "cannot create save dir for steps: " + dir);
            return;
        }
        File pending = new File(dir, PENDING_STEPS_FILENAME);
        long total = steps;
        // Merge with an unconsumed earlier delivery so steps are never lost
        // (same contract as the iOS bridge).
        if (pending.isFile()) {
            try {
                byte[] raw = new byte[(int) Math.min(pending.length(), 4096)];
                FileInputStream in = new FileInputStream(pending);
                int read = in.read(raw);
                in.close();
                if (read > 0) {
                    org.json.JSONObject old =
                        new org.json.JSONObject(new String(raw, 0, read, "UTF-8"));
                    total += Math.max(0, old.optLong("steps", 0));
                }
            } catch (Exception e) {
                Log.d("GameActivity", "ignoring unreadable pending steps: " + e);
            }
        }
        try {
            org.json.JSONObject payload = new org.json.JSONObject();
            payload.put("steps", total);
            payload.put("from", isoTime(fromWalltime));
            payload.put("to", isoTime(now));
            File tmp = new File(dir, PENDING_STEPS_FILENAME + ".tmp");
            FileOutputStream out = new FileOutputStream(tmp);
            out.write(payload.toString().getBytes("UTF-8"));
            out.close();
            if (!tmp.renameTo(pending)) {
                tmp.delete();
                Log.d("GameActivity", "could not publish pending steps");
                return;
            }
            Log.d("GameActivity", total + " steps pending for the Pokewalker mod");
        } catch (Exception e) {
            Log.d("GameActivity", "could not write pending steps: " + e);
        }
    }

    private static String isoTime(long millis) {
        java.text.SimpleDateFormat format =
            new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US);
        format.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
        return format.format(new java.util.Date(millis));
    }

    private boolean copyFileToUri(File source, Uri destUri) {
        InputStream in = null;
        OutputStream out = null;
        try {
            in = new BufferedInputStream(new FileInputStream(source));
            out = getContentResolver().openOutputStream(destUri);
            if (out == null) return false;
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) != -1) {
                out.write(buf, 0, n);
            }
            out.flush();
            return true;
        } catch (IOException e) {
            Log.d("GameActivity", "copy to URI failed: " + e.getMessage());
            return false;
        } finally {
            try { if (in != null) in.close(); } catch (IOException ignored) {}
            try { if (out != null) out.close(); } catch (IOException ignored) {}
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        outState.putString(STATE_PENDING_PICK, pendingPickFilename);
        outState.putString(STATE_PENDING_PICK_DIR, pendingPickSaveDir);
        outState.putString(STATE_PENDING_CREATE, pendingCreateSuggestedName);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == FILE_CREATE_REQUEST_CODE) {
            if (resultCode != RESULT_OK || data == null || data.getData() == null) {
                Log.d("GameActivity", "create-document cancelled");
                return;
            }
            File source = new File(saveIdentityDir(), PENDING_EXPORT_FILENAME);
            if (!source.isFile()) {
                Log.d("GameActivity", "pending export missing at result time");
                return;
            }
            Uri uri = data.getData();
            if (copyFileToUri(source, uri)) {
                // Signal Lua on next focus that the SAF export finished.
                writeSaveDirFlag(EXPORT_DONE_FILENAME, "ok");
                // Keep pending_export.sav so a retry still works; Lua may remove it.
            } else {
                Log.d("GameActivity", "could not write export to " + uri);
            }
            return;
        }
        if (requestCode == FOLDER_PICKER_REQUEST_CODE) {
            if (resultCode != RESULT_OK || data == null || data.getData() == null) {
                Log.d("GameActivity", "folder picker cancelled");
                return;
            }
            Uri tree = data.getData();
            try {
                int keep = data.getFlags()
                    & (Intent.FLAG_GRANT_READ_URI_PERMISSION
                        | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
                if (keep != 0 && android.os.Build.VERSION.SDK_INT >= 19) {
                    getContentResolver().takePersistableUriPermission(tree, keep);
                }
            } catch (Exception e) {
                Log.d("GameActivity", "no persistable tree grant for " + tree + ": " + e);
            }
            String path = pathFromTreeUri(tree);
            if (path == null) {
                writeSaveDirFlag(PICK_ERROR_FILENAME, PICKED_FOLDER_FILENAME
                    + "\nthat location has no filesystem path this app can write to. "
                    + "Pick Phone storage or an SD card from the list instead.");
                return;
            }
            acceptPickedFolder(path);
            return;
        }
        if (requestCode != FILE_PICKER_REQUEST_CODE) return;
        if (resultCode != RESULT_OK || data == null || data.getData() == null) {
            Log.d("GameActivity", "file picker returned no file (cancelled?)");
            return;
        }

        Uri uri = data.getData();
        File destDir = saveIdentityDir();
        if (!destDir.exists() && !destDir.mkdirs()) {
            Log.d("GameActivity", "could not create " + destDir);
            return;
        }
        String destName = pendingPickFilename != null
            ? pendingPickFilename : PICKED_ROM_FILENAME;
        File destFile = new File(destDir, destName);

        // ACTION_OPEN_DOCUMENT is meant to land in the system documents UI, but
        // some OEM shells (ColorOS) offer third-party file managers in a
        // chooser, and those hand back either a provider URI this app has no
        // grant for (SecurityException / FileNotFoundException) or a bare
        // file:// path (unreadable without storage permission on targetSdk 34).
        //
        // Four routes, then a retry, then -- only then -- a report. Each route
        // records WHY it failed, because "could not read the picked file" with
        // nothing after it is a message no one can act on, least of all from
        // the other end of a bug report.
        String why = null;
        InputStream source = null;

        // The grant first. A persistable grant offered but not taken is
        // dropped when this activity finishes, which is exactly the window a
        // low-memory recreation lands in.
        try {
            int keep = data.getFlags() & Intent.FLAG_GRANT_READ_URI_PERMISSION;
            if (keep != 0 && android.os.Build.VERSION.SDK_INT >= 19) {
                getContentResolver().takePersistableUriPermission(uri, keep);
            }
        } catch (Exception e) {
            // not persistable -- ordinary, and not a failure on its own
            Log.d("GameActivity", "no persistable grant for " + uri + ": " + e);
        }

        try {
            source = getContentResolver().openInputStream(uri);
        } catch (Exception e) {
            why = e.getClass().getSimpleName() + ": " + e.getMessage();
            Log.d("GameActivity", "could not open picked file: " + e);
        }

        // Some providers refuse openInputStream and still serve a descriptor.
        if (source == null) {
            try {
                android.os.ParcelFileDescriptor pfd =
                    getContentResolver().openFileDescriptor(uri, "r");
                if (pfd != null) {
                    source = new android.os.ParcelFileDescriptor.AutoCloseInputStream(pfd);
                }
            } catch (Exception e) {
                if (why == null) why = e.getClass().getSimpleName() + ": " + e.getMessage();
                Log.d("GameActivity", "could not open picked descriptor: " + e);
            }
        }

        if (source == null && "file".equals(uri.getScheme()) && uri.getPath() != null) {
            try {
                source = new FileInputStream(uri.getPath());
            } catch (Exception e) {
                if (why == null) why = e.getClass().getSimpleName() + ": " + e.getMessage();
                Log.d("GameActivity", "could not open picked path: " + e);
            }
        }

        if (source == null) {
            // THE RETRY, BEFORE THE APOLOGY. A dead OPEN_DOCUMENT result is
            // the OEM-chooser case, and GET_CONTENT is the route that works
            // there. Once only -- pickRetried is cleared by showFilePicker.
            if (!pickRetried) {
                pickRetried = true;
                Log.d("GameActivity", "picked file unreadable (" + why
                    + "); retrying through ACTION_GET_CONTENT");
                if (launchGetContentPicker()) return;
            }
            Log.d("GameActivity", "no readable stream for picked file " + uri);
            // The basename stays FIRST and on its own line: Lua matches on it
            // to decide which notice this belongs to. Everything after it is
            // detail, and the scheme/authority pair is enough to name the app
            // that served the pick without carrying the file's own path.
            writeSaveDirFlag(PICK_ERROR_FILENAME, destName
                + "\nfrom " + uri.getScheme() + "://" + uri.getAuthority()
                + "\n" + (why == null ? "no reader accepted it" : why));
            return;
        }
        // Lua polls on its own thread while the provider stream is copied.
        // Publish the recognized filename only after a complete close, so a
        // partial ROM cannot be rejected and blacklisted as the user's pick.
        final InputStream pickedSource = source;
        final String pickedName = destName;
        // Provider/SD copying must not block the Android activity thread.
        new Thread(new Runnable() {
            @Override public void run() {
                boolean published = publishPickedFile(pickedSource, destFile);
                if (!published) {
                    Log.d("GameActivity", "could not copy picked file to " + destFile);
                    writeSaveDirFlag(PICK_ERROR_FILENAME, pickedName
                        + "\nfrom " + uri.getScheme() + "://" + uri.getAuthority()
                        + "\nthe file opened but the copy did not finish");
                } else {
                    writeSaveDirFlag("pick_done.flag", pickedName);
                }
            }
        }, "rom-picker-copy").start();
    }

    boolean publishPickedFile(InputStream source, File destFile) {
        File stagedFile = new File(destFile.getParentFile(), destFile.getName() + ".part");
        boolean published = false;
        try {
            boolean copied = copyAssetFile(source, stagedFile.getPath());
            published = copied && (!destFile.exists() || destFile.delete())
                && stagedFile.renameTo(destFile);
        } catch (RuntimeException error) {
            Log.e("GameActivity", "picked file publication failed", error);
        } finally {
            if (!published) stagedFile.delete();
        }
        return published;
    }

    /**
     * Copies a given file from the assets folder to the destination.
     *
     * @return true if successful
     */
    boolean copyAssetFile(InputStream source, String destinationFileName) {
        // SUCCESS USED TO MEAN "THE STREAMS CLOSED".
        //
        // The old body set `success = true` in the block that closes the two
        // streams, which runs whether or not the copy before it threw -- so a
        // read that died halfway through a provider stream logged "Copying
        // failed", closed cleanly, and returned TRUE. The caller then treated
        // a truncated ROM or a half-written mod zip as imported, and the only
        // symptom was a verification failure much later with nothing pointing
        // back here.
        //
        // Two more things were wrong with it. `assert` is disabled on Android,
        // so a null destination (the FileOutputStream throw above it) reached
        // `destination.write` as an NPE -- not an IOException, so it escaped
        // the catch and unwound out of onActivityResult, which is why some
        // failed picks reported nothing at all. And the do/while wrote before
        // it tested, so a zero-length pick called write(buf, 0, -1).
        if (source == null) return false;

        BufferedOutputStream destination = null;
        boolean success = false;
        long bytesWritten = 0;
        try {
            destination = new BufferedOutputStream(
                new FileOutputStream(destinationFileName, false));
            byte[] buf = new byte[8192];
            int n;
            while ((n = source.read(buf)) != -1) {
                destination.write(buf, 0, n);
                bytesWritten += n;
            }
            destination.flush();
            success = true;
        } catch (Exception e) {
            // Exception, not IOException: a provider stream can throw
            // IllegalStateException or SecurityException mid-read, and those
            // must fail the copy rather than escape it.
            Log.d("GameActivity", "Copying failed: " + e);
        } finally {
            try {
                source.close();
            } catch (IOException e) {
                Log.d("GameActivity", "could not close source: " + e.getMessage());
            }
            if (destination != null) {
                try {
                    // close() flushes, so this is the last place the write can
                    // fail -- and a failure here means the file on disk is
                    // short, whatever happened above.
                    destination.close();
                } catch (IOException e) {
                    success = false;
                    Log.d("GameActivity", "could not close destination: " + e.getMessage());
                }
            }
        }

        Log.d("GameActivity", (success ? "Copied stream to " : "FAILED copying stream to ")
            + destinationFileName + " (" + bytesWritten + " bytes written).");
        return success;
    }

    @Keep
    public boolean hasBackgroundMusic() {
        AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        return audioManager.isMusicActive();
    }

    @Keep
    public void showRecordingAudioPermissionMissingDialog() {
        Log.d("GameActivity", "showRecordingAudioPermissionMissingDialog()");
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                AlertDialog dialog = new AlertDialog.Builder(mSingleton)
                    .setTitle("Audio Recording Permission Missing")
                    .setMessage("It appears that this game uses mic capabilities. The game may not work correctly without mic permission!")
                    .setNeutralButton("Continue", new DialogInterface.OnClickListener() {
                        public void onClick(DialogInterface di, int id) {
                            synchronized (recordAudioRequestDummy) {
                                recordAudioRequestDummy.notify();
                            }
                        }
                    })
                    .create();
                dialog.show();
            }
        });

        synchronized (recordAudioRequestDummy) {
            try {
                recordAudioRequestDummy.wait();
            } catch (InterruptedException e) {
                Log.d("GameActivity", "mic permission dialog", e);
            }
        }
    }

    public void showExternalStoragePermissionMissingDialog() {
        AlertDialog dialog = new AlertDialog.Builder(mSingleton)
            .setTitle("Storage Permission Missing")
            .setMessage("LÖVE for Android will not be able to run non-packaged games without storage permission.")
            .setNeutralButton("Continue", null)
            .create();
        dialog.show();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (grantResults.length > 0) {
            Log.d("GameActivity", "Received a request permission result");

            switch (requestCode) {
                case EXTERNAL_STORAGE_REQUEST_CODE: {
                    if (grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                        Log.d("GameActivity", "Permission granted");
                    } else {
                        Log.d("GameActivity", "Did not get permission.");
                        if (ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.READ_EXTERNAL_STORAGE)) {
                            showExternalStoragePermissionMissingDialog();
                        }
                    }

                    Log.d("GameActivity", "Unlocking LÖVE thread");
                    synchronized (externalStorageRequestDummy) {
                        externalStorageRequestDummy[0] = grantResults[0];
                        externalStorageRequestDummy.notify();
                    }
                    break;
                }
                case RECORD_AUDIO_REQUEST_CODE: {
                    if (grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                        Log.d("GameActivity", "Mic permission granted");
                    } else {
                        Log.d("GameActivity", "Did not get mic permission.");
                    }

                    Log.d("GameActivity", "Unlocking LÖVE thread");
                    synchronized (recordAudioRequestDummy) {
                        recordAudioRequestDummy[0] = grantResults[0];
                        recordAudioRequestDummy.notify();
                    }
                    break;
                }
                case STEP_PERMISSION_REQUEST_CODE: {
                    if (grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                        Log.d("GameActivity", "Step permission granted");
                        // Deliver right away so the sync the player just
                        // opted into doesn't wait for the next launch.
                        startStepSensorRead();
                    } else {
                        Log.d("GameActivity", "Did not get step permission.");
                    }
                    break;
                }
                default:
                    super.onRequestPermissionsResult(requestCode, permissions, grantResults);
            }
        }
    }

    @Keep
    public boolean hasExternalStoragePermission() {
        if (ActivityCompat.checkSelfPermission(this,
                Manifest.permission.READ_EXTERNAL_STORAGE)
                == PackageManager.PERMISSION_GRANTED) {
            return true;
        }

        Log.d("GameActivity", "Requesting permission and locking LÖVE thread until we have an answer.");
        ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.READ_EXTERNAL_STORAGE}, EXTERNAL_STORAGE_REQUEST_CODE);

        synchronized (externalStorageRequestDummy) {
            try {
                externalStorageRequestDummy.wait();
            } catch (InterruptedException e) {
                Log.d("GameActivity", "requesting external storage permission", e);
                return false;
            }
        }

        return ActivityCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED;
    }

    @Keep
    public boolean hasRecordAudioPermission() {
        return ActivityCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
    }

    @Keep
    public void requestRecordAudioPermission() {
        if (ActivityCompat.checkSelfPermission(this,
                Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED) {
            return;
        }

        Log.d("GameActivity", "Requesting mic permission and locking LÖVE thread until we have an answer.");
        ActivityCompat.requestPermissions(this, new String[]{Manifest.permission.RECORD_AUDIO}, RECORD_AUDIO_REQUEST_CODE);

        synchronized (recordAudioRequestDummy) {
            try {
                recordAudioRequestDummy.wait();
            } catch (InterruptedException e) {
                Log.d("GameActivity", "requesting mic permission", e);
            }
        }
    }

    @Keep
    public boolean initializeSafeArea() {
        if (android.os.Build.VERSION.SDK_INT >= 28 && shortEdgesMode) {
            DisplayCutout cutout = getWindow().getDecorView().getRootWindowInsets().getDisplayCutout();

            if (cutout != null) {
                safeAreaTop = cutout.getSafeInsetTop();
                safeAreaLeft = cutout.getSafeInsetLeft();
                safeAreaBottom = cutout.getSafeInsetBottom();
                safeAreaRight = cutout.getSafeInsetRight();
                return true;
            }
        }

        return false;
    }

    @Keep
    public String[] buildFileTree() {
        // Map key is path, value is directory flag
        HashMap<String, Boolean> map = buildFileTree(getAssets(), "", new HashMap<String, Boolean>());
        ArrayList<String> result = new ArrayList<String>();

        for (Map.Entry<String, Boolean> data: map.entrySet()) {
            result.add((data.getValue() ? "d" : "f") + data.getKey());
        }

        String[] r = new String[result.size()];
        result.toArray(r);
        return r;
    }

    private HashMap<String, Boolean> buildFileTree(AssetManager assetManager, String dir, HashMap<String, Boolean> map) {
        String strippedDir = dir.endsWith("/") ? dir.substring(0, dir.length() - 1) : dir;

        // Try open dir
        try {
            InputStream test = assetManager.open(strippedDir);
            // It's a file
            test.close();
            map.put(strippedDir, false);
        } catch (FileNotFoundException e) {
            // It's a directory
            String[] list = null;

            // List files
            try {
                list = assetManager.list(strippedDir);
            } catch (IOException e2) {
                Log.e("GameActivity", strippedDir, e2);
            }

            // Mark as file
            map.put(dir, true);

            // This Object comparison is intentional.
            if (strippedDir != dir) {
                map.put(strippedDir, true);
            }

            if (list != null) {
                for (String path: list) {
                    buildFileTree(assetManager, dir + path + "/", map);
                }
            }
        } catch (IOException e) {
            Log.e("GameActivity", dir, e);
        }

        return map;
    }

    public int getAudioSMP() {
        int smp = 256;

        if (android.os.Build.VERSION.SDK_INT >= 17) {
            AudioManager a = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            int b = Integer.parseInt(a.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER));
            return b > 0 ? b : smp;
        }

        return smp;
    }

    public int getAudioFreq() {
        int freq = 44100;

        if (android.os.Build.VERSION.SDK_INT >= 17) {
            AudioManager a = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            int b = Integer.parseInt(a.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE));
            return b > 0 ? b : freq;
        }

        return freq;
    }

    public boolean isNativeLibsExtracted() {
        ApplicationInfo appInfo = getApplicationInfo();

        if (android.os.Build.VERSION.SDK_INT >= 23) {
            return (appInfo.flags & ApplicationInfo.FLAG_EXTRACT_NATIVE_LIBS) != 0;
        }

        return true;
    }

    @Keep
    public String getCRequirePath() {
        ApplicationInfo applicationInfo = getApplicationInfo();

        if (isNativeLibsExtracted()) {
            return applicationInfo.nativeLibraryDir + "/?.so";
        } else {
            // The native libs are inside the APK and can be loaded directly.
            // FIXME: What about split APKs?
            String abi;

            if (android.os.Build.VERSION.SDK_INT >= 21) {
                 abi = android.os.Build.SUPPORTED_ABIS[0];
            } else {
                // This codepath should NEVER be taken as if isNativeLibsExtracted()
                // returns false, it's 100% safe to assume we're on API level 23 or later.
                abi = android.os.Build.CPU_ABI;
            }

            return applicationInfo.sourceDir + "!/lib/" + abi + "/?.so";
        }
    }

    // Dual-screen: mirror the engine's bottom-screen canvas onto a secondary
    // physical display. Driven from the engine through love_android_secondary_*
    // in src/jni/love/src/common/android.cpp.
    private static volatile SecondaryPresentation secondaryPresentation;
    private static volatile boolean secondaryEnabled = false;
    private static final int MAX_SECONDARY_TOUCHES = 32;
    private static final java.util.ArrayDeque<String> secondaryTouches =
        new java.util.ArrayDeque<>();

    @Keep
    public static void setSecondaryEnabled(final boolean on) {
        secondaryEnabled = on;
        final GameActivity self = (GameActivity) mSingleton;
        if (self == null) return;
        self.runOnUiThread(new Runnable() {
            @Override public void run() {
                if (on) setupSecondaryDisplay(); else teardownSecondaryDisplay();
            }
        });
    }

    private static void setupSecondaryDisplay() {
        GameActivity self = (GameActivity) mSingleton;
        if (self == null || !secondaryEnabled || secondaryPresentation != null) return;
        try {
            android.hardware.display.DisplayManager dm =
                (android.hardware.display.DisplayManager) self.getSystemService(Context.DISPLAY_SERVICE);
            if (dm == null) return;
            Display chosen = null;
            for (Display d : dm.getDisplays()) {
                android.graphics.Point size = new android.graphics.Point();
                d.getRealSize(size);
                Log.d("GameActivity", "display id=" + d.getDisplayId() + " name=" + d.getName()
                    + " size=" + size.x + "x" + size.y);
                if (chosen == null && d.getDisplayId() != Display.DEFAULT_DISPLAY) {
                    chosen = d;
                }
            }
            if (chosen == null) {
                Display[] pres =
                    dm.getDisplays(android.hardware.display.DisplayManager.DISPLAY_CATEGORY_PRESENTATION);
                if (pres != null && pres.length > 0) chosen = pres[0];
            }
            if (chosen == null) {
                Log.d("GameActivity", "no secondary display found");
                return;
            }
            SecondaryPresentation p = new SecondaryPresentation(self, chosen);
            p.show();
            secondaryPresentation = p;
            Log.d("GameActivity", "secondary display presentation started on id=" + chosen.getDisplayId());
        } catch (Throwable t) {
            Log.d("GameActivity", "secondary display setup failed: " + t);
            secondaryPresentation = null;
        }
    }

    private static void teardownSecondaryDisplay() {
        SecondaryPresentation p = secondaryPresentation;
        secondaryPresentation = null;
        synchronized (secondaryTouches) { secondaryTouches.clear(); }
        if (p != null) {
            try { p.dismiss(); } catch (Throwable t) {}
        }
    }

    @Keep
    public static boolean hasSecondaryDisplay() {
        return secondaryPresentation != null;
    }

    @Keep
    public static void updateSecondaryFrame(java.nio.ByteBuffer buf, int w, int h) {
        SecondaryPresentation p = secondaryPresentation;
        if (p != null && buf != null && w > 0 && h > 0) {
            p.updateFrame(buf, w, h);
        }
    }

    @Keep
    public static String pollSecondaryDisplayTouch() {
        synchronized (secondaryTouches) {
            return secondaryTouches.pollFirst();
        }
    }

    private static class SecondaryPresentation extends android.app.Presentation {
        private final FrameView frameView;

        SecondaryPresentation(Context context, Display display) {
            super(context, display);
            frameView = new FrameView(context);
        }

        @Override
        protected void onCreate(Bundle savedInstanceState) {
            super.onCreate(savedInstanceState);
            android.view.Window w = getWindow();
            if (w != null) {
                w.setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN
                    | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    WindowManager.LayoutParams.FLAG_FULLSCREEN
                    | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS);
                w.setLayout(WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT);
            }
            setContentView(frameView);
            applyImmersive();
            frameView.post(new Runnable() {
                @Override public void run() { applyImmersive(); }
            });
        }

        @Override
        public void onWindowFocusChanged(boolean hasFocus) {
            super.onWindowFocusChanged(hasFocus);
            if (hasFocus) applyImmersive();
        }

        private void applyImmersive() {
            android.view.Window w = getWindow();
            if (w == null) return;
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                w.setDecorFitsSystemWindows(false);
                android.view.WindowInsetsController c = w.getInsetsController();
                if (c != null) {
                    c.hide(android.view.WindowInsets.Type.systemBars());
                    c.setSystemBarsBehavior(
                        android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
                }
            } else {
                w.getDecorView().setSystemUiVisibility(
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    | android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    | android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    | android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    | android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
                    | android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
            }
        }

        void updateFrame(java.nio.ByteBuffer buf, int w, int h) {
            frameView.updateFrame(buf, w, h);
        }
    }

    private static class FrameView extends View {
        private android.graphics.Bitmap bitmap;
        private final android.graphics.Rect dst = new android.graphics.Rect();
        private final android.graphics.Paint paint = new android.graphics.Paint();
        private final Object lock = new Object();
        private int fw, fh;
        private int activePointer = -1;

        FrameView(Context context) {
            super(context);
            paint.setFilterBitmap(false);
            paint.setAntiAlias(false);
            setBackgroundColor(0xFF000000);
        }

        void updateFrame(java.nio.ByteBuffer buf, int w, int h) {
            synchronized (lock) {
                if (bitmap == null || fw != w || fh != h) {
                    if (bitmap != null) bitmap.recycle();
                    bitmap = android.graphics.Bitmap.createBitmap(w, h, android.graphics.Bitmap.Config.ARGB_8888);
                    fw = w; fh = h;
                }
                buf.rewind();
                bitmap.copyPixelsFromBuffer(buf);
            }
            postInvalidate();
        }

        private void enqueueTouch(String event) {
            synchronized (secondaryTouches) {
                if (secondaryTouches.size() >= MAX_SECONDARY_TOUCHES) {
                    secondaryTouches.clear();
                    secondaryTouches.addLast("cancel,0,0");
                } else {
                    secondaryTouches.addLast(event);
                }
            }
        }

        private int logicalX(float x) {
            return Math.min(fw - 1, Math.max(0,
                (int) ((x - dst.left) * fw / dst.width())));
        }

        private int logicalY(float y) {
            return Math.min(fh - 1, Math.max(0,
                (int) ((y - dst.top) * fh / dst.height())));
        }

        @Override
        public boolean onTouchEvent(android.view.MotionEvent event) {
            synchronized (lock) {
                int action = event.getActionMasked();
                if (action == android.view.MotionEvent.ACTION_DOWN && fw > 0
                        && dst.contains((int) event.getX(), (int) event.getY())) {
                    activePointer = event.getPointerId(0);
                    enqueueTouch("down," + logicalX(event.getX()) + ","
                        + logicalY(event.getY()));
                } else if (action == android.view.MotionEvent.ACTION_UP
                        && activePointer >= 0) {
                    int index = event.findPointerIndex(activePointer);
                    if (index >= 0 && fw > 0) {
                        enqueueTouch("up," + logicalX(event.getX(index)) + ","
                            + logicalY(event.getY(index)));
                    }
                    activePointer = -1;
                } else if (action == android.view.MotionEvent.ACTION_CANCEL) {
                    activePointer = -1;
                    enqueueTouch("cancel,0,0");
                }
            }
            return true;
        }

        @Override
        protected void onDraw(android.graphics.Canvas canvas) {
            synchronized (lock) {
                if (bitmap == null || fw == 0 || fh == 0) return;
                int vw = getWidth(), vh = getHeight();
                int s = Math.min(vw / fw, vh / fh);
                if (s < 1) s = 1;
                int dw = fw * s, dh = fh * s;
                int dx = (vw - dw) / 2, dy = (vh - dh) / 2;
                dst.set(dx, dy, dx + dw, dy + dh);
                canvas.drawColor(0xFF000000);
                canvas.drawBitmap(bitmap, null, dst, paint);
            }
        }
    }

    public static byte[] translateOffline(String source, String target, byte[] input) throws Exception {
        return OfflineTranslation.translate(source, target, input);
    }

    public static boolean closeOfflineTranslation() {
        OfflineTranslation.close();
        return true;
    }
}
