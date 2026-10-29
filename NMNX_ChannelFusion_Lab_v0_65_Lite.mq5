//+------------------------------------------------------------------+
//| NMNX_ChannelFusion_Lab_v0_65_Lite.mq5                            |
//| 南门拈星：融合轨4轻量版，保留原版触轨统计面板与原按钮构造方式。    |
//| 仅显示四条目标轨道及触轨箭头；偏移按钮步进固定0.01。                |
//+------------------------------------------------------------------+//+------------------------------------------------------------------+
//| 中文调试备注：指标线与各轨道的定义                                 |
//|                                                                  |
//| 【五条基础分析线】                                                 |
//| 1. 快速响应线 FastLine：短周期价格平滑线，用于快速跟随价格变化。    |
//| 2. 卡尔曼线 KalmanLine：通过卡尔曼滤波估计价格状态，降低噪声。      |
//| 3. KAMA线 KAMALine：考夫曼自适应均线，依据效率系数调整平滑速度。    |
//| 4. 中位结构线 MedianLine：对局部价格结构取中位数，降低极端值影响。  |
//| 5. 融合线 FusionLine：将多条基础分析线按程序设定融合得到的参考线。  |
//|                                                                  |
//| 【五条基础通道】                                                   |
//| 每条基础通道均由对应分析线加减该线的残差波动宽度构成：              |
//| 快速通道：FastLine ± 快速线残差宽度。                              |
//| 卡尔曼通道：KalmanLine ± 卡尔曼线残差宽度。                        |
//| KAMA通道：KAMALine ± KAMA线残差宽度。                              |
//| 中位通道：MedianLine ± 中位结构线残差宽度。                        |
//| 融合通道：FusionLine ± 融合线残差宽度。                            |
//| 残差宽度由历史价格与对应分析线之间的偏差计算，具体窗口由输入参数控制。|
//|                                                                  |
//| 【实验组合通道】                                                   |
//| A 均值：五条基础通道的上轨取平均、下轨取平均。                      |
//| B 外沿比较：上轨取快速KAMA宽度通道与 A 均值上轨的较大值；           |
//|            下轨取快速KAMA宽度通道与 A 均值下轨的较小值。            |
//| KAMA宽度通道：以快速响应线为中心，按 KAMA 估计的宽度向上下展开。    |
//| C 六组平均：五条基础通道与 KAMA宽度通道的对应轨道取平均。           |
//| D 六组外沿：六组上轨取最大值、下轨取最小值，并可独立调整偏移。       |
//| E 限宽融合：本版C与D均为六组平均，混合后再按ATR限制最大半宽。  |
//| F 五线中位：五条基础通道对应的上轨、下轨分别取中位数。              |
//| 综合轨1：原始轨道使用六组通道平均上/下轨与限宽融合上/下轨计算；动态倍率读取外沿比较通道上/下轨。|
//|                                                                  |
//| 【旧算法备查区：本版不删除历史思路，只切换当前D算法】                  |
//| 旧A：五条基础通道上轨求算术平均；五条基础通道下轨求算术平均。          |
//| 旧B：上轨=max(KAMA宽度通道上轨,A上轨)；下轨=min(KAMA宽度通道下轨,A下轨)。|
//| 旧C：五条基础通道+快速线中心/KAMA宽度通道，共六组对应轨道求平均。     |
//| 旧D：上轨=max(六组上轨)，下轨=min(六组下轨)，得到最宽外包络。         |
//| 旧E：先以 blend 在C平均与D外沿间插值，再将结果限制在快速线±ATR半宽内。|
//|     上轨=min(混合上轨,快速线+最大半宽)；下轨=max(混合下轨,快速线-最大半宽)。|
//| 旧F：五条基础通道上轨排序取中位数，下轨排序取中位数。                |
//| 旧综合轨1：原始上/下轨=2*B轨-E轨；本版改为2*C轨-E轨，动态倍率来源仍为B轨。     |
//| 本版恢复D六组外沿；E使用C平均与D外沿按blend混合后再做ATR限宽。|
//| D的偏移仅用于显示，不参与E原始计算；变量名Envelope6保留。|
//|                                                                  |
//| 【综合轨1动态比值特别说明】                                         |
//| 动态比值来源于 B 外沿比较通道的上下轨：分别计算连续 N 根已收盘K线   |
//| 的轨道平均值，并与最新一根已收盘K线的轨道值比较。                   |
//| 上下轨分别计算自己的变化比值，不能使用收盘价变化率替代。             |
//| 综合轨1再以原始公式值为基础，按该比值对上轨、下轨分别加减调整量。    |
//| 具体实现见“【综合轨1动态比值计算区】”与“【综合轨1最终轨道公式区】”。  |
//+------------------------------------------------------------------+

//| NMNX_ChannelFusion_Lab_v0_60.mq5                       |
//| 南门拈星：多通道边界融合实验版                    |
//| 目的：保留五线原始通道，并新增快速线中心/KAMA宽度通道用于对照。   |
//+------------------------------------------------------------------+
#property strict
#property version   "0.652"
#property description "NMNX双轨测试版：仅显示KAMA宽度与融合轨4，触轨箭头及近10个交易日多空统计。"
#property indicator_chart_window
#property indicator_buffers 41
#property indicator_plots   41

// 1 快速响应线
#property indicator_label1  "快速响应线"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGold
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// 2 快速线上轨
#property indicator_label2  "快速线上轨"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDarkOrange
#property indicator_style2  STYLE_DASH
#property indicator_width2  1

// 3 快速线下轨
#property indicator_label3  "快速线下轨"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDarkOrange
#property indicator_style3  STYLE_DASH
#property indicator_width3  1

// 4 卡尔曼线
#property indicator_label4  "卡尔曼原线"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrDeepSkyBlue
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

// 5 卡尔曼上轨
#property indicator_label5  "卡尔曼上轨"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrSteelBlue
#property indicator_style5  STYLE_DOT
#property indicator_width5  1

// 6 卡尔曼下轨
#property indicator_label6  "卡尔曼下轨"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrSteelBlue
#property indicator_style6  STYLE_DOT
#property indicator_width6  1

// 7 KAMA线
#property indicator_label7  "KAMA自适应线"
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrLimeGreen
#property indicator_style7  STYLE_SOLID
#property indicator_width7  2

// 8 KAMA上轨
#property indicator_label8  "KAMA上轨"
#property indicator_type8   DRAW_LINE
#property indicator_color8  clrForestGreen
#property indicator_style8  STYLE_DASHDOT
#property indicator_width8  1

// 9 KAMA下轨
#property indicator_label9  "KAMA下轨"
#property indicator_type9   DRAW_LINE
#property indicator_color9  clrForestGreen
#property indicator_style9  STYLE_DASHDOT
#property indicator_width9  1

// 10 中位线
#property indicator_label10 "中位结构线"
#property indicator_type10  DRAW_LINE
#property indicator_color10 clrSilver
#property indicator_style10 STYLE_SOLID
#property indicator_width10 1

// 11 中位线上轨
#property indicator_label11 "中位线上轨"
#property indicator_type11  DRAW_LINE
#property indicator_color11 clrGray
#property indicator_style11 STYLE_DOT
#property indicator_width11 1

// 12 中位线下轨
#property indicator_label12 "中位线下轨"
#property indicator_type12  DRAW_LINE
#property indicator_color12 clrGray
#property indicator_style12 STYLE_DOT
#property indicator_width12 1

// 13 融合主线
#property indicator_label13 "五线融合主线"
#property indicator_type13  DRAW_LINE
#property indicator_color13 clrMagenta
#property indicator_style13 STYLE_SOLID
#property indicator_width13 2

// 14 融合线上轨
#property indicator_label14 "融合线上轨"
#property indicator_type14  DRAW_LINE
#property indicator_color14 clrMediumVioletRed
#property indicator_style14 STYLE_DASH
#property indicator_width14 1

// 15 融合线下轨
#property indicator_label15 "融合线下轨"
#property indicator_type15  DRAW_LINE
#property indicator_color15 clrMediumVioletRed
#property indicator_style15 STYLE_DASH
#property indicator_width15 1

// 16 快速线中心 + KAMA宽度上轨
#property indicator_label16 "快速线中心_KAMA宽度上轨"
#property indicator_type16  DRAW_LINE
#property indicator_color16 clrAqua
#property indicator_style16 STYLE_SOLID
#property indicator_width16 2

// 17 快速线中心 + KAMA宽度下轨
#property indicator_label17 "快速线中心_KAMA宽度下轨"
#property indicator_type17  DRAW_LINE
#property indicator_color17 clrAqua
#property indicator_style17 STYLE_SOLID
#property indicator_width17 2


// 18 五线平均上轨
#property indicator_label18 "五线平均上轨"
#property indicator_type18 DRAW_LINE
#property indicator_color18 clrWhite
#property indicator_style18 STYLE_DOT
#property indicator_width18 1
// 19 五线平均下轨
#property indicator_label19 "五线平均下轨"
#property indicator_type19 DRAW_LINE
#property indicator_color19 clrWhite
#property indicator_style19 STYLE_DOT
#property indicator_width19 1
// 20 新通道与五线平均取外沿上轨
#property indicator_label20 "新通道对五线均值_外沿上轨"
#property indicator_type20 DRAW_LINE
#property indicator_color20 clrYellow
#property indicator_style20 STYLE_SOLID
#property indicator_width20 2
// 21 新通道与五线平均取外沿下轨
#property indicator_label21 "新通道对五线均值_外沿下轨"
#property indicator_type21 DRAW_LINE
#property indicator_color21 clrYellow
#property indicator_style21 STYLE_SOLID
#property indicator_width21 2
// 22 六通道边界平均上轨
#property indicator_label22 "六通道边界平均上轨"
#property indicator_type22 DRAW_LINE
#property indicator_color22 clrDeepPink
#property indicator_style22 STYLE_DASH
#property indicator_width22 2
// 23 六通道边界平均下轨
#property indicator_label23 "六通道边界平均下轨"
#property indicator_type23 DRAW_LINE
#property indicator_color23 clrDeepPink
#property indicator_style23 STYLE_DASH
#property indicator_width23 2
// 24 六组平均替代轨上轨（旧缓冲区名保留）
#property indicator_label24 "六组平均替代轨上轨"
#property indicator_type24 DRAW_LINE
#property indicator_color24 clrOrangeRed
#property indicator_style24 STYLE_SOLID
#property indicator_width24 2
// 25 六组平均替代轨下轨（旧缓冲区名保留）
#property indicator_label25 "六组平均替代轨下轨"
#property indicator_type25 DRAW_LINE
#property indicator_color25 clrOrangeRed
#property indicator_style25 STYLE_SOLID
#property indicator_width25 2
// 26 限宽融合上轨
#property indicator_label26 "限宽融合上轨"
#property indicator_type26 DRAW_LINE
#property indicator_color26 clrDodgerBlue
#property indicator_style26 STYLE_SOLID
#property indicator_width26 2
// 27 限宽融合下轨
#property indicator_label27 "限宽融合下轨"
#property indicator_type27 DRAW_LINE
#property indicator_color27 clrDodgerBlue
#property indicator_style27 STYLE_SOLID
#property indicator_width27 2
// 28 五线边界中位上轨
#property indicator_label28 "五线边界中位上轨"
#property indicator_type28 DRAW_LINE
#property indicator_color28 clrViolet
#property indicator_style28 STYLE_DASHDOT
#property indicator_width28 1
// 29 五线边界中位下轨
#property indicator_label29 "五线边界中位下轨"
#property indicator_type29 DRAW_LINE
#property indicator_color29 clrViolet
#property indicator_style29 STYLE_DASHDOT
#property indicator_width29 1
// 30 综合轨1上轨
#property indicator_label30 "综合轨1上轨"
#property indicator_type30 DRAW_LINE
#property indicator_color30 clrTomato
#property indicator_style30 STYLE_SOLID
#property indicator_width30 2

// 31 综合轨1下轨
#property indicator_label31 "综合轨1下轨"
#property indicator_type31 DRAW_LINE
#property indicator_color31 clrTomato
#property indicator_style31 STYLE_SOLID
#property indicator_width31 2

// 32 融合轨2上轨：动能衰竭与极值磁吸实验
#property indicator_label32 "融合轨2上轨_动能衰竭磁吸"
#property indicator_type32 DRAW_LINE
#property indicator_color32 clrAqua
#property indicator_style32 STYLE_SOLID
#property indicator_width32 2

// 33 融合轨2下轨：动能衰竭与极值磁吸实验
#property indicator_label33 "融合轨2下轨_动能衰竭磁吸"
#property indicator_type33 DRAW_LINE
#property indicator_color33 clrAqua
#property indicator_style33 STYLE_SOLID
#property indicator_width33 2

// 34 融合轨2中线：上下轨中心，仅用于观察轨道中心漂移
#property indicator_label34 "融合轨2中线"
#property indicator_type34 DRAW_LINE
#property indicator_color34 clrWhite
#property indicator_style34 STYLE_DOT
#property indicator_width34 1

// 35 融合轨3上轨：KAMA上轨按上轨偏离系数独立调整
#property indicator_label35 "融合轨3上轨"
#property indicator_type35 DRAW_LINE
#property indicator_color35 clrMagenta
#property indicator_style35 STYLE_SOLID
#property indicator_width35 2

// 36 融合轨3下轨：KAMA下轨按下轨偏离系数独立调整
#property indicator_label36 "融合轨3下轨"
#property indicator_type36 DRAW_LINE
#property indicator_color36 clrMagenta
#property indicator_style36 STYLE_SOLID
#property indicator_width36 2

// 37 融合轨3中线：上下轨的中心参考线
#property indicator_label37 "融合轨3均线轨"
#property indicator_type37 DRAW_LINE
#property indicator_color37 clrWhite
#property indicator_style37 STYLE_DOT
#property indicator_width37 1

// 38 融合轨4上轨：综合动能驱离
#property indicator_label38 "融合轨4上轨_综合动能驱离"
#property indicator_type38 DRAW_LINE
#property indicator_color38 clrWhite
#property indicator_style38 STYLE_SOLID
#property indicator_width38 2

// 39 融合轨4下轨：综合动能驱离
#property indicator_label39 "融合轨4下轨_综合动能驱离"
#property indicator_type39 DRAW_LINE
#property indicator_color39 clrWhite
#property indicator_style39 STYLE_DASH
#property indicator_width39 2

// 40 融合轨4上轨触碰：卖出观察箭头（只对已收盘K线绘制）
#property indicator_label40 "融合轨4上轨触碰_卖出观察"
#property indicator_type40 DRAW_ARROW
#property indicator_color40 clrTomato
#property indicator_style40 STYLE_SOLID
#property indicator_width40 2

// 41 融合轨4下轨触碰：买入观察箭头（只对已收盘K线绘制）
#property indicator_label41 "融合轨4下轨触碰_买入观察"
#property indicator_type41 DRAW_ARROW
#property indicator_color41 clrLime
#property indicator_style41 STYLE_SOLID
#property indicator_width41 2

// 综合轨1动态倍率的可选档位
enum ENUM_COMPOSITE_MAX_MULTIPLIER
  {
   COMPOSITE_MAX_1_2 = 0, // 温和扩张：1.2倍
   COMPOSITE_MAX_1_5 = 1, // 适度扩张：1.5倍
   COMPOSITE_MAX_2_0 = 2  // 明显扩张：2.0倍
  };

enum ENUM_COMPOSITE_SPEED_WINDOW
  {
   COMPOSITE_SPEED_3  = 3,  // 最近3根已收盘K线
   COMPOSITE_SPEED_5  = 5,  // 最近5根已收盘K线
   COMPOSITE_SPEED_10 = 10  // 最近10根已收盘K线
  };

enum ENUM_COMPOSITE_SMOOTHING
  {
   COMPOSITE_SMOOTH_1 = 1, // 快速响应
   COMPOSITE_SMOOTH_3 = 3, // 适度平滑
   COMPOSITE_SMOOTH_5 = 5  // 更稳定
  };

input group "01 · 五条分析线：显示开关与引用开关分离"
input bool   InpShow_Fast_Line       = true;    // 显示快速响应线：只影响图表显示
input bool   InpUse_Fast_Line        = true;    // 引用快速响应线：参与融合及组合通道计算
input bool   InpShow_Kalman_Line     = true;    // 显示卡尔曼线：只影响图表显示
input bool   InpUse_Kalman_Line      = true;    // 引用卡尔曼线：参与融合及组合通道计算
input bool   InpShow_KAMA_Line       = true;    // 显示KAMA线：只影响图表显示
input bool   InpUse_KAMA_Line        = true;    // 引用KAMA线：参与融合及组合通道计算
input bool   InpShow_Median_Line     = true;    // 显示中位结构线：只影响图表显示
input bool   InpUse_Median_Line      = true;    // 引用中位结构线：参与融合及组合通道计算
input bool   InpShow_Fusion_Line     = true;    // 显示融合线：只影响图表显示
input bool   InpUse_Fusion_Line      = true;    // 引用融合线：参与组合通道计算
input int    InpFastEMA_Period       = 3;       // 快速响应线周期，建议先观察 2-5
input double InpKalman_Q_Factor      = 0.20;    // 卡尔曼过程噪声，越大通常响应越快
input double InpKalman_R_Factor      = 0.50;    // 卡尔曼测量噪声，越小通常越信任新价格
input int    InpKAMA_ER_Period       = 8;       // KAMA效率比周期
input int    InpKAMA_Fast_Period     = 2;       // KAMA快速周期
input int    InpKAMA_Slow_Period     = 20;      // KAMA慢速周期
input int    InpMedian_Period        = 5;       // 中位线窗口
input int    InpFusion_Smooth_Period = 1;       // 融合线额外平滑，1表示不额外平滑
input double InpWeight_Fast          = 0.30;    // 融合权重：快速响应线
input double InpWeight_Kalman        = 0.30;    // 融合权重：卡尔曼线
input double InpWeight_KAMA          = 0.20;    // 融合权重：KAMA线
input double InpWeight_Median        = 0.20;    // 融合权重：中位线

