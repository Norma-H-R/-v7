//+------------------------------------------------------------------+
//| 大范围-1_Core.mq5                                                 |
//| 南门拈星：KAMA宽度参考轨 + 融合轨4 + 实时触轨统计                   |
//| 只计算并显示 KAMA 宽度参考上下轨、融合轨4上下轨与触轨箭头。           |
//| 触点判定改为逐tick实时判定：价格在运动中碰到外轨即锁定，不等收盘。     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.71"
#property description "EA后台核心计算版：保留原指标算法，关闭图表按钮与统计绘制。"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

// 0 KAMA宽度参考上轨
#property indicator_label1  "KAMA参考上轨"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrAqua
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// 1 KAMA宽度参考下轨
#property indicator_label2  "KAMA参考下轨"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrAqua
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

// 2 融合轨4上轨
#property indicator_label3  "融合轨4上轨_综合动能驱离"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrWhite
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

// 3 融合轨4下轨
#property indicator_label4  "融合轨4下轨_综合动能驱离"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrWhite
#property indicator_style4  STYLE_DASH
#property indicator_width4  2

// 4 上轨触碰：卖出观察箭头
#property indicator_label5  "融合轨4上轨触碰_卖出观察"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrTomato
#property indicator_width5  2

// 5 下轨触碰：买入观察箭头
#property indicator_label6  "融合轨4下轨触碰_买入观察"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrLime
#property indicator_width6  2

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

input group "04 · 触轨统计"
input double InpStatsPointValue            = 10.0; // 价格每波动1.00对应的统计点数
input double InpStatsCostPointsPerPosition = 0.0;  // 每笔仓位估算成本（统计点）；0表示不扣成本

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
//| 持久化                                                            |
//+------------------------------------------------------------------+
string OffsetKey(const string rail)
  {
   // 沿用旧版键名规则，保证已经校准好的偏移在新版本里继续生效
   return "NMNX_CF42_"+_Symbol+"_"+IntegerToString((int)_Period)+"_1_"+rail;
  }

string RuntimeSwitchKey(const string item)
  {
   return "NCF70_"+IntegerToString((long)ChartID())+"_"+item;
  }

void SaveOffsets()
  {
   GlobalVariableSet(OffsetKey("0"),gKamaUpOffset);
   GlobalVariableSet(OffsetKey("1"),gKamaDownOffset);
   GlobalVariableSet(RuntimeSwitchKey("TRACK4_UP_OFFSET"),gTrack4UpperOffset);
   GlobalVariableSet(RuntimeSwitchKey("TRACK4_DN_OFFSET"),gTrack4LowerOffset);
  }

void LoadOffsets()
  {
   if(GlobalVariableCheck(OffsetKey("0"))) gKamaUpOffset=GlobalVariableGet(OffsetKey("0"));
   if(GlobalVariableCheck(OffsetKey("1"))) gKamaDownOffset=GlobalVariableGet(OffsetKey("1"));
  }

void SaveRuntimeSwitches()
  {
   for(int i=0;i<4;i++)
      GlobalVariableSet(RuntimeSwitchKey("RAIL"+IntegerToString(i)),gLiteRailVisible[i]?1.0:0.0);
   GlobalVariableSet(RuntimeSwitchKey("STATS"),gStatsEnabled?1.0:0.0);
   GlobalVariableSet(RuntimeSwitchKey("TOUCHFILTER"),gTouchSpacingFilter?1.0:0.0);
  }

void RestoreRuntimeSwitches()
  {
   string key;
   for(int i=0;i<4;i++)
     {
      key=RuntimeSwitchKey("RAIL"+IntegerToString(i));
      if(GlobalVariableCheck(key)) gLiteRailVisible[i]=(GlobalVariableGet(key)>0.5);
     }
   key=RuntimeSwitchKey("STATS");
   if(GlobalVariableCheck(key)) gStatsEnabled=(GlobalVariableGet(key)>0.5);
   key=RuntimeSwitchKey("TOUCHFILTER");
   if(GlobalVariableCheck(key)) gTouchSpacingFilter=(GlobalVariableGet(key)>0.5);
   key=RuntimeSwitchKey("TRACK4_UP_OFFSET");
   if(GlobalVariableCheck(key)) gTrack4UpperOffset=GlobalVariableGet(key);
   key=RuntimeSwitchKey("TRACK4_DN_OFFSET");
   if(GlobalVariableCheck(key)) gTrack4LowerOffset=GlobalVariableGet(key);
  }

