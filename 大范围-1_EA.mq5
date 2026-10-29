//+------------------------------------------------------------------+
//| 大范围-1_EA.mq5                                                   |
//| 南门拈星：读取“大范围-1”指标的融合轨4触轨信号执行交易               |
//| 仅允许 M5；反向信号平掉本EA本品种全部持仓后反向开仓。               |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "南门拈星：大范围-1触轨交易EA，仅限M5，反向信号统一平仓。"

#include <Trade/Trade.mqh>

enum ENUM_NMNX_TRADE_MODE
  {
   MODE_ONE_POSITION = 1, // 模式1：同一时间只保留一单，同向信号不加仓
   MODE_ADD_SAME_SIDE = 2 // 模式2：同向信号加仓，并把同向持仓止损移到新单止损
  };

input group "01 · 交易设置"
input ENUM_NMNX_TRADE_MODE InpTradeMode = MODE_ONE_POSITION; // 交易模式
input double InpLots = 0.01;                                 // 每次下单手数
input double InpStopLossPriceDistance = 20.0;                // 止损价格距离：黄金价格差20.0
input ulong  InpMagicNumber = 1700529;                        // EA识别码
input int    InpDeviationPoints = 30;                        // 最大成交偏差（券商点）
input string InpIndicatorName = "大范围-1";                  // 指标名称，不带.ex5

input group "02 · 信号设置"
input bool   InpAllowBuy = true;                             // 允许买入
input bool   InpAllowSell = true;                            // 允许卖出
input bool   InpTradeExistingCurrentBarSignal = true;        // 启动时若当前M5已有触轨信号，是否处理

// 指标缓冲区：0参考上轨、1参考下轨、2融合轨4上轨、3融合轨4下轨、
// 4上轨触碰卖出箭头、5下轨触碰买入箭头。
#define SELL_SIGNAL_BUFFER 4
#define BUY_SIGNAL_BUFFER  5

CTrade trade;
int g_indicatorHandle = INVALID_HANDLE;
datetime g_lastProcessedSignalBar = 0;
bool g_firstSignalCheck = true;

//+------------------------------------------------------------------+
//| 交易量按品种规则规整                                              |
//+------------------------------------------------------------------+
double NormalizeTradeVolume(const double requested)
  {
   double minVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   if(step<=0.0 || minVolume<=0.0 || maxVolume<minVolume)
      return 0.0;

   double volume=MathMax(minVolume,MathMin(maxVolume,requested));
   volume=MathFloor((volume-minVolume)/step+0.0000001)*step+minVolume;

   int digits=0;
   double temp=step;
   while(digits<8 && MathAbs(temp-MathRound(temp))>0.0000001)
     {
      temp*=10.0;
      digits++;
     }
   return NormalizeDouble(volume,digits);
  }

//+------------------------------------------------------------------+
//| 价格按交易品种最小跳动规整                                        |
//+------------------------------------------------------------------+
double NormalizeTradePrice(const double price)
  {
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0.0) tickSize=_Point;
   double rounded=MathRound(price/tickSize)*tickSize;
   return NormalizeDouble(rounded,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
  }

//+------------------------------------------------------------------+
//| 根据方向和成交参考价计算止损                                       |
//| 注意：止损距离是“价格距离”，不是直接乘券商_Point。                 |
//+------------------------------------------------------------------+
double CalculateStopLoss(const ENUM_ORDER_TYPE orderType,const double referencePrice)
  {
   double distance=InpStopLossPriceDistance;
   if(distance<=0.0) return 0.0;

   long stopsLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance=(double)stopsLevel*_Point;
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0.0) tickSize=_Point;

   // 若券商规定的最小止损距离大于设定距离，优先满足券商限制。
   distance=MathMax(distance,minDistance+tickSize);

   double sl=0.0;
   if(orderType==ORDER_TYPE_BUY)
      sl=referencePrice-distance;
   else
      sl=referencePrice+distance;

   return NormalizeTradePrice(sl);
  }

//+------------------------------------------------------------------+
//| 判断某个持仓是否属于本EA、当前品种                                 |
//+------------------------------------------------------------------+
bool IsOurPositionAtIndex(const int index,ulong &ticket,ENUM_POSITION_TYPE &type)
  {
   ticket=PositionGetTicket(index);
   if(ticket==0) return false;

   string symbol=PositionGetString(POSITION_SYMBOL);
   ulong magic=(ulong)PositionGetInteger(POSITION_MAGIC);
   if(symbol!=_Symbol || magic!=InpMagicNumber) return false;

   type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   return true;
  }

//+------------------------------------------------------------------+
//| 统计本EA当前品种的持仓                                             |
//+------------------------------------------------------------------+
int CountOurPositions(const int direction=0)
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=0;
      ENUM_POSITION_TYPE type;
      if(!IsOurPositionAtIndex(i,ticket,type)) continue;

      if(direction==1 && type!=POSITION_TYPE_BUY) continue;
      if(direction==-1 && type!=POSITION_TYPE_SELL) continue;
      count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| 平掉本EA在当前品种上的全部持仓                                     |
