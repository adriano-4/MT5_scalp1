//+------------------------------------------------------------------+
//|                                                   Statistics.mqh  |
//|  Lightweight running stats, fed from OnTradeTransaction. Useful  |
//|  on the dashboard and for a quick sanity check after a backtest. |
//+------------------------------------------------------------------+
#ifndef __STATISTICS_MQH__
#define __STATISTICS_MQH__

#include "Config.mqh"
#include "Logger.mqh"

int    g_statTotalTrades=0;
int    g_statWins=0;
int    g_statLosses=0;
double g_statGrossProfit=0.0;
double g_statGrossLoss=0.0;
int    g_statStreak=0; // positive = current win streak, negative = current loss streak

//--- Call from OnTradeTransaction whenever a position-closing deal for our EA fires --
void Statistics_OnDealClosed(ulong dealTicket)
  {
   if(!HistoryDealSelect(dealTicket)) return;
   if((long)HistoryDealGetInteger(dealTicket,DEAL_MAGIC)!=InpMagicNumber) return;
   if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket,DEAL_ENTRY)!=DEAL_ENTRY_OUT
      && (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket,DEAL_ENTRY)!=DEAL_ENTRY_OUT_BY) return;

   double profit = HistoryDealGetDouble(dealTicket,DEAL_PROFIT)
                  +HistoryDealGetDouble(dealTicket,DEAL_SWAP)
                  +HistoryDealGetDouble(dealTicket,DEAL_COMMISSION);

   g_statTotalTrades++;
   if(profit>=0)
     {
      g_statWins++;
      g_statGrossProfit+=profit;
      g_statStreak = (g_statStreak>0) ? g_statStreak+1 : 1;
     }
   else
     {
      g_statLosses++;
      g_statGrossLoss+=MathAbs(profit);
      g_statStreak = (g_statStreak<0) ? g_statStreak-1 : -1;
     }
  }

double Statistics_WinRate()
  {
   if(g_statTotalTrades==0) return 0.0;
   return 100.0*g_statWins/g_statTotalTrades;
  }

double Statistics_ProfitFactor()
  {
   if(g_statGrossLoss<=0) return(g_statGrossProfit>0 ? 999.0 : 0.0);
   return g_statGrossProfit/g_statGrossLoss;
  }

double Statistics_Expectancy()
  {
   if(g_statTotalTrades==0) return 0.0;
   return (g_statGrossProfit-g_statGrossLoss)/g_statTotalTrades;
  }

string Statistics_Summary()
  {
   return StringFormat("Trades:%d  Win%%:%.1f  PF:%.2f  Exp:%.2f  Streak:%d",
                        g_statTotalTrades,Statistics_WinRate(),Statistics_ProfitFactor(),
                        Statistics_Expectancy(),g_statStreak);
  }

//--- One-line-per-trade CSV, handy for post-backtest analysis in Excel -------
void Statistics_ExportCSV(const string filename)
  {
   int handle=FileOpen(filename,FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(handle==INVALID_HANDLE) { LogMsg(LOG_ERROR,"Statistics_ExportCSV: could not open file"); return; }
   FileWrite(handle,"Trades",g_statTotalTrades,"WinRate",Statistics_WinRate(),
             "ProfitFactor",Statistics_ProfitFactor(),"Expectancy",Statistics_Expectancy());
   FileClose(handle);
  }

#endif // __STATISTICS_MQH__