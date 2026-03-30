//+------------------------------------------------------------------+
//| StatisticalDistributionEA.mq5                                   |
//| Interactive statistical distribution analysis on chart.          |
//| Analysis / visualization only — no order execution.              |
//+------------------------------------------------------------------+
// Pipeline: parse -> eval over last N closed bars -> stats -> canvas.
// Submit: CHARTEVENT_OBJECT_ENDEDIT on the expression edit (Enter or focus loss).
// Persistence (InpPersistLastExpression): bars in GlobalVariable; last expression in
// MQL5/Files/*.expr.txt (GV is double-only in MQL5).
//+------------------------------------------------------------------+
#property copyright "MetatraderDataAnalyzer"
#property link      ""
#property version   "1.02"
#property description "Statistical distribution histogram on chart (no trading)."

input int  InpBarsToAnalyze          = 100000; // Closed bars (clamped to SD_MAX_BARS_TO_ANALYZE)
input bool InpPersistLastExpression  = true;  // Restore/save bars (GV) + last expression (file)

#include "Include/SD_Config.mqh"
#include "Include/SD_Types.mqh"
#include "Include/SD_ExprLexer.mqh"
#include "Include/SD_ExprParser.mqh"
#include "Include/SD_SeriesBuffer.mqh"
#include "Include/SD_Persist.mqh"
#include "Include/SD_Stats.mqh"
#include "Include/SD_ExprEval.mqh"
#include "Include/SD_UI.mqh"

int g_sd_bars_effective = SD_DEFAULT_BARS_TO_ANALYZE;

// Sample buffer: grows with max N used; ArrayFree in OnDeinit.
double g_sd_pipeline_vals[];

long g_sd_save_show_date = 1;
long g_sd_save_show_price = 1;
long g_sd_save_show_grid = 1;
long g_sd_save_period_sep = 1;
bool g_sd_chrome_saved = false;

//+------------------------------------------------------------------+
//| Hide native time/price scales so they are not mistaken for the   |
//| distribution axes (CHART_HEIGHT often excludes the time strip). |
//| Restored in OnDeinit.                                            |
//+------------------------------------------------------------------+
void SdChart_SaveAndHideScales(const long chart_id)
  {
   if(!g_sd_chrome_saved)
     {
      g_sd_save_show_date = ChartGetInteger(chart_id, CHART_SHOW_DATE_SCALE, 0);
      g_sd_save_show_price = ChartGetInteger(chart_id, CHART_SHOW_PRICE_SCALE, 0);
      g_sd_save_show_grid = ChartGetInteger(chart_id, CHART_SHOW_GRID, 0);
      g_sd_save_period_sep = ChartGetInteger(chart_id, CHART_SHOW_PERIOD_SEP, 0);
      g_sd_chrome_saved = true;
     }
   ChartSetInteger(chart_id, CHART_SHOW_DATE_SCALE, 0, false);
   ChartSetInteger(chart_id, CHART_SHOW_PRICE_SCALE, 0, false);
   ChartSetInteger(chart_id, CHART_SHOW_GRID, 0, false);
   ChartSetInteger(chart_id, CHART_SHOW_PERIOD_SEP, 0, false);
   ChartRedraw(chart_id);
  }

//+------------------------------------------------------------------+
void SdChart_RestoreScales(const long chart_id)
  {
   if(!g_sd_chrome_saved)
      return;
   ChartSetInteger(chart_id, CHART_SHOW_DATE_SCALE, 0, g_sd_save_show_date);
   ChartSetInteger(chart_id, CHART_SHOW_PRICE_SCALE, 0, g_sd_save_show_price);
   ChartSetInteger(chart_id, CHART_SHOW_GRID, 0, g_sd_save_show_grid);
   ChartSetInteger(chart_id, CHART_SHOW_PERIOD_SEP, 0, g_sd_save_period_sep);
   g_sd_chrome_saved = false;
   ChartRedraw(chart_id);
  }