//+------------------------------------------------------------------+
bool CloseAllOurPositions()
  {
   bool allClosed=true;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=0;
      ENUM_POSITION_TYPE type;
      if(!IsOurPositionAtIndex(i,ticket,type)) continue;

      ResetLastError();
      if(!trade.PositionClose(ticket))
        {
         allClosed=false;
         PrintFormat("平仓失败：票据=%I64u，交易返回码=%u，说明=%s，错误=%d",
                     ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription(),GetLastError());
        }
     }

   if(CountOurPositions()>0)
      allClosed=false;

   return allClosed;
  }

//+------------------------------------------------------------------+
//| 将同方向持仓止损统一移动到指定价格                                 |
//+------------------------------------------------------------------+
void MoveSameDirectionStops(const int direction,const double newStopLoss)
  {
   if(newStopLoss<=0.0) return;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=0;
      ENUM_POSITION_TYPE type;
      if(!IsOurPositionAtIndex(i,ticket,type)) continue;

      if(direction==1 && type!=POSITION_TYPE_BUY) continue;
      if(direction==-1 && type!=POSITION_TYPE_SELL) continue;

      double currentSL=PositionGetDouble(POSITION_SL);
      double currentTP=PositionGetDouble(POSITION_TP);

      if(MathAbs(currentSL-newStopLoss)<_Point*0.5)
         continue;

      ResetLastError();
      if(!trade.PositionModify(ticket,newStopLoss,currentTP))
        {
         PrintFormat("移动止损失败：票据=%I64u，新止损=%.*f，交易返回码=%u，说明=%s，错误=%d",
                     ticket,_Digits,newStopLoss,trade.ResultRetcode(),
                     trade.ResultRetcodeDescription(),GetLastError());
        }
     }
  }

//+------------------------------------------------------------------+
//| 执行一笔新订单                                                     |
//+------------------------------------------------------------------+
bool OpenPosition(const int direction)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
     {
      Print("无法获取最新报价，暂不下单。");
      return false;
     }

   double volume=NormalizeTradeVolume(InpLots);
   if(volume<=0.0)
     {
      Print("下单手数无效，请检查品种最小手数与手数步进。");
      return false;
     }

   ENUM_ORDER_TYPE orderType=(direction==1 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double referencePrice=(direction==1 ? tick.ask : tick.bid);
   double stopLoss=CalculateStopLoss(orderType,referencePrice);
   if(stopLoss<=0.0)
     {
      Print("止损价格计算失败，未发送订单。");
      return false;
     }

   ResetLastError();
   bool sent=false;
   if(direction==1)
      sent=trade.Buy(volume,_Symbol,0.0,stopLoss,0.0,"大范围-1 EA 买入");
   else
      sent=trade.Sell(volume,_Symbol,0.0,stopLoss,0.0,"大范围-1 EA 卖出");

   uint retcode=trade.ResultRetcode();
   bool success=(sent && (retcode==TRADE_RETCODE_DONE ||
                          retcode==TRADE_RETCODE_DONE_PARTIAL ||
                          retcode==TRADE_RETCODE_PLACED));

   if(!success)
     {
      PrintFormat("%s下单失败：手数=%.2f，初始止损=%.*f，返回码=%u，说明=%s，错误=%d",
                  direction==1?"买入":"卖出",volume,_Digits,stopLoss,
                  retcode,trade.ResultRetcodeDescription(),GetLastError());
      return false;
     }

   // 以实际成交价重新计算止损距离，减少滑点造成的距离偏差。
   double actualPrice=trade.ResultPrice();
   if(actualPrice>0.0)
     {
      double actualSL=CalculateStopLoss(orderType,actualPrice);
      if(actualSL>0.0)
         MoveSameDirectionStops(direction,actualSL);
     }
   else
      MoveSameDirectionStops(direction,stopLoss);

   PrintFormat("%s下单成功：品种=%s，手数=%.2f，成交参考价=%.*f，止损=%.*f，无止盈，模式=%d",
               direction==1?"买入":"卖出",_Symbol,volume,_Digits,
               (actualPrice>0.0?actualPrice:referencePrice),_Digits,stopLoss,(int)InpTradeMode);
   return true;
  }

