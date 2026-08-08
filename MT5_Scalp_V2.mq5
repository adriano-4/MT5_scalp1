//+------------------------------------------------------------------+
//| MT5_Scalp_V2.mq5                                                 |
//| V2 = V1 EXACT CORE + daily profit/loss protections               |
//| NO range filter / NO BOS / NO CHoCH / NO SMC                    |
//+------------------------------------------------------------------+
#property strict
#property version "2.10"

#include <Trade/Trade.mqh>
CTrade trade;

//============================= V1 CORE =============================
input string InpSymbol                = "";
input double InpLot                   = 0.01;
input int    InpInitialDistancePoints = 20;
input int    InpTrailDistancePoints   = 15;
input ulong  InpMagic                 = 2026080802;

//=========================== SAFETY V1 =============================
input int    InpMaxSpreadPoints       = 0;    // 0 = disabled
input int    InpMaxConsecutiveErrors  = 3;
input bool   InpHaltOnInconsistentState = true;

//========================= V2 DAILY LIMITS =========================
// All limits are in account currency. 0 = disabled.
input double InpDailyProfitTarget     = 0.0;  // normal daily target
input double InpDailyProfitHardMax    = 0.0;  // absolute profit ceiling
input double InpDailyLossLimit        = 0.0;  // positive number
input bool   InpCloseOnDailyLoss      = false;

// Optional frequency limits. Disabled by default so V1 behaviour stays intact.
input int    InpMaxTradesPerDay       = 0;
input int    InpMaxReversalsPerDay    = 0;

//============================= STATE ===============================
enum EA_STATE
{
   STATE_INIT = 0,
   STATE_BUY  = 1,
   STATE_SELL = 2,
   STATE_HALT = 3
};

EA_STATE state = STATE_INIT;
string sym = "";
int digits_count = 0;
double point_size = 0.0;

int consecutive_errors = 0;
datetime day_stamp = 0;
double day_start_equity = 0.0;
int day_trades = 0;
int day_reversals = 0;
datetime last_entry_time = 0;

ulong active_position_ticket = 0;
double highest_since_entry = 0.0;
double lowest_since_entry = 0.0;

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
long DayKey(const datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return (long)dt.year * 10000 + (long)dt.mon * 100 + dt.day;
}

//+------------------------------------------------------------------+
void ResetDayIfNeeded()
{
   datetime now = TimeCurrent();
   if(day_stamp == 0 || DayKey(now) != DayKey(day_stamp))
   {
      day_stamp = now;
      day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      day_trades = 0;
      day_reversals = 0;
      last_entry_time = 0;
      consecutive_errors = 0;
      if(state == STATE_HALT)
         state = STATE_INIT;

      PrintFormat("[V2] New day | start equity=%.2f", day_start_equity);
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
void Halt(const string reason)
{
   if(state != STATE_HALT)
      PrintFormat("[V2][HALT] %s", reason);
   state = STATE_HALT;
}

//+------------------------------------------------------------------+
void RegisterError(const string where)
{
   consecutive_errors++;
   PrintFormat("[V2][ERROR] %s | retcode=%u | %s | count=%d",
               where,
               trade.ResultRetcode(),
               trade.ResultRetcodeDescription(),
               consecutive_errors);

   if(InpMaxConsecutiveErrors > 0 && consecutive_errors >= InpMaxConsecutiveErrors)
      Halt("Maximum consecutive trade errors reached");
}

//+------------------------------------------------------------------+
void ClearErrors()
{
   consecutive_errors = 0;
}

//+------------------------------------------------------------------+
bool TradeRetcodeOK()
{
   uint rc = trade.ResultRetcode();
   return (rc == TRADE_RETCODE_DONE ||
           rc == TRADE_RETCODE_DONE_PARTIAL ||
           rc == TRADE_RETCODE_PLACED ||
           rc == TRADE_RETCODE_NO_CHANGES);
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
   return spread_points <= InpMaxSpreadPoints;
}

//+------------------------------------------------------------------+
bool HasOurPosition(ENUM_POSITION_TYPE &ptype, ulong &ticket)
{
   int found = 0;
   ticket = 0;
   ptype = POSITION_TYPE_BUY;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !PositionSelectByTicket(t))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != sym)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      found++;
      ticket = t;
      ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   }

   if(found > 1)
   {
      if(InpHaltOnInconsistentState)
         Halt("More than one EA position detected");
      return false;
   }

   return found == 1;
}