//+------------------------------------------------------------------+
//| 轨道显隐                                                          |
//+------------------------------------------------------------------+
void ApplyPlotVisibility()
  {
   PlotIndexSetInteger(0,PLOT_DRAW_TYPE,gLiteRailVisible[0] ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(1,PLOT_DRAW_TYPE,gLiteRailVisible[1] ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(2,PLOT_DRAW_TYPE,gLiteRailVisible[2] ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(3,PLOT_DRAW_TYPE,gLiteRailVisible[3] ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(4,PLOT_DRAW_TYPE,DRAW_ARROW);
   PlotIndexSetInteger(5,PLOT_DRAW_TYPE,DRAW_ARROW);
   ChartRedraw(0);
  }

string LiteRailButtonName(const int index)
  {
   return UI_PREFIX+"LITE_RAIL_"+IntegerToString(index);
  }

void UpdateLiteRailButtons()
  {
   for(int i=0;i<4;i++)
     {
      string name=LiteRailButtonName(i);
      if(ObjectFind(0,name)<0) continue;
      ObjectSetString(0,name,OBJPROP_TEXT,gRailLabels[i]+(gLiteRailVisible[i]?" [显示]":" [隐藏]"));
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,gLiteRailVisible[i] ? C'35,95,75' : C'65,65,65');
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,gLiteRailVisible[i] ? clrLimeGreen : clrDimGray);
      ObjectSetInteger(0,name,OBJPROP_STATE,false);
     }
  }

void CreateLiteRailButtons()
  {
   for(int i=0;i<4;i++)
     {
      string name=LiteRailButtonName(i);
      if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
      ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,12+134*i);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,Y_RAIL_BUTTONS);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,128);
      ObjectSetInteger(0,name,OBJPROP_YSIZE,22);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
      ObjectSetString(0,name,OBJPROP_FONT,"Microsoft YaHei UI");
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
      ObjectSetInteger(0,name,OBJPROP_STATE,false);
     }
   UpdateLiteRailButtons();
  }

//+------------------------------------------------------------------+
//| 统计开关与触轨过滤开关（两枚按钮分两行摆放，避免互相遮挡）          |
//+------------------------------------------------------------------+
string StatsToggleButtonName() { return UI_PREFIX+"STATS_TOGGLE"; }
string TouchFilterButtonName() { return UI_PREFIX+"TOUCH_FILTER"; }

void UpdateStatsToggleButton()
  {
   string name=StatsToggleButtonName();
   if(ObjectFind(0,name)<0) return;
   ObjectSetString(0,name,OBJPROP_TEXT,gStatsEnabled?"统计面板与统计计算：[开]":"统计面板与统计计算：[关]");
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,gStatsEnabled?clrDarkGreen:clrDimGray);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrSilver);
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
  }

void CreateStatsToggleButton()
  {
   string name=StatsToggleButtonName();
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,8);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,Y_STATS_TOGGLE);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,224);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,24);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetString(0,name,OBJPROP_FONT,"Microsoft YaHei UI");
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
   UpdateStatsToggleButton();
  }

void RefreshTouchFilterButton()
  {
   string name=TouchFilterButtonName();
   if(ObjectFind(0,name)<0) return;
   ObjectSetString(0,name,OBJPROP_TEXT,(gTouchSpacingFilter ? "三根K线限一个触点：[开]" : "三根K线限一个触点：[关]"));
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,(gTouchSpacingFilter ? clrDarkGreen : clrDimGray));
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
  }

void CreateTouchFilterButton()
  {
   string name=TouchFilterButtonName();
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
   ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,8);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,Y_TOUCH_FILTER);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,224);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,24);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
   ObjectSetString(0,name,OBJPROP_FONT,"Microsoft YaHei UI");
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrSilver);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,(gTouchSpacingFilter ? clrDarkGreen : clrDimGray));
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
   RefreshTouchFilterButton();
  }

//+------------------------------------------------------------------+
//| KAMA参考轨偏移按钮                                                 |
//+------------------------------------------------------------------+
string KamaOffsetButtonName(const int n) { return UI_PREFIX+"KOFF_"+IntegerToString(n); }

string KamaOffsetText(const int n)
  {
   int row=n/3,action=n%3;
   if(action==0) return "-";
   if(action==2) return "+";
   double value=(row==0 ? gKamaUpOffset : gKamaDownOffset);
   return (row==0 ? "KAMA参考上轨 " : "KAMA参考下轨 ")+DoubleToString(value,2);
  }

void UpdateKamaOffsetButtons()
  {
   for(int n=0;n<6;n++)
     {
      string name=KamaOffsetButtonName(n);
      if(ObjectFind(0,name)<0) continue;
      ObjectSetString(0,name,OBJPROP_TEXT,KamaOffsetText(n));
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,(n%3==1 ? C'45,65,90' : C'55,75,95'));
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrSteelBlue);
      ObjectSetInteger(0,name,OBJPROP_STATE,false);
     }
  }

