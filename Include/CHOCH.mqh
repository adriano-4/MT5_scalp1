//+------------------------------------------------------------------+
//|                                                        CHOCH.mqh  |
//|  Change of Character: the FIRST close against the prevailing     |
//|  structure bias. This is the early warning of a reversal and,    |
//|  combined with a liquidity sweep, is the core "sniper" trigger.  |
//+------------------------------------------------------------------+
#ifndef __CHOCH_MQH__
#define __CHOCH_MQH__

#include "Globals.mqh"
#include "MarketStructure.mqh"

ENUM_STRUCT_EVENT DetectCHOCH(const string symbol,ENUM_TIMEFRAMES structTF)
  {
   double lastClose = iClose(symbol,structTF,1);

   SwingPoint highs[],lows[];
   int nh=GetLastNHighs(highs,1);
   int nl=GetLastNLows(lows,1);
   if(nh<1 || nl<1) return STRUCT_EVENT_NONE;

   // Bias was bullish (making HH/HL) but price closes below the last swing low
   // -> character has changed, a bearish reversal may be starting.
   if(g_structBias==BIAS_BULLISH && !lows[0].broken && lastClose<lows[0].price)
     {
      for(int i=ArraySize(g_swingsLTF)-1;i>=0;i--)
         if(!g_swingsLTF[i].isHigh && g_swingsLTF[i].time==lows[0].time)
           { g_swingsLTF[i].broken=true; break; }
      g_structBias=BIAS_BEARISH;   // structure officially flips
      g_lastEvent=STRUCT_EVENT_CHOCH_BEAR;
      g_lastEventTime=TimeCurrent();
      return STRUCT_EVENT_CHOCH_BEAR;
     }

   // Symmetric bullish CHOCH
   if(g_structBias==BIAS_BEARISH && !highs[0].broken && lastClose>highs[0].price)
     {
      for(int i=ArraySize(g_swingsLTF)-1;i>=0;i--)
         if(g_swingsLTF[i].isHigh && g_swingsLTF[i].time==highs[0].time)
           { g_swingsLTF[i].broken=true; break; }
      g_structBias=BIAS_BULLISH;
      g_lastEvent=STRUCT_EVENT_CHOCH_BULL;
      g_lastEventTime=TimeCurrent();
      return STRUCT_EVENT_CHOCH_BULL;
     }

   return STRUCT_EVENT_NONE;
  }

#endif // __CHOCH_MQH__