input group "02 · 各线独立通道"
input int    InpATR_Period           = 7;       // 波动测量周期
input int    InpResidual_Period      = 10;      // 各线残差测量周期
input double InpATR_Min_Multiplier   = 0.35;    // 通道最小半宽 = ATR × 此系数
input double InpResidual_Multiplier  = 1.00;    // 通道残差半宽系数
input double InpFast_Width_Mult      = 0.85;    // 快速线通道宽度调整
input double InpKalman_Width_Mult    = 1.00;    // 卡尔曼线通道宽度调整
input double InpKAMA_Width_Mult      = 1.00;    // KAMA线通道宽度调整
input double InpMedian_Width_Mult    = 0.90;    // 中位线通道宽度调整
input double InpFusion_Width_Mult    = 1.00;    // 融合线通道宽度调整
input bool   InpShow_Fast_Channel    = true;    // 显示快速线通道
input bool   InpShow_Kalman_Channel  = true;    // 显示卡尔曼线通道
input bool   InpShow_KAMA_Channel    = true;    // 显示KAMA线通道
input bool   InpShow_Median_Channel  = true;    // 显示中位线通道
input bool   InpShow_Fusion_Channel  = true;    // 显示融合线通道
input group "03 · 快速线借用KAMA通道宽度实验"
input bool   InpShow_Fast_KAMAWidth_Channel = true; // 显示新增对照通道
input double InpFast_KAMAWidth_Scale = 1.00;         // KAMA半通道宽度缩放：1.00为原样移植

input group "04 · 融合实验显示开关（可多选叠加）"
input bool InpShow_Avg5_Channel = false;       // A：五条线各自上下轨的算术平均
input bool InpShow_NewVsAvg_Outer = false;    // B：新通道与五线均值比较，上轨取大/下轨取小
input bool InpShow_Avg6_Channel = false;      // C：五条通道 + 新通道，共六组边界直接平均
input bool InpShow_Envelope6_Channel = false; // D：六组外沿，上轨取最大、下轨取最小
input bool InpShow_Capped_Channel = false;    // E：六组平均经混合参数后再限制最大半宽
input bool InpShow_Median5_Channel = false;   // F：五组原始通道边界分别取中位数
input double InpMaxHalfWidth_ATR = 2.50;      // 限宽实验：最大半宽=ATR×系数
input double InpCappedBlend = 0.65;           // 限宽通道向外沿靠拢比例，0=平均通道，1=完整外沿
input group "05 · 综合轨1动态倍率（可选测试档位）"
input bool InpEnableCompositeDynamicMultiplier = true; // 启用动态倍率：缓慢时收拢，快速时扩张
input ENUM_COMPOSITE_MAX_MULTIPLIER InpCompositeMaxMultiplier = COMPOSITE_MAX_1_5; // 动态调整最大比例档位
input ENUM_COMPOSITE_SPEED_WINDOW InpCompositeSpeedWindow = COMPOSITE_SPEED_5; // B轨连续N根均值窗口
input ENUM_COMPOSITE_SMOOTHING InpCompositeSmoothing = COMPOSITE_SMOOTH_3; // 动态比值平滑窗口
input int InpCompositeBaselineWindow = 20; // 长期基准速度窗口，默认20根已收盘K线

input group "07 · 融合轨4：综合动能驱离引擎"
input bool   InpEnableFusionTrack4       = true; // 启用融合轨4计算
input int    InpTrack4_MACD_Fast         = 7;    // 融合轨4 MACD快周期
input int    InpTrack4_MACD_Slow         = 14;   // 融合轨4 MACD慢周期
input int    InpTrack4_MACD_Signal       = 5;    // 融合轨4 MACD信号周期
input int    InpTrack4_RSI_Fast          = 7;    // RSI快周期
input int    InpTrack4_RSI_Slow          = 17;   // RSI慢周期
input int    InpTrack4_WPR_Fast          = 7;    // WPR快周期
input int    InpTrack4_WPR_Slow          = 14;   // WPR慢周期
input int    InpTrack4_ADX_Period        = 7;    // ADX与+DI/-DI周期
input int    InpTrack4_KDJ_K             = 5;    // KDJ的K周期
input int    InpTrack4_KDJ_D             = 3;    // KDJ的D周期
input int    InpTrack4_KDJ_Slowing       = 3;    // KDJ平滑周期
input double InpTrack4_MaxDrive_ATR       = 2.20; // 顺势外侧轨最大驱离距离：ATR倍数
input double InpTrack4_MaxLift_ATR        = 0.85; // 顺势内侧轨最大抬升/压低距离：ATR倍数
input double InpTrack4_ADX_Weak           = 14.0; // ADX低于该值时趋势贡献较弱
input double InpTrack4_ADX_Strong         = 32.0; // ADX达到该值时趋势强度归一化封顶
input double InpTrack4_ExpandSpeed        = 0.22; // 驱离扩张速度：越大越快
input double InpTrack4_RecoilSpeed        = 0.68; // 动能减弱后的回收速度：应显著快于扩张速度
input group "06 · 融合轨2：动能衰竭与极值磁吸实验"
input bool   InpEnableFusionTrack2 = true;       // 计算融合轨2；关闭后不绘制
input int    InpTrack2_ExtremeLookback = 5;       // 近期极值参考窗口，只读取当前K线之前已收盘K线
input double InpTrack2_MagnetIntensity = 0.55;   // 磁吸强度，0=不吸附，1=完全靠近近期极值
input double InpTrack2_MaxPull_ATR = 1.20;       // 单次磁吸最大位移，按ATR限制
input double InpTrack2_ADX_TrendGuard = 28.0;    // ADX高于该值时减弱磁吸，避免强趋势中提前贴顶/贴底
input int    InpTrack2_MACD_Fast = 7;             // 融合轨2动能MACD快周期
input int    InpTrack2_MACD_Slow = 14;            // 融合轨2动能MACD慢周期
input int    InpTrack2_MACD_Signal = 5;           // 融合轨2动能MACD信号周期
input int    InpTrack2_RSI_Fast = 7;              // 融合轨2短周期RSI
input int    InpTrack2_RSI_Slow = 14;             // 融合轨2长周期RSI
input int    InpTrack2_WPR_Period = 14;           // 融合轨2威廉指标周期
input int    InpTrack2_ADX_Period = 7;            // 融合轨2趋势强度ADX周期


double FastLine[], FastUpper[], FastLower[];
double KalmanLine[], KalmanUpper[], KalmanLower[];
double KAMALine[], KAMAUpper[], KAMALower[];
double MedianLine[], MedianUpper[], MedianLower[];
double FusionLine[], FusionUpper[], FusionLower[];
double FastKAMAWidthUpper[], FastKAMAWidthLower[];
double Avg5Upper[],Avg5Lower[],NewVsAvgUpper[],NewVsAvgLower[];
double Avg6Upper[],Avg6Lower[],Envelope6Upper[],Envelope6Lower[];
double CappedUpper[],CappedLower[],Median5Upper[],Median5Lower[];
double Composite1Upper[],Composite1Lower[];
double Composite2Upper[],Composite2Lower[],Composite2Middle[];
double Composite3Upper[],Composite3Lower[],Composite3Middle[];
double Composite4Upper[],Composite4Lower[];
double SellTouchArrow[],BuyTouchArrow[];
double Composite3BaseUpper[],Composite3BaseLower[]; // 融合轨3无人工偏移的基准轨，用于按钮轻量重建
double Composite4BaseUpper[],Composite4BaseLower[]; // 融合轨4动态引擎输出的基准轨，不含人工偏移
double Track4DriveUpper[],Track4DriveLower[],Track4Energy[]; // 融合轨4递归驱离记忆
double Track2MACDMain[],Track2MACDSignal[],Track2RSI7[],Track2RSI14[],Track2WPR[],Track2ADX[],Track2PlusDI[],Track2MinusDI[];
double Track4MACDMain[],Track4MACDSignal[],Track4RSI7[],Track4RSI17[];
double Track4WPR7[],Track4WPR14[],Track4K[],Track4D[],Track4ADX[],Track4PlusDI[],Track4MinusDI[];
int gTrack2MACDHandle=INVALID_HANDLE,gTrack2RSI7Handle=INVALID_HANDLE,gTrack2RSI14Handle=INVALID_HANDLE;
int gTrack2WPRHandle=INVALID_HANDLE,gTrack2ADXHandle=INVALID_HANDLE;
int gTrack4MACDHandle=INVALID_HANDLE,gTrack4RSI7Handle=INVALID_HANDLE,gTrack4RSI17Handle=INVALID_HANDLE;
int gTrack4WPR7Handle=INVALID_HANDLE,gTrack4WPR14Handle=INVALID_HANDLE,gTrack4ADXHandle=INVALID_HANDLE,gTrack4KDJHandle=INVALID_HANDLE;

double Atr[], KalmanP[], FusionRaw[];
double CompositeDynamicKUpper[], CompositeDynamicKLower[]; // 综合轨1上下轨独立动态倍率缓存

//====================================================================
// 【综合轨1动态比值计算区】
// 比值来源：B「外沿比较」通道，不使用收盘价涨跌幅。
// 对上轨、下轨分别计算：
// 1. 取连续 N 根已收盘K线的 B 轨道值平均值；
// 2. 取最新一根已收盘K线的 B 轨道值；
// 3. 计算相对变化幅度 = abs(最新值 - 平均值) / abs(平均值)；
// 4. 将变化幅度映射到有限的倍率调整区间，避免异常值导致轨道爆开。
// 这里的 N 就是“短期变化速度窗口”选项：3、5、10 根。
//====================================================================
double CompositeMaxMultiplierValue()
  {
   if(InpCompositeMaxMultiplier==COMPOSITE_MAX_1_2) return 1.2;
   if(InpCompositeMaxMultiplier==COMPOSITE_MAX_2_0) return 2.0;
   return 1.5;
  }

int CompositeSpeedWindowValue()
  {
   return (int)InpCompositeSpeedWindow;
  }

int CompositeSmoothingValue()
  {
   return (int)InpCompositeSmoothing;
  }

//【算法逐行备注：动态倍率的输入变化率】
// 本函数计算 B 外沿比较通道某一条轨道的变化率；不直接计算价格涨跌幅。
// 参数 i：当前正在计算的指标缓冲区索引；MT5 序列数组通常以 0 表示最新K线。
// 参数 total：当前可用K线总数，用来防止访问数组范围之外的数据。
// 参数 channelUpper：true 表示读取“快速线中心KAMA宽度通道与五条基础通道上轨均值比较后形成的外沿比较通道”的上轨 NewVsAvgUpper；false 表示读取该外沿比较通道的下轨 NewVsAvgLower。
double CompositeRailRatioAt(const int i,const int total,const bool channelUpper)
  {
   int n=MathMax(1,CompositeSpeedWindowValue()); // 读取输入参数 InpCompositeSpeedWindow；至少取1根K线，作为比较均值窗口长度。
   double sum=0.0;                               // 累加窗口内有效的 B 通道轨道值，初始为0。
   int count=0;                                  // 统计实际参与均值计算的有效数据数量，避免 EMPTY_VALUE 被纳入平均值。

   // i 是当前要计算的索引；从 i+1 开始取数据，尽量只用已收盘K线，避免当前K线盘中变化直接影响结果。
   for(int j=i+1;j<i+1+n && j<total;j++)          // 从下一根K线开始，最多检查 n 根，并确保 j 不超过 total。
     {
      double v=channelUpper ? NewVsAvgUpper[j] : NewVsAvgLower[j]; // 按 channelUpper 选择“外沿比较通道上轨 NewVsAvgUpper”或“外沿比较通道下轨 NewVsAvgLower”的第 j 根数值；该通道上轨取快速线中心KAMA宽度通道上轨与五条基础通道上轨均值的较大值，下轨取两者下轨的较小值。
      if(v!=EMPTY_VALUE && MathIsValidNumber(v)) // 只有非空且为有效数值的数据才参与统计。
        {
         sum+=v;                                 // 把本根 B 通道轨道值加入累加和。
         count++;                                // 有效数据计数加1。
        }
     }
   if(count<=0) return 0.0;                      // 如果窗口里没有有效值，返回0变化率，避免除以0。

   double avg=sum/count;                         // 计算最近有效窗口内“外沿比较通道上轨 NewVsAvgUpper”或“外沿比较通道下轨 NewVsAvgLower”的算术平均值。
   int latest=i+1;                               // 指定用于比较的“最新已收盘K线”索引，不直接使用当前索引 i。
   if(latest>=total) return 0.0;                 // 如果下一根K线超出历史数据范围，无法比较，返回0。
   double latestValue=channelUpper ? NewVsAvgUpper[latest] : NewVsAvgLower[latest]; // 读取最新已收盘K线上的“外沿比较通道上轨 NewVsAvgUpper”或“外沿比较通道下轨 NewVsAvgLower”数值。
   double denom=MathMax(MathAbs(avg),_Point);    // 以均值绝对值作为分母；若均值过小，则至少使用一个最小报价单位 _Point，防止分母为0。
   return MathAbs(latestValue-avg)/denom;        // 返回“最新已收盘K线的外沿比较通道对应轨道值与该轨道窗口均值之差的绝对值 ÷ 该轨道窗口均值的绝对值”；这是相对变化率，不是 ATR 标准化速度。
  }

//【算法逐行备注：把变化率换算成综合轨1的动态倍率】
// 注意：此倍率只影响综合轨1最终上下轨的扩张/收缩项，不改变 C、E 通道自身的计算。
// 输入参数 InpEnableCompositeDynamicMultiplier：动态倍率总开关；关闭时直接返回固定倍率1.0。
// 输入参数 InpCompositeMaxMultiplier：用户设定的倍率上限，具体取值由 CompositeMaxMultiplierValue() 读取。
// 输入参数 InpCompositeSmoothing：对多少个相邻计算索引的变化率进行平均；最少为1。
// 当前算法的关键阈值是固定的 0.02，即相对变化率达到2%时，归一化值封顶为1。
// 低变化区倍率下限固定为0.20；因此该算法的倍率范围为 0.20 至用户设定的最大倍率。
double CalculateCompositeRailMultiplier(const int i,const int total,const bool channelUpper)
  {
   if(!gDynamicMultiplierEnabled) return 1.0; // 若用户关闭动态倍率，直接使用1.0，不再执行后续变化率计算。

   double maxK=CompositeMaxMultiplierValue();            // 读取用户设定的动态倍率上限，限制极速行情下倍率的最大值。
   int smoothN=MathMax(1,CompositeSmoothingValue());     // 读取 InpCompositeSmoothing，并保证平滑样本数至少为1。
   double ratioSum=0.0;                                  // 累加后续各样本的相对变化率。
   int ratioCount=0;                                     // 记录成功取得的变化率样本数。

   for(int s=0;s<smoothN;s++)                            // 按平滑样本数逐个取变化率，降低单个样本突变对倍率的影响。
     {
      int idx=i+s;                                       // 当前样本索引；每次循环向历史方向移动一个指标索引。
      if(idx>=total) break;                              // 超出可用K线总数后停止循环，避免越界访问。
      double ratio=CompositeRailRatioAt(idx,total,channelUpper); // 计算该样本中“外沿比较通道上轨 NewVsAvgUpper”或“外沿比较通道下轨 NewVsAvgLower”相对于自身窗口均值的变化率。
      ratioSum+=ratio;                                   // 将本次变化率加入累计和。
      ratioCount++;                                      // 成功计算一个样本，计数加1。
     }
   if(ratioCount<=0) return 1.0;                         // 没有可用样本时退回倍率1.0，避免空数据导致异常。

   double ratioAvg=ratioSum/ratioCount;                  // 计算平滑后的平均相对变化率。
   double normalized=ClampValue(ratioAvg/0.02,0.0,1.0);  // 用固定2%阈值归一化：0%映射到0，达到或超过2%映射到1；超出部分不再继续增大。
   return ClampValue(0.20+(maxK-0.20)*normalized,0.20,maxK); // 将归一化结果线性映射到[0.20,maxK]，并再次限幅确保倍率不越界。
  }

double ClampValue(const double v,const double lo,const double hi)
{
   return MathMax(lo,MathMin(hi,v));
}