void CreateKamaOffsetButtons()
  {
   for(int n=0;n<6;n++)
     {
      int row=n/3,action=n%3;
      string name=KamaOffsetButtonName(n);
      if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
      ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,(action==0 ? 12 : (action==1 ? 48 : 190)));
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,Y_KAMA_OFFSET+row*25);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,(action==1 ? 138 : 32));
      ObjectSetInteger(0,name,OBJPROP_YSIZE,22);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
      ObjectSetInteger(0,name,OBJPROP_STATE,false);
     }
   UpdateKamaOffsetButtons();
  }

//+------------------------------------------------------------------+
//| 融合轨4偏移按钮                                                    |
//+------------------------------------------------------------------+
string Track4OffsetButtonName(const int rail,const int part)
  {
   return UI_PREFIX+"T4_"+gT4Rail[rail]+"_"+gT4Part[part];
  }

double Track4OffsetValue(const int rail)
  {
   return (rail==0 ? gTrack4UpperOffset : gTrack4LowerOffset);
  }

void SetTrack4OffsetValue(const int rail,const double value)
  {
   if(rail==0) gTrack4UpperOffset=NormalizeDouble(value,2);
   else        gTrack4LowerOffset=NormalizeDouble(value,2);
  }

void UpdateTrack4OffsetButtons()
  {
   for(int r=0;r<2;r++)
     {
      // 固定带符号两位小数，避免数值变化时按钮文字宽度跳动
      string labels[3]={"-",(r==0?"融合轨4上轨 ":"融合轨4下轨 ")+StringFormat("%+.2f",Track4OffsetValue(r)),"+"};
      for(int i=0;i<3;i++)
        {
         string name=Track4OffsetButtonName(r,i);
         if(ObjectFind(0,name)<0) continue;
         ObjectSetString(0,name,OBJPROP_TEXT,labels[i]);
         ObjectSetInteger(0,name,OBJPROP_BGCOLOR,(i==1 ? C'45,65,90' : C'55,75,95'));
         ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
         ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrWhite);
         ObjectSetInteger(0,name,OBJPROP_STATE,false);
        }
     }
  }

void CreateTrack4OffsetButtons()
  {
   for(int r=0;r<2;r++)
     {
      int xs[3]={12,48,190};
      int ws[3]={32,138,32};
      for(int i=0;i<3;i++)
        {
         string name=Track4OffsetButtonName(r,i);
         if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
         ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
         ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,name,OBJPROP_XDISTANCE,xs[i]);
         ObjectSetInteger(0,name,OBJPROP_YDISTANCE,Y_TRACK4_OFFSET+r*25);
         ObjectSetInteger(0,name,OBJPROP_XSIZE,ws[i]);
         ObjectSetInteger(0,name,OBJPROP_YSIZE,22);
         ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
         ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
         ObjectSetInteger(0,name,OBJPROP_STATE,false);
        }
     }
   UpdateTrack4OffsetButtons();
  }

//+------------------------------------------------------------------+
//| 统计面板                                                          |
//+------------------------------------------------------------------+
string StatsObjectName(const int row) { return UI_PREFIX+"STATS_"+IntegerToString(row); }
string StatsBackgroundName()          { return UI_PREFIX+"STATS_BG"; }

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

void DeleteStatsPanelObjects()
  {
   string bg=StatsBackgroundName();
   if(ObjectFind(0,bg)>=0) ObjectDelete(0,bg);
   for(int i=0;i<STATS_LINE_COUNT;i++)
     {
      string n=StatsObjectName(i);
      if(ObjectFind(0,n)>=0) ObjectDelete(0,n);
     }
  }

void SetStatsLine(const int row,const string text,const color clr=clrWhite)
  {
   string name=StatsObjectName(row);
   if(ObjectFind(0,name)<0) return;
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
  }

//+------------------------------------------------------------------+
//| 亏损连线                                                          |
//+------------------------------------------------------------------+
void ClearLossTradeLines()
  {
   string prefix=UI_PREFIX+"LOSSLINE_";
   for(int obj=ObjectsTotal(0,-1,-1)-1;obj>=0;obj--)
     {
      string objName=ObjectName(0,obj,-1,-1);
      if(StringFind(objName,prefix)==0) ObjectDelete(0,objName);
     }
  }

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

