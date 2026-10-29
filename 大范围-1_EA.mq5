//+------------------------------------------------------------------+
//| 大范围-1_EA.mq5                                                   |
//| NMNX 自包含交易版：手写指标计算，不调用任何外部指标                 |
//| 仅 M5；融合轨4下轨买、上轨卖；反向信号先平仓再反向开仓               |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"
#property description "NMNX 自包含版：不加载外部指标，KAMA与融合轨4绘图可独立关闭。"

#include <Trade/Trade.mqh>

enum ENUM_NMNX_TRADE_MODE
  {
   MODE_ONE_POSITION=1,
   MODE_ADD_SAME_SIDE=2
  };

input group "01 · 交易设置"
input ENUM_NMNX_TRADE_MODE InpTradeMode=MODE_ONE_POSITION;
input double InpLots=0.01;
input double InpStopLossPriceDistance=20.0;
input ulong InpMagicNumber=1700529;
input int InpDeviationPoints=30;
input bool InpAllowBuy=true;
input bool InpAllowSell=true;
input bool InpTradeExistingCurrentBarSignal=true;

input group "02 · 回测图表显示（只控制绘图，不关闭计算）"
input bool InpShowKAMAReferenceRails=false;
input bool InpShowFusionTrack4Rails=false;
input int InpDisplayBars=250;
input double InpKAMAReferenceUpperOffset=0.0;
input double InpKAMAReferenceLowerOffset=0.0;
input double InpFusion4UpperOffset=0.0;
input double InpFusion4LowerOffset=0.0;

input group "03 · 基础轨道参数（与原指标默认值一致）"
input int InpFastEMA_Period=3;
input int InpKAMA_ER_Period=8;
input int InpKAMA_Fast_Period=2;
input int InpKAMA_Slow_Period=20;
input int InpATR_Period=7;
input int InpResidual_Period=10;
input double InpATR_Min_Multiplier=0.35;
input double InpResidual_Multiplier=1.00;
input double InpKAMA_Width_Mult=1.00;
input double InpFast_KAMAWidth_Scale=1.00;

input group "04 · 融合轨4动能参数（与原指标默认值一致）"
input bool InpEnableFusionTrack4=true;
input int InpTrack4_MACD_Fast=7;
input int InpTrack4_MACD_Slow=14;
input int InpTrack4_MACD_Signal=5;
input int InpTrack4_RSI_Fast=7;
input int InpTrack4_RSI_Slow=17;
input int InpTrack4_WPR_Fast=7;
input int InpTrack4_WPR_Slow=14;
input int InpTrack4_ADX_Period=7;
input int InpTrack4_KDJ_K=5;
input int InpTrack4_KDJ_D=3;
input int InpTrack4_KDJ_Slowing=3;
input double InpTrack4_MaxDrive_ATR=2.20;
input double InpTrack4_MaxLift_ATR=0.85;
input double InpTrack4_ADX_Weak=14.0;
input double InpTrack4_ADX_Strong=32.0;
input double InpTrack4_ExpandSpeed=0.22;
input double InpTrack4_RecoilSpeed=0.68;

input group "05 · 计算性能"
input int InpCalculationBars=3000;
input bool InpSameDirectionSpacingFilter=true;

CTrade trade;
string OBJ_PREFIX="NMNX_EA_RAIL_";
datetime gLastProcessedBar=0;
datetime gCurrentBar=0;
bool gFirstCheck=true;
bool gUpperLatched=false,gLowerLatched=false;
double gUpperTouchPrice=0.0,gLowerTouchPrice=0.0;
int gLastAcceptedDirection=0;
datetime gLastAcceptedTime=0;

MqlRates rates[];
double fastLine[],kama[],atr[],kamaUpper[],kamaLower[],refUpper[],refLower[];
double macdMain[],macdSignal[],rsiFast[],rsiSlow[],wprFast[],wprSlow[];
double adx[],plusDI[],minusDI[],stochK[],stochD[];
double driveUpper[],driveLower[],energy[],fusionUpper[],fusionLower[];
double avgGainFast[],avgLossFast[],avgGainSlow[],avgLossSlow[];
double smoothTR[],smoothPlusDM[],smoothMinusDM[],dx[];
double macdEmaFast[],macdEmaSlow[],macdSignalEma[],rawStoch[];

double ClampV(const double x,const double lo,const double hi)
  {
   return MathMax(lo,MathMin(hi,x));
  }

double SafeDiv(const double a,const double b,const double fallback=0.0)
  {
   if(MathAbs(b)<1.0e-12) return fallback;
   return a/b;
  }

int MaxRequiredBars()
  {
   int n=InpKAMA_ER_Period+InpResidual_Period+5;
   n=MathMax(n,InpTrack4_MACD_Slow+InpTrack4_MACD_Signal+5);
   n=MathMax(n,InpTrack4_ADX_Period*3+5);
   n=MathMax(n,InpTrack4_KDJ_K+InpTrack4_KDJ_Slowing+InpTrack4_KDJ_D+5);
   return n;
  }

