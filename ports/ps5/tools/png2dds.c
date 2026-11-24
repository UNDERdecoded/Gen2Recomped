/* png2dds: PNG -> 3840x2160 BC7_UNORM DX10 DDS for a PS5 title's
 * sce_sys/pic0.dds and pic1.dds (single surface, no mipmaps; the layout the
 * ps5-native-app-boilerplate's validate-assets.sh accepts).
 *
 *   png2dds <in.png> <out.dds>
 *
 * Built for the host by scripts/build_ps5.sh against LOVE's bundled
 * stb_image.h. The input is scaled to 3840x2160 (bilinear) if it has another
 * size. Every 4x4 block is BC7 mode 6 (one subset, RGBA 7.7.7.7 endpoints
 * with p-bits, 4-bit indices), endpoints along the block's principal colour
 * axis: not texconv quality, but plenty for a home-screen background, and no
 * Windows tool or extra download. */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#include "stb_image.h"

enum { W = 3840, H = 2160 };

static const int weights[16] = {0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64};

typedef struct {
    uint64_t lo, hi;
    int pos;
} Bits;

static void put(Bits *b, uint32_t value, int count)
{
    for (int i = 0; i < count; i++, b->pos++) {
        uint64_t bit = (value >> i) & 1;
        if (b->pos < 64)
            b->lo |= bit << b->pos;
        else
            b->hi |= bit << (b->pos - 64);
    }
}

/* 8-bit endpoint from 7 bits + p-bit; the best (7-bit, p) pair for a target. */
static void quantize(const float target[4], int p, int out7[4])
{
    for (int c = 0; c < 4; c++) {
        int v = (int)lrintf((target[c] - p) / 2.0f);
        out7[c] = v < 0 ? 0 : v > 127 ? 127 : v;
    }
}

static int expand(int v7, int p) { return (v7 << 1) | p; }

static float encode_block(const uint8_t px[16][4], Bits *out)
{
    float mean[4] = {0}, cov[4][4] = {{0}};
    for (int i = 0; i < 16; i++)
        for (int c = 0; c < 4; c++)
            mean[c] += px[i][c] / 16.0f;
    for (int i = 0; i < 16; i++)
        for (int a = 0; a < 4; a++)
            for (int b = 0; b < 4; b++)
                cov[a][b] += (px[i][a] - mean[a]) * (px[i][b] - mean[b]);
    float axis[4] = {1, 1, 1, 0.5f};
    for (int it = 0; it < 8; it++) {
        float next[4] = {0}, len = 0;
        for (int a = 0; a < 4; a++)
            for (int b = 0; b < 4; b++)
                next[a] += cov[a][b] * axis[b];
        for (int a = 0; a < 4; a++)
            len += next[a] * next[a];
        if (len < 1e-6f)
            break;
        len = sqrtf(len);
        for (int a = 0; a < 4; a++)
            axis[a] = next[a] / len;
    }
    float lo = 1e9f, hi = -1e9f;
    for (int i = 0; i < 16; i++) {
        float t = 0;
        for (int c = 0; c < 4; c++)
            t += (px[i][c] - mean[c]) * axis[c];
        lo = t < lo ? t : lo;
        hi = t > hi ? t : hi;
    }
    float e[2][4];
    for (int c = 0; c < 4; c++) {
        e[0][c] = fminf(255, fmaxf(0, mean[c] + axis[c] * lo));
        e[1][c] = fminf(255, fmaxf(0, mean[c] + axis[c] * hi));
    }

    float best_err = 1e30f;
    int best_q[2][4] = {{0}}, best_p[2] = {0}, best_idx[16] = {0};
    for (int p0 = 0; p0 < 2; p0++) {
        for (int p1 = 0; p1 < 2; p1++) {
            int q[2][4], ep[2][4];
            quantize(e[0], p0, q[0]);
            quantize(e[1], p1, q[1]);
            for (int c = 0; c < 4; c++) {
                ep[0][c] = expand(q[0][c], p0);
                ep[1][c] = expand(q[1][c], p1);
            }
            int pal[16][4];
            for (int k = 0; k < 16; k++)
                for (int c = 0; c < 4; c++)
                    pal[k][c] = ((64 - weights[k]) * ep[0][c] + weights[k] * ep[1][c] + 32) >> 6;
            float err = 0;
            int idx[16];
            for (int i = 0; i < 16; i++) {
                int bk = 0, be = 1 << 30;
                for (int k = 0; k < 16; k++) {
                    int d = 0;
                    for (int c = 0; c < 4; c++) {
                        int x = pal[k][c] - px[i][c];
                        d += x * x;
                    }
                    if (d < be) {
                        be = d;
                        bk = k;
                    }
                }
                idx[i] = bk;
                err += be;
            }
            if (err < best_err) {
                best_err = err;
                memcpy(best_q, q, sizeof(q));
                best_p[0] = p0;
                best_p[1] = p1;
                memcpy(best_idx, idx, sizeof(idx));
            }
        }
    }
    /* The anchor (pixel 0) index is stored with 3 bits: its top bit must be 0. */
    if (best_idx[0] & 8) {
        for (int c = 0; c < 4; c++) {
            int t = best_q[0][c];
            best_q[0][c] = best_q[1][c];
            best_q[1][c] = t;
        }
        int t = best_p[0];
        best_p[0] = best_p[1];
        best_p[1] = t;
        for (int i = 0; i < 16; i++)
            best_idx[i] = 15 - best_idx[i];
    }
    memset(out, 0, sizeof(*out));
    put(out, 1u << 6, 7); /* mode 6 */
    for (int c = 0; c < 4; c++) {
        put(out, (uint32_t)best_q[0][c], 7);
        put(out, (uint32_t)best_q[1][c], 7);
    }
    put(out, (uint32_t)best_p[0], 1);
    put(out, (uint32_t)best_p[1], 1);
    put(out, (uint32_t)best_idx[0], 3);
    for (int i = 1; i < 16; i++)
        put(out, (uint32_t)best_idx[i], 4);
    return best_err;
}