//+------------------------------------------------------------------+
int PendingCount(const ENUM_ORDER_TYPE wanted)
{
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != sym)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == wanted)
         count++;
   }

   return count;
}

//+------------------------------------------------------------------+
ulong FindPending(const ENUM_ORDER_TYPE wanted)
{
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != sym)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == wanted)
         return ticket;
   }

   return 0;
}

//+------------------------------------------------------------------+
bool DeletePending(const ENUM_ORDER_TYPE wanted)
{
   bool ok = true;

   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != sym)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != wanted)
         continue;

      if(!trade.OrderDelete(ticket) || !TradeRetcodeOK())
      {
         RegisterError("OrderDelete");
         ok = false;
      }
      else
         ClearErrors();
   }

   return ok;
}

//+------------------------------------------------------------------+
bool BrokerDistanceOK(const ENUM_ORDER_TYPE type, const double price)
{
   MqlTick tick;
   if(!SymbolInfoTick(sym, tick))
      return false;

   long stops  = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_distance = (double)MathMax(stops, freeze) * point_size;

   if(type == ORDER_TYPE_BUY_STOP)
      return price >= tick.ask + min_distance;

   if(type == ORDER_TYPE_SELL_STOP)
      return price <= tick.bid - min_distance;

   return false;
}

//+------------------------------------------------------------------+
bool PlaceInitialOrders()
{
   if(!SpreadOK())
      return false;

   MqlTick tick;
   if(!SymbolInfoTick(sym, tick))
      return false;

   double buy_price  = NormPrice(tick.ask + InpInitialDistancePoints * point_size);
   double sell_price = NormPrice(tick.bid - InpInitialDistancePoints * point_size);

   if(BrokerDistanceOK(ORDER_TYPE_BUY_STOP, buy_price) && PendingCount(ORDER_TYPE_BUY_STOP) == 0)
   {
      if(!trade.BuyStop(InpLot, buy_price, sym, 0.0, 0.0,
                        ORDER_TIME_GTC, 0, "V2_INIT_BUY") || !TradeRetcodeOK())
      {
         RegisterError("Initial BuyStop");
         return false;
      }
      ClearErrors();
   }

   if(BrokerDistanceOK(ORDER_TYPE_SELL_STOP, sell_price) && PendingCount(ORDER_TYPE_SELL_STOP) == 0)
   {
      if(!trade.SellStop(InpLot, sell_price, sym, 0.0, 0.0,
                         ORDER_TIME_GTC, 0, "V2_INIT_SELL") || !TradeRetcodeOK())
      {
         RegisterError("Initial SellStop");
         return false;
      }
      ClearErrors();
   }

   state = STATE_INIT;
   return true;
}

//+------------------------------------------------------------------+
bool ModifyOrCreateOpposite(const ENUM_ORDER_TYPE type, const double desired)
{
   double price = NormPrice(desired);
   if(!BrokerDistanceOK(type, price))
      return false;

   ulong ticket = FindPending(type);

   if(ticket != 0)
   {
      if(!OrderSelect(ticket))
         return false;

      double current = OrderGetDouble(ORDER_PRICE_OPEN);
      bool should_move = false;

      if(type == ORDER_TYPE_SELL_STOP)
         should_move = price > current + point_size * 0.5;
      else if(type == ORDER_TYPE_BUY_STOP)
         should_move = price < current - point_size * 0.5;

      if(!should_move)
         return true;

      if(!trade.OrderModify(ticket, price, 0.0, 0.0,
                            ORDER_TIME_GTC, 0, 0.0) || !TradeRetcodeOK())
      {
         RegisterError("Modify opposite pending");
         return false;
      }

      ClearErrors();
      return true;
   }

   if(PendingCount(type) > 0)
      return false;

   bool ok = false;
   if(type == ORDER_TYPE_SELL_STOP)
      ok = trade.SellStop(InpLot, price, sym, 0.0, 0.0,
                          ORDER_TIME_GTC, 0, "V2_REV_SELL");
   else if(type == ORDER_TYPE_BUY_STOP)
      ok = trade.BuyStop(InpLot, price, sym, 0.0, 0.0,
                         ORDER_TIME_GTC, 0, "V2_REV_BUY");

   if(!ok || !TradeRetcodeOK())
   {
      RegisterError("Create opposite pending");
      return false;
   }

   ClearErrors();
   return true;
}

