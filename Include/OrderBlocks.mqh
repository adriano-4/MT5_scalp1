//+------------------------------------------------------------------+
//|                                                  OrderBlocks.mqh  |
//|  When a BOS/CHOCH fires, walks back to the last opposite-colour  |
//|  candle before the impulsive move - that candle's range is the   |
//|  order block (the zone we want price to retrace into).           |
//+------------------------------------------------------------------+
#ifndef __ORDERBLOCKS_MQH__
#define __ORDERBLOCKS_MQH__

#include "Globals.mqh"

#define OB_LOOKBACK_MAX 15

//--- Call right after DetectBOS()/DetectCHOCH() returns a non-NONE event ----
void RegisterOrderBlock(const string symbol,ENUM_TIMEFRAMES structTF,ENUM_STRUCT_EVENT ev)
  {
   bool bullish;
   if(ev==STRUCT_EVENT_BOS_BULL || ev==STRUCT_EVENT_CHOCH_BULL) bullish=true;
   else if(ev==STRUCT_EVENT_BOS_BEAR || ev==STRUCT_EVENT_CHOCH_BEAR) bullish=false;
   else return;

   // Walk back from the breakout bar (shift 1) to find the last opposite candle
   for(int shift=1; shift<=OB_LOOKBACK_MAX; shift++)
     {
      double o=iOpen(symbol,structTF,shift);
      double c=iClose(symbol,structTF,shift);
      bool bearCandle = c<o;
      bool bullCandle = c>o;

      if(bullish && bearCandle)
        {
         OrderBlockZone ob;
         ob.top    = iHigh(symbol,structTF,shift);
         ob.bottom = iLow(symbol,structTF,shift);
         ob.time   = iTime(symbol,structTF,shift);
         ob.bullish= true;
         ob.mitigated=false;
         ob.traded=false;
         ob.confluenceTag=0;
         int sz=ArraySize(g_orderBlocks);
         ArrayResize(g_orderBlocks,sz+1);
         g_orderBlocks[sz]=ob;
         return;
        }
      if(!bullish && bullCandle)
        {
         OrderBlockZone ob;
         ob.top    = iHigh(symbol,structTF,shift);
         ob.bottom = iLow(symbol,structTF,shift);
         ob.time   = iTime(symbol,structTF,shift);
         ob.bullish= false;
         ob.mitigated=false;
         ob.traded=false;
         ob.confluenceTag=0;
         int sz=ArraySize(g_orderBlocks);
         ArrayResize(g_orderBlocks,sz+1);
         g_orderBlocks[sz]=ob;
         return;
        }
     }
  }

//--- Invalidate OBs that price has closed straight through, and drop old ones --
void UpdateOrderBlockState(const string symbol,ENUM_TIMEFRAMES structTF,int maxAgeBars)
  {
   double lastClose=iClose(symbol,structTF,1);
   datetime ageCutoff=iTime(symbol,structTF,MathMin(maxAgeBars,Bars(symbol,structTF)-1));

   for(int i=ArraySize(g_orderBlocks)-1;i>=0;i--)
     {
      if(g_orderBlocks[i].bullish && lastClose<g_orderBlocks[i].bottom)
         g_orderBlocks[i].mitigated=true;
      if(!g_orderBlocks[i].bullish && lastClose>g_orderBlocks[i].top)
         g_orderBlocks[i].mitigated=true;
      if(g_orderBlocks[i].time<ageCutoff)
         g_orderBlocks[i].mitigated=true;
     }
  }

//--- Is "price" sitting inside a still-valid order block? Returns the zone ---
bool GetActiveOB(double price,bool wantBullish,OrderBlockZone &out)
  {
   // most recent first
   for(int i=ArraySize(g_orderBlocks)-1;i>=0;i--)
     {
      if(g_orderBlocks[i].mitigated) continue;
      if(g_orderBlocks[i].bullish!=wantBullish) continue;
      if(price<=g_orderBlocks[i].top && price>=g_orderBlocks[i].bottom)
        {
         out=g_orderBlocks[i];
         return true;
        }
     }
   return false;
  }

//--- Flag a zone as traded so EntryEngine won't fire on it again -----------
void MarkOBTraded(datetime t,double top,double bottom)
  {
   for(int i=0;i<ArraySize(g_orderBlocks);i++)
      if(g_orderBlocks[i].time==t && g_orderBlocks[i].top==top && g_orderBlocks[i].bottom==bottom)
        { g_orderBlocks[i].traded=true; return; }
  }

#endif // __ORDERBLOCKS_MQH__