double MedianAt(const int i,const int period,const int total,
                const double &high[],const double &low[])
{
   int n=MathMax(1,MathMin(period,total-i));
   double values[];
   ArrayResize(values,n);
   for(int j=0;j<n;j++)
      values[j]=(high[i+j]+low[i+j])*0.5;

   // 插入排序，窗口较小，足够用于观察版
   for(int a=1;a<n;a++)
   {
      double key=values[a];
      int b=a-1;
      while(b>=0 && values[b]>key)
      {
         values[b+1]=values[b];
         b--;
      }
      values[b+1]=key;
   }
   if((n%2)==1)
      return values[n/2];
   return (values[n/2-1]+values[n/2])*0.5;
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

//==================== 盘面快捷开关 ====================
#define UI_PREFIX "NMNX_CF30_"
#define UI_BUTTON_COUNT 16
#define LINE_SWITCH_COUNT 10
#define OFFSET_BUTTON_COUNT 30
#define OFFSET_STEP 0.1
#define TRACK3_OFFSET_STEP 0.1
#define TRACK4_OFFSET_STEP 0.01
#define DEBUG_PANEL_VISIBLE_ROWS 14
#define DEBUG_PANEL_ROW_HEIGHT 16
#define DEBUG_PANEL_HEIGHT 270
int gDebugPanelPage=0;
string gDebugPanelLines[];
bool gShow[UI_BUTTON_COUNT];
bool gLineVisible[5];
bool gLineUsed[5];
bool gDynamicMultiplierEnabled=true;
double gTrack3UpperOffset=0.0; // 融合轨3上轨位置偏移，正值上移
double gTrack3LowerOffset=0.0; // 融合轨3下轨位置偏移，正值上移
double gTrack4UpperOffset=0.0; // 融合轨4上轨人工偏移，正值上移
double gTrack4LowerOffset=0.0; // 融合轨4下轨人工偏移，正值上移
bool gForceFullRecalc=false;
string gLineNames[5]={"快速线","卡尔曼线","KAMA线","中位线","融合线"};
int gLinePlotIndex[5]={0,3,6,9,12};
double gUpperOffset[5]={0.0,0.0,0.0,0.0,0.0}; // B外沿比较、KAMA宽度、E限宽融合、综合轨1、D六组外沿
// 独立下轨偏移，正值代表向上移动，负值代表向下移动
double gLowerOffset[5]={0.0,0.0,0.0,0.0,0.0};
int gCachedRatesTotal=0;
bool gTouchSpacingFilter=true; // 默认开启：任意3根K线范围内最多接受一个触点
bool gLiteRailVisible[4]={true,true,true,true}; // 四条目标轨道仅控制绘制，不影响计算
string gButtonText[UI_BUTTON_COUNT] =
  {"快速通道","卡尔曼通道","KAMA通道","中位通道","融合通道",
   "KAMA宽度","A 均值","B 外沿比较","C 六组平均","D 六组外沿","E 限宽融合","F 五线中位","综合轨1","融合轨2","融合轨3","融合轨4"};
int gButtonPlotA[UI_BUTTON_COUNT]={1,4,7,10,13,15,17,19,21,23,25,27,29,31,34,37};
int gButtonPlotB[UI_BUTTON_COUNT]={2,5,8,11,14,16,18,20,22,24,26,28,30,32,35,38};

void ApplyPlotVisibility()
  {
   // 轻量版固定只绘制四条目标轨道和原版触轨箭头。
   // 轨道显示开关只切换绘图类型，不改变基础数组、动能递归或统计计算。
   for(int p=0;p<41;p++)
      PlotIndexSetInteger(p,PLOT_DRAW_TYPE,DRAW_NONE);
   PlotIndexSetInteger(15,PLOT_DRAW_TYPE,gLiteRailVisible[0] ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(16,PLOT_DRAW_TYPE,gLiteRailVisible[1] ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(37,PLOT_DRAW_TYPE,gLiteRailVisible[2] ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(38,PLOT_DRAW_TYPE,gLiteRailVisible[3] ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(39,PLOT_DRAW_TYPE,DRAW_ARROW);
   PlotIndexSetInteger(40,PLOT_DRAW_TYPE,DRAW_ARROW);
   ChartRedraw(0);
  }

string LineSwitchName(const int line,const bool useSwitch)
  {
   return UI_PREFIX+"LINE_"+(useSwitch?"U_":"S_")+IntegerToString(line);
  }

void UpdateLineSwitchLook(const int line,const bool useSwitch)
  {
   if(line<0 || line>=5) return;
   string name=LineSwitchName(line,useSwitch);
   if(ObjectFind(0,name)<0) return;
   bool enabled=(useSwitch ? gLineUsed[line] : gLineVisible[line]);
   // 盘面按钮必须明确区分“是否绘制”和“是否参与算法计算”。
   string suffix=(useSwitch ? " 参与计算 " : " 显示 ");
   ObjectSetString(0,name,OBJPROP_TEXT,gLineNames[line]+suffix+(enabled?"[开]":"[关]"));
   ObjectSetString(0,name,OBJPROP_TOOLTIP,
                   useSwitch
                   ? gLineNames[line]+"：开=参与融合/组合通道计算；关=计算时排除该线"
                   : gLineNames[line]+"：开=在图表绘制；关=隐藏绘图，不改变计算");
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,enabled ? C'35,95,75' : C'65,65,65');
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,enabled ? clrLimeGreen : clrDimGray);
  }

void ApplyBaseLineVisibility()
  {
   for(int i=0;i<5;i++)
      PlotIndexSetInteger(gLinePlotIndex[i],PLOT_DRAW_TYPE,gLineVisible[i] ? DRAW_LINE : DRAW_NONE);
   ChartRedraw(0);
  }

void UpdateDynamicButtonLook()
  {
   string name=UI_PREFIX+"DYNAMIC";
   if(ObjectFind(0,name)<0) return;
   ObjectSetString(0,name,OBJPROP_TEXT,StringFormat("综合轨1动态倍率 [%s]",gDynamicMultiplierEnabled?"开":"关"));
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,gDynamicMultiplierEnabled ? C'35,95,75' : C'65,65,65');
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,gDynamicMultiplierEnabled ? clrLimeGreen : clrDimGray);
  }

void CreateLineSwitchButtons()
  {
   // 每条基础分析线一行，左侧控制绘图，右侧明确控制“是否参与计算”。
   for(int line=0;line<5;line++)
     for(int sw=0;sw<2;sw++)
       {
        bool useSwitch=(sw==1);
        string name=LineSwitchName(line,useSwitch);
        if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
        ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
        ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
        ObjectSetInteger(0,name,OBJPROP_XDISTANCE,12+sw*142);
        ObjectSetInteger(0,name,OBJPROP_YDISTANCE,24+line*25);
        ObjectSetInteger(0,name,OBJPROP_XSIZE,136);
        ObjectSetInteger(0,name,OBJPROP_YSIZE,22);
        ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
        ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
        ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
        ObjectSetInteger(0,name,OBJPROP_STATE,false);
        UpdateLineSwitchLook(line,useSwitch);
       }
   string dyn=UI_PREFIX+"DYNAMIC";
   if(ObjectFind(0,dyn)>=0) ObjectDelete(0,dyn);
   ObjectCreate(0,dyn,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,dyn,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,dyn,OBJPROP_XDISTANCE,12);
   ObjectSetInteger(0,dyn,OBJPROP_YDISTANCE,153);
   ObjectSetInteger(0,dyn,OBJPROP_XSIZE,278);
   ObjectSetInteger(0,dyn,OBJPROP_YSIZE,22);
   ObjectSetInteger(0,dyn,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,dyn,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,dyn,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,dyn,OBJPROP_STATE,false);
   UpdateDynamicButtonLook();
  }

void UpdateButtonLook(const int n)
  {
   string name=UI_PREFIX+IntegerToString(n);
   if(ObjectFind(0,name)<0) return;
   ObjectSetString(0,name,OBJPROP_TEXT,gButtonText[n]+(gShow[n] ? "  [开]" : "  [关]"));
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,gShow[n] ? C'35,95,75' : C'65,65,65');
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,gShow[n] ? clrLimeGreen : clrDimGray);
  }

string OffsetGlobalKey(const int channel,const int rail)
  {
   return "NMNX_CF42_"+_Symbol+"_"+IntegerToString((int)_Period)+"_"+
          IntegerToString(channel)+"_"+IntegerToString(rail);
  }

string OffsetRowName(const int row)
  {
   int channel=row/2;
   int rail=row%2;
   string channelName=(channel==0 ? "B外沿" : (channel==1 ? "KAMA宽度" : (channel==2 ? "E限宽" : (channel==3 ? "综合轨1" : "D六组外沿"))));
   return channelName+(rail==0 ? "上轨" : "下轨");
  }

string OffsetButtonText(const int n)
  {
   int row=n/3;
   int action=n%3;
   if(action==0) return "-";
   if(action==2) return "+";
   int channel=row/2;
   int rail=row%2;
   double value=(rail==0 ? gUpperOffset[channel] : gLowerOffset[channel]);
   return OffsetRowName(row)+" "+DoubleToString(value,1);
  }

void UpdateOffsetButtonLook(const int n)
  {
   string name=UI_PREFIX+"OFF_"+IntegerToString(n);
   if(ObjectFind(0,name)<0) return;
   ObjectSetString(0,name,OBJPROP_TEXT,OffsetButtonText(n));
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,(n%3==1 ? C'45,65,90' : C'55,75,95'));
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrSteelBlue);
  }

void RefreshOffsetRow(const int row)
  {
   UpdateOffsetButtonLook(row*3);
   UpdateOffsetButtonLook(row*3+1);
   UpdateOffsetButtonLook(row*3+2);
  }

string Track3DeviationButtonName(const string rail,const string part)
  {
   return UI_PREFIX+"T3_"+rail+"_"+part;
  }

double Track3OffsetValue(const string rail)
  {
   return (rail=="UP" ? gTrack3UpperOffset : gTrack3LowerOffset);
  }

void SetTrack3OffsetValue(const string rail,const double value)
  {
   if(rail=="UP") gTrack3UpperOffset=NormalizeDouble(value,1);
   else            gTrack3LowerOffset=NormalizeDouble(value,1);
  }

void UpdateTrack3DeviationButtons()
  {
   string rails[2]={"UP","DN"};
   for(int r=0;r<2;r++)
     {
      string rail=rails[r];
      string names[3]={Track3DeviationButtonName(rail,"DEC"),Track3DeviationButtonName(rail,"VAL"),Track3DeviationButtonName(rail,"INC")};
      string title=(rail=="UP" ? "融合轨3上轨偏移" : "融合轨3下轨偏移");
      string labels[3]={"-",title+" "+DoubleToString(Track3OffsetValue(rail),1),"+"};
      for(int i=0;i<3;i++)
        {
         if(ObjectFind(0,names[i])<0) continue;
         ObjectSetString(0,names[i],OBJPROP_TEXT,labels[i]);
         ObjectSetInteger(0,names[i],OBJPROP_BGCOLOR,(i==1 ? C'45,65,90' : C'55,75,95'));
         ObjectSetInteger(0,names[i],OBJPROP_COLOR,clrWhite);
         ObjectSetInteger(0,names[i],OBJPROP_BORDER_COLOR,clrSteelBlue);
         ObjectSetInteger(0,names[i],OBJPROP_STATE,false);
        }
     }
  }

void CreateTrack3DeviationButtons()
  {
   string rails[2]={"UP","DN"};
   for(int r=0;r<2;r++)
     {
      string rail=rails[r];
      string names[3]={Track3DeviationButtonName(rail,"DEC"),Track3DeviationButtonName(rail,"VAL"),Track3DeviationButtonName(rail,"INC")};
      int xs[3]={12,48,190};
      int ws[3]={32,138,32};
      for(int i=0;i<3;i++)
        {
         if(ObjectFind(0,names[i])>=0) ObjectDelete(0,names[i]);
         ObjectCreate(0,names[i],OBJ_BUTTON,0,0,0);
         ObjectSetInteger(0,names[i],OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,names[i],OBJPROP_XDISTANCE,xs[i]);
         // D六组外沿的上下轨按钮在第9、10行；融合轨3按钮紧接其下。
         ObjectSetInteger(0,names[i],OBJPROP_YDISTANCE,635+r*25);
         ObjectSetInteger(0,names[i],OBJPROP_XSIZE,ws[i]);
         ObjectSetInteger(0,names[i],OBJPROP_YSIZE,22);
         ObjectSetInteger(0,names[i],OBJPROP_FONTSIZE,8);
         ObjectSetInteger(0,names[i],OBJPROP_HIDDEN,true);
         ObjectSetInteger(0,names[i],OBJPROP_SELECTABLE,true);
         ObjectSetInteger(0,names[i],OBJPROP_STATE,false);
        }
     }
   UpdateTrack3DeviationButtons();
  }

string Track4DeviationButtonName(const string rail,const string part)
  {
   return UI_PREFIX+"T4_"+rail+"_"+part;
  }

double Track4OffsetValue(const string rail)
  {
   return (rail=="UP" ? gTrack4UpperOffset : gTrack4LowerOffset);
  }

void SetTrack4OffsetValue(const string rail,const double value)
  {
   if(rail=="UP") gTrack4UpperOffset=NormalizeDouble(value,2);
   else            gTrack4LowerOffset=NormalizeDouble(value,2);
  }

void UpdateTrack4DeviationButtons()
  {
   string rails[2]={"UP","DN"};
   for(int r=0;r<2;r++)
     {
      string rail=rails[r];
      string names[3]={Track4DeviationButtonName(rail,"DEC"),Track4DeviationButtonName(rail,"VAL"),Track4DeviationButtonName(rail,"INC")};
      string title=(rail=="UP" ? "融合轨4上轨偏移" : "融合轨4下轨偏移");
      string labels[3]={"-",title+" "+DoubleToString(Track4OffsetValue(rail),2),"+"};
      for(int i=0;i<3;i++)
        {
         if(ObjectFind(0,names[i])<0) continue;
         ObjectSetString(0,names[i],OBJPROP_TEXT,labels[i]);
         ObjectSetInteger(0,names[i],OBJPROP_BGCOLOR,(i==1 ? C'45,65,90' : C'55,75,95'));
         ObjectSetInteger(0,names[i],OBJPROP_COLOR,clrWhite);
         ObjectSetInteger(0,names[i],OBJPROP_BORDER_COLOR,clrWhite);
         ObjectSetInteger(0,names[i],OBJPROP_STATE,false);
        }
     }
  }

void CreateTrack4DeviationButtons()
  {
   string rails[2]={"UP","DN"};
   for(int r=0;r<2;r++)
     {
      string rail=rails[r];
      string names[3]={Track4DeviationButtonName(rail,"DEC"),Track4DeviationButtonName(rail,"VAL"),Track4DeviationButtonName(rail,"INC")};
      int xs[3]={12,48,190};
      int ws[3]={32,138,32};
      for(int i=0;i<3;i++)
        {
         if(ObjectFind(0,names[i])>=0) ObjectDelete(0,names[i]);
         ObjectCreate(0,names[i],OBJ_BUTTON,0,0,0);
         ObjectSetInteger(0,names[i],OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,names[i],OBJPROP_XDISTANCE,xs[i]);
         ObjectSetInteger(0,names[i],OBJPROP_YDISTANCE,685+r*25);
         ObjectSetInteger(0,names[i],OBJPROP_XSIZE,ws[i]);
         ObjectSetInteger(0,names[i],OBJPROP_YSIZE,22);
         ObjectSetInteger(0,names[i],OBJPROP_FONTSIZE,8);
         ObjectSetInteger(0,names[i],OBJPROP_HIDDEN,true);
         ObjectSetInteger(0,names[i],OBJPROP_SELECTABLE,true);
         ObjectSetInteger(0,names[i],OBJPROP_STATE,false);
        }
     }
   UpdateTrack4DeviationButtons();
  }

void CreateOffsetButtons()
  {
   // 每一行采用“ -  当前偏移  + ”布局，十行分别控制五组通道的上下轨。
   for(int n=0;n<OFFSET_BUTTON_COUNT;n++)
     {
      string name=UI_PREFIX+"OFF_"+IntegerToString(n);
      if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
      ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
      int row=n/3;
      int action=n%3;
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      int x=(action==0 ? 12 : (action==1 ? 48 : 190));
      int w=(action==1 ? 138 : 32);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,385+row*25);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
      ObjectSetInteger(0,name,OBJPROP_YSIZE,22);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
      ObjectSetInteger(0,name,OBJPROP_STATE,false);
      UpdateOffsetButtonLook(n);
     }
  }

void LoadOffsets()
  {
   for(int c=0;c<5;c++)
     for(int r=0;r<2;r++)
       {
        string key=OffsetGlobalKey(c,r);
        double value=0.0;
        if(GlobalVariableCheck(key)) value=GlobalVariableGet(key);
        else if(c==0 || c==2 || c==4) value=(r==0 ? 0.9 : -0.9);
        if(r==0) gUpperOffset[c]=value;
        else     gLowerOffset[c]=value;
       }
  }

void SaveOffsets()
  {
   for(int c=0;c<5;c++)
     {
      GlobalVariableSet(OffsetGlobalKey(c,0),gUpperOffset[c]);
      GlobalVariableSet(OffsetGlobalKey(c,1),gLowerOffset[c]);
     }
  }

// 保存盘面运行时开关，供同周期刷新后恢复，避免即时重算时丢失按钮状态。
string RuntimeSwitchKey(const string item)
  {
   return "NCF58_"+IntegerToString((int)ChartID())+"_"+IntegerToString((int)_Period)+"_"+item;
  }

void SaveRuntimeSwitches()
  {
   for(int i=0;i<UI_BUTTON_COUNT;i++)
      GlobalVariableSet(RuntimeSwitchKey("SHOW"+IntegerToString(i)),gShow[i]?1.0:0.0);
   for(int i=0;i<5;i++)
     {
      GlobalVariableSet(RuntimeSwitchKey("LINEVIS"+IntegerToString(i)),gLineVisible[i]?1.0:0.0);
      GlobalVariableSet(RuntimeSwitchKey("LINEUSE"+IntegerToString(i)),gLineUsed[i]?1.0:0.0);
     }
   GlobalVariableSet(RuntimeSwitchKey("DYNAMIC"),gDynamicMultiplierEnabled?1.0:0.0);
   GlobalVariableSet(RuntimeSwitchKey("TRACK3_UP_OFFSET_V064"),gTrack3UpperOffset);
   GlobalVariableSet(RuntimeSwitchKey("TRACK3_DN_OFFSET_V064"),gTrack3LowerOffset);
   GlobalVariableSet(RuntimeSwitchKey("TRACK4_UP_OFFSET_V065"),gTrack4UpperOffset);
   GlobalVariableSet(RuntimeSwitchKey("TRACK4_DN_OFFSET_V065"),gTrack4LowerOffset);
  }