//+------------------------------------------------------------------+
void ManageBuy()
{
   MqlTick tick;
   if(!SymbolInfoTick(sym, tick))
      return;

   if(highest_since_entry <= 0.0)
      highest_since_entry = tick.bid;

   if(tick.bid > highest_since_entry)
      highest_since_entry = tick.bid;

   double level = highest_since_entry - InpTrailDistancePoints * point_size;
   ModifyOrCreateOpposite(ORDER_TYPE_SELL_STOP, level);
}

//+------------------------------------------------------------------+
void ManageSell()
{
   MqlTick tick;
   if(!SymbolInfoTick(sym, tick))
      return;

   if(lowest_since_entry <= 0.0)
      lowest_since_entry = tick.ask;

   if(tick.ask < lowest_since_entry)
      lowest_since_entry = tick.ask;

   double level = lowest_since_entry + InpTrailDistancePoints * point_size;
   ModifyOrCreateOpposite(ORDER_TYPE_BUY_STOP, level);
}

//+------------------------------------------------------------------+
void SyncPositionState()
{
   ENUM_POSITION_TYPE ptype;
   ulong ticket;
   bool has_position = HasOurPosition(ptype, ticket);

   if(state == STATE_HALT)
      return;

   if(has_position)
   {
      active_position_ticket = ticket;

      if(ptype == POSITION_TYPE_BUY)
      {
         if(state != STATE_BUY)
         {
            state = STATE_BUY;
            highest_since_entry = PositionGetDouble(POSITION_PRICE_OPEN);
            lowest_since_entry = 0.0;
            DeletePending(ORDER_TYPE_BUY_STOP);
         }
      }
      else
      {
         if(state != STATE_SELL)
         {
            state = STATE_SELL;
            lowest_since_entry = PositionGetDouble(POSITION_PRICE_OPEN);
            highest_since_entry = 0.0;
            DeletePending(ORDER_TYPE_SELL_STOP);
         }
      }
      return;
   }

   active_position_ticket = 0;
   highest_since_entry = 0.0;
   lowest_since_entry = 0.0;

   int buy_count  = PendingCount(ORDER_TYPE_BUY_STOP);
   int sell_count = PendingCount(ORDER_TYPE_SELL_STOP);

   if(buy_count > 1 || sell_count > 1)
   {
      if(InpHaltOnInconsistentState)
         Halt("Duplicate pending orders detected");
      return;
   }

   // Initial state: both pending orders are required.
   if(buy_count == 1 && sell_count == 1)
   {
      state = STATE_INIT;
      return;
   }

   // A partial initial state is not repaired blindly.
   if(buy_count == 1 || sell_count == 1)
   {
      if(InpHaltOnInconsistentState)
         Halt("Only one initial pending order exists without a position");
      return;
   }

   state = STATE_INIT;
}

