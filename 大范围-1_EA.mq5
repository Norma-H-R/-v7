//+------------------------------------------------------------------+
//| 大范围-1_EA.mq5                                                   |
//| 南门拈星：原指标计算链单文件移植版                                   |
//| 后台计算原始轨道，融合轨4触轨交易；不绘制指标或统计面板。              |
//| 触点判定改为逐tick实时判定：价格在运动中碰到外轨即锁定，不等收盘。     |
//+------------------------------------------------------------------+
#property version   "3.10"
#property description "NMNX 单文件EA：直接移植原始轨道计算，后台计算不绘制指标。"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| 输入参数                                                          |
//+------------------------------------------------------------------+
input group "01 · 基础线"
input int    InpFastEMA_Period       = 3;       // 快速响应线周期，建议 2-5
input int    InpKAMA_ER_Period       = 8;       // KAMA效率比周期
input int    InpKAMA_Fast_Period     = 2;       // KAMA快速周期
input int    InpKAMA_Slow_Period     = 20;      // KAMA慢速周期

input group "02 · 通道宽度"
input int    InpATR_Period           = 7;       // 波动测量周期
input int    InpResidual_Period      = 10;      // 残差测量周期
input double InpATR_Min_Multiplier   = 0.35;    // 通道最小半宽 = ATR × 此系数
input double InpResidual_Multiplier  = 1.00;    // 通道残差半宽系数
input double InpKAMA_Width_Mult      = 1.00;    // KAMA通道宽度调整
input double InpFast_KAMAWidth_Scale = 1.00;    // 参考轨半宽缩放：1.00为原样

input group "03 · 融合轨4：综合动能驱离引擎"
input bool   InpEnableFusionTrack4   = true;    // 启用融合轨4计算
input int    InpTrack4_MACD_Fast     = 7;       // MACD快周期
input int    InpTrack4_MACD_Slow     = 14;      // MACD慢周期
input int    InpTrack4_MACD_Signal   = 5;       // MACD信号周期
input int    InpTrack4_RSI_Fast      = 7;       // RSI快周期
input int    InpTrack4_RSI_Slow      = 17;      // RSI慢周期
input int    InpTrack4_WPR_Fast      = 7;       // WPR快周期
input int    InpTrack4_WPR_Slow      = 14;      // WPR慢周期
input int    InpTrack4_ADX_Period    = 7;       // ADX与+DI/-DI周期
input int    InpTrack4_KDJ_K         = 5;       // KDJ的K周期
input int    InpTrack4_KDJ_D         = 3;       // KDJ的D周期
input int    InpTrack4_KDJ_Slowing   = 3;       // KDJ平滑周期
input double InpTrack4_MaxDrive_ATR  = 2.20;    // 顺势外侧轨最大驱离距离：ATR倍数
input double InpTrack4_MaxLift_ATR   = 0.85;    // 顺势内侧轨最大抬升/压低距离：ATR倍数
input double InpTrack4_ADX_Weak      = 14.0;    // ADX低于该值时趋势贡献较弱
input double InpTrack4_ADX_Strong    = 32.0;    // ADX达到该值时趋势强度归一化封顶
input double InpTrack4_ExpandSpeed   = 0.22;    // 驱离扩张速度
input double InpTrack4_RecoilSpeed   = 0.68;    // 动能减弱后的回收速度

input group "05 · EA交易设置"
input double InpLots=0.01;                         // 交易手数
input double InpStopLossPriceDistance=20.0;        // 价格距离，例如黄金4500买入，止损4480
input ulong  InpMagicNumber=1700529;               // EA魔术号
input int    InpDeviationPoints=30;                // 允许滑点（点）
input bool   InpAllowBuy=true;
input bool   InpAllowSell=true;
input bool   InpSameDirectionSpacingFilter=true;   // 同方向信号间隔3根K线
input bool   InpTradeExistingCurrentBarSignal=false;
input bool   InpShowKAMAReferenceRails=false;       // 只控制绘图，不影响计算
input bool   InpShowFusionTrack4Rails=false;        // 只控制绘图，不影响计算
input int    InpDisplayBars=250;
input int    InpCalculationBars=3000;
input double InpKAMAReferenceUpperOffset=0.0;
input double InpKAMAReferenceLowerOffset=0.0;
input double InpFusion4UpperOffset=0.0;
input double InpFusion4LowerOffset=0.0;

//+------------------------------------------------------------------+
//| 指标缓冲区与内部数组                                              |
//+------------------------------------------------------------------+
double FastKAMAWidthUpper[], FastKAMAWidthLower[];
double Composite4Upper[], Composite4Lower[];
double SellTouchArrow[], BuyTouchArrow[];

double FastLine[], KAMALine[], KAMAUpper[], KAMALower[];
double Atr[];
double Composite4BaseUpper[], Composite4BaseLower[];
double Track4DriveUpper[], Track4DriveLower[], Track4Energy[];
double Track4MACDMain[], Track4MACDSignal[], Track4RSI7[], Track4RSI17[];
double Track4WPR7[], Track4WPR14[], Track4K[], Track4D[], Track4ADX[], Track4PlusDI[], Track4MinusDI[];

