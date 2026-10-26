// Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
// Host test transport for Android's POSIX rename seam; no sensor/OS proof.
package android.system;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.io.IOException;
public final class Os {
    public static boolean failRename = false;
    public static void rename(String source, String target) throws IOException {
        if (failRename) throw new IOException("injected atomic publication failure");
        Files.move(Path.of(source), Path.of(target), StandardCopyOption.ATOMIC_MOVE,
                   StandardCopyOption.REPLACE_EXISTING);
    }
}
