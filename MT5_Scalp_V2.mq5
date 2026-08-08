//+------------------------------------------------------------------+
//| MT5_Scalp_V2.mq5                                                 |
//| V2 = V1 EXACT CORE + daily profit/loss protections               |
//| NO range filter / NO BOS / NO CHoCH / NO SMC                    |
//+------------------------------------------------------------------+
#property strict
#property version "2.12"
#include <Trade/Trade.mqh>
CTrade trade;

input string InpSymbol="";
input double InpLot=0.01;
input int InpInitialDistancePoints=20;
input int InpTrailDistancePoints=15;
input ulong InpMagic=2026080802;

// V1 safety
input int InpMaxSpreadPoints=0;
input int InpMaxConsecutiveErrors=3;
input bool InpHaltOnInconsistentState=true;

// V2 daily stop limits, account currency. 0 = disabled.
// As soon as the daily P&L reaches OR exceeds a limit, the EA stops.
input double InpDailyProfitTarget=0.0;
input double InpDailyLossLimit=0.0;
input bool InpCloseOnDailyProfit=true;
input bool InpCloseOnDailyLoss=true;

// Optional limits, disabled by default to preserve V1 frequency.
input int InpMaxTradesPerDay=0;
input int InpMaxReversalsPerDay=0;

enum EA_STATE { STATE_INIT=0, STATE_BUY=1, STATE_SELL=2, STATE_HALT=3 };
EA_STATE state=STATE_INIT;
string sym="";
int digits_count=0;
double point_size=0.0;
int consecutive_errors=0;
datetime day_stamp=0;
double day_start_equity=0.0;
int day_trades=0;
int day_reversals=0;
datetime last_entry_time=0;
double highest_since_entry=0.0;
double lowest_since_entry=0.0;
ulong active_position_ticket=0;

int PriceDigits(){return digits_count;}
double NormPrice(double p){return NormalizeDouble(p,PriceDigits());}
long DayKey(datetime t){MqlDateTime d;TimeToStruct(t,d);return (long)d.year*10000+(long)d.mon*100+d.day;}

void Halt(string reason){if(state!=STATE_HALT)PrintFormat("[V2][HALT] %s",reason);state=STATE_HALT;}
void ClearErrors(){consecutive_errors=0;}
void RegisterError(string where){consecutive_errors++;PrintFormat("[V2][ERROR] %s | retcode=%u | %s | count=%d",where,trade.ResultRetcode(),trade.ResultRetcodeDescription(),consecutive_errors);if(InpMaxConsecutiveErrors>0&&consecutive_errors>=InpMaxConsecutiveErrors)Halt("Maximum consecutive trade errors reached");}
bool TradeRetcodeOK(){uint r=trade.ResultRetcode();return r==TRADE_RETCODE_DONE||r==TRADE_RETCODE_DONE_PARTIAL||r==TRADE_RETCODE_PLACED||r==TRADE_RETCODE_NO_CHANGES;}

void ResetDayIfNeeded(){datetime now=TimeCurrent();if(day_stamp==0||DayKey(now)!=DayKey(day_stamp)){day_stamp=now;day_start_equity=AccountInfoDouble(ACCOUNT_EQUITY);day_trades=0;day_reversals=0;last_entry_time=0;consecutive_errors=0;if(state==STATE_HALT)state=STATE_INIT;PrintFormat("[V2] New day | start equity=%.2f",day_start_equity);}}
double DailyPnL(){return day_start_equity>0.0?AccountInfoDouble(ACCOUNT_EQUITY)-day_start_equity:0.0;}

bool SpreadOK(){if(InpMaxSpreadPoints<=0)return true;MqlTick t;if(!SymbolInfoTick(sym,t))return false;return (t.ask-t.bid)/point_size<=InpMaxSpreadPoints;}

bool HasOurPosition(ENUM_POSITION_TYPE &ptype,ulong &ticket){int found=0;ticket=0;ptype=POSITION_TYPE_BUY;for(int i=PositionsTotal()-1;i>=0;--i){ulong t=PositionGetTicket(i);if(!t||!PositionSelectByTicket(t))continue;if(PositionGetString(POSITION_SYMBOL)!=sym)continue;if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic)continue;found++;ticket=t;ptype=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);}if(found>1){if(InpHaltOnInconsistentState)Halt("More than one EA position detected");return false;}return found==1;}

int PendingCount(ENUM_ORDER_TYPE wanted){int n=0;for(int i=OrdersTotal()-1;i>=0;--i){ulong t=OrderGetTicket(i);if(!t||!OrderSelect(t))continue;if(OrderGetString(ORDER_SYMBOL)!=sym)continue;if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic)continue;if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)==wanted)n++;}return n;}
ulong FindPending(ENUM_ORDER_TYPE wanted){for(int i=OrdersTotal()-1;i>=0;--i){ulong t=OrderGetTicket(i);if(!t||!OrderSelect(t))continue;if(OrderGetString(ORDER_SYMBOL)!=sym)continue;if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic)continue;if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)==wanted)return t;}return 0;}