//+------------------------------------------------------------------+
//| 触轨箭头                                                          |
//+------------------------------------------------------------------+
void UpdateTouchArrowsOnly(const int rates_total,const double &high[],const double &low[])
  {
   if(rates_total<3) return;
   ArrayInitialize(SellTouchArrow,EMPTY_VALUE);
   ArrayInitialize(BuyTouchArrow,EMPTY_VALUE);
   int lastAcceptedTouchIndex=-1,lastAcceptedTouchDirection=0;
   for(int i=rates_total-1;i>=0;i--)
     {
      if(Composite4Upper[i]==EMPTY_VALUE || Composite4Lower[i]==EMPTY_VALUE ||
         !MathIsValidNumber(Composite4Upper[i]) || !MathIsValidNumber(Composite4Lower[i])) continue;
      bool upper=BarTouchedUpper(i,high),lower=BarTouchedLower(i,low);
      if(!upper && !lower) continue;
      int direction=(lower&&!upper?1:(upper&&!lower?-1:0));
      bool opposite=(direction!=0 && lastAcceptedTouchDirection!=0 && direction!=lastAcceptedTouchDirection);
      if(gTouchSpacingFilter && !opposite && direction!=0 && lastAcceptedTouchIndex>=0 &&
         (lastAcceptedTouchIndex-i)<3 && direction==lastAcceptedTouchDirection) continue;
      if(upper) SellTouchArrow[i]=TouchPriceForDirection(-1,i);
      if(lower) BuyTouchArrow[i]=TouchPriceForDirection(1,i);
      lastAcceptedTouchIndex=i;
      lastAcceptedTouchDirection=direction;
     }
  }

