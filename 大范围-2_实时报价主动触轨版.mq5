//+------------------------------------------------------------------+
//| NMNX_TwoTrack_Core_v1.10.mq5                                     |
//| 南门拈星：KAMA宽度通道 + 融合轨4核心实验版                       |
//| 说明：双轨核心实验版，改为实时报价主动穿越触发并锁定信号。       |
//| 注意：本版尚未经过 MetaEditor 实际编译。                          |
//+------------------------------------------------------------------+
#property strict
#property version   "1.10"
#property description "NMNX独立双轨核心：KAMA宽度通道、融合轨4、实时报价主动触轨箭头"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

//--- KAMA宽度通道上轨
#property indicator_label1  "KAMA宽度上轨"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrAqua
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- KAMA宽度通道下轨
#property indicator_label2  "KAMA宽度下轨"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrAqua
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- 融合轨4上轨
#property indicator_label3  "融合轨4上轨"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrWhite
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

//--- 融合轨4下轨
#property indicator_label4  "融合轨4下轨"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrWhite
#property indicator_style4  STYLE_DASH
#property indicator_width4  2

//--- 上轨触碰卖出观察箭头
#property indicator_label5  "上轨触碰卖出观察"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrTomato
#property indicator_width5  2

//--- 下轨触碰买入观察箭头
#property indicator_label6  "下轨触碰买入观察"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrLime
#property indicator_width6  2

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
input int      InpArrowOffsetPoints    = 20;

//====================================================================
// 绘图缓冲区
//====================================================================

double KAMAWidthUpper[];
double KAMAWidthLower[];
double Track4Upper[];
double Track4Lower[];
double SellTouchArrow[];
double BuyTouchArrow[];

//====================================================================
// 内部计算数组
//====================================================================

double FastLine[];
double KAMALine[];
double KAMAUpper[];
double KAMALower[];
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

string gObjectPrefix = "NMNX_TwoTrack_Core_";

