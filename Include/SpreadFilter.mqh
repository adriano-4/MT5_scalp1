//+------------------------------------------------------------------+
//|                                                  SpreadFilter.mqh  |
//|  M1 scalping lives and dies by the spread. Reject entries when   |
//|  it's wider than what the strategy's SL/TP distances can absorb. |
//+------------------------------------------------------------------+
#ifndef __SPREADFILTER_MQH__
#define __SPREADFILTER_MQH__

#include "Config.mqh"
#include "Utils.mqh"

bool IsSpreadOK(const string symbol)
  {
   if(!InpUseSpreadFilter) return true;
   return CurrentSpreadPoints(symbol) <= InpMaxSpreadPoints;
  }

#endif // __SPREADFILTER_MQH__