bool DeletePending(ENUM_ORDER_TYPE wanted){bool ok=true;for(int i=OrdersTotal()-1;i>=0;--i){ulong t=OrderGetTicket(i);if(!t||!OrderSelect(t))continue;if(OrderGetString(ORDER_SYMBOL)!=sym)continue;if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic)continue;if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)!=wanted)continue;if(!trade.OrderDelete(t)||!TradeRetcodeOK()){RegisterError("OrderDelete");ok=false;}else ClearErrors();}return ok;}

bool BrokerDistanceOK(ENUM_ORDER_TYPE type,double price){MqlTick t;if(!SymbolInfoTick(sym,t))return false;long stops=SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL);long freeze=SymbolInfoInteger(sym,SYMBOL_TRADE_FREEZE_LEVEL);double d=(double)MathMax(stops,freeze)*point_size;if(type==ORDER_TYPE_BUY_STOP)return price>=t.ask+d;if(type==ORDER_TYPE_SELL_STOP)return price<=t.bid-d;return false;}

bool PlaceInitialOrders(){if(!SpreadOK())return false;MqlTick t;if(!SymbolInfoTick(sym,t))return false;double buy=NormPrice(t.ask+InpInitialDistancePoints*point_size);double sell=NormPrice(t.bid-InpInitialDistancePoints*point_size);if(PendingCount(ORDER_TYPE_BUY_STOP)==0&&BrokerDistanceOK(ORDER_TYPE_BUY_STOP,buy)){if(!trade.BuyStop(InpLot,buy,sym,0,0,ORDER_TIME_GTC,0,"V2_INIT_BUY")||!TradeRetcodeOK()){RegisterError("Initial BuyStop");return false;}ClearErrors();}if(PendingCount(ORDER_TYPE_SELL_STOP)==0&&BrokerDistanceOK(ORDER_TYPE_SELL_STOP,sell)){if(!trade.SellStop(InpLot,sell,sym,0,0,ORDER_TIME_GTC,0,"V2_INIT_SELL")||!TradeRetcodeOK()){RegisterError("Initial SellStop");return false;}ClearErrors();}state=STATE_INIT;return true;}

bool ModifyOrCreateOpposite(ENUM_ORDER_TYPE type,double desired){double price=NormPrice(desired);if(!BrokerDistanceOK(type,price))return false;ulong ticket=FindPending(type);if(ticket){if(!OrderSelect(ticket))return false;double old=OrderGetDouble(ORDER_PRICE_OPEN);bool move=(type==ORDER_TYPE_SELL_STOP)?price>old+point_size*0.5:price<old-point_size*0.5;if(!move)return true;if(!trade.OrderModify(ticket,price,0,0,ORDER_TIME_GTC,0,0)||!TradeRetcodeOK()){RegisterError("Modify opposite pending");return false;}ClearErrors();return true;}if(PendingCount(type)>0)return false;bool ok=false;if(type==ORDER_TYPE_SELL_STOP)ok=trade.SellStop(InpLot,price,sym,0,0,ORDER_TIME_GTC,0,"V2_REV_SELL");else if(type==ORDER_TYPE_BUY_STOP)ok=trade.BuyStop(InpLot,price,sym,0,0,ORDER_TIME_GTC,0,"V2_REV_BUY");if(!ok||!TradeRetcodeOK()){RegisterError("Create opposite pending");return false;}ClearErrors();return true;}

void ManageBuy(){MqlTick t;if(!SymbolInfoTick(sym,t))return;if(highest_since_entry<=0)highest_since_entry=t.bid;if(t.bid>highest_since_entry)highest_since_entry=t.bid;ModifyOrCreateOpposite(ORDER_TYPE_SELL_STOP,highest_since_entry-InpTrailDistancePoints*point_size);}
void ManageSell(){MqlTick t;if(!SymbolInfoTick(sym,t))return;if(lowest_since_entry<=0)lowest_since_entry=t.ask;if(t.ask<lowest_since_entry)lowest_since_entry=t.ask;ModifyOrCreateOpposite(ORDER_TYPE_BUY_STOP,lowest_since_entry+InpTrailDistancePoints*point_size);}

void SyncPositionState(){if(state==STATE_HALT)return;ENUM_POSITION_TYPE pt;ulong ticket;bool has=HasOurPosition(pt,ticket);if(state==STATE_HALT)return;if(has){active_position_ticket=ticket;if(pt==POSITION_TYPE_BUY){if(state!=STATE_BUY){state=STATE_BUY;highest_since_entry=PositionGetDouble(POSITION_PRICE_OPEN);lowest_since_entry=0;DeletePending(ORDER_TYPE_BUY_STOP);}}else{if(state!=STATE_SELL){state=STATE_SELL;lowest_since_entry=PositionGetDouble(POSITION_PRICE_OPEN);highest_since_entry=0;DeletePending(ORDER_TYPE_SELL_STOP);}}return;}active_position_ticket=0;highest_since_entry=0;lowest_since_entry=0;int b=PendingCount(ORDER_TYPE_BUY_STOP),s=PendingCount(ORDER_TYPE_SELL_STOP);if(b>1||s>1){if(InpHaltOnInconsistentState)Halt("Duplicate pending orders detected");return;}if((b==1&&s==1)||(b==0&&s==0)){state=STATE_INIT;return;}if(InpHaltOnInconsistentState)Halt("Only one pending order exists without a position");}

