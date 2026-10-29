//+------------------------------------------------------------------+
//| NMNX_ChannelFusion_Lab_v0_65_Lite.mq5                            |
//| 南门拈星：融合轨4轻量版                                            |
//| 仅保留：KAMA宽度参考轨上下轨 + 融合轨4上下轨；四线独立显示控制。    |
//| 偏移按钮固定步进 0.01；显示开关不影响任何计算。                    |
//+------------------------------------------------------------------+
#property strict
#property version   "0.650"
#property description "NMNX融合轨4轻量版：四条轨道、独立显示、上下轨偏移步进0.01"
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

double RefUpper[],RefLower[],Track4Upper[],Track4Lower[];
double KAMALine[],KAMAUpper[],KAMALower[],AtrValues[];
double Track4DriveUpper[],Track4DriveLower[],Track4Energy[];
double MacdMain[],MacdSignal[],RsiFast[],RsiSlow[],WprFast[],WprSlow[];
double AdxValues[],PlusDI[],MinusDI[],StochK[],StochD[];

int hATR=INVALID_HANDLE,hMACD=INVALID_HANDLE,hRSIFast=INVALID_HANDLE,hRSISlow=INVALID_HANDLE;
int hWPRFast=INVALID_HANDLE,hWPRSlow=INVALID_HANDLE,hADX=INVALID_HANDLE,hStoch=INVALID_HANDLE;

bool gShow[4]={true,true,true,true};
double gUpperOffset=0.0,gLowerOffset=0.0;
const double OFFSET_STEP=0.01;
string PREFIX="NMNX65L_";
int gLastRates=0;

double ClampValue(const double v,const double lo,const double hi)
{
   return MathMax(lo,MathMin(hi,v));
}

bool CopySeries(const int handle,const int buffer,const int count,double &dst[])
{
   ArrayResize(dst,count);
   ArraySetAsSeries(dst,true);
   if(handle==INVALID_HANDLE) return false;
   int copied=CopyBuffer(handle,buffer,0,count,dst);
   return copied==count;
}

void SetPlotVisibility()
{
   for(int p=0;p<4;p++)
      PlotIndexSetInteger(p,PLOT_DRAW_TYPE,gShow[p] ? DRAW_LINE : DRAW_NONE);
}

