//+------------------------------------------------------------------+
//|                                              MarketStructure.mqh  |
//|  Turns the raw swing list from SwingDetector.mqh into a          |
//|  structure bias: sequence of Higher-Highs/Higher-Lows = bullish, |
//|  Lower-Highs/Lower-Lows = bearish, anything else = ranging.      |
//+------------------------------------------------------------------+
#ifndef __MARKETSTRUCTURE_MQH__
#define __MARKETSTRUCTURE_MQH__

#include "Globals.mqh"
#include "SwingDetector.mqh"

//--- Pull the last two swing highs / lows out of g_swingsLTF[] --------------
int GetLastNHighs(SwingPoint &out[],int n)
  {
   int found=0;
   ArrayResize(out,n);
   for(int i=ArraySize(g_swingsLTF)-1;i>=0 && found<n;i--)
      if(g_swingsLTF[i].isHigh) out[found++]=g_swingsLTF[i];
   ArrayResize(out,found);
   return found;
  }
int GetLastNLows(SwingPoint &out[],int n)
  {
   int found=0;
   ArrayResize(out,n);
   for(int i=ArraySize(g_swingsLTF)-1;i>=0 && found<n;i--)
      if(!g_swingsLTF[i].isHigh) out[found++]=g_swingsLTF[i];
   ArrayResize(out,found);
   return found;
  }

//--- Recompute g_structBias from the current swing list ---------------------
void UpdateMarketStructure(const string symbol,ENUM_TIMEFRAMES tf,int swingN,int keepCount)
  {
   UpdateSwings(symbol,tf,swingN,keepCount);

   SwingPoint highs[],lows[];
   int nh=GetLastNHighs(highs,2);
   int nl=GetLastNLows(lows,2);

   if(nh<2 || nl<2) { g_structBias=BIAS_NONE; return; } // not enough data yet

   // highs[0]/lows[0] = most recent, highs[1]/lows[1] = previous
   bool higherHigh = highs[0].price > highs[1].price;
   bool higherLow  = lows[0].price  > lows[1].price;
   bool lowerHigh  = highs[0].price < highs[1].price;
   bool lowerLow   = lows[0].price  < lows[1].price;

   if(higherHigh && higherLow)      g_structBias = BIAS_BULLISH;
   else if(lowerHigh && lowerLow)   g_structBias = BIAS_BEARISH;
   // else: mixed signals -> keep previous g_structBias (avoids flip-flopping on noise)
  }

#endif // __MARKETSTRUCTURE_MQH__