bool ResizeAll(const int n)
  {
   if(n<MaxRequiredBars()) return false;
   ArrayResize(rates,n); ArraySetAsSeries(rates,true);
#define RESIZE_SERIES(a) ArrayResize(a,n); ArraySetAsSeries(a,true)
   RESIZE_SERIES(fastLine); RESIZE_SERIES(kama); RESIZE_SERIES(atr);
   RESIZE_SERIES(kamaUpper); RESIZE_SERIES(kamaLower); RESIZE_SERIES(refUpper); RESIZE_SERIES(refLower);
   RESIZE_SERIES(macdMain); RESIZE_SERIES(macdSignal); RESIZE_SERIES(rsiFast); RESIZE_SERIES(rsiSlow);
   RESIZE_SERIES(wprFast); RESIZE_SERIES(wprSlow); RESIZE_SERIES(adx); RESIZE_SERIES(plusDI); RESIZE_SERIES(minusDI);
   RESIZE_SERIES(stochK); RESIZE_SERIES(stochD); RESIZE_SERIES(driveUpper); RESIZE_SERIES(driveLower);
   RESIZE_SERIES(energy); RESIZE_SERIES(fusionUpper); RESIZE_SERIES(fusionLower);
   RESIZE_SERIES(avgGainFast); RESIZE_SERIES(avgLossFast); RESIZE_SERIES(avgGainSlow); RESIZE_SERIES(avgLossSlow);
   RESIZE_SERIES(smoothTR); RESIZE_SERIES(smoothPlusDM); RESIZE_SERIES(smoothMinusDM); RESIZE_SERIES(dx);
   RESIZE_SERIES(macdEmaFast); RESIZE_SERIES(macdEmaSlow); RESIZE_SERIES(macdSignalEma); RESIZE_SERIES(rawStoch);
#undef RESIZE_SERIES
   return true;
  }