void RestoreRuntimeSwitches()
  {
   string key;
   for(int i=0;i<UI_BUTTON_COUNT;i++)
     {
      key=RuntimeSwitchKey("SHOW"+IntegerToString(i));
      if(GlobalVariableCheck(key)) gShow[i]=(GlobalVariableGet(key)>0.5);
     }
   for(int i=0;i<5;i++)
     {
      key=RuntimeSwitchKey("LINEVIS"+IntegerToString(i));
      if(GlobalVariableCheck(key)) gLineVisible[i]=(GlobalVariableGet(key)>0.5);
      key=RuntimeSwitchKey("LINEUSE"+IntegerToString(i));
      if(GlobalVariableCheck(key)) gLineUsed[i]=(GlobalVariableGet(key)>0.5);
     }
   key=RuntimeSwitchKey("DYNAMIC");
   if(GlobalVariableCheck(key)) gDynamicMultiplierEnabled=(GlobalVariableGet(key)>0.5);
   key=RuntimeSwitchKey("TRACK3_UP_OFFSET_V064");
   if(GlobalVariableCheck(key)) gTrack3UpperOffset=GlobalVariableGet(key);
   key=RuntimeSwitchKey("TRACK3_DN_OFFSET_V064");
   if(GlobalVariableCheck(key)) gTrack3LowerOffset=GlobalVariableGet(key);
   key=RuntimeSwitchKey("TRACK4_UP_OFFSET_V065");
   if(GlobalVariableCheck(key)) gTrack4UpperOffset=GlobalVariableGet(key);
   key=RuntimeSwitchKey("TRACK4_DN_OFFSET_V065");
   if(GlobalVariableCheck(key)) gTrack4LowerOffset=GlobalVariableGet(key);
  }

// 同周期刷新图表，强制指标重新初始化并完整计算历史数据。
void ForceImmediateRecalculation()
  {
   SaveRuntimeSwitches();
   SaveOffsets();
   ChartSetSymbolPeriod(0,_Symbol,(ENUM_TIMEFRAMES)_Period);
  }

void CreateChartButtons()
  {
   // 左上角两列按钮，直接点击切换，不需要打开参数窗口。
   for(int n=0;n<UI_BUTTON_COUNT;n++)
     {
      string name=UI_PREFIX+IntegerToString(n);
      if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
      ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,12+(n%2)*142);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,183+(n/2)*25);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,136);
      ObjectSetInteger(0,name,OBJPROP_YSIZE,22);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
      ObjectSetInteger(0,name,OBJPROP_STATE,false);
      UpdateButtonLook(n);
     }
  }

void DeleteChartButtons()
  {
   for(int n=0;n<UI_BUTTON_COUNT;n++) ObjectDelete(0,UI_PREFIX+IntegerToString(n));
   for(int line=0;line<5;line++)
     {
      ObjectDelete(0,LineSwitchName(line,false));
      ObjectDelete(0,LineSwitchName(line,true));
     }
   ObjectDelete(0,UI_PREFIX+"DYNAMIC");
   string t3rails[2]={"UP","DN"};
   string t3parts[3]={"DEC","VAL","INC"};
   for(int r=0;r<2;r++) for(int j=0;j<3;j++) ObjectDelete(0,Track3DeviationButtonName(t3rails[r],t3parts[j]));
   string t4rails[2]={"UP","DN"};
   string t4parts[3]={"DEC","VAL","INC"};
   for(int r=0;r<2;r++) for(int j=0;j<3;j++) ObjectDelete(0,Track4DeviationButtonName(t4rails[r],t4parts[j]));
   for(int n=0;n<OFFSET_BUTTON_COUNT;n++) ObjectDelete(0,UI_PREFIX+"OFF_"+IntegerToString(n));
  }

//====================================================================
// 盘面底部算法说明面板：把每条线的输入来源、公式、组合阶段和实时开关状态显示出来。
// 使用只读多行编辑框，内容较长时可在面板内滚动查看。
string DebugPanelName()
  {
   return UI_PREFIX+"ALGORITHM_DEBUG_PANEL";
  }

string OnOffText(const bool value)
  {
   return (value ? "开" : "关");
  }

string DebugLineState(const int i)
  {
   return gLineNames[i]+" | 显示="+OnOffText(gLineVisible[i])+" | 参与计算="+OnOffText(gLineUsed[i]);
  }

void UpdateDebugPanel()
  {
   string t="【南门拈星｜指标算法与引用关系调试台】 版本 v0.65\r\n";
   t+="说明：显示=只控制是否画线；参与计算=控制该线进入哪些后续算法。基础线引用状态变化会触发完整重算；轨3/轨4的人工偏移仅重建绘图缓冲区。\r\n\r\n";
   t+="一、基础分析线：输入数据、计算方法与当前状态\r\n";
   t+="1. 快速响应线：输入=当前品种收盘价；公式=EMA(close, "+IntegerToString(InpFastEMA_Period)+")，递推系数 α=2/(周期+1)。用于快速跟随价格。\r\n";
   t+="   当前："+DebugLineState(0)+"。参与后续阶段：融合线加权输入、五线基础通道集合、A/B/C/D/E/F组合通道；并作为KAMA宽度通道中心及E限宽中心。\r\n";
   t+="2. 卡尔曼线：输入=收盘价观测值；过程噪声Q=ATR²×"+DoubleToString(InpKalman_Q_Factor,2)+"，测量噪声R=ATR²×"+DoubleToString(InpKalman_R_Factor,2)+"；预测误差协方差递推后计算增益K，再按“旧估计+K×(收盘价-旧估计)”更新。\r\n";
   t+="   当前："+DebugLineState(1)+"。参与后续阶段：融合线加权输入、五线基础通道集合及A/B/C/D/E/F组合通道。\r\n";
   t+="3. KAMA自适应线：输入=收盘价；效率比ER=周期净变化/周期内逐根绝对变化总和；平滑系数=(ER×(快速系数-慢速系数)+慢速系数)²；再递推更新KAMA。ER周期="+IntegerToString(InpKAMA_ER_Period)+"，快周期="+IntegerToString(InpKAMA_Fast_Period)+"，慢周期="+IntegerToString(InpKAMA_Slow_Period)+"。\r\n";
   t+="   当前："+DebugLineState(2)+"。参与后续阶段：融合线加权输入、五线基础通道集合；并与快速线共同决定KAMA宽度通道是否进入B/C/D/E/综合轨1。\r\n";
   t+="4. 中位结构线：对当前及更旧K线的局部窗口取中位数；窗口="+IntegerToString(InpMedian_Period)+"，每根样本取(high+low)/2，再排序取中位数。降低单根极端值影响。\r\n";
   t+="   当前："+DebugLineState(3)+"。参与后续阶段：融合线加权输入、五线基础通道集合及A/B/C/D/E/F组合通道。\r\n";
   t+="5. 融合线：输入=快速线、卡尔曼线、KAMA线、中位结构线；按启用引用状态和非负权重归一化加权平均；权重分别为快速="+DoubleToString(InpWeight_Fast,2)+"、卡尔曼="+DoubleToString(InpWeight_Kalman,2)+"、KAMA="+DoubleToString(InpWeight_KAMA,2)+"、中位="+DoubleToString(InpWeight_Median,2)+"；额外平滑周期="+IntegerToString(InpFusion_Smooth_Period)+"。融合线不把自身作为输入。\r\n";
   t+="   当前："+DebugLineState(4)+"。注意：其“参与计算”开关控制融合通道是否进入组合通道，不会把融合线自身再次塞回融合公式。\r\n\r\n";
   t+="四、融合轨4综合动能驱离：方向输入=RSI("+IntegerToString(InpTrack4_RSI_Fast)+"/"+IntegerToString(InpTrack4_RSI_Slow)+")、WPR("+IntegerToString(InpTrack4_WPR_Fast)+"/"+IntegerToString(InpTrack4_WPR_Slow)+")、MACD("+IntegerToString(InpTrack4_MACD_Fast)+"/"+IntegerToString(InpTrack4_MACD_Slow)+"/"+IntegerToString(InpTrack4_MACD_Signal)+")、KDJ("+IntegerToString(InpTrack4_KDJ_K)+","+IntegerToString(InpTrack4_KDJ_D)+","+IntegerToString(InpTrack4_KDJ_Slowing)+")、+DI/-DI；ADX周期="+IntegerToString(InpTrack4_ADX_Period)+"，ATR采用基础ATR周期="+IntegerToString(InpATR_Period)+"。\r\n";
   t+="多头时上轨按ATR×"+DoubleToString(InpTrack4_MaxDrive_ATR,2)+"×能量驱离，下轨按ATR×"+DoubleToString(InpTrack4_MaxLift_ATR,2)+"×能量抬升；空头镜像处理。扩张速度="+DoubleToString(InpTrack4_ExpandSpeed,2)+"，回收速度="+DoubleToString(InpTrack4_RecoilSpeed,2)+"。融合轨3/4偏移按钮仅更新绘图缓冲区，不重算基础指标。\r\n\r\n";

   t+="二、通道宽度算法（五条基础通道分别独立计算）\r\n";
   t+="公共宽度：ATR周期="+IntegerToString(InpATR_Period)+"；残差窗口="+IntegerToString(InpResidual_Period)+"；最小半宽=ATR×"+DoubleToString(InpATR_Min_Multiplier,2)+"；残差系数="+DoubleToString(InpResidual_Multiplier,2)+"。每条线的残差宽度由 close 与该线的残差RMS估计，并乘各自宽度倍率；半宽至少不低于ATR最小半宽。\r\n";
   t+="快速通道=快速线±快速线残差半宽×"+DoubleToString(InpFast_Width_Mult,2)+"；卡尔曼通道=卡尔曼线±卡尔曼残差半宽×"+DoubleToString(InpKalman_Width_Mult,2)+"。\r\n";
   t+="KAMA通道=KAMA线±KAMA残差半宽×"+DoubleToString(InpKAMA_Width_Mult,2)+"；中位通道=中位线±中位残差半宽×"+DoubleToString(InpMedian_Width_Mult,2)+"。\r\n";
   t+="融合通道=融合线±融合残差半宽×"+DoubleToString(InpFusion_Width_Mult,2)+"。基础通道各自的绘制开关只影响显示，不改变本条通道的底层数值计算。\r\n\r\n";

   t+="三、组合通道：输入成员、公式与阶段关系\r\n";
   t+="KAMA宽度通道：中心=快速线；上/下半宽直接借用KAMA通道对应半宽×缩放系数"+DoubleToString(InpFast_KAMAWidth_Scale,2)+"。只有快速线和KAMA线的“参与计算”都开启时，才纳入组合通道集合。\r\n";
   t+="A 均值：对已启用参与计算的基础通道（快速、卡尔曼、KAMA、中位、融合）分别求上轨算术平均和下轨算术平均；不含KAMA宽度通道。\r\n";
   t+="B 外沿比较：基础通道均值与KAMA宽度通道比较；上轨取较大值，下轨取较小值。若其中一类输入没有可用成员，则使用仍可用的那一类；两类都无则不输出。偏移只影响B显示轨道。\r\n";
   t+="C 六组平均：对启用的五条基础通道及可用的KAMA宽度通道，分别求上轨和下轨算术平均。实际参与组数由当前引用开关决定，不一定固定为6组。\r\n";
   t+="D 六组外沿：同一组可用通道中，上轨取最大值、下轨取最小值，形成外包络；D上下轨偏移仅改变D显示结果，不作为E限宽融合的输入。\r\n";
   t+="E 限宽融合：当前源码中C均值与D计算源使用同一批组成员；按混合比例 blend="+DoubleToString(InpCappedBlend,2)+"在C六组平均与六组外沿之间插值，再以快速线为中心限制半宽不超过ATR×"+DoubleToString(InpMaxHalfWidth_ATR,2)+"，最后加E上下轨偏移。blend=0偏向C平均，blend=1偏向外沿。\r\n";
   t+="F 五线中位：对当前启用引用的基础通道，上轨单独排序取中位数，下轨单独排序取中位数；不包含KAMA宽度通道。\r\n";
   t+="综合轨1：原始上/下轨=2×C上/下轨-E上/下轨；再分别加/减 |E轨-C轨|×动态倍率，最后叠加综合轨1人工偏移。动态倍率来源于B外沿比较轨道的窗口相对变化率，参数窗口="+IntegerToString(CompositeSpeedWindowValue())+"，平滑窗口="+IntegerToString(CompositeSmoothingValue())+"，长期基准="+IntegerToString(InpCompositeBaselineWindow)+"；动态倍率当前="+OnOffText(gDynamicMultiplierEnabled)+"。\r\n\r\n";

   t+="四、实时参与状态总表（每次开关切换后自动刷新）\r\n";
   t+="基础线："+DebugLineState(0)+"；"+DebugLineState(1)+"；"+DebugLineState(2)+"。\r\n";
   t+="基础线："+DebugLineState(3)+"；"+DebugLineState(4)+"。\r\n";
   t+="通道绘制：快速="+OnOffText(gShow[0])+"，卡尔曼="+OnOffText(gShow[1])+"，KAMA="+OnOffText(gShow[2])+"，中位="+OnOffText(gShow[3])+"，融合="+OnOffText(gShow[4])+"，KAMA宽度="+OnOffText(gShow[5])+"。\r\n";
   t+="组合绘制：A均值="+OnOffText(gShow[6])+"，B外沿="+OnOffText(gShow[7])+"，C六组平均="+OnOffText(gShow[8])+"，D六组外沿="+OnOffText(gShow[9])+"，E限宽="+OnOffText(gShow[10])+"，F五线中位="+OnOffText(gShow[11])+"，综合轨1="+OnOffText(gShow[12])+"，融合轨2="+OnOffText(gShow[13])+"，融合轨3="+OnOffText(gShow[14])+"，融合轨4="+OnOffText(gShow[15])+"。\r\n";
   t+="融合轨3：基础上轨=KAMA上轨-融合轨2上半宽；基础下轨=KAMA下轨+融合轨2下半宽；均线轨=(上轨+下轨)/2。上下轨按钮只负责独立平移，每次调整0.1；上轨偏移="+DoubleToString(gTrack3UpperOffset,1)+"，下轨偏移="+DoubleToString(gTrack3LowerOffset,1)+"。\r\n";
   t+="偏移说明：B、KAMA宽度、E、综合轨1、D各有独立上/下轨偏移；偏移只影响相应通道显示值，具体数值可查看左上角偏移按钮。\r\n";
   t+="调试建议：先单独切换某条基础线的‘参与计算’，观察融合线、A/B/C/D/E/F与综合轨1；再分别切换通道‘显示’以区分计算变化和绘图变化。\r\n";

   // 使用逐行标签呈现多行内容，避免 OBJ_EDIT 单行编辑框导致说明无法显示。
   int count=StringSplit(t,'\n',gDebugPanelLines);
   for(int i=0;i<count;i++) StringReplace(gDebugPanelLines[i],"\r","");
   int pages=MathMax(1,(count+DEBUG_PANEL_VISIBLE_ROWS-1)/DEBUG_PANEL_VISIBLE_ROWS);
   if(gDebugPanelPage>=pages) gDebugPanelPage=pages-1;
   if(gDebugPanelPage<0) gDebugPanelPage=0;
   RenderDebugPanel(count,pages);
  }

string DebugPanelPartName(const string part,const int index=-1)
  {
   if(index<0) return UI_PREFIX+"DBG_"+part;
   return UI_PREFIX+"DBG_"+part+"_"+IntegerToString(index);
  }

void CreateDebugPanel()
  {
   int chartWidth=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int panelWidth=MathMax(700,chartWidth-20);
   string bg=DebugPanelPartName("BG");
   if(ObjectFind(0,bg)>=0) ObjectDelete(0,bg);
   ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,8);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,8);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,panelWidth);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,DEBUG_PANEL_HEIGHT);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,C'22,28,36');
   ObjectSetInteger(0,bg,OBJPROP_COLOR,C'80,100,120');
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   ObjectSetInteger(0,bg,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,bg,OBJPROP_HIDDEN,true);

   for(int i=0;i<DEBUG_PANEL_VISIBLE_ROWS;i++)
     {
      string row=DebugPanelPartName("ROW",i);
      if(ObjectFind(0,row)>=0) ObjectDelete(0,row);
      ObjectCreate(0,row,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,row,OBJPROP_CORNER,CORNER_LEFT_LOWER);
      ObjectSetInteger(0,row,OBJPROP_XDISTANCE,18);
      ObjectSetInteger(0,row,OBJPROP_YDISTANCE,30+(DEBUG_PANEL_VISIBLE_ROWS-1-i)*DEBUG_PANEL_ROW_HEIGHT);
      ObjectSetInteger(0,row,OBJPROP_FONTSIZE,8);
      ObjectSetString(0,row,OBJPROP_FONT,"Microsoft YaHei UI");
      ObjectSetInteger(0,row,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,row,OBJPROP_ANCHOR,ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0,row,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,row,OBJPROP_HIDDEN,true);
     }

   string prev=DebugPanelPartName("PREV"), next=DebugPanelPartName("NEXT"), page=DebugPanelPartName("PAGE");
   string names[2]={prev,next};
   string labels[2]={"上一页","下一页"};
   for(int i=0;i<2;i++)
     {
      if(ObjectFind(0,names[i])>=0) ObjectDelete(0,names[i]);
      ObjectCreate(0,names[i],OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,names[i],OBJPROP_CORNER,CORNER_RIGHT_LOWER);
      ObjectSetInteger(0,names[i],OBJPROP_XDISTANCE,(i==0?150:78));
      ObjectSetInteger(0,names[i],OBJPROP_YDISTANCE,10);
      ObjectSetInteger(0,names[i],OBJPROP_XSIZE,68);
      ObjectSetInteger(0,names[i],OBJPROP_YSIZE,20);
      ObjectSetInteger(0,names[i],OBJPROP_FONTSIZE,8);
      ObjectSetString(0,names[i],OBJPROP_TEXT,labels[i]);
      ObjectSetInteger(0,names[i],OBJPROP_BGCOLOR,C'45,65,90');
      ObjectSetInteger(0,names[i],OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,names[i],OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,names[i],OBJPROP_SELECTABLE,true);
     }
   if(ObjectFind(0,page)>=0) ObjectDelete(0,page);
   ObjectCreate(0,page,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,page,OBJPROP_CORNER,CORNER_RIGHT_LOWER);
   ObjectSetInteger(0,page,OBJPROP_XDISTANCE,225);
   ObjectSetInteger(0,page,OBJPROP_YDISTANCE,12);
   ObjectSetInteger(0,page,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,page,OBJPROP_COLOR,clrSilver);
   ObjectSetInteger(0,page,OBJPROP_HIDDEN,true);
   UpdateDebugPanel();
  }

