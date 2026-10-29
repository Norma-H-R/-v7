//+------------------------------------------------------------------+
//| NMNX_ChannelFusion_Lab_v0_65_Lite.mq5                            |
//| 南门拈星：融合轨4轻量版，保留原版触轨统计面板与原按钮构造方式。    |
//| 仅计算并显示KAMA宽度参考轨与融合轨4；保留触轨统计。                |
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
#property version   "000.660"
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
double Track4MACDMain[],Track4MACDSignal[],Track4RSI7[],Track4RSI17[];
double Track4WPR7[],Track4WPR14[],Track4K[],Track4D[],Track4ADX[],Track4PlusDI[],Track4MinusDI[];
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
//【算法逐行备注：动态倍率的输入变化率】
// 本函数计算 B 外沿比较通道某一条轨道的变化率；不直接计算价格涨跌幅。
// 参数 i：当前正在计算的指标缓冲区索引；MT5 序列数组通常以 0 表示最新K线。
// 参数 total：当前可用K线总数，用来防止访问数组范围之外的数据。
// 参数 channelUpper：true 表示读取“快速线中心KAMA宽度通道与五条基础通道上轨均值比较后形成的外沿比较通道”的上轨 NewVsAvgUpper；false 表示读取该外沿比较通道的下轨 NewVsAvgLower。
//【算法逐行备注：把变化率换算成综合轨1的动态倍率】
// 注意：此倍率只影响综合轨1最终上下轨的扩张/收缩项，不改变 C、E 通道自身的计算。
// 输入参数 InpEnableCompositeDynamicMultiplier：动态倍率总开关；关闭时直接返回固定倍率1.0。
// 输入参数 InpCompositeMaxMultiplier：用户设定的倍率上限，具体取值由 CompositeMaxMultiplierValue() 读取。
// 输入参数 InpCompositeSmoothing：对多少个相邻计算索引的变化率进行平均；最少为1。
// 当前算法的关键阈值是固定的 0.02，即相对变化率达到2%时，归一化值封顶为1。
// 低变化区倍率下限固定为0.20；因此该算法的倍率范围为 0.20 至用户设定的最大倍率。
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
bool gStatsEnabled=true; // 关闭后不运行历史盈亏统计计算
bool gStatsDirty=true; // 轨道偏移或新K线出现后需要刷新统计
bool gArrowDirty=true; // 融合轨4偏移后重建触轨箭头
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
   key=RuntimeSwitchKey("TRACK3_DN_OFFSET_V064");
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
   t+="轻量版计算链：KAMA宽度参考轨使用快速响应线、KAMA中线、ATR与残差均方根宽度；融合轨4在此基础上结合动能指标计算驱离量。旧综合轨动态倍率计算已删除。\\r\\n\\r\\n";

   t+="四、实时参与状态总表（每次开关切换后自动刷新）\r\n";
   t+="基础线："+DebugLineState(0)+"；"+DebugLineState(1)+"；"+DebugLineState(2)+"。\r\n";
   t+="基础线："+DebugLineState(3)+"；"+DebugLineState(4)+"。\r\n";
   t+="通道绘制：快速="+OnOffText(gShow[0])+"，卡尔曼="+OnOffText(gShow[1])+"，KAMA="+OnOffText(gShow[2])+"，中位="+OnOffText(gShow[3])+"，融合="+OnOffText(gShow[4])+"，KAMA宽度="+OnOffText(gShow[5])+"。\r\n";
   t+="组合绘制：A均值="+OnOffText(gShow[6])+"，B外沿="+OnOffText(gShow[7])+"，C六组平均="+OnOffText(gShow[8])+"，D六组外沿="+OnOffText(gShow[9])+"，E限宽="+OnOffText(gShow[10])+"，F五线中位="+OnOffText(gShow[11])+"，综合轨1="+OnOffText(gShow[12])+"，融合轨2="+OnOffText(gShow[13])+"，融合轨3="+OnOffText(gShow[14])+"，融合轨4="+OnOffText(gShow[15])+"。\r\n";
   t+="当前轻量版保留KAMA宽度参考上下轨、融合轨4上下轨、触轨箭头及统计面板；融合轨2、融合轨3和旧组合轨计算已停用。\\r\\n";
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
string StatsToggleButtonName() { return UI_PREFIX+"STATS_TOGGLE"; }
void CreateStatsToggleButton()
  {
   string name=StatsToggleButtonName();
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
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
   UpdateStatsToggleButton();
  }