// 手写 EMA、KAMA、ATR、残差 RMS、MACD、RSI、WPR、ADX/DI、随机指标及融合轨4。
bool CalculateAll()
  {
   int copied=CopyRates(_Symbol,PERIOD_M5,0,MathMax(InpCalculationBars,MaxRequiredBars()),rates);
   if(copied<MaxRequiredBars()) return false;
   if(!ResizeAll(copied)) return false;
   double aFast=2.0/(MathMax(1,InpFastEMA_Period)+1.0);
   double aMF=2.0/(MathMax(1,InpTrack4_MACD_Fast)+1.0);
   double aMS=2.0/(MathMax(1,InpTrack4_MACD_Slow)+1.0);
   double aSig=2.0/(MathMax(1,InpTrack4_MACD_Signal)+1.0);
   double kamaFastSC=2.0/(MathMax(1,InpKAMA_Fast_Period)+1.0);
   double kamaSlowSC=2.0/(MathMax(2,InpKAMA_Slow_Period)+1.0);
   int oldest=copied-1;

   // 由最旧K线向当前K线递推。系列数组索引越大，时间越早。
   for(int i=oldest;i>=0;i--)
     {
      double c=rates[i].close;
      double tr=rates[i].high-rates[i].low;
      if(i<oldest)
        {
         tr=MathMax(tr,MathAbs(rates[i].high-rates[i+1].close));
         tr=MathMax(tr,MathAbs(rates[i].low-rates[i+1].close));
         atr[i]=(atr[i+1]*(MathMax(1,InpATR_Period)-1)+tr)/MathMax(1,InpATR_Period);
         fastLine[i]=aFast*c+(1.0-aFast)*fastLine[i+1];
         double change=MathAbs(c-rates[MathMin(oldest,i+MathMax(1,InpKAMA_ER_Period))].close);
         double volatility=0.0;
         int end=MathMin(oldest,i+MathMax(1,InpKAMA_ER_Period)-1);
         for(int j=i;j<=end;j++)
            if(j+1<=oldest) volatility+=MathAbs(rates[j].close-rates[j+1].close);
         double er=ClampV(SafeDiv(change,volatility,0.0),0.0,1.0);
         double sc=er*(kamaFastSC-kamaSlowSC)+kamaSlowSC;
         sc*=sc;
         kama[i]=kama[i+1]+sc*(c-kama[i+1]);
        }
      else
        {
         atr[i]=tr;
         fastLine[i]=c;
         kama[i]=c;
        }

      double sumSq=0.0;
      int cnt=MathMin(MathMax(1,InpResidual_Period),copied-i);
      for(int j=0;j<cnt;j++)
        {
         double d=rates[i+j].close-kama[i+j];
         sumSq+=d*d;
        }
      double rms=MathSqrt(sumSq/MathMax(1,cnt));
      double half=MathMax(MathMax(atr[i]*InpATR_Min_Multiplier,rms*InpResidual_Multiplier)*InpKAMA_Width_Mult,_Point*2.0);
      kamaUpper[i]=kama[i]+half;
      kamaLower[i]=kama[i]-half;
      refUpper[i]=fastLine[i]+half*MathMax(0.01,InpFast_KAMAWidth_Scale)+InpKAMAReferenceUpperOffset;
      refLower[i]=fastLine[i]-half*MathMax(0.01,InpFast_KAMAWidth_Scale)+InpKAMAReferenceLowerOffset;
     }

   // MACD 主线及信号线，使用 EA 内部缓存数组递推。
   for(int i=oldest;i>=0;i--)
     {
      if(i==oldest) { macdEmaFast[i]=rates[i].close; macdEmaSlow[i]=rates[i].close; }
      else
        {
         macdEmaFast[i]=aMF*rates[i].close+(1.0-aMF)*macdEmaFast[i+1];
         macdEmaSlow[i]=aMS*rates[i].close+(1.0-aMS)*macdEmaSlow[i+1];
        }
      macdMain[i]=macdEmaFast[i]-macdEmaSlow[i];
      if(i==oldest) macdSignalEma[i]=macdMain[i];
      else macdSignalEma[i]=aSig*macdMain[i]+(1.0-aSig)*macdSignalEma[i+1];
      macdSignal[i]=macdSignalEma[i];
     }

   // RSI（Wilder 平滑）。
   for(int i=oldest;i>=0;i--)
     {
      double change=(i<oldest ? rates[i].close-rates[i+1].close : 0.0);
      double gain=MathMax(change,0.0),loss=MathMax(-change,0.0);
      if(i==oldest)
        {
         avgGainFast[i]=gain; avgLossFast[i]=loss;
         avgGainSlow[i]=gain; avgLossSlow[i]=loss;
        }
      else
        {
         avgGainFast[i]=(avgGainFast[i+1]*(InpTrack4_RSI_Fast-1)+gain)/MathMax(1,InpTrack4_RSI_Fast);
         avgLossFast[i]=(avgLossFast[i+1]*(InpTrack4_RSI_Fast-1)+loss)/MathMax(1,InpTrack4_RSI_Fast);
         avgGainSlow[i]=(avgGainSlow[i+1]*(InpTrack4_RSI_Slow-1)+gain)/MathMax(1,InpTrack4_RSI_Slow);
         avgLossSlow[i]=(avgLossSlow[i+1]*(InpTrack4_RSI_Slow-1)+loss)/MathMax(1,InpTrack4_RSI_Slow);
        }
      rsiFast[i]=(avgLossFast[i]<=1.0e-12 ? 100.0 : 100.0-100.0/(1.0+avgGainFast[i]/avgLossFast[i]));
      rsiSlow[i]=(avgLossSlow[i]<=1.0e-12 ? 100.0 : 100.0-100.0/(1.0+avgGainSlow[i]/avgLossSlow[i]));
     }

   // WPR，直接按窗口最高价和最低价计算。
   for(int i=oldest;i>=0;i--)
     {
      for(int which=0;which<2;which++)
        {
         int p=(which==0?MathMax(1,InpTrack4_WPR_Fast):MathMax(1,InpTrack4_WPR_Slow));
         int end=MathMin(oldest,i+p-1);
         double hh=rates[i].high,ll=rates[i].low;
         for(int j=i+1;j<=end;j++) { hh=MathMax(hh,rates[j].high); ll=MathMin(ll,rates[j].low); }
         double value=(hh-ll<=_Point*0.01 ? -50.0 : -100.0*(hh-rates[i].close)/(hh-ll));
         if(which==0) wprFast[i]=value; else wprSlow[i]=value;
        }
     }

   // ADX、+DI、-DI：Wilder 平滑。
   for(int i=oldest;i>=0;i--)
     {
      double tr=rates[i].high-rates[i].low,up=0.0,down=0.0;
      if(i<oldest)
        {
         tr=MathMax(tr,MathAbs(rates[i].high-rates[i+1].close));
         tr=MathMax(tr,MathAbs(rates[i].low-rates[i+1].close));
         double upMove=rates[i].high-rates[i+1].high;
         double downMove=rates[i+1].low-rates[i].low;
         if(upMove>downMove && upMove>0.0) up=upMove;
         if(downMove>upMove && downMove>0.0) down=downMove;
         smoothTR[i]=(smoothTR[i+1]*(InpTrack4_ADX_Period-1)+tr)/MathMax(1,InpTrack4_ADX_Period);
         smoothPlusDM[i]=(smoothPlusDM[i+1]*(InpTrack4_ADX_Period-1)+up)/MathMax(1,InpTrack4_ADX_Period);
         smoothMinusDM[i]=(smoothMinusDM[i+1]*(InpTrack4_ADX_Period-1)+down)/MathMax(1,InpTrack4_ADX_Period);
        }
      else { smoothTR[i]=tr; smoothPlusDM[i]=0.0; smoothMinusDM[i]=0.0; }
      plusDI[i]=100.0*SafeDiv(smoothPlusDM[i],smoothTR[i],0.0);
      minusDI[i]=100.0*SafeDiv(smoothMinusDM[i],smoothTR[i],0.0);
      dx[i]=100.0*SafeDiv(MathAbs(plusDI[i]-minusDI[i]),plusDI[i]+minusDI[i],0.0);
      if(i==oldest) adx[i]=dx[i];
      else adx[i]=(adx[i+1]*(InpTrack4_ADX_Period-1)+dx[i])/MathMax(1,InpTrack4_ADX_Period);
     }

   // 随机指标：STO_LOWHIGH，SMA 平滑，模拟原指标 K/D 输出。
   for(int i=oldest;i>=0;i--)
     {
      int end=MathMin(oldest,i+MathMax(1,InpTrack4_KDJ_K)-1);
      double hh=rates[i].high,ll=rates[i].low;
      for(int j=i+1;j<=end;j++) { hh=MathMax(hh,rates[j].high); ll=MathMin(ll,rates[j].low); }
      rawStoch[i]=(hh-ll<=_Point*0.01?50.0:100.0*(rates[i].close-ll)/(hh-ll));
      int smoothEnd=MathMin(oldest,i+MathMax(1,InpTrack4_KDJ_Slowing)-1);
      double sum=0.0; int n=0;
      for(int j=i;j<=smoothEnd;j++) { sum+=rawStoch[j]; n++; }
      stochK[i]=sum/MathMax(1,n);
     }
   for(int i=oldest;i>=0;i--)
     {
      int end=MathMin(oldest,i+MathMax(1,InpTrack4_KDJ_D)-1);
      double sum=0.0; int n=0;
      for(int j=i;j<=end;j++) { sum+=stochK[j]; n++; }
      stochD[i]=sum/MathMax(1,n);
     }

   // 原融合轨4算法：归一化多指标方向分数、ADX趋势强度、能量与驱离递推。
   for(int i=oldest;i>=0;i--)
     {
      if(!InpEnableFusionTrack4 || i+3>=copied)
        {
         driveUpper[i]=0.0; driveLower[i]=0.0; energy[i]=0.0;
         fusionUpper[i]=EMPTY_VALUE; fusionLower[i]=EMPTY_VALUE;
         continue;
        }
      double atrScale=MathMax(atr[i],_Point*2.0);
      double widthScale=MathMax(0.01,InpFast_KAMAWidth_Scale);
      double baseUpper=fastLine[i]+MathMax(0.0,kamaUpper[i]-kama[i])*widthScale;
      double baseLower=fastLine[i]-MathMax(0.0,kama[i]-kamaLower[i])*widthScale;
      double hist=macdMain[i]-macdSignal[i];
      double oldHist=macdMain[i+1]-macdSignal[i+1];
      double k=stochK[i],d=stochD[i],jLine=3.0*k-2.0*d;
      double rsiScore=0.60*ClampV((rsiFast[i]-rsiSlow[i])/15.0,-1.0,1.0)
                     +0.40*ClampV((rsiSlow[i]-50.0)/25.0,-1.0,1.0);
      double wprScore=0.60*ClampV((wprFast[i]-wprSlow[i])/25.0,-1.0,1.0)
                     +0.40*ClampV((wprSlow[i]+50.0)/35.0,-1.0,1.0);
      double macdLevel=ClampV(hist/MathMax(atrScale*0.12,_Point),-1.0,1.0);
      double macdChange=ClampV((hist-oldHist)/MathMax(atrScale*0.08,_Point),-1.0,1.0);
      double macdScore=0.70*macdLevel+0.30*macdChange;
      double kdjScore=0.45*ClampV((k-d)/20.0,-1.0,1.0)
                     +0.35*ClampV((jLine-50.0)/45.0,-1.0,1.0)
                     +0.20*ClampV((k-50.0)/35.0,-1.0,1.0);
      double diScore=ClampV(SafeDiv(plusDI[i]-minusDI[i],MathMax(plusDI[i]+minusDI[i],1.0),0.0),-1.0,1.0);
      double priceSlope=ClampV((rates[i].close-rates[i+3].close)/MathMax(atrScale*1.50,_Point),-1.0,1.0);
      double body=ClampV((rates[i].close-rates[i].open)/MathMax(atrScale*0.80,_Point),-1.0,1.0);
      double priceScore=0.70*priceSlope+0.30*body;
      double directionScore=ClampV(0.18*rsiScore+0.14*wprScore+0.24*macdScore+0.14*kdjScore+0.18*diScore+0.12*priceScore,-1.0,1.0);
      double adxStrength=ClampV((adx[i]-InpTrack4_ADX_Weak)/MathMax(InpTrack4_ADX_Strong-InpTrack4_ADX_Weak,1.0),0.0,1.0);
      double continuity=ClampV(MathAbs(rates[i].close-rates[i+3].close)/MathMax(atrScale*1.20,_Point),0.0,1.0);
      double rawEnergy=ClampV((MathAbs(directionScore)-0.08)/0.92,0.0,1.0);
      double e=ClampV(rawEnergy*(0.15+0.85*adxStrength)*(0.08+0.92*continuity),0.0,1.0);
      energy[i]=e;
      double targetU=0.0,targetL=0.0;
      if(directionScore>0.0) { targetU=atrScale*InpTrack4_MaxDrive_ATR*e; targetL=atrScale*InpTrack4_MaxLift_ATR*e; }
      else if(directionScore<0.0) { targetU=-atrScale*InpTrack4_MaxLift_ATR*e; targetL=-atrScale*InpTrack4_MaxDrive_ATR*e; }
      if(i==oldest) { driveUpper[i]=targetU; driveLower[i]=targetL; }
      else
        {
         double prevU=driveUpper[i+1],prevL=driveLower[i+1],prevE=energy[i+1];
         double expand=ClampV(InpTrack4_ExpandSpeed,0.01,1.0);
         double recoil=ClampV(InpTrack4_RecoilSpeed,0.01,1.0);
         double fade=ClampV((prevE-e)*1.50,0.0,1.0);
         bool upperExp=((prevU==0.0 || targetU*prevU>0.0) && MathAbs(targetU)>MathAbs(prevU));
         bool lowerExp=((prevL==0.0 || targetL*prevL>0.0) && MathAbs(targetL)>MathAbs(prevL));
         double upperRate=(upperExp?expand:ClampV(recoil+0.20*fade,recoil,0.95));
         double lowerRate=(lowerExp?expand:ClampV(recoil+0.20*fade,recoil,0.95));
         driveUpper[i]=prevU+upperRate*(targetU-prevU);
         driveLower[i]=prevL+lowerRate*(targetL-prevL);
        }
      fusionUpper[i]=baseUpper+driveUpper[i]+InpFusion4UpperOffset;
      fusionLower[i]=baseLower+driveLower[i]+InpFusion4LowerOffset;
     }
   return true;
  }

