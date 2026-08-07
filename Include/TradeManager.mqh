//+------------------------------------------------------------------+
//|                                                  TradeManager.mqh  |
//|  Sends the order, then babysits it: partial close at TP1,        |
//|  breakeven, and a tightening trail toward TP2.                   |
//+------------------------------------------------------------------+
#ifndef __TRADEMANAGER_MQH__
#define __TRADEMANAGER_MQH__

#include <Trade\Trade.mqh>
#include "Config.mqh"
#include "Globals.mqh"
#include "Utils.mqh"
#include "Logger.mqh"
#include "RiskManager.mqh"

CTrade g_trade;

struct ManagedTrade
  {
   ulong  ticket;
   double entryPrice;
   double initialSL;
   bool   partialClosed;
   bool   beApplied;
  };
ManagedTrade g_managedTrades[];

void TradeManager_Init()
  {
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(20);
   g_trade.LogLevel(LOG_LEVEL_ERRORS);
  }

//--- Register a freshly opened position for partial/BE/trailing management --
void TrackNewPosition(ulong dealTicket,double entryPrice,double initialSL)
  {
   ulong posId=0;
   if(HistoryDealSelect(dealTicket))
      posId=HistoryDealGetInteger(dealTicket,DEAL_POSITION_ID);
   if(posId==0) return;

   ManagedTrade mt;
   mt.ticket=posId;
   mt.entryPrice=entryPrice;
   mt.initialSL=initialSL;
   mt.partialClosed=false;
   mt.beApplied=false;

   int sz=ArraySize(g_managedTrades);
   ArrayResize(g_managedTrades,sz+1);
   g_managedTrades[sz]=mt;
  }

//--- Fire a market order from a validated TradeSignal ------------------------
bool OpenTradeFromSignal(const string symbol,TradeSignal &sig)
  {
   double sl=sig.sl, tp=sig.tp2; // broker-level TP = the far target (TP1 is managed in code)
   ClampStopsToBrokerMin(symbol,sig.type,sig.entry,sl,tp);

   double lot=GetTradeLot(symbol);
   bool ok=false;

   if(sig.type==ORDER_TYPE_BUY)
      ok=g_trade.Buy(lot,symbol,0.0,sl,tp,InpTradeComment);
   else
      ok=g_trade.Sell(lot,symbol,0.0,sl,tp,InpTradeComment);

   if(!ok)
     {
      LogMsg(LOG_ERROR,StringFormat("Order failed (%d): %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription()));
      return false;
     }

   LogMsg(LOG_TRADE,sig.reason);
   TrackNewPosition(g_trade.ResultDeal(),sig.entry,sl);
   return true;
  }

//--- Per-tick/per-bar housekeeping on every open EA position ------------------
void ManageOpenTrades(const string symbol)
  {
   for(int i=ArraySize(g_managedTrades)-1;i>=0;i--)
     {
      ulong ticket=g_managedTrades[i].ticket;
      if(!PositionSelectByTicket(ticket))
        {
         // position is gone (closed by SL/TP/manually) - stop tracking it
         ArrayRemove(g_managedTrades,i,1);
         continue;
        }

      long type=PositionGetInteger(POSITION_TYPE);
      double vol=PositionGetDouble(POSITION_VOLUME);
      double curSL=PositionGetDouble(POSITION_SL);
      double curTP=PositionGetDouble(POSITION_TP);
      double entry=g_managedTrades[i].entryPrice;
      double initSL=g_managedTrades[i].initialSL;
      double risk=MathAbs(entry-initSL);
      if(risk<=0) continue;

      double curPrice = (type==POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol,SYMBOL_BID)
                                                    : SymbolInfoDouble(symbol,SYMBOL_ASK);
      double rr = (type==POSITION_TYPE_BUY) ? (curPrice-entry)/risk : (entry-curPrice)/risk;

      //--- Partial close at TP1 ------------------------------------------------
      if(!g_managedTrades[i].partialClosed && rr>=InpTP1_RR)
        {
         double closeVol=NormalizeLot(symbol,vol*InpTP1_ClosePercent/100.0);
         if(closeVol>0 && closeVol<vol)
           {
            if(g_trade.PositionClosePartial(ticket,closeVol))
              {
               g_managedTrades[i].partialClosed=true;
               LogMsg(LOG_TRADE,StringFormat("TP1 hit, closed %.2f lots on #%d",closeVol,(int)ticket));
              }
           }
         else
           {
            g_managedTrades[i].partialClosed=true; // too small to split further, treat as done
           }
        }

      //--- Move to breakeven after the partial -----------------------------------
      if(InpUseBreakEvenAfterTP1 && g_managedTrades[i].partialClosed && !g_managedTrades[i].beApplied)
        {
         double beBuffer=PointsToPrice(symbol,InpBreakEvenBufferPts);
         double newSL = (type==POSITION_TYPE_BUY) ? entry+beBuffer : entry-beBuffer;
         if(g_trade.PositionModify(ticket,NormalizePriceEx(symbol,newSL),curTP))
            g_managedTrades[i].beApplied=true;
        }

      //--- Trail the remainder toward TP2 once we're in profit enough -----------
      if(InpUseTrailing && rr>=InpTrailStartRR)
        {
         double trailDist=PointsToPrice(symbol,InpTrailStepPoints);
         if(type==POSITION_TYPE_BUY)
           {
            double newSL=curPrice-trailDist;
            if(newSL>curSL) g_trade.PositionModify(ticket,NormalizePriceEx(symbol,newSL),curTP);
           }
         else
           {
            double newSL=curPrice+trailDist;
            if(curSL==0 || newSL<curSL) g_trade.PositionModify(ticket,NormalizePriceEx(symbol,newSL),curTP);
           }
        }
     }
  }

#endif // __TRADEMANAGER_MQH__