//+------------------------------------------------------------------+
//| 处理指标信号                                                       |
//+------------------------------------------------------------------+
void ProcessSignal(const int direction,const datetime signalBar)
  {
   if(direction==1 && !InpAllowBuy) return;
   if(direction==-1 && !InpAllowSell) return;

   int sameCount=CountOurPositions(direction);
   int oppositeCount=CountOurPositions(-direction);

   // 反向信号：必须先统一平掉本EA本品种全部持仓，平仓不成功就不反向开仓。
   if(oppositeCount>0)
     {
      Print(direction==1 ? "检测到买入反向信号，先统一平仓。" : "检测到卖出反向信号，先统一平仓。");
      if(!CloseAllOurPositions())
        {
         Print("仍有本EA持仓未能平掉，本次反向开仓取消。");
         return;
        }
      OpenPosition(direction);
      return;
     }

   if(InpTradeMode==MODE_ONE_POSITION)
     {
      // 模式1：已有同向单就不重复开仓，直到反向信号统一平仓。
      if(sameCount>0)
        {
         Print("模式1：已有同方向持仓，本次同向信号不加仓。");
         return;
        }
      OpenPosition(direction);
      return;
     }

   // 模式2：每个新的同方向信号都新增一单；OpenPosition成功后，
   // 会将当前品种、当前EA、同方向的所有持仓止损统一移动到新单止损。
   OpenPosition(direction);
  }

//+------------------------------------------------------------------+
//| 初始化                                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(_Period!=PERIOD_M5)
     {
      Print("大范围-1 EA 只允许在5分钟图表运行。请切换到M5后重新挂载。");
      return INIT_FAILED;
     }

   if(InpLots<=0.0 || InpStopLossPriceDistance<=0.0)
     {
      Print("参数错误：下单手数与止损价格距离必须大于0。");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(!SymbolSelect(_Symbol,true))
     {
      PrintFormat("无法选择交易品种：%s",_Symbol);
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints((ulong)MathMax(0,InpDeviationPoints));
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   // 指标必须先编译为 MQL5/Indicators/大范围-1.ex5。
   // 不传入指标参数时，使用该指标源码中定义的默认参数。
   ResetLastError();
   g_indicatorHandle=iCustom(_Symbol,PERIOD_M5,InpIndicatorName);
   if(g_indicatorHandle==INVALID_HANDLE)
     {
      PrintFormat("无法加载指标“%s”。请先将大范围-1.mq5编译为大范围-1.ex5，并放入MQL5/Indicators目录。错误=%d",
                  InpIndicatorName,GetLastError());
      return INIT_FAILED;
     }

   g_firstSignalCheck=true;
   g_lastProcessedSignalBar=0;

   PrintFormat("大范围-1 EA 已启动：品种=%s，周期=M5，模式=%d，止损价格距离=%.2f，无止盈。",
               _Symbol,(int)InpTradeMode,InpStopLossPriceDistance);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| 反初始化                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_indicatorHandle!=INVALID_HANDLE)
     {
      IndicatorRelease(g_indicatorHandle);
      g_indicatorHandle=INVALID_HANDLE;
     }
   Print("大范围-1 EA 已停止。");
  }

//+------------------------------------------------------------------+
//| 主交易逻辑                                                         |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(_Period!=PERIOD_M5) return;
   if(g_indicatorHandle==INVALID_HANDLE) return;

   datetime currentBar=iTime(_Symbol,PERIOD_M5,0);
   if(currentBar<=0) return;

   double sellBuffer[1];
   double buyBuffer[1];

   if(CopyBuffer(g_indicatorHandle,SELL_SIGNAL_BUFFER,0,1,sellBuffer)!=1)
      return;
   if(CopyBuffer(g_indicatorHandle,BUY_SIGNAL_BUFFER,0,1,buyBuffer)!=1)
      return;

   bool sellSignal=(sellBuffer[0]!=EMPTY_VALUE && MathIsValidNumber(sellBuffer[0]));
   bool buySignal=(buyBuffer[0]!=EMPTY_VALUE && MathIsValidNumber(buyBuffer[0]));

   if(g_firstSignalCheck)
     {
      g_firstSignalCheck=false;
      if(!InpTradeExistingCurrentBarSignal)
        {
         g_lastProcessedSignalBar=currentBar;
         return;
        }
     }

   // 同一根M5若上下轨都被触及，方向不明确，不在该根K线上自动开仓。
   if(sellSignal && buySignal)
     {
      g_lastProcessedSignalBar=currentBar;
      Print("当前M5同时出现上下轨触碰信号，方向不明确，本根K线不下单。");
      return;
     }

   if(!sellSignal && !buySignal) return;

   // 同一根K线只处理一次，防止每个报价都重复下单。
   if(g_lastProcessedSignalBar==currentBar) return;

   int direction=(buySignal ? 1 : -1);
   g_lastProcessedSignalBar=currentBar;

   PrintFormat("收到%s信号：品种=%s，M5时间=%s，指标箭头价=%.*f",
               direction==1?"买入":"卖出",_Symbol,
               TimeToString(currentBar,TIME_DATE|TIME_MINUTES),_Digits,
               direction==1?buyBuffer[0]:sellBuffer[0]);

   ProcessSignal(direction,currentBar);
  }
//+------------------------------------------------------------------+
