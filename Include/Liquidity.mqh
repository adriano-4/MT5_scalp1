//+------------------------------------------------------------------+
//|                                                    Liquidity.mqh  |
//|  Finds resting liquidity (equal highs/lows, prior day/session    |
//|  extremes) and detects when it gets swept (wick through + close  |
//|  back inside) - the "stop hunt" that precedes a sniper entry.    |
//+------------------------------------------------------------------+
#ifndef __LIQUIDITY_MQH__
#define __LIQUIDITY_MQH__

#include "Globals.mqh"
#include "Utils.mqh"

//--- Add a pool only if nothing similar already exists at that price -------
void AddLiquidityPool(const string symbol,double price,datetime t,bool isHigh,double tolPoints)
  {
   for(int i=0;i<ArraySize(g_liquidityPools);i++)
     {
      if(g_liquidityPools[i].isHigh==isHigh && IsNear(symbol,price,g_liquidityPools[i].price,tolPoints))
         return; // duplicate pool, skip
     }
   int sz=ArraySize(g_liquidityPools);
   ArrayResize(g_liquidityPools,sz+1);
   g_liquidityPools[sz].price=price;
   g_liquidityPools[sz].time=t;
   g_liquidityPools[sz].isHigh=isHigh;
   g_liquidityPools[sz].swept=false;
   g_liquidityPools[sz].sweptTime=0;
  }

//--- Rebuild the pool list: equal highs/lows + optional day/session extremes --
void UpdateLiquidityPools(const string symbol,ENUM_TIMEFRAMES tf,int lookback,double tolPoints,
                           bool usePrevDay,bool usePrevSession)
  {
   // Keep already-swept pools out of the rebuild noise, but preserve them for the log/dashboard
   LiquidityPool kept[];
   int keptN=0;
   for(int i=0;i<ArraySize(g_liquidityPools);i++)
      if(g_liquidityPools[i].swept) keptN++;
   ArrayResize(kept,keptN);
   int k=0;
   for(int i=0;i<ArraySize(g_liquidityPools);i++)
      if(g_liquidityPools[i].swept) kept[k++]=g_liquidityPools[i];

   ArrayResize(g_liquidityPools,keptN);
   for(int i=0;i<keptN;i++) g_liquidityPools[i]=kept[i];

   int bars=MathMin(lookback,Bars(symbol,tf)-2);
   for(int i=1;i<bars;i++)
     {
      double hi=iHigh(symbol,tf,i);
      double lo=iLow(symbol,tf,i);
      for(int j=i+1;j<bars;j++)
        {
         if(IsNear(symbol,hi,iHigh(symbol,tf,j),tolPoints))
            AddLiquidityPool(symbol,hi,iTime(symbol,tf,i),true,tolPoints);
         if(IsNear(symbol,lo,iLow(symbol,tf,j),tolPoints))
            AddLiquidityPool(symbol,lo,iTime(symbol,tf,i),false,tolPoints);
        }
     }

   if(usePrevDay)
     {
      double pdHigh=iHigh(symbol,PERIOD_D1,1);
      double pdLow =iLow(symbol,PERIOD_D1,1);
      if(pdHigh>0) AddLiquidityPool(symbol,pdHigh,iTime(symbol,PERIOD_D1,1),true,tolPoints);
      if(pdLow>0)  AddLiquidityPool(symbol,pdLow, iTime(symbol,PERIOD_D1,1),false,tolPoints);
     }
   if(usePrevSession)
     {
      // Approximate "session" with the last 4H bar as a lightweight proxy
      double shHigh=iHigh(symbol,PERIOD_H4,1);
      double shLow =iLow(symbol,PERIOD_H4,1);
      if(shHigh>0) AddLiquidityPool(symbol,shHigh,iTime(symbol,PERIOD_H4,1),true,tolPoints);
      if(shLow>0)  AddLiquidityPool(symbol,shLow, iTime(symbol,PERIOD_H4,1),false,tolPoints);
     }
  }

//--- Check the last closed bar on checkTF against all unswept pools --------
//--- Returns true and fills "swept" if a sweep just happened. --------------
bool UpdateLiquiditySweeps(const string symbol,ENUM_TIMEFRAMES checkTF,LiquidityPool &swept)
  {
   double hi=iHigh(symbol,checkTF,1);
   double lo=iLow(symbol,checkTF,1);
   double cl=iClose(symbol,checkTF,1);
   datetime t=iTime(symbol,checkTF,1);

   bool found=false;
   for(int i=0;i<ArraySize(g_liquidityPools);i++)
     {
      if(g_liquidityPools[i].swept) continue;

      if(g_liquidityPools[i].isHigh && hi>g_liquidityPools[i].price && cl<g_liquidityPools[i].price)
        {
         g_liquidityPools[i].swept=true;
         g_liquidityPools[i].sweptTime=t;
         swept=g_liquidityPools[i];
         found=true;
        }
      else if(!g_liquidityPools[i].isHigh && lo<g_liquidityPools[i].price && cl>g_liquidityPools[i].price)
        {
         g_liquidityPools[i].swept=true;
         g_liquidityPools[i].sweptTime=t;
         swept=g_liquidityPools[i];
         found=true;
        }
     }
   return found;
  }

//--- Was there a sweep within the last N bars? (used as an entry condition) --
bool HasRecentSweep(const string symbol,ENUM_TIMEFRAMES checkTF,int withinBars,bool wantHighSweep,LiquidityPool &out)
  {
   datetime cutoff = iTime(symbol,checkTF,MathMin(withinBars,Bars(symbol,checkTF)-1));
   for(int i=0;i<ArraySize(g_liquidityPools);i++)
     {
      if(!g_liquidityPools[i].swept) continue;
      if(g_liquidityPools[i].isHigh!=wantHighSweep) continue;
      if(g_liquidityPools[i].sweptTime>=cutoff)
        {
         out=g_liquidityPools[i];
         return true;
        }
     }
   return false;
  }

#endif // __LIQUIDITY_MQH__