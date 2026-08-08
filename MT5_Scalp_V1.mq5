#property strict
#property version   "1.0"
#property description "V1: alternating BUY/SELL stop cycle with trailing opposite stop and safety manager"

#include <Trade/Trade.mqh>
CTrade trade;

enum EA_STATE
  {
   STATE_INIT=0,
   STATE_BUY=1,
   STATE_SELL=2,
   STATE_HALT=3
  };

input string InpSymbol="";
input double InpLot=0.01;
input int    InpInitialDistancePoints=20;
input int    InpTrailDistancePoints=15;
input ulong  InpMagic=26080801;
input int    InpMaxSpreadPoints=0;          // 0 = disabled
input int    InpMaxConsecutiveErrors=3;
input int    InpMaxReversals=0;             // 0 = disabled
input double InpMaxDailyLossMoney=0.0;      // 0 = disabled
input double InpMaxFloatingLossMoney=0.0;   // 0 = disabled
input bool   InpRequireHedgingAccount=true;
input bool   InpHaltOnStateMismatch=true;
input int    InpTradeDeviationPoints=20;
input bool   InpUseTradingHours=false;
input int    InpStartHour=0;
input int    InpEndHour=23;

string sym;
EA_STATE state=STATE_INIT;
double extreme=0.0;
int consecutive_errors=0;
int reversals=0;
bool halted=false;
datetime last_action=0;

// ---------- basic helpers ----------

double P(){ return SymbolInfoDouble(sym,SYMBOL_POINT); }
int PriceDigits(){ return (int)SymbolInfoInteger(sym,SYMBOL_DIGITS); }
double Norm(double price){ return NormalizeDouble(price,PriceDigits()); }

double Bid(){ return SymbolInfoDouble(sym,SYMBOL_BID); }
double Ask(){ return SymbolInfoDouble(sym,SYMBOL_ASK); }

int StopLevelPoints()
  {
   int a=(int)SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL);
   int b=(int)SymbolInfoInteger(sym,SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax(a,b);
  }

bool IsHedging()
  {
   long mode=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   return mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
  }

bool InHours()
  {
   if(!InpUseTradingHours) return true;
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   if(InpStartHour<=InpEndHour) return t.hour>=InpStartHour && t.hour<=InpEndHour;
   return t.hour>=InpStartHour || t.hour<=InpEndHour;
  }

bool SpreadOK()
  {
   if(InpMaxSpreadPoints<=0) return true;
   double sp=(Ask()-Bid())/P();
   return sp<=InpMaxSpreadPoints;
  }

bool TradingEnvironmentOK()
  {
   if(halted) return false;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return false;
   if(!SymbolInfoInteger(sym,SYMBOL_TRADE_MODE)) return false;
   if(!SpreadOK()) return false;
   if(!InHours()) return false;
   return true;
  }

void LogError(string where)
  {
   consecutive_errors++;
   PrintFormat("[V1][ERROR] %s | retcode=%u | %s | consecutive=%d",
               where,trade.ResultRetcode(),trade.ResultRetcodeDescription(),consecutive_errors);
   if(consecutive_errors>=InpMaxConsecutiveErrors)
      Halt("too many consecutive trade errors");
  }

void ResetErrors(){ consecutive_errors=0; }

void Halt(string reason)
  {
   if(halted) return;
   halted=true;
   state=STATE_HALT;
   Print("[V1][HALT] ",reason);
  }

// ---------- order/position discovery ----------

int OurPendingCount(ENUM_ORDER_TYPE wanted=(ENUM_ORDER_TYPE)-1)
  {
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || !OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=sym) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_SELL_STOP)
        {
         if((int)wanted==-1 || type==wanted) n++;
        }
     }
   return n;
  }

ulong FindPending(ENUM_ORDER_TYPE wanted)
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || !OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=sym) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)==wanted) return ticket;
     }
   return 0;
  }

int OurPositionsCount()
  {
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      n++;
     }
   return n;
  }

bool FindPosition(ENUM_POSITION_TYPE type,ulong &ticket,double &open_price)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=type) continue;
      ticket=t; open_price=PositionGetDouble(POSITION_PRICE_OPEN); return true;
     }
   return false;
  }

void DeletePending(ENUM_ORDER_TYPE type)
  {
   ulong t=FindPending(type);
   if(t==0) return;
   if(!trade.OrderDelete(t)) LogError("OrderDelete"); else ResetErrors();
  }

void DeleteAllOurPendings()
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong t=OrderGetTicket(i);
      if(t==0 || !OrderSelect(t)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=sym) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type!=ORDER_TYPE_BUY_STOP && type!=ORDER_TYPE_SELL_STOP) continue;
      if(!trade.OrderDelete(t)) LogError("DeleteAllOurPendings"); else ResetErrors();
     }
  }

// ---------- broker-safe level validation ----------

bool ValidBuyStop(double price)
  {
   return price>Ask()+StopLevelPoints()*P();
  }

bool ValidSellStop(double price)
  {
   return price<Bid()-StopLevelPoints()*P();
  }

