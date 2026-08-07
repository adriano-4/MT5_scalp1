#ifndef __CONFIG_MQH__
#define __CONFIG_MQH__

//========================
// GENERAL
//========================

input long MagicNumber = 990011;

input ENUM_TIMEFRAMES TradeTF = PERIOD_M1;

input int MaxOpenTrades = 2;

//========================
// MONEY MANAGEMENT
//========================

input bool UseFixedLot = true;
input double FixedLot = 0.01;

input double RiskPercent = 1.0;

//========================
// EMA
//========================

input int FastEMA = 20;
input int SlowEMA = 50;

//========================
// ATR
//========================

input int ATRPeriod = 14;

//========================
// ADX
//========================

input int ADXPeriod = 14;
input double MinADX = 20.0;

//========================
// SPREAD
//========================

input int MaxSpreadPoints = 20;

//========================
// SCORE
//========================

input int MinimumScore = 80;

//========================
// RR
//========================

input double MinimumRR = 2.0;

//========================
// SESSION
//========================

input bool LondonSession = true;
input bool NewYorkSession = true;
input bool AsianSession = false;

//========================
// DEBUG
//========================

input bool DebugMode = true;

#endif