// 当前K线内只更新索引0，避免每个报价重算整段历史。
bool CalculateCurrentBar()
  {
   int n=ArraySize(rates);
   if(n<MaxRequiredBars()) return false;
   MqlRates latest[];
   ArraySetAsSeries(latest,true);
   if(CopyRates(_Symbol,PERIOD_M5,0,1,latest)!=1) return false;
   rates[0]=latest[0];

   double close0=rates[0].close;
   double tr=MathMax(rates[0].high-rates[0].low,MathMax(MathAbs(rates[0].high-rates[1].close),MathAbs(rates[0].low-rates[1].close)));
   atr[0]=(atr[1]*(MathMax(1,InpATR_Period)-1)+tr)/MathMax(1,InpATR_Period);
   double alphaFast=2.0/(MathMax(1,InpFastEMA_Period)+1.0);
   fastLine[0]=alphaFast*close0+(1.0-alphaFast)*fastLine[1];

   double change=MathAbs(close0-rates[MathMin(n-1,MathMax(1,InpKAMA_ER_Period))].close);
   double volatility=0.0;
   int erEnd=MathMin(n-1,MathMax(1,InpKAMA_ER_Period));
   for(int j=0;j<erEnd;j++) volatility+=MathAbs(rates[j].close-rates[j+1].close);
   double er=ClampV(SafeDiv(change,volatility,0.0),0.0,1.0);
   double fastSC=2.0/(MathMax(1,InpKAMA_Fast_Period)+1.0);
   double slowSC=2.0/(MathMax(2,InpKAMA_Slow_Period)+1.0);
   double sc=er*(fastSC-slowSC)+slowSC;
   sc*=sc;
   kama[0]=kama[1]+sc*(close0-kama[1]);

   double sumSq=0.0;
   int residualN=MathMin(MathMax(1,InpResidual_Period),n);
   for(int j=0;j<residualN;j++)
     {
      double d=rates[j].close-kama[j];
      sumSq+=d*d;
     }
   double rms=MathSqrt(sumSq/MathMax(1,residualN));
   double half=MathMax(MathMax(atr[0]*InpATR_Min_Multiplier,rms*InpResidual_Multiplier)*InpKAMA_Width_Mult,_Point*2.0);
   kamaUpper[0]=kama[0]+half;
   kamaLower[0]=kama[0]-half;
   refUpper[0]=fastLine[0]+half*MathMax(0.01,InpFast_KAMAWidth_Scale)+InpKAMAReferenceUpperOffset;
   refLower[0]=fastLine[0]-half*MathMax(0.01,InpFast_KAMAWidth_Scale)+InpKAMAReferenceLowerOffset;

   double aMF=2.0/(MathMax(1,InpTrack4_MACD_Fast)+1.0);
   double aMS=2.0/(MathMax(1,InpTrack4_MACD_Slow)+1.0);
   double aSig=2.0/(MathMax(1,InpTrack4_MACD_Signal)+1.0);
   macdEmaFast[0]=aMF*close0+(1.0-aMF)*macdEmaFast[1];
   macdEmaSlow[0]=aMS*close0+(1.0-aMS)*macdEmaSlow[1];
   macdMain[0]=macdEmaFast[0]-macdEmaSlow[0];
   macdSignalEma[0]=aSig*macdMain[0]+(1.0-aSig)*macdSignalEma[1];
   macdSignal[0]=macdSignalEma[0];

   double delta=close0-rates[1].close;
   double gain=MathMax(delta,0.0),loss=MathMax(-delta,0.0);
   avgGainFast[0]=(avgGainFast[1]*(InpTrack4_RSI_Fast-1)+gain)/MathMax(1,InpTrack4_RSI_Fast);
   avgLossFast[0]=(avgLossFast[1]*(InpTrack4_RSI_Fast-1)+loss)/MathMax(1,InpTrack4_RSI_Fast);
   avgGainSlow[0]=(avgGainSlow[1]*(InpTrack4_RSI_Slow-1)+gain)/MathMax(1,InpTrack4_RSI_Slow);
   avgLossSlow[0]=(avgLossSlow[1]*(InpTrack4_RSI_Slow-1)+loss)/MathMax(1,InpTrack4_RSI_Slow);
   rsiFast[0]=(avgLossFast[0]<=1.0e-12?100.0:100.0-100.0/(1.0+avgGainFast[0]/avgLossFast[0]));
   rsiSlow[0]=(avgLossSlow[0]<=1.0e-12?100.0:100.0-100.0/(1.0+avgGainSlow[0]/avgLossSlow[0]));

   for(int which=0;which<2;which++)
     {
      int p=(which==0?MathMax(1,InpTrack4_WPR_Fast):MathMax(1,InpTrack4_WPR_Slow));
      int end=MathMin(n-1,p-1);
      double hh=rates[0].high,ll=rates[0].low;
      for(int j=1;j<=end;j++) { hh=MathMax(hh,rates[j].high); ll=MathMin(ll,rates[j].low); }
      double v=(hh-ll<=_Point*0.01?-50.0:-100.0*(hh-close0)/(hh-ll));
      if(which==0) wprFast[0]=v; else wprSlow[0]=v;
     }

   double tr0=rates[0].high-rates[0].low;
   tr0=MathMax(tr0,MathAbs(rates[0].high-rates[1].close));
   tr0=MathMax(tr0,MathAbs(rates[0].low-rates[1].close));
   double upMove=rates[0].high-rates[1].high;
   double downMove=rates[1].low-rates[0].low;
   double up=(upMove>downMove && upMove>0.0?upMove:0.0);
   double down=(downMove>upMove && downMove>0.0?downMove:0.0);
   smoothTR[0]=(smoothTR[1]*(InpTrack4_ADX_Period-1)+tr0)/MathMax(1,InpTrack4_ADX_Period);
   smoothPlusDM[0]=(smoothPlusDM[1]*(InpTrack4_ADX_Period-1)+up)/MathMax(1,InpTrack4_ADX_Period);
   smoothMinusDM[0]=(smoothMinusDM[1]*(InpTrack4_ADX_Period-1)+down)/MathMax(1,InpTrack4_ADX_Period);
   plusDI[0]=100.0*SafeDiv(smoothPlusDM[0],smoothTR[0],0.0);
   minusDI[0]=100.0*SafeDiv(smoothMinusDM[0],smoothTR[0],0.0);
   dx[0]=100.0*SafeDiv(MathAbs(plusDI[0]-minusDI[0]),plusDI[0]+minusDI[0],0.0);
   adx[0]=(adx[1]*(InpTrack4_ADX_Period-1)+dx[0])/MathMax(1,InpTrack4_ADX_Period);

   int kEnd=MathMin(n-1,MathMax(1,InpTrack4_KDJ_K)-1);
   double kh=rates[0].high,kl=rates[0].low;
   for(int j=1;j<=kEnd;j++) { kh=MathMax(kh,rates[j].high); kl=MathMin(kl,rates[j].low); }
   rawStoch[0]=(kh-kl<=_Point*0.01?50.0:100.0*(close0-kl)/(kh-kl));
   int smoothEnd=MathMin(n-1,MathMax(1,InpTrack4_KDJ_Slowing)-1);
   double sum=0.0; int cnt=0;
   for(int j=0;j<=smoothEnd;j++) { sum+=rawStoch[j]; cnt++; }
   stochK[0]=sum/MathMax(1,cnt);
   int dEnd=MathMin(n-1,MathMax(1,InpTrack4_KDJ_D)-1);
   sum=0.0; cnt=0;
   for(int j=0;j<=dEnd;j++) { sum+=stochK[j]; cnt++; }
   stochD[0]=sum/MathMax(1,cnt);

   if(!InpEnableFusionTrack4 || n<4)
     { fusionUpper[0]=EMPTY_VALUE; fusionLower[0]=EMPTY_VALUE; return true; }
   double atrScale=MathMax(atr[0],_Point*2.0);
   double widthScale=MathMax(0.01,InpFast_KAMAWidth_Scale);
   double baseUpper=fastLine[0]+MathMax(0.0,kamaUpper[0]-kama[0])*widthScale;
   double baseLower=fastLine[0]-MathMax(0.0,kama[0]-kamaLower[0])*widthScale;
   double hist=macdMain[0]-macdSignal[0],oldHist=macdMain[1]-macdSignal[1];
   double k=stochK[0],d=stochD[0],jLine=3.0*k-2.0*d;
   double rsiScore=0.60*ClampV((rsiFast[0]-rsiSlow[0])/15.0,-1.0,1.0)+0.40*ClampV((rsiSlow[0]-50.0)/25.0,-1.0,1.0);
   double wprScore=0.60*ClampV((wprFast[0]-wprSlow[0])/25.0,-1.0,1.0)+0.40*ClampV((wprSlow[0]+50.0)/35.0,-1.0,1.0);
   double macdLevel=ClampV(hist/MathMax(atrScale*0.12,_Point),-1.0,1.0);
   double macdChange=ClampV((hist-oldHist)/MathMax(atrScale*0.08,_Point),-1.0,1.0);
   double macdScore=0.70*macdLevel+0.30*macdChange;
   double kdjScore=0.45*ClampV((k-d)/20.0,-1.0,1.0)+0.35*ClampV((jLine-50.0)/45.0,-1.0,1.0)+0.20*ClampV((k-50.0)/35.0,-1.0,1.0);
   double diScore=ClampV(SafeDiv(plusDI[0]-minusDI[0],MathMax(plusDI[0]+minusDI[0],1.0),0.0),-1.0,1.0);
   double priceSlope=ClampV((close0-rates[3].close)/MathMax(atrScale*1.50,_Point),-1.0,1.0);
   double body=ClampV((close0-rates[0].open)/MathMax(atrScale*0.80,_Point),-1.0,1.0);
   double priceScore=0.70*priceSlope+0.30*body;
   double directionScore=ClampV(0.18*rsiScore+0.14*wprScore+0.24*macdScore+0.14*kdjScore+0.18*diScore+0.12*priceScore,-1.0,1.0);
   double adxStrength=ClampV((adx[0]-InpTrack4_ADX_Weak)/MathMax(InpTrack4_ADX_Strong-InpTrack4_ADX_Weak,1.0),0.0,1.0);
   double continuity=ClampV(MathAbs(close0-rates[3].close)/MathMax(atrScale*1.20,_Point),0.0,1.0);
   double rawEnergy=ClampV((MathAbs(directionScore)-0.08)/0.92,0.0,1.0);
   double e=ClampV(rawEnergy*(0.15+0.85*adxStrength)*(0.08+0.92*continuity),0.0,1.0);
   energy[0]=e;
   double targetU=0.0,targetL=0.0;
   if(directionScore>0.0) { targetU=atrScale*InpTrack4_MaxDrive_ATR*e; targetL=atrScale*InpTrack4_MaxLift_ATR*e; }
   else if(directionScore<0.0) { targetU=-atrScale*InpTrack4_MaxLift_ATR*e; targetL=-atrScale*InpTrack4_MaxDrive_ATR*e; }
   double prevU=driveUpper[1],prevL=driveLower[1],prevE=energy[1];
   double expand=ClampV(InpTrack4_ExpandSpeed,0.01,1.0),recoil=ClampV(InpTrack4_RecoilSpeed,0.01,1.0);
   double fade=ClampV((prevE-e)*1.50,0.0,1.0);
   bool upperExp=((prevU==0.0 || targetU*prevU>0.0) && MathAbs(targetU)>MathAbs(prevU));
   bool lowerExp=((prevL==0.0 || targetL*prevL>0.0) && MathAbs(targetL)>MathAbs(prevL));
   double upperRate=(upperExp?expand:ClampV(recoil+0.20*fade,recoil,0.95));
   double lowerRate=(lowerExp?expand:ClampV(recoil+0.20*fade,recoil,0.95));
   driveUpper[0]=prevU+upperRate*(targetU-prevU);
   driveLower[0]=prevL+lowerRate*(targetL-prevL);
   fusionUpper[0]=baseUpper+driveUpper[0]+InpFusion4UpperOffset;
   fusionLower[0]=baseLower+driveLower[0]+InpFusion4LowerOffset;
   return true;
  }