//--- 实时报价触轨状态：只记录报价主动穿越轨道的信号
datetime gLastArrowBarTime = 0;
double gPrevBid = 0.0;
double gPrevAsk = 0.0;
double gPrevTrack4Upper = EMPTY_VALUE;
double gPrevTrack4Lower = EMPTY_VALUE;
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
      KAMAUpper[i] == EMPTY_VALUE ||
      KAMALower[i] == EMPTY_VALUE ||
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
   double kamaHalfUp = MathMax(0.0, KAMAUpper[i] - KAMALine[i]);
   double kamaHalfDown = MathMax(0.0, KAMALine[i] - KAMALower[i]);

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
   SetIndexBuffer(0,KAMAWidthUpper,INDICATOR_DATA);
   SetIndexBuffer(1,KAMAWidthLower,INDICATOR_DATA);
   SetIndexBuffer(2,Track4Upper,INDICATOR_DATA);
   SetIndexBuffer(3,Track4Lower,INDICATOR_DATA);
   SetIndexBuffer(4,SellTouchArrow,INDICATOR_DATA);
   SetIndexBuffer(5,BuyTouchArrow,INDICATOR_DATA);

   ArraySetAsSeries(KAMAWidthUpper,true);
   ArraySetAsSeries(KAMAWidthLower,true);
   ArraySetAsSeries(Track4Upper,true);
   ArraySetAsSeries(Track4Lower,true);
   ArraySetAsSeries(SellTouchArrow,true);
   ArraySetAsSeries(BuyTouchArrow,true);

   PlotIndexSetInteger(4,PLOT_ARROW,234);
   PlotIndexSetInteger(5,PLOT_ARROW,233);

   for(int p=0; p<6; p++)
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
      Print("NMNX双轨：创建一个或多个指标句柄失败。");
      return INIT_FAILED;
   }

   IndicatorSetString(
      INDICATOR_SHORTNAME,
      "NMNX双轨核心 v1.00");

   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);

   return INIT_SUCCEEDED;
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
   ArrayResize(FastLine,rates_total);
   ArrayResize(KAMALine,rates_total);
   ArrayResize(KAMAUpper,rates_total);
   ArrayResize(KAMALower,rates_total);
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

   ArraySetAsSeries(FastLine,true);
   ArraySetAsSeries(KAMALine,true);
   ArraySetAsSeries(KAMAUpper,true);
   ArraySetAsSeries(KAMALower,true);
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

      KAMAUpper[i]=KAMALine[i]+wKAMA;
      KAMALower[i]=KAMALine[i]-wKAMA;

      double kamaHalfUp =
         MathMax(0.0,KAMAUpper[i]-KAMALine[i]);

      double kamaHalfDown =
         MathMax(0.0,KAMALine[i]-KAMALower[i]);

      double scale=MathMax(0.01,InpFast_KAMAWidth_Scale);

      KAMAWidthUpper[i] =
         FastLine[i]+kamaHalfUp*scale+InpKAMA_UpperOffset;

      KAMAWidthLower[i] =
         FastLine[i]-kamaHalfDown*scale+InpKAMA_LowerOffset;
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

   // 第四阶段：实时报价主动触轨
   // 不再使用整根K线的 high/low 判断，避免轨道移动追上价格时产生假信号。
   // 卖出观察：Bid必须向上移动，并穿越上一次报价时的上轨位置，
   //           同时当前Bid仍在当前上轨或其上方。
   // 买入观察：Ask必须向下移动，并穿越上一次报价时的下轨位置，
   //           同时当前Ask仍在当前下轨或其下方。
   // 信号触发后锁定到本根K线结束，不随轨道后续移动而改价或撤销。

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
      gPrevTrack4Upper = EMPTY_VALUE;
      gPrevTrack4Lower = EMPTY_VALUE;
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
   else if(Track4Upper[0] != EMPTY_VALUE &&
           Track4Lower[0] != EMPTY_VALUE)
   {
      MqlTick currentTick;
      if(SymbolInfoTick(_Symbol, currentTick))
      {
         double currentBid = currentTick.bid;
         double currentAsk = currentTick.ask;
         double currentUpper = Track4Upper[0];
         double currentLower = Track4Lower[0];

         if(gHasPreviousQuote &&
            gPrevTrack4Upper != EMPTY_VALUE &&
            gPrevTrack4Lower != EMPTY_VALUE)
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

            // 上轨卖出观察：必须是Bid向上移动并穿越前一报价时的上轨。
            // 若只是上轨向下移动到Bid附近，currentBid不会满足穿越条件。
            bool sellTouch =
               !gSellTriggeredThisBar &&
               !recentSell &&
               currentBid > gPrevBid &&
               gPrevBid < gPrevTrack4Upper &&
               currentBid >= gPrevTrack4Upper &&
               currentBid >= currentUpper;

            // 下轨买入观察：必须是Ask向下移动并穿越前一报价时的下轨。
            // 若只是下轨向上移动到Ask附近，currentAsk不会满足穿越条件。
            bool buyTouch =
               !gBuyTriggeredThisBar &&
               !recentBuy &&
               currentAsk < gPrevAsk &&
               gPrevAsk > gPrevTrack4Lower &&
               currentAsk <= gPrevTrack4Lower &&
               currentAsk <= currentLower;

            if(sellTouch)
            {
               SellTouchArrow[0] = currentUpper;
               gSellTriggeredThisBar = true;
            }

            if(buyTouch)
            {
               BuyTouchArrow[0] = currentLower;
               gBuyTriggeredThisBar = true;
            }
         }

         // 保存本次报价及本次报价对应的轨道值，供下一次报价比较。
         gPrevBid = currentBid;
         gPrevAsk = currentAsk;
         gPrevTrack4Upper = currentUpper;
         gPrevTrack4Lower = currentLower;
         gHasPreviousQuote = true;
      }
   }

   return rates_total;
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
