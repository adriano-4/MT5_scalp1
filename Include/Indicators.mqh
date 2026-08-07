//+------------------------------------------------------------------+
//|                                                   Indicators.mqh  |
//|  Owns every indicator handle used by the EA. Create in OnInit,   |
//|  release in OnDeinit, read via the getter functions below.       |
//+------------------------------------------------------------------+
#ifndef __INDICATORS_MQH__
#define __INDICATORS_MQH__

#include "Config.mqh"

int g_atrHandle    = INVALID_HANDLE;
int g_emaFastHandle= INVALID_HANDLE;
int g_emaSlowHandle= INVALID_HANDLE;

bool Indicators_Init(const string symbol)
  {
   g_atrHandle = iATR(symbol,InpATRTimeframe,InpATRPeriod);
   g_emaFastHandle = iMA(symbol,InpHTF,20,0,MODE_EMA,PRICE_CLOSE);
   g_emaSlowHandle = iMA(symbol,InpHTF,50,0,MODE_EMA,PRICE_CLOSE);

   if(g_atrHandle==INVALID_HANDLE || g_emaFastHandle==INVALID_HANDLE || g_emaSlowHandle==INVALID_HANDLE)
     {
      Print("Indicators_Init: failed to create one or more indicator handles");
      return false;
     }
   return true;
  }

void Indicators_Deinit()
  {
   if(g_atrHandle!=INVALID_HANDLE)     IndicatorRelease(g_atrHandle);
   if(g_emaFastHandle!=INVALID_HANDLE) IndicatorRelease(g_emaFastHandle);
   if(g_emaSlowHandle!=INVALID_HANDLE) IndicatorRelease(g_emaSlowHandle);
  }

//--- Returns ATR value "shift" bars back, or -1.0 on failure -----------
double GetATR(int shift=0)
  {
   double buf[];
   ArraySetAsSeries(buf,true);
   if(CopyBuffer(g_atrHandle,0,shift,1,buf)!=1) return -1.0;
   return buf[0];
  }

double GetEMA(int handle,int shift=0)
  {
   double buf[];
   ArraySetAsSeries(buf,true);
   if(CopyBuffer(handle,0,shift,1,buf)!=1) return -1.0;
   return buf[0];
  }

double GetEMAFast(int shift=0){ return GetEMA(g_emaFastHandle,shift); }
double GetEMASlow(int shift=0){ return GetEMA(g_emaSlowHandle,shift); }

#endif // __INDICATORS_MQH__