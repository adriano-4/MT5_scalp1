//+------------------------------------------------------------------+
//| MT5_Scalp_V2.mq5                                                 |
//| V2: V1 reversal engine + anti-range filter + daily risk controls |
//| No BOS/CHoCH/SMC/indicator-entry logic.                         |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"

#include <Trade/Trade.mqh>

CTrade trade;

input string InpSymbol = "";
input double InpLot = 0.01;
input int InpInitialDistancePoints = 20;
input int InpTrailDistancePoints = 15;
input ulong InpMagic = 2026080802;

// Execution / safety
input int InpMaxSpreadPoints = 0;          // 0 = disabled
input int InpMaxConsecutiveErrors = 3;
input int InpRetryDelayMs = 100;
input int InpMaxTradesPerDay = 50;         // 0 = disabled
input int InpMaxReversalsPerDay = 50;      // 0 = disabled
input int InpCooldownSeconds = 10;         // 0 = disabled

// Daily protection / target
input double InpDailyProfitTarget = 0.0;   // account currency, 0 = disabled
input double InpDailyProfitCap = 0.0;      // hard cap, 0 = disabled
input double InpDailyLossLimit = 0.0;      // positive account currency, 0 = disabled

// Anti-range filter. These are deliberately simple market-state filters.
input bool InpUseRangeFilter = true;
input ENUM_TIMEFRAMES InpFilterTF = PERIOD_M1;
input int InpATRPeriod = 14;
input int InpRangeLookbackBars = 20;
input double InpMinATRPoints = 0.0;        // 0 = disabled
input double InpMinRangeATR = 0.80;        // recent range must be >= ATR * this factor
input double InpDirectionalEfficiency = 0.25; // net displacement / total movement

string sym;
int digits_count = 0;
double point_size = 0.0;
int atr_handle = INVALID_HANDLE;

const int STATE_INIT = 0;
const int STATE_BUY = 1;
const int STATE_SELL = 2;
const int STATE_HALT = 3;
int state = STATE_INIT;

int consecutive_errors = 0;
datetime cooldown_until = 0;
datetime last_trade_day = 0;
double day_start_equity = 0.0;
int day_trades = 0;
int day_reversals = 0;

ulong active_position_ticket = 0;
double highest_since_entry = 0.0;
double lowest_since_entry = 0.0;
double last_pending_price = 0.0;

//+------------------------------------------------------------------+
int PriceDigits()
{
   return digits_count;
}

//+------------------------------------------------------------------+
double NormPrice(const double price)
{
   return NormalizeDouble(price, PriceDigits());
}

//+------------------------------------------------------------------+
bool IsTradeRetcodeOK(const uint rc)
{
   return (rc == TRADE_RETCODE_DONE ||
           rc == TRADE_RETCODE_DONE_PARTIAL ||
           rc == TRADE_RETCODE_PLACED ||
           rc == TRADE_RETCODE_NO_CHANGES);
}

//+------------------------------------------------------------------+
void LogTradeFailure(const string action)
{
   PrintFormat("[V2][ERROR] %s | retcode=%u | %s", action,
               trade.ResultRetcode(), trade.ResultRetcodeDescription());
   consecutive_errors++;
   if(InpMaxConsecutiveErrors > 0 && consecutive_errors >= InpMaxConsecutiveErrors)
      Halt("Maximum consecutive trade errors reached");
}

//+------------------------------------------------------------------+
void ResetErrors()
{
   consecutive_errors = 0;
}

//+------------------------------------------------------------------+
void Halt(const string reason)
{
   if(state != STATE_HALT)
      PrintFormat("[V2][HALT] %s", reason);
   state = STATE_HALT;
}

//+------------------------------------------------------------------+
long DayKey(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return (long)dt.year * 10000 + dt.mon * 100 + dt.day;
}

//+------------------------------------------------------------------+
void ResetDayIfNeeded()
{
   datetime now = TimeCurrent();
   if(last_trade_day == 0 || DayKey(now) != DayKey(last_trade_day))
   {
      last_trade_day = now;
      day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      day_trades = 0;
      day_reversals = 0;
      cooldown_until = 0;
      if(state == STATE_HALT)
         state = STATE_INIT;
      PrintFormat("[V2] New trading day | start equity=%.2f", day_start_equity);
   }
}

//+------------------------------------------------------------------+
double DailyPnL()
{
   if(day_start_equity <= 0.0)
      return 0.0;
   return AccountInfoDouble(ACCOUNT_EQUITY) - day_start_equity;
}

