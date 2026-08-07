//+------------------------------------------------------------------+
//|                                                   EntryEngine.mqh  |
//|  The "sniper" brain. Three conditions are MANDATORY (liquidity   |
//|  sweep, a live OB/FVG zone, an M1 confirmation candle) - without |
//|  all three there is no signal, full stop. On top of that a       |
//|  weighted score (HTF bias, structure, S/R) has to clear          |
//|  InpMinConfluenceScore. This is deliberately strict: fewer,      |
//|  higher-quality trades rather than many mediocre ones.           |
//+------------------------------------------------------------------+
#ifndef __ENTRYENGINE_MQH__
#define __ENTRYENGINE_MQH__

#include "Globals.mqh"
#include "Config.mqh"
#include "Utils.mqh"
#include "MarketStructure.mqh"
#include "Liquidity.mqh"
#include "OrderBlocks.mqh"
#include "FVG.mqh"
#include "Indicators.mqh"

//--- Candle-pattern confirmation on the entry timeframe ---------------------
bool IsBullishEngulfing(const string symbol,ENUM_TIMEFRAMES tf,int shift=1)
  {
   double o1=iOpen(symbol,tf,shift),   c1=iClose(symbol,tf,shift);
   double o2=iOpen(symbol,tf,shift+1), c2=iClose(symbol,tf,shift+1);
   return(c1>o1 && o2>c2 && c1>=o2 && o1<=c2);
  }
bool IsBearishEngulfing(const string symbol,ENUM_TIMEFRAMES tf,int shift=1)
  {
   double o1=iOpen(symbol,tf,shift),   c1=iClose(symbol,tf,shift);
   double o2=iOpen(symbol,tf,shift+1), c2=iClose(symbol,tf,shift+1);
   return(c1<o1 && o2<c2 && c1<=o2 && o1>=c2);
  }
bool IsBullishPinBar(const string symbol,ENUM_TIMEFRAMES tf,int shift=1)
  {
   double o=iOpen(symbol,tf,shift), c=iClose(symbol,tf,shift);
   double h=iHigh(symbol,tf,shift), l=iLow(symbol,tf,shift);
   double body=MathAbs(c-o), range=h-l;
   if(range<=0) return false;
   double lowerWick=MathMin(o,c)-l, upperWick=h-MathMax(o,c);
   return(lowerWick>=body*2.0 && upperWick<=body*0.5);
  }
bool IsBearishPinBar(const string symbol,ENUM_TIMEFRAMES tf,int shift=1)
  {
   double o=iOpen(symbol,tf,shift), c=iClose(symbol,tf,shift);
   double h=iHigh(symbol,tf,shift), l=iLow(symbol,tf,shift);
   double body=MathAbs(c-o), range=h-l;
   if(range<=0) return false;
   double lowerWick=MathMin(o,c)-l, upperWick=h-MathMax(o,c);
   return(upperWick>=body*2.0 && lowerWick<=body*0.5);
  }
bool IsBullishTrigger(const string symbol,ENUM_TIMEFRAMES tf)
  { return(IsBullishEngulfing(symbol,tf) || IsBullishPinBar(symbol,tf)); }
bool IsBearishTrigger(const string symbol,ENUM_TIMEFRAMES tf)
  { return(IsBearishEngulfing(symbol,tf) || IsBearishPinBar(symbol,tf)); }

//--- Does price align with an older swing point = old support/resistance ---
bool CheckSRConfluence(const string symbol,double price,double tolPoints)
  {
   int n=ArraySize(g_swingsLTF);
   for(int i=0;i<n-2;i++) // exclude the two most recent (already used by structure logic)
      if(IsNear(symbol,price,g_swingsLTF[i].price,tolPoints))
         return true;
   return false;
  }

//--- Anchor price used to build the SL, taken from whichever zone is active --
double GetZoneSLAnchor(bool bullish,bool haveOB,const OrderBlockZone &ob,bool haveFVG,const FVGZone &fvg)
  {
   if(bullish)
     {
      double lvl=DBL_MAX;
      if(haveOB)  lvl=MathMin(lvl,ob.bottom);
      if(haveFVG) lvl=MathMin(lvl,fvg.bottom);
      return(lvl==DBL_MAX ? 0 : lvl);
     }
   else
     {
      double lvl=-DBL_MAX;
      if(haveOB)  lvl=MathMax(lvl,ob.top);
      if(haveFVG) lvl=MathMax(lvl,fvg.top);
      return(lvl==-DBL_MAX ? 0 : lvl);
     }
  }

