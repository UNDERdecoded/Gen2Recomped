/*
 * Tiny one-shot helper: swap a staged launcher NRO into place, then load the game.
 * The main OTA launcher chainloads here because a running NRO cannot replace itself
 * on sdmc/FAT.
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#if defined(__SWITCH__)
#include <switch.h>
#endif

#define INSTALL_DIR "sdmc:/switch/gen2recomp"
#define STAGED INSTALL_DIR "/gen2recomp.nro.staged"
#define LAUNCHER INSTALL_DIR "/gen2recomp.nro"
#define GAME INSTALL_DIR "/Gen2Recomped-game.nro"

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;

#if defined(__SWITCH__)
  remove(LAUNCHER);
  if (rename(STAGED, LAUNCHER) != 0) {
    return 1;
  }
  Result rc = envSetNextLoad(GAME, GAME);
  if (R_FAILED(rc)) return 1;
  return 0;
#else
  fprintf(stderr, "ota-bootstrap: host stub (would rename %s -> %s, load %s)\n", STAGED, LAUNCHER,
          GAME);
  return 0;
#endif
}
