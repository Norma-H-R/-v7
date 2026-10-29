//+------------------------------------------------------------------+
//| 大范围-1_EA.mq5                                                   |
//| NMNX EA：直接读取原指标核心缓冲区，避免重写算法造成轨道偏差          |
//| 仅M5；融合轨4下轨买、上轨卖；反向先平仓再反手；固定价格距离止损       |
//+------------------------------------------------------------------+
#property strict
#property version   "3.00"
#property description "读取大范围-1_Core原始指标计算，不把指标绘制到图表。"

#include <Trade/Trade.mqh>

input group "01 · 交易设置"
input double InpLots=0.01;                         // 交易手数
input double InpStopLossPriceDistance=20.0;        // 价格距离，例如4500买入，止损4480
input ulong  InpMagicNumber=1700529;               // EA独立魔术号
input int    InpDeviationPoints=30;               // 允许滑点（点）
input bool   InpAllowBuy=true;                     // 允许买入
input bool   InpAllowSell=true;                    // 允许卖出
input bool   InpTradeExistingCurrentBarSignal=true;// EA启动时是否允许处理当前K线已有触轨

input group "02 · 轨道显示（只控制EA绘图，不影响计算与交易）"
input bool   InpShowKAMAReferenceRails=false;      // 显示KAMA参考轨
input bool   InpShowFusionTrack4Rails=false;       // 显示融合轨4
input int    InpDisplayBars=250;                   // 最多绘制K线数量

input group "03 · 原指标基础参数"
input int    InpFastEMA_Period=3;
input int    InpKAMA_ER_Period=8;
input int    InpKAMA_Fast_Period=2;
input int    InpKAMA_Slow_Period=20;
input int    InpATR_Period=7;
input int    InpResidual_Period=10;
input double InpATR_Min_Multiplier=0.35;
input double InpResidual_Multiplier=1.00;
input double InpKAMA_Width_Mult=1.00;
input double InpFast_KAMAWidth_Scale=1.00;

input group "04 · 原指标融合轨4参数"
input bool   InpEnableFusionTrack4=true;
input int    InpTrack4_MACD_Fast=7;
input int    InpTrack4_MACD_Slow=14;
input int    InpTrack4_MACD_Signal=5;
input int    InpTrack4_RSI_Fast=7;
input int    InpTrack4_RSI_Slow=17;
input int    InpTrack4_WPR_Fast=7;
input int    InpTrack4_WPR_Slow=14;
input int    InpTrack4_ADX_Period=7;
input int    InpTrack4_KDJ_K=5;
input int    InpTrack4_KDJ_D=3;
input int    InpTrack4_KDJ_Slowing=3;
input double InpTrack4_MaxDrive_ATR=2.20;
input double InpTrack4_MaxLift_ATR=0.85;
input double InpTrack4_ADX_Weak=14.0;
input double InpTrack4_ADX_Strong=32.0;
input double InpTrack4_ExpandSpeed=0.22;
input double InpTrack4_RecoilSpeed=0.68;

input group "05 · 信号过滤与轨道校准"
input bool   InpSameDirectionSpacingFilter=true;  // 同方向信号间隔3根K线
input double InpKAMAReferenceUpperOffset=0.0;      // KAMA参考上轨偏移
input double InpKAMAReferenceLowerOffset=0.0;      // KAMA参考下轨偏移
input double InpFusion4UpperOffset=0.0;            // 融合轨4上轨偏移
input double InpFusion4LowerOffset=0.0;            // 融合轨4下轨偏移

input group "06 · 计算与调试"
input int    InpCalculationBars=3000;
input bool   InpPrintRailValues=false;             // 输出当前轨道数值，便于与原指标对照

CTrade trade;
int gCoreHandle=INVALID_HANDLE;
datetime gCurrentBar=0;
datetime gLastProcessedBar=0;
datetime gLastAcceptedTime=0;
int gLastAcceptedDirection=0;
bool gFirstCheck=true;
bool gUpperLatched=false,gLowerLatched=false;
double gUpperTouchPrice=0.0,gLowerTouchPrice=0.0;
string OBJ_PREFIX="NMNX_EA_RAIL_";
MqlRates gRates[];

double ClampDouble(const double x,const double lo,const double hi)
  {
   return MathMax(lo,MathMin(hi,x));
  }

string KamaOffsetKey(const string rail)
  {
   return "NMNX_CF42_"+_Symbol+"_"+IntegerToString((int)_Period)+"_1_"+rail;
  }

string RuntimeSwitchKey(const string item)
  {
   return "NCF70_"+IntegerToString((long)ChartID())+"_"+item;
  }