// 实时触点记忆：价格在K线形成过程中一旦触碰即锁定，收盘后不再重新判定
bool   TouchUpperFlag[], TouchLowerFlag[];
double TouchUpperPrice[], TouchLowerPrice[];

int gTrack4MACDHandle=INVALID_HANDLE,gTrack4RSI7Handle=INVALID_HANDLE,gTrack4RSI17Handle=INVALID_HANDLE;
int gTrack4WPR7Handle=INVALID_HANDLE,gTrack4WPR14Handle=INVALID_HANDLE,gTrack4ADXHandle=INVALID_HANDLE,gTrack4KDJHandle=INVALID_HANDLE;

//+------------------------------------------------------------------+
//| 盘面状态                                                          |
//+------------------------------------------------------------------+
#define UI_PREFIX          "NMNX_CF30_"
#define STATS_LINE_COUNT   24
#define KAMA_OFFSET_STEP   0.1
#define TRACK4_OFFSET_STEP 0.01

#define Y_STATS_TOGGLE  404
#define Y_TOUCH_FILTER  432
#define Y_KAMA_OFFSET   470
#define Y_TRACK4_OFFSET 530
#define Y_RAIL_BUTTONS  615

bool   gLiteRailVisible[4]={true,true,true,true}; // 四条轨道仅控制绘制，不影响计算
bool   gStatsEnabled=true;                        // 关闭后不运行历史盈亏统计计算
bool   gTouchSpacingFilter=true;                  // 默认开启：同方向3根K线内只接受一个触点
bool   gStatsDirty=true;                          // 轨道或新K线变化后需要刷新统计
bool   gArrowDirty=true;                          // 仅箭头需要刷新
double gKamaUpOffset=0.0;                         // KAMA参考上轨人工偏移
double gKamaDownOffset=0.0;                       // KAMA参考下轨人工偏移
double gTrack4UpperOffset=0.0;                    // 融合轨4上轨人工偏移
double gTrack4LowerOffset=0.0;                    // 融合轨4下轨人工偏移
int    gCachedRatesTotal=0;
CTrade trade;
datetime gEAbarTime=0, gLastAcceptedSignalTime=0;
int gLastAcceptedDirection=0;
bool gEALatchedUpper=false, gEALatchedLower=false;
bool gEAFirstTick=true;
MqlRates gEABars[];
datetime gTime[];
double gOpen[],gHigh[],gLow[],gClose[];
string EA_OBJECT_PREFIX="NMNX_EA_SINGLE_";

// 已经烘焙进缓冲区的偏移量：按钮只做增量平移，避免整段重建引入横向错位
double gAppliedKamaUp=0.0, gAppliedKamaDown=0.0;
double gAppliedTrack4Up=0.0, gAppliedTrack4Down=0.0;

string gT4Rail[2]={"UP","DN"};
string gT4Part[3]={"DEC","VAL","INC"};
string gRailLabels[4]={"KAMA参考上轨","KAMA参考下轨","融合轨4上轨","融合轨4下轨"};

//+------------------------------------------------------------------+
//| 公共计算                                                          |
//+------------------------------------------------------------------+
double ClampValue(const double v,const double lo,const double hi)
  {
   return MathMax(lo,MathMin(hi,v));
  }

double ResidualRMSAt(const int i,const int period,const int total,
                     const double &close[],const double &line[])
  {
   int n=MathMax(1,MathMin(period,total-i));
   double sum=0.0;
   for(int j=0;j<n;j++)
     {
      double d=close[i+j]-line[i+j];
      sum+=d*d;
     }
   return MathSqrt(sum/n);
  }

//+------------------------------------------------------------------+
//| 触点判定                                                          |
//| 已收盘K线：历史无法逐tick回放，用 high/low 对最终轨道值判定；        |
//| 正在形成的K线(i=0)：只用实时锁定标志，收盘前就已经判定并锁死。       |
//+------------------------------------------------------------------+
bool BarTouchedUpper(const int i,const double &high[])
  {
   if(i==0) return TouchUpperFlag[0];
   return (TouchUpperFlag[i] || high[i]>=Composite4Upper[i]);
  }

bool BarTouchedLower(const int i,const double &low[])
  {
   if(i==0) return TouchLowerFlag[0];
   return (TouchLowerFlag[i] || low[i]<=Composite4Lower[i]);
  }

double BarTouchPriceUpper(const int i)
  {
   if(TouchUpperFlag[i] && TouchUpperPrice[i]!=EMPTY_VALUE && MathIsValidNumber(TouchUpperPrice[i]))
      return TouchUpperPrice[i];
   return Composite4Upper[i];
  }

double BarTouchPriceLower(const int i)
  {
   if(TouchLowerFlag[i] && TouchLowerPrice[i]!=EMPTY_VALUE && MathIsValidNumber(TouchLowerPrice[i]))
      return TouchLowerPrice[i];
   return Composite4Lower[i];
  }

// direction=+1 下轨多头，-1 上轨空头；返回该次触轨的理论成交价
double TouchPriceForDirection(const int direction,const int i)
  {
   if(direction==1)  return BarTouchPriceLower(i);
   if(direction==-1) return BarTouchPriceUpper(i);
   return EMPTY_VALUE;
  }

