//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh  |
//|  Gatekeeper for capital: how big the trade is, how many can run  |
//|  at once, and the daily kill-switch that overrides everything.   |
//+------------------------------------------------------------------+
#ifndef __RISKMANAGER_MQH__
#define __RISKMANAGER_MQH__

#include "Config.mqh"
#include "Globals.mqh"
#include "Utils.mqh"
#include "Logger.mqh"

//--- Count open positions that belong to this EA (by magic number) ---------
int CountOpenEAPositions()
  {
   int count=0;
   int total=PositionsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)
         count++;
     }
   return count;
  }

//--- Call once per tick/bar to roll the daily guard over at midnight -------
void RiskManager_RollDailyGuard()
  {
   datetime today=BrokerDateOnly();
   if(today!=g_currentDay)
     {
      g_currentDay=today;
      g_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      g_dailyLossHit=false;
     }
  }

//--- Has today's loss limit been breached? Sets the kill-switch if so ------
bool RiskManager_CheckDailyLoss()
  {
   if(g_dailyLossHit) return true;
   if(g_dayStartEquity<=0) return false;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPct = (g_dayStartEquity-equity)/g_dayStartEquity*100.0;

   if(lossPct>=InpDailyLossLimitPct)
     {
      g_dailyLossHit=true;
      LogMsg(LOG_WARN,StringFormat("Daily loss limit hit (%.2f%% >= %.2f%%). No new trades until tomorrow.",
             lossPct,InpDailyLossLimitPct));
      return true;
     }
   return false;
  }

//--- Master gate: is the EA allowed to open a brand-new trade right now? ---
bool CanOpenNewTrade()
  {
   if(!InpEnableTrading) return false;
   RiskManager_RollDailyGuard();
   if(RiskManager_CheckDailyLoss()) return false;
   if(CountOpenEAPositions()>=InpMaxConcurrentTrades) return false;
   return true;
  }

//--- Fixed lot size, normalized to the symbol's volume step ----------------
double GetTradeLot(const string symbol)
  {
   return NormalizeLot(symbol,InpFixedLotSize);
  }

//--- Push SL/TP out to the broker's minimum stop-level distance if needed --
void ClampStopsToBrokerMin(const string symbol,ENUM_ORDER_TYPE type,double entry,double &sl,double &tp)
  {
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   long stopLevelPts=SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double minDist=stopLevelPts*point;
   if(minDist<=0) return;

   if(type==ORDER_TYPE_BUY)
     {
      if(entry-sl<minDist) sl=entry-minDist;
      if(tp-entry<minDist) tp=entry+minDist;
     }
   else if(type==ORDER_TYPE_SELL)
     {
      if(sl-entry<minDist) sl=entry+minDist;
      if(entry-tp<minDist) tp=entry-minDist;
     }
   sl=NormalizePriceEx(symbol,sl);
   tp=NormalizePriceEx(symbol,tp);
  }

#endif // __RISKMANAGER_MQH__