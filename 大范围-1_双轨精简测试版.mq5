// NMNX 双轨精简测试版
// 计算链仅保留：快速线中心 + KAMA宽度；融合轨4原始动能驱离公式。
// 触轨统计为指标理论轨道价统计，不等同于交易所/经纪商真实成交回测。
#property strict
#property version "0.10"
#property description "NMNX精简双轨实验指标：仅保留KAMA宽度通道、融合轨4及触轨统计"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots 6

#property indicator_label1 "KAMA宽度上轨"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrAqua
#property indicator_style1 STYLE_SOLID
#property indicator_width1 2
#property indicator_label2 "KAMA宽度下轨"
#property indicator_type2 DRAW_LINE
#property indicator_color2 clrAqua
#property indicator_style2 STYLE_SOLID
#property indicator_width2 2
#property indicator_label3 "融合轨4上轨"
#property indicator_type3 DRAW_LINE
#property indicator_color3 clrWhite
#property indicator_style3 STYLE_SOLID
#property indicator_width3 2
#property indicator_label4 "融合轨4下轨"
#property indicator_type4 DRAW_LINE
#property indicator_color4 clrWhite
#property indicator_style4 STYLE_DASH
#property indicator_width4 2
#property indicator_label5 "融合轨4上轨触碰_卖出观察"
#property indicator_type5 DRAW_ARROW
#property indicator_color5 clrTomato
#property indicator_width5 2
#property indicator_label6 "融合轨4下轨触碰_买入观察"
#property indicator_type6 DRAW_ARROW
#property indicator_color6 clrLime
#property indicator_width6 2

input group "01 · KAMA宽度通道"
input int    InpFastEMA_Period       = 3;
input int    InpKAMA_ER_Period       = 8;
input int    InpKAMA_Fast_Period     = 2;
input int    InpKAMA_Slow_Period     = 20;
input int    InpATR_Period           = 7;
input int    InpResidual_Period      = 10;
input double InpATR_Min_Multiplier   = 0.35;
input double InpResidual_Multiplier  = 1.00;
input double InpKAMA_Width_Mult      = 1.00;
input double InpFast_KAMAWidth_Scale = 1.00;

input group "02 · 融合轨4综合动能驱离"
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

input group "03 · 统计与测试"

#define UI_PREFIX "NMNX_CF30_"
#define STATS_LINE_COUNT 24
#define TRACK4_OFFSET_STEP 0.1

double FastLine[], KAMALine[], KAMAUpper[], KAMALower[];
double FastKAMAWidthUpper[], FastKAMAWidthLower[];
double Composite4Upper[], Composite4Lower[], SellTouchArrow[], BuyTouchArrow[];
double Atr[], Track4DriveUpper[], Track4DriveLower[], Track4Energy[];
double Track4MACDMain[],Track4MACDSignal[],Track4RSI7[],Track4RSI17[];
double Track4WPR7[],Track4WPR14[],Track4K[],Track4D[],Track4ADX[],Track4PlusDI[],Track4MinusDI[];
double Composite4BaseUpper[],Composite4BaseLower[];
int gTrack4MACDHandle=INVALID_HANDLE,gTrack4RSI7Handle=INVALID_HANDLE,gTrack4RSI17Handle=INVALID_HANDLE;
int gTrack4WPR7Handle=INVALID_HANDLE,gTrack4WPR14Handle=INVALID_HANDLE,gTrack4ADXHandle=INVALID_HANDLE,gTrack4KDJHandle=INVALID_HANDLE;
double gTrack4UpperOffset=0.0, gTrack4LowerOffset=0.0;
bool gTouchSpacingFilter=true;
int gCachedRatesTotal=0;

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
input double InpStatsCostPointsPerPosition = 0.0; // 每笔仓位估算交易成本（统计点）；0表示不扣成本

//==================== 触轨箭头与近10个交易日统计 ====================
#define STATS_LINE_COUNT 24
string StatsObjectName(const int row)
  {
   return UI_PREFIX+"STATS_"+IntegerToString(row);
  }