double NormalizeVolume(const double requested)
  {
   double minV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),maxV=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0 || minV<=0.0 || maxV<minV) return 0.0;
   double v=MathMax(minV,MathMin(maxV,requested));
   v=MathFloor((v-minV)/step+1e-8)*step+minV;
   int digits=0; double x=step;
   while(digits<8 && MathAbs(x-MathRound(x))>1e-8) { x*=10.0; digits++; }
   return NormalizeDouble(v,digits);
  }

double NormalizePrice(const double p)
  {
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0.0) tick=_Point;
   return NormalizeDouble(MathRound(p/tick)*tick,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
  }

double StopLossFor(const int direction,const double price)
  {
   double distance=InpStopLossPriceDistance;
   long stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0.0) tick=_Point;
   distance=MathMax(distance,stops*_Point+tick);
   return NormalizePrice(direction==1?price-distance:price+distance);
  }

bool IsOurPosition(const int index,ulong &ticket,ENUM_POSITION_TYPE &type)
  {
   ticket=PositionGetTicket(index);
   if(ticket==0) return false;
   if(PositionGetString(POSITION_SYMBOL)!=_Symbol) return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) return false;
   type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   return true;
  }

int CountPositions(const int direction=0)
  {
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket; ENUM_POSITION_TYPE type;
      if(!IsOurPosition(i,ticket,type)) continue;
      if(direction==1 && type!=POSITION_TYPE_BUY) continue;
      if(direction==-1 && type!=POSITION_TYPE_SELL) continue;
      n++;
     }
   return n;
  }

