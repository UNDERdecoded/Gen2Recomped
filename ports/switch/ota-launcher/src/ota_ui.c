/*
 * Switch OTA UI — matches in-game launcher language (Theme.lua):
 * black field, RGB version rail, flat yellow/white buttons, white ink.
 * Quiet until called. Uses framebuffer + 8x8 font + optional romfs logo.
 */
#include "ota_ui.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__SWITCH__)
#include <switch.h>

#include "../third_party/font8x8_basic.h"

#define OTA_LOGO_ROMFS "romfs:/logo.rgba"

#define FB_W 1280
#define FB_H 720

#define TITLE_Y 200
#define LINE_TITLE 44
#define LINE_BODY 36
#define LINE_SMALL 28
#define WRAP_MAX_PX 720

/* Theme.PAL (0-255) -> RGBA8 */
#define COL_BG RGBA8_MAXALPHA(0, 0, 0)
#define COL_INK RGBA8_MAXALPHA(255, 255, 255)
#define COL_DETAIL RGBA8_MAXALPHA(200, 200, 200)
#define COL_MUTED RGBA8_MAXALPHA(150, 150, 150)
#define COL_INVERSE RGBA8_MAXALPHA(0, 0, 0)
#define COL_YELLOW RGBA8_MAXALPHA(255, 214, 0)
#define COL_GREEN RGBA8_MAXALPHA(0, 255, 140)
#define COL_RAIL_R RGBA8_MAXALPHA(255, 60, 72)
#define COL_RAIL_B RGBA8_MAXALPHA(70, 150, 255)
#define COL_RAIL_G RGBA8_MAXALPHA(255, 203, 5)
#define COL_LINE RGBA8_MAXALPHA(90, 90, 90)
#define COL_RAISED RGBA8_MAXALPHA(20, 20, 20)

static int g_ready = 0;
static Framebuffer g_fb;
static PadState g_pad;
static u32 *g_logo = NULL;
static int g_logo_w = 0, g_logo_h = 0;

static void fill_rect(u32 *fb, u32 stride_px, int x, int y, int w, int h, u32 color) {
  if (w <= 0 || h <= 0) return;
  if (x < 0) {
    w += x;
    x = 0;
  }
  if (y < 0) {
    h += y;
    y = 0;
  }
  if (x + w > FB_W) w = FB_W - x;
  if (y + h > FB_H) h = FB_H - y;
  if (w <= 0 || h <= 0) return;
  for (int row = 0; row < h; row++) {
    u32 *line = fb + (y + row) * stride_px + x;
    for (int col = 0; col < w; col++) line[col] = color;
  }
}

/* Normalize UTF-8 punctuation to ASCII; drop other non-ASCII bytes. */
static size_t ota_ui_sanitize_ascii(const char *src, char *dst, size_t dst_len) {
  if (!dst || dst_len == 0) return 0;
  dst[0] = '\0';
  if (!src) return 0;
  size_t w = 0;
  for (size_t i = 0; src[i] && w + 1 < dst_len;) {
    unsigned char c = (unsigned char)src[i];
    if (c < 0x80) {
      dst[w++] = (char)c;
      i++;
      continue;
    }
    if (c == 0xE2 && src[i + 1] && src[i + 2]) {
      unsigned char b2 = (unsigned char)src[i + 1];
      unsigned char b3 = (unsigned char)src[i + 2];
      if (b2 == 0x80 && b3 == 0xA6) {
        if (w + 3 < dst_len) {
          dst[w++] = '.';
          dst[w++] = '.';
          dst[w++] = '.';
        }
        i += 3;
        continue;
      }
      if (b2 == 0x80 && (b3 == 0x94 || b3 == 0x93)) {
        dst[w++] = '-';
        i += 3;
        continue;
      }
      if (b2 == 0x80 && (b3 == 0x98 || b3 == 0x99)) {
        dst[w++] = '\'';
        i += 3;
        continue;
      }
    }
    if ((c & 0xE0) == 0xC0) i += 2;
    else if ((c & 0xF0) == 0xE0) i += 3;
    else if ((c & 0xF8) == 0xF0) i += 4;
    else i++;
  }
  dst[w] = '\0';
  return w;
}