//+------------------------------------------------------------------+
//| 触轨箭头 + 统计：最近10个交易日                                    |
//+------------------------------------------------------------------+
void UpdateTouchArrowsAndStats(const int rates_total,const datetime &time[],const double &high[],const double &low[],const double &close[])
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
   int lastAcceptedTouchDirection=0;
   for(int i=rates_total-1;i>=0;i--)
     {
      if(Composite4Upper[i]==EMPTY_VALUE || Composite4Lower[i]==EMPTY_VALUE ||
         !MathIsValidNumber(Composite4Upper[i]) || !MathIsValidNumber(Composite4Lower[i]))
         continue;
      bool touchUpper=BarTouchedUpper(i,high);
      bool touchLower=BarTouchedLower(i,low);
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

      if(touchUpper) SellTouchArrow[i]=TouchPriceForDirection(-1,i);
      if(touchLower) BuyTouchArrow[i]=TouchPriceForDirection(1,i);
     }

   // 取最近10个交易日的日期桶，包含正在形成的当天。
   string dayKeys[10];
   int dayCount=0;
   string previous="";
   for(int i=0;i<rates_total && dayCount<10;i++)
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

   ClearLossTradeLines();

   // 持仓篮子统计：同方向每次合格触点都新增一笔；反向触点到来时，所有同向仓位统一在该信号价平仓。
   double activeEntryPrices[];
   datetime activeEntryTimes[];
   ArrayResize(activeEntryPrices,rates_total);
   ArrayResize(activeEntryTimes,rates_total);
   int activeCount=0;
   int activeDirection=0;
   double activeEntryPriceSum=0.0;

   for(int i=rates_total-1;i>=0;i--)
     {
      // 每根K线按收盘价估算仍未平仓篮子的浮动盈亏，记录最深浮亏；该值是历史K线近似值。
      if(activeCount>0)
        {
         double floatingPoints=(activeDirection==1
                                ? (activeCount*close[i]-activeEntryPriceSum)
                                : (activeEntryPriceSum-activeCount*close[i]))*InpStatsPointValue;
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
         activeEntryPrices[0]=TouchPriceForDirection(direction,i);
         activeEntryTimes[0]=time[i];
         activeEntryPriceSum=activeEntryPrices[0];
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
         activeEntryPrices[activeCount]=TouchPriceForDirection(direction,i);
         activeEntryTimes[activeCount]=time[i];
         activeEntryPriceSum+=activeEntryPrices[activeCount];
         activeCount++;
         if(activeCount>maxSimultaneousPositions)
           { maxSimultaneousPositions=activeCount; maxPositionsDates=StatsDateTimeKey(time[i]); }
         else if(activeCount==maxSimultaneousPositions && maxSimultaneousPositions>0)
           { string pd2=StatsDateTimeKey(time[i]); if(StringFind("|"+maxPositionsDates+"|","|"+pd2+"|")<0) maxPositionsDates+="、"+pd2; }
         continue;
        }

      // 反向触点：篮子中每笔仓位统一在反向轨道接触价平仓。
      string exitKey=StatsDateKey(time[i]);
      int d=FindStatsDay(exitKey,dayKeys,dayCount);
      double exitTouchPrice=TouchPriceForDirection(direction,i);
      for(int p=0;p<activeCount;p++)
        {
         double points=(activeDirection==1 ? (exitTouchPrice-activeEntryPrices[p]) : (activeEntryPrices[p]-exitTouchPrice))*InpStatsPointValue;
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
      activeEntryPrices[0]=TouchPriceForDirection(direction,i);
      activeEntryTimes[0]=time[i];
      activeEntryPriceSum=activeEntryPrices[0];
     }

   SetStatsLine(0,"NMNX 双轨触轨统计 | 最近10个交易日 | 价格波动1.00="+DoubleToString(InpStatsPointValue,1)+"点",clrAqua);
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

int FindStatsDay(const string key,const string &keys[],const int count)
  {
   for(int i=0;i<count;i++) if(keys[i]==key) return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| 融合轨4：单根K线计算                                              |
//| 综合动能负责方向/能量，ADX负责趋势强度，ATR负责价格尺度。           |
//| 递归驱离只读取更旧的 i+1 状态；按钮调整不调用本函数，只应用缓存偏移。 |
//+------------------------------------------------------------------+
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
//| 偏移增量应用                                                      |
//| 只把"新偏移-已烘焙偏移"的差值加到已经画出的点上，做纯竖向平移。       |
//| 不重建整段历史、不重新索引，因此不会让轨道在时间轴上左右错位。       |
//+------------------------------------------------------------------+
void ShiftKamaWidthOffset()
  {
   int total=(int)MathMin(gCachedRatesTotal,ArraySize(FastKAMAWidthUpper));
   double deltaUp=gKamaUpOffset-gAppliedKamaUp;
   double deltaDown=gKamaDownOffset-gAppliedKamaDown;
   if(total<=0 || (deltaUp==0.0 && deltaDown==0.0)) return;
   for(int i=0;i<total;i++)
     {
      if(deltaUp!=0.0 && FastKAMAWidthUpper[i]!=EMPTY_VALUE && MathIsValidNumber(FastKAMAWidthUpper[i]))
         FastKAMAWidthUpper[i]+=deltaUp;
      if(deltaDown!=0.0 && FastKAMAWidthLower[i]!=EMPTY_VALUE && MathIsValidNumber(FastKAMAWidthLower[i]))
         FastKAMAWidthLower[i]+=deltaDown;
     }
   gAppliedKamaUp=gKamaUpOffset;
   gAppliedKamaDown=gKamaDownOffset;
   ChartRedraw(0);
  }

void ShiftTrack4Offset()
  {
   int total=(int)MathMin(gCachedRatesTotal,ArraySize(Composite4Upper));
   double deltaUp=gTrack4UpperOffset-gAppliedTrack4Up;
   double deltaDown=gTrack4LowerOffset-gAppliedTrack4Down;
   if(total<=0 || (deltaUp==0.0 && deltaDown==0.0)) return;
   for(int i=0;i<total;i++)
     {
      if(deltaUp!=0.0 && Composite4Upper[i]!=EMPTY_VALUE && MathIsValidNumber(Composite4Upper[i]))
         Composite4Upper[i]+=deltaUp;
      if(deltaDown!=0.0 && Composite4Lower[i]!=EMPTY_VALUE && MathIsValidNumber(Composite4Lower[i]))
         Composite4Lower[i]+=deltaDown;
     }
   gAppliedTrack4Up=gTrack4UpperOffset;
   gAppliedTrack4Down=gTrack4LowerOffset;
   ChartRedraw(0);
  }

// 偏移后立即重算触轨箭头与统计，不必等到下一个报价
void RefreshSignalsNow()
  {
   int total=(int)MathMin(gCachedRatesTotal,Bars(_Symbol,_Period));
   if(total<3) return;
   datetime t[];
   double h[],l[],c[];
   if(CopyTime(_Symbol,_Period,0,total,t)<total) return;
   if(CopyHigh(_Symbol,_Period,0,total,h)<total) return;
   if(CopyLow(_Symbol,_Period,0,total,l)<total) return;
   if(CopyClose(_Symbol,_Period,0,total,c)<total) return;
   ArraySetAsSeries(t,true);
   ArraySetAsSeries(h,true);
   ArraySetAsSeries(l,true);
   ArraySetAsSeries(c,true);
   if(gStatsEnabled) UpdateTouchArrowsAndStats(total,t,h,l,c);
   else              UpdateTouchArrowsOnly(total,h,l);
   gStatsDirty=false;
   gArrowDirty=false;
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| 对象清理                                                          |
//+------------------------------------------------------------------+
void DeleteAllOwnedObjects()
  {
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string name=ObjectName(0,i,-1,-1);
      if(StringFind(name,UI_PREFIX)==0) ObjectDelete(0,name);
     }
  }

//+------------------------------------------------------------------+
//| 初始化                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpFastEMA_Period<1 || InpKAMA_ER_Period<1 || InpKAMA_Fast_Period<1 || InpKAMA_Slow_Period<2 ||
      InpATR_Period<1 || InpResidual_Period<1 || InpATR_Min_Multiplier<0.0 ||
      InpResidual_Multiplier<0.0 || InpKAMA_Width_Mult<=0.0 || InpFast_KAMAWidth_Scale<=0.0)
     {
      Print("轻量版-大范围：参数无效，请检查输入参数。");
      return INIT_PARAMETERS_INCORRECT;
     }

   RestoreRuntimeSwitches();
   LoadOffsets();

   SetIndexBuffer(0,FastKAMAWidthUpper,INDICATOR_DATA);
   SetIndexBuffer(1,FastKAMAWidthLower,INDICATOR_DATA);
   SetIndexBuffer(2,Composite4Upper,INDICATOR_DATA);
   SetIndexBuffer(3,Composite4Lower,INDICATOR_DATA);
   SetIndexBuffer(4,SellTouchArrow,INDICATOR_DATA);
   SetIndexBuffer(5,BuyTouchArrow,INDICATOR_DATA);

   ArraySetAsSeries(FastKAMAWidthUpper,true);
   ArraySetAsSeries(FastKAMAWidthLower,true);
   ArraySetAsSeries(Composite4Upper,true);
   ArraySetAsSeries(Composite4Lower,true);
   ArraySetAsSeries(SellTouchArrow,true);
   ArraySetAsSeries(BuyTouchArrow,true);

   for(int p=0;p<6;p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(4,PLOT_ARROW,234); // 向下箭头
   PlotIndexSetInteger(5,PLOT_ARROW,233); // 向上箭头

   ApplyPlotVisibility();

   // EA后台核心模式：不创建按钮、统计面板或其他图表对象。
   gTrack4MACDHandle=iMACD(_Symbol,_Period,InpTrack4_MACD_Fast,InpTrack4_MACD_Slow,InpTrack4_MACD_Signal,PRICE_CLOSE);
   gTrack4RSI7Handle=iRSI(_Symbol,_Period,InpTrack4_RSI_Fast,PRICE_CLOSE);
   gTrack4RSI17Handle=iRSI(_Symbol,_Period,InpTrack4_RSI_Slow,PRICE_CLOSE);
   gTrack4WPR7Handle=iWPR(_Symbol,_Period,InpTrack4_WPR_Fast);
   gTrack4WPR14Handle=iWPR(_Symbol,_Period,InpTrack4_WPR_Slow);
   gTrack4ADXHandle=iADX(_Symbol,_Period,InpTrack4_ADX_Period);
   gTrack4KDJHandle=iStochastic(_Symbol,_Period,InpTrack4_KDJ_K,InpTrack4_KDJ_D,InpTrack4_KDJ_Slowing,MODE_SMA,STO_LOWHIGH);
   if(gTrack4MACDHandle==INVALID_HANDLE || gTrack4RSI7Handle==INVALID_HANDLE || gTrack4RSI17Handle==INVALID_HANDLE ||
      gTrack4WPR7Handle==INVALID_HANDLE || gTrack4WPR14Handle==INVALID_HANDLE ||
      gTrack4ADXHandle==INVALID_HANDLE || gTrack4KDJHandle==INVALID_HANDLE)
     {
      Print("轻量版-大范围：无法创建一个或多个动能指标句柄，检查参数与终端数据。");
      return INIT_FAILED;
     }

   IndicatorSetString(INDICATOR_SHORTNAME,"南门拈星 大范围-1 Core v1.71");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| 反初始化                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   SaveOffsets();
   SaveRuntimeSwitches();
   DeleteAllOwnedObjects();
   if(gTrack4MACDHandle!=INVALID_HANDLE) IndicatorRelease(gTrack4MACDHandle);
   if(gTrack4RSI7Handle!=INVALID_HANDLE) IndicatorRelease(gTrack4RSI7Handle);
   if(gTrack4RSI17Handle!=INVALID_HANDLE) IndicatorRelease(gTrack4RSI17Handle);
   if(gTrack4WPR7Handle!=INVALID_HANDLE) IndicatorRelease(gTrack4WPR7Handle);
   if(gTrack4WPR14Handle!=INVALID_HANDLE) IndicatorRelease(gTrack4WPR14Handle);
   if(gTrack4ADXHandle!=INVALID_HANDLE) IndicatorRelease(gTrack4ADXHandle);
   if(gTrack4KDJHandle!=INVALID_HANDLE) IndicatorRelease(gTrack4KDJHandle);
  }

//+------------------------------------------------------------------+
//| 主计算                                                            |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
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
   if(rates_total<MathMax(MathMax(InpKAMA_ER_Period,InpATR_Period),InpResidual_Period)+4)
      return 0;

   bool full=(prev_calculated<=0 || prev_calculated>rates_total);
   int start=(full ? rates_total-1 : (int)MathMin(rates_total-1,rates_total-prev_calculated));
   gCachedRatesTotal=rates_total;

   // 内部数组扩容。系列数组扩容后新元素落在索引0，旧数据整体后移，与新增K线对齐。
   ArrayResize(FastLine,rates_total);      ArraySetAsSeries(FastLine,true);
   ArrayResize(KAMALine,rates_total);      ArraySetAsSeries(KAMALine,true);
   ArrayResize(KAMAUpper,rates_total);     ArraySetAsSeries(KAMAUpper,true);
   ArrayResize(KAMALower,rates_total);     ArraySetAsSeries(KAMALower,true);
   ArrayResize(Atr,rates_total);           ArraySetAsSeries(Atr,true);
   ArrayResize(Track4DriveUpper,rates_total); ArraySetAsSeries(Track4DriveUpper,true);
   ArrayResize(Track4DriveLower,rates_total); ArraySetAsSeries(Track4DriveLower,true);
   ArrayResize(Track4Energy,rates_total);     ArraySetAsSeries(Track4Energy,true);
   ArrayResize(Composite4BaseUpper,rates_total); ArraySetAsSeries(Composite4BaseUpper,true);
   ArrayResize(Composite4BaseLower,rates_total); ArraySetAsSeries(Composite4BaseLower,true);
   ArrayResize(TouchUpperFlag,rates_total);   ArraySetAsSeries(TouchUpperFlag,true);
   ArrayResize(TouchLowerFlag,rates_total);   ArraySetAsSeries(TouchLowerFlag,true);
   ArrayResize(TouchUpperPrice,rates_total);  ArraySetAsSeries(TouchUpperPrice,true);
   ArrayResize(TouchLowerPrice,rates_total);  ArraySetAsSeries(TouchLowerPrice,true);
   if(full)
     {
      // 参数或历史变化后重建触点记忆，避免旧参数下的锁定结果残留。
      ArrayInitialize(TouchUpperFlag,false);
      ArrayInitialize(TouchLowerFlag,false);
      ArrayInitialize(TouchUpperPrice,EMPTY_VALUE);
      ArrayInitialize(TouchLowerPrice,EMPTY_VALUE);
     }

   // 普通报价只读取当前计算段所需的动能数据；关闭统计时不做多余复制。
   int copyCount=(full ? rates_total : MathMin(rates_total,start+2));
   if(BarsCalculated(gTrack4MACDHandle)<copyCount || BarsCalculated(gTrack4RSI7Handle)<copyCount ||
      BarsCalculated(gTrack4RSI17Handle)<copyCount || BarsCalculated(gTrack4WPR7Handle)<copyCount ||
      BarsCalculated(gTrack4WPR14Handle)<copyCount || BarsCalculated(gTrack4KDJHandle)<copyCount ||
      BarsCalculated(gTrack4ADXHandle)<copyCount)
      return prev_calculated;

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
   bool dataReady=true;
   if(CopyBuffer(gTrack4MACDHandle,0,0,copyCount,macdMain)<copyCount) dataReady=false;
   if(CopyBuffer(gTrack4MACDHandle,1,0,copyCount,macdSignal)<copyCount) dataReady=false;
   if(CopyBuffer(gTrack4RSI7Handle,0,0,copyCount,rsi7)<copyCount) dataReady=false;
   if(CopyBuffer(gTrack4RSI17Handle,0,0,copyCount,rsi17)<copyCount) dataReady=false;
   if(CopyBuffer(gTrack4WPR7Handle,0,0,copyCount,wpr7)<copyCount) dataReady=false;
   if(CopyBuffer(gTrack4WPR14Handle,0,0,copyCount,wpr14)<copyCount) dataReady=false;
   if(CopyBuffer(gTrack4KDJHandle,0,0,copyCount,kdjK)<copyCount) dataReady=false;
   if(CopyBuffer(gTrack4KDJHandle,1,0,copyCount,kdjD)<copyCount) dataReady=false;
   if(CopyBuffer(gTrack4ADXHandle,0,0,copyCount,adx)<copyCount) dataReady=false;
   if(CopyBuffer(gTrack4ADXHandle,1,0,copyCount,plusDI)<copyCount) dataReady=false;
   if(CopyBuffer(gTrack4ADXHandle,2,0,copyCount,minusDI)<copyCount) dataReady=false;
   if(!dataReady) return prev_calculated;

   ArrayResize(Track4MACDMain,rates_total);   ArraySetAsSeries(Track4MACDMain,true);
   ArrayResize(Track4MACDSignal,rates_total); ArraySetAsSeries(Track4MACDSignal,true);
   ArrayResize(Track4RSI7,rates_total);       ArraySetAsSeries(Track4RSI7,true);
   ArrayResize(Track4RSI17,rates_total);      ArraySetAsSeries(Track4RSI17,true);
   ArrayResize(Track4WPR7,rates_total);       ArraySetAsSeries(Track4WPR7,true);
   ArrayResize(Track4WPR14,rates_total);      ArraySetAsSeries(Track4WPR14,true);
   ArrayResize(Track4K,rates_total);          ArraySetAsSeries(Track4K,true);
   ArrayResize(Track4D,rates_total);          ArraySetAsSeries(Track4D,true);
   ArrayResize(Track4ADX,rates_total);        ArraySetAsSeries(Track4ADX,true);
   ArrayResize(Track4PlusDI,rates_total);     ArraySetAsSeries(Track4PlusDI,true);
   ArrayResize(Track4MinusDI,rates_total);    ArraySetAsSeries(Track4MinusDI,true);
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

   // ===== 实时触点判定：不等K线收盘，逐个报价就地判定并锁定 =====
   UpdateLiveTouch(high[0],low[0]);

   // EA后台核心模式：跳过箭头历史扫描、盈亏统计及统计连线。
   // 四条轨道缓冲区仍由原始计算链完整计算，EA读取缓冲区0-3。
   // 缓冲区已经按当前偏移重新写过，同步"已烘焙偏移"基准，防止按钮再次叠加
   gAppliedKamaUp=gKamaUpOffset;
   gAppliedKamaDown=gKamaDownOffset;
   gAppliedTrack4Up=gTrack4UpperOffset;
   gAppliedTrack4Down=gTrack4LowerOffset;

   return rates_total;
  }