//+------------------------------------------------------------------+
bool SafetyLimitsOK()
{
   double pnl = DailyPnL();

   if(InpDailyLossLimit > 0.0 && pnl <= -InpDailyLossLimit)
   {
      Halt("Daily loss limit reached");
      return false;
   }
   if(InpDailyProfitCap > 0.0 && pnl >= InpDailyProfitCap)
   {
      Halt("Daily profit cap reached");
      return false;
   }
   if(InpDailyProfitTarget > 0.0 && pnl >= InpDailyProfitTarget)
   {
      Halt("Daily profit target reached");
      return false;
   }
   if(InpMaxTradesPerDay > 0 && day_trades >= InpMaxTradesPerDay)
   {
      Halt("Maximum daily trades reached");
      return false;
   }
   if(InpMaxReversalsPerDay > 0 && day_reversals >= InpMaxReversalsPerDay)
   {
      Halt("Maximum daily reversals reached");
      return false;
   }
   if(TimeCurrent() < cooldown_until)
      return false;

   return true;
}

//+------------------------------------------------------------------+
bool SpreadOK()
{
   if(InpMaxSpreadPoints <= 0)
      return true;
   MqlTick tick;
   if(!SymbolInfoTick(sym, tick))
      return false;
   double spread_points = (tick.ask - tick.bid) / point_size;
   return (spread_points <= InpMaxSpreadPoints);
}

//+------------------------------------------------------------------+
bool HasOurPosition(ENUM_POSITION_TYPE &ptype, ulong &ticket)
{
   int found = 0;
   ptype = POSITION_TYPE_BUY;
   ticket = 0;
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ticket = t;
      found++;
   }
   if(found > 1)
   {
      Halt("Multiple EA positions detected");
      return false;
   }
   return found == 1;
}

//+------------------------------------------------------------------+
int OurPendingCount(ENUM_ORDER_TYPE wanted = WRONG_VALUE)
{
   int count = 0;
   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0 || !OrderSelect(t)) continue;
      if(OrderGetString(ORDER_SYMBOL) != sym) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      ENUM_ORDER_TYPE typ = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(wanted == WRONG_VALUE || typ == wanted)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
ulong FindPending(ENUM_ORDER_TYPE wanted)
{
   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0 || !OrderSelect(t)) continue;
      if(OrderGetString(ORDER_SYMBOL) != sym) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == wanted)
         return t;
   }
   return 0;
}

//+------------------------------------------------------------------+
void DeletePendingType(const ENUM_ORDER_TYPE wanted)
{
   for(int i=OrdersTotal()-1; i>=0; --i)
   {
      ulong t = OrderGetTicket(i);
      if(t == 0 || !OrderSelect(t)) continue;
      if(OrderGetString(ORDER_SYMBOL) != sym) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != wanted) continue;

      ResetErrors();
      if(!trade.OrderDelete(t) || !IsTradeRetcodeOK(trade.ResultRetcode()))
      {
         LogTradeFailure("OrderDelete");
         return;
      }
   }
}

//+------------------------------------------------------------------+
bool BrokerDistanceOK(const ENUM_ORDER_TYPE type, const double price)
{
   MqlTick tick;
   if(!SymbolInfoTick(sym, tick)) return false;
   long stops = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_dist = (double)MathMax(stops, freeze) * point_size;

   if(type == ORDER_TYPE_BUY_STOP)
      return price >= tick.ask + min_dist;
   if(type == ORDER_TYPE_SELL_STOP)
      return price <= tick.bid - min_dist;
   return false;
}

//+------------------------------------------------------------------+
bool PlaceOrMovePending(const ENUM_ORDER_TYPE type, const double desired)
{
   double price = NormPrice(desired);
   if(!BrokerDistanceOK(type, price))
      return false;

   ulong ticket = FindPending(type);
   if(ticket != 0)
   {
      if(!OrderSelect(ticket)) return false;
      double current = OrderGetDouble(ORDER_PRICE_OPEN);
      bool better = (type == ORDER_TYPE_SELL_STOP) ? price > current + point_size*0.5
                                                   : price < current - point_size*0.5;
      if(!better)
         return true;

      ResetErrors();
      if(!trade.OrderModify(ticket, price, 0.0, 0.0, ORDER_TIME_GTC, 0, 0.0) ||
         !IsTradeRetcodeOK(trade.ResultRetcode()))
      {
         LogTradeFailure("OrderModify pending");
         return false;
      }
      last_pending_price = price;
      return true;
   }

   if(OurPendingCount((ENUM_ORDER_TYPE)type) > 0)
      return false;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(sym);
   ResetErrors();
   bool ok = false;
   if(type == ORDER_TYPE_BUY_STOP)
      ok = trade.BuyStop(InpLot, price, sym, 0.0, 0.0, ORDER_TIME_GTC, 0, "V2_BUY_STOP");
   else if(type == ORDER_TYPE_SELL_STOP)
      ok = trade.SellStop(InpLot, price, sym, 0.0, 0.0, ORDER_TIME_GTC, 0, "V2_SELL_STOP");

   if(!ok || !IsTradeRetcodeOK(trade.ResultRetcode()))
   {
      LogTradeFailure("Place pending");
      return false;
   }
   last_pending_price = price;
   return true;
}