static void draw_glyph(u32 *fb, u32 stride_px, int x, int y, char ch, u32 color, int scale) {
  unsigned char c = (unsigned char)ch;
  if (c > 127) return;
  const char *bits = font8x8_basic[c];
  for (int row = 0; row < 8; row++) {
    unsigned char line = (unsigned char)bits[row];
    for (int col = 0; col < 8; col++) {
      if (line & (1 << col)) {
        fill_rect(fb, stride_px, x + col * scale, y + row * scale, scale, scale, color);
      }
    }
  }
}

static int text_width(const char *s, int scale) {
  if (!s) return 0;
  return (int)strlen(s) * 8 * scale;
}

static void draw_text(u32 *fb, u32 stride_px, int x, int y, const char *s, u32 color, int scale) {
  if (!s) return;
  char buf[512];
  ota_ui_sanitize_ascii(s, buf, sizeof(buf));
  int cx = x;
  for (const char *p = buf; *p; p++) {
    if (*p == '\n') {
      cx = x;
      y += 8 * scale + 4;
      continue;
    }
    draw_glyph(fb, stride_px, cx, y, *p, color, scale);
    cx += 8 * scale;
  }
}

static void draw_text_centered(u32 *fb, u32 stride_px, int y, const char *s, u32 color, int scale) {
  char buf[512];
  ota_ui_sanitize_ascii(s, buf, sizeof(buf));
  int w = text_width(buf, scale);
  draw_text(fb, stride_px, (FB_W - w) / 2, y, buf, color, scale);
}

static int draw_text_wrapped_centered(u32 *fb, u32 stride_px, int y, const char *s, u32 color,
                                      int scale, int max_px) {
  if (!s || !*s) return y;
  char buf[512];
  ota_ui_sanitize_ascii(s, buf, sizeof(buf));
  int char_w = 8 * scale;
  int max_chars = max_px / char_w;
  if (max_chars < 8) max_chars = 8;

  char line[128];
  int line_len = 0;
  const char *word = buf;
  int lines = 0;

  while (*word) {
    while (*word == ' ') word++;
    if (!*word) break;

    const char *end = word;
    while (*end && *end != ' ' && *end != '\n') end++;
    int wlen = (int)(end - word);

    if (line_len > 0 && line_len + 1 + wlen > max_chars) {
      line[line_len] = '\0';
      draw_text_centered(fb, stride_px, y, line, color, scale);
      y += 8 * scale + 4;
      lines++;
      line_len = 0;
    }

    if (wlen > max_chars) {
      if (line_len > 0) {
        line[line_len] = '\0';
        draw_text_centered(fb, stride_px, y, line, color, scale);
        y += 8 * scale + 4;
        lines++;
        line_len = 0;
      }
      while (wlen > 0) {
        int chunk = wlen > max_chars ? max_chars : wlen;
        memcpy(line, word, (size_t)chunk);
        line[chunk] = '\0';
        draw_text_centered(fb, stride_px, y, line, color, scale);
        y += 8 * scale + 4;
        lines++;
        word += chunk;
        wlen -= chunk;
      }
      word = end;
      continue;
    }

    if (line_len > 0) line[line_len++] = ' ';
    memcpy(line + line_len, word, (size_t)wlen);
    line_len += wlen;
    line[line_len] = '\0';
    word = (*end == '\n') ? end + 1 : end;
    if (*(end - 1) == '\n' || *end == '\n') {
      draw_text_centered(fb, stride_px, y, line, color, scale);
      y += 8 * scale + 4;
      lines++;
      line_len = 0;
      if (*end == '\n') word = end + 1;
    }
  }

  if (line_len > 0) {
    draw_text_centered(fb, stride_px, y, line, color, scale);
    y += 8 * scale + 4;
    lines++;
  }
  if (lines == 0) return y;
  return y;
}

