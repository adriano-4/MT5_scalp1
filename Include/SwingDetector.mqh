//+------------------------------------------------------------------+
//|                                                SwingDetector.mqh  |
//|  Pure geometry: finds confirmed fractal swing highs/lows on a    |
//|  given timeframe. Knows nothing about "trend" or "structure" -   |
//|  MarketStructure.mqh interprets the output.                      |
//+------------------------------------------------------------------+
#ifndef __SWINGDETECTOR_MQH__
#define __SWINGDETECTOR_MQH__

#include "Globals.mqh"

#define SWING_SCAN_BARS 300   // how far back we look each recompute

//--- Is the bar at "shift" a swing high, given N bars either side? ------
bool IsFractalHigh(const string symbol,ENUM_TIMEFRAMES tf,int shift,int n)
  {
   double mid=iHigh(symbol,tf,shift);
   for(int i=1;i<=n;i++)
     {
      if(iHigh(symbol,tf,shift-i)>=mid) return false; // newer side
      if(iHigh(symbol,tf,shift+i)>=mid) return false; // older side
     }
   return true;
  }

bool IsFractalLow(const string symbol,ENUM_TIMEFRAMES tf,int shift,int n)
  {
   double mid=iLow(symbol,tf,shift);
   for(int i=1;i<=n;i++)
     {
      if(iLow(symbol,tf,shift-i)<=mid) return false;
      if(iLow(symbol,tf,shift+i)<=mid) return false;
     }
   return true;
  }

//--- Rebuilds g_swingsLTF[] with the most recent confirmed swings ----------
//--- (oldest first, newest last). Called once per new structure-TF bar. ---
void UpdateSwings(const string symbol,ENUM_TIMEFRAMES tf,int n,int keepCount)
  {
   SwingPoint tmp[];
   ArrayResize(tmp,0);

   int maxShift = SWING_SCAN_BARS;
   int available = Bars(symbol,tf);
   if(available < maxShift+n+2) maxShift = available-n-2;
   if(maxShift < n+2) return; // not enough history yet

   // Scan from the oldest end of the window to the newest confirmable bar
   // (bars newer than "shift = n" are not confirmable yet).
   for(int shift=maxShift; shift>=n; shift--)
     {
      if(IsFractalHigh(symbol,tf,shift,n))
        {
         SwingPoint sp;
         sp.time=iTime(symbol,tf,shift);
         sp.price=iHigh(symbol,tf,shift);
         sp.isHigh=true;
         sp.broken=false;
         int sz=ArraySize(tmp);
         ArrayResize(tmp,sz+1);
         tmp[sz]=sp;
        }
      else if(IsFractalLow(symbol,tf,shift,n))
        {
         SwingPoint sp;
         sp.time=iTime(symbol,tf,shift);
         sp.price=iLow(symbol,tf,shift);
         sp.isHigh=false;
         sp.broken=false;
         int sz=ArraySize(tmp);
         ArrayResize(tmp,sz+1);
         tmp[sz]=sp;
        }
     }

   // Keep only the most recent "keepCount" swings
   int total=ArraySize(tmp);
   int start=MathMax(0,total-keepCount);
   int newSize=total-start;
   ArrayResize(g_swingsLTF,newSize);
   for(int i=0;i<newSize;i++)
      g_swingsLTF[i]=tmp[start+i];
  }

//--- Convenience getters -----------------------------------------------------
bool GetLastSwingHigh(SwingPoint &out)
  {
   for(int i=ArraySize(g_swingsLTF)-1;i>=0;i--)
      if(g_swingsLTF[i].isHigh){ out=g_swingsLTF[i]; return true; }
   return false;
  }
bool GetLastSwingLow(SwingPoint &out)
  {
   for(int i=ArraySize(g_swingsLTF)-1;i>=0;i--)
      if(!g_swingsLTF[i].isHigh){ out=g_swingsLTF[i]; return true; }
   return false;
  }

#endif // __SWINGDETECTOR_MQH__