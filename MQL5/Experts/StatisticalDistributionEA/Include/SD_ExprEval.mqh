//+------------------------------------------------------------------+
//| SD_ExprEval.mqh                                                  |
//| Walks the parsed AST and produces one double per “window row”.   |
//| Rows are 0..N-1 (newest closed bar = row 0); MT5 shift = row+1.   |
//| Handles: SMA/EMA/RSI/ATR/StdDev, Bollinger Bands lines, series,   |
//| arithmetic, and [k] shift inside the window.                      |
//+------------------------------------------------------------------+
#ifndef __SD_EXPR_EVAL_MQH__
#define __SD_EXPR_EVAL_MQH__

#include "SD_Config.mqh"
#include "SD_Types.mqh"
#include "SD_ExprParser.mqh"
#include "SD_SeriesBuffer.mqh"

// Max distinct indicator instances kept open (see SdEval_CacheObtain).
#define SD_EVAL_CACHE_MAX  48

//+------------------------------------------------------------------+
//| Per-sample evaluation frame: which bar inside the N-bar window.   |
//| window_row_index 0 = youngest closed bar; maps to MT5 shift row+1.|
//+------------------------------------------------------------------+
struct SdEvalContext
  {
   string            symbol;
   ENUM_TIMEFRAMES   timeframe;
   int               window_row_index;
   int               window_bar_count;
  };

//+------------------------------------------------------------------+
//| One slot in the global indicator handle pool (freed on clear).   |
//+------------------------------------------------------------------+
struct SdIndiCacheSlot
  {
   bool              is_slot_used;
   string            cache_key;
   int               indicator_handle;
  };

SdIndiCacheSlot g_sd_eval_indicator_cache[SD_EVAL_CACHE_MAX];

//+------------------------------------------------------------------+
//| Map parser band member (SD_BAND_*) to CopyBuffer line index.      |
//| iBands buffers: 0 = middle, 1 = upper, 2 = lower.                |
//+------------------------------------------------------------------+
int SdEval_BandsBufferIndex(const int member)
  {
   if(member == SD_BAND_UPPER)
      return 1;
   if(member == SD_BAND_LOWER)
      return 2;
   return 0;
  }