static void draw_rail(u32 *fb, u32 stride_px) {
  int h = 6;
  int third = FB_W / 3;
  fill_rect(fb, stride_px, 0, 0, third, h, COL_RAIL_R);
  fill_rect(fb, stride_px, third, 0, third, h, COL_RAIL_B);
  fill_rect(fb, stride_px, third * 2, 0, FB_W - third * 2, h, COL_RAIL_G);
}

static void blit_logo(u32 *fb, u32 stride_px, int dst_x, int dst_y, int max_w) {
  if (!g_logo || g_logo_w <= 0 || g_logo_h <= 0) return;
  int dw = g_logo_w;
  int dh = g_logo_h;
  if (dw > max_w) {
    dh = dh * max_w / dw;
    dw = max_w;
  }
  for (int y = 0; y < dh; y++) {
    int sy = y * g_logo_h / dh;
    for (int x = 0; x < dw; x++) {
      int sx = x * g_logo_w / dw;
      u32 px = g_logo[sy * g_logo_w + sx];
      u8 a = (px >> 24) & 0xff;
      if (a < 16) continue;
      int dx = dst_x + x;
      int dy = dst_y + y;
      if (dx < 0 || dy < 0 || dx >= FB_W || dy >= FB_H) continue;
      fb[dy * stride_px + dx] = px | 0xff000000u;
    }
  }
}

static void load_logo(void) {
  if (g_logo) return;
  FILE *fp = fopen(OTA_LOGO_ROMFS, "rb");
  if (!fp) return;

  unsigned char header[8];
  if (fread(header, 1, sizeof(header), fp) != sizeof(header)) {
    fclose(fp);
    return;
  }

  int w = (int)(header[0] | (header[1] << 8) | (header[2] << 16) | (header[3] << 24));
  int h = (int)(header[4] | (header[5] << 8) | (header[6] << 16) | (header[7] << 24));
  if (w <= 0 || h <= 0 || w > 2048 || h > 2048) {
    fclose(fp);
    return;
  }

  size_t nbytes = (size_t)w * (size_t)h * 4u;
  unsigned char *data = (unsigned char *)malloc(nbytes);
  if (!data) {
    fclose(fp);
    return;
  }
  if (fread(data, 1, nbytes, fp) != nbytes) {
    free(data);
    fclose(fp);
    return;
  }
  fclose(fp);

  g_logo = (u32 *)malloc((size_t)w * (size_t)h * sizeof(u32));
  if (!g_logo) {
    free(data);
    return;
  }
  for (int i = 0; i < w * h; i++) {
    unsigned char *p = data + (size_t)i * 4u;
    g_logo[i] = RGBA8(p[0], p[1], p[2], p[3]);
  }
  free(data);
  g_logo_w = w;
  g_logo_h = h;
}

static int ui_ensure(void) {
  if (g_ready) return 1;
  NWindow *win = nwindowGetDefault();
  if (R_FAILED(framebufferCreate(&g_fb, win, FB_W, FB_H, PIXEL_FORMAT_RGBA_8888, 2))) return 0;
  framebufferMakeLinear(&g_fb);
  padInitializeDefault(&g_pad);
  load_logo();
  g_ready = 1;
  return 1;
}

void ota_ui_shutdown(void) {
  if (!g_ready) return;
  framebufferClose(&g_fb);
  free(g_logo);
  g_logo = NULL;
  g_logo_w = g_logo_h = 0;
  g_ready = 0;
}

