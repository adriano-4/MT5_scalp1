//+------------------------------------------------------------------+
//|                                                        Utils.mqh  |
//|  Generic, symbol-agnostic helper functions used everywhere.      |
//+------------------------------------------------------------------+
#ifndef __UTILS_MQH__
#define __UTILS_MQH__

//--- Convert a "points" input (broker points) to a price distance ----
double PointsToPrice(const string symbol,const double points)
  {
   double point = SymbolInfoDouble(symbol,SYMBOL_POINT);
   return points*point;
  }

//--- Normalize a price to the symbol's digit precision ----------------
double NormalizePriceEx(const string symbol,const double price)
  {
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   return NormalizeDouble(price,digits);
  }

//--- Current spread in points -------------------------------------------
double CurrentSpreadPoints(const string symbol)
  {
   double ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(symbol,SYMBOL_BID);
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   if(point<=0) return 0;
   return (ask-bid)/point;
  }

//--- New-bar detector, one instance per timeframe you track -------------
bool IsNewBar(const string symbol,ENUM_TIMEFRAMES tf,datetime &lastBarTime)
  {
   datetime t[1];
   if(CopyTime(symbol,tf,0,1,t)!=1) return false;
   if(t[0]!=lastBarTime)
     {
      lastBarTime=t[0];
      return true;
     }
   return false;
  }

//--- Safe wrapper around iHigh/iLow/iOpen/iClose that returns EMPTY_VALUE on failure --
double SafeHigh(const string symbol,ENUM_TIMEFRAMES tf,int shift)
  {
   double v=iHigh(symbol,tf,shift);
   return(v==0.0 ? EMPTY_VALUE : v);
  }
double SafeLow(const string symbol,ENUM_TIMEFRAMES tf,int shift)
  {
   double v=iLow(symbol,tf,shift);
   return(v==0.0 ? EMPTY_VALUE : v);
  }

//--- Round lot to the symbol's allowed step / min / max ------------------
double NormalizeLot(const string symbol,double lot)
  {
   double minLot  = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step=0.01;
   double steps = MathFloor(lot/step + 0.0000001);
   double norm  = steps*step;
   if(norm<minLot) norm=minLot;
   if(norm>maxLot) norm=maxLot;
   return norm;
  }

//--- Is "price" within tolerance (points) of "level" ----------------------
bool IsNear(const string symbol,double price,double level,double tolerancePoints)
  {
   double tol = PointsToPrice(symbol,tolerancePoints);
   return(MathAbs(price-level)<=tol);
  }

//--- Broker-time hour / day-of-week helpers --------------------------------
int BrokerHour()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   return dt.hour;
  }
int BrokerDOW()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   return dt.day_of_week; // 0=Sunday
  }
datetime BrokerDateOnly()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   dt.hour=0; dt.min=0; dt.sec=0;
   return StructToTime(dt);
  }

#endif // __UTILS_MQH__