//+------------------------------------------------------------------+
//| 实时触点监测（核心修复）                                          |
//| 每收到一个报价，就用当前K线运行中的最高/最低与此刻的轨道值比较，     |
//| 一旦触碰立即锁定并记录触碰瞬间的轨道价，绝不等K线收盘后再判断。      |
//+------------------------------------------------------------------+
void UpdateLiveTouch(const double barHigh,const double barLow)
  {
   if(Composite4Upper[0]==EMPTY_VALUE || Composite4Lower[0]==EMPTY_VALUE) return;
   if(!MathIsValidNumber(Composite4Upper[0]) || !MathIsValidNumber(Composite4Lower[0])) return;
   bool latched=false;
   double trackUp=Composite4Upper[0];
   double trackDown=Composite4Lower[0];
   if(!TouchUpperFlag[0] && barHigh>=trackUp)
     {
      TouchUpperFlag[0]=true;
      TouchUpperPrice[0]=trackUp;
      latched=true;
     }
   if(!TouchLowerFlag[0] && barLow<=trackDown)
     {
      TouchLowerFlag[0]=true;
      TouchLowerPrice[0]=trackDown;
      latched=true;
     }
   if(latched)
     {
      gStatsDirty=true;
      gArrowDirty=true;
     }
  }

void CalculateTrack4At(const int i,const int total,const double &open[],const double &close[],const bool dataReady)
  {
   if(!InpEnableFusionTrack4 || !dataReady || i+3>=total ||
      KAMALine[i]==EMPTY_VALUE || KAMAUpper[i]==EMPTY_VALUE || KAMALower[i]==EMPTY_VALUE || FastLine[i]==EMPTY_VALUE ||
      Track4MACDMain[i]==EMPTY_VALUE || Track4MACDSignal[i]==EMPTY_VALUE ||
      Track4MACDMain[i+1]==EMPTY_VALUE || Track4MACDSignal[i+1]==EMPTY_VALUE ||
      Track4RSI7[i]==EMPTY_VALUE || Track4RSI17[i]==EMPTY_VALUE ||
      Track4WPR7[i]==EMPTY_VALUE || Track4WPR14[i]==EMPTY_VALUE ||
      Track4K[i]==EMPTY_VALUE || Track4D[i]==EMPTY_VALUE || Track4ADX[i]==EMPTY_VALUE ||
      Track4PlusDI[i]==EMPTY_VALUE || Track4MinusDI[i]==EMPTY_VALUE)
     {
      Composite4BaseUpper[i]=EMPTY_VALUE;
      Composite4BaseLower[i]=EMPTY_VALUE;
      Composite4Upper[i]=EMPTY_VALUE;
      Composite4Lower[i]=EMPTY_VALUE;
      Track4DriveUpper[i]=0.0;
      Track4DriveLower[i]=0.0;
      Track4Energy[i]=0.0;
      return;
     }

   double atrScale=MathMax(Atr[i],_Point*2.0);
   double widthScale=MathMax(0.01,InpFast_KAMAWidth_Scale);
   double kamaHalfUp=MathMax(0.0,KAMAUpper[i]-KAMALine[i]);
   double kamaHalfDown=MathMax(0.0,KAMALine[i]-KAMALower[i]);
   double baseUpper=FastLine[i]+kamaHalfUp*widthScale;
   double baseLower=FastLine[i]-kamaHalfDown*widthScale;

   double rsi7=Track4RSI7[i];
   double rsi17=Track4RSI17[i];
   double wpr7=Track4WPR7[i];
   double wpr14=Track4WPR14[i];
   double macdHist=Track4MACDMain[i]-Track4MACDSignal[i];
   double macdHistOld=Track4MACDMain[i+1]-Track4MACDSignal[i+1];
   double k=Track4K[i];
   double d=Track4D[i];
   double j=3.0*k-2.0*d; // KDJ的J线由K、D计算得出
   double adx=Track4ADX[i];
   double plusDI=Track4PlusDI[i];
   double minusDI=Track4MinusDI[i];

   // 各组指标归一化至[-1,+1]，避免将不同量纲的原始值直接相加。
   double rsiScore=0.60*ClampValue((rsi7-rsi17)/15.0,-1.0,1.0)
                  +0.40*ClampValue((rsi17-50.0)/25.0,-1.0,1.0);
   double wprScore=0.60*ClampValue((wpr7-wpr14)/25.0,-1.0,1.0)
                  +0.40*ClampValue((wpr14+50.0)/35.0,-1.0,1.0);
   double macdLevel=ClampValue(macdHist/MathMax(atrScale*0.12,_Point),-1.0,1.0);
   double macdChange=ClampValue((macdHist-macdHistOld)/MathMax(atrScale*0.08,_Point),-1.0,1.0);
   double macdScore=0.70*macdLevel+0.30*macdChange;
   double kdjScore=0.45*ClampValue((k-d)/20.0,-1.0,1.0)
                  +0.35*ClampValue((j-50.0)/45.0,-1.0,1.0)
                  +0.20*ClampValue((k-50.0)/35.0,-1.0,1.0);
   double diDenom=MathMax(plusDI+minusDI,1.0);
   double diScore=ClampValue((plusDI-minusDI)/diDenom,-1.0,1.0);
   double priceSlope=ClampValue((close[i]-close[i+3])/MathMax(atrScale*1.50,_Point),-1.0,1.0);
   double candleBody=ClampValue((close[i]-open[i])/MathMax(atrScale*0.80,_Point),-1.0,1.0);
   double priceScore=0.70*priceSlope+0.30*candleBody;

   // 权重合计为1.00。震荡指标组不单独重复叠加极值票，减轻 RSI/WPR/KDJ 的相关性。
   double directionScore=0.18*rsiScore+0.14*wprScore+0.24*macdScore
                        +0.14*kdjScore+0.18*diScore+0.12*priceScore;
   directionScore=ClampValue(directionScore,-1.0,1.0);

   double adxStrength=ClampValue((adx-InpTrack4_ADX_Weak)/
                                 MathMax(InpTrack4_ADX_Strong-InpTrack4_ADX_Weak,1.0),0.0,1.0);
   double priceContinuity=ClampValue(MathAbs(close[i]-close[i+3])/
                                     MathMax(atrScale*1.20,_Point),0.0,1.0);
   double rawDirectionalEnergy=ClampValue((MathAbs(directionScore)-0.08)/0.92,0.0,1.0);
   double energy=ClampValue(rawDirectionalEnergy*(0.15+0.85*adxStrength)
                           *(0.08+0.92*priceContinuity),0.0,1.0);
   Track4Energy[i]=energy;

   double targetUpper=0.0;
   double targetLower=0.0;
   if(directionScore>0.0)
     {
      // 多头：上轨向外驱离，下轨向上抬升；两者使用不同最大幅度。
      targetUpper=atrScale*InpTrack4_MaxDrive_ATR*energy;
      targetLower=atrScale*InpTrack4_MaxLift_ATR*energy;
     }
   else if(directionScore<0.0)
     {
      // 空头镜像：下轨向外驱离，上轨向下压低。
      targetUpper=-atrScale*InpTrack4_MaxLift_ATR*energy;
      targetLower=-atrScale*InpTrack4_MaxDrive_ATR*energy;
     }

   double previousUpper=0.0,previousLower=0.0,previousEnergy=0.0;
   if(i+1<total)
     {
      previousUpper=Track4DriveUpper[i+1];
      previousLower=Track4DriveLower[i+1];
      previousEnergy=Track4Energy[i+1];
     }
   double expandRate=ClampValue(InpTrack4_ExpandSpeed,0.01,1.0);
   double recoilBase=ClampValue(InpTrack4_RecoilSpeed,0.01,1.0);
   double energyFade=ClampValue((previousEnergy-energy)*1.50,0.0,1.0);

   bool upperExpanding=((previousUpper==0.0 || targetUpper*previousUpper>0.0) && MathAbs(targetUpper)>MathAbs(previousUpper));
   bool lowerExpanding=((previousLower==0.0 || targetLower*previousLower>0.0) && MathAbs(targetLower)>MathAbs(previousLower));
   double upperRate=(upperExpanding ? expandRate : ClampValue(recoilBase+0.20*energyFade,recoilBase,0.95));
   double lowerRate=(lowerExpanding ? expandRate : ClampValue(recoilBase+0.20*energyFade,recoilBase,0.95));
   if(i==total-1)
     {
      Track4DriveUpper[i]=targetUpper;
      Track4DriveLower[i]=targetLower;
     }
   else
     {
      Track4DriveUpper[i]=previousUpper+upperRate*(targetUpper-previousUpper);
      Track4DriveLower[i]=previousLower+lowerRate*(targetLower-previousLower);
     }

   Composite4BaseUpper[i]=baseUpper+Track4DriveUpper[i];
   Composite4BaseLower[i]=baseLower+Track4DriveLower[i];
   Composite4Upper[i]=Composite4BaseUpper[i]+gTrack4UpperOffset;
   Composite4Lower[i]=Composite4BaseLower[i]+gTrack4LowerOffset;
  }

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 反初始化                                                          |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| 主计算                                                            |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(_Period!=PERIOD_M5)
     {
      Print("大范围-1_EA 仅允许在M5图表运行。");
      return INIT_FAILED;
     }
   if(InpFastEMA_Period<1 || InpKAMA_ER_Period<1 || InpKAMA_Fast_Period<1 ||
      InpKAMA_Slow_Period<2 || InpATR_Period<1 || InpResidual_Period<1 ||
      InpATR_Min_Multiplier<0.0 || InpResidual_Multiplier<0.0 ||
      InpKAMA_Width_Mult<=0.0 || InpFast_KAMAWidth_Scale<=0.0 ||
      InpLots<=0.0 || InpStopLossPriceDistance<=0.0 || InpCalculationBars<100)
      return INIT_PARAMETERS_INCORRECT;

   gKamaUpOffset=InpKAMAReferenceUpperOffset;
   gKamaDownOffset=InpKAMAReferenceLowerOffset;
   gTrack4UpperOffset=InpFusion4UpperOffset;
   gTrack4LowerOffset=InpFusion4LowerOffset;
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints((ulong)MathMax(0,InpDeviationPoints));
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);

   gTrack4MACDHandle=iMACD(_Symbol,PERIOD_M5,InpTrack4_MACD_Fast,InpTrack4_MACD_Slow,InpTrack4_MACD_Signal,PRICE_CLOSE);
   gTrack4RSI7Handle=iRSI(_Symbol,PERIOD_M5,InpTrack4_RSI_Fast,PRICE_CLOSE);
   gTrack4RSI17Handle=iRSI(_Symbol,PERIOD_M5,InpTrack4_RSI_Slow,PRICE_CLOSE);
   gTrack4WPR7Handle=iWPR(_Symbol,PERIOD_M5,InpTrack4_WPR_Fast);
   gTrack4WPR14Handle=iWPR(_Symbol,PERIOD_M5,InpTrack4_WPR_Slow);
   gTrack4ADXHandle=iADX(_Symbol,PERIOD_M5,InpTrack4_ADX_Period);
   gTrack4KDJHandle=iStochastic(_Symbol,PERIOD_M5,InpTrack4_KDJ_K,InpTrack4_KDJ_D,InpTrack4_KDJ_Slowing,MODE_SMA,STO_LOWHIGH);
   if(gTrack4MACDHandle==INVALID_HANDLE || gTrack4RSI7Handle==INVALID_HANDLE ||
      gTrack4RSI17Handle==INVALID_HANDLE || gTrack4WPR7Handle==INVALID_HANDLE ||
      gTrack4WPR14Handle==INVALID_HANDLE || gTrack4ADXHandle==INVALID_HANDLE ||
      gTrack4KDJHandle==INVALID_HANDLE)
     {
      Print("无法创建原指标使用的内置动能指标句柄。错误=",GetLastError());
      return INIT_FAILED;
     }
   gEAbarTime=iTime(_Symbol,PERIOD_M5,0);
   Print("大范围-1_EA 单文件版启动。原指标轨道计算链已移植；默认不绘制轨道、统计面板或按钮。");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| 卸载                                                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(gTrack4MACDHandle!=INVALID_HANDLE) IndicatorRelease(gTrack4MACDHandle);
   if(gTrack4RSI7Handle!=INVALID_HANDLE) IndicatorRelease(gTrack4RSI7Handle);
   if(gTrack4RSI17Handle!=INVALID_HANDLE) IndicatorRelease(gTrack4RSI17Handle);
   if(gTrack4WPR7Handle!=INVALID_HANDLE) IndicatorRelease(gTrack4WPR7Handle);
   if(gTrack4WPR14Handle!=INVALID_HANDLE) IndicatorRelease(gTrack4WPR14Handle);
   if(gTrack4ADXHandle!=INVALID_HANDLE) IndicatorRelease(gTrack4ADXHandle);
   if(gTrack4KDJHandle!=INVALID_HANDLE) IndicatorRelease(gTrack4KDJHandle);
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string n=ObjectName(0,i,-1,-1);
      if(StringFind(n,EA_OBJECT_PREFIX)==0) ObjectDelete(0,n);
     }
  }