void UpdateStatsToggleButton()
  {
   string name=StatsToggleButtonName();
   if(ObjectFind(0,name)<0) return;
   ObjectSetString(0,name,OBJPROP_TEXT,gStatsEnabled?"统计面板与统计计算：[开]":"统计面板与统计计算：[关]");
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,gStatsEnabled?clrDarkGreen:clrDimGray);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrSilver);
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
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
void CreateLiteKamaOffsetButtons()
  {
   // 仅创建KAMA宽度参考轨的上下偏移控制。
   for(int n=6;n<=11;n++)
     {
      string name=UI_PREFIX+"OFF_"+IntegerToString(n);
      if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
      ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
      int row=n/3,action=n%3;
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,(action==0?12:(action==1?48:190)));
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,625+(row-2)*25);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,(action==1?138:32));
      ObjectSetInteger(0,name,OBJPROP_YSIZE,22);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
      ObjectSetInteger(0,name,OBJPROP_STATE,false);
      UpdateOffsetButtonLook(n);
     }
  }
void UpdateTouchArrowsOnly(const int rates_total,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[])
  {
   if(rates_total<3) return;
   ArrayInitialize(SellTouchArrow,EMPTY_VALUE);
   ArrayInitialize(BuyTouchArrow,EMPTY_VALUE);
   int lastAcceptedTouchIndex=-1,lastAcceptedTouchDirection=0;
   for(int i=rates_total-1;i>=1;i--)
     {
      if(Composite4Upper[i]==EMPTY_VALUE || Composite4Lower[i]==EMPTY_VALUE ||
         !MathIsValidNumber(Composite4Upper[i]) || !MathIsValidNumber(Composite4Lower[i])) continue;
      bool upper=(high[i]>=Composite4Upper[i]),lower=(low[i]<=Composite4Lower[i]);
      if(!upper && !lower) continue;
      int direction=(lower&&!upper?1:(upper&&!lower?-1:0));
      bool opposite=(direction!=0 && lastAcceptedTouchDirection!=0 && direction!=lastAcceptedTouchDirection);
      if(gTouchSpacingFilter && !opposite && direction!=0 && lastAcceptedTouchIndex>=0 &&
         (lastAcceptedTouchIndex-i)<3 && direction==lastAcceptedTouchDirection) continue;
      if(upper) SellTouchArrow[i]=Composite4Upper[i];
      if(lower) BuyTouchArrow[i]=Composite4Lower[i];
      lastAcceptedTouchIndex=i;
      lastAcceptedTouchDirection=direction;
     }
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
      ObjectSetString(0,name,OBJPROP_TEXT,labels[i]+(gLiteRailVisible[i]?" [显示]":" [隐藏]"));
      ObjectSetInteger(0,name,OBJPROP_BGCOLOR,gLiteRailVisible[i] ? C'35,95,75' : C'65,65,65');
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,gLiteRailVisible[i] ? clrLimeGreen : clrDimGray);
      ObjectSetInteger(0,name,OBJPROP_STATE,false);
     }
  }

