//+------------------------------------------------------------------+
//| NMNX_TouchTrack3_Only_v1.34.mq5                                  |
//| 南门拈星：仅绘制触点轨3 + 触轨统计                                |
//| 说明：仅绘制黄色触点轨3上下轨与触轨箭头；其他必要轨道仅内部计算。             |
//| 注意：本版尚未经过 MetaEditor 实际编译。                          |
//+------------------------------------------------------------------+
#property strict
#property version   "1.34"
#property description "NMNX仅显示触点轨3、实时触轨圆点标记与十日统计 v1.34"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

//--- 触点轨3上轨
#property indicator_label1  "触点轨3上轨"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrYellow
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- 触点轨3下轨
#property indicator_label2  "触点轨3下轨"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrYellow
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- 上轨触碰卖出观察箭头
#property indicator_label3  "触点轨3上轨触碰卖出观察"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrTomato
#property indicator_width3  2

//--- 下轨触碰买入观察箭头
#property indicator_label4  "触点轨3下轨触碰买入观察"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_width4  2

//====================================================================
// 输入参数
//====================================================================

input group "01 · 快速线与KAMA"
input int      InpFastEMA_Period       = 3;
input int      InpKAMA_ER_Period       = 8;
input int      InpKAMA_Fast_Period     = 2;
input int      InpKAMA_Slow_Period     = 20;

input group "02 · KAMA宽度通道"
input int      InpATR_Period           = 7;
input int      InpResidual_Period      = 10;
input double   InpATR_Min_Multiplier   = 0.35;
input double   InpResidual_Multiplier  = 1.00;
input double   InpKAMA_Width_Mult      = 1.00;
input double   InpFast_KAMAWidth_Scale = 1.00;

input group "03 · 融合轨4动能指标"
input bool     InpEnableFusionTrack4   = true;
input int      InpTrack4_MACD_Fast     = 7;
input int      InpTrack4_MACD_Slow     = 14;
input int      InpTrack4_MACD_Signal   = 5;
input int      InpTrack4_RSI_Fast      = 7;
input int      InpTrack4_RSI_Slow      = 17;
input int      InpTrack4_WPR_Fast      = 7;
input int      InpTrack4_WPR_Slow      = 14;
input int      InpTrack4_ADX_Period    = 7;
input int      InpTrack4_KDJ_K         = 5;
input int      InpTrack4_KDJ_D         = 3;
input int      InpTrack4_KDJ_Slowing   = 3;

input group "04 · 融合轨4驱离参数"
input double   InpTrack4_MaxDrive_ATR  = 2.20;
input double   InpTrack4_MaxLift_ATR   = 0.85;
input double   InpTrack4_ADX_Weak      = 14.0;
input double   InpTrack4_ADX_Strong    = 32.0;
input double   InpTrack4_ExpandSpeed   = 0.22;
input double   InpTrack4_RecoilSpeed   = 0.68;

input group "05 · 轨道偏移"
input double   InpKAMA_UpperOffset     = 0.0;
input double   InpKAMA_LowerOffset     = 0.0;
input double   InpTrack4_UpperOffset   = 0.0;
input double   InpTrack4_LowerOffset   = 0.0;

input group "06 · 触轨信号"
input bool     InpShowTouchArrows      = true;
input bool     InpEnableTouchSpacing  = true;
input int      InpTouchSpacingBars     = 3;

//====================================================================
// 绘图缓冲区：仅保留触点轨3上下轨与买卖箭头，共4个
//====================================================================

double TouchTrack3Upper[];
double TouchTrack3Lower[];
double SellTouchArrow[];
double BuyTouchArrow[];

//====================================================================
// 内部轨道数组：只参与触点轨3计算，不创建绘图缓冲区
//====================================================================

double KAMAWidthUpper[];
double KAMAWidthLower[];
double Track4Upper[];
double Track4Lower[];
// 触点轨1、触点轨2只作为公式概念，不单独保存数组。
// 它们的结果直接折叠进触点轨3计算，减少中间数组和一轮遍历。

//====================================================================
// 内部计算数组
//====================================================================

double FastLine[];
double KAMALine[];
double KAMAHalfWidth[];
double Atr[];
double Track4DriveUpper[];
double Track4DriveLower[];
double Track4Energy[];

double Track4MACDMain[];
double Track4MACDSignal[];
double Track4RSIFast[];
double Track4RSISlow[];
double Track4WPRFast[];
double Track4WPRSlow[];
double Track4K[];
double Track4D[];
double Track4ADX[];
double Track4PlusDI[];
double Track4MinusDI[];

//====================================================================
// 指标句柄
//====================================================================

int gMACDHandle = INVALID_HANDLE;
int gRSIFastHandle = INVALID_HANDLE;
int gRSISlowHandle = INVALID_HANDLE;
int gWPRFastHandle = INVALID_HANDLE;
int gWPRSlowHandle = INVALID_HANDLE;
int gADXHandle = INVALID_HANDLE;
int gKDJHandle = INVALID_HANDLE;

string gObjectPrefix = "NMNX_TouchTrack3_Only_";