//+------------------------------------------------------------------+
//| 原指标计算主程序：按原始算法计算轨道，不做图表统计                 |
//+------------------------------------------------------------------+
int CalculateCore(const int rates_total,
                  const datetime &time[],
                  const double &open[],
                  const double &high[],
                  const double &low[],
                  const double &close[])
  {
   if(rates_total<MathMax(MathMax(InpKAMA_ER_Period,InpATR_Period),InpResidual_Period)+4)
      return 0;
   bool full=true;
   int start=rates_total-1;
   gCachedRatesTotal=rates_total;

   ArrayResize(FastKAMAWidthUpper,rates_total); ArraySetAsSeries(FastKAMAWidthUpper,true);
   ArrayResize(FastKAMAWidthLower,rates_total); ArraySetAsSeries(FastKAMAWidthLower,true);
   ArrayResize(Composite4Upper,rates_total); ArraySetAsSeries(Composite4Upper,true);
   ArrayResize(Composite4Lower,rates_total); ArraySetAsSeries(Composite4Lower,true);
   ArrayResize(SellTouchArrow,rates_total); ArraySetAsSeries(SellTouchArrow,true);
   ArrayResize(BuyTouchArrow,rates_total); ArraySetAsSeries(BuyTouchArrow,true);
   ArrayInitialize(FastKAMAWidthUpper,EMPTY_VALUE);
   ArrayInitialize(FastKAMAWidthLower,EMPTY_VALUE);
   ArrayInitialize(Composite4Upper,EMPTY_VALUE);
   ArrayInitialize(Composite4Lower,EMPTY_VALUE);
   ArrayInitialize(SellTouchArrow,EMPTY_VALUE);
   ArrayInitialize(BuyTouchArrow,EMPTY_VALUE);

   ArrayResize(FastLine,rates_total); ArraySetAsSeries(FastLine,true);
   ArrayResize(KAMALine,rates_total); ArraySetAsSeries(KAMALine,true);
   ArrayResize(KAMAUpper,rates_total); ArraySetAsSeries(KAMAUpper,true);
   ArrayResize(KAMALower,rates_total); ArraySetAsSeries(KAMALower,true);
   ArrayResize(Atr,rates_total); ArraySetAsSeries(Atr,true);
   ArrayResize(Track4DriveUpper,rates_total); ArraySetAsSeries(Track4DriveUpper,true);
   ArrayResize(Track4DriveLower,rates_total); ArraySetAsSeries(Track4DriveLower,true);
   ArrayResize(Track4Energy,rates_total); ArraySetAsSeries(Track4Energy,true);
   ArrayResize(Composite4BaseUpper,rates_total); ArraySetAsSeries(Composite4BaseUpper,true);
   ArrayResize(Composite4BaseLower,rates_total); ArraySetAsSeries(Composite4BaseLower,true);
   ArrayResize(TouchUpperFlag,rates_total); ArraySetAsSeries(TouchUpperFlag,true);
   ArrayResize(TouchLowerFlag,rates_total); ArraySetAsSeries(TouchLowerFlag,true);
   ArrayResize(TouchUpperPrice,rates_total); ArraySetAsSeries(TouchUpperPrice,true);
   ArrayResize(TouchLowerPrice,rates_total); ArraySetAsSeries(TouchLowerPrice,true);
   ArrayInitialize(TouchUpperFlag,false);
   ArrayInitialize(TouchLowerFlag,false);
   ArrayInitialize(TouchUpperPrice,EMPTY_VALUE);
   ArrayInitialize(TouchLowerPrice,EMPTY_VALUE);

   int copyCount=rates_total;
   if(BarsCalculated(gTrack4MACDHandle)<copyCount || BarsCalculated(gTrack4RSI7Handle)<copyCount ||
      BarsCalculated(gTrack4RSI17Handle)<copyCount || BarsCalculated(gTrack4WPR7Handle)<copyCount ||
      BarsCalculated(gTrack4WPR14Handle)<copyCount || BarsCalculated(gTrack4KDJHandle)<copyCount ||
      BarsCalculated(gTrack4ADXHandle)<copyCount)
      return 0;

   double macdMain[],macdSignal[],rsi7[],rsi17[],wpr7[],wpr14[],kdjK[],kdjD[],adx[],plusDI[],minusDI[];
   ArrayResize(macdMain,copyCount); ArrayResize(macdSignal,copyCount);
   ArrayResize(rsi7,copyCount); ArrayResize(rsi17,copyCount);
   ArrayResize(wpr7,copyCount); ArrayResize(wpr14,copyCount);
   ArrayResize(kdjK,copyCount); ArrayResize(kdjD,copyCount);
   ArrayResize(adx,copyCount); ArrayResize(plusDI,copyCount); ArrayResize(minusDI,copyCount);
   ArraySetAsSeries(macdMain,true); ArraySetAsSeries(macdSignal,true);
   ArraySetAsSeries(rsi7,true); ArraySetAsSeries(rsi17,true);
   ArraySetAsSeries(wpr7,true); ArraySetAsSeries(wpr14,true);
   ArraySetAsSeries(kdjK,true); ArraySetAsSeries(kdjD,true);
   ArraySetAsSeries(adx,true); ArraySetAsSeries(plusDI,true); ArraySetAsSeries(minusDI,true);
   if(CopyBuffer(gTrack4MACDHandle,0,0,copyCount,macdMain)<copyCount ||
      CopyBuffer(gTrack4MACDHandle,1,0,copyCount,macdSignal)<copyCount ||
      CopyBuffer(gTrack4RSI7Handle,0,0,copyCount,rsi7)<copyCount ||
      CopyBuffer(gTrack4RSI17Handle,0,0,copyCount,rsi17)<copyCount ||
      CopyBuffer(gTrack4WPR7Handle,0,0,copyCount,wpr7)<copyCount ||
      CopyBuffer(gTrack4WPR14Handle,0,0,copyCount,wpr14)<copyCount ||
      CopyBuffer(gTrack4KDJHandle,0,0,copyCount,kdjK)<copyCount ||
      CopyBuffer(gTrack4KDJHandle,1,0,copyCount,kdjD)<copyCount ||
      CopyBuffer(gTrack4ADXHandle,0,0,copyCount,adx)<copyCount ||
      CopyBuffer(gTrack4ADXHandle,1,0,copyCount,plusDI)<copyCount ||
      CopyBuffer(gTrack4ADXHandle,2,0,copyCount,minusDI)<copyCount)
      return 0;

   ArrayResize(Track4MACDMain,rates_total); ArraySetAsSeries(Track4MACDMain,true);
   ArrayResize(Track4MACDSignal,rates_total); ArraySetAsSeries(Track4MACDSignal,true);
   ArrayResize(Track4RSI7,rates_total); ArraySetAsSeries(Track4RSI7,true);
   ArrayResize(Track4RSI17,rates_total); ArraySetAsSeries(Track4RSI17,true);
   ArrayResize(Track4WPR7,rates_total); ArraySetAsSeries(Track4WPR7,true);
   ArrayResize(Track4WPR14,rates_total); ArraySetAsSeries(Track4WPR14,true);
   ArrayResize(Track4K,rates_total); ArraySetAsSeries(Track4K,true);
   ArrayResize(Track4D,rates_total); ArraySetAsSeries(Track4D,true);
   ArrayResize(Track4ADX,rates_total); ArraySetAsSeries(Track4ADX,true);
   ArrayResize(Track4PlusDI,rates_total); ArraySetAsSeries(Track4PlusDI,true);
   ArrayResize(Track4MinusDI,rates_total); ArraySetAsSeries(Track4MinusDI,true);
   for(int k=0;k<copyCount;k++)
     {
      Track4MACDMain[k]=macdMain[k]; Track4MACDSignal[k]=macdSignal[k];
      Track4RSI7[k]=rsi7[k]; Track4RSI17[k]=rsi17[k];
      Track4WPR7[k]=wpr7[k]; Track4WPR14[k]=wpr14[k];
      Track4K[k]=kdjK[k]; Track4D[k]=kdjD[k];
      Track4ADX[k]=adx[k]; Track4PlusDI[k]=plusDI[k]; Track4MinusDI[k]=minusDI[k];
     }

   double alphaFast=2.0/(InpFastEMA_Period+1.0);
   double fastSC=2.0/(InpKAMA_Fast_Period+1.0);
   double slowSC=2.0/(InpKAMA_Slow_Period+1.0);
   double widthScale=MathMax(0.01,InpFast_KAMAWidth_Scale);
   for(int i=start;i>=0;i--)
     {
      double tr=high[i]-low[i];
      if(i<rates_total-1)
        {
         tr=MathMax(tr,MathAbs(high[i]-close[i+1]));
         tr=MathMax(tr,MathAbs(low[i]-close[i+1]));
         Atr[i]=(Atr[i+1]*(InpATR_Period-1)+tr)/InpATR_Period;
        }
      else Atr[i]=tr;
      if(i==rates_total-1) FastLine[i]=close[i];
      else FastLine[i]=alphaFast*close[i]+(1.0-alphaFast)*FastLine[i+1];
      if(i==rates_total-1) KAMALine[i]=close[i];
      else
        {
         int oldIndex=MathMin(rates_total-1,i+InpKAMA_ER_Period);
         double change=MathAbs(close[i]-close[oldIndex]),volatility=0.0;
         int endIndex=MathMin(rates_total-1,i+InpKAMA_ER_Period-1);
         for(int j=i;j<=endIndex;j++) if(j+1<rates_total) volatility+=MathAbs(close[j]-close[j+1]);
         double er=(volatility>0.0?change/volatility:0.0);
         er=ClampValue(er,0.0,1.0);
         double sc=er*(fastSC-slowSC)+slowSC; sc*=sc;
         KAMALine[i]=KAMALine[i+1]+sc*(close[i]-KAMALine[i+1]);
        }
      double rms=ResidualRMSAt(i,InpResidual_Period,rates_total,close,KAMALine);
      double half=MathMax(MathMax(Atr[i]*InpATR_Min_Multiplier,rms*InpResidual_Multiplier)*InpKAMA_Width_Mult,_Point*2.0);
      KAMAUpper[i]=KAMALine[i]+half;
      KAMALower[i]=KAMALine[i]-half;
      FastKAMAWidthUpper[i]=FastLine[i]+half*widthScale+gKamaUpOffset;
      FastKAMAWidthLower[i]=FastLine[i]-half*widthScale+gKamaDownOffset;
      CalculateTrack4At(i,rates_total,open,close,true);
     }
   return rates_total;
  }

