//+------------------------------------------------------------------+
//|                                                       Logger.mqh  |
//|  Minimal logging wrapper. Keeps the Journal readable and gives   |
//|  one place to silence/expand logging later.                      |
//+------------------------------------------------------------------+
#ifndef __LOGGER_MQH__
#define __LOGGER_MQH__

enum ENUM_LOG_LEVEL
  {
   LOG_INFO = 0,
   LOG_TRADE,
   LOG_WARN,
   LOG_ERROR
  };

void LogMsg(ENUM_LOG_LEVEL level,const string msg)
  {
   string tag;
   switch(level)
     {
      case LOG_TRADE: tag="[TRADE]"; break;
      case LOG_WARN:  tag="[WARN] "; break;
      case LOG_ERROR: tag="[ERROR]"; break;
      default:        tag="[INFO] "; break;
     }
   PrintFormat("%s %s | %s",tag,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),msg);
  }

#endif // __LOGGER_MQH__