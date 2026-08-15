#ifndef GEN1_OTA_UI_H
#define GEN1_OTA_UI_H

#ifdef __cplusplus
extern "C" {
#endif

/* Framebuffer UI matching the in-game launcher look (black + RGB rail +
 * flat semantic buttons). Silent by default — only call when user-facing. */

/* Returns 1 = update, 0 = skip / play installed. */
int ota_ui_prompt_update(const char *installed, const char *latest);

/* Status screen (download / install). Redraws each call. */
void ota_ui_show_status(const char *title, const char *detail);

/* Progress 0..1; detail optional. */
void ota_ui_show_progress(const char *title, const char *detail, float progress01);

/* Error / info + wait for B. */
void ota_ui_alert(const char *title, const char *line1, const char *line2);

/* User-friendly error with optional technical detail and installed-version footer. */
void ota_ui_alert_error(const char *title, const char *friendly, const char *technical,
                        const char *installed_version);

/* Missing game install screen; wait for +. */
void ota_ui_missing_game(void);

/* Tear down framebuffer if active. Safe to call when UI never opened. */
void ota_ui_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif
