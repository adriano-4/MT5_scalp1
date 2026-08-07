//+------------------------------------------------------------------+
//|                                                       Engine.mqh |
//|  The only file the .mq5 talks to. Sequences everything:          |
//|  indicators -> structure -> liquidity -> zones -> filters ->     |
//|  entry engine -> risk manager -> trade manager -> dashboard.     |
//+------------------------------------------------------------------+
#ifndef __ENGINE_MQH__
#define __ENGINE_MQH__

#include "Config.mqh"
#include "Globals.mqh"
#include "Utils.mqh"
#include "Logger.mqh"
#include "Indicators.mqh"
#include "MarketStructure.mqh"
#include "BOS.mqh"
#include "CHOCH.mqh"
#include "Liquidity.mqh"
#include "OrderBlocks.mqh"
#include "FVG.mqh"
#include "TrendFilter.mqh"
#include "SessionFilter.mqh"
#include "SpreadFilter.mqh"
#include "RiskManager.mqh"
#include "EntryEngine.mqh"
#include "TradeManager.mqh"
#include "Statistics.mqh"
#include "Dashboard.mqh"

datetime g_lastHTFBarTime=0;
datetime g_lastStructBarTime=0;
datetime g_lastEntryBarTime=0;

bool Engine_Init(const string symbol)
  {
   if(!Indicators_Init(symbol)) return false;
   TradeManager_Init();
   Dashboard_Init();
   RiskManager_RollDailyGuard();
   LogMsg(LOG_INFO,"SniperScalpEA engine initialised on "+symbol);
   return true;
  }

void Engine_Deinit()
  {
   Indicators_Deinit();
   Dashboard_Deinit();
  }

//--- Runs the heavier structure/zone recalculation, gated per timeframe ------
void Engine_UpdateStructureIfNewBar(const string symbol)
  {
   if(IsNewBar(symbol,InpHTF,g_lastHTFBarTime))
      UpdateTrendFilter(symbol);

   if(IsNewBar(symbol,InpStructTF,g_lastStructBarTime))
     {
      UpdateMarketStructure(symbol,InpStructTF,InpSwingLookback,InpSwingHistoryCount);

      ENUM_STRUCT_EVENT ev=DetectCHOCH(symbol,InpStructTF); // check reversal first...
      if(ev==STRUCT_EVENT_NONE)
         ev=DetectBOS(symbol,InpStructTF);                  // ...then continuation

      if(ev!=STRUCT_EVENT_NONE)
         RegisterOrderBlock(symbol,InpStructTF,ev);

      UpdateOrderBlockState(symbol,InpStructTF,InpMaxOBAgeBars);
      DetectFVG(symbol,InpStructTF);
      UpdateFVGState(symbol,InpStructTF,InpMaxFVGAgeBars);
      UpdateLiquidityPools(symbol,InpStructTF,InpLiquidityLookback,InpLiquidityTolPoints,
                           InpUsePrevDayHiLo,InpUsePrevSessionHiLo);
     }
  }

//--- Runs the fast entry-timeframe checks: sweep detection + signal search ---
void Engine_CheckEntryIfNewBar(const string symbol)
  {
   if(!IsNewBar(symbol,InpEntryTF,g_lastEntryBarTime)) return;

   LiquidityPool sweptDummy;
   UpdateLiquiditySweeps(symbol,InpEntryTF,sweptDummy);

   if(!CanOpenNewTrade())       return;
   if(!IsTradingWindowOK(symbol)) return;
   if(!IsSpreadOK(symbol))      return;

   TradeSignal sig=EvaluateEntry(symbol);
   if(sig.valid)
     {
      bool bullish=(sig.type==ORDER_TYPE_BUY);
      if(OpenTradeFromSignal(symbol,sig))
         MarkZoneTraded(symbol,bullish,sig.entry);
     }
  }

//--- Called on every OnTick() from the .mq5 -----------------------------------
void Engine_OnTick(const string symbol)
  {
   ManageOpenTrades(symbol);          
   Engine_UpdateStructureIfNewBar(symbol);
   Engine_CheckEntryIfNewBar(symbol);
   Dashboard_Update(symbol);
  }

#endif // __ENGINE_MQH__