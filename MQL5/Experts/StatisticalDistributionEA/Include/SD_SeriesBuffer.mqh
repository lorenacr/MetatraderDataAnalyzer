//+------------------------------------------------------------------+
//| SD_SeriesBuffer.mqh                                              |
//| Resolves how many closed bars we can analyze for symbol/TF.      |
//| Row index 0 = newest closed bar → MT5 series shift = 1 (bar 0     |
//| is the forming bar and is excluded from the window).              |
//+------------------------------------------------------------------+
#ifndef __SD_SERIES_BUFFER_MQH__
#define __SD_SERIES_BUFFER_MQH__

#include "SD_Config.mqh"
#include "SD_Types.mqh"

//+------------------------------------------------------------------+
//| After SdBarWindow_Build: effective window ≤ bars_requested.       |
//| closed_bar_count = min(requested, history allows).                |
//+------------------------------------------------------------------+
struct SdBarWindow
  {
   string            symbol;
   ENUM_TIMEFRAMES   timeframe;
   int               bars_requested;
   int               closed_bar_count;
  };

//+------------------------------------------------------------------+
//| Clamp user/restore input to [1, SD_MAX_BARS_TO_ANALYZE].         |
//+------------------------------------------------------------------+
int SdBarWindow_ClampBarsRequested(const int requested_bars)
  {
   if(requested_bars < 1)
      return 1;
   if(requested_bars > SD_MAX_BARS_TO_ANALYZE)
      return SD_MAX_BARS_TO_ANALYZE;
   return requested_bars;
  }

//+------------------------------------------------------------------+
//| Fill w: closed_bar_count = min(bars_requested, available closed).|
//| Bars(sym,tf): index 0 is forming bar → closed count = total - 1.  |
//| Returns false and fills result on hard failure.                   |
//+------------------------------------------------------------------+
bool SdBarWindow_Build(SdBarWindow &w,
                       const string symbol,
                       const ENUM_TIMEFRAMES timeframe,
                       const int bars_requested,
                       SdResult &result)
  {
   SdResult_Clear(result);
   if(bars_requested < 1)
     {
      SdResult_SetError(result, SD_ERR_BUFFER_INSUFFICIENT,
                        "bars_requested must be at least 1");
      return false;
     }
   if(bars_requested > SD_MAX_BARS_TO_ANALYZE)
     {
      SdResult_SetError(result, SD_ERR_BUFFER_INSUFFICIENT,
                        "bars_requested exceeds SD_MAX_BARS_TO_ANALYZE");
      return false;
     }
   const int total_bars_on_chart = Bars(symbol, timeframe);
   if(total_bars_on_chart < 2)
     {
      SdResult_SetError(result, SD_ERR_BUFFER_INSUFFICIENT,
                        "insufficient history (need at least 2 bars)");
      return false;
     }
   const int closed_bars_available = total_bars_on_chart - 1;
   int effective_count = bars_requested;
   if(effective_count > closed_bars_available)
      effective_count = closed_bars_available;
   if(effective_count < 1)
     {
      SdResult_SetError(result, SD_ERR_BUFFER_INSUFFICIENT,
                        "no closed bars available for window");
      return false;
     }
   w.symbol = symbol;
   w.timeframe = timeframe;
   w.bars_requested = bars_requested;
   w.closed_bar_count = effective_count;
   SdResult_SetOk(result);
   return true;
  }

//+------------------------------------------------------------------+
//| Map window row (0 = newest closed) to Copy* / CopyBuffer shift.  |
//| Newest closed bar uses shift 1; forming bar (shift 0) is unused.  |
//+------------------------------------------------------------------+
int SdBarWindow_IndexToShift(const int window_row_index)
  {
   return window_row_index + 1;
  }

#endif
