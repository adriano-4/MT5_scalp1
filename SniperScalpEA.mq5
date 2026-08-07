#property copyright "SniperScalpEA"
#property version   "1.00"
#property strict

#include "Include/Engine.mqh"


int OnInit()
  {
   if(!Engine_Init(_Symbol))
     {
      Print("SniperScalpEA: initialisation failed");
      return(INIT_FAILED);
     }
   return(INIT_SUCCEEDED);
  }


void OnDeinit(const int reason)
  {
   Engine_Deinit();
  }


void OnTick()
  {
   Engine_OnTick(_Symbol);
  }


void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest      &request,
                         const MqlTradeResult       &result)
  {
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
      Statistics_OnDealClosed(trans.deal);
  }
