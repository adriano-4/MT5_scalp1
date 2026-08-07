//+------------------------------------------------------------------+
//|                                                          FVG.mqh  |
//|  Classic 3-candle Fair Value Gap: an imbalance left behind by an |
//|  impulsive move. Overlap with an order block = highest-quality   |
//|  "optimal trade entry" zone.                                     |
//+------------------------------------------------------------------+
#ifndef __FVG_MQH__
#define __FVG_MQH__

#include "Globals.mqh"

//--- Call once per new structure-TF bar ------------------------------------
void DetectFVG(const string symbol,ENUM_TIMEFRAMES tf)
  {
   // candle1 = shift 3 (oldest), candle2 = shift 2 (impulse), candle3 = shift 1 (newest closed)
   double c1High=iHigh(symbol,tf,3), c1Low=iLow(symbol,tf,3);
   double c3High=iHigh(symbol,tf,1), c3Low=iLow(symbol,tf,1);
   datetime t=iTime(symbol,tf,2);

   // Avoid re-adding the same gap
   for(int i=0;i<ArraySize(g_fvgZones);i++)
      if(g_fvgZones[i].time==t) return;

   if(c1High<c3Low) // bullish imbalance
     {
      FVGZone z;
      z.top=c3Low; z.bottom=c1High; z.time=t; z.bullish=true; z.filled=false; z.traded=false;
      int sz=ArraySize(g_fvgZones);
      ArrayResize(g_fvgZones,sz+1);
      g_fvgZones[sz]=z;
     }
   else if(c1Low>c3High) // bearish imbalance
     {
      FVGZone z;
      z.top=c1Low; z.bottom=c3High; z.time=t; z.bullish=false; z.filled=false; z.traded=false;
      int sz=ArraySize(g_fvgZones);
      ArrayResize(g_fvgZones,sz+1);
      g_fvgZones[sz]=z;
     }
  }

//--- Mark gaps that have since been fully traded through as filled ----------
void UpdateFVGState(const string symbol,ENUM_TIMEFRAMES tf,int maxAgeBars)
  {
   double lo=iLow(symbol,tf,1);
   double hi=iHigh(symbol,tf,1);
   datetime ageCutoff=iTime(symbol,tf,MathMin(maxAgeBars,Bars(symbol,tf)-1));

   for(int i=0;i<ArraySize(g_fvgZones);i++)
     {
      if(g_fvgZones[i].filled) continue;
      if(g_fvgZones[i].bullish && lo<=g_fvgZones[i].bottom) g_fvgZones[i].filled=true;
      if(!g_fvgZones[i].bullish && hi>=g_fvgZones[i].top)   g_fvgZones[i].filled=true;
      if(g_fvgZones[i].time<ageCutoff) g_fvgZones[i].filled=true;
     }
  }

//--- Is "price" inside a still-open FVG of the requested direction? --------
bool GetActiveFVG(double price,bool wantBullish,FVGZone &out)
  {
   for(int i=ArraySize(g_fvgZones)-1;i>=0;i--)
     {
      if(g_fvgZones[i].filled) continue;
      if(g_fvgZones[i].bullish!=wantBullish) continue;
      if(price<=g_fvgZones[i].top && price>=g_fvgZones[i].bottom)
        {
         out=g_fvgZones[i];
         return true;
        }
     }
   return false;
  }

//--- Flag a zone as traded so EntryEngine won't fire on it again -----------
void MarkFVGTraded(datetime t,double top,double bottom)
  {
   for(int i=0;i<ArraySize(g_fvgZones);i++)
      if(g_fvgZones[i].time==t && g_fvgZones[i].top==top && g_fvgZones[i].bottom==bottom)
        { g_fvgZones[i].traded=true; return; }
  }

#endif // __FVG_MQH__