bool SetCoreOffsets()
  {
   // 原指标从终端全局变量读取轨道偏移。EA启动前写入EA参数值，
   // 让后台核心与当前EA设定使用同一组偏移。
   GlobalVariableSet(KamaOffsetKey("0"),InpKAMAReferenceUpperOffset);
   GlobalVariableSet(KamaOffsetKey("1"),InpKAMAReferenceLowerOffset);
   GlobalVariableSet(RuntimeSwitchKey("TRACK4_UP_OFFSET"),InpFusion4UpperOffset);
   GlobalVariableSet(RuntimeSwitchKey("TRACK4_DN_OFFSET"),InpFusion4LowerOffset);
   return true;
  }

bool CreateCoreHandle()
  {
   gCoreHandle=iCustom(_Symbol,PERIOD_M5,"大范围-1_Core",
                       InpFastEMA_Period,InpKAMA_ER_Period,InpKAMA_Fast_Period,InpKAMA_Slow_Period,
                       InpATR_Period,InpResidual_Period,InpATR_Min_Multiplier,InpResidual_Multiplier,
                       InpKAMA_Width_Mult,InpFast_KAMAWidth_Scale,
                       InpEnableFusionTrack4,
                       InpTrack4_MACD_Fast,InpTrack4_MACD_Slow,InpTrack4_MACD_Signal,
                       InpTrack4_RSI_Fast,InpTrack4_RSI_Slow,
                       InpTrack4_WPR_Fast,InpTrack4_WPR_Slow,InpTrack4_ADX_Period,
                       InpTrack4_KDJ_K,InpTrack4_KDJ_D,InpTrack4_KDJ_Slowing,
                       InpTrack4_MaxDrive_ATR,InpTrack4_MaxLift_ATR,
                       InpTrack4_ADX_Weak,InpTrack4_ADX_Strong,
                       InpTrack4_ExpandSpeed,InpTrack4_RecoilSpeed,
                       10.0,0.0);
   if(gCoreHandle==INVALID_HANDLE)
     {
      Print("无法加载 大范围-1_Core.ex5。请先编译大范围-1_Core.mq5，并确认它位于 MQL5\\Indicators 目录。错误=",GetLastError());
      return false;
     }
   return true;
  }

bool ReadRails(double &refUpper,double &refLower,double &fusionUpper,double &fusionLower)
  {
   double v0[1],v1[1],v2[1],v3[1];
   if(BarsCalculated(gCoreHandle)<MathMax(30,InpCalculationBars/10)) { /*允许逐步预热*/ }
   if(CopyBuffer(gCoreHandle,0,0,1,v0)!=1) return false;
   if(CopyBuffer(gCoreHandle,1,0,1,v1)!=1) return false;
   if(CopyBuffer(gCoreHandle,2,0,1,v2)!=1) return false;
   if(CopyBuffer(gCoreHandle,3,0,1,v3)!=1) return false;
   refUpper=v0[0]; refLower=v1[0]; fusionUpper=v2[0]; fusionLower=v3[0];
   if(refUpper==EMPTY_VALUE || refLower==EMPTY_VALUE || fusionUpper==EMPTY_VALUE || fusionLower==EMPTY_VALUE)
      return false;
   if(!MathIsValidNumber(refUpper) || !MathIsValidNumber(refLower) ||
      !MathIsValidNumber(fusionUpper) || !MathIsValidNumber(fusionLower))
      return false;
   return true;
  }

void DeleteRailObjects()
  {
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string n=ObjectName(0,i,-1,-1);
      if(StringFind(n,OBJ_PREFIX)==0) ObjectDelete(0,n);
     }
  }