//+------------------------------------------------------------------+
bool ReadATR(double &atr)
{
   atr = 0.0;
   if(atr_handle == INVALID_HANDLE) return false;
   double buf[1];
   if(CopyBuffer(atr_handle, 0, 1, 1, buf) != 1)
      return false;
   atr = buf[0];
   return atr > 0.0;
}

//+------------------------------------------------------------------+
bool MarketIsTradable()
{
   if(!InpUseRangeFilter)
      return true;
   if(!SpreadOK())
      return false;

   double atr = 0.0;
   if(!ReadATR(atr))
      return false;

   if(InpMinATRPoints > 0.0 && atr / point_size < InpMinATRPoints)
      return false;

   int n = MathMax(5, InpRangeLookbackBars);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(sym, InpFilterTF, 1, n, rates) < n)
      return false;

   double hi = rates[0].high;
   double lo = rates[0].low;
   double total_move = 0.0;
   for(int i=0; i<n; ++i)
   {
      hi = MathMax(hi, rates[i].high);
      lo = MathMin(lo, rates[i].low);
      if(i < n-1)
         total_move += MathAbs(rates[i].close - rates[i+1].close);
   }

   double range = hi - lo;
   if(range < atr * InpMinRangeATR)
      return false;

   double net = MathAbs(rates[0].close - rates[n-1].close);
   double efficiency = (total_move > 0.0 ? net / total_move : 0.0);
   return efficiency >= InpDirectionalEfficiency;
}