// Daily protection: if P&L reaches OR exceeds a configured limit,
// stop the whole cycle. Overshoot is allowed; exact equality is not required.
void ApplyDailyLimits(){if(state==STATE_HALT)return;double pnl=DailyPnL();string reason="";bool limit=false;bool close_position=false;if(InpDailyLossLimit>0&&pnl<=-InpDailyLossLimit){limit=true;reason="Daily loss limit reached/exceeded";close_position=InpCloseOnDailyLoss;}else if(InpDailyProfitTarget>0&&pnl>=InpDailyProfitTarget){limit=true;reason="Daily profit target reached/exceeded";close_position=InpCloseOnDailyProfit;}else if(InpMaxTradesPerDay>0&&day_trades>=InpMaxTradesPerDay){limit=true;reason="Maximum daily trades reached";close_position=false;}else if(InpMaxReversalsPerDay>0&&day_reversals>=InpMaxReversalsPerDay){limit=true;reason="Maximum daily reversals reached";close_position=false;}if(!limit)return;PrintFormat("[V2] %s | PnL=%.2f",reason,pnl);DeletePending(ORDER_TYPE_BUY_STOP);DeletePending(ORDER_TYPE_SELL_STOP);if(close_position){ENUM_POSITION_TYPE pt;ulong ticket;if(HasOurPosition(pt,ticket)){if(!trade.PositionClose(ticket)||!TradeRetcodeOK()){RegisterError("Close position at daily limit");return;}ClearErrors();}}Halt(reason);}

void HandleEntry(const MqlTradeTransaction &trans){if(trans.type!=TRADE_TRANSACTION_DEAL_ADD||trans.deal==0||!HistoryDealSelect(trans.deal))return;if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=sym)return;if((ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic)return;if(HistoryDealGetInteger(trans.deal,DEAL_ENTRY)!=DEAL_ENTRY_IN)return;long typ=HistoryDealGetInteger(trans.deal,DEAL_TYPE);double price=HistoryDealGetDouble(trans.deal,DEAL_PRICE);day_trades++;if(last_entry_time>0)day_reversals++;last_entry_time=TimeCurrent();if(typ==DEAL_TYPE_BUY){state=STATE_BUY;highest_since_entry=price;lowest_since_entry=0;DeletePending(ORDER_TYPE_BUY_STOP);}else if(typ==DEAL_TYPE_SELL){state=STATE_SELL;lowest_since_entry=price;highest_since_entry=0;DeletePending(ORDER_TYPE_SELL_STOP);}PrintFormat("[V2] ENTRY | trades=%d | reversals=%d | price=%.*f",day_trades,day_reversals,PriceDigits(),price);ApplyDailyLimits();}

int OnInit(){sym=(InpSymbol==""?_Symbol:InpSymbol);if(!SymbolSelect(sym,true))return INIT_FAILED;digits_count=(int)SymbolInfoInteger(sym,SYMBOL_DIGITS);point_size=SymbolInfoDouble(sym,SYMBOL_POINT);if(point_size<=0||InpLot<=0||InpInitialDistancePoints<=0||InpTrailDistancePoints<=0)return INIT_PARAMETERS_INCORRECT;trade.SetExpertMagicNumber(InpMagic);trade.SetAsyncMode(false);trade.SetTypeFillingBySymbol(sym);ResetDayIfNeeded();state=STATE_INIT;SyncPositionState();PrintFormat("[V2] READY | V1 core preserved | lot=%.2f | initial=%d pts | trail=%d pts",InpLot,InpInitialDistancePoints,InpTrailDistancePoints);Print("[V2] No range filter. No BOS/CHoCH/SMC. Only daily limits added.");return INIT_SUCCEEDED;}

void OnTick(){ResetDayIfNeeded();if(state==STATE_HALT)return;ApplyDailyLimits();if(state==STATE_HALT)return;SyncPositionState();if(state==STATE_HALT)return;ENUM_POSITION_TYPE pt;ulong ticket;if(HasOurPosition(pt,ticket)){if(pt==POSITION_TYPE_BUY)ManageBuy();else ManageSell();return;}if(state==STATE_INIT)PlaceInitialOrders();}
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result){HandleEntry(trans);}
void OnDeinit(const int reason){PrintFormat("[V2] STOP | reason=%d | daily PnL=%.2f | trades=%d | reversals=%d",reason,DailyPnL(),day_trades,day_reversals);}
//+------------------------------------------------------------------+