string gStatsLabelName = "NMNX_TouchTrack3_Only_Stats";
string gStatsRecentName = "NMNX_TouchTrack3_Only_StatsRecent";
string gStatsNoteName = "NMNX_TouchTrack3_Only_StatsNote";

//--- 实时报价触轨状态：只记录报价主动穿越轨道的信号
datetime gLastArrowBarTime = 0;
double gPrevBid = 0.0;
double gPrevAsk = 0.0;
double gPrevTouchTrack3Upper = EMPTY_VALUE;
double gPrevTouchTrack3Lower = EMPTY_VALUE;
bool gHasPreviousQuote = false;
bool gSellTriggeredThisBar = false;
bool gBuyTriggeredThisBar = false;

//====================================================================
// 通用函数
//====================================================================

double ClampValue(const double value,
                  const double minimum,
                  const double maximum)
{
   return MathMax(minimum, MathMin(maximum, value));
}

// 残差均方根：使用当前索引及更旧的K线，不读取未来K线。
double ResidualRMSAt(const int index,
                    const int period,
                    const int total,
                    const double &close[],
                    const double &line[])
{
   int count = MathMax(1, period);
   double sumSquares = 0.0;
   int samples = 0;

   for(int j = index; j < total && j < index + count; j++)
   {
      if(line[j] == EMPTY_VALUE)
         continue;

      double residual = close[j] - line[j];
      sumSquares += residual * residual;
      samples++;
   }

   if(samples <= 0)
      return 0.0;

   return MathSqrt(sumSquares / samples);
}

//====================================================================
// 融合轨4计算
// 保留原版方向评分、能量计算和递归驱离的核心公式。
//====================================================================