//+------------------------------------------------------------------+
//| 图表事件                                                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id!=CHARTEVENT_OBJECT_CLICK || StringFind(sparam,UI_PREFIX)!=0)
      return;

   if(sparam==StatsToggleButtonName())
     {
      gStatsEnabled=!gStatsEnabled;
      gStatsDirty=true;
      if(gStatsEnabled) CreateStatsPanel();
      else
        {
         DeleteStatsPanelObjects();
         ClearLossTradeLines();
        }
      UpdateStatsToggleButton();
      SaveRuntimeSwitches();
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      ChartRedraw(0);
      return;
     }

   if(sparam==TouchFilterButtonName())
     {
      gTouchSpacingFilter=!gTouchSpacingFilter;
      RefreshTouchFilterButton();
      SaveRuntimeSwitches();
      gStatsDirty=true;
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      ChartRedraw(0);
      return;
     }

   for(int i=0;i<4;i++)
      if(sparam==LiteRailButtonName(i))
        {
         gLiteRailVisible[i]=!gLiteRailVisible[i];
         ApplyPlotVisibility();
         UpdateLiteRailButtons();
         SaveRuntimeSwitches();
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         ChartRedraw(0);
         return;
        }

   if(StringFind(sparam,UI_PREFIX+"KOFF_")==0)
     {
      int n=(int)StringToInteger(StringSubstr(sparam,StringLen(UI_PREFIX+"KOFF_")));
      if(n>=0 && n<6 && n%3!=1)
        {
         int row=n/3;
         double delta=(n%3==0 ? -KAMA_OFFSET_STEP : KAMA_OFFSET_STEP);
         if(row==0) gKamaUpOffset=NormalizeDouble(gKamaUpOffset+delta,2);
         else       gKamaDownOffset=NormalizeDouble(gKamaDownOffset+delta,2);
         GlobalVariableSet(OffsetKey("0"),gKamaUpOffset);
         GlobalVariableSet(OffsetKey("1"),gKamaDownOffset);
         ShiftKamaWidthOffset();
         UpdateKamaOffsetButtons();
        }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      ChartRedraw(0);
      return;
     }

   for(int r=0;r<2;r++)
      for(int part=0;part<3;part++)
         if(sparam==Track4OffsetButtonName(r,part))
           {
            if(part!=1)
              {
               double value=Track4OffsetValue(r);
               value=NormalizeDouble(value+(part==0 ? -TRACK4_OFFSET_STEP : TRACK4_OFFSET_STEP),2);
               SetTrack4OffsetValue(r,value);
               SaveOffsets();
               UpdateTrack4OffsetButtons();
               // 先竖向平移轨道，再就地刷新触轨箭头与统计，箭头不会停在旧轨道上
               ShiftTrack4Offset();
               RefreshSignalsNow();
              }
            ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
            ChartRedraw(0);
            return;
           }
  }
//+------------------------------------------------------------------+