string StatsBackgroundName()
  {
   return UI_PREFIX+"STATS_BG";
  }
string StatsDateKey(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t,dt);
   return StringFormat("%04d.%02d.%02d",dt.year,dt.mon,dt.day);
  }
string StatsDateTimeKey(const datetime t)
  {
   return TimeToString(t,TIME_DATE|TIME_MINUTES);
  }

// 清理本指标上一次计算生成的亏损交易连线，避免每次刷新重复叠加。
void ClearLossTradeLines()
  {
   string prefix=UI_PREFIX+"LOSSLINE_";
   for(int obj=ObjectsTotal(0,-1,-1)-1;obj>=0;obj--)
     {
      string objName=ObjectName(0,obj,-1,-1);
      if(StringFind(objName,prefix)==0) ObjectDelete(0,objName);
     }
  }

// 将亏损仓位的入场触轨点与反向触轨平仓点连接起来。
void DrawLossTradeLine(const datetime entryTime,const double entryPrice,
                       const datetime exitTime,const double exitPrice,const int serial)
  {
   string name=UI_PREFIX+"LOSSLINE_"+IntegerToString((long)entryTime)+"_"+
               IntegerToString((long)exitTime)+"_"+IntegerToString(serial);
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   if(!ObjectCreate(0,name,OBJ_TREND,0,entryTime,entryPrice,exitTime,exitPrice)) return;
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrRed);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,
                   "亏损交易（连线端点=统计成交价） | 入场："+StatsDateTimeKey(entryTime)+
                   " | 平仓："+StatsDateTimeKey(exitTime)+
                   " | 入场价："+DoubleToString(entryPrice,_Digits)+
                   " | 平仓价："+DoubleToString(exitPrice,_Digits));
  }
int FindStatsDay(const string key,const string &keys[],const int count)
  {
   for(int i=0;i<count;i++) if(keys[i]==key) return i;
   return -1;
  }
void CreateStatsPanel()
  {
   string bg=StatsBackgroundName();
   if(ObjectFind(0,bg)>=0) ObjectDelete(0,bg);
   ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,8);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,8);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,560);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,STATS_LINE_COUNT*16+8);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'10,10,10');
   ObjectSetInteger(0,bg,OBJPROP_COLOR,clrDimGray);
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);
   for(int i=0;i<STATS_LINE_COUNT;i++)
     {
      string name=StatsObjectName(i);
      if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,15);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,13+i*16);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
      ObjectSetString(0,name,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetString(0,name,OBJPROP_TEXT,"");
     }
  }
void SetStatsLine(const int row,const string text,const color clr=clrWhite)
  {
   string name=StatsObjectName(row);
   if(ObjectFind(0,name)<0) return;
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
  }
void CreateTouchFilterButton()
  {
   string name=UI_PREFIX+"TOUCH_FILTER";
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,8);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,8+STATS_LINE_COUNT*16+12);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,224);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,24);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetString(0,name,OBJPROP_FONT,"Microsoft YaHei UI");
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,(gTouchSpacingFilter ? clrDarkGreen : clrDimGray));
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrSilver);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
   ObjectSetString(0,name,OBJPROP_TEXT,(gTouchSpacingFilter ? "三根K线限一个触点：[开]" : "三根K线限一个触点：[关]"));
  }

void RefreshTouchFilterButton()
  {
   string name=UI_PREFIX+"TOUCH_FILTER";
   if(ObjectFind(0,name)<0) return;
   ObjectSetString(0,name,OBJPROP_TEXT,(gTouchSpacingFilter ? "三根K线限一个触点：[开]" : "三根K线限一个触点：[关]"));
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,(gTouchSpacingFilter ? clrDarkGreen : clrDimGray));
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
  }

// A规则：理论触轨成交。入场/平仓/箭头/连线统一直接采用对应融合轨4轨道价。
// 不用开盘价或收盘价替代轨道价；这是指标理论统计，不含跳空、点差与滑点模拟。
double GetTouchExecutionPrice(const int direction,const int i,const double &open[],
                              const double &upper[],const double &lower[])
  {
   if(direction==1)  // 下轨触发多头
      return lower[i];
   if(direction==-1) // 上轨触发空头
      return upper[i];
   return EMPTY_VALUE;
  }

