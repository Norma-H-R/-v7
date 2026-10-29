//+------------------------------------------------------------------+
//| NMNX_ChannelFusion_Lab_v0_65_Lite.mq5                            |
//| 南门拈星：融合轨4轻量版                                            |
//| 保留原版 v0.652 的快速线、KAMA通道宽度及融合轨4动能驱离计算。       |
//| 仅绘制四条轨道；显示开关与计算分离；偏移步进固定0.01。               |
//+------------------------------------------------------------------+
#property strict
#property version   "0.650"
#property description "融合轨4轻量版：KAMA宽度参考上下轨、融合轨4上下轨"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "KAMA宽度参考上轨"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_style1  STYLE_DOT
#property indicator_width1  1
#property indicator_label2  "KAMA宽度参考下轨"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDeepSkyBlue
#property indicator_style2  STYLE_DOT
#property indicator_width2  1
#property indicator_label3  "融合轨4上轨"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrWhite
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2
#property indicator_label4  "融合轨4下轨"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrWhite
#property indicator_style4  STYLE_DASH
#property indicator_width4  2

input group "融合轨4计算参数（保留原版默认值）"
input int    InpFastEMA_Period        = 3;
input int    InpKAMA_ER_Period        = 8;
input int    InpKAMA_Fast_Period      = 2;
input int    InpKAMA_Slow_Period      = 20;
input int    InpATR_Period            = 7;
input int    InpResidual_Period       = 10;
input double InpATR_Min_Multiplier    = 0.35;
input double InpResidual_Multiplier   = 1.00;
input double InpFast_Width_Mult       = 0.85;
input double InpKAMA_Width_Mult       = 1.00;
input double InpFast_KAMAWidth_Scale  = 1.00;
input int    InpTrack4_MACD_Fast      = 7;
input int    InpTrack4_MACD_Slow      = 14;
input int    InpTrack4_MACD_Signal    = 5;
input int    InpTrack4_RSI_Fast       = 7;
input int    InpTrack4_RSI_Slow       = 17;
input int    InpTrack4_WPR_Fast       = 7;
input int    InpTrack4_WPR_Slow       = 14;
input int    InpTrack4_ADX_Period     = 7;
input int    InpTrack4_KDJ_K          = 5;
input int    InpTrack4_KDJ_D          = 3;
input int    InpTrack4_KDJ_Slowing    = 3;
input double InpTrack4_MaxDrive_ATR   = 2.20;
input double InpTrack4_MaxLift_ATR    = 0.85;
input double InpTrack4_ADX_Weak       = 14.0;
input double InpTrack4_ADX_Strong     = 32.0;
input double InpTrack4_ExpandSpeed    = 0.22;
input double InpTrack4_RecoilSpeed    = 0.68;

double RefUpper[],RefLower[],Track4Upper[],Track4Lower[];
double Track4BaseUpper[],Track4BaseLower[];
double FastLine[],KAMALine[],KAMAUpper[],KAMALower[],Atr[];
double Track4DriveUpper[],Track4DriveLower[],Track4Energy[];
double Track4MACDMain[],Track4MACDSignal[],Track4RSIFast[],Track4RSISlow[];
double Track4WPRFast[],Track4WPRSlow[],Track4K[],Track4D[],Track4ADX[],Track4PlusDI[],Track4MinusDI[];

int hMACD=INVALID_HANDLE,hRSIFast=INVALID_HANDLE,hRSISlow=INVALID_HANDLE;
int hWPRFast=INVALID_HANDLE,hWPRSlow=INVALID_HANDLE,hADX=INVALID_HANDLE,hKDJ=INVALID_HANDLE;

bool gShow[4]={true,true,true,true};
double gUpperOffset=0.0,gLowerOffset=0.0;
const double OFFSET_STEP=0.01;
string PREFIX="NMNX65L_";

double ClampValue(const double v,const double lo,const double hi)
{
   return MathMax(lo,MathMin(hi,v));
}

void SetPlotVisibility()
{
   for(int p=0;p<4;p++)
      PlotIndexSetInteger(p,PLOT_DRAW_TYPE,gShow[p] ? DRAW_LINE : DRAW_NONE);
}

