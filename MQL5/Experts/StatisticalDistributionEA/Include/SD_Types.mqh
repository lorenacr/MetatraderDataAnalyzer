//+------------------------------------------------------------------+
//| SD_Types.mqh                                                     |
//| Shared operation result + helpers for lexer, parser, pipeline.   |
//| Callers pass SdResult by reference; check ok before using data.   |
//+------------------------------------------------------------------+
#ifndef __SD_TYPES_MQH__
#define __SD_TYPES_MQH__

#include "SD_Config.mqh"

//+------------------------------------------------------------------+
//| Pipeline / parse outcome: success flag + machine code + text.   |
//| message: human detail when set; else SdConfig_ErrorMessage(code). |
//+------------------------------------------------------------------+
struct SdResult
  {
   bool              ok;
   int               code;
   string            message;
  };

//+------------------------------------------------------------------+
//| Reset to success (ok, SD_ERR_OK, empty message).                 |
//+------------------------------------------------------------------+
void SdResult_Clear(SdResult &result)
  {
   result.ok = true;
   result.code = SD_ERR_OK;
   result.message = "";
  }

//+------------------------------------------------------------------+
//| Mark success explicitly (same as Clear for this project).         |
//+------------------------------------------------------------------+
void SdResult_SetOk(SdResult &result)
  {
   result.ok = true;
   result.code = SD_ERR_OK;
   result.message = "";
  }

//+------------------------------------------------------------------+
//| Record failure: code from SD_* catalog; message in English.      |
//+------------------------------------------------------------------+
void SdResult_SetError(SdResult &result, const int code, const string msg)
  {
   result.ok = false;
   result.code = code;
   result.message = msg;
  }

//+------------------------------------------------------------------+
//| Text for status line: prefer result.message, else catalog string. |
//+------------------------------------------------------------------+
string SdResult_FormatUserMessage(const SdResult &result)
  {
   if(StringLen(result.message) > 0)
      return result.message;
   return SdConfig_ErrorMessage(result.code);
  }

#endif