void UpdateTouchArrowsAndStats(const int rates_total,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[])
  {
   if(rates_total<3) return;
   ArrayInitialize(SellTouchArrow,EMPTY_VALUE);
   ArrayInitialize(BuyTouchArrow,EMPTY_VALUE);

   // acceptedUpper/Lower 保存经过触点间隔筛选后的信号，箭头和统计共用同一份信号序列。
   int acceptedUpper[],acceptedLower[];
   ArrayResize(acceptedUpper,rates_total);
   ArrayResize(acceptedLower,rates_total);
   ArrayInitialize(acceptedUpper,0);
   ArrayInitialize(acceptedLower,0);

   // 从旧到新扫描。三根K线过滤只约束同方向重复触点，反向触点必须无条件通过，
   // 因为反向触点会统一平掉当前方向的全部模拟仓位。
   int lastAcceptedTouchIndex=-1;
   int lastAcceptedTouchDirection=0; // +1下轨多头，-1上轨空头，0表示同K线双触轨/方向不明
   for(int i=rates_total-1;i>=1;i--)
     {
      if(Composite4Upper[i]==EMPTY_VALUE || Composite4Lower[i]==EMPTY_VALUE ||
         !MathIsValidNumber(Composite4Upper[i]) || !MathIsValidNumber(Composite4Lower[i]))
         continue;
      bool touchUpper=(high[i]>=Composite4Upper[i]);
      bool touchLower=(low[i]<=Composite4Lower[i]);
      if(!touchUpper && !touchLower) continue;

      // 同一根K线同时触及上下轨，仍保留两个触点标记，但不把它当成明确的方向切换。
      int touchDirection=(touchLower && !touchUpper ? 1 : (touchUpper && !touchLower ? -1 : 0));
      bool isOpposite=(touchDirection!=0 && lastAcceptedTouchDirection!=0 && touchDirection!=lastAcceptedTouchDirection);
      if(gTouchSpacingFilter && !isOpposite && touchDirection!=0 && lastAcceptedTouchIndex>=0 &&
         (lastAcceptedTouchIndex-i)<3 && touchDirection==lastAcceptedTouchDirection)
         continue;

      acceptedUpper[i]=(touchUpper ? 1 : 0);
      acceptedLower[i]=(touchLower ? 1 : 0);
      lastAcceptedTouchIndex=i;
      lastAcceptedTouchDirection=touchDirection;

      // 箭头直接画在轨道与K线的接触价位，不再偏移到K线最高/最低点之外。
      if(touchUpper) SellTouchArrow[i]=GetTouchExecutionPrice(-1,i,open,Composite4Upper,Composite4Lower);
      if(touchLower) BuyTouchArrow[i]=GetTouchExecutionPrice(1,i,open,Composite4Upper,Composite4Lower);
     }

   // 取最近10个有K线的交易日期，按最新日期优先建立统计桶。
   string dayKeys[10];
   int dayCount=0;
   string previous="";
   for(int i=1;i<rates_total && dayCount<10;i++)
     {
      string key=StatsDateKey(time[i]);
      if(key!=previous)
        {
         dayKeys[dayCount]=key;
         dayCount++;
         previous=key;
        }
     }
   if(dayCount==0) return;

   int dayTrades[10],dayWins[10],dayLosses[10];
   double dayWinPoints[10],dayLossPoints[10],dayNetPoints[10];
   ArrayInitialize(dayTrades,0); ArrayInitialize(dayWins,0); ArrayInitialize(dayLosses,0);
   ArrayInitialize(dayWinPoints,0.0); ArrayInitialize(dayLossPoints,0.0); ArrayInitialize(dayNetPoints,0.0);

   int totalTrades=0,totalWins=0,totalLosses=0;
   double totalWinPoints=0.0,totalLossPoints=0.0,totalNetPoints=0.0;
   double totalWinSum=0.0,totalLossSum=0.0;
   double maxSingleLoss=0.0,maxFloatingLoss=0.0,maxDailyDrawdown=0.0;
   int maxSimultaneousPositions=0,currentConsecutiveLosses=0,maxConsecutiveLosses=0;
   string maxFloatingLossDate="无",maxSingleLossDate="无",maxPositionsDates="无";
   string currentLossStartDate="无",maxConsecutiveStartDate="无",maxConsecutiveEndDate="无";
   int trendTrades=0,trendWins=0,rangeTrades=0,rangeWins=0;
   double totalCostPoints=0.0;

   // 每次重新计算先清除旧亏损连线，再按当前历史数据重建。
   ClearLossTradeLines();

   // 持仓篮子统计：同方向每次合格触点都新增一笔；反向触点到来时，所有同向仓位统一在该信号K线收盘价平仓。
   // 每笔仓位仍分别按自己的入场价计算盈亏，不能把A/B/C合并成一个入场价。
   double activeEntryPrices[];
   datetime activeEntryTimes[];
   int activeCount=0;
   int activeDirection=0; // +1多头，-1空头

   for(int i=rates_total-1;i>=1;i--)
     {
      // 每根K线按收盘价估算仍未平仓篮子的浮动盈亏，记录最深浮亏；该值是历史K线近似值。
      if(activeCount>0)
        {
         double floatingPoints=0.0;
         for(int fp=0;fp<activeCount;fp++)
            floatingPoints+=(activeDirection==1 ? (close[i]-activeEntryPrices[fp]) : (activeEntryPrices[fp]-close[i]))*10.0;
         if(floatingPoints<0.0 && -floatingPoints>maxFloatingLoss)
          { maxFloatingLoss=-floatingPoints; maxFloatingLossDate=StatsDateTimeKey(time[i]); }
        }
      if(activeCount>maxSimultaneousPositions)
        { maxSimultaneousPositions=activeCount; maxPositionsDates=StatsDateTimeKey(time[i]); }
      else if(activeCount==maxSimultaneousPositions && maxSimultaneousPositions>0)
        { string pd=StatsDateTimeKey(time[i]); if(StringFind("|"+maxPositionsDates+"|","|"+pd+"|")<0) maxPositionsDates+="、"+pd; }
      bool upper=(acceptedUpper[i]!=0);
      bool lower=(acceptedLower[i]!=0);
      if(upper==lower) continue; // 没有信号或同一根K线同时触及两轨，无法确认先后顺序
      int direction=(lower ? 1 : -1);

      if(activeCount==0)
        {
         activeDirection=direction;
         ArrayResize(activeEntryPrices,1);
         ArrayResize(activeEntryTimes,1);
         activeEntryPrices[0]=GetTouchExecutionPrice(direction,i,open,Composite4Upper,Composite4Lower);
         activeEntryTimes[0]=time[i];
         activeCount=1;
         if(activeCount>maxSimultaneousPositions)
           { maxSimultaneousPositions=activeCount; maxPositionsDates=StatsDateTimeKey(time[i]); }
         else if(activeCount==maxSimultaneousPositions && maxSimultaneousPositions>0)
           { string pd2=StatsDateTimeKey(time[i]); if(StringFind("|"+maxPositionsDates+"|","|"+pd2+"|")<0) maxPositionsDates+="、"+pd2; }
         continue;
        }

      if(direction==activeDirection)
        {
         ArrayResize(activeEntryPrices,activeCount+1);
         ArrayResize(activeEntryTimes,activeCount+1);
         activeEntryPrices[activeCount]=GetTouchExecutionPrice(direction,i,open,Composite4Upper,Composite4Lower);
         activeEntryTimes[activeCount]=time[i];
         activeCount++;
         if(activeCount>maxSimultaneousPositions)
           { maxSimultaneousPositions=activeCount; maxPositionsDates=StatsDateTimeKey(time[i]); }
         else if(activeCount==maxSimultaneousPositions && maxSimultaneousPositions>0)
           { string pd2=StatsDateTimeKey(time[i]); if(StringFind("|"+maxPositionsDates+"|","|"+pd2+"|")<0) maxPositionsDates+="、"+pd2; }
         continue;
        }

      // 反向触点：篮子中每笔仓位统一在反向轨道接触价平仓，而非K线收盘价。
      // 统计点数统一采用“价格每波动1.00美元=10点”，避免直接除以_Point造成点数放大。
      string exitKey=StatsDateKey(time[i]);
      int d=FindStatsDay(exitKey,dayKeys,dayCount);
      double exitTouchPrice=GetTouchExecutionPrice(direction,i,open,Composite4Upper,Composite4Lower);
      for(int p=0;p<activeCount;p++)
        {
         double points=(activeDirection==1 ? (exitTouchPrice-activeEntryPrices[p]) : (activeEntryPrices[p]-exitTouchPrice))*10.0;
         if(d>=0)
           {
            totalTrades++;
            double netAfterCost=points-InpStatsCostPointsPerPosition;
            totalCostPoints+=InpStatsCostPointsPerPosition;
            totalNetPoints+=netAfterCost;
            dayTrades[d]++;
            dayNetPoints[d]+=netAfterCost;
            if(points>0.0)
              {
               totalWins++; totalWinPoints+=points; totalWinSum+=points;
               dayWins[d]++; dayWinPoints[d]+=points;
               currentConsecutiveLosses=0; currentLossStartDate="无";
              }
            else if(points<0.0)
              {
               totalLosses++; totalLossPoints+=-points; totalLossSum+=-points;
               dayLosses[d]++; dayLossPoints[d]+=-points;
               // 只为纳入最近10个交易日统计的亏损仓位画线：入场触轨点 -> 反向触轨平仓点。
               DrawLossTradeLine(activeEntryTimes[p],activeEntryPrices[p],time[i],exitTouchPrice,p);
               if(-points>maxSingleLoss) { maxSingleLoss=-points; maxSingleLossDate=StatsDateTimeKey(time[i]); }
               if(currentConsecutiveLosses==0) currentLossStartDate=StatsDateTimeKey(time[i]);
               currentConsecutiveLosses++;
               if(currentConsecutiveLosses>maxConsecutiveLosses)
                 { maxConsecutiveLosses=currentConsecutiveLosses; maxConsecutiveStartDate=currentLossStartDate; maxConsecutiveEndDate=StatsDateTimeKey(time[i]); }
              }
            // 按平仓触发时的ADX粗分趋势/震荡：ADX>=20计入趋势组，低于20计入震荡组。
            if(i<ArraySize(Track4ADX) && Track4ADX[i]!=EMPTY_VALUE && MathIsValidNumber(Track4ADX[i]) && Track4ADX[i]>=20.0)
              { trendTrades++; if(netAfterCost>0.0) trendWins++; }
            else
              { rangeTrades++; if(netAfterCost>0.0) rangeWins++; }
           }
        }

      // 全部旧方向仓位已经在同一位置平仓；当前反向触点同时成为新方向的第一笔入场。
      activeDirection=direction;
      activeCount=1;
      ArrayResize(activeEntryPrices,1);
      ArrayResize(activeEntryTimes,1);
      activeEntryPrices[0]=GetTouchExecutionPrice(direction,i,open,Composite4Upper,Composite4Lower);
      activeEntryTimes[0]=time[i];
     }

   SetStatsLine(0,"NMNX 双轨触轨统计 | 最近10个交易日 | 价格波动1.00美元=10点",clrAqua);
   SetStatsLine(1,"日期        胜率   完成仓位   盈利点   亏损点    净点",clrSilver);
   for(int row=0;row<10;row++)
     {
      if(row<dayCount)
        {
         int d=dayCount-1-row; // 按日期从旧到新显示
         double accuracy=(dayTrades[d]>0 ? 100.0*dayWins[d]/dayTrades[d] : 0.0);
         string line=StringFormat("%s  %5.1f%%  %4d  +%7.1f  -%7.1f  %+7.1f",dayKeys[d],accuracy,dayTrades[d],dayWinPoints[d],dayLossPoints[d],dayNetPoints[d]);
         SetStatsLine(2+row,line,clrWhite);
        }
      else SetStatsLine(2+row,"",clrWhite);
     }
   double accuracyAll=(totalTrades>0 ? 100.0*totalWins/totalTrades : 0.0);
   double avgWin=(totalWins>0 ? totalWinSum/totalWins : 0.0);
   double avgLoss=(totalLosses>0 ? totalLossSum/totalLosses : 0.0);
   double avgTrade=(totalTrades>0 ? totalNetPoints/totalTrades : 0.0);
   double trendAccuracy=(trendTrades>0 ? 100.0*trendWins/trendTrades : 0.0);
   double rangeAccuracy=(rangeTrades>0 ? 100.0*rangeWins/rangeTrades : 0.0);
   // 最近10个交易日的每日净值曲线与最大回撤（以每日已平仓净点数累计）。
   double cumulative=0.0,peak=0.0;
   for(int d=dayCount-1;d>=0;d--)
     {
      cumulative+=dayNetPoints[d];
      if(cumulative>peak) peak=cumulative;
      double dd=peak-cumulative;
      if(dd>maxDailyDrawdown) maxDailyDrawdown=dd;
     }
   SetStatsLine(12,StringFormat("总计：胜率 %.1f%% | 完成仓位 %d | 盈利 %d | 亏损 %d",accuracyAll,totalTrades,totalWins,totalLosses),clrAqua);
   SetStatsLine(13,StringFormat("总盈利 +%.1f点 | 总亏损 -%.1f点 | 净值(扣成本) %.1f点",totalWinPoints,totalLossPoints,totalNetPoints),(totalNetPoints>=0.0 ? clrLime : clrTomato));
   SetStatsLine(14,StringFormat("平均盈利 +%.1f | 平均亏损 -%.1f | 平均每仓 %.1f点",avgWin,avgLoss,avgTrade),clrWhite);
   SetStatsLine(15,StringFormat("风险：最大单笔亏损 %.1f点 | 最大连续亏损 %d笔",maxSingleLoss,maxConsecutiveLosses),clrOrange);
   SetStatsLine(16,StringFormat("持仓：最大同时仓位 %d笔 | 历史K线估算最大浮亏 %.1f点",maxSimultaneousPositions,maxFloatingLoss),clrOrange);
   SetStatsLine(17,StringFormat("行情分组(ADX20)：趋势胜率 %.1f%%(%d笔) | 震荡胜率 %.1f%%(%d笔)",trendAccuracy,trendTrades,rangeAccuracy,rangeTrades),clrAqua);
   SetStatsLine(18,StringFormat("成本：估算成本 %.1f点 | 每仓成本设置 %.1f点",totalCostPoints,InpStatsCostPointsPerPosition),clrWhite);
   SetStatsLine(19,StringFormat("近10日净值回撤：最大 %.1f点 | 统计基于已平仓日净值",maxDailyDrawdown),clrWhite);
   SetStatsLine(20,StringFormat("最大浮亏时间：%s",maxFloatingLossDate),clrOrange);
   SetStatsLine(21,StringFormat("最大同时仓位时间：%s",maxPositionsDates),clrOrange);
   SetStatsLine(22,StringFormat("最大单笔亏损时间：%s",maxSingleLossDate),clrOrange);
   SetStatsLine(23,StringFormat("最长连续亏损：%d笔 | 时间 %s 至 %s",maxConsecutiveLosses,maxConsecutiveStartDate,maxConsecutiveEndDate),clrOrange);
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

int OnInit()
{
   if(InpFastEMA_Period<1 || InpKAMA_ER_Period<1 || InpKAMA_Fast_Period<1 ||
      InpKAMA_Slow_Period<=InpKAMA_Fast_Period || InpATR_Period<1 ||
      InpResidual_Period<1 || InpATR_Min_Multiplier<=0.0 ||
      InpResidual_Multiplier<0.0 || InpKAMA_Width_Mult<=0.0 ||
      InpFast_KAMAWidth_Scale<=0.0 ||
      InpTrack4_MACD_Fast<1 || InpTrack4_MACD_Slow<=InpTrack4_MACD_Fast ||
      InpTrack4_MACD_Signal<1 || InpTrack4_RSI_Fast<2 || InpTrack4_RSI_Slow<2 ||
      InpTrack4_WPR_Fast<2 || InpTrack4_WPR_Slow<2 || InpTrack4_ADX_Period<2 ||
      InpTrack4_KDJ_K<1 || InpTrack4_KDJ_D<1 || InpTrack4_KDJ_Slowing<1 ||
      InpTrack4_ADX_Strong<=InpTrack4_ADX_Weak ||
      InpTrack4_ExpandSpeed<=0.0 || InpTrack4_ExpandSpeed>1.0 ||
      InpTrack4_RecoilSpeed<=0.0 || InpTrack4_RecoilSpeed>1.0)
      return INIT_PARAMETERS_INCORRECT;

   SetIndexBuffer(0,FastKAMAWidthUpper,INDICATOR_DATA);
   SetIndexBuffer(1,FastKAMAWidthLower,INDICATOR_DATA);
   SetIndexBuffer(2,Composite4Upper,INDICATOR_DATA);
   SetIndexBuffer(3,Composite4Lower,INDICATOR_DATA);
   SetIndexBuffer(4,SellTouchArrow,INDICATOR_DATA);
   SetIndexBuffer(5,BuyTouchArrow,INDICATOR_DATA);
   ArraySetAsSeries(FastKAMAWidthUpper,true); ArraySetAsSeries(FastKAMAWidthLower,true);
   ArraySetAsSeries(Composite4Upper,true); ArraySetAsSeries(Composite4Lower,true);
   ArraySetAsSeries(SellTouchArrow,true); ArraySetAsSeries(BuyTouchArrow,true);
   PlotIndexSetInteger(4,PLOT_ARROW,234);
   PlotIndexSetInteger(5,PLOT_ARROW,233);
   for(int p=0;p<6;p++) PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   gTrack4MACDHandle=iMACD(_Symbol,_Period,InpTrack4_MACD_Fast,InpTrack4_MACD_Slow,InpTrack4_MACD_Signal,PRICE_CLOSE);
   gTrack4RSI7Handle=iRSI(_Symbol,_Period,InpTrack4_RSI_Fast,PRICE_CLOSE);
   gTrack4RSI17Handle=iRSI(_Symbol,_Period,InpTrack4_RSI_Slow,PRICE_CLOSE);
   gTrack4WPR7Handle=iWPR(_Symbol,_Period,InpTrack4_WPR_Fast);
   gTrack4WPR14Handle=iWPR(_Symbol,_Period,InpTrack4_WPR_Slow);
   gTrack4ADXHandle=iADX(_Symbol,_Period,InpTrack4_ADX_Period);
   gTrack4KDJHandle=iStochastic(_Symbol,_Period,InpTrack4_KDJ_K,InpTrack4_KDJ_D,InpTrack4_KDJ_Slowing,MODE_SMA,STO_LOWHIGH);
   if(gTrack4MACDHandle==INVALID_HANDLE || gTrack4RSI7Handle==INVALID_HANDLE ||
      gTrack4RSI17Handle==INVALID_HANDLE || gTrack4WPR7Handle==INVALID_HANDLE ||
      gTrack4WPR14Handle==INVALID_HANDLE || gTrack4ADXHandle==INVALID_HANDLE ||
      gTrack4KDJHandle==INVALID_HANDLE)
      return INIT_FAILED;

   CreateStatsPanel();
   CreateTouchFilterButton();
   return INIT_SUCCEEDED;
}


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
      if(StringFind(n,UI_PREFIX)==0) ObjectDelete(0,n);
   }
}