void MakeButton(const string name,const string caption,const int x,const int y,const int w=94)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,24);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clrDimGray);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrGray);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetString(0,name,OBJPROP_TEXT,caption);
}

void RefreshButtons()
{
   MakeButton(PREFIX+"S0",StringFormat("参考上轨 %s",gShow[0]?"显示":"隐藏"),10,18);
   MakeButton(PREFIX+"S1",StringFormat("参考下轨 %s",gShow[1]?"显示":"隐藏"),108,18);
   MakeButton(PREFIX+"S2",StringFormat("融合上轨 %s",gShow[2]?"显示":"隐藏"),206,18);
   MakeButton(PREFIX+"S3",StringFormat("融合下轨 %s",gShow[3]?"显示":"隐藏"),304,18);
   MakeButton(PREFIX+"U-",StringFormat("上轨 - %.2f",OFFSET_STEP),402,18);
   MakeButton(PREFIX+"U+",StringFormat("上轨 + %.2f",OFFSET_STEP),500,18);
   MakeButton(PREFIX+"D-",StringFormat("下轨 - %.2f",OFFSET_STEP),598,18);
   MakeButton(PREFIX+"D+",StringFormat("下轨 + %.2f",OFFSET_STEP),696,18);
   ChartRedraw(0);
}

void ApplyOffsets()
{
   int n=ArraySize(Track4Upper);
   for(int i=0;i<n;i++)
   {
      Track4Upper[i]=(Track4BaseUpper[i]==EMPTY_VALUE ? EMPTY_VALUE : Track4BaseUpper[i]+gUpperOffset);
      Track4Lower[i]=(Track4BaseLower[i]==EMPTY_VALUE ? EMPTY_VALUE : Track4BaseLower[i]+gLowerOffset);
   }
}

void DeleteOwnObjects()
{
   for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--)
   {
      string name=ObjectName(0,i,0,-1);
      if(StringFind(name,PREFIX)==0) ObjectDelete(0,name);
   }
}

void ReleaseHandle(int &h)
{
   if(h!=INVALID_HANDLE) { IndicatorRelease(h); h=INVALID_HANDLE; }
}

