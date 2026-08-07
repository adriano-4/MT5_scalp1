//+------------------------------------------------------------------+
//|                                                 SessionFilter.mqh  |
//|  Two independent gates that both have to pass before we ever     |
//|  look for a trade: (1) we're inside the liquid London/NY window, |
//|  (2) no high-impact news is imminent on this symbol's currencies.|
//|  News uses MetaTrader's built-in Economic Calendar API - its     |
//|  coverage in the Strategy Tester depends on the calendar cache   |
//|  your terminal has downloaded, so verify it fires as expected    |
//|  on your broker/build before trusting it live.                  |
//+------------------------------------------------------------------+
#ifndef __SESSIONFILTER_MQH__
#define __SESSIONFILTER_MQH__

#include "Config.mqh"
#include "Utils.mqh"

//--- Simple broker-time session window + Friday-evening cutoff -------------
bool IsSessionOK()
  {
   if(!InpUseSessionFilter) return true;

   int h=BrokerHour();
   if(h<InpSessionStartHour || h>=InpSessionEndHour) return false;

   if(InpAvoidFridayLateHrs && BrokerDOW()==5 && h>=InpFridayCutoffHour) return false;
   if(BrokerDOW()==0 || BrokerDOW()==6) return false; // weekend safety net

   return true;
  }

//--- Is a high-impact (or any, per input) news event imminent on this symbol? --
bool IsNewsBlackout(const string symbol)
  {
   if(!InpUseNewsFilter) return false;

   string baseCcy = SymbolInfoString(symbol,SYMBOL_CURRENCY_BASE);
   string profCcy = SymbolInfoString(symbol,SYMBOL_CURRENCY_PROFIT);

   datetime from = TimeCurrent()-InpNewsMinutesAfter*60;
   datetime to   = TimeCurrent()+InpNewsMinutesBefore*60;

   MqlCalendarValue values[];
   string currencies[2]; currencies[0]=baseCcy; currencies[1]=profCcy;

   for(int c=0;c<2;c++)
     {
      if(currencies[c]=="") continue;
      int n=CalendarValueHistory(values,from,to,NULL,currencies[c]);
      if(n<=0) continue;

      for(int i=0;i<n;i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id,ev)) continue;
         if(InpNewsHighImpactOnly && ev.importance!=CALENDAR_IMPORTANCE_HIGH) continue;
         return true; // qualifying event sits inside our blackout window
        }
     }
   return false;
  }

//--- Single entry point used by the Engine ----------------------------------
bool IsTradingWindowOK(const string symbol)
  {
   if(!IsSessionOK()) return false;
   if(IsNewsBlackout(symbol)) return false;
   return true;
  }

#endif // __SESSIONFILTER_MQH__