void CalculateTrack4At(
   const int i,
   const int total,
   const double &open[],
   const double &close[],
   const bool dataReady)
{
   if(!InpEnableFusionTrack4 ||
      !dataReady ||
      i + 3 >= total ||
      KAMALine[i] == EMPTY_VALUE ||
      KAMAHalfWidth[i] == EMPTY_VALUE ||
      FastLine[i] == EMPTY_VALUE ||
      Track4MACDMain[i] == EMPTY_VALUE ||
      Track4MACDSignal[i] == EMPTY_VALUE ||
      Track4MACDMain[i+1] == EMPTY_VALUE ||
      Track4MACDSignal[i+1] == EMPTY_VALUE ||
      Track4RSIFast[i] == EMPTY_VALUE ||
      Track4RSISlow[i] == EMPTY_VALUE ||
      Track4WPRFast[i] == EMPTY_VALUE ||
      Track4WPRSlow[i] == EMPTY_VALUE ||
      Track4K[i] == EMPTY_VALUE ||
      Track4D[i] == EMPTY_VALUE ||
      Track4ADX[i] == EMPTY_VALUE ||
      Track4PlusDI[i] == EMPTY_VALUE ||
      Track4MinusDI[i] == EMPTY_VALUE)
   {
      Track4Upper[i] = EMPTY_VALUE;
      Track4Lower[i] = EMPTY_VALUE;
      Track4DriveUpper[i] = 0.0;
      Track4DriveLower[i] = 0.0;
      Track4Energy[i] = 0.0;
      return;
   }

   double atrScale = MathMax(Atr[i], _Point * 2.0);

   // 基础通道：快速线为中心，借用KAMA上下半宽。
   double widthScale = MathMax(0.01, InpFast_KAMAWidth_Scale);
   double kamaHalfUp = MathMax(0.0, KAMAHalfWidth[i]);
   double kamaHalfDown = MathMax(0.0, KAMAHalfWidth[i]);

   double baseUpper = FastLine[i] + kamaHalfUp * widthScale;
   double baseLower = FastLine[i] - kamaHalfDown * widthScale;

   double rsiFast = Track4RSIFast[i];
   double rsiSlow = Track4RSISlow[i];
   double wprFast = Track4WPRFast[i];
   double wprSlow = Track4WPRSlow[i];

   double macdHist =
      Track4MACDMain[i] - Track4MACDSignal[i];

   double macdHistOld =
      Track4MACDMain[i+1] - Track4MACDSignal[i+1];

   double k = Track4K[i];
   double d = Track4D[i];
   double j = 3.0 * k - 2.0 * d;

   double adx = Track4ADX[i];
   double plusDI = Track4PlusDI[i];
   double minusDI = Track4MinusDI[i];

   // 1. RSI方向评分
   double rsiScore =
      0.60 * ClampValue((rsiFast-rsiSlow)/15.0,-1.0,1.0)
    + 0.40 * ClampValue((rsiSlow-50.0)/25.0,-1.0,1.0);

   // 2. 威廉指标方向评分
   double wprScore =
      0.60 * ClampValue((wprFast-wprSlow)/25.0,-1.0,1.0)
    + 0.40 * ClampValue((wprSlow+50.0)/35.0,-1.0,1.0);

   // 3. MACD动能及动能变化
   double macdLevel =
      ClampValue(macdHist/MathMax(atrScale*0.12,_Point),-1.0,1.0);

   double macdChange =
      ClampValue((macdHist-macdHistOld)/
                 MathMax(atrScale*0.08,_Point),-1.0,1.0);

   double macdScore = 0.70*macdLevel + 0.30*macdChange;

   // 4. KDJ方向评分
   double kdjScore =
      0.45 * ClampValue((k-d)/20.0,-1.0,1.0)
    + 0.35 * ClampValue((j-50.0)/45.0,-1.0,1.0)
    + 0.20 * ClampValue((k-50.0)/35.0,-1.0,1.0);

   // 5. 多空DI差值
   double diDenom = MathMax(plusDI+minusDI,1.0);
   double diScore =
      ClampValue((plusDI-minusDI)/diDenom,-1.0,1.0);

   // 6. 价格连续性与当前K线实体
   double priceSlope =
      ClampValue((close[i]-close[i+3])/
                 MathMax(atrScale*1.50,_Point),-1.0,1.0);

   double candleBody =
      ClampValue((close[i]-open[i])/
                 MathMax(atrScale*0.80,_Point),-1.0,1.0);

   double priceScore = 0.70*priceSlope + 0.30*candleBody;

   // 综合方向评分
   double directionScore =
      0.18*rsiScore
    + 0.14*wprScore
    + 0.24*macdScore
    + 0.14*kdjScore
    + 0.18*diScore
    + 0.12*priceScore;

   directionScore = ClampValue(directionScore,-1.0,1.0);

   // ADX趋势强度
   double adxStrength =
      ClampValue((adx-InpTrack4_ADX_Weak)/
      MathMax(InpTrack4_ADX_Strong-InpTrack4_ADX_Weak,1.0),
      0.0,1.0);

   // 价格连续性
   double priceContinuity =
      ClampValue(MathAbs(close[i]-close[i+3])/
                 MathMax(atrScale*1.20,_Point),0.0,1.0);

   // 综合能量
   double rawDirectionalEnergy =
      ClampValue((MathAbs(directionScore)-0.08)/0.92,0.0,1.0);

   double energy =
      ClampValue(rawDirectionalEnergy
                 *(0.15+0.85*adxStrength)
                 *(0.08+0.92*priceContinuity),
                 0.0,1.0);

   Track4Energy[i] = energy;

   // 多头：上轨外扩、下轨上抬。
   // 空头：下轨外扩、上轨下压。
   double targetUpper = 0.0;
   double targetLower = 0.0;

   if(directionScore > 0.0)
   {
      targetUpper = atrScale * InpTrack4_MaxDrive_ATR * energy;
      targetLower = atrScale * InpTrack4_MaxLift_ATR * energy;
   }
   else if(directionScore < 0.0)
   {
      targetUpper = -atrScale * InpTrack4_MaxLift_ATR * energy;
      targetLower = -atrScale * InpTrack4_MaxDrive_ATR * energy;
   }

   // 只读取更旧K线的递归状态。
   double previousUpper = 0.0;
   double previousLower = 0.0;
   double previousEnergy = 0.0;

   if(i+1 < total)
   {
      previousUpper = Track4DriveUpper[i+1];
      previousLower = Track4DriveLower[i+1];
      previousEnergy = Track4Energy[i+1];
   }

   double expandRate =
      ClampValue(InpTrack4_ExpandSpeed,0.01,1.0);

   double recoilBase =
      ClampValue(InpTrack4_RecoilSpeed,0.01,1.0);

   double energyFade =
      ClampValue((previousEnergy-energy)*1.50,0.0,1.0);

   bool upperExpanding =
      ((previousUpper==0.0 || targetUpper*previousUpper>0.0)
       && MathAbs(targetUpper)>MathAbs(previousUpper));

   bool lowerExpanding =
      ((previousLower==0.0 || targetLower*previousLower>0.0)
       && MathAbs(targetLower)>MathAbs(previousLower));

   double upperRate =
      upperExpanding
      ? expandRate
      : ClampValue(recoilBase+0.20*energyFade,recoilBase,0.95);

   double lowerRate =
      lowerExpanding
      ? expandRate
      : ClampValue(recoilBase+0.20*energyFade,recoilBase,0.95);

   if(i == total-1)
   {
      Track4DriveUpper[i] = targetUpper;
      Track4DriveLower[i] = targetLower;
   }
   else
   {
      Track4DriveUpper[i] =
         previousUpper + upperRate*(targetUpper-previousUpper);

      Track4DriveLower[i] =
         previousLower + lowerRate*(targetLower-previousLower);
   }

   Track4Upper[i] =
      baseUpper + Track4DriveUpper[i] + InpTrack4_UpperOffset;

   Track4Lower[i] =
      baseLower + Track4DriveLower[i] + InpTrack4_LowerOffset;
}

//====================================================================
// 初始化
//====================================================================