void CreateLiteRailButtons()
  {

   int xs[4]={250,385,520,655};
   int ys[4]={675,675,700,700};
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

void UpdateTouchArrowsLatestBar(const int rates_total,const double &high[],const double &low[])
  {
   if(rates_total<3) return;
   SellTouchArrow[0]=EMPTY_VALUE;
   BuyTouchArrow[0]=EMPTY_VALUE;
   int i=1;
   if(Composite4Upper[i]==EMPTY_VALUE || Composite4Lower[i]==EMPTY_VALUE ||
      !MathIsValidNumber(Composite4Upper[i]) || !MathIsValidNumber(Composite4Lower[i])) return;
   bool upper=(high[i]>=Composite4Upper[i]);
   bool lower=(low[i]<=Composite4Lower[i]);
   if(!upper && !lower) return;
   int direction=(lower&&!upper?1:(upper&&!lower?-1:0));
   if(gTouchSpacingFilter && direction!=0)
     {
      for(int j=2;j<=3 && j<rates_total;j++)
        {
         int prior=(BuyTouchArrow[j]!=EMPTY_VALUE && SellTouchArrow[j]==EMPTY_VALUE ? 1 :
                    (SellTouchArrow[j]!=EMPTY_VALUE && BuyTouchArrow[j]==EMPTY_VALUE ? -1 : 0));
         if(prior==direction && (j-i)<3) return;
         if(prior!=0 && prior!=direction) break;
        }
     }
   if(upper) SellTouchArrow[i]=Composite4Upper[i];
   if(lower) BuyTouchArrow[i]=Composite4Lower[i];
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
   ArrayResize(activeEntryPrices,rates_total);
   ArrayResize(activeEntryTimes,rates_total);
   int activeCount=0;
   int activeDirection=0; // +1多头，-1空头
   double activeEntryPriceSum=0.0; // 用入场价总和计算篮子浮盈，避免每根K线遍历所有持仓

   for(int i=rates_total-1;i>=1;i--)
     {
      // 每根K线按收盘价估算仍未平仓篮子的浮动盈亏，记录最深浮亏；该值是历史K线近似值。
      if(activeCount>0)
        {
         double floatingPoints=(activeDirection==1
                                ? (activeCount*close[i]-activeEntryPriceSum)
                                : (activeEntryPriceSum-activeCount*close[i]))*10.0;
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
         activeEntryPrices[activeCount]=GetTouchExecutionPrice(direction,i,open,Composite4Upper,Composite4Lower);
         activeEntryTimes[activeCount]=time[i];
         activeEntryPriceSum+=activeEntryPrices[activeCount];
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
      activeEntryPrices[0]=GetTouchExecutionPrice(direction,i,open,Composite4Upper,Composite4Lower);
      activeEntryTimes[0]=time[i];
      activeEntryPriceSum=activeEntryPrices[0];
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
      InpATR_Period<1 || InpResidual_Period<1)
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
   gShow[13]=false;
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
   gShow[13]=false;
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
   PlotIndexSetInteger(31,PLOT_DRAW_TYPE,false ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(32,PLOT_DRAW_TYPE,false ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(33,PLOT_DRAW_TYPE,false ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(34,PLOT_DRAW_TYPE,false ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(35,PLOT_DRAW_TYPE,false ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(36,PLOT_DRAW_TYPE,false ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(37,PLOT_DRAW_TYPE,InpEnableFusionTrack4 ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(38,PLOT_DRAW_TYPE,InpEnableFusionTrack4 ? DRAW_LINE : DRAW_NONE);
   ApplyPlotVisibility();
   // 精简盘面：隐藏原多通道按钮和调试面板，只保留统计面板与四条目标轨道/箭头。
   if(gStatsEnabled) CreateStatsPanel();
   CreateStatsToggleButton();
   CreateTouchFilterButton();
   CreateLiteKamaOffsetButtons();
   CreateTrack4DeviationButtons();
   CreateLiteRailButtons();

   gTrack4MACDHandle=iMACD(_Symbol,_Period,InpTrack4_MACD_Fast,InpTrack4_MACD_Slow,InpTrack4_MACD_Signal,PRICE_CLOSE);
   gTrack4RSI7Handle=iRSI(_Symbol,_Period,InpTrack4_RSI_Fast,PRICE_CLOSE);
   gTrack4RSI17Handle=iRSI(_Symbol,_Period,InpTrack4_RSI_Slow,PRICE_CLOSE);
   gTrack4WPR7Handle=iWPR(_Symbol,_Period,InpTrack4_WPR_Fast);
   gTrack4WPR14Handle=iWPR(_Symbol,_Period,InpTrack4_WPR_Slow);
   gTrack4ADXHandle=iADX(_Symbol,_Period,InpTrack4_ADX_Period);
   gTrack4KDJHandle=iStochastic(_Symbol,_Period,InpTrack4_KDJ_K,InpTrack4_KDJ_D,InpTrack4_KDJ_Slowing,MODE_SMA,STO_LOWHIGH);
   if(gTrack4MACDHandle==INVALID_HANDLE || gTrack4RSI7Handle==INVALID_HANDLE || gTrack4RSI17Handle==INVALID_HANDLE || gTrack4WPR7Handle==INVALID_HANDLE || gTrack4WPR14Handle==INVALID_HANDLE || gTrack4ADXHandle==INVALID_HANDLE || gTrack4KDJHandle==INVALID_HANDLE)
     {
      Print("融合轨4轻量版：无法创建一个或多个动能指标句柄，检查参数与终端数据。");
      return INIT_FAILED;
     }

   IndicatorSetString(INDICATOR_SHORTNAME,"南门拈星 融合轨4轻量版 v0.66（KAMA宽度+融合轨4）");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return INIT_SUCCEEDED;
}

// 仅更新指定轨道的显示缓冲区。底层均线、ATR、残差宽度及其他轨道不重算。
void RebuildOffsetChannel(const int channel)
  {
   // 轻量版只保留 channel==1：快速线中心 + KAMA宽度参考轨。
   // 偏移仅改显示缓冲区，不重新计算EMA、KAMA、ATR、残差或融合轨4动能。
   if(channel!=1 || gCachedRatesTotal<=0) return;
   int total=gCachedRatesTotal;
   double scale=MathMax(0.01,InpFast_KAMAWidth_Scale);
   for(int i=0;i<total;i++)
     {
      if(KAMAUpper[i]==EMPTY_VALUE || KAMALower[i]==EMPTY_VALUE ||
         KAMALine[i]==EMPTY_VALUE || FastLine[i]==EMPTY_VALUE)
        {
         FastKAMAWidthUpper[i]=EMPTY_VALUE;
         FastKAMAWidthLower[i]=EMPTY_VALUE;
         continue;
        }
      double halfUp=MathMax(0.0,KAMAUpper[i]-KAMALine[i]);
      double halfDown=MathMax(0.0,KAMALine[i]-KAMALower[i]);
      FastKAMAWidthUpper[i]=FastLine[i]+halfUp*scale+gUpperOffset[1];
      FastKAMAWidthLower[i]=FastLine[i]-halfDown*scale+gLowerOffset[1];
     }
   ChartRedraw(0);
  }

// 融合轨3偏移重建：只将人工偏移加到预先计算好的基础轨上，不重算融合轨2、KAMA或ATR。
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
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      ChartRedraw(0);
      return;
     }

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
          gStatsDirty=true;
          gArrowDirty=true;
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
            gStatsDirty=true;
            gArrowDirty=true;
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
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(open,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);
   if(rates_total<MathMax(MathMax(InpKAMA_ER_Period,InpATR_Period),InpResidual_Period)+4)
      return 0;

   bool full=(prev_calculated<=0 || prev_calculated>rates_total || gForceFullRecalc);
   int start=(full ? rates_total-1 : (int)MathMin(rates_total-1,rates_total-prev_calculated));
   gForceFullRecalc=false;
   gCachedRatesTotal=rates_total;

   ArrayResize(Atr,rates_total); ArraySetAsSeries(Atr,true);
   ArrayResize(Track4DriveUpper,rates_total); ArraySetAsSeries(Track4DriveUpper,true);
   ArrayResize(Track4DriveLower,rates_total); ArraySetAsSeries(Track4DriveLower,true);
   ArrayResize(Track4Energy,rates_total); ArraySetAsSeries(Track4Energy,true);
   ArrayResize(Composite4BaseUpper,rates_total); ArraySetAsSeries(Composite4BaseUpper,true);
   ArrayResize(Composite4BaseLower,rates_total); ArraySetAsSeries(Composite4BaseLower,true);

   // 普通报价只读取当前计算段所需的动能数据；关闭统计时绝不复制全历史指标数据。
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
      double widthScale=MathMax(0.01,InpFast_KAMAWidth_Scale);
      FastKAMAWidthUpper[i]=FastLine[i]+half*widthScale+gUpperOffset[1];
      FastKAMAWidthLower[i]=FastLine[i]-half*widthScale+gLowerOffset[1];
      CalculateTrack4At(i,rates_total,open,close,true);
     }

   if(gStatsEnabled && (gStatsDirty || full || rates_total>prev_calculated))
     {
      // 统计打开时才扫描历史触点、重建盈亏篮子和亏损连线。
      UpdateTouchArrowsAndStats(rates_total,time,open,high,low,close);
      gStatsDirty=false;
     }
   else if(!gStatsEnabled && (gArrowDirty || full))
     {
      UpdateTouchArrowsOnly(rates_total,time,open,high,low,close);
      gArrowDirty=false;
     }
   else if(!gStatsEnabled && rates_total>prev_calculated)
      UpdateTouchArrowsLatestBar(rates_total,high,low);
   return rates_total;
  }
//+------------------------------------------------------------------+