//+------------------------------------------------------------------+
bool ReconcileState()
{
   ENUM_POSITION_TYPE pt;
   ulong pos_ticket;
   bool has_pos = HasOurPosition(pt, pos_ticket);
   int buy_stops = OurPendingCount((ENUM_ORDER_TYPE)ORDER_TYPE_BUY_STOP);
   int sell_stops = OurPendingCount((ENUM_ORDER_TYPE)ORDER_TYPE_SELL_STOP);

   if(!has_pos)
   {
      if(buy_stops > 1 || sell_stops > 1)
      {
         Halt("Invalid initial pending state");
         return false;
      }
      if(buy_stops == 1 && sell_stops == 1)
         state = STATE_INIT;
      else if(buy_stops == 0 && sell_stops == 0)
         state = STATE_INIT;
      else
      {
         Halt("Only one initial pending order exists");
         return false;
      }
      return true;
   }

   active_position_ticket = pos_ticket;
   if(pt == POSITION_TYPE_BUY)
   {
      state = STATE_BUY;
      if(buy_stops != 0 || sell_stops > 1)
      {
         Halt("Invalid BUY state: pending order mismatch");
         return false;
      }
   }
   else
   {
      state = STATE_SELL;
      if(sell_stops != 0 || buy_stops > 1)
      {
         Halt("Invalid SELL state: pending order mismatch");
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
void InitializeExtremesFromPosition()
{
   if(!PositionSelectByTicket(active_position_ticket)) return;
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   MqlTick tick;
   if(!SymbolInfoTick(sym, tick)) return;

   if(state == STATE_BUY)
   {
      if(highest_since_entry <= 0.0)
         highest_since_entry = MathMax(open, tick.bid);
      lowest_since_entry = 0.0;
   }
   else if(state == STATE_SELL)
   {
      if(lowest_since_entry <= 0.0)
         lowest_since_entry = MathMin(open, tick.ask);
      highest_since_entry = 0.0;
   }
}

//+------------------------------------------------------------------+
bool StartInitialCycle()
{
   if(!SafetyLimitsOK() || !MarketIsTradable())
      return false;

   MqlTick tick;
   if(!SymbolInfoTick(sym, tick)) return false;
   double buy = tick.ask + InpInitialDistancePoints * point_size;
   double sell = tick.bid - InpInitialDistancePoints * point_size;

   if(OurPendingCount((ENUM_ORDER_TYPE)ORDER_TYPE_BUY_STOP) == 0)
      if(!PlaceOrMovePending(ORDER_TYPE_BUY_STOP, buy)) return false;
   if(OurPendingCount((ENUM_ORDER_TYPE)ORDER_TYPE_SELL_STOP) == 0)
      if(!PlaceOrMovePending(ORDER_TYPE_SELL_STOP, sell)) return false;

   state = STATE_INIT;
   return true;
}

//+------------------------------------------------------------------+
void ManageBuy()
{
   if(state != STATE_BUY) return;
   if(!PositionSelectByTicket(active_position_ticket)) return;
   MqlTick tick;
   if(!SymbolInfoTick(sym, tick)) return;

   if(tick.bid > highest_since_entry)
      highest_since_entry = tick.bid;

   double desired = highest_since_entry - InpTrailDistancePoints * point_size;
   PlaceOrMovePending(ORDER_TYPE_SELL_STOP, desired);
}

//+------------------------------------------------------------------+
void ManageSell()
{
   if(state != STATE_SELL) return;
   if(!PositionSelectByTicket(active_position_ticket)) return;
   MqlTick tick;
   if(!SymbolInfoTick(sym, tick)) return;

   if(lowest_since_entry <= 0.0 || tick.ask < lowest_since_entry)
      lowest_since_entry = tick.ask;

   double desired = lowest_since_entry + InpTrailDistancePoints * point_size;
   PlaceOrMovePending(ORDER_TYPE_BUY_STOP, desired);
}

//+------------------------------------------------------------------+
int OnInit()
{
   sym = (InpSymbol == "" ? _Symbol : InpSymbol);
   if(!SymbolSelect(sym, true)) return INIT_FAILED;
   point_size = SymbolInfoDouble(sym, SYMBOL_POINT);
   digits_count = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(point_size <= 0.0) return INIT_FAILED;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(sym);
   trade.SetAsyncMode(false);

   if(InpUseRangeFilter)
   {
      atr_handle = iATR(sym, InpFilterTF, InpATRPeriod);
      if(atr_handle == INVALID_HANDLE)
         return INIT_FAILED;
   }

   last_trade_day = TimeCurrent();
   day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   ReconcileState();

   if(state != STATE_HALT)
   {
      ENUM_POSITION_TYPE pt;
      ulong ticket;
      if(HasOurPosition(pt, ticket))
      {
         active_position_ticket = ticket;
         InitializeExtremesFromPosition();
      }
      else
         StartInitialCycle();
   }

   PrintFormat("[V2] Initialized | symbol=%s lot=%.2f initial=%d trail=%d range_filter=%s",
               sym, InpLot, InpInitialDistancePoints, InpTrailDistancePoints,
               InpUseRangeFilter ? "ON" : "OFF");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atr_handle != INVALID_HANDLE)
      IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
void OnTick()
{
   ResetDayIfNeeded();
   if(state == STATE_HALT) return;
   if(!SafetyLimitsOK()) return;

   if(!ReconcileState()) return;

   ENUM_POSITION_TYPE pt;
   ulong ticket;
   bool has_pos = HasOurPosition(pt, ticket);

   if(has_pos)
   {
      if(active_position_ticket != ticket)
      {
         active_position_ticket = ticket;
         if(pt == POSITION_TYPE_BUY)
         {
            state = STATE_BUY;
            highest_since_entry = PositionGetDouble(POSITION_PRICE_OPEN);
            lowest_since_entry = 0.0;
         }
         else
         {
            state = STATE_SELL;
            lowest_since_entry = PositionGetDouble(POSITION_PRICE_OPEN);
            highest_since_entry = 0.0;
         }
      }

      if(state == STATE_BUY) ManageBuy();
      else if(state == STATE_SELL) ManageSell();
      return;
   }

   if(state == STATE_INIT)
   {
      if(OurPendingCount((ENUM_ORDER_TYPE)ORDER_TYPE_BUY_STOP) == 0 &&
         OurPendingCount((ENUM_ORDER_TYPE)ORDER_TYPE_SELL_STOP) == 0)
         StartInitialCycle();
   }
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.symbol != sym) return;

   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong deal = trans.deal;
   if(deal == 0 || !HistoryDealSelect(deal)) return;
   if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagic) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
   ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);

   if(entry == DEAL_ENTRY_IN)
   {
      day_trades++;
      cooldown_until = TimeCurrent() + InpCooldownSeconds;
      active_position_ticket = 0;
      highest_since_entry = 0.0;
      lowest_since_entry = 0.0;

      if(dtype == DEAL_TYPE_BUY)
      {
         state = STATE_BUY;
         DeletePendingType(ORDER_TYPE_SELL_STOP);
      }
      else if(dtype == DEAL_TYPE_SELL)
      {
         state = STATE_SELL;
         DeletePendingType(ORDER_TYPE_BUY_STOP);
      }
      ResetErrors();
      PrintFormat("[V2] Entry detected | type=%s | trades_today=%d",
                  dtype == DEAL_TYPE_BUY ? "BUY" : "SELL", day_trades);
   }
   else if(entry == DEAL_ENTRY_OUT)
   {
      day_reversals++;
      cooldown_until = TimeCurrent() + InpCooldownSeconds;
      PrintFormat("[V2] Exit/reversal detected | reversals_today=%d", day_reversals);
   }
}
//+------------------------------------------------------------------+
