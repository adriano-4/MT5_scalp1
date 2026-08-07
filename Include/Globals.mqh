//+------------------------------------------------------------------+
//|                                                     Globals.mqh   |
//|  Enums, structs and shared runtime state used by every module.   |
//|  No dependencies on other project headers.                       |
//+------------------------------------------------------------------+
#ifndef __GLOBALS_MQH__
#define __GLOBALS_MQH__

//--- Directional bias / trend state --------------------------------
enum ENUM_BIAS
  {
   BIAS_NONE = 0,
   BIAS_BULLISH,
   BIAS_BEARISH
  };

//--- Market structure events ----------------------------------------
enum ENUM_STRUCT_EVENT
  {
   STRUCT_EVENT_NONE = 0,
   STRUCT_EVENT_BOS_BULL,
   STRUCT_EVENT_BOS_BEAR,
   STRUCT_EVENT_CHOCH_BULL,
   STRUCT_EVENT_CHOCH_BEAR
  };

//--- A swing (pivot) point -------------------------------------------
struct SwingPoint
  {
   datetime time;
   double   price;
   bool     isHigh;     // true = swing high, false = swing low
   bool     broken;     // has price closed beyond it already
  };

//--- A liquidity pool (equal highs/lows, session high/low, etc.) ----
struct LiquidityPool
  {
   double   price;
   datetime time;
   bool     isHigh;      // pool sits above price (sell-side liquidity resting above) 
   bool     swept;        // price has wicked through and closed back inside
   datetime sweptTime;
  };

//--- An order block zone ---------------------------------------------
struct OrderBlockZone
  {
   double   top;
   double   bottom;
   datetime time;
   bool     bullish;      // true = demand (bullish) OB, false = supply (bearish) OB
   bool     mitigated;    // price has closed fully through it
   bool     traded;       // a trade has already been taken from this zone
   int      confluenceTag; // bitmask of extra confluence found in this zone (FVG overlap, S/R, etc.)
  };

//--- A fair value gap zone --------------------------------------------
struct FVGZone
  {
   double   top;
   double   bottom;
   datetime time;
   bool     bullish;
   bool     filled;
   bool     traded;       // a trade has already been taken from this zone
  };

//--- Final trade signal produced by the EntryEngine -------------------
struct TradeSignal
  {
   bool          valid;
   ENUM_ORDER_TYPE type;
   double        entry;
   double        sl;
   double        tp1;
   double        tp2;
   int           score;
   string        reason;
   string        zoneId;   // identifies the OB/FVG zone used, to avoid re-trading it
  };

//--- Confluence bit flags (used for scoring + logging) -----------------
#define CONFLUENCE_HTF_BIAS      1
#define CONFLUENCE_STRUCTURE     2
#define CONFLUENCE_LIQ_SWEEP     4
#define CONFLUENCE_ORDER_BLOCK   8
#define CONFLUENCE_FVG           16
#define CONFLUENCE_SR_LEVEL      32
#define CONFLUENCE_CANDLE_TRIG   64

//--- Shared runtime arrays (populated each new bar) ---------------------
SwingPoint      g_swingsLTF[];     // swing points on the structure timeframe
LiquidityPool   g_liquidityPools[];
OrderBlockZone  g_orderBlocks[];
FVGZone         g_fvgZones[];

//--- Shared runtime state -----------------------------------------------
ENUM_BIAS       g_htfBias        = BIAS_NONE;   // higher-timeframe bias (TrendFilter.mqh)
ENUM_BIAS       g_structBias     = BIAS_NONE;   // structure-timeframe bias (MarketStructure.mqh)
ENUM_STRUCT_EVENT g_lastEvent    = STRUCT_EVENT_NONE;
datetime        g_lastEventTime  = 0;
string          g_lastTradedZone = "";
datetime        g_lastTradedZoneTime = 0;

//--- Daily risk-guard state -----------------------------------------------
double          g_dayStartEquity   = 0.0;
datetime        g_currentDay       = 0;
bool            g_dailyLossHit     = false;

#endif // __GLOBALS_MQH__