//+------------------------------------------------------------------+
//| SD_Persist.mqh                                                   |
//| Bar count: GlobalVariable (double only in MQL5).                 |
//| Last expression: text file under MQL5/Files/.                   |
//| Keys: SD_GV_PREFIX + symbol + timeframe.                          |
//+------------------------------------------------------------------+
#ifndef __SD_PERSIST_MQH__
#define __SD_PERSIST_MQH__

#include "SD_Config.mqh"
#include "SD_SeriesBuffer.mqh"

//+------------------------------------------------------------------+
string SdPersist_KeyBars(const string symbol, const ENUM_TIMEFRAMES timeframe)
  {
   return SD_GV_PREFIX + symbol + "_" + IntegerToString((int)timeframe) + "_bars";
  }

//+------------------------------------------------------------------+
//| Sanitize symbol for use in file names (strip path-like chars).    |
//+------------------------------------------------------------------+
string SdPersist_FileStem(const string symbol, const ENUM_TIMEFRAMES timeframe)
  {
   string safe = symbol;
   StringReplace(safe, "#", "_");
   StringReplace(safe, "\\", "_");
   StringReplace(safe, "/", "_");
   StringReplace(safe, ":", "_");
   StringReplace(safe, "*", "_");
   StringReplace(safe, "?", "_");
   StringReplace(safe, "\"", "_");
   StringReplace(safe, "<", "_");
   StringReplace(safe, ">", "_");
   StringReplace(safe, "|", "_");
   return SD_GV_PREFIX + safe + "_" + IntegerToString((int)timeframe);
  }

string SdPersist_ExprFileName(const string symbol, const ENUM_TIMEFRAMES timeframe)
  {
   return SdPersist_FileStem(symbol, timeframe) + ".expr.txt";
  }

//+------------------------------------------------------------------+
bool SdPersist_LoadBars(int &bars_out, const string symbol, const ENUM_TIMEFRAMES timeframe)
  {
   const string gv_key = SdPersist_KeyBars(symbol, timeframe);
   if(!GlobalVariableCheck(gv_key))
      return false;
   const double stored = GlobalVariableGet(gv_key);
   if(!MathIsValidNumber(stored))
      return false;
   bars_out = SdBarWindow_ClampBarsRequested((int)stored);
   return true;
  }

//+------------------------------------------------------------------+
void SdPersist_SaveBars(const int bars, const string symbol, const ENUM_TIMEFRAMES timeframe)
  {
   const int clamped = SdBarWindow_ClampBarsRequested(bars);
   GlobalVariableSet(SdPersist_KeyBars(symbol, timeframe), (double)clamped);
  }

//+------------------------------------------------------------------+
bool SdPersist_LoadExpr(string &expression_out, const string symbol, const ENUM_TIMEFRAMES timeframe)
  {
   expression_out = "";
   const string file_name = SdPersist_ExprFileName(symbol, timeframe);
   const int file_handle = FileOpen(file_name, FILE_READ | FILE_TXT | FILE_ANSI);
   if(file_handle == INVALID_HANDLE)
      return false;
   while(!FileIsEnding(file_handle))
      expression_out += FileReadString(file_handle);
   FileClose(file_handle);
   StringTrimLeft(expression_out);
   StringTrimRight(expression_out);
   return StringLen(expression_out) > 0;
  }

//+------------------------------------------------------------------+
//| ANSI path; ASCII expressions are sufficient for this EA.         |
//+------------------------------------------------------------------+
void SdPersist_SaveExpr(const string expression, const string symbol, const ENUM_TIMEFRAMES timeframe)
  {
   const string file_name = SdPersist_ExprFileName(symbol, timeframe);
   const int file_handle = FileOpen(file_name, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_REWRITE);
   if(file_handle == INVALID_HANDLE)
     {
      Print("SdPersist_SaveExpr: FileOpen failed ", file_name, " err=", GetLastError());
      return;
     }
   FileWriteString(file_handle, expression);
   FileClose(file_handle);
  }

#endif
