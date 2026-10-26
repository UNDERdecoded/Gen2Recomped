// Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
// Host-only codec adapter. Android builds use the platform implementation.
package android.util;
public final class Base64 {
    public static final int DEFAULT=0,NO_WRAP=2;
    public static byte[] decode(String input,int flags) {return java.util.Base64.getMimeDecoder().decode(input);}
    public static String encodeToString(byte[] input,int flags) {return java.util.Base64.getEncoder().encodeToString(input);}
}