static void draw_button(u32 *fb, u32 stride_px, int x, int y, int w, int h, u32 fill, u32 ink,
                        const char *label, int focused) {
  fill_rect(fb, stride_px, x, y, w, h, fill);
  if (focused) {
    fill_rect(fb, stride_px, x - 3, y - 3, w + 6, 2, COL_INK);
    fill_rect(fb, stride_px, x - 3, y + h + 1, w + 6, 2, COL_INK);
    fill_rect(fb, stride_px, x - 3, y - 3, 2, h + 6, COL_INK);
    fill_rect(fb, stride_px, x + w + 1, y - 3, 2, h + 6, COL_INK);
  } else {
    fill_rect(fb, stride_px, x, y, w, 1, COL_LINE);
    fill_rect(fb, stride_px, x, y + h - 1, w, 1, COL_LINE);
    fill_rect(fb, stride_px, x, y, 1, h, COL_LINE);
    fill_rect(fb, stride_px, x + w - 1, y, 1, h, COL_LINE);
  }
  int scale = 3;
  char lbl[128];
  ota_ui_sanitize_ascii(label, lbl, sizeof(lbl));
  int max_tw = w - 24;
  int tw = text_width(lbl, scale);
  while (scale > 2 && tw > max_tw) {
    scale--;
    tw = text_width(lbl, scale);
  }
  int tx = x + (w - tw) / 2;
  int ty = y + (h - 8 * scale) / 2;
  draw_text(fb, stride_px, tx, ty, lbl, ink, scale);
}

static void draw_chrome(u32 *fb, u32 stride_px) {
  fill_rect(fb, stride_px, 0, 0, FB_W, FB_H, COL_BG);
  draw_rail(fb, stride_px);
  int logo_max = 320;
  int logo_h = g_logo ? (g_logo_h * logo_max / g_logo_w) : 40;
  if (logo_h > 90) logo_h = 90;
  int logo_y = 48;
  if (g_logo) {
    int logo_w = logo_max;
    if (g_logo_w * logo_h / g_logo_h < logo_max) logo_w = g_logo_w * logo_h / g_logo_h;
    blit_logo(fb, stride_px, (FB_W - logo_w) / 2, logo_y, logo_max);
  } else {
    draw_text_centered(fb, stride_px, logo_y + 16, "gen2recomp", COL_INK, 4);
  }
}

static void present(void (*paint)(u32 *fb, u32 stride_px, void *ctx), void *ctx) {
  if (!ui_ensure()) return;
  u32 stride = 0;
  u32 *fb = (u32 *)framebufferBegin(&g_fb, &stride);
  u32 stride_px = stride / sizeof(u32);
  paint(fb, stride_px, ctx);
  framebufferEnd(&g_fb);
}

typedef struct {
  const char *installed;
  const char *latest;
  int focus; /* 0 = Update, 1 = Play */
} prompt_ctx_t;

static void paint_prompt(u32 *fb, u32 stride_px, void *ctx) {
  prompt_ctx_t *p = (prompt_ctx_t *)ctx;
  draw_chrome(fb, stride_px);

  int y = TITLE_Y - 20;
  draw_text_centered(fb, stride_px, y, "Update available", COL_INK, 3);
  y += LINE_TITLE;

  char line[96];
  snprintf(line, sizeof(line), "v%s to v%s", p->installed ? p->installed : "?",
           p->latest ? p->latest : "?");
  draw_text_centered(fb, stride_px, y, line, COL_YELLOW, 3);
  y += LINE_TITLE + 8;

  draw_text_centered(fb, stride_px, y, "Your saves stay on this console.", COL_MUTED, 2);
  y += LINE_BODY + 28;

  int bw = 600;
  int bh = 64;
  int bx = (FB_W - bw) / 2;
  draw_button(fb, stride_px, bx, y, bw, bh, COL_YELLOW, COL_INVERSE, "(A) Update", p->focus == 0);
  y += bh + 24;
  draw_button(fb, stride_px, bx, y, bw, bh, COL_INK, COL_INVERSE, "(B) Play without update",
              p->focus == 1);
}