void DrawSegment(const string name,const datetime t1,const double p1,const datetime t2,const double p2,
                 const color clr,const ENUM_LINE_STYLE style)
  {
   if(ObjectFind(0,name)<0)
      if(!ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2)) return;
   ObjectMove(0,name,0,t1,p1);
   ObjectMove(0,name,1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void DrawRails()
  {
   if(!InpShowKAMAReferenceRails && !InpShowFusionTrack4Rails) { DeleteRailObjects(); return; }
   int copied=CopyRates(_Symbol,PERIOD_M5,0,MathMax(3,InpDisplayBars+2),gRates);
   if(copied<3) return;
   ArraySetAsSeries(gRates,true);
   double u[],l[],fu[],fl[];
   ArrayResize(u,copied); ArrayResize(l,copied); ArrayResize(fu,copied); ArrayResize(fl,copied);
   ArraySetAsSeries(u,true); ArraySetAsSeries(l,true); ArraySetAsSeries(fu,true); ArraySetAsSeries(fl,true);
   if(CopyBuffer(gCoreHandle,0,0,copied,u)<2 || CopyBuffer(gCoreHandle,1,0,copied,l)<2 ||
      CopyBuffer(gCoreHandle,2,0,copied,fu)<2 || CopyBuffer(gCoreHandle,3,0,copied,fl)<2) return;
   int bars=MathMin(InpDisplayBars,copied-1);
   for(int i=bars-1;i>=0;i--)
     {
      int j=i+1;
      if(InpShowKAMAReferenceRails)
        {
         DrawSegment(OBJ_PREFIX+"KU_"+IntegerToString(i),gRates[j].time,u[j],gRates[i].time,u[i],clrAqua,STYLE_SOLID);
         DrawSegment(OBJ_PREFIX+"KL_"+IntegerToString(i),gRates[j].time,l[j],gRates[i].time,l[i],clrAqua,STYLE_SOLID);
        }
      else
        {
         ObjectDelete(0,OBJ_PREFIX+"KU_"+IntegerToString(i));
         ObjectDelete(0,OBJ_PREFIX+"KL_"+IntegerToString(i));
        }
      if(InpShowFusionTrack4Rails && fu[i]!=EMPTY_VALUE && fu[j]!=EMPTY_VALUE && fl[i]!=EMPTY_VALUE && fl[j]!=EMPTY_VALUE)
        {
         DrawSegment(OBJ_PREFIX+"FU_"+IntegerToString(i),gRates[j].time,fu[j],gRates[i].time,fu[i],clrWhite,STYLE_SOLID);
         DrawSegment(OBJ_PREFIX+"FL_"+IntegerToString(i),gRates[j].time,fl[j],gRates[i].time,fl[i],clrWhite,STYLE_DASH);
        }
      else
        {
         ObjectDelete(0,OBJ_PREFIX+"FU_"+IntegerToString(i));
         ObjectDelete(0,OBJ_PREFIX+"FL_"+IntegerToString(i));
        }
     }
  }

int CountOwnPositions(const int direction)
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(direction==0 || (direction==1 && type==POSITION_TYPE_BUY) || (direction==-1 && type==POSITION_TYPE_SELL))
         count++;
     }
   return count;
  }

bool CloseOwnPositions(const int direction)
  {
   bool allClosed=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(direction==1 && type!=POSITION_TYPE_BUY) continue;
      if(direction==-1 && type!=POSITION_TYPE_SELL) continue;
      if(!trade.PositionClose(ticket))
        {
         PrintFormat("平仓失败 ticket=%I64u，retcode=%u，%s",ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
         allClosed=false;
        }
     }
   return allClosed;
  }

double NormalizeLots(double lots)
  {
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   lots=ClampDouble(lots,minLot,maxLot);
   if(step>0.0) lots=MathFloor(lots/step+1.0e-8)*step;
   int digits=2;
   if(step>=1.0) digits=0;
   else if(step>=0.1) digits=1;
   else if(step>=0.01) digits=2;
   else if(step>=0.001) digits=3;
   return NormalizeDouble(lots,digits);
  }

