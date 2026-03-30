//+------------------------------------------------------------------+
//| SD_Config.mqh                                                    |
//| Central configuration: histogram bin limits, bar-window caps,     |
//| GlobalVariable key prefix, and numeric error IDs for SdResult.  |
//|                                                                  |
//| Error codes are stable API: SdResult.code + optional detail in   |
//| SdResult.message. UI uses SdConfig_ErrorMessage(code) when the   |
//| message is empty (see SdResult_FormatUserMessage in SD_Types).   |
//+------------------------------------------------------------------+
#ifndef __SD_CONFIG_MQH__
#define __SD_CONFIG_MQH__

//--- Histogram bucket count (used by SdStats_Compute).
//| K ≈ ceil(sqrt(sample_count)), then clamped to [SD_HIST_MIN_BINS, SD_HIST_MAX_BINS].
//| (Plot overlay may use a normal curve; bins still back summary / edge cases.)
#define SD_HIST_MIN_BINS             8
#define SD_HIST_MAX_BINS             256

//--- Closed-bar analysis window (requested count clamped in SD_SeriesBuffer).
//| SD_DEFAULT_BARS_TO_ANALYZE: EA input default when user does not override persist.
//| SD_MAX_BARS_TO_ANALYZE: hard cap to bound memory and copy cost.
#define SD_DEFAULT_BARS_TO_ANALYZE    100000
#define SD_MAX_BARS_TO_ANALYZE       500000

//--- Persistence (GlobalVariable keys): human-readable prefix; full key = f(EA, symbol, TF).
#define SD_GV_PREFIX                 "SDEA_"

//--- Error codes for SdResult.code (keep ranges grouped for readability in logs).
//| Parse / lexer: 1–9
#define SD_ERR_OK                    0
#define SD_ERR_LEX_UNEXPECTED        1   // Lexer: illegal or unfinished token
#define SD_ERR_PARSE_EXPECTED        2   // Parser: expected token missing (detail = context)
#define SD_ERR_PARSE_BARE_BANDS      3   // Bands(…) not followed by .Upper|.Lower|.Mid
#define SD_ERR_PARSE_BAD_BAND_MEMBER 4 // .Foo after Bands is not Upper/Lower/Mid
#define SD_ERR_PARSE_UNKNOWN_IDENT   5   // Identifier is not a known series or symbol
#define SD_ERR_PARSE_UNKNOWN_FUNC    6   // Function name not supported (detail = name)
#define SD_ERR_PARSE_CALL_ARITY      7   // Wrong argument count for function call
#define SD_ERR_PARSE_PAREN           8   // "(" ")" mismatch
#define SD_ERR_PARSE_EMPTY_EXPR      9   // Nothing to parse
//| Data window: 20–29
#define SD_ERR_BUFFER_INSUFFICIENT   20  // Not enough closed bars for requested N
//| Evaluation: 30–39
#define SD_ERR_EVAL_DIV0             30  // Division by zero in expression
#define SD_ERR_EVAL_INDICATOR        31  // i* handle invalid or CopyBuffer failed
#define SD_ERR_EVAL_RANGE            32  // Shift or window row out of bounds
#define SD_ERR_EVAL_PERIOD           33  // Indicator period invalid (e.g. ≤ 0)
#define SD_ERR_EVAL_COPY             34  // CopyClose/Open/… failed or empty value
//| Post-process: 40–49
#define SD_ERR_STATS_EMPTY           40  // No finite values after filtering (EMPTY/NaN)

//+------------------------------------------------------------------+
//| Default English status text when detail is empty.                |
//| Parser/eval may set SdResult.message to a longer, contextual line.|
//+------------------------------------------------------------------+
string SdConfig_ErrorMessage(const int error_code)
  {
   switch(error_code)
     {
      case SD_ERR_OK:
         return "OK";
      case SD_ERR_LEX_UNEXPECTED:
         return "Invalid character or incomplete token — check spelling and brackets";
      case SD_ERR_PARSE_EXPECTED:
         return "Syntax error";
      case SD_ERR_PARSE_BARE_BANDS:
         return "Bands(...) needs .Upper, .Lower, or .Mid (e.g. Bands(20,2).Mid)";
      case SD_ERR_PARSE_BAD_BAND_MEMBER:
         return "After Bands(...), use only .Upper, .Lower, or .Mid";
      case SD_ERR_PARSE_UNKNOWN_IDENT:
         return "Unknown name";
      case SD_ERR_PARSE_UNKNOWN_FUNC:
         return "Unknown function";
      case SD_ERR_PARSE_CALL_ARITY:
         return "Wrong number of arguments for this function";
      case SD_ERR_PARSE_PAREN:
         return "Unbalanced parentheses";
      case SD_ERR_PARSE_EMPTY_EXPR:
         return "Expression is empty — type a formula and press Enter";
      case SD_ERR_BUFFER_INSUFFICIENT:
         return "Not enough history — download more data or reduce BarsToAnalyze";
      case SD_ERR_EVAL_DIV0:
         return "Division by zero in expression";
      case SD_ERR_EVAL_INDICATOR:
         return "Indicator failed — check period/settings or history";
      case SD_ERR_EVAL_RANGE:
         return "Bar shift or index out of range";
      case SD_ERR_EVAL_PERIOD:
         return "Period must be a positive integer";
      case SD_ERR_EVAL_COPY:
         return "Could not read series or indicator data";
      case SD_ERR_STATS_EMPTY:
         return "No usable numeric values — check expression and history";
      default:
         return "Unknown error — see Experts log";
     }
  }

#endif