int OnInit()
{
   SetIndexBuffer(0,TouchTrack3Upper,INDICATOR_DATA);
   SetIndexBuffer(1,TouchTrack3Lower,INDICATOR_DATA);
   SetIndexBuffer(2,SellTouchArrow,INDICATOR_DATA);
   SetIndexBuffer(3,BuyTouchArrow,INDICATOR_DATA);

   ArraySetAsSeries(TouchTrack3Upper,true);
   ArraySetAsSeries(TouchTrack3Lower,true);
   ArraySetAsSeries(SellTouchArrow,true);
   ArraySetAsSeries(BuyTouchArrow,true);

   PlotIndexSetInteger(2,PLOT_ARROW,234);
   PlotIndexSetInteger(3,PLOT_ARROW,233);

   for(int p=0; p<4; p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   gMACDHandle = iMACD(
      _Symbol,_Period,
      InpTrack4_MACD_Fast,
      InpTrack4_MACD_Slow,
      InpTrack4_MACD_Signal,
      PRICE_CLOSE);

   gRSIFastHandle = iRSI(
      _Symbol,_Period,InpTrack4_RSI_Fast,PRICE_CLOSE);

   gRSISlowHandle = iRSI(
      _Symbol,_Period,InpTrack4_RSI_Slow,PRICE_CLOSE);

   gWPRFastHandle = iWPR(
      _Symbol,_Period,InpTrack4_WPR_Fast);

   gWPRSlowHandle = iWPR(
      _Symbol,_Period,InpTrack4_WPR_Slow);

   gADXHandle = iADX(
      _Symbol,_Period,InpTrack4_ADX_Period);

   gKDJHandle = iStochastic(
      _Symbol,_Period,
      InpTrack4_KDJ_K,
      InpTrack4_KDJ_D,
      InpTrack4_KDJ_Slowing,
      MODE_SMA,
      STO_LOWHIGH);

   if(gMACDHandle==INVALID_HANDLE ||
      gRSIFastHandle==INVALID_HANDLE ||
      gRSISlowHandle==INVALID_HANDLE ||
      gWPRFastHandle==INVALID_HANDLE ||
      gWPRSlowHandle==INVALID_HANDLE ||
      gADXHandle==INVALID_HANDLE ||
      gKDJHandle==INVALID_HANDLE)
   {
      Print("NMNX触点轨3：创建一个或多个指标句柄失败。");
      return INIT_FAILED;
   }

   IndicatorSetString(
      INDICATOR_SHORTNAME,
      "NMNX触点轨3单轨 v1.33");

   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   CreateStatsUI();

   return INIT_SUCCEEDED;
}

// 实时触轨圆点：使用图表对象，确保标记清晰可见。
void DrawTouchMarker(const datetime barTime,
                     const double price,
                     const bool isSell)
{
   string side = isSell ? "SELL_" : "BUY_";
   string objectName = gObjectPrefix + "Touch_" + side
                       + IntegerToString((long)barTime);

   if(ObjectFind(0, objectName) >= 0)
      return;

   if(!ObjectCreate(0, objectName, OBJ_ARROW, 0, barTime, price))
   {
      Print("触轨圆点创建失败，错误：", GetLastError());
      return;
   }

   ObjectSetInteger(0, objectName, OBJPROP_ARROWCODE, 159);
   ObjectSetInteger(0, objectName, OBJPROP_COLOR,
                    isSell ? clrTomato : clrLime);
   ObjectSetInteger(0, objectName, OBJPROP_WIDTH, 4);
   ObjectSetInteger(0, objectName, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, objectName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, objectName, OBJPROP_HIDDEN, true);
   ChartRedraw(0);
}

//====================================================================
// 主计算
//====================================================================

int OnCalculate(
   const int rates_total,
   const int prev_calculated,
   const datetime &time[],
   const double &open[],
   const double &high[],
   const double &low[],
   const double &close[],
   const long &tick_volume[],
   const long &volume[],
   const int &spread[])
{
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(open,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);

   int minimumBars =
      MathMax(InpKAMA_ER_Period,
      MathMax(InpATR_Period,InpResidual_Period))+5;

   if(rates_total < minimumBars)
      return 0;

   // 内部数组尺寸与时间序列方向
   ArrayResize(KAMAWidthUpper,rates_total);
   ArrayResize(KAMAWidthLower,rates_total);
   ArrayResize(Track4Upper,rates_total);
   ArrayResize(Track4Lower,rates_total);
   ArrayResize(FastLine,rates_total);
   ArrayResize(KAMALine,rates_total);
   ArrayResize(KAMAHalfWidth,rates_total);
   ArrayResize(Atr,rates_total);
   ArrayResize(Track4DriveUpper,rates_total);
   ArrayResize(Track4DriveLower,rates_total);
   ArrayResize(Track4Energy,rates_total);

   ArrayResize(Track4MACDMain,rates_total);
   ArrayResize(Track4MACDSignal,rates_total);
   ArrayResize(Track4RSIFast,rates_total);
   ArrayResize(Track4RSISlow,rates_total);
   ArrayResize(Track4WPRFast,rates_total);
   ArrayResize(Track4WPRSlow,rates_total);
   ArrayResize(Track4K,rates_total);
   ArrayResize(Track4D,rates_total);
   ArrayResize(Track4ADX,rates_total);
   ArrayResize(Track4PlusDI,rates_total);
   ArrayResize(Track4MinusDI,rates_total);

   ArraySetAsSeries(KAMAWidthUpper,true);
   ArraySetAsSeries(KAMAWidthLower,true);
   ArraySetAsSeries(Track4Upper,true);
   ArraySetAsSeries(Track4Lower,true);
   ArraySetAsSeries(FastLine,true);
   ArraySetAsSeries(KAMALine,true);
   ArraySetAsSeries(KAMAHalfWidth,true);
   ArraySetAsSeries(Atr,true);
   ArraySetAsSeries(Track4DriveUpper,true);
   ArraySetAsSeries(Track4DriveLower,true);
   ArraySetAsSeries(Track4Energy,true);

   ArraySetAsSeries(Track4MACDMain,true);
   ArraySetAsSeries(Track4MACDSignal,true);
   ArraySetAsSeries(Track4RSIFast,true);
   ArraySetAsSeries(Track4RSISlow,true);
   ArraySetAsSeries(Track4WPRFast,true);
   ArraySetAsSeries(Track4WPRSlow,true);
   ArraySetAsSeries(Track4K,true);
   ArraySetAsSeries(Track4D,true);
   ArraySetAsSeries(Track4ADX,true);
   ArraySetAsSeries(Track4PlusDI,true);
   ArraySetAsSeries(Track4MinusDI,true);

   // 读取融合轨4所需指标数据
   bool dataReady = true;

   if(CopyBuffer(gMACDHandle,0,0,rates_total,Track4MACDMain)<rates_total)
      dataReady=false;
   if(CopyBuffer(gMACDHandle,1,0,rates_total,Track4MACDSignal)<rates_total)
      dataReady=false;
   if(CopyBuffer(gRSIFastHandle,0,0,rates_total,Track4RSIFast)<rates_total)
      dataReady=false;
   if(CopyBuffer(gRSISlowHandle,0,0,rates_total,Track4RSISlow)<rates_total)
      dataReady=false;
   if(CopyBuffer(gWPRFastHandle,0,0,rates_total,Track4WPRFast)<rates_total)
      dataReady=false;
   if(CopyBuffer(gWPRSlowHandle,0,0,rates_total,Track4WPRSlow)<rates_total)
      dataReady=false;
   if(CopyBuffer(gKDJHandle,0,0,rates_total,Track4K)<rates_total)
      dataReady=false;
   if(CopyBuffer(gKDJHandle,1,0,rates_total,Track4D)<rates_total)
      dataReady=false;
   if(CopyBuffer(gADXHandle,0,0,rates_total,Track4ADX)<rates_total)
      dataReady=false;
   if(CopyBuffer(gADXHandle,1,0,rates_total,Track4PlusDI)<rates_total)
      dataReady=false;
   if(CopyBuffer(gADXHandle,2,0,rates_total,Track4MinusDI)<rates_total)
      dataReady=false;

   // 基础线参数
   double alphaFast = 2.0/(InpFastEMA_Period+1.0);
   double fastSC = 2.0/(InpKAMA_Fast_Period+1.0);
   double slowSC = 2.0/(InpKAMA_Slow_Period+1.0);

   // 第一阶段：计算ATR、快速线、KAMA线
   for(int i=rates_total-1; i>=0; i--)
   {
      double tr = high[i]-low[i];

      if(i < rates_total-1)
      {
         tr=MathMax(tr,MathAbs(high[i]-close[i+1]));
         tr=MathMax(tr,MathAbs(low[i]-close[i+1]));

         Atr[i] =
            (Atr[i+1]*(InpATR_Period-1)+tr)/InpATR_Period;

         FastLine[i] =
            alphaFast*close[i]+(1.0-alphaFast)*FastLine[i+1];
      }
      else
      {
         Atr[i]=tr;
         FastLine[i]=close[i];
      }

      // KAMA效率比
      if(i == rates_total-1)
      {
         KAMALine[i]=close[i];
      }
      else
      {
         int oldIndex =
            MathMin(rates_total-1,i+InpKAMA_ER_Period);

         double change=MathAbs(close[i]-close[oldIndex]);
         double volatility=0.0;

         int endIndex =
            MathMin(rates_total-1,i+InpKAMA_ER_Period-1);

         for(int j=i; j<=endIndex; j++)
         {
            if(j+1<rates_total)
               volatility+=MathAbs(close[j]-close[j+1]);
         }

         double er =
            volatility>0.0 ? change/volatility : 0.0;

         er=ClampValue(er,0.0,1.0);

         double sc=er*(fastSC-slowSC)+slowSC;
         sc*=sc;

         KAMALine[i] =
            KAMALine[i+1]+sc*(close[i]-KAMALine[i+1]);
      }
   }

   // 第二阶段：KAMA宽度通道
   for(int i=rates_total-1; i>=0; i--)
   {
      double atrValue=MathMax(Atr[i],_Point*2.0);
      double minHalf=atrValue*InpATR_Min_Multiplier;

      double residual =
         ResidualRMSAt(
            i,
            InpResidual_Period,
            rates_total,
            close,
            KAMALine);

      double wKAMA =
         MathMax(
            minHalf,
            residual*InpResidual_Multiplier)
         *InpKAMA_Width_Mult;

      KAMAHalfWidth[i] = wKAMA;

      double scale=MathMax(0.01,InpFast_KAMAWidth_Scale);

      KAMAWidthUpper[i] =
         FastLine[i]+wKAMA*scale+InpKAMA_UpperOffset;

      KAMAWidthLower[i] =
         FastLine[i]-wKAMA*scale+InpKAMA_LowerOffset;
   }

   // 第三阶段：融合轨4
   // 从较旧K线向当前K线递推，保持轨道状态的因果顺序。
   for(int i=rates_total-1; i>=0; i--)
   {
      CalculateTrack4At(
         i,
         rates_total,
         open,
         close,
         dataReady);
   }

   // 第四阶段：直接计算触点轨3。
   // 原公式等价于：
   // 轨1上轨=(融合轨4上轨+KAMA宽度上轨)/2
   // 轨2上轨=min(融合轨4上轨,KAMA宽度上轨)
   // 轨3上轨=(轨1上轨+轨2上轨)/2
   // 下轨对应使用 max()。直接展开可删除轨1/轨2中间数组和额外遍历。
   for(int i=rates_total-1; i>=0; i--)
   {
      if(Track4Upper[i] == EMPTY_VALUE ||
         Track4Lower[i] == EMPTY_VALUE ||
         KAMAWidthUpper[i] == EMPTY_VALUE ||
         KAMAWidthLower[i] == EMPTY_VALUE)
      {
         TouchTrack3Upper[i] = EMPTY_VALUE;
         TouchTrack3Lower[i] = EMPTY_VALUE;
         continue;
      }

      double track4Upper = Track4Upper[i];
      double track4Lower = Track4Lower[i];
      double kamaWidthUpper = KAMAWidthUpper[i];
      double kamaWidthLower = KAMAWidthLower[i];

      double track1Upper = (track4Upper + kamaWidthUpper) * 0.5;
      double track2Upper = MathMin(track4Upper, kamaWidthUpper);
      double track1Lower = (track4Lower + kamaWidthLower) * 0.5;
      double track2Lower = MathMax(track4Lower, kamaWidthLower);

      TouchTrack3Upper[i] = (track1Upper + track2Upper) * 0.5;
      TouchTrack3Lower[i] = (track1Lower + track2Lower) * 0.5;
   }

   // 实时触轨对象固定为触点轨3。
   // 第六阶段：实时报价实时触轨标记
   // 使用每次报价进行判断，不等待K线收盘；历史 high/low 仅用于统计估算。
   // 卖出观察：Bid必须向上移动，并穿越上一次报价时的上轨位置，
   //           同时当前Bid仍在当前上轨或其上方。
   // 买入观察：Ask必须向下移动，并穿越上一次报价时的下轨位置，
   //           同时当前Ask仍在当前下轨或其下方。
   // 报价一旦穿越触轨条件，立即在当前K线上绘制标记，不等待K线完成；触发后本根K线不重复标记。

   if(prev_calculated == 0)
   {
      ArrayInitialize(SellTouchArrow, EMPTY_VALUE);
      ArrayInitialize(BuyTouchArrow, EMPTY_VALUE);
      gLastArrowBarTime = time[0];
      gSellTriggeredThisBar = false;
      gBuyTriggeredThisBar = false;
      gHasPreviousQuote = false;
      gPrevBid = 0.0;
      gPrevAsk = 0.0;
      gPrevTouchTrack3Upper = EMPTY_VALUE;
      gPrevTouchTrack3Lower = EMPTY_VALUE;
   }

   // 新K线开始时，允许新的一轮信号；已完成K线的箭头保留。
   if(gLastArrowBarTime != time[0])
   {
      gLastArrowBarTime = time[0];
      gSellTriggeredThisBar = false;
      gBuyTriggeredThisBar = false;
      SellTouchArrow[0] = EMPTY_VALUE;
      BuyTouchArrow[0] = EMPTY_VALUE;
   }

   if(!InpShowTouchArrows)
   {
      SellTouchArrow[0] = EMPTY_VALUE;
      BuyTouchArrow[0] = EMPTY_VALUE;
   }
   else if(TouchTrack3Upper[0] != EMPTY_VALUE &&
           TouchTrack3Lower[0] != EMPTY_VALUE)
   {
      MqlTick currentTick;
      if(SymbolInfoTick(_Symbol, currentTick))
      {
         double currentBid = currentTick.bid;
         double currentAsk = currentTick.ask;
         double currentUpper = TouchTrack3Upper[0];
         double currentLower = TouchTrack3Lower[0];

         if(gHasPreviousQuote &&
            gPrevTouchTrack3Upper != EMPTY_VALUE &&
            gPrevTouchTrack3Lower != EMPTY_VALUE)
         {
            // 先检查近期是否已有同方向信号，避免连续K线重复标记。
            bool recentSell = false;
            bool recentBuy = false;
            if(InpEnableTouchSpacing)
            {
               int spacing = MathMax(1, InpTouchSpacingBars);
               for(int k = 1; k < rates_total && k <= spacing; k++)
               {
                  if(SellTouchArrow[k] != EMPTY_VALUE)
                     recentSell = true;
                  if(BuyTouchArrow[k] != EMPTY_VALUE)
                     recentBuy = true;
               }
            }

            // 实时触轨：当前Bid/Ask到达或越过当前轨道即标记，不等待K线收盘。
            // 取消“必须穿越上一报价轨道”的多重限制，避免动态轨道变化造成漏标。
            bool sellTouch =
               !gSellTriggeredThisBar &&
               !recentSell &&
               currentBid >= currentUpper;

            bool buyTouch =
               !gBuyTriggeredThisBar &&
               !recentBuy &&
               currentAsk <= currentLower;

            if(sellTouch)
            {
               SellTouchArrow[0] = currentUpper;
               DrawTouchMarker(time[0], currentUpper, true);
               gSellTriggeredThisBar = true;
            }

            if(buyTouch)
            {
               BuyTouchArrow[0] = currentLower;
               DrawTouchMarker(time[0], currentLower, false);
               gBuyTriggeredThisBar = true;
            }
         }

         // 保存本次报价及本次报价对应的轨道值，供下一次报价比较。
         gPrevBid = currentBid;
         gPrevAsk = currentAsk;
         gPrevTouchTrack3Upper = currentUpper;
         gPrevTouchTrack3Lower = currentLower;
         gHasPreviousQuote = true;
      }
   }

   UpdateStatsDisplay(rates_total, time, high, low);

   return rates_total;
}

//====================================================================
// 统计界面
//====================================================================

void CreateStatsUI()
{
   // 统计面板：总计、近10天汇总、说明、最近10个自然日逐日统计。
   string names[13];
   names[0] = gStatsLabelName;
   names[1] = gStatsRecentName;
   names[2] = gStatsNoteName;
   for(int d=0; d<10; d++)
      names[3+d] = gObjectPrefix + "Day_" + IntegerToString(d);

   for(int j=0; j<13; j++)
   {
      if(ObjectFind(0,names[j]) < 0)
         ObjectCreate(0,names[j],OBJ_LABEL,0,0,0);

      ObjectSetInteger(0,names[j],OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,names[j],OBJPROP_XDISTANCE,10);
      ObjectSetInteger(0,names[j],OBJPROP_YDISTANCE,18+j*17);
      ObjectSetInteger(0,names[j],OBJPROP_FONTSIZE,10);
      ObjectSetInteger(0,names[j],OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,names[j],OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,names[j],OBJPROP_SELECTABLE,false);
   }
}

// 历史统计使用已完成K线的触轨价进行模拟。
// 价格差换算沿用本指标规则：价格差×10。
// 同向触点分别开仓，反向触点平掉所有反向持仓；逐笔独立计算。
// 当前未收盘K线不参与历史统计。历史K线只知道 high/low，不能还原同根K线内真实触轨先后顺序，
// 因此同根K线同时触及上下轨时跳过，避免虚构交易顺序。
void UpdateStatsDisplay(const int total,
                        const datetime &time[],
                        const double &high[],
                        const double &low[])
{
   if(ObjectFind(0,gStatsLabelName) < 0)
      return;

   int maxTrades = MathMax(100,total);
   int posDir[];
   double posEntry[];
   ArrayResize(posDir,maxTrades);
   ArrayResize(posEntry,maxTrades);
   int openCount=0;

   int completed=0, wins=0, losses=0;
   double netPoints=0.0, grossWin=0.0, grossLoss=0.0;
   int recentCompleted=0, recentWins=0, recentLosses=0;
   double recentNet=0.0;
   datetime nowTime = TimeCurrent();
   datetime cutoff = nowTime - 10*24*60*60;

   int dailyCompleted[10];
   int dailyWins[10];
   int dailyLosses[10];
   double dailyNet[10];
   for(int d=0; d<10; d++)
   {
      dailyCompleted[d]=0;
      dailyWins[d]=0;
      dailyLosses[d]=0;
      dailyNet[d]=0.0;
   }

   MqlDateTime todayParts;
   TimeToStruct(nowTime,todayParts);
   todayParts.hour=0;
   todayParts.min=0;
   todayParts.sec=0;
   datetime todayMidnight=StructToTime(todayParts);

   int lastSignalDir=0;
   int lastSignalIndex=-1000000;

   // 从最旧已完成K线向最新已完成K线模拟，排除当前未收盘K线。
   for(int i=total-1; i>=1; i--)
   {
      double upper=TouchTrack3Upper[i];
      double lower=TouchTrack3Lower[i];
      if(upper==EMPTY_VALUE || lower==EMPTY_VALUE)
         continue;

      bool sellTouch = (high[i] >= upper);
      bool buyTouch  = (low[i] <= lower);
      if(sellTouch && buyTouch)
         continue;
      if(!sellTouch && !buyTouch)
         continue;

      int signalDir = sellTouch ? -1 : 1;

      // 同方向信号间隔过滤；反向信号不受间隔限制。
      if(signalDir==lastSignalDir &&
         InpEnableTouchSpacing &&
         (lastSignalIndex-i) < MathMax(1,InpTouchSpacingBars))
         continue;

      double exitPrice = sellTouch ? upper : lower;

      // 反向触点平掉全部反向持仓，每笔独立统计。
      for(int p=openCount-1; p>=0; p--)
      {
         if(posDir[p] == signalDir)
            continue;

         double points = (posDir[p] == 1)
                         ? (exitPrice-posEntry[p])*10.0
                         : (posEntry[p]-exitPrice)*10.0;

         completed++;
         netPoints += points;
         if(points >= 0.0)
         {
            wins++;
            grossWin += points;
         }
         else
         {
            losses++;
            grossLoss += points;
         }

         if(time[i] >= cutoff)
         {
            recentCompleted++;
            recentNet += points;
            if(points >= 0.0) recentWins++;
            else recentLosses++;

            // 按自然日分桶：今天为0，昨天为1，依此类推。
            MqlDateTime tradeParts;
            TimeToStruct(time[i],tradeParts);
            tradeParts.hour=0;
            tradeParts.min=0;
            tradeParts.sec=0;
            datetime tradeMidnight=StructToTime(tradeParts);
            int dayIndex=(int)((todayMidnight-tradeMidnight)/86400);

            if(dayIndex>=0 && dayIndex<10)
            {
               dailyCompleted[dayIndex]++;
               dailyNet[dayIndex]+=points;
               if(points>=0.0) dailyWins[dayIndex]++;
               else dailyLosses[dayIndex]++;
            }
         }

         for(int q=p; q<openCount-1; q++)
         {
            posDir[q]=posDir[q+1];
            posEntry[q]=posEntry[q+1];
         }
         openCount--;
      }

      // 每次触点开一笔新模拟单。
      if(openCount < maxTrades)
      {
         posDir[openCount]=signalDir;
         posEntry[openCount]=exitPrice;
         openCount++;
      }

      lastSignalDir=signalDir;
      lastSignalIndex=i;
   }

   double winRate = completed>0 ? 100.0*wins/completed : 0.0;
   double recentRate = recentCompleted>0 ? 100.0*recentWins/recentCompleted : 0.0;
   double avgWin = wins>0 ? grossWin/wins : 0.0;
   double avgLoss = losses>0 ? grossLoss/losses : 0.0;
   string textOut = StringFormat(
      "触点轨3总计：完成%d笔 胜%d/负%d 胜率%.1f%% 净点数%.1f",
      completed,wins,losses,winRate,netPoints);
   string recentOut = StringFormat(
      "近10天：完成%d笔 胜率%.1f%% 净点数%.1f | 平均盈利%.1f点 平均亏损%.1f点 | 未平仓%d笔",
      recentCompleted,recentRate,recentNet,avgWin,avgLoss,openCount);

   ObjectSetString(0,gStatsLabelName,OBJPROP_TEXT,textOut);
   ObjectSetString(0,gStatsRecentName,OBJPROP_TEXT,recentOut);
   ObjectSetString(0,gStatsNoteName,OBJPROP_TEXT,
      "历史统计为已完成K线触轨模拟；同根K线同时触及上下轨则跳过；价格差×10");

   // 显示最近10个自然日，每天独立统计。
   for(int d=0; d<10; d++)
   {
      MqlDateTime dayParts;
      TimeToStruct(todayMidnight - d*86400,dayParts);
      string dateText=StringFormat("%04d-%02d-%02d",
                                   dayParts.year,dayParts.mon,dayParts.day);
      double dayRate = dailyCompleted[d]>0
                       ? 100.0*dailyWins[d]/dailyCompleted[d] : 0.0;
      string dailyText;
      if(dailyCompleted[d]>0)
         dailyText=StringFormat("%s：平仓%d笔 胜%d/负%d 胜率%.1f%% 净点数%.1f",
                                dateText,dailyCompleted[d],dailyWins[d],
                                dailyLosses[d],dayRate,dailyNet[d]);
      else
         dailyText=StringFormat("%s：平仓0笔",dateText);

      string objectName=gObjectPrefix + "Day_" + IntegerToString(d);
      if(ObjectFind(0,objectName)>=0)
         ObjectSetString(0,objectName,OBJPROP_TEXT,dailyText);
   }
}

//====================================================================
// 卸载清理
//====================================================================

void OnDeinit(const int reason)
{
   if(gMACDHandle!=INVALID_HANDLE)
      IndicatorRelease(gMACDHandle);

   if(gRSIFastHandle!=INVALID_HANDLE)
      IndicatorRelease(gRSIFastHandle);

   if(gRSISlowHandle!=INVALID_HANDLE)
      IndicatorRelease(gRSISlowHandle);

   if(gWPRFastHandle!=INVALID_HANDLE)
      IndicatorRelease(gWPRFastHandle);

   if(gWPRSlowHandle!=INVALID_HANDLE)
      IndicatorRelease(gWPRSlowHandle);

   if(gADXHandle!=INVALID_HANDLE)
      IndicatorRelease(gADXHandle);

   if(gKDJHandle!=INVALID_HANDLE)
      IndicatorRelease(gKDJHandle);

   // 删除本指标创建的图表对象。
   int total=ObjectsTotal(0,0,-1);

   for(int i=total-1; i>=0; i--)
   {
      string name=ObjectName(0,i,0,-1);

      if(StringFind(name,gObjectPrefix)==0)
         ObjectDelete(0,name);
   }
}
//+------------------------------------------------------------------+