int OnInit()
{
   if(InpFastEMA_Period<1 || InpKAMA_ER_Period<1 || InpKAMA_Fast_Period<1 ||
      InpKAMA_Slow_Period<2 || InpATR_Period<1 || InpResidual_Period<1 ||
      InpATR_Min_Multiplier<=0.0 || InpResidual_Multiplier<0.0 ||
      InpFast_Width_Mult<=0.0 || InpKAMA_Width_Mult<=0.0 || InpFast_KAMAWidth_Scale<=0.0 ||
      InpTrack4_MACD_Fast<1 || InpTrack4_MACD_Slow<=InpTrack4_MACD_Fast ||
      InpTrack4_MACD_Signal<1 || InpTrack4_RSI_Fast<2 || InpTrack4_RSI_Slow<2 ||
      InpTrack4_WPR_Fast<2 || InpTrack4_WPR_Slow<2 || InpTrack4_ADX_Period<2 ||
      InpTrack4_KDJ_K<1 || InpTrack4_KDJ_D<1 || InpTrack4_KDJ_Slowing<1 ||
      InpTrack4_ADX_Strong<=InpTrack4_ADX_Weak ||
      InpTrack4_ExpandSpeed<=0.0 || InpTrack4_ExpandSpeed>1.0 ||
      InpTrack4_RecoilSpeed<=0.0 || InpTrack4_RecoilSpeed>1.0)
      return INIT_PARAMETERS_INCORRECT;

   SetIndexBuffer(0,RefUpper,INDICATOR_DATA);
   SetIndexBuffer(1,RefLower,INDICATOR_DATA);
   SetIndexBuffer(2,Track4Upper,INDICATOR_DATA);
   SetIndexBuffer(3,Track4Lower,INDICATOR_DATA);
   ArraySetAsSeries(RefUpper,true); ArraySetAsSeries(RefLower,true);
   ArraySetAsSeries(Track4Upper,true); ArraySetAsSeries(Track4Lower,true);
   ArraySetAsSeries(Track4BaseUpper,true); ArraySetAsSeries(Track4BaseLower,true);
   for(int p=0;p<4;p++) PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   hMACD=iMACD(_Symbol,_Period,InpTrack4_MACD_Fast,InpTrack4_MACD_Slow,InpTrack4_MACD_Signal,PRICE_CLOSE);
   hRSIFast=iRSI(_Symbol,_Period,InpTrack4_RSI_Fast,PRICE_CLOSE);
   hRSISlow=iRSI(_Symbol,_Period,InpTrack4_RSI_Slow,PRICE_CLOSE);
   hWPRFast=iWPR(_Symbol,_Period,InpTrack4_WPR_Fast);
   hWPRSlow=iWPR(_Symbol,_Period,InpTrack4_WPR_Slow);
   hADX=iADX(_Symbol,_Period,InpTrack4_ADX_Period);
   hKDJ=iStochastic(_Symbol,_Period,InpTrack4_KDJ_K,InpTrack4_KDJ_D,InpTrack4_KDJ_Slowing,MODE_SMA,STO_LOWHIGH);
   if(hMACD==INVALID_HANDLE || hRSIFast==INVALID_HANDLE || hRSISlow==INVALID_HANDLE ||
      hWPRFast==INVALID_HANDLE || hWPRSlow==INVALID_HANDLE || hADX==INVALID_HANDLE || hKDJ==INVALID_HANDLE)
   {
      Print("NMNX融合轨4轻量版：指标句柄创建失败，错误=",GetLastError());
      return INIT_FAILED;
   }

   SetPlotVisibility();
   RefreshButtons();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteOwnObjects();
   ReleaseHandle(hMACD); ReleaseHandle(hRSIFast); ReleaseHandle(hRSISlow);
   ReleaseHandle(hWPRFast); ReleaseHandle(hWPRSlow); ReleaseHandle(hADX); ReleaseHandle(hKDJ);
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id!=CHARTEVENT_OBJECT_CLICK) return;
   if(sparam==PREFIX+"S0") gShow[0]=!gShow[0];
   else if(sparam==PREFIX+"S1") gShow[1]=!gShow[1];
   else if(sparam==PREFIX+"S2") gShow[2]=!gShow[2];
   else if(sparam==PREFIX+"S3") gShow[3]=!gShow[3];
   else if(sparam==PREFIX+"U-") gUpperOffset=NormalizeDouble(gUpperOffset-OFFSET_STEP,2);
   else if(sparam==PREFIX+"U+") gUpperOffset=NormalizeDouble(gUpperOffset+OFFSET_STEP,2);
   else if(sparam==PREFIX+"D-") gLowerOffset=NormalizeDouble(gLowerOffset-OFFSET_STEP,2);
   else if(sparam==PREFIX+"D+") gLowerOffset=NormalizeDouble(gLowerOffset+OFFSET_STEP,2);
   else return;
   SetPlotVisibility();
   ApplyOffsets();
   RefreshButtons();
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<MathMax(40,InpKAMA_ER_Period+InpResidual_Period+5)) return 0;

   ArrayResize(FastLine,rates_total); ArraySetAsSeries(FastLine,true);
   ArrayResize(KAMALine,rates_total); ArraySetAsSeries(KAMALine,true);
   ArrayResize(KAMAUpper,rates_total); ArraySetAsSeries(KAMAUpper,true);
   ArrayResize(KAMALower,rates_total); ArraySetAsSeries(KAMALower,true);
   ArrayResize(Atr,rates_total); ArraySetAsSeries(Atr,true);
   ArrayResize(Track4DriveUpper,rates_total); ArraySetAsSeries(Track4DriveUpper,true);
   ArrayResize(Track4DriveLower,rates_total); ArraySetAsSeries(Track4DriveLower,true);
   ArrayResize(Track4Energy,rates_total); ArraySetAsSeries(Track4Energy,true);
   ArrayResize(Track4BaseUpper,rates_total); ArraySetAsSeries(Track4BaseUpper,true);
   ArrayResize(Track4BaseLower,rates_total); ArraySetAsSeries(Track4BaseLower,true);

   ArrayResize(Track4MACDMain,rates_total); ArraySetAsSeries(Track4MACDMain,true);
   ArrayResize(Track4MACDSignal,rates_total); ArraySetAsSeries(Track4MACDSignal,true);
   ArrayResize(Track4RSIFast,rates_total); ArraySetAsSeries(Track4RSIFast,true);
   ArrayResize(Track4RSISlow,rates_total); ArraySetAsSeries(Track4RSISlow,true);
   ArrayResize(Track4WPRFast,rates_total); ArraySetAsSeries(Track4WPRFast,true);
   ArrayResize(Track4WPRSlow,rates_total); ArraySetAsSeries(Track4WPRSlow,true);
   ArrayResize(Track4K,rates_total); ArraySetAsSeries(Track4K,true);
   ArrayResize(Track4D,rates_total); ArraySetAsSeries(Track4D,true);
   ArrayResize(Track4ADX,rates_total); ArraySetAsSeries(Track4ADX,true);
   ArrayResize(Track4PlusDI,rates_total); ArraySetAsSeries(Track4PlusDI,true);
   ArrayResize(Track4MinusDI,rates_total); ArraySetAsSeries(Track4MinusDI,true);

   if(CopyBuffer(hMACD,0,0,rates_total,Track4MACDMain)<rates_total ||
      CopyBuffer(hMACD,1,0,rates_total,Track4MACDSignal)<rates_total ||
      CopyBuffer(hRSIFast,0,0,rates_total,Track4RSIFast)<rates_total ||
      CopyBuffer(hRSISlow,0,0,rates_total,Track4RSISlow)<rates_total ||
      CopyBuffer(hWPRFast,0,0,rates_total,Track4WPRFast)<rates_total ||
      CopyBuffer(hWPRSlow,0,0,rates_total,Track4WPRSlow)<rates_total ||
      CopyBuffer(hADX,0,0,rates_total,Track4ADX)<rates_total ||
      CopyBuffer(hADX,1,0,rates_total,Track4PlusDI)<rates_total ||
      CopyBuffer(hADX,2,0,rates_total,Track4MinusDI)<rates_total ||
      CopyBuffer(hKDJ,0,0,rates_total,Track4K)<rates_total ||
      CopyBuffer(hKDJ,1,0,rates_total,Track4D)<rates_total)
      return prev_calculated;

   double alphaFast=2.0/(InpFastEMA_Period+1.0);
   double fastSC=2.0/(InpKAMA_Fast_Period+1.0);
   double slowSC=2.0/(InpKAMA_Slow_Period+1.0);

   // 每次完整递推，保证递归驱离状态和原版一致；索引i+1永远是更旧K线。
   for(int i=rates_total-1;i>=0;i--)
   {
      double tr=high[i]-low[i];
      if(i<rates_total-1)
      {
         tr=MathMax(tr,MathAbs(high[i]-close[i+1]));
         tr=MathMax(tr,MathAbs(low[i]-close[i+1]));
         Atr[i]=(Atr[i+1]*(InpATR_Period-1)+tr)/InpATR_Period;
      }
      else Atr[i]=tr;
      double atrValue=MathMax(Atr[i],_Point*2.0);

      if(i==rates_total-1) FastLine[i]=close[i];
      else FastLine[i]=alphaFast*close[i]+(1.0-alphaFast)*FastLine[i+1];

      if(i==rates_total-1) KAMALine[i]=close[i];
      else
      {
         int oldIndex=MathMin(rates_total-1,i+InpKAMA_ER_Period);
         double change=MathAbs(close[i]-close[oldIndex]);
         double volatility=0.0;
         int endIndex=MathMin(rates_total-1,i+InpKAMA_ER_Period-1);
         for(int j=i;j<=endIndex;j++)
            if(j+1<rates_total) volatility+=MathAbs(close[j]-close[j+1]);
         double er=(volatility>0.0 ? change/volatility : 0.0);
         er=ClampValue(er,0.0,1.0);
         double sc=er*(fastSC-slowSC)+slowSC;
         sc*=sc;
         KAMALine[i]=KAMALine[i+1]+sc*(close[i]-KAMALine[i+1]);
      }

      double minHalf=atrValue*InpATR_Min_Multiplier;
      double kamaHalf=MathMax(minHalf,atrValue*InpKAMA_Width_Mult);
      // 原版KAMA轨道宽度以KAMA线残差RMS为主，保留相同残差窗口计算。
      double residual=0.0; int residualCount=0;
      int endResidual=MathMin(rates_total-1,i+InpResidual_Period-1);
      for(int j=i;j<=endResidual;j++)
      {
         // 因为KAMA递推从旧到新已完成该点及更旧点，残差只使用当前及更旧K线。
         double e=close[j]-KAMALine[j];
         residual+=e*e; residualCount++;
      }
      double rms=(residualCount>0 ? MathSqrt(residual/residualCount) : 0.0);
      kamaHalf=MathMax(minHalf,rms*InpResidual_Multiplier)*InpKAMA_Width_Mult;
      KAMAUpper[i]=KAMALine[i]+kamaHalf;
      KAMALower[i]=KAMALine[i]-kamaHalf;

      double scale=MathMax(0.01,InpFast_KAMAWidth_Scale);
      double halfUp=MathMax(0.0,KAMAUpper[i]-KAMALine[i])*scale;
      double halfDown=MathMax(0.0,KAMALine[i]-KAMALower[i])*scale;
      RefUpper[i]=FastLine[i]+halfUp;
      RefLower[i]=FastLine[i]-halfDown;

      if(i+3>=rates_total ||
         Track4MACDMain[i]==EMPTY_VALUE || Track4MACDSignal[i]==EMPTY_VALUE ||
         Track4MACDMain[i+1]==EMPTY_VALUE || Track4MACDSignal[i+1]==EMPTY_VALUE ||
         Track4RSIFast[i]==EMPTY_VALUE || Track4RSISlow[i]==EMPTY_VALUE ||
         Track4WPRFast[i]==EMPTY_VALUE || Track4WPRSlow[i]==EMPTY_VALUE ||
         Track4K[i]==EMPTY_VALUE || Track4D[i]==EMPTY_VALUE ||
         Track4ADX[i]==EMPTY_VALUE || Track4PlusDI[i]==EMPTY_VALUE || Track4MinusDI[i]==EMPTY_VALUE)
      {
         Track4DriveUpper[i]=0.0; Track4DriveLower[i]=0.0; Track4Energy[i]=0.0;
         Track4BaseUpper[i]=EMPTY_VALUE; Track4BaseLower[i]=EMPTY_VALUE;
         Track4Upper[i]=EMPTY_VALUE; Track4Lower[i]=EMPTY_VALUE;
         continue;
      }

      double rsiScore=0.60*ClampValue((Track4RSIFast[i]-Track4RSISlow[i])/15.0,-1.0,1.0)
                     +0.40*ClampValue((Track4RSISlow[i]-50.0)/25.0,-1.0,1.0);
      double wprScore=0.60*ClampValue((Track4WPRFast[i]-Track4WPRSlow[i])/25.0,-1.0,1.0)
                     +0.40*ClampValue((Track4WPRSlow[i]+50.0)/35.0,-1.0,1.0);
      double macdHist=Track4MACDMain[i]-Track4MACDSignal[i];
      double macdHistOld=Track4MACDMain[i+1]-Track4MACDSignal[i+1];
      double macdLevel=ClampValue(macdHist/MathMax(atrValue*0.12,_Point),-1.0,1.0);
      double macdChange=ClampValue((macdHist-macdHistOld)/MathMax(atrValue*0.08,_Point),-1.0,1.0);
      double macdScore=0.70*macdLevel+0.30*macdChange;
      double k=Track4K[i],d=Track4D[i],jline=3.0*k-2.0*d;
      double kdjScore=0.45*ClampValue((k-d)/20.0,-1.0,1.0)
                     +0.35*ClampValue((jline-50.0)/45.0,-1.0,1.0)
                     +0.20*ClampValue((k-50.0)/35.0,-1.0,1.0);
      double diScore=ClampValue((Track4PlusDI[i]-Track4MinusDI[i])/
                                MathMax(Track4PlusDI[i]+Track4MinusDI[i],1.0),-1.0,1.0);
      double priceSlope=ClampValue((close[i]-close[i+3])/MathMax(atrValue*1.50,_Point),-1.0,1.0);
      double candleBody=ClampValue((close[i]-open[i])/MathMax(atrValue*0.80,_Point),-1.0,1.0);
      double priceScore=0.70*priceSlope+0.30*candleBody;
      double direction=ClampValue(0.18*rsiScore+0.14*wprScore+0.24*macdScore+
                                  0.14*kdjScore+0.18*diScore+0.12*priceScore,-1.0,1.0);
      double adxStrength=ClampValue((Track4ADX[i]-InpTrack4_ADX_Weak)/
                           MathMax(InpTrack4_ADX_Strong-InpTrack4_ADX_Weak,1.0),0.0,1.0);
      double continuity=ClampValue(MathAbs(close[i]-close[i+3])/MathMax(atrValue*1.20,_Point),0.0,1.0);
      double rawEnergy=ClampValue((MathAbs(direction)-0.08)/0.92,0.0,1.0);
      double energy=ClampValue(rawEnergy*(0.15+0.85*adxStrength)*(0.08+0.92*continuity),0.0,1.0);
      Track4Energy[i]=energy;

      double targetUpper=0.0,targetLower=0.0;
      if(direction>0.0)
      {
         targetUpper=atrValue*InpTrack4_MaxDrive_ATR*energy;
         targetLower=atrValue*InpTrack4_MaxLift_ATR*energy;
      }
      else if(direction<0.0)
      {
         targetUpper=-atrValue*InpTrack4_MaxLift_ATR*energy;
         targetLower=-atrValue*InpTrack4_MaxDrive_ATR*energy;
      }

      if(i==rates_total-1)
      {
         Track4DriveUpper[i]=targetUpper;
         Track4DriveLower[i]=targetLower;
      }
      else
      {
         double prevUpper=Track4DriveUpper[i+1],prevLower=Track4DriveLower[i+1];
         double prevEnergy=Track4Energy[i+1];
         double energyFade=ClampValue((prevEnergy-energy)*1.50,0.0,1.0);
         bool upperExpanding=((prevUpper==0.0 || targetUpper*prevUpper>0.0) && MathAbs(targetUpper)>MathAbs(prevUpper));
         bool lowerExpanding=((prevLower==0.0 || targetLower*prevLower>0.0) && MathAbs(targetLower)>MathAbs(prevLower));
         double upperRate=upperExpanding ? ClampValue(InpTrack4_ExpandSpeed,0.01,1.0) :
                          ClampValue(InpTrack4_RecoilSpeed+0.20*energyFade,InpTrack4_RecoilSpeed,0.95);
         double lowerRate=lowerExpanding ? ClampValue(InpTrack4_ExpandSpeed,0.01,1.0) :
                          ClampValue(InpTrack4_RecoilSpeed+0.20*energyFade,InpTrack4_RecoilSpeed,0.95);
         Track4DriveUpper[i]=prevUpper+upperRate*(targetUpper-prevUpper);
         Track4DriveLower[i]=prevLower+lowerRate*(targetLower-prevLower);
      }

      // 原版融合轨4基准：快速线中心 + KAMA通道半宽 + 动能驱离量。
      Track4BaseUpper[i]=FastLine[i]+halfUp+Track4DriveUpper[i];
      Track4BaseLower[i]=FastLine[i]-halfDown+Track4DriveLower[i];
      Track4Upper[i]=Track4BaseUpper[i]+gUpperOffset;
      Track4Lower[i]=Track4BaseLower[i]+gLowerOffset;
   }
   SetPlotVisibility();
   return rates_total;
}
//+------------------------------------------------------------------+
