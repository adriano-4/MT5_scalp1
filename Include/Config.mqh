//+------------------------------------------------------------------+
//|                                                      Config.mqh   |
//|  Every tunable input for SniperScalpEA, grouped for the          |
//|  MetaTrader "Inputs" tab. No logic lives here.                   |
//+------------------------------------------------------------------+
#ifndef __CONFIG_MQH__
#define __CONFIG_MQH__

//====================================================================
input group "=== General ==="
input long    InpMagicNumber        = 20260807;   // Magic number
input string  InpTradeComment       = "SniperScalp"; // Trade comment
input int     InpMaxConcurrentTrades = 2;          // Max trades open at once (global cap)
input bool    InpEnableTrading      = true;        // Master ON/OFF switch

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES InpHTF        = PERIOD_M15;  // Higher timeframe (bias)
input ENUM_TIMEFRAMES InpStructTF   = PERIOD_M5;   // Structure timeframe (BOS/CHOCH)
input ENUM_TIMEFRAMES InpEntryTF    = PERIOD_M1;   // Entry / trigger timeframe

input group "=== Market Structure ==="
input int     InpSwingLookback      = 3;           // Bars each side to confirm a swing (fractal size)
input int     InpSwingHistoryCount  = 30;           // How many recent swings to keep in memory
input int     InpMaxOBAgeBars       = 60;           // Order block expires after N bars unmitigated
input int     InpMaxFVGAgeBars      = 60;           // FVG expires after N bars unfilled

input group "=== Liquidity ==="
input int     InpLiquidityLookback  = 50;           // Bars scanned for equal highs/lows
input double  InpLiquidityTolPoints = 30;            // Tolerance (points) for "equal" highs/lows
input bool    InpUsePrevDayHiLo     = true;          // Include previous day high/low as liquidity pools
input bool    InpUsePrevSessionHiLo = true;          // Include previous session high/low as liquidity pools

input group "=== Confluence / Entry ==="
input int     InpMinConfluenceScore = 4;            // Minimum weighted score required to enter (see EntryEngine)
input int     InpScoreHTFBias       = 1;
input int     InpScoreStructure     = 1;
input int     InpScoreLiqSweep      = 2;
input int     InpScoreOrderBlock    = 1;
input int     InpScoreFVG           = 1;
input int     InpScoreSRLevel       = 1;
input int     InpScoreCandleTrigger = 1;
input double  InpSRTolerancePoints  = 40;            // Tolerance (points) to consider a zone aligned with S/R

input group "=== Session Filter ==="
input bool    InpUseSessionFilter   = true;
input int     InpSessionStartHour   = 7;             // Broker-time hour, London open (adjust to your broker GMT offset)
input int     InpSessionEndHour     = 20;            // Broker-time hour, NY close
input bool    InpAvoidFridayLateHrs = true;
input int     InpFridayCutoffHour   = 19;

input group "=== News Filter ==="
input bool    InpUseNewsFilter      = true;
input int     InpNewsMinutesBefore  = 15;
input int     InpNewsMinutesAfter   = 15;
input bool    InpNewsHighImpactOnly = true;

input group "=== Spread Filter ==="
input bool    InpUseSpreadFilter    = true;
input double  InpMaxSpreadPoints    = 25;

input group "=== Risk / Money Management ==="
input double  InpFixedLotSize       = 0.10;          // Fixed lot size per trade
input double  InpATRSLBufferMult    = 0.25;           // Extra SL buffer = ATR * this multiplier
input int     InpATRPeriod          = 14;
input ENUM_TIMEFRAMES InpATRTimeframe = PERIOD_M5;
input double  InpTP1_RR             = 1.5;            // Reward:risk for partial TP1
input double  InpTP2_RR             = 3.0;            // Reward:risk for runner TP2
input double  InpTP1_ClosePercent   = 50;              // % of position closed at TP1
input bool    InpUseBreakEvenAfterTP1 = true;
input double  InpBreakEvenBufferPts = 10;
input bool    InpUseTrailing        = true;
input double  InpTrailStartRR       = 1.0;             // Start trailing once price reaches this RR
input double  InpTrailStepPoints    = 50;
input double  InpDailyLossLimitPct  = 3.0;             // Daily equity-loss kill-switch (%)

input group "=== Dashboard ==="
input bool    InpShowDashboard      = true;
input int     InpDashboardX         = 15;
input int     InpDashboardY         = 25;

#endif // __CONFIG_MQH__