int ota_ui_prompt_update(const char *installed, const char *latest) {
  if (!ui_ensure()) return 0;
  prompt_ctx_t ctx = {installed, latest, 0};
  while (appletMainLoop()) {
    present(paint_prompt, &ctx);
    padUpdate(&g_pad);
    u64 k = padGetButtonsDown(&g_pad);
    if (k & HidNpadButton_A) {
      int do_update = (ctx.focus == 0);
      if (!do_update) ota_ui_shutdown();
      return do_update;
    }
    if (k & HidNpadButton_B) {
      ota_ui_shutdown();
      return 0;
    }
    if (k & (HidNpadButton_Up | HidNpadButton_Down | HidNpadButton_Left | HidNpadButton_Right)) {
      ctx.focus = 1 - ctx.focus;
    }
    svcSleepThread(16000000ULL);
  }
  ota_ui_shutdown();
  return 0;
}

typedef struct {
  const char *title;
  const char *detail;
  float progress;
  int show_bar;
} status_ctx_t;

static void paint_progress_bar(u32 *fb, u32 stride_px, int y, float t) {
  int bw = 520;
  int bh = 18;
  int bx = (FB_W - bw) / 2;
  if (t < 0.f) t = 0.f;
  if (t > 1.f) t = 1.f;
  fill_rect(fb, stride_px, bx, y, bw, bh, COL_RAISED);
  fill_rect(fb, stride_px, bx, y, bw, 1, COL_LINE);
  fill_rect(fb, stride_px, bx, y + bh - 1, bw, 1, COL_LINE);
  fill_rect(fb, stride_px, bx, y, 1, bh, COL_LINE);
  fill_rect(fb, stride_px, bx + bw - 1, y, 1, bh, COL_LINE);
  int fw = (int)(bw * t);
  if (fw > 0) fill_rect(fb, stride_px, bx, y, fw, bh, COL_GREEN);
}

static void paint_status(u32 *fb, u32 stride_px, void *ctx) {
  status_ctx_t *s = (status_ctx_t *)ctx;
  draw_chrome(fb, stride_px);
  int y = TITLE_Y;
  draw_text_centered(fb, stride_px, y, s->title ? s->title : "", COL_INK, 3);
  y += LINE_TITLE;
  if (s->detail && s->detail[0]) {
    y = draw_text_wrapped_centered(fb, stride_px, y, s->detail, COL_DETAIL, 2, WRAP_MAX_PX);
    y += LINE_SMALL;
  }
  if (s->show_bar) paint_progress_bar(fb, stride_px, y, s->progress);
}

void ota_ui_show_status(const char *title, const char *detail) {
  status_ctx_t s = {title, detail, 0.f, 0};
  present(paint_status, &s);
}

void ota_ui_show_progress(const char *title, const char *detail, float progress01) {
  status_ctx_t s = {title, detail, progress01, 1};
  present(paint_status, &s);
}

typedef struct {
  const char *title;
  const char *line1;
  const char *line2;
  const char *line3;
} alert_ctx_t;

static void paint_alert(u32 *fb, u32 stride_px, void *ctx) {
  alert_ctx_t *a = (alert_ctx_t *)ctx;
  draw_chrome(fb, stride_px);
  int y = TITLE_Y;
  draw_text_centered(fb, stride_px, y, a->title ? a->title : "", COL_YELLOW, 3);
  y += LINE_TITLE;
  if (a->line1 && a->line1[0])
    y = draw_text_wrapped_centered(fb, stride_px, y, a->line1, COL_DETAIL, 2, WRAP_MAX_PX);
  y += LINE_SMALL;
  if (a->line2 && a->line2[0])
    y = draw_text_wrapped_centered(fb, stride_px, y, a->line2, COL_MUTED, 2, WRAP_MAX_PX);
  y += LINE_SMALL;
  if (a->line3 && a->line3[0])
    y = draw_text_wrapped_centered(fb, stride_px, y, a->line3, COL_MUTED, 2, WRAP_MAX_PX);
  y += LINE_BODY + 16;
  int bw = 360;
  int bh = 56;
  draw_button(fb, stride_px, (FB_W - bw) / 2, y, bw, bh, COL_INK, COL_INVERSE, "(B) Continue", 1);
}