//+------------------------------------------------------------------+
//| Reject EMPTY_VALUE and non-finite doubles.                        |
//+------------------------------------------------------------------+
bool SdEval_IsGoodValue(const double value)
  {
   if(value == EMPTY_VALUE)
      return false;
   if(!MathIsValidNumber(value))
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Close every cached handle and reset slots.                        |
//| Call from OnDeinit and at OnInit so a reattach never leaks.      |
//+------------------------------------------------------------------+
void SdEval_ClearCache()
  {
   for(int slot_index = 0; slot_index < SD_EVAL_CACHE_MAX; slot_index++)
     {
      if(g_sd_eval_indicator_cache[slot_index].is_slot_used &&
         g_sd_eval_indicator_cache[slot_index].indicator_handle != INVALID_HANDLE)
        {
         IndicatorRelease(g_sd_eval_indicator_cache[slot_index].indicator_handle);
        }
      g_sd_eval_indicator_cache[slot_index].is_slot_used = false;
      g_sd_eval_indicator_cache[slot_index].cache_key = "";
      g_sd_eval_indicator_cache[slot_index].indicator_handle = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
//| Reuse a handle when cache_key matches; otherwise occupy a slot.    |
//| If the key already exists, fresh_handle is released (duplicate).   |
//| Returns INVALID_HANDLE when the pool is full.                      |
//+------------------------------------------------------------------+
int SdEval_CacheObtain(const string cache_key, const int fresh_handle)
  {
   for(int slot_index = 0; slot_index < SD_EVAL_CACHE_MAX; slot_index++)
     {
      if(g_sd_eval_indicator_cache[slot_index].is_slot_used &&
         StringCompare(g_sd_eval_indicator_cache[slot_index].cache_key, cache_key) == 0)
        {
         if(fresh_handle != INVALID_HANDLE &&
            fresh_handle != g_sd_eval_indicator_cache[slot_index].indicator_handle)
            IndicatorRelease(fresh_handle);
         return g_sd_eval_indicator_cache[slot_index].indicator_handle;
        }
     }
   int free_slot_index = -1;
   for(int scan_index = 0; scan_index < SD_EVAL_CACHE_MAX; scan_index++)
     {
      if(!g_sd_eval_indicator_cache[scan_index].is_slot_used)
        {
         free_slot_index = scan_index;
         break;
        }
     }
   if(free_slot_index < 0)
     {
      if(fresh_handle != INVALID_HANDLE)
         IndicatorRelease(fresh_handle);
      return INVALID_HANDLE;
     }
   g_sd_eval_indicator_cache[free_slot_index].is_slot_used = true;
   g_sd_eval_indicator_cache[free_slot_index].cache_key = cache_key;
   g_sd_eval_indicator_cache[free_slot_index].indicator_handle = fresh_handle;
   return fresh_handle;
  }

//+------------------------------------------------------------------+
//| Require a positive integer period (no fractional part).           |
//+------------------------------------------------------------------+
bool SdEval_AsPeriod(const double period_double, int &out_period, SdResult &r)
  {
   const int period_int = (int)period_double;
   if(period_int < 1 || MathAbs(period_double - (double)period_int) > 1e-6)
     {
      SdResult_SetError(r, SD_ERR_EVAL_PERIOD, SdConfig_ErrorMessage(SD_ERR_EVAL_PERIOD));
      return false;
     }
   out_period = period_int;
   return true;
  }

//+------------------------------------------------------------------+
//| Read one value from an indicator buffer at the given MT5 shift.    |
//| Static scratch avoids per-call heap churn in the hot loop.         |
//+------------------------------------------------------------------+
bool SdEval_CopyOne(const int indicator_handle, const int buffer_index,
                    const int mt5_shift, double &out_value)
  {
   static double scratch_one_sample[1];
   if(CopyBuffer(indicator_handle, buffer_index, mt5_shift, 1, scratch_one_sample) != 1)
      return false;
   out_value = scratch_one_sample[0];
   return SdEval_IsGoodValue(out_value);
  }

//+------------------------------------------------------------------+
bool SdEval_Node(SdAstNode *node, const SdEvalContext &ctx, double &out_value, SdResult &r);

//+------------------------------------------------------------------+
//| OHLCV for the current window row (closed bar only).                |
//+------------------------------------------------------------------+
bool SdEval_SeriesAt(const SdEvalContext &ctx, const int series_kind, double &out_value, SdResult &r)
  {
   const int mt5_shift = SdBarWindow_IndexToShift(ctx.window_row_index);
   double price_scratch[1];
   int bars_copied = 0;
   if(series_kind == SD_SER_CLOSE)
      bars_copied = CopyClose(ctx.symbol, ctx.timeframe, mt5_shift, 1, price_scratch);
   else if(series_kind == SD_SER_OPEN)
      bars_copied = CopyOpen(ctx.symbol, ctx.timeframe, mt5_shift, 1, price_scratch);
   else if(series_kind == SD_SER_HIGH)
      bars_copied = CopyHigh(ctx.symbol, ctx.timeframe, mt5_shift, 1, price_scratch);
   else if(series_kind == SD_SER_LOW)
      bars_copied = CopyLow(ctx.symbol, ctx.timeframe, mt5_shift, 1, price_scratch);
   else if(series_kind == SD_SER_VOLUME)
     {
      long volume_scratch[1];
      bars_copied = (int)CopyTickVolume(ctx.symbol, ctx.timeframe, mt5_shift, 1, volume_scratch);
      if(bars_copied == 1)
        {
         out_value = (double)volume_scratch[0];
         return true;
        }
      SdResult_SetError(r, SD_ERR_EVAL_COPY,
                        StringFormat("Could not read Volume at shift %d (row %d). Download history or increase BarsToAnalyze.",
                                     mt5_shift, ctx.window_row_index));
      return false;
     }
   if(bars_copied != 1)
     {
      SdResult_SetError(r, SD_ERR_EVAL_COPY,
                        StringFormat("Could not read price/volume at shift %d (row %d of %d). Download history or increase BarsToAnalyze.",
                                     mt5_shift, ctx.window_row_index, ctx.window_bar_count));
      return false;
     }
   out_value = price_scratch[0];
   return true;
  }

//+------------------------------------------------------------------+
//| Dispatch by AST node kind (recursive).                           |
//+------------------------------------------------------------------+
bool SdEval_Node(SdAstNode *node, const SdEvalContext &ctx, double &out_value, SdResult &r)
  {
   if(node == NULL)
     {
      SdResult_SetError(r, SD_ERR_EVAL_RANGE, "null AST node");
      return false;
     }
   SdResult_SetOk(r);

   if(node.m_kind == SD_AST_NUMBER)
     {
      SdAstNumber *number_node = (SdAstNumber*)node;
      out_value = number_node.m_value;
      return true;
     }

   if(node.m_kind == SD_AST_UNARY_MINUS)
     {
      SdAstUnaryMinus *unary_node = (SdAstUnaryMinus*)node;
      double child_value;
      if(!SdEval_Node(unary_node.m_child, ctx, child_value, r))
         return false;
      out_value = -child_value;
      return true;
     }

   if(node.m_kind == SD_AST_BINARY)
     {
      SdAstBinary *binary_node = (SdAstBinary*)node;
      double left_value;
      double right_value;
      if(!SdEval_Node(binary_node.m_left, ctx, left_value, r))
         return false;
      if(!SdEval_Node(binary_node.m_right, ctx, right_value, r))
         return false;
      if(binary_node.m_op == '+')
        {
         out_value = left_value + right_value;
         return true;
        }
      if(binary_node.m_op == '-')
        {
         out_value = left_value - right_value;
         return true;
        }
      if(binary_node.m_op == '*')
        {
         out_value = left_value * right_value;
         return true;
        }
      if(binary_node.m_op == '/')
        {
         if(MathAbs(right_value) < 1e-15)
           {
            SdResult_SetError(r, SD_ERR_EVAL_DIV0, SdConfig_ErrorMessage(SD_ERR_EVAL_DIV0));
            return false;
           }
         out_value = left_value / right_value;
         return true;
        }
      SdResult_SetError(r, SD_ERR_EVAL_RANGE, "unknown binary op");
      return false;
     }

   if(node.m_kind == SD_AST_SHIFT)
     {
      SdAstShift *shift_node = (SdAstShift*)node;
      const int shifted_row_index = ctx.window_row_index + shift_node.m_shift;
      if(shifted_row_index < 0 || shifted_row_index >= ctx.window_bar_count)
        {
         SdResult_SetError(r, SD_ERR_EVAL_RANGE,
                           StringFormat("Shift [%d] at row %d leaves the analysis window (0..%d). Reduce the shift or use more bars.",
                                        shift_node.m_shift, ctx.window_row_index, ctx.window_bar_count - 1));
         return false;
        }
      SdEvalContext ctx_shifted = ctx;
      ctx_shifted.window_row_index = shifted_row_index;
      return SdEval_Node(shift_node.m_inner, ctx_shifted, out_value, r);
     }

   if(node.m_kind == SD_AST_SERIES)
     {
      SdAstSeries *series_node = (SdAstSeries*)node;
      return SdEval_SeriesAt(ctx, series_node.m_series, out_value, r);
     }

   if(node.m_kind == SD_AST_CALL)
     {
      SdAstCall *call_node = (SdAstCall*)node;
      double period_double;
      if(!SdEval_Node(call_node.m_arg, ctx, period_double, r))
         return false;
      int period = 0;
      if(!SdEval_AsPeriod(period_double, period, r))
         return false;

      const int mt5_shift = SdBarWindow_IndexToShift(ctx.window_row_index);
      string cache_key = call_node.m_name + "|" + IntegerToString(period);
      int new_handle = INVALID_HANDLE;

      if(StringCompare(call_node.m_name, "SMA") == 0)
        {
         new_handle = iMA(ctx.symbol, ctx.timeframe, period, 0, MODE_SMA, PRICE_CLOSE);
         cache_key = "SMA|" + IntegerToString(period);
        }
      else if(StringCompare(call_node.m_name, "EMA") == 0)
        {
         new_handle = iMA(ctx.symbol, ctx.timeframe, period, 0, MODE_EMA, PRICE_CLOSE);
         cache_key = "EMA|" + IntegerToString(period);
        }
      else if(StringCompare(call_node.m_name, "RSI") == 0)
        {
         new_handle = iRSI(ctx.symbol, ctx.timeframe, period, PRICE_CLOSE);
         cache_key = "RSI|" + IntegerToString(period);
        }
      else if(StringCompare(call_node.m_name, "ATR") == 0)
        {
         new_handle = iATR(ctx.symbol, ctx.timeframe, period);
         cache_key = "ATR|" + IntegerToString(period);
        }
      else if(StringCompare(call_node.m_name, "StdDev") == 0)
        {
         new_handle = iStdDev(ctx.symbol, ctx.timeframe, period, 0, MODE_SMA, PRICE_CLOSE);
         cache_key = "StdDev|" + IntegerToString(period);
        }
      else
        {
         SdResult_SetError(r, SD_ERR_EVAL_INDICATOR, call_node.m_name);
         return false;
        }

      if(new_handle == INVALID_HANDLE)
        {
         SdResult_SetError(r, SD_ERR_EVAL_INDICATOR, SdConfig_ErrorMessage(SD_ERR_EVAL_INDICATOR));
         return false;
        }

      const int resolved_handle = SdEval_CacheObtain(cache_key, new_handle);
      if(resolved_handle == INVALID_HANDLE)
        {
         SdResult_SetError(r, SD_ERR_EVAL_INDICATOR, "indicator cache full");
         return false;
        }

      double sample_value;
      if(!SdEval_CopyOne(resolved_handle, 0, mt5_shift, sample_value))
        {
         SdResult_SetError(r, SD_ERR_EVAL_INDICATOR,
                           StringFormat("%s(%d): value not ready at shift %d (row %d). Indicator needs more history — increase BarsToAnalyze or lower the period.",
                                        call_node.m_name, period, mt5_shift, ctx.window_row_index));
         return false;
        }
      out_value = sample_value;
      return true;
     }

   if(node.m_kind == SD_AST_BANDS)
     {
      SdAstBands *bands_node = (SdAstBands*)node;
      double period_value;
      double deviation_value;
      if(!SdEval_Node(bands_node.m_period, ctx, period_value, r))
         return false;
      if(!SdEval_Node(bands_node.m_dev, ctx, deviation_value, r))
         return false;
      int bands_period = 0;
      if(!SdEval_AsPeriod(period_value, bands_period, r))
         return false;
      if(deviation_value <= 0.0 || !MathIsValidNumber(deviation_value))
        {
         SdResult_SetError(r, SD_ERR_EVAL_PERIOD, "Bands deviation must be > 0");
         return false;
        }

      const int mt5_shift = SdBarWindow_IndexToShift(ctx.window_row_index);
      string cache_key = "BANDS|" + IntegerToString(bands_period) + "|" + DoubleToString(deviation_value, 6);
      int new_handle = iBands(ctx.symbol, ctx.timeframe, bands_period, 0, deviation_value, PRICE_CLOSE);
      if(new_handle == INVALID_HANDLE)
        {
         SdResult_SetError(r, SD_ERR_EVAL_INDICATOR, SdConfig_ErrorMessage(SD_ERR_EVAL_INDICATOR));
         return false;
        }
      const int resolved_handle = SdEval_CacheObtain(cache_key, new_handle);
      if(resolved_handle == INVALID_HANDLE)
        {
         SdResult_SetError(r, SD_ERR_EVAL_INDICATOR, "indicator cache full");
         return false;
        }

      const int bands_line_buffer_index = SdEval_BandsBufferIndex(bands_node.m_member);
      double sample_value;
      if(!SdEval_CopyOne(resolved_handle, bands_line_buffer_index, mt5_shift, sample_value))
        {
         SdResult_SetError(r, SD_ERR_EVAL_INDICATOR,
                           StringFormat("Bands(%d,…).%s: value not ready at shift %d (row %d). Increase BarsToAnalyze so the band has enough warmup bars.",
                                        bands_period, (bands_node.m_member == SD_BAND_UPPER ? "Upper" : (bands_node.m_member == SD_BAND_LOWER ? "Lower" : "Mid")),
                                        mt5_shift, ctx.window_row_index));
         return false;
        }
      out_value = sample_value;
      return true;
     }

   SdResult_SetError(r, SD_ERR_EVAL_RANGE, "unsupported AST kind");
   return false;
  }

//+------------------------------------------------------------------+
//| Public entry: evaluate the root node for one window row.          |
//+------------------------------------------------------------------+
bool SdEval_RootAt(SdAstNode *root, const SdEvalContext &ctx, double &out_value, SdResult &r)
  {
   return SdEval_Node(root, ctx, out_value, r);
  }

#endif