//+------------------------------------------------------------------+
//| Ensure g_sd_pipeline_vals has at least n elements (amortized   |
//| ArrayResize for repeated pipeline runs).                         |
//+------------------------------------------------------------------+
bool SdPipeline_EnsureSampleBuffer(const int n, SdResult &r)
  {
   if(n < 1)
     {
      SdResult_SetError(r, SD_ERR_BUFFER_INSUFFICIENT, "Invalid sample count.");
      return false;
     }
   if(ArraySize(g_sd_pipeline_vals) < n)
     {
      if(ArrayResize(g_sd_pipeline_vals, n) != n)
        {
         SdResult_SetError(r, SD_ERR_BUFFER_INSUFFICIENT,
                           "Could not allocate memory for samples. Reduce BarsToAnalyze.");
         return false;
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Run full pipeline for current chart symbol/period.               |
//| On failure, SdUi_ReportPipelineFailure shows status and keeps the |
//| last successful distribution when available (no misleading plot).|
//+------------------------------------------------------------------+
void SdRunPipeline(const long chart_id)
  {
   Print("[Pipeline] START");
   
   string expr = SdUi_GetExpressionText(chart_id);
   Print("[Pipeline] Expression: '", expr, "'");
   
   if(StringLen(expr) == 0)
     {
      Print("[Pipeline] ERROR: Empty expression");
      SdResult empty_r;
      SdResult_SetError(empty_r, SD_ERR_PARSE_EMPTY_EXPR, "Enter an expression, then press Enter.");
      SdUi_ReportPipelineFailure(chart_id, empty_r);
      return;
     }
   
   SdResult pr;
   CSdParser parser;
   SdAstNode *ast = parser.Parse(expr, pr);
   Print("[Pipeline] Parse result: ok=", pr.ok, " msg=", pr.message, " ast=", (ast != NULL ? "valid" : "NULL"));
   
   if(ast == NULL || !pr.ok)
     {
      Print("[Pipeline] ERROR: Parse failed");
      SdUi_ReportPipelineFailure(chart_id, pr);
      return;
     }

   SdBarWindow w;
   int bars_req = SdBarWindow_ClampBarsRequested(g_sd_bars_effective);
   Print("[Pipeline] Bars requested: ", bars_req);
   
   if(!SdBarWindow_Build(w, _Symbol, _Period, bars_req, pr))
     {
      Print("[Pipeline] ERROR: BarWindow build failed: ", pr.message);
      SdAst_Free(ast);
      SdUi_ReportPipelineFailure(chart_id, pr);
      return;
     }
   Print("[Pipeline] BarWindow built: count=", w.closed_bar_count, " sym=", w.symbol, " tf=", EnumToString(w.timeframe));

   SdResult cap_r;
   if(!SdPipeline_EnsureSampleBuffer(w.closed_bar_count, cap_r))
     {
      Print("[Pipeline] ERROR: sample buffer: ", cap_r.message);
      SdAst_Free(ast);
      SdUi_ReportPipelineFailure(chart_id, cap_r);
      return;
     }
   
   SdEvalContext ec;
   ec.symbol = _Symbol;
   ec.timeframe = _Period;
   ec.window_bar_count = w.closed_bar_count;
   SdResult er;
   
   Print("[Pipeline] Evaluating ", w.closed_bar_count, " bars...");
   for(int row_index = 0; row_index < w.closed_bar_count; row_index++)
     {
      ec.window_row_index = row_index;
      if(!SdEval_RootAt(ast, ec, g_sd_pipeline_vals[row_index], er))
        {
         Print("[Pipeline] ERROR: Eval failed at row=", row_index, ": ", er.message);
         SdAst_Free(ast);
         SdUi_ReportPipelineFailure(chart_id, er);
         return;
        }
     }
   SdAst_Free(ast);
   Print("[Pipeline] Evaluation complete");

   SdStatsSummary sum;
   SdResult sr;
   Print("[Pipeline] Computing stats...");
   SdStats_Compute(g_sd_pipeline_vals, w.closed_bar_count, sum, sr);
   
   if(!sr.ok)
     {
      Print("[Pipeline] ERROR: Stats compute failed: ", sr.message);
      SdUi_ReportPipelineFailure(chart_id, sr);
      return;
     }
   
   Print("[Pipeline] Stats: has_data=", sum.has_data, " count=", sum.count, 
         " mean=", sum.mean, " stdev=", sum.stdev, 
         " vmin=", sum.vmin, " vmax=", sum.vmax);

   Print("[Pipeline] Calling SdUi_SetStats...");
   SdUi_SetStats(chart_id, sum);
   
   Print("[Pipeline] Calling SdUi_DrawDistribution...");
   SdUi_DrawDistribution(chart_id, sum);
   SdUi_SetStatus(chart_id, "");

   if(InpPersistLastExpression)
     {
      SdPersist_SaveBars(g_sd_bars_effective, _Symbol, _Period);
      SdPersist_SaveExpr(expr, _Symbol, _Period);
     }
   
   Print("[Pipeline] END - Success");
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("[OnInit] START - Symbol=", _Symbol, " Period=", EnumToString(_Period));
   
   SdEval_ClearCache();

   g_sd_bars_effective = SdBarWindow_ClampBarsRequested(InpBarsToAnalyze);
   Print("[OnInit] Bars effective: ", g_sd_bars_effective);
   
   if(InpPersistLastExpression)
     {
      int btmp = 0;
      if(SdPersist_LoadBars(btmp, _Symbol, _Period))
        {
         if(InpBarsToAnalyze == SD_DEFAULT_BARS_TO_ANALYZE)
            g_sd_bars_effective = btmp;
         Print("[OnInit] Loaded persisted bars: ", btmp);
        }
     }

   SdChart_SaveAndHideScales(ChartID());

   Print("[OnInit] Calling SdUi_Init...");
   if(!SdUi_Init(ChartID()))
     {
      Print("[OnInit] ERROR: SdUi_Init failed!");
      SdChart_RestoreScales(ChartID());
      return(INIT_FAILED);
     }
   Print("[OnInit] SdUi_Init succeeded");

   if(InpPersistLastExpression)
     {
      string prev;
      if(SdPersist_LoadExpr(prev, _Symbol, _Period))
        {
         Print("[OnInit] Loaded persisted expression: '", prev, "'");
         SdUi_SetExpressionText(ChartID(), prev);
        }
     }

   Print("[OnInit] END - INIT_SUCCEEDED");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//| Order: indicator cache, pipeline array, UI/canvas, chart scales. |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   SdEval_ClearCache();
   ArrayFree(g_sd_pipeline_vals);
   SdUi_Deinit(ChartID());
   SdChart_RestoreScales(ChartID());
  }

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
     {
      SdChart_SaveAndHideScales(ChartID());
      SdUi_OnChartResize(ChartID());
      return;
     }

   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      Print("[Event] OBJECT_CLICK: ", sparam);
      if(SdUi_TryExampleClick(ChartID(), sparam))
        {
         Print("[Event] Example click handled");
         return;
        }
     }

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
     {
      Print("[Event] OBJECT_ENDEDIT: ", sparam);
      string expected = SdUi_ExprObjectName(ChartID());
      Print("[Event] Expected object name: ", expected);
      
      if(sparam == expected)
        {
         Print("[Event] Match! Calling SdRunPipeline...");
         SdRunPipeline(ChartID());
        }
      else
        {
         Print("[Event] No match, ignoring");
        }
     }
  }