void MakeButton(const string name,const string caption,const int x,const int y,const int w=88)
{
   if(ObjectFind(0,name)<0)
      ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
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
   MakeButton(PREFIX+"S0",StringFormat("参考上轨 %s",gShow[0]?"显示":"隐藏"),10,18,94);
   MakeButton(PREFIX+"S1",StringFormat("参考下轨 %s",gShow[1]?"显示":"隐藏"),108,18,94);
   MakeButton(PREFIX+"S2",StringFormat("融合上轨 %s",gShow[2]?"显示":"隐藏"),206,18,94);
   MakeButton(PREFIX+"S3",StringFormat("融合下轨 %s",gShow[3]?"显示":"隐藏"),304,18,94);
   MakeButton(PREFIX+"U-",StringFormat("上轨 - %.2f",OFFSET_STEP),402,18,92);
   MakeButton(PREFIX+"U+",StringFormat("上轨 + %.2f",OFFSET_STEP),498,18,92);
   MakeButton(PREFIX+"D-",StringFormat("下轨 - %.2f",OFFSET_STEP),594,18,92);
   MakeButton(PREFIX+"D+",StringFormat("下轨 + %.2f",OFFSET_STEP),690,18,92);
   ChartRedraw(0);
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
   SetIndexBuffer(0,RefUpper,INDICATOR_DATA);
   SetIndexBuffer(1,RefLower,INDICATOR_DATA);
   SetIndexBuffer(2,Track4Upper,INDICATOR_DATA);
   SetIndexBuffer(3,Track4Lower,INDICATOR_DATA);
   ArraySetAsSeries(RefUpper,true); ArraySetAsSeries(RefLower,true);
   ArraySetAsSeries(Track4Upper,true); ArraySetAsSeries(Track4Lower,true);

   for(int p=0;p<4;p++) PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   hATR=iATR(_Symbol,_Period,7);
   hMACD=iMACD(_Symbol,_Period,7,14,5,PRICE_CLOSE);
   hRSIFast=iRSI(_Symbol,_Period,7,PRICE_CLOSE);
   hRSISlow=iRSI(_Symbol,_Period,17,PRICE_CLOSE);
   hWPRFast=iWPR(_Symbol,_Period,7);
   hWPRSlow=iWPR(_Symbol,_Period,14);
   hADX=iADX(_Symbol,_Period,7);
   hStoch=iStochastic(_Symbol,_Period,5,3,3,MODE_SMA,STO_LOWHIGH);

   if(hATR==INVALID_HANDLE || hMACD==INVALID_HANDLE || hRSIFast==INVALID_HANDLE ||
      hRSISlow==INVALID_HANDLE || hWPRFast==INVALID_HANDLE || hWPRSlow==INVALID_HANDLE ||
      hADX==INVALID_HANDLE || hStoch==INVALID_HANDLE)
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
   ReleaseHandle(hATR); ReleaseHandle(hMACD); ReleaseHandle(hRSIFast); ReleaseHandle(hRSISlow);
   ReleaseHandle(hWPRFast); ReleaseHandle(hWPRSlow); ReleaseHandle(hADX); ReleaseHandle(hStoch);
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
   RefreshButtons();
   // 偏移仅叠加到融合轨4最终输出，不重算KAMA、ATR及动能递归状态。
   int n=ArraySize(Track4Upper);
   for(int i=0;i<n;i++)
   {
      if(Track4Upper[i]!=EMPTY_VALUE) Track4Upper[i]=Track4Upper[i]-gUpperOffset;
      if(Track4Lower[i]!=EMPTY_VALUE) Track4Lower[i]=Track4Lower[i]-gLowerOffset;
   }
   // 由下一次行情计算刷新完整缓冲区，避免重复点击造成累计位移。
   ChartRedraw(0);
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<40) return 0;

   if(!CopySeries(hATR,0,rates_total,AtrValues) ||
      !CopySeries(hMACD,0,rates_total,MacdMain) ||
      !CopySeries(hMACD,1,rates_total,MacdSignal) ||
      !CopySeries(hRSIFast,0,rates_total,RsiFast) ||
      !CopySeries(hRSISlow,0,rates_total,RsiSlow) ||
      !CopySeries(hWPRFast,0,rates_total,WprFast) ||
      !CopySeries(hWPRSlow,0,rates_total,WprSlow) ||
      !CopySeries(hADX,0,rates_total,AdxValues) ||
      !CopySeries(hADX,1,rates_total,PlusDI) ||
      !CopySeries(hADX,2,rates_total,MinusDI) ||
      !CopySeries(hStoch,0,rates_total,StochK) ||
      !CopySeries(hStoch,1,rates_total,StochD))
      return prev_calculated;

   ArrayResize(KAMALine,rates_total); ArraySetAsSeries(KAMALine,true);
   ArrayResize(KAMAUpper,rates_total); ArraySetAsSeries(KAMAUpper,true);
   ArrayResize(KAMALower,rates_total); ArraySetAsSeries(KAMALower,true);
   ArrayResize(Track4DriveUpper,rates_total); ArraySetAsSeries(Track4DriveUpper,true);
   ArrayResize(Track4DriveLower,rates_total); ArraySetAsSeries(Track4DriveLower,true);
   ArrayResize(Track4Energy,rates_total); ArraySetAsSeries(Track4Energy,true);

   // 固定沿用原版参数：KAMA ER=8，快/慢周期=2/20；残差窗口=10，ATR最小半宽=0.35。
   // 从最旧K线向最新K线计算，递归只读取 i+1 的历史状态，不使用未来K线。
   for(int i=rates_total-1;i>=0;i--)
   {
      double price=close[i];
      double change=(i+8<rates_total ? MathAbs(close[i]-close[i+8]) : 0.0);
      double volatility=0.0;
      for(int j=i;j<i+8 && j+1<rates_total;j++) volatility+=MathAbs(close[j]-close[j+1]);
      double er=(volatility>0.0 ? change/volatility : 0.0);
      double fastSC=2.0/(2.0+1.0),slowSC=2.0/(20.0+1.0);
      double sc=MathPow(er*(fastSC-slowSC)+slowSC,2.0);
      if(i==rates_total-1) KAMALine[i]=price;
      else KAMALine[i]=KAMALine[i+1]+sc*(price-KAMALine[i+1]);

      double atr=MathMax(AtrValues[i],_Point*2.0);
      double residual=0.0; int rc=0;
      for(int j=i;j<i+10 && j<rates_total;j++)
      {
         double e=close[j]-KAMALine[j];
         residual+=e*e; rc++;
      }
      double half=MathMax(atr*0.35,(rc>0 ? MathSqrt(residual/rc) : 0.0));
      KAMAUpper[i]=KAMALine[i]+half;
      KAMALower[i]=KAMALine[i]-half;

      double halfUp=MathMax(0.0,KAMAUpper[i]-KAMALine[i]);
      double halfDown=MathMax(0.0,KAMALine[i]-KAMALower[i]);
      double baseUpper=KAMALine[i]+halfUp;
      double baseLower=KAMALine[i]-halfDown;
      RefUpper[i]=baseUpper;
      RefLower[i]=baseLower;

      if(i+3>=rates_total || MacdMain[i]==EMPTY_VALUE || MacdSignal[i]==EMPTY_VALUE ||
         MacdMain[MathMin(i+1,rates_total-1)]==EMPTY_VALUE || MacdSignal[MathMin(i+1,rates_total-1)]==EMPTY_VALUE ||
         RsiFast[i]==EMPTY_VALUE || RsiSlow[i]==EMPTY_VALUE || WprFast[i]==EMPTY_VALUE ||
         WprSlow[i]==EMPTY_VALUE || StochK[i]==EMPTY_VALUE || StochD[i]==EMPTY_VALUE ||
         AdxValues[i]==EMPTY_VALUE || PlusDI[i]==EMPTY_VALUE || MinusDI[i]==EMPTY_VALUE)
      {
         Track4DriveUpper[i]=0.0; Track4DriveLower[i]=0.0; Track4Energy[i]=0.0;
         Track4Upper[i]=EMPTY_VALUE; Track4Lower[i]=EMPTY_VALUE;
         continue;
      }

      double rsiScore=0.60*ClampValue((RsiFast[i]-RsiSlow[i])/15.0,-1.0,1.0)
                     +0.40*ClampValue((RsiSlow[i]-50.0)/25.0,-1.0,1.0);
      double wprScore=0.60*ClampValue((WprFast[i]-WprSlow[i])/25.0,-1.0,1.0)
                     +0.40*ClampValue((WprSlow[i]+50.0)/35.0,-1.0,1.0);
      double macdHist=MacdMain[i]-MacdSignal[i];
      double oldHist=MacdMain[i+1]-MacdSignal[i+1];
      double macdLevel=ClampValue(macdHist/MathMax(atr*0.12,_Point),-1.0,1.0);
      double macdChange=ClampValue((macdHist-oldHist)/MathMax(atr*0.08,_Point),-1.0,1.0);
      double macdScore=0.70*macdLevel+0.30*macdChange;
      double k=StochK[i],d=StochD[i],jline=3.0*k-2.0*d;
      double kdjScore=0.45*ClampValue((k-d)/20.0,-1.0,1.0)
                     +0.35*ClampValue((jline-50.0)/45.0,-1.0,1.0)
                     +0.20*ClampValue((k-50.0)/35.0,-1.0,1.0);
      double diScore=ClampValue((PlusDI[i]-MinusDI[i])/MathMax(PlusDI[i]+MinusDI[i],1.0),-1.0,1.0);
      double priceSlope=ClampValue((close[i]-close[i+3])/MathMax(atr*1.50,_Point),-1.0,1.0);
      double candleBody=ClampValue((close[i]-open[i])/MathMax(atr*0.80,_Point),-1.0,1.0);
      double priceScore=0.70*priceSlope+0.30*candleBody;
      double direction=ClampValue(0.18*rsiScore+0.14*wprScore+0.24*macdScore+
                                  0.14*kdjScore+0.18*diScore+0.12*priceScore,-1.0,1.0);
      double adxStrength=ClampValue((AdxValues[i]-14.0)/(32.0-14.0),0.0,1.0);
      double continuity=ClampValue(MathAbs(close[i]-close[i+3])/MathMax(atr*1.20,_Point),0.0,1.0);
      double rawEnergy=ClampValue((MathAbs(direction)-0.08)/0.92,0.0,1.0);
      double energy=ClampValue(rawEnergy*(0.15+0.85*adxStrength)*(0.08+0.92*continuity),0.0,1.0);
      Track4Energy[i]=energy;

      double targetU=0.0,targetL=0.0;
      if(direction>0.0) { targetU=atr*2.20*energy; targetL=atr*0.85*energy; }
      else if(direction<0.0) { targetU=-atr*0.85*energy; targetL=-atr*2.20*energy; }

      if(i==rates_total-1)
      {
         Track4DriveUpper[i]=targetU;
         Track4DriveLower[i]=targetL;
      }
      else
      {
         double prevU=Track4DriveUpper[i+1],prevL=Track4DriveLower[i+1];
         double prevEnergy=Track4Energy[i+1];
         double energyFade=ClampValue((prevEnergy-energy)*1.50,0.0,1.0);
         bool expandU=((prevU==0.0 || targetU*prevU>0.0) && MathAbs(targetU)>MathAbs(prevU));
         bool expandL=((prevL==0.0 || targetL*prevL>0.0) && MathAbs(targetL)>MathAbs(prevL));
         double rateU=expandU ? 0.22 : ClampValue(0.68+0.20*energyFade,0.68,0.95);
         double rateL=expandL ? 0.22 : ClampValue(0.68+0.20*energyFade,0.68,0.95);
         Track4DriveUpper[i]=prevU+rateU*(targetU-prevU);
         Track4DriveLower[i]=prevL+rateL*(targetL-prevL);
      }
      Track4Upper[i]=baseUpper+Track4DriveUpper[i]+gUpperOffset;
      Track4Lower[i]=baseLower+Track4DriveLower[i]+gLowerOffset;
   }

   SetPlotVisibility();
   gLastRates=rates_total;
   return rates_total;
}
//+------------------------------------------------------------------+