bool CloseAllOurPositions()
  {
   bool ok=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket; ENUM_POSITION_TYPE type;
      if(!IsOurPosition(i,ticket,type)) continue;
      if(!trade.PositionClose(ticket))
        {
         ok=false;
         PrintFormat("平仓失败 ticket=%I64u ret=%u %s",ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
        }
     }
   return ok && CountPositions()==0;
  }

void MoveStops(const int direction,const double sl)
  {
   if(sl<=0.0) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket; ENUM_POSITION_TYPE type;
      if(!IsOurPosition(i,ticket,type)) continue;
      if(direction==1 && type!=POSITION_TYPE_BUY) continue;
      if(direction==-1 && type!=POSITION_TYPE_SELL) continue;
      double oldSL=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
      if(MathAbs(oldSL-sl)<_Point*0.5) continue;
      if(!trade.PositionModify(ticket,sl,tp))
         PrintFormat("移动止损失败 ticket=%I64u ret=%u %s",ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
     }
  }

bool OpenTrade(const int direction)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   double lots=NormalizeVolume(InpLots);
   if(lots<=0.0) return false;
   double price=(direction==1?tick.ask:tick.bid);
   double sl=StopLossFor(direction,price);
   bool sent=(direction==1?trade.Buy(lots,_Symbol,0.0,sl,0.0,"NMNX Fusion4 BUY"):
                          trade.Sell(lots,_Symbol,0.0,sl,0.0,"NMNX Fusion4 SELL"));
   uint rc=trade.ResultRetcode();
   if(!sent || (rc!=TRADE_RETCODE_DONE && rc!=TRADE_RETCODE_DONE_PARTIAL && rc!=TRADE_RETCODE_PLACED))
     {
      PrintFormat("下单失败 direction=%d ret=%u %s",direction,rc,trade.ResultRetcodeDescription());
      return false;
     }
   double fill=trade.ResultPrice();
   if(fill>0.0) MoveStops(direction,StopLossFor(direction,fill));
   else MoveStops(direction,sl);
   PrintFormat("%s成功 %s lots=%.2f SL=%.*f mode=%d",direction==1?"买入":"卖出",_Symbol,lots,_Digits,sl,(int)InpTradeMode);
   return true;
  }

