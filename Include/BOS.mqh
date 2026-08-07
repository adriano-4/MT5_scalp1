//+------------------------------------------------------------------+
//|                                                          BOS.mqh  |
//|  Break of Structure: a CLOSE beyond the last swing high/low in   |
//|  the direction of the prevailing structure bias = continuation.  |
//+------------------------------------------------------------------+
#ifndef __BOS_MQH__
#define __BOS_MQH__

#include "Globals.mqh"
#include "MarketStructure.mqh"

//--- Returns the event detected on the most recently CLOSED bar (shift 1) ---
ENUM_STRUCT_EVENT DetectBOS(const string symbol,ENUM_TIMEFRAMES structTF)
  {
   double lastClose = iClose(symbol,structTF,1);

   SwingPoint highs[],lows[];
   int nh=GetLastNHighs(highs,1);
   int nl=GetLastNLows(lows,1);
   if(nh<1 || nl<1) return STRUCT_EVENT_NONE;

   if(g_structBias==BIAS_BULLISH && !highs[0].broken && lastClose>highs[0].price)
     {
      // mark it broken in the shared array so we don't refire on the next bar
      for(int i=ArraySize(g_swingsLTF)-1;i>=0;i--)
         if(g_swingsLTF[i].isHigh && g_swingsLTF[i].time==highs[0].time)
           { g_swingsLTF[i].broken=true; break; }
      g_lastEvent=STRUCT_EVENT_BOS_BULL;
      g_lastEventTime=TimeCurrent();
      return STRUCT_EVENT_BOS_BULL;
     }

   if(g_structBias==BIAS_BEARISH && !lows[0].broken && lastClose<lows[0].price)
     {
      for(int i=ArraySize(g_swingsLTF)-1;i>=0;i--)
         if(!g_swingsLTF[i].isHigh && g_swingsLTF[i].time==lows[0].time)
           { g_swingsLTF[i].broken=true; break; }
      g_lastEvent=STRUCT_EVENT_BOS_BEAR;
      g_lastEventTime=TimeCurrent();
      return STRUCT_EVENT_BOS_BEAR;
     }

   return STRUCT_EVENT_NONE;
  }

#endif // __BOS_MQH__