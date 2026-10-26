/* Authored input shim. The checked, original GetWhoStrikesFirst is included
 * from the pinned decompilation checkout by check.py, never copied here. */
#include <stdint.h>
#include <stdio.h>
#include <limits.h>
#include <string.h>
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef u8 bool8;
#define STAT_SPEED 0
#define ABILITY_SWIFT_SWIM 33
#define ABILITY_CHLOROPHYLL 34
#define B_WEATHER_RAIN 7
#define B_WEATHER_SUN 0x60
#define ITEM_ENIGMA_BERRY 175
#define HOLD_EFFECT_MACHO_BRACE 24
#define HOLD_EFFECT_QUICK_CLAW 26
#define STATUS1_PARALYSIS 64
#define BATTLE_TYPE_LINK 1
#define BATTLE_TYPE_RECORDED_LINK 2
#define BATTLE_TYPE_FRONTIER 4
#define B_SIDE_PLAYER 0
#define FLAG_BADGE03_GET 1
#define B_ACTION_USE_MOVE 0
#define MOVE_NONE 0
#define MOVE_STRUGGLE 5
static struct { u16 speed, item, hp, moves[4]; u8 ability, statStages[8]; u32 status1; } gBattleMons[4];
static struct { u8 holdEffect, holdEffectParam; } gEnigmaBerries[4], items[256];
static struct { int8_t priority; } gBattleMoves[6];
static struct { u8 noValidMoves; } gProtectStructs[4];
static struct { u8 chosenMovePositions[4]; } battleStruct, *gBattleStruct = &battleStruct;
static u8 gChosenActionByBattler[4], gBattlersCount, badge;
static u16 gBattleWeather, gRandomTurnNumber, tie;
static u32 gBattleTypeFlags, oracleSpeed1, oracleSpeed2;
static unsigned draws;
static const u8 gStatStageRatios[13][2] = {
  {10,40},{10,35},{10,30},{10,25},{10,20},{10,15},{10,10},
  {15,10},{20,10},{25,10},{30,10},{35,10},{40,10}
};
static u8 weatherActive(void) {
  for (u8 i=0; i<gBattlersCount; i++)
    if (gBattleMons[i].hp && (gBattleMons[i].ability==13 || gBattleMons[i].ability==76)) return 0;
  return 1;
}
#define WEATHER_HAS_EFFECT weatherActive()
static u8 ItemId_GetHoldEffect(u16 item) { return items[item].holdEffect; }
static u8 ItemId_GetHoldEffectParam(u16 item) { return items[item].holdEffectParam; }
#define GetItemHoldEffect ItemId_GetHoldEffect
#define GetItemHoldEffectParam ItemId_GetHoldEffectParam
static u8 FlagGet(unsigned flag) { (void)flag; return badge; }
static u8 GetBattlerSide(u8 id) { return id%2; }
static u16 Random(void) { draws++; return tie; }
#include "native-function.c"
int main(void) {
  long long in[52];
  while (scanf("%lld", &in[0])==1) {
    for (unsigned i=1; i<52; i++) if (scanf("%lld", &in[i])!=1) return 2;
    memset(gBattleMons,0,sizeof gBattleMons);
    memset(items,0,sizeof items);
    gBattlersCount=in[2]; gBattleWeather=in[3]; gBattleTypeFlags=in[4];
    badge=in[5]; gRandomTurnNumber=in[6]; tie=in[7];
    for (unsigned i=0; i<4; i++) {
      long long *a=in+8+11*i;
      gBattleMons[i].speed=a[0]; gBattleMons[i].statStages[0]=a[1];
      gBattleMons[i].ability=a[2]; gBattleMons[i].status1=a[3];
      gBattleMons[i].item=a[4]; items[a[4]].holdEffect=a[5]; items[a[4]].holdEffectParam=a[6];
      gEnigmaBerries[i].holdEffect=a[7]; gEnigmaBerries[i].holdEffectParam=a[8];
      gBattleMons[i].hp=a[9]; gBattleMons[i].moves[0]=i+1; gBattleMoves[i+1].priority=a[10];
    }
    draws=0;
    u8 result=GetWhoStrikesFirst(in[0],in[1],1);
    printf("%u %u %u %u ",result,oracleSpeed1,oracleSpeed2,draws);
    draws=0;
    result=GetWhoStrikesFirst(in[0],in[1],0);
    printf("%u %u ",result,draws);
    u8 order[4]={0,1,2,3};
    draws=0;
    for (unsigned i=0; i+1<gBattlersCount; i++)
      for (unsigned j=i+1; j<gBattlersCount; j++)
        if (GetWhoStrikesFirst(order[i],order[j],0)) { u8 t=order[i]; order[i]=order[j]; order[j]=t; }
    printf("%u ",draws);
    for (unsigned i=0; i<gBattlersCount; i++) printf("%u ",order[i]);
    puts("");
  }
  return 0;
}