void RenderDebugPanel(const int count,const int pages)
  {
   for(int row=0;row<DEBUG_PANEL_VISIBLE_ROWS;row++)
     {
      int idx=gDebugPanelPage*DEBUG_PANEL_VISIBLE_ROWS+row;
      string name=DebugPanelPartName("ROW",row);
      string line=(idx<count ? gDebugPanelLines[idx] : "");
      ObjectSetString(0,name,OBJPROP_TEXT,line);
      ObjectSetInteger(0,name,OBJPROP_COLOR,(row==0 && gDebugPanelPage==0) ? clrAqua : clrWhite);
     }
   ObjectSetString(0,DebugPanelPartName("PAGE"),OBJPROP_TEXT,
                   IntegerToString(gDebugPanelPage+1)+"/"+IntegerToString(pages));
   ObjectSetInteger(0,DebugPanelPartName("PREV"),OBJPROP_STATE,false);
   ObjectSetInteger(0,DebugPanelPartName("NEXT"),OBJPROP_STATE,false);
   ChartRedraw(0);
  }

void DeleteDebugPanel()
  {
   ObjectDelete(0,DebugPanelName());
   ObjectDelete(0,DebugPanelPartName("BG"));
   ObjectDelete(0,DebugPanelPartName("PREV"));
   ObjectDelete(0,DebugPanelPartName("NEXT"));
   ObjectDelete(0,DebugPanelPartName("PAGE"));
   for(int i=0;i<DEBUG_PANEL_VISIBLE_ROWS;i++)
      ObjectDelete(0,DebugPanelPartName("ROW",i));
  }

void DeleteAllOwnedObjects()
  {
   // 仅删除本指标自己的对象，避免误删用户或其他指标的图形。
   for(int i=ObjectsTotal(0,-1,-1)-1;i>=0;i--)
     {
      string name=ObjectName(0,i,-1,-1);
      if(StringFind(name,UI_PREFIX)==0)
         ObjectDelete(0,name);
     }
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
string LiteRailButtonName(const int index)
  {
   return UI_PREFIX+"LITE_RAIL_"+IntegerToString(index);
  }

void UpdateLiteRailButtons()
  {
   string labels[4]={"KAMA参考上轨","KAMA参考下轨","融合轨4上轨","融合轨4下轨"};
   for(int i=0;i<4;i++)
     {
      string name=LiteRailButtonName(i);
      if(ObjectFind(0,name)<0) continue;
      ObjectSetString(0,name,OBJPROP_TEXT,labels[i]+(gLiteRailVisible[i]?" [显示]":" [隐藏]"));
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,gLiteRailVisible[i] ? C'35,95,75' : C'65,65,65');
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,gLiteRailVisible[i] ? clrLimeGreen : clrDimGray);
      ObjectSetInteger(0,name,OBJPROP_STATE,false);
     }
  }

void CreateLiteRailButtons()
  {
   string labels[4]={"KAMA参考上轨","KAMA参考下轨","融合轨4上轨","融合轨4下轨"};
   int xs[4]={250,385,520,655};
   int ys[4]={685,685,685,685};
   for(int i=0;i<4;i++)
     {
      string name=LiteRailButtonName(i);
      if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
      ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,xs[i]);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,ys[i]);
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