static void put32(uint8_t *p, uint32_t v)
{
    p[0] = v & 255;
    p[1] = (v >> 8) & 255;
    p[2] = (v >> 16) & 255;
    p[3] = v >> 24;
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: png2dds <in.png> <out.dds>\n");
        return 2;
    }
    int sw, sh, n;
    uint8_t *src = stbi_load(argv[1], &sw, &sh, &n, 4);
    if (!src) {
        fprintf(stderr, "png2dds: cannot read %s: %s\n", argv[1], stbi_failure_reason());
        return 1;
    }
    uint8_t *img = malloc((size_t)W * H * 4);
    for (int y = 0; y < H; y++) {
        float fy = (y + 0.5f) * sh / H - 0.5f;
        int y0 = (int)floorf(fy);
        float ty = fy - y0;
        int ya = y0 < 0 ? 0 : y0, yb = y0 + 1 >= sh ? sh - 1 : y0 + 1;
        for (int x = 0; x < W; x++) {
            float fx = (x + 0.5f) * sw / W - 0.5f;
            int x0 = (int)floorf(fx);
            float tx = fx - x0;
            int xa = x0 < 0 ? 0 : x0, xb = x0 + 1 >= sw ? sw - 1 : x0 + 1;
            for (int c = 0; c < 4; c++) {
                float a = src[((size_t)ya * sw + xa) * 4 + c], b = src[((size_t)ya * sw + xb) * 4 + c];
                float d = src[((size_t)yb * sw + xa) * 4 + c], e = src[((size_t)yb * sw + xb) * 4 + c];
                float v = (a + (b - a) * tx) * (1 - ty) + (d + (e - d) * tx) * ty;
                img[((size_t)y * W + x) * 4 + c] = (uint8_t)lrintf(v);
            }
        }
    }
    stbi_image_free(src);

    const size_t data_size = (size_t)W * H; /* 16 bytes per 4x4 block */
    uint8_t header[148] = {0};
    memcpy(header, "DDS ", 4);
    put32(header + 4, 124);
    put32(header + 8, 0x000A1007); /* caps, height, width, pixelformat, mipmapcount, linearsize */
    put32(header + 12, H);
    put32(header + 16, W);
    put32(header + 20, (uint32_t)data_size);
    put32(header + 28, 1);
    put32(header + 76, 32);
    put32(header + 80, 4); /* DDPF_FOURCC */
    memcpy(header + 84, "DX10", 4);
    put32(header + 108, 0x1000); /* DDSCAPS_TEXTURE */
    put32(header + 128, 98);     /* DXGI_FORMAT_BC7_UNORM */
    put32(header + 132, 3);      /* D3D10_RESOURCE_DIMENSION_TEXTURE2D */
    put32(header + 140, 1);      /* array size */

    FILE *f = fopen(argv[2], "wb");
    if (!f) {
        fprintf(stderr, "png2dds: cannot write %s\n", argv[2]);
        return 1;
    }
    fwrite(header, 1, sizeof(header), f);
    double total = 0;
    for (int by = 0; by < H; by += 4) {
        for (int bx = 0; bx < W; bx += 4) {
            uint8_t px[16][4];
            for (int i = 0; i < 16; i++)
                memcpy(px[i], img + ((size_t)(by + i / 4) * W + bx + i % 4) * 4, 4);
            Bits b;
            total += encode_block(px, &b);
            uint8_t block[16];
            for (int i = 0; i < 8; i++) {
                block[i] = (uint8_t)(b.lo >> (8 * i));
                block[8 + i] = (uint8_t)(b.hi >> (8 * i));
            }
            fwrite(block, 1, 16, f);
        }
    }
    fclose(f);
    free(img);
    printf("png2dds: %s -> %s (%dx%d from %dx%d, RMSE %.2f)\n", argv[1], argv[2], W, H, sw, sh,
           sqrt(total / ((double)W * H * 4)));
    return 0;
}