bool ValidSLForBuy(double price)
  {
   return price<Bid()-StopLevelPoints()*P();
  }

bool ValidSLForSell(double price)
  {
   return price>Ask()+StopLevelPoints()*P();
  }

// ---------- initial cycle ----------

bool PlaceInitialPendings()
  {
   if(!TradingEnvironmentOK()) return false;
   if(OurPositionsCount()!=0) return false;
   if(OurPendingCount()!=0) return true;

   double buy=Norm(Ask()+InpInitialDistancePoints*P());
   double sell=Norm(Bid()-InpInitialDistancePoints*P());
   if(!ValidBuyStop(buy) || !ValidSellStop(sell))
     {
      Halt("initial pending distance is below broker minimum");
      return false;
     }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpTradeDeviationPoints);
   bool ok1=trade.BuyStop(InpLot,buy,sym,0,0,ORDER_TIME_GTC,0,"V1_INIT_BUY");
   if(!ok1){ LogError("Initial BuyStop"); return false; }
   ResetErrors();

   bool ok2=trade.SellStop(InpLot,sell,sym,0,0,ORDER_TIME_GTC,0,"V1_INIT_SELL");
   if(!ok2)
     {
      LogError("Initial SellStop");
      DeletePending(ORDER_TYPE_BUY_STOP);
      return false;
     }
   ResetErrors();
   PrintFormat("[V1] INITIALIZED | BuyStop=%.*f SellStop=%.*f",PriceDigits(),buy,PriceDigits(),sell);
   return true;
  }

// ---------- active side ----------

bool OpenOrRecoverSide()
  {
   ulong bt=0,st=0; double bo=0,so=0;
   bool hasBuy=FindPosition(POSITION_TYPE_BUY,bt,bo);
   bool hasSell=FindPosition(POSITION_TYPE_SELL,st,so);

   if(hasBuy && hasSell)
     {
      Halt("both BUY and SELL positions exist");
      return false;
     }

   if(hasBuy)
     {
      if(state!=STATE_BUY){ state=STATE_BUY; extreme=bo; Print("[V1] RECOVER BUY state"); }
      DeletePending(ORDER_TYPE_BUY_STOP);
      return true;
     }
   if(hasSell)
     {
      if(state!=STATE_SELL){ state=STATE_SELL; extreme=so; Print("[V1] RECOVER SELL state"); }
      DeletePending(ORDER_TYPE_SELL_STOP);
      return true;
     }
   return false;
  }

bool ModifyBuyProtection(ulong pos_ticket,double stop_level)
  {
   ulong pending=FindPending(ORDER_TYPE_SELL_STOP);
   if(pending==0)
     {
      if(!trade.SellStop(InpLot,stop_level,sym,0,0,ORDER_TIME_GTC,0,"V1_SELL_REVERSAL"))
        { LogError("Create SellStop"); return false; }
      ResetErrors();
     }
   else
     {
      if(!OrderSelect(pending)) { LogError("Select SellStop"); return false; }
      double old=OrderGetDouble(ORDER_PRICE_OPEN);
      if(stop_level<old-P()/2.0)
        {
         if(!trade.OrderModify(pending,stop_level,0,0,ORDER_TIME_GTC,0,0))
           { LogError("Modify SellStop"); return false; }
         ResetErrors();
        }
     }

   if(!trade.PositionModify(pos_ticket,stop_level,0))
     { LogError("Set BUY SL"); return false; }
   ResetErrors();
   return true;
  }

bool ModifySellProtection(ulong pos_ticket,double stop_level)
  {
   ulong pending=FindPending(ORDER_TYPE_BUY_STOP);
   if(pending==0)
     {
      if(!trade.BuyStop(InpLot,stop_level,sym,0,0,ORDER_TIME_GTC,0,"V1_BUY_REVERSAL"))
        { LogError("Create BuyStop"); return false; }
      ResetErrors();
     }
   else
     {
      if(!OrderSelect(pending)) { LogError("Select BuyStop"); return false; }
      double old=OrderGetDouble(ORDER_PRICE_OPEN);
      if(stop_level>old+P()/2.0)
        {
         if(!trade.OrderModify(pending,stop_level,0,0,ORDER_TIME_GTC,0,0))
           { LogError("Modify BuyStop"); return false; }
         ResetErrors();
        }
     }

   if(!trade.PositionModify(pos_ticket,stop_level,0))
     { LogError("Set SELL SL"); return false; }
   ResetErrors();
   return true;
  }

void ManageBuy()
  {
   ulong ticket=0; double open=0;
   if(!FindPosition(POSITION_TYPE_BUY,ticket,open)) return;
   state=STATE_BUY;

   if(extreme<=0) extreme=open;
   if(Bid()>extreme) extreme=Bid();

   double level=Norm(extreme-InpTrailDistancePoints*P());
   if(!ValidSellStop(level) || !ValidSLForBuy(level)) return;
   ModifyBuyProtection(ticket,level);
  }

