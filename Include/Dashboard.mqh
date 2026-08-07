//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh  |
//|  A minimal on-chart panel so you can see, at a glance, why the   |
//|  EA is or isn't trading right now.                                |
//+------------------------------------------------------------------+
#ifndef __DASHBOARD_MQH__
#define __DASHBOARD_MQH__

#include "Config.mqh"
#include "Globals.mqh"
#include "Statistics.mqh"
#include "SessionFilter.mqh"
#include "SpreadFilter.mqh"
#include "RiskManager.mqh"

#define DASH_PREFIX "SSE_DASH_"

string BiasToString(ENUM_BIAS b)
  {
   if(b==BIAS_BULLISH) return "BULLISH";
   if(b==BIAS_BEARISH) return "BEARISH";
   return "NONE";
  }

void DashLabel(const string name,int y,const string text,color clr)
  {
   string obj=DASH_PREFIX+name;
   if(ObjectFind(0,obj)<0)
     {
      ObjectCreate(0,obj,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,obj,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,obj,OBJPROP_XDISTANCE,InpDashboardX);
      ObjectSetInteger(0,obj,OBJPROP_FONTSIZE,9);
      ObjectSetString(0,obj,OBJPROP_FONT,"Consolas");
     }
   ObjectSetInteger(0,obj,OBJPROP_YDISTANCE,InpDashboardY+y*16);
   ObjectSetString(0,obj,OBJPROP_TEXT,text);
   ObjectSetInteger(0,obj,OBJPROP_COLOR,clr);
  }

void Dashboard_Init()
  {
   if(!InpShowDashboard) return;
   DashLabel("title",0,"SniperScalpEA",clrWhite);
  }

void Dashboard_Update(const string symbol)
  {
   if(!InpShowDashboard) return;

   color okClr=clrLimeGreen, badClr=clrTomato, neutClr=clrSilver;

   DashLabel("title",0,"SniperScalpEA - "+symbol,clrWhite);
   DashLabel("htf",1,"HTF bias:   "+BiasToString(g_htfBias),
             g_htfBias==BIAS_NONE?neutClr:okClr);
   DashLabel("struct",2,"Structure:  "+BiasToString(g_structBias),
             g_structBias==BIAS_NONE?neutClr:okClr);
   DashLabel("session",3,"Session:    "+(IsSessionOK()?"OPEN":"CLOSED"),
             IsSessionOK()?okClr:badClr);
   DashLabel("news",4,"News:       "+(IsNewsBlackout(symbol)?"BLACKOUT":"clear"),
             IsNewsBlackout(symbol)?badClr:okClr);
   DashLabel("spread",5,StringFormat("Spread:     %.1f pts",CurrentSpreadPoints(symbol)),
             IsSpreadOK(symbol)?okClr:badClr);
   DashLabel("trades",6,StringFormat("Open trades: %d / %d",CountOpenEAPositions(),InpMaxConcurrentTrades),
             neutClr);
   DashLabel("daily",7,"Daily guard: "+(g_dailyLossHit?"HALTED":"ok"),
             g_dailyLossHit?badClr:okClr);
   DashLabel("stats",8,Statistics_Summary(),clrSilver);
   DashLabel("status",9,"Status: "+(InpEnableTrading?"ACTIVE":"DISABLED"),
             InpEnableTrading?okClr:badClr);
  }

void Dashboard_Deinit()
  {
   ObjectsDeleteAll(0,DASH_PREFIX);
  }

#endif // __DASHBOARD_MQH__