void ota_ui_alert(const char *title, const char *line1, const char *line2) {
  if (!ui_ensure()) return;
  alert_ctx_t a = {title, line1, line2, NULL};
  while (appletMainLoop()) {
    present(paint_alert, &a);
    padUpdate(&g_pad);
    if (padGetButtonsDown(&g_pad) & HidNpadButton_B) break;
    svcSleepThread(16000000ULL);
  }
  ota_ui_shutdown();
}

void ota_ui_alert_error(const char *title, const char *friendly, const char *technical,
                        const char *installed_version) {
  if (!ui_ensure()) return;
  char footer[96];
  snprintf(footer, sizeof(footer), "Playing installed version (v%s).",
           installed_version && installed_version[0] ? installed_version : "?");
  char tech[256];
  if (technical && technical[0]) {
    ota_ui_sanitize_ascii(technical, tech, sizeof(tech));
    if (strlen(tech) > 80) tech[80] = '\0';
  } else {
    tech[0] = '\0';
  }
  alert_ctx_t a = {title, friendly, tech[0] ? tech : NULL, footer};
  while (appletMainLoop()) {
    present(paint_alert, &a);
    padUpdate(&g_pad);
    if (padGetButtonsDown(&g_pad) & HidNpadButton_B) break;
    svcSleepThread(16000000ULL);
  }
  ota_ui_shutdown();
}

static void paint_missing(u32 *fb, u32 stride_px, void *ctx) {
  (void)ctx;
  draw_chrome(fb, stride_px);
  int y = TITLE_Y - 10;
  draw_text_centered(fb, stride_px, y, "Game files missing", COL_YELLOW, 3);
  y += LINE_TITLE;
  y = draw_text_wrapped_centered(fb, stride_px, y,
                                 "Copy the Switch zip onto your microSD, then open gen2recomp again.",
                                 COL_DETAIL, 2, WRAP_MAX_PX);
  y += LINE_BODY + 16;
  int bw = 320;
  int bh = 56;
  draw_button(fb, stride_px, (FB_W - bw) / 2, y, bw, bh, COL_INK, COL_INVERSE, "(+) Exit", 1);
}

void ota_ui_missing_game(void) {
  if (!ui_ensure()) return;
  while (appletMainLoop()) {
    present(paint_missing, NULL);
    padUpdate(&g_pad);
    if (padGetButtonsDown(&g_pad) & HidNpadButton_Plus) break;
    svcSleepThread(16000000ULL);
  }
  ota_ui_shutdown();
}

#else /* host stub */

int ota_ui_prompt_update(const char *installed, const char *latest) {
  fprintf(stderr, "[ota_ui] update %s -> %s (host stub: skip)\n", installed ? installed : "?",
          latest ? latest : "?");
  return 0;
}
void ota_ui_show_status(const char *title, const char *detail) {
  fprintf(stderr, "[ota_ui] %s %s\n", title ? title : "", detail ? detail : "");
}
void ota_ui_show_progress(const char *title, const char *detail, float progress01) {
  fprintf(stderr, "[ota_ui] %s %s (%.0f%%)\n", title ? title : "", detail ? detail : "",
          progress01 * 100.f);
}
void ota_ui_alert(const char *title, const char *line1, const char *line2) {
  fprintf(stderr, "[ota_ui] alert: %s / %s / %s\n", title ? title : "", line1 ? line1 : "",
          line2 ? line2 : "");
}
void ota_ui_alert_error(const char *title, const char *friendly, const char *technical,
                        const char *installed_version) {
  fprintf(stderr, "[ota_ui] error: %s / %s / %s / v%s\n", title ? title : "",
          friendly ? friendly : "", technical ? technical : "",
          installed_version ? installed_version : "?");
}
void ota_ui_missing_game(void) { fprintf(stderr, "[ota_ui] missing game\n"); }
void ota_ui_shutdown(void) {}

#endif