bool OpenTrade(const int direction)
  {
   if(direction==1 && !InpAllowBuy) { Print("买入信号出现，但买入已关闭。"); return false; }
   if(direction==-1 && !InpAllowSell) { Print("卖出信号出现，但卖出已关闭。"); return false; }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   double lots=NormalizeLots(InpLots);
   double sl=0.0;
   bool isBuy=(direction==1);
   double entry=(isBuy?tick.ask:tick.bid);
   sl=(isBuy?entry-InpStopLossPriceDistance:entry+InpStopLossPriceDistance);
   sl=NormalizeDouble(sl,_Digits);
   if(isBuy && sl>=tick.bid) { Print("买入止损价格无效。"); return false; }
   if(!isBuy && sl<=tick.ask) { Print("卖出止损价格无效。"); return false; }
   bool ok=(isBuy?trade.Buy(lots,_Symbol,0.0,sl,0.0,"NMNX Fusion4 Buy")
                  :trade.Sell(lots,_Symbol,0.0,sl,0.0,"NMNX Fusion4 Sell"));
   if(!ok)
     {
      PrintFormat("开仓失败，retcode=%u，%s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
      return false;
     }
   PrintFormat("%s开仓成功：手数=%.2f，参考触轨价=%.*f，止损=%.*f，无固定止盈。",
               isBuy?"买入":"卖出",lots,_Digits,isBuy?gLowerTouchPrice:gUpperTouchPrice,_Digits,sl);
   return true;
  }

void ProcessSignal(const int direction)
  {
   int oppositeCount=CountOwnPositions(-direction);
   if(oppositeCount>0)
     {
      if(!CloseOwnPositions(-direction))
        {
         Print("反向信号：旧仓未能全部平仓，取消反手开仓。");
         return;
        }
     }
   // 一单一结：同方向已有持仓不加仓。
   if(CountOwnPositions(direction)>0) return;
   OpenTrade(direction);
  }

int OnInit()
  {
   if(_Period!=PERIOD_M5)
     {
      Print("大范围-1 EA只允许在M5图表运行。");
      return INIT_FAILED;
     }
   if(InpLots<=0.0 || InpStopLossPriceDistance<=0.0 || InpCalculationBars<100)
      return INIT_PARAMETERS_INCORRECT;
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints((ulong)MathMax(0,InpDeviationPoints));
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);
   SetCoreOffsets();
   if(!CreateCoreHandle()) return INIT_FAILED;
   gCurrentBar=iTime(_Symbol,PERIOD_M5,0);
   gFirstCheck=true;
   gLastProcessedBar=0;
   PrintFormat("NMNX EA启动：%s M5；使用大范围-1_Core原始计算；轨道不自动显示；止损价格距离=%.2f。",_Symbol,InpStopLossPriceDistance);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(gCoreHandle!=INVALID_HANDLE) IndicatorRelease(gCoreHandle);
   DeleteRailObjects();
   Print("NMNX EA已停止。");
  }

void OnTick()
  {
   if(_Period!=PERIOD_M5 || gCoreHandle==INVALID_HANDLE) return;
   datetime barTime=iTime(_Symbol,PERIOD_M5,0);
   if(barTime<=0) return;
   bool newBar=(barTime!=gCurrentBar);
   if(newBar)
     {
      gCurrentBar=barTime;
      gUpperLatched=false;
      gLowerLatched=false;
      gUpperTouchPrice=0.0;
      gLowerTouchPrice=0.0;
     }

   double refUpper,refLower,fusionUpper,fusionLower;
   if(!ReadRails(refUpper,refLower,fusionUpper,fusionLower)) return;
   MqlRates current[1];
   if(CopyRates(_Symbol,PERIOD_M5,0,1,current)!=1) return;

   if(!gUpperLatched && current[0].high>=fusionUpper)
     { gUpperLatched=true; gUpperTouchPrice=fusionUpper; }
   if(!gLowerLatched && current[0].low<=fusionLower)
     { gLowerLatched=true; gLowerTouchPrice=fusionLower; }

   if(InpPrintRailValues)
      PrintFormat("轨道对照 %s KU=%.*f KL=%.*f F4U=%.*f F4L=%.*f",
                  TimeToString(barTime,TIME_DATE|TIME_MINUTES),
                  _Digits,refUpper,_Digits,refLower,_Digits,fusionUpper,_Digits,fusionLower);
   if(newBar || InpShowKAMAReferenceRails || InpShowFusionTrack4Rails) DrawRails();

   if(gFirstCheck)
     {
      gFirstCheck=false;
      if(!InpTradeExistingCurrentBarSignal)
        {
         gLastProcessedBar=barTime;
         return;
        }
     }

   bool buySignal=gLowerLatched;
   bool sellSignal=gUpperLatched;
   if(buySignal && sellSignal)
     {
      gLastProcessedBar=barTime;
      Print("本根M5同时触及融合轨4上下轨，方向不明确，本根不交易。");
      return;
     }
   if(!buySignal && !sellSignal) return;
   if(gLastProcessedBar==barTime) return;

   int direction=(buySignal?1:-1);
   if(InpSameDirectionSpacingFilter && gLastAcceptedDirection==direction && gLastAcceptedTime>0)
     {
      int shift=iBarShift(_Symbol,PERIOD_M5,gLastAcceptedTime,true);
      if(shift>=0 && shift<3)
        {
         gLastProcessedBar=barTime;
         return;
        }
     }

   gLastProcessedBar=barTime;
   gLastAcceptedDirection=direction;
   gLastAcceptedTime=barTime;
   PrintFormat("融合轨4触轨信号：%s，时间=%s，触轨价=%.*f",
               direction==1?"买入":"卖出",TimeToString(barTime,TIME_DATE|TIME_MINUTES),
               _Digits,direction==1?gLowerTouchPrice:gUpperTouchPrice);
   ProcessSignal(direction);
  }
//+------------------------------------------------------------------+