void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==UI_PREFIX+"TOUCH_FILTER")
   {
      gTouchSpacingFilter=!gTouchSpacingFilter;
      RefreshTouchFilterButton();
      ChartRedraw(0);
   }
}


int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<MathMax(50,InpKAMA_ER_Period+InpResidual_Period+5)) return 0;
   ArraySetAsSeries(time,true); ArraySetAsSeries(open,true); ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true); ArraySetAsSeries(close,true);
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

   bool ready=true;
   if(CopyBuffer(gTrack4MACDHandle,0,0,rates_total,Track4MACDMain)<rates_total) ready=false;
   if(CopyBuffer(gTrack4MACDHandle,1,0,rates_total,Track4MACDSignal)<rates_total) ready=false;
   if(CopyBuffer(gTrack4RSI7Handle,0,0,rates_total,Track4RSI7)<rates_total) ready=false;
   if(CopyBuffer(gTrack4RSI17Handle,0,0,rates_total,Track4RSI17)<rates_total) ready=false;
   if(CopyBuffer(gTrack4WPR7Handle,0,0,rates_total,Track4WPR7)<rates_total) ready=false;
   if(CopyBuffer(gTrack4WPR14Handle,0,0,rates_total,Track4WPR14)<rates_total) ready=false;
   if(CopyBuffer(gTrack4KDJHandle,0,0,rates_total,Track4K)<rates_total) ready=false;
   if(CopyBuffer(gTrack4KDJHandle,1,0,rates_total,Track4D)<rates_total) ready=false;
   if(CopyBuffer(gTrack4ADXHandle,0,0,rates_total,Track4ADX)<rates_total) ready=false;
   if(CopyBuffer(gTrack4ADXHandle,1,0,rates_total,Track4PlusDI)<rates_total) ready=false;
   if(CopyBuffer(gTrack4ADXHandle,2,0,rates_total,Track4MinusDI)<rates_total) ready=false;
   if(!ready) return prev_calculated;

   double alphaFast=2.0/(InpFastEMA_Period+1.0);
   double fastSC=2.0/(InpKAMA_Fast_Period+1.0), slowSC=2.0/(InpKAMA_Slow_Period+1.0);
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

      FastLine[i]=(i==rates_total-1 ? close[i] : alphaFast*close[i]+(1.0-alphaFast)*FastLine[i+1]);
      if(i==rates_total-1) KAMALine[i]=close[i];
      else
      {
         int oldIndex=MathMin(rates_total-1,i+InpKAMA_ER_Period);
         double change=MathAbs(close[i]-close[oldIndex]), volatility=0.0;
         int endIndex=MathMin(rates_total-1,i+InpKAMA_ER_Period-1);
         for(int j=i;j<=endIndex;j++)
         {
            int next=j+1;
            if(next<rates_total) volatility+=MathAbs(close[j]-close[next]);
         }
         double er=(volatility>0.0 ? change/volatility : 0.0);
         er=ClampValue(er,0.0,1.0);
         double sc=er*(fastSC-slowSC)+slowSC; sc*=sc;
         KAMALine[i]=KAMALine[i+1]+sc*(close[i]-KAMALine[i+1]);
      }
   }

   for(int i=rates_total-1;i>=0;i--)
   {
      double atrValue=MathMax(Atr[i],_Point*2.0);
      double minHalf=atrValue*InpATR_Min_Multiplier;
      double wKAMA=MathMax(minHalf,ResidualRMSAt(i,InpResidual_Period,rates_total,close,KAMALine)*InpResidual_Multiplier)*InpKAMA_Width_Mult;
      KAMAUpper[i]=KAMALine[i]+wKAMA;
      KAMALower[i]=KAMALine[i]-wKAMA;
      double halfUp=MathMax(0.0,KAMAUpper[i]-KAMALine[i]);
      double halfDown=MathMax(0.0,KAMALine[i]-KAMALower[i]);
      double scale=MathMax(0.01,InpFast_KAMAWidth_Scale);
      FastKAMAWidthUpper[i]=FastLine[i]+halfUp*scale;
      FastKAMAWidthLower[i]=FastLine[i]-halfDown*scale;
   }
   for(int i=rates_total-1;i>=0;i--)
      CalculateTrack4At(i,rates_total,open,close,ready);
   UpdateTouchArrowsAndStats(rates_total,time,open,high,low,close);
   gCachedRatesTotal=rates_total;
   return rates_total;
}