//--- Main entry point, called once per new InpEntryTF bar -------------------
TradeSignal EvaluateEntry(const string symbol)
  {
   TradeSignal sig;
   sig.valid=false; sig.score=0; sig.reason="";

   double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
   double atr=GetATR();
   if(atr<=0) return sig;

   //================= BULLISH PATH =================
   if(g_htfBias!=BIAS_BEARISH)
     {
      LiquidityPool sweep;
      bool haveSweep = HasRecentSweep(symbol,InpEntryTF,10,false,sweep); // low-side sweep

      OrderBlockZone ob; bool haveOB = GetActiveOB(bid,true,ob) && !ob.traded;
      FVGZone fvg;       bool haveFVG= GetActiveFVG(bid,true,fvg) && !fvg.traded;

      bool haveTrigger = IsBullishTrigger(symbol,InpEntryTF);

      if(haveSweep && (haveOB || haveFVG) && haveTrigger)
        {
         int score=0;
         if(g_htfBias==BIAS_BULLISH)   score+=InpScoreHTFBias;
         if(g_structBias==BIAS_BULLISH) score+=InpScoreStructure;
         score+=InpScoreLiqSweep;
         if(haveOB)  score+=InpScoreOrderBlock;
         if(haveFVG) score+=InpScoreFVG;
         if(CheckSRConfluence(symbol,bid,InpSRTolerancePoints)) score+=InpScoreSRLevel;
         score+=InpScoreCandleTrigger;

         if(score>=InpMinConfluenceScore)
           {
            double slAnchor=GetZoneSLAnchor(true,haveOB,ob,haveFVG,fvg);
            double sl=slAnchor-atr*InpATRSLBufferMult;
            double risk=ask-sl;
            if(risk>0)
              {
               sig.valid=true;
               sig.type=ORDER_TYPE_BUY;
               sig.entry=ask;
               sig.sl=sl;
               sig.tp1=ask+risk*InpTP1_RR;
               sig.tp2=ask+risk*InpTP2_RR;
               sig.score=score;
               sig.reason=StringFormat("BUY sniper: sweep+%s+trigger, score=%d",
                                        (haveOB&&haveFVG?"OB+FVG":(haveOB?"OB":"FVG")),score);
               sig.zoneId=StringFormat("%d_%.5f",(int)(haveOB?ob.time:fvg.time),slAnchor);
               return sig;
              }
           }
        }
     }

   //================= BEARISH PATH =================
   if(g_htfBias!=BIAS_BULLISH)
     {
      LiquidityPool sweep;
      bool haveSweep = HasRecentSweep(symbol,InpEntryTF,10,true,sweep); // high-side sweep

      OrderBlockZone ob; bool haveOB = GetActiveOB(ask,false,ob) && !ob.traded;
      FVGZone fvg;       bool haveFVG= GetActiveFVG(ask,false,fvg) && !fvg.traded;

      bool haveTrigger = IsBearishTrigger(symbol,InpEntryTF);

      if(haveSweep && (haveOB || haveFVG) && haveTrigger)
        {
         int score=0;
         if(g_htfBias==BIAS_BEARISH)   score+=InpScoreHTFBias;
         if(g_structBias==BIAS_BEARISH) score+=InpScoreStructure;
         score+=InpScoreLiqSweep;
         if(haveOB)  score+=InpScoreOrderBlock;
         if(haveFVG) score+=InpScoreFVG;
         if(CheckSRConfluence(symbol,ask,InpSRTolerancePoints)) score+=InpScoreSRLevel;
         score+=InpScoreCandleTrigger;

         if(score>=InpMinConfluenceScore)
           {
            double slAnchor=GetZoneSLAnchor(false,haveOB,ob,haveFVG,fvg);
            double sl=slAnchor+atr*InpATRSLBufferMult;
            double risk=sl-bid;
            if(risk>0)
              {
               sig.valid=true;
               sig.type=ORDER_TYPE_SELL;
               sig.entry=bid;
               sig.sl=sl;
               sig.tp1=bid-risk*InpTP1_RR;
               sig.tp2=bid-risk*InpTP2_RR;
               sig.score=score;
               sig.reason=StringFormat("SELL sniper: sweep+%s+trigger, score=%d",
                                        (haveOB&&haveFVG?"OB+FVG":(haveOB?"OB":"FVG")),score);
               sig.zoneId=StringFormat("%d_%.5f",(int)(haveOB?ob.time:fvg.time),slAnchor);
               return sig;
              }
           }
        }
     }

   return sig; // no valid setup this bar
  }

//--- Call after a signal has actually been executed, so we never re-fire ---
void MarkZoneTraded(const string symbol,bool bullish,double price)
  {
   OrderBlockZone ob;
   if(GetActiveOB(price,bullish,ob)) MarkOBTraded(ob.time,ob.top,ob.bottom);
   FVGZone fvg;
   if(GetActiveFVG(price,bullish,fvg)) MarkFVGTraded(fvg.time,fvg.top,fvg.bottom);
  }

#endif // __ENTRYENGINE_MQH__