int OnInit()
{
   if(InpFastEMA_Period<1 || InpKalman_Q_Factor<=0.0 ||
      InpKalman_R_Factor<=0.0 || InpKAMA_ER_Period<1 ||
      InpKAMA_Fast_Period<1 || InpKAMA_Slow_Period<2 ||
      InpMedian_Period<1 || InpFusion_Smooth_Period<1 ||
      InpATR_Period<1 || InpResidual_Period<1 ||
      InpATR_Min_Multiplier<=0.0 || InpResidual_Multiplier<0.0 || InpFast_KAMAWidth_Scale<=0.0 || InpMaxHalfWidth_ATR<=0.0 || InpTrack2_ExtremeLookback<2 || InpTrack2_MagnetIntensity<0.0 || InpTrack2_MaxPull_ATR<0.0 || InpTrack2_MACD_Fast<1 || InpTrack2_MACD_Slow<=InpTrack2_MACD_Fast || InpTrack2_MACD_Signal<1 || InpTrack2_RSI_Fast<2 || InpTrack2_RSI_Slow<2 || InpTrack2_WPR_Period<2 || InpTrack2_ADX_Period<2 || InpTrack4_MACD_Fast<1 || InpTrack4_MACD_Slow<=InpTrack4_MACD_Fast || InpTrack4_MACD_Signal<1 || InpTrack4_RSI_Fast<2 || InpTrack4_RSI_Slow<2 || InpTrack4_WPR_Fast<2 || InpTrack4_WPR_Slow<2 || InpTrack4_ADX_Period<2 || InpTrack4_KDJ_K<1 || InpTrack4_KDJ_D<1 || InpTrack4_KDJ_Slowing<1 || InpTrack4_MaxDrive_ATR<0.0 || InpTrack4_MaxLift_ATR<0.0 || InpTrack4_ADX_Strong<=InpTrack4_ADX_Weak || InpTrack4_ExpandSpeed<=0.0 || InpTrack4_ExpandSpeed>1.0 || InpTrack4_RecoilSpeed<=0.0 || InpTrack4_RecoilSpeed>1.0)
   {
      Print("五线原始通道：参数无效，请检查输入参数。");
      return INIT_PARAMETERS_INCORRECT;
   }

   gShow[0]=InpShow_Fast_Channel;
   gShow[1]=InpShow_Kalman_Channel;
   gShow[2]=InpShow_KAMA_Channel;
   gShow[3]=InpShow_Median_Channel;
   gShow[4]=InpShow_Fusion_Channel;
   gShow[5]=InpShow_Fast_KAMAWidth_Channel;
   gShow[6]=InpShow_Avg5_Channel;
   gShow[7]=InpShow_NewVsAvg_Outer;
   gShow[8]=InpShow_Avg6_Channel;
   gShow[9]=InpShow_Envelope6_Channel;
   gShow[10]=InpShow_Capped_Channel;
   gShow[11]=InpShow_Median5_Channel;
   gShow[12]=true;
   gShow[13]=InpEnableFusionTrack2;
   gLineVisible[0]=InpShow_Fast_Line;
   gLineVisible[1]=InpShow_Kalman_Line;
   gLineVisible[2]=InpShow_KAMA_Line;
   gLineVisible[3]=InpShow_Median_Line;
   gLineVisible[4]=InpShow_Fusion_Line;
   gLineUsed[0]=InpUse_Fast_Line;
   gLineUsed[1]=InpUse_Kalman_Line;
   gLineUsed[2]=InpUse_KAMA_Line;
   gLineUsed[3]=InpUse_Median_Line;
   gLineUsed[4]=InpUse_Fusion_Line;
   gDynamicMultiplierEnabled=InpEnableCompositeDynamicMultiplier;
   gShow[12]=false;
   gShow[13]=InpEnableFusionTrack2;
   gShow[14]=true;
   gShow[15]=true;
   RestoreRuntimeSwitches();
   LoadOffsets();

   SetIndexBuffer(0,FastLine,INDICATOR_DATA);
   SetIndexBuffer(1,FastUpper,INDICATOR_DATA);
   SetIndexBuffer(2,FastLower,INDICATOR_DATA);
   SetIndexBuffer(3,KalmanLine,INDICATOR_DATA);
   SetIndexBuffer(4,KalmanUpper,INDICATOR_DATA);
   SetIndexBuffer(5,KalmanLower,INDICATOR_DATA);
   SetIndexBuffer(6,KAMALine,INDICATOR_DATA);
   SetIndexBuffer(7,KAMAUpper,INDICATOR_DATA);
   SetIndexBuffer(8,KAMALower,INDICATOR_DATA);
   SetIndexBuffer(9,MedianLine,INDICATOR_DATA);
   SetIndexBuffer(10,MedianUpper,INDICATOR_DATA);
   SetIndexBuffer(11,MedianLower,INDICATOR_DATA);
   SetIndexBuffer(12,FusionLine,INDICATOR_DATA);
   SetIndexBuffer(13,FusionUpper,INDICATOR_DATA);
   SetIndexBuffer(14,FusionLower,INDICATOR_DATA);
   SetIndexBuffer(15,FastKAMAWidthUpper,INDICATOR_DATA);
   SetIndexBuffer(16,FastKAMAWidthLower,INDICATOR_DATA);
   SetIndexBuffer(17,Avg5Upper,INDICATOR_DATA);
   SetIndexBuffer(18,Avg5Lower,INDICATOR_DATA);
   SetIndexBuffer(19,NewVsAvgUpper,INDICATOR_DATA);
   SetIndexBuffer(20,NewVsAvgLower,INDICATOR_DATA);
   SetIndexBuffer(21,Avg6Upper,INDICATOR_DATA);
   SetIndexBuffer(22,Avg6Lower,INDICATOR_DATA);
   SetIndexBuffer(23,Envelope6Upper,INDICATOR_DATA);
   SetIndexBuffer(24,Envelope6Lower,INDICATOR_DATA);
   SetIndexBuffer(25,CappedUpper,INDICATOR_DATA);
   SetIndexBuffer(26,CappedLower,INDICATOR_DATA);
   SetIndexBuffer(27,Median5Upper,INDICATOR_DATA);
   SetIndexBuffer(28,Median5Lower,INDICATOR_DATA);
   SetIndexBuffer(29,Composite1Upper,INDICATOR_DATA);
   SetIndexBuffer(30,Composite1Lower,INDICATOR_DATA);
   SetIndexBuffer(31,Composite2Upper,INDICATOR_DATA);
   SetIndexBuffer(32,Composite2Lower,INDICATOR_DATA);
   SetIndexBuffer(33,Composite2Middle,INDICATOR_DATA);
   SetIndexBuffer(34,Composite3Upper,INDICATOR_DATA);
   SetIndexBuffer(35,Composite3Lower,INDICATOR_DATA);
   SetIndexBuffer(36,Composite3Middle,INDICATOR_DATA);
   SetIndexBuffer(37,Composite4Upper,INDICATOR_DATA);
   SetIndexBuffer(38,Composite4Lower,INDICATOR_DATA);
   SetIndexBuffer(39,SellTouchArrow,INDICATOR_DATA);
   SetIndexBuffer(40,BuyTouchArrow,INDICATOR_DATA);

   ArraySetAsSeries(FastLine,true);
   ArraySetAsSeries(FastUpper,true);
   ArraySetAsSeries(FastLower,true);
   ArraySetAsSeries(KalmanLine,true);
   ArraySetAsSeries(KalmanUpper,true);
   ArraySetAsSeries(KalmanLower,true);
   ArraySetAsSeries(KAMALine,true);
   ArraySetAsSeries(KAMAUpper,true);
   ArraySetAsSeries(KAMALower,true);
   ArraySetAsSeries(MedianLine,true);
   ArraySetAsSeries(MedianUpper,true);
   ArraySetAsSeries(MedianLower,true);
   ArraySetAsSeries(FusionLine,true);
   ArraySetAsSeries(FusionUpper,true);
   ArraySetAsSeries(FusionLower,true);
   ArraySetAsSeries(FastKAMAWidthUpper,true);
   ArraySetAsSeries(FastKAMAWidthLower,true);
   ArraySetAsSeries(Avg5Upper,true); ArraySetAsSeries(Avg5Lower,true);
   ArraySetAsSeries(NewVsAvgUpper,true); ArraySetAsSeries(NewVsAvgLower,true);
   ArraySetAsSeries(Avg6Upper,true); ArraySetAsSeries(Avg6Lower,true);
   ArraySetAsSeries(Envelope6Upper,true); ArraySetAsSeries(Envelope6Lower,true);
   ArraySetAsSeries(CappedUpper,true); ArraySetAsSeries(CappedLower,true);
   ArraySetAsSeries(Median5Upper,true); ArraySetAsSeries(Median5Lower,true);
   ArraySetAsSeries(Composite1Upper,true); ArraySetAsSeries(Composite1Lower,true);
   ArraySetAsSeries(Composite2Upper,true); ArraySetAsSeries(Composite2Lower,true);
   ArraySetAsSeries(Composite2Middle,true);
   ArraySetAsSeries(Composite3Upper,true); ArraySetAsSeries(Composite3Lower,true); ArraySetAsSeries(Composite3Middle,true);
   ArraySetAsSeries(Composite4Upper,true); ArraySetAsSeries(Composite4Lower,true);
   ArraySetAsSeries(SellTouchArrow,true); ArraySetAsSeries(BuyTouchArrow,true);

   for(int p=0;p<41;p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(39,PLOT_ARROW,234); // 向下箭头
   PlotIndexSetInteger(40,PLOT_ARROW,233); // 向上箭头

   ApplyBaseLineVisibility();
   PlotIndexSetInteger(27,PLOT_DRAW_TYPE,InpShow_Median5_Channel ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(28,PLOT_DRAW_TYPE,InpShow_Median5_Channel ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(29,PLOT_DRAW_TYPE,DRAW_LINE);
   PlotIndexSetInteger(30,PLOT_DRAW_TYPE,DRAW_LINE);
   PlotIndexSetInteger(31,PLOT_DRAW_TYPE,InpEnableFusionTrack2 ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(32,PLOT_DRAW_TYPE,InpEnableFusionTrack2 ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(33,PLOT_DRAW_TYPE,InpEnableFusionTrack2 ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(34,PLOT_DRAW_TYPE,InpEnableFusionTrack2 ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(35,PLOT_DRAW_TYPE,InpEnableFusionTrack2 ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(36,PLOT_DRAW_TYPE,InpEnableFusionTrack2 ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(37,PLOT_DRAW_TYPE,InpEnableFusionTrack4 ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(38,PLOT_DRAW_TYPE,InpEnableFusionTrack4 ? DRAW_LINE : DRAW_NONE);
   ApplyPlotVisibility();
   // 精简盘面：隐藏原多通道按钮和调试面板，只保留统计面板与四条目标轨道/箭头。
   CreateStatsPanel();
   CreateTouchFilterButton();
   CreateTrack4DeviationButtons();
   CreateLiteRailButtons();

   gTrack2MACDHandle=iMACD(_Symbol,_Period,InpTrack2_MACD_Fast,InpTrack2_MACD_Slow,InpTrack2_MACD_Signal,PRICE_CLOSE);
   gTrack2RSI7Handle=iRSI(_Symbol,_Period,InpTrack2_RSI_Fast,PRICE_CLOSE);
   gTrack2RSI14Handle=iRSI(_Symbol,_Period,InpTrack2_RSI_Slow,PRICE_CLOSE);
   gTrack2WPRHandle=iWPR(_Symbol,_Period,InpTrack2_WPR_Period);
   gTrack2ADXHandle=iADX(_Symbol,_Period,InpTrack2_ADX_Period);
   gTrack4MACDHandle=iMACD(_Symbol,_Period,InpTrack4_MACD_Fast,InpTrack4_MACD_Slow,InpTrack4_MACD_Signal,PRICE_CLOSE);
   gTrack4RSI7Handle=iRSI(_Symbol,_Period,InpTrack4_RSI_Fast,PRICE_CLOSE);
   gTrack4RSI17Handle=iRSI(_Symbol,_Period,InpTrack4_RSI_Slow,PRICE_CLOSE);
   gTrack4WPR7Handle=iWPR(_Symbol,_Period,InpTrack4_WPR_Fast);
   gTrack4WPR14Handle=iWPR(_Symbol,_Period,InpTrack4_WPR_Slow);
   gTrack4ADXHandle=iADX(_Symbol,_Period,InpTrack4_ADX_Period);
   gTrack4KDJHandle=iStochastic(_Symbol,_Period,InpTrack4_KDJ_K,InpTrack4_KDJ_D,InpTrack4_KDJ_Slowing,MODE_SMA,STO_LOWHIGH);
   if(gTrack2MACDHandle==INVALID_HANDLE || gTrack2RSI7Handle==INVALID_HANDLE || gTrack2RSI14Handle==INVALID_HANDLE || gTrack2WPRHandle==INVALID_HANDLE || gTrack2ADXHandle==INVALID_HANDLE || gTrack4MACDHandle==INVALID_HANDLE || gTrack4RSI7Handle==INVALID_HANDLE || gTrack4RSI17Handle==INVALID_HANDLE || gTrack4WPR7Handle==INVALID_HANDLE || gTrack4WPR14Handle==INVALID_HANDLE || gTrack4ADXHandle==INVALID_HANDLE || gTrack4KDJHandle==INVALID_HANDLE)
     {
      Print("融合轨2：无法创建一个或多个指标句柄，检查参数与终端数据。");
      return INIT_FAILED;
     }

   IndicatorSetString(INDICATOR_SHORTNAME,"南门拈星 融合轨4轻量版 v0.65（保留原统计）");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return INIT_SUCCEEDED;
}

// 仅更新指定轨道的显示缓冲区。底层均线、ATR、残差宽度及其他轨道不重算。
void RebuildOffsetChannel(const int channel)
  {
   if(gCachedRatesTotal<=0) return;
   int total=gCachedRatesTotal;
   double scale=MathMax(0.01,InpFast_KAMAWidth_Scale);
   double blend=ClampValue(InpCappedBlend,0.0,1.0);

   for(int i=0;i<total;i++)
     {
      // KAMA宽度通道：只在原始边界上加显示偏移。
      double kamaHalfUp=MathMax(0.0,KAMAUpper[i]-KAMALine[i]);
      double kamaHalfDown=MathMax(0.0,KAMALine[i]-KAMALower[i]);
      double baseKU=FastLine[i]+kamaHalfUp*scale;
      double baseKL=FastLine[i]-kamaHalfDown*scale;

      if(channel==1)
        {
         FastKAMAWidthUpper[i]=baseKU+gUpperOffset[1];
         FastKAMAWidthLower[i]=baseKL+gLowerOffset[1];
        }
      else if(channel==0 || channel==2 || channel==4)
        {
         double bu[5]={FastUpper[i],KalmanUpper[i],KAMAUpper[i],MedianUpper[i],FusionUpper[i]};
         double bl[5]={FastLower[i],KalmanLower[i],KAMALower[i],MedianLower[i],FusionLower[i]};
         bool use[5]={gLineUsed[0],gLineUsed[1],gLineUsed[2],gLineUsed[3],gLineUsed[4]};
         double sum5u=0.0,sum5l=0.0,sum6u=0.0,sum6l=0.0,outerU=0.0,outerL=0.0;
         int n5=0,n6=0;
         for(int k=0;k<5;k++) if(use[k])
           {
            sum5u+=bu[k]; sum5l+=bl[k]; n5++;
            sum6u+=bu[k]; sum6l+=bl[k];
            if(n6==0) { outerU=bu[k]; outerL=bl[k]; }
            else { outerU=MathMax(outerU,bu[k]); outerL=MathMin(outerL,bl[k]); }
            n6++;
           }
         bool useWidth=(gLineUsed[0] && gLineUsed[2]);
         if(useWidth)
           {
            sum6u+=baseKU; sum6l+=baseKL;
            if(n6==0) { outerU=baseKU; outerL=baseKL; }
            else { outerU=MathMax(outerU,baseKU); outerL=MathMin(outerL,baseKL); }
            n6++;
           }
         if(channel==0)
           {
            if(n5>0 && useWidth)
              { NewVsAvgUpper[i]=MathMax(baseKU,sum5u/n5)+gUpperOffset[0]; NewVsAvgLower[i]=MathMin(baseKL,sum5l/n5)+gLowerOffset[0]; }
            else if(n5>0)
              { NewVsAvgUpper[i]=sum5u/n5+gUpperOffset[0]; NewVsAvgLower[i]=sum5l/n5+gLowerOffset[0]; }
            else if(useWidth)
              { NewVsAvgUpper[i]=baseKU+gUpperOffset[0]; NewVsAvgLower[i]=baseKL+gLowerOffset[0]; }
            else { NewVsAvgUpper[i]=EMPTY_VALUE; NewVsAvgLower[i]=EMPTY_VALUE; }
           }
         else if(channel==2)
           {
            if(n6<=0) { CappedUpper[i]=EMPTY_VALUE; CappedLower[i]=EMPTY_VALUE; }
            else
              {
               double avg6U=sum6u/n6,avg6L=sum6l/n6;
               double rawU=avg6U+(outerU-avg6U)*blend;
               double rawL=avg6L-(avg6L-outerL)*blend;
               double atrValue=MathMax(Atr[i],_Point*2.0);
               double maxHalf=MathMax(atrValue*InpMaxHalfWidth_ATR,_Point*2.0);
               CappedUpper[i]=MathMin(rawU,FastLine[i]+maxHalf)+gUpperOffset[2];
               CappedLower[i]=MathMax(rawL,FastLine[i]-maxHalf)+gLowerOffset[2];
              }
           }
         else
           {
            if(n6<=0) { Envelope6Upper[i]=EMPTY_VALUE; Envelope6Lower[i]=EMPTY_VALUE; }
            else { Envelope6Upper[i]=outerU+gUpperOffset[4]; Envelope6Lower[i]=outerL+gLowerOffset[4]; }
           }
        }
      else if(channel==3)
        {
         //=================================================================
         // 【综合轨1最终轨道公式区：当前版本只增加注释，不改变原计算】
         //
         // 相关变量中文定义：
         // Avg6Upper/Avg6Lower：
         //   C「六组平均」的原始上轨/下轨，即六组通道对应边界的算术平均。
         // CappedUpper/CappedLower：
         //   E「限宽融合」的最终上轨/下轨，先做混合计算，再受 ATR 最大半宽限制。
         // CompositeDynamicKUpper/Lower：
         //   综合轨1上下轨各自使用的动态倍率，来源于 B「外沿比较」轨道的变化率。
         // gUpperOffset[3]/gLowerOffset[3]：
         //   综合轨1的人工显示偏移，不参与动态倍率的计算。
         //
         // 第1步：读取动态倍率。
         // 如果缓存数组尚未覆盖当前索引，暂时使用 1.0。
         double dynUpper=1.0, dynLower=1.0;
         if(ArraySize(CompositeDynamicKUpper)>i) dynUpper=CompositeDynamicKUpper[i];
         if(ArraySize(CompositeDynamicKLower)>i) dynLower=CompositeDynamicKLower[i];

         // 第2步：计算原始综合轨。
         // 上轨：2*C上轨 - E上轨。
         // 下轨：2*C下轨 - E下轨。
         // 这一步相当于以C为基准，沿着C与E之间的距离向反方向外推。
         double rawUpper=Avg6Upper[i]-(CappedUpper[i]-Avg6Upper[i]);
         double rawLower=Avg6Lower[i]-(CappedLower[i]-Avg6Lower[i]);

         // 第3步：计算动态扩张量。
         // 当前扩张量 = |E轨 - C轨| × 动态倍率。
         // 注意：扩张量的“距离来源”是E与C的差，而不是市场实际波动幅度。
         // 潜在问题A：如果E受ATR最大半宽限制，E与C的距离可能被压小，
         //             即使行情极速，扩张量也可能跟着变小。
         // 潜在问题B：当前动态倍率的变化率计算使用B轨绝对价格作分母，
         //             例如黄金价格约4000时，2%的变化门槛约为80个价格单位，
         //             短周期内通常很难达到，倍率可能长期停留在较低档。
         // 潜在问题C：倍率下限为0.2，且这里使用MathAbs距离；
         //             当E与C的相对位置变化时，扩张量只看距离大小，不判断距离方向。
         double upperAdjustment=MathAbs(CappedUpper[i]-Avg6Upper[i])*dynUpper;
         double lowerAdjustment=MathAbs(CappedLower[i]-Avg6Lower[i])*dynLower;

         // 第4步：生成最终综合轨1。
         // 上轨 = 原始上轨 + 动态扩张量 + 人工偏移。
         // 下轨 = 原始下轨 - 动态扩张量 + 人工偏移。
         // 这里假设上轨始终向上扩张、下轨始终向下扩张。
         // 若极速区仍然过窄，应优先检查“动态倍率是否真的升高”和
         // “|E-C|这个基准距离是否过小”，不要先盲目增大倍率上限。
         Composite1Upper[i]=rawUpper+upperAdjustment+gUpperOffset[3];
         Composite1Lower[i]=rawLower-lowerAdjustment+gLowerOffset[3];
        }
      else if(channel==4)
        {
         // D「六组外沿」：六组通道上轨取最大值、下轨取最小值，独立加减显示偏移。
         double kamaHalfUp=MathMax(0.0,KAMAUpper[i]-KAMALine[i])*scale;
         double kamaHalfDown=MathMax(0.0,KAMALine[i]-KAMALower[i])*scale;
         double sixUpper[6]={FastUpper[i],KalmanUpper[i],KAMAUpper[i],MedianUpper[i],FusionUpper[i],FastLine[i]+kamaHalfUp};
         double sixLower[6]={FastLower[i],KalmanLower[i],KAMALower[i],MedianLower[i],FusionLower[i],FastLine[i]-kamaHalfDown};
         double outerUpper=sixUpper[0],outerLower=sixLower[0];
         for(int k=1;k<6;k++)
           {
            outerUpper=MathMax(outerUpper,sixUpper[k]);
            outerLower=MathMin(outerLower,sixLower[k]);
           }
         Envelope6Upper[i]=outerUpper+gUpperOffset[4];
         Envelope6Lower[i]=outerLower+gLowerOffset[4];
        }
     }
   ChartRedraw(0);
  }

// 融合轨3偏移重建：只将人工偏移加到预先计算好的基础轨上，不重算融合轨2、KAMA或ATR。
void RebuildTrack3()
  {
   if(gCachedRatesTotal<=0) return;
   int total=gCachedRatesTotal;
   for(int i=0;i<total;i++)
     {
      if(Composite3BaseUpper[i]==EMPTY_VALUE || Composite3BaseLower[i]==EMPTY_VALUE)
        {
         Composite3Upper[i]=EMPTY_VALUE;
         Composite3Lower[i]=EMPTY_VALUE;
         Composite3Middle[i]=(Composite2Middle[i]==EMPTY_VALUE ? EMPTY_VALUE : Composite2Middle[i]);
         continue;
        }
      Composite3Upper[i]=Composite3BaseUpper[i]+gTrack3UpperOffset;
      Composite3Lower[i]=Composite3BaseLower[i]+gTrack3LowerOffset;
      // 融合轨3中心线沿用融合轨2中线，不因上下轨人工偏移而改变。
      Composite3Middle[i]=Composite2Middle[i];
     }
   ChartRedraw(0);
  }

// 融合轨4偏移重建：只更新两个绘图缓冲区；综合能量、指标句柄和历史递归状态均不重算。
void RebuildTrack4()
  {
   if(gCachedRatesTotal<=0) return;
   int total=gCachedRatesTotal;
   for(int i=0;i<total;i++)
     {
      if(Composite4BaseUpper[i]==EMPTY_VALUE || Composite4BaseLower[i]==EMPTY_VALUE)
        {
         Composite4Upper[i]=EMPTY_VALUE;
         Composite4Lower[i]=EMPTY_VALUE;
         continue;
        }
      Composite4Upper[i]=Composite4BaseUpper[i]+gTrack4UpperOffset;
      Composite4Lower[i]=Composite4BaseLower[i]+gTrack4LowerOffset;
     }
   ChartRedraw(0);
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id!=CHARTEVENT_OBJECT_CLICK || StringFind(sparam,UI_PREFIX)!=0)
      return;

   for(int rail=0;rail<4;rail++)
     {
      if(sparam==LiteRailButtonName(rail))
        {
         gLiteRailVisible[rail]=!gLiteRailVisible[rail];
         ApplyPlotVisibility();
         UpdateLiteRailButtons();
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         ChartRedraw(0);
         return;
        }
     }

   if(sparam==UI_PREFIX+"TOUCH_FILTER")
     {
      gTouchSpacingFilter=!gTouchSpacingFilter;
      RefreshTouchFilterButton();
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      ChartRedraw(0);
      return;
     }

   if(sparam==DebugPanelPartName("PREV") || sparam==DebugPanelPartName("NEXT"))
     {
      int count=ArraySize(gDebugPanelLines);
      int pages=MathMax(1,(count+DEBUG_PANEL_VISIBLE_ROWS-1)/DEBUG_PANEL_VISIBLE_ROWS);
      if(sparam==DebugPanelPartName("PREV")) gDebugPanelPage=MathMax(0,gDebugPanelPage-1);
      else gDebugPanelPage=MathMin(pages-1,gDebugPanelPage+1);
      RenderDebugPanel(count,pages);
      return;
     }

   // 基础分析线“显示/参与计算”开关：显示只影响绘图；参与计算开关触发全历史重算。
   if(StringFind(sparam,UI_PREFIX+"LINE_S_")==0 || StringFind(sparam,UI_PREFIX+"LINE_U_")==0)
     {
      bool useSwitch=(StringFind(sparam,UI_PREFIX+"LINE_U_")==0); // LINE_U 按钮在盘面显示为“参与计算”
      string prefix=(useSwitch ? UI_PREFIX+"LINE_U_" : UI_PREFIX+"LINE_S_");
      int line=(int)StringToInteger(StringSubstr(sparam,StringLen(prefix)));
      if(line>=0 && line<5)
        {
         if(useSwitch)
           {
            gLineUsed[line]=!gLineUsed[line];
            UpdateLineSwitchLook(line,true);
            ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
            ChartRedraw(0);
            ForceImmediateRecalculation();
            return;
           }
         else
           {
            gLineVisible[line]=!gLineVisible[line];
            ApplyBaseLineVisibility();
           }
         UpdateLineSwitchLook(line,false);
         UpdateLineSwitchLook(line,true);
         UpdateDebugPanel();
        }
        // 【核心修改】：这里不再整表重载，而是直接调用即时重建缓冲区函数！
          RebuildTrack3();
          
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      ChartRedraw(0);
      return;
     }

   if(sparam==UI_PREFIX+"DYNAMIC")
     {
      gDynamicMultiplierEnabled=!gDynamicMultiplierEnabled;
      UpdateDynamicButtonLook();
      UpdateDebugPanel();
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      ChartRedraw(0);
      ForceImmediateRecalculation();
      return;
     }

   string t3rails[2]={"UP","DN"};
   string t3parts[3]={"DEC","VAL","INC"};
   for(int r=0;r<2;r++)
     for(int part=0;part<3;part++)
       if(sparam==Track3DeviationButtonName(t3rails[r],t3parts[part]))
         {
          string rail=t3rails[r];
          if(t3parts[part]=="VAL")
            {
             ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
             ChartRedraw(0);
             return;
            }
          double value=Track3OffsetValue(rail);
          if(t3parts[part]=="DEC") value=NormalizeDouble(value-TRACK3_OFFSET_STEP,1);
          else if(t3parts[part]=="INC") value=NormalizeDouble(value+TRACK3_OFFSET_STEP,1);
          SetTrack3OffsetValue(rail,value);
          GlobalVariableSet(RuntimeSwitchKey(rail=="UP" ? "TRACK3_UP_OFFSET_V064" : "TRACK3_DN_OFFSET_V064"),Track3OffsetValue(rail));
          UpdateTrack3DeviationButtons();
          RebuildTrack3();
          SaveRuntimeSwitches();
          ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
          ChartRedraw(0);
          return;
         }

   string t4rails[2]={"UP","DN"};
   string t4parts[3]={"DEC","VAL","INC"};
   for(int r=0;r<2;r++)
     for(int part=0;part<3;part++)
       if(sparam==Track4DeviationButtonName(t4rails[r],t4parts[part]))
         {
          string rail=t4rails[r];
          if(t4parts[part]=="VAL")
            {
             ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
             ChartRedraw(0);
             return;
            }
          double value=Track4OffsetValue(rail);
          if(t4parts[part]=="DEC") value=NormalizeDouble(value-TRACK4_OFFSET_STEP,2);
          else if(t4parts[part]=="INC") value=NormalizeDouble(value+TRACK4_OFFSET_STEP,2);
          SetTrack4OffsetValue(rail,value);
          GlobalVariableSet(RuntimeSwitchKey(rail=="UP" ? "TRACK4_UP_OFFSET_V065" : "TRACK4_DN_OFFSET_V065"),Track4OffsetValue(rail));
          UpdateTrack4DeviationButtons();
          RebuildTrack4();
          ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
          ChartRedraw(0);
          return;
         }
   if(StringFind(sparam,UI_PREFIX+"OFF_")==0)
     {
      int n=(int)StringToInteger(StringSubstr(sparam,StringLen(UI_PREFIX+"OFF_")));
      if(n>=0 && n<OFFSET_BUTTON_COUNT)
        {
         int row=n/3;
         int action=n%3;
         // 中间按钮只显示数值，不改变偏移；左右按钮分别减/加0.1。
         if(action==0 || action==2)
           {
            int channel=row/2;
            int rail=row%2;
            double delta=(action==0 ? -OFFSET_STEP : OFFSET_STEP);
            if(rail==0) gUpperOffset[channel]=NormalizeDouble(gUpperOffset[channel]+delta,1);
            else        gLowerOffset[channel]=NormalizeDouble(gLowerOffset[channel]+delta,1);
            SaveOffsets();
            RefreshOffsetRow(row);
            // 仅重建被调整通道的显示缓冲区，不重启图表、不重算基础指标。
            RebuildOffsetChannel(channel);
            if(channel==0 || channel==2 || channel==4) RebuildOffsetChannel(3);
            if(channel==4) RebuildOffsetChannel(2);
            UpdateDebugPanel();
           }
         ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
         ChartRedraw(0);
        }
      return;
     }

   int n=(int)StringToInteger(StringSubstr(sparam,StringLen(UI_PREFIX)));
   if(n>=0 && n<UI_BUTTON_COUNT)
     {
      gShow[n]=!gShow[n];
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      UpdateButtonLook(n);
      ApplyPlotVisibility();
      UpdateDebugPanel();
     }
  }

void OnDeinit(const int reason)
  {
   SaveOffsets();
   DeleteAllOwnedObjects();
   if(gTrack2MACDHandle!=INVALID_HANDLE) IndicatorRelease(gTrack2MACDHandle);
   if(gTrack2RSI7Handle!=INVALID_HANDLE) IndicatorRelease(gTrack2RSI7Handle);
   if(gTrack2RSI14Handle!=INVALID_HANDLE) IndicatorRelease(gTrack2RSI14Handle);
   if(gTrack2WPRHandle!=INVALID_HANDLE) IndicatorRelease(gTrack2WPRHandle);
   if(gTrack2ADXHandle!=INVALID_HANDLE) IndicatorRelease(gTrack2ADXHandle);
   if(gTrack4MACDHandle!=INVALID_HANDLE) IndicatorRelease(gTrack4MACDHandle);
   if(gTrack4RSI7Handle!=INVALID_HANDLE) IndicatorRelease(gTrack4RSI7Handle);
   if(gTrack4RSI17Handle!=INVALID_HANDLE) IndicatorRelease(gTrack4RSI17Handle);
   if(gTrack4WPR7Handle!=INVALID_HANDLE) IndicatorRelease(gTrack4WPR7Handle);
   if(gTrack4WPR14Handle!=INVALID_HANDLE) IndicatorRelease(gTrack4WPR14Handle);
   if(gTrack4ADXHandle!=INVALID_HANDLE) IndicatorRelease(gTrack4ADXHandle);
   if(gTrack4KDJHandle!=INVALID_HANDLE) IndicatorRelease(gTrack4KDJHandle);
  }

// 融合轨4单根K线计算：综合动能负责方向/能量，ADX负责趋势强度，ATR负责价格尺度。
// 上涨趋势时上轨驱离、下轨抬升；下跌趋势时下轨驱离、上轨下压。
// 递归驱离只读取更旧的 i+1 状态；按钮调整不调用本函数，只应用缓存偏移。
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
   // 显式统一为时间序列方向：索引 0 为当前K线，索引越大越旧。
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(open,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);

   if(rates_total<MathMax(MathMax(InpKAMA_ER_Period,InpATR_Period),InpMedian_Period)+3)
      return 0;

   ArrayResize(CompositeDynamicKUpper,rates_total);
   ArraySetAsSeries(CompositeDynamicKUpper,true);
   ArrayResize(CompositeDynamicKLower,rates_total);
   ArraySetAsSeries(CompositeDynamicKLower,true);
   gCachedRatesTotal=rates_total;
   ArrayResize(Composite3BaseUpper,rates_total); ArraySetAsSeries(Composite3BaseUpper,true);
   ArrayResize(Composite3BaseLower,rates_total); ArraySetAsSeries(Composite3BaseLower,true);
   ArrayResize(Composite4BaseUpper,rates_total); ArraySetAsSeries(Composite4BaseUpper,true);
   ArrayResize(Composite4BaseLower,rates_total); ArraySetAsSeries(Composite4BaseLower,true);
   ArrayResize(Track4DriveUpper,rates_total); ArraySetAsSeries(Track4DriveUpper,true);
   ArrayResize(Track4DriveLower,rates_total); ArraySetAsSeries(Track4DriveLower,true);
   ArrayResize(Track4Energy,rates_total); ArraySetAsSeries(Track4Energy,true);

   // 增量计算：正常行情只重算当前K线；新K线出现时重算上一根已收盘K线和当前K线。
   // 首次加载、历史数据变化或终端要求重算时，才完整计算全部历史。
   int start;
   if(gForceFullRecalc || prev_calculated<=0 || prev_calculated>rates_total)
     {
      start=rates_total-1;
      gForceFullRecalc=false;
     }
   else
      start=(int)MathMin(rates_total-1, rates_total-prev_calculated);

   ArrayResize(Atr,rates_total);
   ArrayResize(KalmanP,rates_total);
   ArrayResize(FusionRaw,rates_total);
   ArraySetAsSeries(Atr,true);
   ArraySetAsSeries(KalmanP,true);
   ArraySetAsSeries(FusionRaw,true);

   // 融合轨2所需指标读取到序列数组。融合轨4使用独立句柄，不依赖轨2的开关或参数。
   ArrayResize(Track2MACDMain,rates_total); ArraySetAsSeries(Track2MACDMain,true);
   ArrayResize(Track2MACDSignal,rates_total); ArraySetAsSeries(Track2MACDSignal,true);
   ArrayResize(Track2RSI7,rates_total); ArraySetAsSeries(Track2RSI7,true);
   ArrayResize(Track2RSI14,rates_total); ArraySetAsSeries(Track2RSI14,true);
   ArrayResize(Track2WPR,rates_total); ArraySetAsSeries(Track2WPR,true);
   ArrayResize(Track2ADX,rates_total); ArraySetAsSeries(Track2ADX,true);
   ArrayResize(Track2PlusDI,rates_total); ArraySetAsSeries(Track2PlusDI,true);
   ArrayResize(Track2MinusDI,rates_total); ArraySetAsSeries(Track2MinusDI,true);
   bool track2DataReady=true;
   if(InpEnableFusionTrack2)
     {
      if(CopyBuffer(gTrack2MACDHandle,0,0,rates_total,Track2MACDMain)<rates_total) track2DataReady=false;
      if(CopyBuffer(gTrack2MACDHandle,1,0,rates_total,Track2MACDSignal)<rates_total) track2DataReady=false;
      if(CopyBuffer(gTrack2RSI7Handle,0,0,rates_total,Track2RSI7)<rates_total) track2DataReady=false;
      if(CopyBuffer(gTrack2RSI14Handle,0,0,rates_total,Track2RSI14)<rates_total) track2DataReady=false;
      if(CopyBuffer(gTrack2WPRHandle,0,0,rates_total,Track2WPR)<rates_total) track2DataReady=false;
      if(CopyBuffer(gTrack2ADXHandle,0,0,rates_total,Track2ADX)<rates_total) track2DataReady=false;
      if(CopyBuffer(gTrack2ADXHandle,1,0,rates_total,Track2PlusDI)<rates_total) track2DataReady=false;
      if(CopyBuffer(gTrack2ADXHandle,2,0,rates_total,Track2MinusDI)<rates_total) track2DataReady=false;
      // 句柄首次加载时可能暂未准备好全部历史数据，下一次完整重算会自动补齐。
      if(!track2DataReady) gForceFullRecalc=true;
     }

   bool track4DataReady=true;
   // 融合轨4使用独立指标句柄，避免更改融合轨2参数时意外改变轨4的综合能量。
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
   if(InpEnableFusionTrack4)
     {
      if(CopyBuffer(gTrack4MACDHandle,0,0,rates_total,Track4MACDMain)<rates_total) track4DataReady=false;
      if(CopyBuffer(gTrack4MACDHandle,1,0,rates_total,Track4MACDSignal)<rates_total) track4DataReady=false;
      if(CopyBuffer(gTrack4RSI7Handle,0,0,rates_total,Track4RSI7)<rates_total) track4DataReady=false;
      if(CopyBuffer(gTrack4RSI17Handle,0,0,rates_total,Track4RSI17)<rates_total) track4DataReady=false;
      if(CopyBuffer(gTrack4WPR7Handle,0,0,rates_total,Track4WPR7)<rates_total) track4DataReady=false;
      if(CopyBuffer(gTrack4WPR14Handle,0,0,rates_total,Track4WPR14)<rates_total) track4DataReady=false;
      if(CopyBuffer(gTrack4KDJHandle,0,0,rates_total,Track4K)<rates_total) track4DataReady=false;
      if(CopyBuffer(gTrack4KDJHandle,1,0,rates_total,Track4D)<rates_total) track4DataReady=false;
      if(CopyBuffer(gTrack4ADXHandle,0,0,rates_total,Track4ADX)<rates_total) track4DataReady=false;
      if(CopyBuffer(gTrack4ADXHandle,1,0,rates_total,Track4PlusDI)<rates_total) track4DataReady=false;
      if(CopyBuffer(gTrack4ADXHandle,2,0,rates_total,Track4MinusDI)<rates_total) track4DataReady=false;
      if(!track4DataReady) gForceFullRecalc=true;
     }

   double alphaFast=2.0/(InpFastEMA_Period+1.0);
   double alphaFusion=2.0/(InpFusion_Smooth_Period+1.0);
   double fastSC=2.0/(InpKAMA_Fast_Period+1.0);
   double slowSC=2.0/(InpKAMA_Slow_Period+1.0);
   double weightSum=0.0;
   if(gLineUsed[0])   weightSum+=MathMax(0.0,InpWeight_Fast);
   if(gLineUsed[1]) weightSum+=MathMax(0.0,InpWeight_Kalman);
   if(gLineUsed[2])   weightSum+=MathMax(0.0,InpWeight_KAMA);
   if(gLineUsed[3]) weightSum+=MathMax(0.0,InpWeight_Median);

   // 从需要更新的最旧K线递推到当前K线。时间序列索引越大，K线越旧。
   for(int i=start;i>=0;i--)
   {
      double tr=high[i]-low[i];
      if(i<rates_total-1)
      {
         tr=MathMax(tr,MathAbs(high[i]-close[i+1]));
         tr=MathMax(tr,MathAbs(low[i]-close[i+1]));
         Atr[i]=(Atr[i+1]*(InpATR_Period-1)+tr)/InpATR_Period;
      }
      else
         Atr[i]=tr;

      double atrValue=MathMax(Atr[i],_Point*2.0);

      // 1. 快速响应线：低周期EMA，目标是先反映变化，不追求过度平滑。
      if(i==rates_total-1)
         FastLine[i]=close[i];
      else
         FastLine[i]=alphaFast*close[i]+(1.0-alphaFast)*FastLine[i+1];

      // 2. 卡尔曼原线：独立使用收盘价作为观测，不耦合其他指标分数。
      double q=atrValue*atrValue*InpKalman_Q_Factor;
      double r=atrValue*atrValue*InpKalman_R_Factor;
      if(i==rates_total-1)
      {
         KalmanLine[i]=close[i];
         KalmanP[i]=MathMax(r,1.0e-8);
      }
      else
      {
         double predictedP=KalmanP[i+1]+q;
         double gain=predictedP/(predictedP+r);
         gain=ClampValue(gain,0.01,0.99);
         KalmanLine[i]=KalmanLine[i+1]+gain*(close[i]-KalmanLine[i+1]);
         KalmanP[i]=(1.0-gain)*predictedP;
      }

      // 3. KAMA：效率比控制快慢。
      if(i==rates_total-1)
         KAMALine[i]=close[i];
      else
      {
         int oldIndex=MathMin(rates_total-1,i+InpKAMA_ER_Period);
         double change=MathAbs(close[i]-close[oldIndex]);
         double volatility=0.0;
         int endIndex=MathMin(rates_total-1,i+InpKAMA_ER_Period-1);
         for(int j=i;j<=endIndex;j++)
         {
            int next=j+1;
            if(next<rates_total)
               volatility+=MathAbs(close[j]-close[next]);
         }
         double er=(volatility>0.0 ? change/volatility : 0.0);
         er=ClampValue(er,0.0,1.0);
         double sc=er*(fastSC-slowSC)+slowSC;
         sc*=sc;
         KAMALine[i]=KAMALine[i+1]+sc*(close[i]-KAMALine[i+1]);
      }

      // 4. 局部中位结构线：窗口只使用当前及更旧K线。
      MedianLine[i]=MedianAt(i,InpMedian_Period,rates_total,high,low);

      // 5. 原始融合线：四条基础线等输入后按权重融合，可独立调节权重。
      double fusionSum=0.0;
      if(gLineUsed[0])   fusionSum+=MathMax(0.0,InpWeight_Fast)*FastLine[i];
      if(gLineUsed[1]) fusionSum+=MathMax(0.0,InpWeight_Kalman)*KalmanLine[i];
      if(gLineUsed[2])   fusionSum+=MathMax(0.0,InpWeight_KAMA)*KAMALine[i];
      if(gLineUsed[3]) fusionSum+=MathMax(0.0,InpWeight_Median)*MedianLine[i];
      FusionRaw[i]=(weightSum>0.0 ? fusionSum/weightSum : close[i]);

      if(i==rates_total-1 || InpFusion_Smooth_Period==1)
         FusionLine[i]=FusionRaw[i];
      else
         FusionLine[i]=alphaFusion*FusionRaw[i]+(1.0-alphaFusion)*FusionLine[i+1];
   }

   // 各条线独立计算残差宽度。先完整生成五条线，再生成各自上下轨。
   for(int i=start;i>=0;i--)
   {
      double atrValue=MathMax(Atr[i],_Point*2.0);
      double minHalf=atrValue*InpATR_Min_Multiplier;

      double wFast=MathMax(minHalf,ResidualRMSAt(i,InpResidual_Period,rates_total,close,FastLine)*InpResidual_Multiplier)*InpFast_Width_Mult;
      double wKalman=MathMax(minHalf,ResidualRMSAt(i,InpResidual_Period,rates_total,close,KalmanLine)*InpResidual_Multiplier)*InpKalman_Width_Mult;
      double wKAMA=MathMax(minHalf,ResidualRMSAt(i,InpResidual_Period,rates_total,close,KAMALine)*InpResidual_Multiplier)*InpKAMA_Width_Mult;
      double wMedian=MathMax(minHalf,ResidualRMSAt(i,InpResidual_Period,rates_total,close,MedianLine)*InpResidual_Multiplier)*InpMedian_Width_Mult;
      double wFusion=MathMax(minHalf,ResidualRMSAt(i,InpResidual_Period,rates_total,close,FusionLine)*InpResidual_Multiplier)*InpFusion_Width_Mult;

      FastUpper[i]=FastLine[i]+wFast;
      FastLower[i]=FastLine[i]-wFast;
      KalmanUpper[i]=KalmanLine[i]+wKalman;
      KalmanLower[i]=KalmanLine[i]-wKalman;
      KAMAUpper[i]=KAMALine[i]+wKAMA;
      KAMALower[i]=KAMALine[i]-wKAMA;
      MedianUpper[i]=MedianLine[i]+wMedian;
      MedianLower[i]=MedianLine[i]-wMedian;
      FusionUpper[i]=FusionLine[i]+wFusion;
      FusionLower[i]=FusionLine[i]-wFusion;

      // 新实验：通道中心使用快速线，宽度直接借用KAMA原通道的上下半宽。
      // 不使用快速线自身残差重新计算宽度，避免把中心与宽度来源混在一起。
      double kamaHalfUp=MathMax(0.0,KAMAUpper[i]-KAMALine[i]);
      double kamaHalfDown=MathMax(0.0,KAMALine[i]-KAMALower[i]);
      double scale=MathMax(0.01,InpFast_KAMAWidth_Scale);
      FastKAMAWidthUpper[i]=FastLine[i]+kamaHalfUp*scale+gUpperOffset[1];
      FastKAMAWidthLower[i]=FastLine[i]-kamaHalfDown*scale+gLowerOffset[1];
      double baseKAMAWidthUpper=FastLine[i]+kamaHalfUp*scale;
      double baseKAMAWidthLower=FastLine[i]-kamaHalfDown*scale;

      // 五条基础通道引用状态。显示开关不参与这里的判断，只由 InpUse_* 控制计算引用。
      double baseUpper[5]={FastUpper[i],KalmanUpper[i],KAMAUpper[i],MedianUpper[i],FusionUpper[i]};
      double baseLower[5]={FastLower[i],KalmanLower[i],KAMALower[i],MedianLower[i],FusionLower[i]};
      bool useBase[5]={gLineUsed[0],gLineUsed[1],gLineUsed[2],gLineUsed[3],gLineUsed[4]};
      double sum5U=0.0,sum5L=0.0; int count5=0;
      for(int k=0;k<5;k++)
        if(useBase[k]) { sum5U+=baseUpper[k]; sum5L+=baseLower[k]; count5++; }
      Avg5Upper[i]=(count5>0 ? sum5U/count5 : EMPTY_VALUE);
      Avg5Lower[i]=(count5>0 ? sum5L/count5 : EMPTY_VALUE);

      // B：仅当快速线与KAMA线都允许被引用时，才把“快速线中心+KAMA宽度”作为候选组。
      bool useKAMAWidth=(gLineUsed[0] && gLineUsed[2]);
      if(count5>0 && useKAMAWidth)
        {
         NewVsAvgUpper[i]=MathMax(baseKAMAWidthUpper,Avg5Upper[i])+gUpperOffset[0];
         NewVsAvgLower[i]=MathMin(baseKAMAWidthLower,Avg5Lower[i])+gLowerOffset[0];
        }
      else if(count5>0)
        {
         NewVsAvgUpper[i]=Avg5Upper[i]+gUpperOffset[0];
         NewVsAvgLower[i]=Avg5Lower[i]+gLowerOffset[0];
        }
      else if(useKAMAWidth)
        {
         NewVsAvgUpper[i]=baseKAMAWidthUpper+gUpperOffset[0];
         NewVsAvgLower[i]=baseKAMAWidthLower+gLowerOffset[0];
        }
      else { NewVsAvgUpper[i]=EMPTY_VALUE; NewVsAvgLower[i]=EMPTY_VALUE; }

      // C/D/E/综合轨1：只汇总被允许引用的基础通道；KAMA宽度通道需快速线与KAMA线同时启用引用。
      double sum6U=0.0,sum6L=0.0,outerUpper=0.0,outerLower=0.0; int count6=0;
      for(int k=0;k<5;k++)
        if(useBase[k])
          {
           sum6U+=baseUpper[k]; sum6L+=baseLower[k];
           if(count6==0) { outerUpper=baseUpper[k]; outerLower=baseLower[k]; }
           else { outerUpper=MathMax(outerUpper,baseUpper[k]); outerLower=MathMin(outerLower,baseLower[k]); }
           count6++;
          }
      if(useKAMAWidth)
        {
         sum6U+=baseKAMAWidthUpper; sum6L+=baseKAMAWidthLower;
         if(count6==0) { outerUpper=baseKAMAWidthUpper; outerLower=baseKAMAWidthLower; }
         else { outerUpper=MathMax(outerUpper,baseKAMAWidthUpper); outerLower=MathMin(outerLower,baseKAMAWidthLower); }
         count6++;
        }
      Avg6Upper[i]=(count6>0 ? sum6U/count6 : EMPTY_VALUE);
      Avg6Lower[i]=(count6>0 ? sum6L/count6 : EMPTY_VALUE);
      Envelope6Upper[i]=(count6>0 ? outerUpper+gUpperOffset[4] : EMPTY_VALUE);
      Envelope6Lower[i]=(count6>0 ? outerLower+gLowerOffset[4] : EMPTY_VALUE);

      // E【本版】：C六组平均与D替代版（同样为六组平均）按混合比例融合，再限制最大半宽。
      // 因为C=D，所以无论混合比例为多少，混合前的rawUpper/rawLower都等于六组平均。
      // InpCappedBlend暂时保留，方便将来恢复旧D外沿算法后继续测试。
      double blend=ClampValue(InpCappedBlend,0.0,1.0);
      if(count6>0)
        {
         double rawUpper=Avg6Upper[i]+((outerUpper)-Avg6Upper[i])*blend;
         double rawLower=Avg6Lower[i]-(Avg6Lower[i]-(outerLower))*blend;
         double maxHalf=MathMax(atrValue*InpMaxHalfWidth_ATR,_Point*2.0);
         CappedUpper[i]=MathMin(rawUpper,FastLine[i]+maxHalf)+gUpperOffset[2];
         CappedLower[i]=MathMax(rawLower,FastLine[i]-maxHalf)+gLowerOffset[2];
        }
      else { CappedUpper[i]=EMPTY_VALUE; CappedLower[i]=EMPTY_VALUE; }

      // F：只对允许引用的基础通道取中位数，0条时不绘制。
      double ups[5],dns[5]; int medianCount=0;
      for(int k=0;k<5;k++) if(useBase[k]) { ups[medianCount]=baseUpper[k]; dns[medianCount]=baseLower[k]; medianCount++; }
      for(int a=1;a<medianCount;a++)
        {
         double keyU=ups[a],keyD=dns[a]; int b=a-1;
         while(b>=0 && ups[b]>keyU){ups[b+1]=ups[b];b--;}
         ups[b+1]=keyU;
         b=a-1;
         while(b>=0 && dns[b]>keyD){dns[b+1]=dns[b];b--;}
         dns[b+1]=keyD;
        }
      if(medianCount>0)
        {
         int mid=medianCount/2;
         if((medianCount%2)==1) { Median5Upper[i]=ups[mid]; Median5Lower[i]=dns[mid]; }
         else { Median5Upper[i]=(ups[mid-1]+ups[mid])*0.5; Median5Lower[i]=(dns[mid-1]+dns[mid])*0.5; }
        }
      else { Median5Upper[i]=EMPTY_VALUE; Median5Lower[i]=EMPTY_VALUE; }

      //================================================================
      // 【综合轨1最终轨道公式区：每行对应一条公式说明】
      // 六组通道平均上轨 Avg6Upper：快速通道上轨 FastUpper、卡尔曼通道上轨 KalmanUpper、KAMA通道上轨 KAMAUpper、中位结构通道上轨 MedianUpper、融合通道上轨 FusionUpper、快速线中心KAMA宽度通道上轨 FastKAMAWidthUpper，六者相加后除以6。
      // 六组通道平均下轨 Avg6Lower：快速通道下轨 FastLower、卡尔曼通道下轨 KalmanLower、KAMA通道下轨 KAMALower、中位结构通道下轨 MedianLower、融合通道下轨 FusionLower、快速线中心KAMA宽度通道下轨 FastKAMAWidthLower，六者相加后除以6。
      // 限宽融合通道上轨 CappedUpper：先将六组通道平均上轨与六组通道外沿上轨按混合系数 blend 插值，再限制在“快速响应线 FastLine + ATR最大半宽 maxHalf”以内，最后加上限宽融合通道上轨位移 gUpperOffset[2]。
      // 限宽融合通道下轨 CappedLower：先将六组通道平均下轨与六组通道外沿下轨按混合系数 blend 插值，再限制在“快速响应线 FastLine - ATR最大半宽 maxHalf”以外，最后加上限宽融合通道下轨位移 gLowerOffset[2]。
      // 外沿比较通道上轨 NewVsAvgUpper：快速线中心KAMA宽度通道上轨与五条基础通道上轨均值 Avg5Upper 取较大值，再加 gUpperOffset[0]。
      // 外沿比较通道下轨 NewVsAvgLower：快速线中心KAMA宽度通道下轨与五条基础通道下轨均值 Avg5Lower 取较小值，再加 gLowerOffset[0]。动态倍率函数使用这两条轨道的窗口均值与最新已收盘值计算倍率。
      // 综合轨1上轨位移 gUpperOffset[3]、综合轨1下轨位移 gLowerOffset[3]：由界面对应的加减按钮调整并保存，只作用于综合轨1最终显示值。
      //================================================================
      // 融合轨4独立于A-F组合轨的引用成员开关，基于快速线中心/KAMA基础宽度和综合动能计算。
      CalculateTrack4At(i,rates_total,open,close,track4DataReady);

      if(count6<=0 || Avg6Upper[i]==EMPTY_VALUE || CappedUpper[i]==EMPTY_VALUE)
        {
         Composite1Upper[i]=EMPTY_VALUE; Composite1Lower[i]=EMPTY_VALUE;
         Composite2Upper[i]=EMPTY_VALUE; Composite2Lower[i]=EMPTY_VALUE; Composite2Middle[i]=EMPTY_VALUE;
         Composite3Upper[i]=EMPTY_VALUE; Composite3Lower[i]=EMPTY_VALUE; Composite3Middle[i]=EMPTY_VALUE;
         Composite3BaseUpper[i]=EMPTY_VALUE; Composite3BaseLower[i]=EMPTY_VALUE;
         continue;
        }
      double rawCompositeUpper=Avg6Upper[i]-(CappedUpper[i]-Avg6Upper[i]); // 综合轨1原始上轨 = 六组通道平均上轨 Avg6Upper - (限宽融合通道上轨 CappedUpper - 六组通道平均上轨 Avg6Upper)，代数等价于 2×Avg6Upper - CappedUpper；此处尚未加入动态调整量和综合轨1上轨人工位移。
      double rawCompositeLower=Avg6Lower[i]-(CappedLower[i]-Avg6Lower[i]); // 综合轨1原始下轨 = 六组通道平均下轨 Avg6Lower - (限宽融合通道下轨 CappedLower - 六组通道平均下轨 Avg6Lower)，代数等价于 2×Avg6Lower - CappedLower；此处尚未加入动态调整量和综合轨1下轨人工位移。
      CompositeDynamicKUpper[i]=CalculateCompositeRailMultiplier(i,rates_total,true); // 计算综合轨1上轨动态倍率：读取外沿比较通道上轨 NewVsAvgUpper，比较其窗口均值与最新已收盘值，按输入参数平滑并映射到倍率范围；true 指定使用上轨。
      CompositeDynamicKLower[i]=CalculateCompositeRailMultiplier(i,rates_total,false); // 计算综合轨1下轨动态倍率：读取外沿比较通道下轨 NewVsAvgLower，比较其窗口均值与最新已收盘值，按输入参数平滑并映射到倍率范围；false 指定使用下轨，上下轨分别计算。
      double upperAdjustment=MathAbs(CappedUpper[i]-Avg6Upper[i])*CompositeDynamicKUpper[i]; // 综合轨1上轨动态调整量 = 限宽融合通道上轨 CappedUpper 与六组通道平均上轨 Avg6Upper 的绝对距离 × 综合轨1上轨动态倍率 CompositeDynamicKUpper；MathAbs 仅保留距离大小，不保留 CappedUpper 位于 Avg6Upper 上方还是下方的信息。
      double lowerAdjustment=MathAbs(CappedLower[i]-Avg6Lower[i])*CompositeDynamicKLower[i]; // 综合轨1下轨动态调整量 = 限宽融合通道下轨 CappedLower 与六组通道平均下轨 Avg6Lower 的绝对距离 × 综合轨1下轨动态倍率 CompositeDynamicKLower；MathAbs 仅保留距离大小，不保留 CappedLower 位于 Avg6Lower 上方还是下方的信息。
      Composite1Upper[i]=rawCompositeUpper+upperAdjustment+gUpperOffset[3]; // 综合轨1最终上轨 = 综合轨1原始上轨 rawCompositeUpper + 上轨动态调整量 upperAdjustment + 综合轨1上轨人工位移 gUpperOffset[3]；人工位移为正则上移，为负则下移。
      Composite1Lower[i]=rawCompositeLower-lowerAdjustment+gLowerOffset[3]; // 综合轨1最终下轨 = 综合轨1原始下轨 rawCompositeLower - 下轨动态调整量 lowerAdjustment + 综合轨1下轨人工位移 gLowerOffset[3]；人工位移为正则上移，为负则下移。

      //================================================================
      // 【融合轨2：动能衰竭与极值磁吸实验，v0.61增加最小宽度保护和中线】
      // 融合轨1保持原样。融合轨2单独读取MACD、RSI(7/14)、威廉指标、ADX及+DI/-DI。
      // ATR只作为价格尺度和最大位移限制，不参加多空投票。
      // 所有动能确认使用 i+1 及更旧的已收盘K线，避免盘中指标抖动回写历史。
      //================================================================
      if(!InpEnableFusionTrack2 || !track2DataReady || i+3>=rates_total)
        {
         Composite2Upper[i]=EMPTY_VALUE;
         Composite2Lower[i]=EMPTY_VALUE;
         Composite2Middle[i]=EMPTY_VALUE;
         Composite3Upper[i]=EMPTY_VALUE;
         Composite3Lower[i]=EMPTY_VALUE;
         Composite3Middle[i]=EMPTY_VALUE;
         Composite3BaseUpper[i]=EMPTY_VALUE;
         Composite3BaseLower[i]=EMPTY_VALUE;
        }
      else
        {
         int lb=MathMax(2,InpTrack2_ExtremeLookback);
         double recentHigh=high[i+1],recentLow=low[i+1];
         int validExtreme=0;
         for(int j=i+1;j<i+1+lb && j<rates_total;j++)
           {
            recentHigh=MathMax(recentHigh,high[j]);
            recentLow=MathMin(recentLow,low[j]);
            validExtreme++;
           }
         double atrScale=MathMax(Atr[i+1],_Point*2.0);
         double velocityNow=(close[i+1]-close[i+2])/atrScale;
         double velocityBefore=(close[i+2]-close[i+3])/MathMax(Atr[i+2],_Point*2.0);
         double speedNow=MathAbs(velocityNow);
         double speedBefore=MathAbs(velocityBefore);
         double deceleration=ClampValue((speedBefore-speedNow)/(MathMax(speedBefore,0.08)),0.0,1.0);
         double macdHist=Track2MACDMain[i+1]-Track2MACDSignal[i+1];
         double macdHistOlder=Track2MACDMain[i+2]-Track2MACDSignal[i+2];
         double rsiFast=Track2RSI7[i+1];
         double rsiSlow=Track2RSI14[i+1];
         double wpr=Track2WPR[i+1];
         double adx=Track2ADX[i+1];
         double plusDI=Track2PlusDI[i+1];
         double minusDI=Track2MinusDI[i+1];

         // 上轨风险：上涨速度减弱、MACD柱缩短、短RSI相对长RSI转弱、威廉极值共同提高磁吸评分。
         double upperMacdWeak=(macdHist>0.0 && macdHist<macdHistOlder) ? 1.0 : 0.0;
         double lowerMacdWeak=(macdHist<0.0 && macdHist>macdHistOlder) ? 1.0 : 0.0;
         double upperRsiWeak=ClampValue((rsiFast-rsiSlow+8.0)/20.0,0.0,1.0);
         double lowerRsiWeak=ClampValue((rsiSlow-rsiFast+8.0)/20.0,0.0,1.0);
         double upperWprExtreme=ClampValue((wpr+45.0)/25.0,0.0,1.0);
         double lowerWprExtreme=ClampValue((-55.0-wpr)/25.0,0.0,1.0);
         double upDirection=(velocityNow>0.0 ? 1.0 : 0.0);
         double downDirection=(velocityNow<0.0 ? 1.0 : 0.0);
         double upperDIDivergence=(plusDI<minusDI ? 1.0 : 0.0);
         double lowerDIDivergence=(minusDI<plusDI ? 1.0 : 0.0);
         double upperExhaustion=ClampValue(0.38*deceleration+0.22*upperMacdWeak+0.18*upperRsiWeak+0.12*upperWprExtreme+0.10*upperDIDivergence,0.0,1.0)*upDirection;
         double lowerExhaustion=ClampValue(0.38*deceleration+0.22*lowerMacdWeak+0.18*lowerRsiWeak+0.12*lowerWprExtreme+0.10*lowerDIDivergence,0.0,1.0)*downDirection;

         // ADX较强时不直接否定衰竭，但削弱磁吸，减少强趋势中提前贴顶或贴底。
         double trendGuard=1.0;
         if(adx>InpTrack2_ADX_TrendGuard && speedNow>speedBefore)
            trendGuard=0.35;
         else if(adx>InpTrack2_ADX_TrendGuard)
            trendGuard=0.70;
         double pullCap=atrScale*MathMax(0.0,InpTrack2_MaxPull_ATR);

         // 先把融合轨1上下轨规范化，避免原轨道因公式外推而出现上下颠倒。
         double baseUpper=MathMax(Composite1Upper[i],Composite1Lower[i]);
         double baseLower=MathMin(Composite1Upper[i],Composite1Lower[i]);
         double baseWidth=baseUpper-baseLower;

         double upperGap=MathMax(0.0,baseUpper-recentHigh);
         double lowerGap=MathMax(0.0,recentLow-baseLower);
         double upperPull=MathMin(pullCap,upperGap*ClampValue(InpTrack2_MagnetIntensity,0.0,1.0)*upperExhaustion*trendGuard);
         double lowerPull=MathMin(pullCap,lowerGap*ClampValue(InpTrack2_MagnetIntensity,0.0,1.0)*lowerExhaustion*trendGuard);

         double candidateUpper=baseUpper-upperPull;
         double candidateLower=baseLower+lowerPull;

         // 核心修复：不能只在上下轨交叉后扩成2个点，否则两条线会肉眼合并。
         // 最小宽度取原轨宽度的35%、0.25 ATR、20个点三者最大值。
         double minimumWidth=MathMax(MathMax(baseWidth*0.35,atrScale*0.25),_Point*20.0);
         double candidateWidth=candidateUpper-candidateLower;
         if(candidateWidth<minimumWidth)
           {
            double repairedMiddle=(candidateUpper+candidateLower)*0.5;
            candidateUpper=repairedMiddle+minimumWidth*0.5;
            candidateLower=repairedMiddle-minimumWidth*0.5;
           }

         Composite2Upper[i]=candidateUpper;
         Composite2Lower[i]=candidateLower;
         Composite2Middle[i]=(candidateUpper+candidateLower)*0.5;

         // 融合轨3基础公式：不乘系数。
         // 上轨 = KAMA上轨 - 融合轨2上半宽；下轨 = KAMA下轨 + 融合轨2下半宽。
         // 两个独立按钮只负责将对应轨道整体上下平移，规则与D六组外沿、KAMA宽度等轨道一致。
         // 融合轨3基础公式：严格以融合轨2的中线（Composite2Middle）为基准。
         // 上轨 = 轨2中线 - 轨2上半宽 + 上轨独立偏移；
         // 下轨 = 轨2中线 + 轨2下半宽 + 下轨独立偏移。
         // t+="融合轨3：基准中线=融合轨2中线；上轨=轨2中线-轨2上半宽+上轨偏移；下轨=轨2中线+轨2下半宽+下轨偏移；均线轨=(上轨+下轨)/2。上下轨按钮负责独立平移，每次调整0.1；上轨偏移="+DoubleToString(gTrack3UpperOffset,1)+"，下轨偏移="+DoubleToString(gTrack3LowerOffset,1)+"。\r\n";
         // 融合轨3基础公式：严格按照您的调制逻辑
         // 1. 获取融合轨2的中线作为基准锚点
         double track2Middle = Composite2Middle[i];
         
         // 2. 获取融合轨2的上下半宽（到中线的距离）
         double track2UpperHalf = Composite2Upper[i] - track2Middle;
         double track2LowerHalf = track2Middle - Composite2Lower[i];
         
         // 3. 融合轨3基础公式：KAMA上轨减去融合轨2上半宽；KAMA下轨加上融合轨2下半宽。
         // 人工偏移与基础计算分离，只在输出阶段叠加，按钮点击不会重算动能/ATR/KAMA。
         Composite3BaseUpper[i]=KAMAUpper[i]-track2UpperHalf;
         Composite3BaseLower[i]=KAMALower[i]+track2LowerHalf;
         Composite3Upper[i]=Composite3BaseUpper[i]+gTrack3UpperOffset;
         Composite3Lower[i]=Composite3BaseLower[i]+gTrack3LowerOffset;
         // 中线继续沿用融合轨2中线，不随上下轨独立人工偏移改变。
         Composite3Middle[i]=track2Middle;
        }
   }
   UpdateTouchArrowsAndStats(rates_total,time,open,high,low,close);
   return rates_total;
}
//+------------------------------------------------------------------+