void ProcessSignal(const int direction)
  {
   if(direction==1 && !InpAllowBuy) return;
   if(direction==-1 && !InpAllowSell) return;
   int same=CountPositions(direction),opposite=CountPositions(-direction);
   if(opposite>0)
     {
      if(!CloseAllOurPositions()) { Print("反向信号平仓未完成，取消反向开仓。"); return; }
      OpenTrade(direction);
      return;
     }
   if(InpTradeMode==MODE_ONE_POSITION)
     {
      if(same>0) return;
      OpenTrade(direction);
      return;
     }
   OpenTrade(direction);
  }

// 图表绘制：仅在用户打开对应开关时创建对象。绘图关闭不影响计算/下单。
void DeleteRailObjects()
  {
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string n=ObjectName(0,i,-1,-1);
      if(StringFind(n,OBJ_PREFIX)==0) ObjectDelete(0,n);
     }
  }

void DrawOneSegment(const string name,const datetime t1,const double p1,const datetime t2,const double p2,const color clr,const ENUM_LINE_STYLE style)
  {
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2);
   else { ObjectMove(0,name,0,t1,p1); ObjectMove(0,name,1,t2,p2); }
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
   int n=ArraySize(rates);
   int bars=MathMin(MathMax(2,InpDisplayBars),n-1);
   for(int i=bars-1;i>=0;i--)
     {
      int j=i+1;
      if(InpShowKAMAReferenceRails)
        {
         DrawOneSegment(OBJ_PREFIX+"KU_"+IntegerToString(i),rates[j].time,refUpper[j],rates[i].time,refUpper[i],clrAqua,STYLE_SOLID);
         DrawOneSegment(OBJ_PREFIX+"KL_"+IntegerToString(i),rates[j].time,refLower[j],rates[i].time,refLower[i],clrAqua,STYLE_SOLID);
        }
      if(InpShowFusionTrack4Rails && fusionUpper[i]!=EMPTY_VALUE && fusionUpper[j]!=EMPTY_VALUE)
        {
         DrawOneSegment(OBJ_PREFIX+"FU_"+IntegerToString(i),rates[j].time,fusionUpper[j],rates[i].time,fusionUpper[i],clrWhite,STYLE_SOLID);
         DrawOneSegment(OBJ_PREFIX+"FL_"+IntegerToString(i),rates[j].time,fusionLower[j],rates[i].time,fusionLower[i],clrWhite,STYLE_DASH);
        }
     }
  }