void ManageSell()
  {
   ulong ticket=0; double open=0;
   if(!FindPosition(POSITION_TYPE_SELL,ticket,open)) return;
   state=STATE_SELL;

   if(extreme<=0) extreme=open;
   if(Ask()<extreme) extreme=Ask();

   double level=Norm(extreme+InpTrailDistancePoints*P());
   if(!ValidBuyStop(level) || !ValidSLForSell(level)) return;
   ModifySellProtection(ticket,level);
  }

// ---------- safety ----------

double TodayClosedPnL()
  {
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   t.hour=0; t.min=0; t.sec=0;
   datetime start=StructToTime(t);
   if(!HistorySelect(start,TimeCurrent())) return 0;
   double pnl=0;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=sym) continue;
      if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagic) continue;
      long entry=HistoryDealGetInteger(d,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
        pnl+=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)+HistoryDealGetDouble(d,DEAL_COMMISSION);
     }
   return pnl;
  }

bool SafetyLimitsOK()
  {
   if(InpMaxDailyLossMoney>0 && TodayClosedPnL()<=-MathAbs(InpMaxDailyLossMoney))
     { Halt("maximum daily loss reached"); return false; }

   if(InpMaxFloatingLossMoney>0)
     {
      double floating=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(t==0 || !PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
         floating+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
        }
      if(floating<=-MathAbs(InpMaxFloatingLossMoney))
        { Halt("maximum floating loss reached"); return false; }
     }

   if(InpMaxReversals>0 && reversals>=InpMaxReversals)
     { Halt("maximum reversals reached"); return false; }
   return true;
  }

bool ValidateState()
  {
   int pos=OurPositionsCount();
   int pend=OurPendingCount();

   if(pos>1)
     { Halt("more than one managed position"); return false; }

   if(pos==0 && pend>2)
     { Halt("too many initial pending orders"); return false; }

   if(pos==1 && pend>1)
     { Halt("more than one pending order while position is active"); return false; }

   if(pos==0 && pend==1)
     {
      if(InpHaltOnStateMismatch)
        { Halt("orphan pending order"); return false; }
     }
   return true;
  }

// ---------- event handling ----------

void DetectNewSide()
  {
   ulong b=0,s=0; double bp=0,sp=0;
   bool hasB=FindPosition(POSITION_TYPE_BUY,b,bp);
   bool hasS=FindPosition(POSITION_TYPE_SELL,s,sp);

   if(hasB && !hasS)
     {
      if(state==STATE_SELL) reversals++;
      state=STATE_BUY;
      if(extreme<=0) extreme=bp;
      DeletePending(ORDER_TYPE_SELL_STOP);
      DeletePending(ORDER_TYPE_BUY_STOP);
      if(extreme<=0) extreme=bp;
     }
   else if(hasS && !hasB)
     {
      if(state==STATE_BUY) reversals++;
      state=STATE_SELL;
      if(extreme<=0) extreme=sp;
      DeletePending(ORDER_TYPE_BUY_STOP);
      DeletePending(ORDER_TYPE_SELL_STOP);
      if(extreme<=0) extreme=sp;
     }
  }

int OnInit()
  {
   sym=(InpSymbol=="" ? _Symbol : InpSymbol);
   if(!SymbolSelect(sym,true)) return INIT_FAILED;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpTradeDeviationPoints);

   if(InpLot<=0 || InpInitialDistancePoints<=0 || InpTrailDistancePoints<=0) return INIT_PARAMETERS_INCORRECT;
   if(InpMaxConsecutiveErrors<1) return INIT_PARAMETERS_INCORRECT;

   if(InpRequireHedgingAccount && !IsHedging())
     {
      Print("[V1][HALT] This EA requires a HEDGING MT5 account.");
      halted=true; state=STATE_HALT;
      return INIT_SUCCEEDED;
     }

   PrintFormat("[V1] START | %s | lot=%.2f | initial=%d pts | trail=%d pts",sym,InpLot,InpInitialDistancePoints,InpTrailDistancePoints);
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   if(halted) return;
   if(!SafetyLimitsOK()) return;
   if(!ValidateState()) return;

   bool hasSide=OpenOrRecoverSide();
   if(hasSide)
     {
      DetectNewSide();
      if(state==STATE_BUY) ManageBuy();
      else if(state==STATE_SELL) ManageSell();
      return;
     }

   if(OurPendingCount()==0)
     {
      extreme=0;
      state=STATE_INIT;
      PlaceInitialPendings();
     }
   else if(OurPendingCount()==2)
     {
      state=STATE_INIT;
     }
   else if(InpHaltOnStateMismatch)
     {
      Halt("unexpected no-position pending state");
     }
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(halted) return;
   if(trans.symbol!=sym) return;
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD || trans.type==TRADE_TRANSACTION_ORDER_ADD || trans.type==TRADE_TRANSACTION_ORDER_DELETE)
      PrintFormat("[V1][TRADE] transaction type=%d order=%I64u deal=%I64u",trans.type,trans.order,trans.deal);
  }

void OnDeinit(const int reason)
  {
   PrintFormat("[V1] STOP | reason=%d | state=%d | reversals=%d | dailyClosedPnL=%.2f",reason,state,reversals,TodayClosedPnL());
  }