//+------------------------------------------------------------------+
void ApplyDailyLimits()
{
   if(state == STATE_HALT)
      return;

   double pnl = DailyPnL();
   bool stop = false;
   string reason = "";

   if(InpDailyLossLimit > 0.0 && pnl <= -InpDailyLossLimit)
   {
      stop = true;
      reason = "Daily loss limit reached";
   }
   else if(InpDailyProfitHardMax > 0.0 && pnl >= InpDailyProfitHardMax)
   {
      stop = true;
      reason = "Daily profit hard cap reached";
   }
   else if(InpDailyProfitTarget > 0.0 && pnl >= InpDailyProfitTarget)
   {
      stop = true;
      reason = "Daily profit target reached";
   }
   else if(InpMaxTradesPerDay > 0 && day_trades >= InpMaxTradesPerDay)
   {
      stop = true;
      reason = "Maximum daily trades reached";
   }
   else if(InpMaxReversalsPerDay > 0 && day_reversals >= InpMaxReversalsPerDay)
   {
      stop = true;
      reason = "Maximum daily reversals reached";
   }

   if(!stop)
      return;

   PrintFormat("[V2] %s | daily PnL=%.2f", reason, pnl);

   // Stop new entries immediately. Existing V1 position is not closed
   // on profit target; it remains protected by the V1 reversal mechanism.
   DeletePending(ORDER_TYPE_BUY_STOP);
   DeletePending(ORDER_TYPE_SELL_STOP);

   if(InpCloseOnDailyLoss && InpDailyLossLimit > 0.0 && pnl <= -InpDailyLossLimit)
   {
      ENUM_POSITION_TYPE ptype;
      ulong ticket;
      if(HasOurPosition(ptype, ticket))
      {
         if(!trade.PositionClose(ticket) || !TradeRetcodeOK())
            RegisterError("Emergency close on daily loss");
         else
            ClearErrors();
      }
   }

   Halt(reason);
}

//+------------------------------------------------------------------+
void HandleEntryFromTransaction(const MqlTradeTransaction &trans)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(trans.deal == 0 || !HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != sym)
      return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
      return;

   long deal_type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   double deal_price = HistoryDealGetDouble(trans.deal, DEAL_PRICE);

   day_trades++;
   if(last_entry_time > 0)
      day_reversals++;
   last_entry_time = TimeCurrent();

   if(deal_type == DEAL_TYPE_BUY)
   {
      state = STATE_BUY;
      highest_since_entry = deal_price;
      lowest_since_entry = 0.0;
      DeletePending(ORDER_TYPE_BUY_STOP);
   }
   else if(deal_type == DEAL_TYPE_SELL)
   {
      state = STATE_SELL;
      lowest_since_entry = deal_price;
      highest_since_entry = 0.0;
      DeletePending(ORDER_TYPE_SELL_STOP);
   }

   PrintFormat("[V2] ENTRY | trades=%d | reversals=%d | price=%.*f",
               day_trades, day_reversals, PriceDigits(), deal_price);
}

//+------------------------------------------------------------------+
int OnInit()
{
   sym = (InpSymbol == "" ? _Symbol : InpSymbol);

   if(!SymbolSelect(sym, true))
      return INIT_FAILED;

   digits_count = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   point_size = SymbolInfoDouble(sym, SYMBOL_POINT);

   if(point_size <= 0.0 || InpLot <= 0.0 ||
      InpInitialDistancePoints <= 0 || InpTrailDistancePoints <= 0)
      return INIT_PARAMETERS_INCORRECT;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(sym);

   ResetDayIfNeeded();
   state = STATE_INIT;
   SyncPositionState();

   PrintFormat("[V2] READY | V1 core preserved | lot=%.2f | initial=%d pts | trail=%d pts",
               InpLot, InpInitialDistancePoints, InpTrailDistancePoints);
   Print("[V2] No range filter. No BOS/CHoCH/SMC. Daily limits only added.");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   ResetDayIfNeeded();

   if(state == STATE_HALT)
      return;

   ApplyDailyLimits();
   if(state == STATE_HALT)
      return;

   SyncPositionState();
   if(state == STATE_HALT)
      return;

   ENUM_POSITION_TYPE ptype;
   ulong ticket;
   bool has_position = HasOurPosition(ptype, ticket);

   if(has_position)
   {
      if(ptype == POSITION_TYPE_BUY)
         ManageBuy();
      else
         ManageSell();
      return;
   }

   // V1 initial mechanism: both sides are placed whenever there is no position.
   if(state == STATE_INIT)
      PlaceInitialOrders();
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   HandleEntryFromTransaction(trans);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   PrintFormat("[V2] STOP | reason=%d | daily PnL=%.2f | trades=%d | reversals=%d",
               reason, DailyPnL(), day_trades, day_reversals);
}
//+------------------------------------------------------------------+