int CountOwnPositions(const int direction)
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(direction==0 || (direction==1 && type==POSITION_TYPE_BUY) ||
         (direction==-1 && type==POSITION_TYPE_SELL)) count++;
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
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
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

double NormalizeLots(const double lots)
  {
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double v=ClampValue(lots,minLot,maxLot);
   if(step>0.0) v=MathFloor(v/step+1.0e-8)*step;
   int digits=(step>=1.0?0:(step>=0.1?1:(step>=0.01?2:3)));
   return NormalizeDouble(v,digits);
  }

bool OpenTrade(const int direction)
  {
   if(direction==1 && !InpAllowBuy) return false;
   if(direction==-1 && !InpAllowSell) return false;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   double lots=NormalizeLots(InpLots);
   bool isBuy=(direction==1);
   double entry=(isBuy?tick.ask:tick.bid);
   double sl=NormalizeDouble(isBuy?entry-InpStopLossPriceDistance:entry+InpStopLossPriceDistance,_Digits);
   if(isBuy && sl>=tick.bid) return false;
   if(!isBuy && sl<=tick.ask) return false;
   bool ok=(isBuy?trade.Buy(lots,_Symbol,0.0,sl,0.0,"NMNX Fusion4 Buy")
                  :trade.Sell(lots,_Symbol,0.0,sl,0.0,"NMNX Fusion4 Sell"));
   if(!ok) PrintFormat("开仓失败，retcode=%u，%s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
   return ok;
  }

void DrawRailSegment(const string name,const datetime t1,const double p1,const datetime t2,const double p2,
                     const color clr,const ENUM_LINE_STYLE style)
  {
   if(ObjectFind(0,name)<0)
      if(!ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2)) return;
   ObjectMove(0,name,0,t1,p1); ObjectMove(0,name,1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void DrawOptionalRails(const int total)
  {
   if(!InpShowKAMAReferenceRails && !InpShowFusionTrack4Rails)
     {
      for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
        {
         string n=ObjectName(0,i,-1,-1);
         if(StringFind(n,EA_OBJECT_PREFIX)==0) ObjectDelete(0,n);
        }
      return;
     }
   int n=MathMin(MathMin(InpDisplayBars,total-1),500);
   for(int i=n-1;i>=0;i--)
     {
      int j=i+1;
      if(InpShowKAMAReferenceRails)
        {
         DrawRailSegment(EA_OBJECT_PREFIX+"KU_"+IntegerToString(i),gTime[j],FastKAMAWidthUpper[j],gTime[i],FastKAMAWidthUpper[i],clrAqua,STYLE_SOLID);
         DrawRailSegment(EA_OBJECT_PREFIX+"KL_"+IntegerToString(i),gTime[j],FastKAMAWidthLower[j],gTime[i],FastKAMAWidthLower[i],clrAqua,STYLE_SOLID);
        }
      else
        {
         ObjectDelete(0,EA_OBJECT_PREFIX+"KU_"+IntegerToString(i));
         ObjectDelete(0,EA_OBJECT_PREFIX+"KL_"+IntegerToString(i));
        }
      if(InpShowFusionTrack4Rails && Composite4Upper[i]!=EMPTY_VALUE && Composite4Lower[i]!=EMPTY_VALUE &&
         Composite4Upper[j]!=EMPTY_VALUE && Composite4Lower[j]!=EMPTY_VALUE)
        {
         DrawRailSegment(EA_OBJECT_PREFIX+"FU_"+IntegerToString(i),gTime[j],Composite4Upper[j],gTime[i],Composite4Upper[i],clrWhite,STYLE_SOLID);
         DrawRailSegment(EA_OBJECT_PREFIX+"FL_"+IntegerToString(i),gTime[j],Composite4Lower[j],gTime[i],Composite4Lower[i],clrWhite,STYLE_DASH);
        }
      else
        {
         ObjectDelete(0,EA_OBJECT_PREFIX+"FU_"+IntegerToString(i));
         ObjectDelete(0,EA_OBJECT_PREFIX+"FL_"+IntegerToString(i));
        }
     }
  }

void OnTick()
  {
   if(_Period!=PERIOD_M5) return;
   int want=MathMax(InpCalculationBars,100);
   int copied=CopyRates(_Symbol,PERIOD_M5,0,want,gEABars);
   if(copied<MathMax(50,InpKAMA_ER_Period+InpResidual_Period+5)) return;
   ArraySetAsSeries(gEABars,true);
   ArrayResize(gTime,copied); ArrayResize(gOpen,copied); ArrayResize(gHigh,copied);
   ArrayResize(gLow,copied); ArrayResize(gClose,copied);
   ArraySetAsSeries(gTime,true); ArraySetAsSeries(gOpen,true); ArraySetAsSeries(gHigh,true);
   ArraySetAsSeries(gLow,true); ArraySetAsSeries(gClose,true);
   for(int i=0;i<copied;i++)
     {
      gTime[i]=gEABars[i].time; gOpen[i]=gEABars[i].open; gHigh[i]=gEABars[i].high;
      gLow[i]=gEABars[i].low; gClose[i]=gEABars[i].close;
     }
   if(CalculateCore(copied,gTime,gOpen,gHigh,gLow,gClose)<=0) return;

   datetime barTime=gTime[0];
   bool newBar=(barTime!=gEAbarTime);
   if(newBar)
     {
      gEAbarTime=barTime;
      gEALatchedUpper=false; gEALatchedLower=false;
     }
   DrawOptionalRails(copied);

   if(gEAFirstTick)
     {
      gEAFirstTick=false;
      if(!InpTradeExistingCurrentBarSignal) return;
     }
   if(Composite4Upper[0]==EMPTY_VALUE || Composite4Lower[0]==EMPTY_VALUE ||
      !MathIsValidNumber(Composite4Upper[0]) || !MathIsValidNumber(Composite4Lower[0])) return;

   if(!gEALatchedUpper && gHigh[0]>=Composite4Upper[0]) gEALatchedUpper=true;
   if(!gEALatchedLower && gLow[0]<=Composite4Lower[0]) gEALatchedLower=true;
   if(!gEALatchedUpper && !gEALatchedLower) return;
   if(gEALatchedUpper && gEALatchedLower)
     {
      Print("当前M5同时触及融合轨4上下轨，方向不明确，本根不交易。");
      return;
     }
   if(gLastAcceptedSignalTime==barTime) return;

   int direction=(gEALatchedLower?1:-1);
   if(InpSameDirectionSpacingFilter && direction==gLastAcceptedDirection && gLastAcceptedSignalTime>0)
     {
      int barsApart=iBarShift(_Symbol,PERIOD_M5,gLastAcceptedSignalTime,true);
      if(barsApart>=0 && barsApart<3) return;
     }

   gLastAcceptedDirection=direction;
   gLastAcceptedSignalTime=barTime;
   PrintFormat("融合轨4触轨：%s，K线=%s，触轨轨道价=%.*f",
               direction==1?"买入":"卖出",TimeToString(barTime,TIME_DATE|TIME_MINUTES),
               _Digits,direction==1?Composite4Lower[0]:Composite4Upper[0]);

   if(CountOwnPositions(-direction)>0 && !CloseOwnPositions(-direction))
     {
      Print("反向信号未能全部平仓，取消反手开仓。");
      return;
     }
   if(CountOwnPositions(direction)>0) return;
   OpenTrade(direction);
  }
//+------------------------------------------------------------------+
