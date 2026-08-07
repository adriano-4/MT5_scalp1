//+------------------------------------------------------------------+
//|                                                   TrendFilter.mqh  |
//|  Higher-timeframe bias. Uses fast/slow EMA regime + price        |
//|  location rather than a second full swing-structure engine -     |
//|  cheap, robust, and exactly what a top-down bias gate needs.     |
//+------------------------------------------------------------------+
#ifndef __TRENDFILTER_MQH__
#define __TRENDFILTER_MQH__

#include "Globals.mqh"
#include "Indicators.mqh"

//--- Recomputes g_htfBias. Call once per new HTF bar. -----------------------
void UpdateTrendFilter(const string symbol)
  {
   double emaFast=GetEMAFast(1);
   double emaSlow=GetEMASlow(1);
   double closeHTF=iClose(symbol,InpHTF,1);

   if(emaFast<0 || emaSlow<0) { g_htfBias=BIAS_NONE; return; }

   if(emaFast>emaSlow && closeHTF>emaFast)
      g_htfBias=BIAS_BULLISH;
   else if(emaFast<emaSlow && closeHTF<emaFast)
      g_htfBias=BIAS_BEARISH;
   else
      g_htfBias=BIAS_NONE; // EMAs tangled / price between them = no clean bias, sit out
  }

#endif // __TRENDFILTER_MQH__