int OnInit()
  {
   if(_Period!=PERIOD_M5)
     {
      Print("大范围-1 EA 只允许在 M5 图表运行。");
      return INIT_FAILED;
     }
   if(InpLots<=0.0 || InpStopLossPriceDistance<=0.0 || InpCalculationBars<MaxRequiredBars())
      return INIT_PARAMETERS_INCORRECT;
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints((ulong)MathMax(0,InpDeviationPoints));
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetAsyncMode(false);
   gFirstCheck=true;
   gLastProcessedBar=0;
   gCurrentBar=iTime(_Symbol,PERIOD_M5,0);
   PrintFormat("NMNX 自包含EA启动：%s M5，模式=%d，止损距离=%.2f，无止盈；不加载外部指标。",_Symbol,(int)InpTradeMode,InpStopLossPriceDistance);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   DeleteRailObjects();
   Print("NMNX 自包含EA已停止。");
  }

void OnTick()
  {
   if(_Period!=PERIOD_M5) return;
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
   if(newBar || ArraySize(rates)<MaxRequiredBars())
     {
      if(!CalculateAll()) return;
     }
   else
     {
      if(!CalculateCurrentBar()) return;
     }
   if(ArraySize(rates)<4 || fusionUpper[0]==EMPTY_VALUE || fusionLower[0]==EMPTY_VALUE) return;

   // 与原指标一致：逐报价检查当前K线最高/最低，一旦触轨就锁定触碰瞬间的轨道价。
   if(!gUpperLatched && rates[0].high>=fusionUpper[0])
     { gUpperLatched=true; gUpperTouchPrice=fusionUpper[0]; }
   if(!gLowerLatched && rates[0].low<=fusionLower[0])
     { gLowerLatched=true; gLowerTouchPrice=fusionLower[0]; }

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
   bool buySignal=gLowerLatched,sellSignal=gUpperLatched;
   if(buySignal && sellSignal)
     {
      gLastProcessedBar=barTime;
      Print("当前M5同一根K线触及融合轨4上下轨，方向不明确，本根不下单。");
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
   PrintFormat("融合轨4触轨信号：%s %s 时间=%s 触轨价=%.*f",
               direction==1?"买入":"卖出",_Symbol,TimeToString(barTime,TIME_DATE|TIME_MINUTES),
               _Digits,direction==1?gLowerTouchPrice:gUpperTouchPrice);
   ProcessSignal(direction);
  }
//+------------------------------------------------------------------+
