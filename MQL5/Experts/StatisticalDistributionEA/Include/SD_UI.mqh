//+------------------------------------------------------------------+
//| SD_UI.mqh                                                        |
//| Full-chart overlay: dark panel, CCanvas histogram, edit + labels.|
//| Pipeline runs on CHARTEVENT_OBJECT_ENDEDIT (expression field).    |
//+------------------------------------------------------------------+
#ifndef __SD_UI_MQH__
#define __SD_UI_MQH__

#include "SD_Config.mqh"
#include "SD_Stats.mqh"
#include <Canvas\Canvas.mqh>

#define SD_UI_EXAMPLE_COUNT 9

#define SD_UI_PANEL_BG    C'26,28,34'
#define SD_UI_PANEL_BR    C'55,58,68'
#define SD_UI_TEXT_MAIN   clrSilver
#define SD_UI_TEXT_STATUS clrLightGray
#define SD_UI_TEXT_LINK   clrDeepSkyBlue
// Z-order: higher draws above; keep panel under candles if OBJPROP_BACK is false.
#define SD_UI_Z_PANEL     5000
#define SD_UI_Z_CANVAS    5100
#define SD_UI_Z_LABEL     5200
#define SD_UI_Z_EXAMPLE   5210
#define SD_UI_Z_EDIT      5300
// Covers terminal time strip so it is not confused with histogram x-axis.
#define SD_UI_TIME_COVER_H  48
#define SD_UI_Z_TIMECOVER   5350
#define SD_UI_DIST_CURVE_LINE_PX   2
#define SD_UI_DIST_BAND_LINE_PX    1
// Double-stroke bands: ghost line offset + alpha (see SdUi_DrawBandVerticalDouble).
#define SD_UI_BAND_LINE_OFFSET       1
#define SD_UI_BAND_LINE_GHOST_ALPHA  100
#define SD_UI_BAND_LBL_GAP           4
// Legend font sizes (CCanvas TextOut): axis titles / ticks vs percentile band tags.
#define SD_UI_DIST_AXIS_LABEL_PT     12
#define SD_UI_DIST_BAND_LABEL_PT     12
// Extra span around outer ICs (p005–p995), as a fraction of that IC width, for margin.
#define SD_UI_DIST_AXIS_MODE_PAD_FRAC    0.04
// Optional slack below vmin when pinning the left axis (fraction of IC width; 0 = use raw vmin).
#define SD_UI_DIST_AXIS_VMIN_SLACK_FRAC  0.0

CCanvas g_sdui_canvas;
bool    g_sdui_canvas_ok = false;

// Cached layout (pixels, main chart window): client size, plot rect, right column.
int     g_sdui_chw = 800;
int     g_sdui_chh = 600;
int     g_sdui_cv_x = 16;
int     g_sdui_cv_y = 56;
int     g_sdui_cv_w = 350;
int     g_sdui_cv_h = 220;
int     g_sdui_right_x = 400;
int     g_sdui_edit_w = 180;
int     g_sdui_top_row = 8;
int     g_sdui_hdr = 26;

SdStatsSummary g_sdui_last_stats;
bool           g_sdui_last_stats_ok = false;

void SdUi_SetStatus(const long chart_id, const string msg);
void SdUi_ReportPipelineFailure(const long chart_id, const SdResult &pipeline_result);
void SdUi_DrawCanvasPlaceholder(const long chart_id);
void SdUi_DrawDistribution(const long chart_id, const SdStatsSummary &ss);
void SdUi_ApplyLayout(const long chart_id);
void SdUi_UpdateTimeCover(const long chart_id);

//+------------------------------------------------------------------+
//| Chart object name: unique per chart id + tag.                    |
//+------------------------------------------------------------------+
string SdUi_Name(const long chart_id, const string tag)
  {
   return "SDEA_" + IntegerToString(chart_id) + "_" + tag;
  }

//+------------------------------------------------------------------+
//| Expression edit object name (for OnChartEvent).                  |
//+------------------------------------------------------------------+
string SdUi_ExprObjectName(const long chart_id)
  {
   return SdUi_Name(chart_id, "expr");
  }

//+------------------------------------------------------------------+
//| Preset expressions for the example labels.                       |
//+------------------------------------------------------------------+
string SdUi_ExampleAt(const int i)
  {
   switch(i)
     {
      case 0:
         return "Close";
      case 1:
         return "Open";
      case 2:
         return "High-Low";
      case 3:
         return "RSI(14)";
      case 4:
         return "ATR(14)";
      case 5:
         return "SMA(20)";
      case 6:
         return "StdDev(20)";
      case 7:
         return "Bands(20,2).Mid";
      case 8:
         return "Volume";
      default:
         return "Close";
     }
  }

//+------------------------------------------------------------------+
//| Read CHART_WIDTH/HEIGHT_IN_PIXELS (subwindow 0); clamp tiny sizes.|
//+------------------------------------------------------------------+
void SdUi_ReadChartPixels(const long chart_id)
  {
   int client_w = (int)ChartGetInteger(chart_id, CHART_WIDTH_IN_PIXELS, 0);
   int client_h = (int)ChartGetInteger(chart_id, CHART_HEIGHT_IN_PIXELS, 0);
   if(client_w < 320)
      client_w = 640;
   if(client_h < 240)
      client_h = 480;
   g_sdui_chw = client_w;
   g_sdui_chh = client_h;
  }

//+------------------------------------------------------------------+
//| Compute plot rectangle (left) and right column (edit, examples). |
//+------------------------------------------------------------------+
void SdUi_ComputeLayout(const long chart_id)
  {
   SdUi_ReadChartPixels(chart_id);

   const int margin_px = 12;
   g_sdui_top_row = 8;
   g_sdui_hdr = 26;
   int right_column_width = 210;
   if(g_sdui_chw < 520)
      right_column_width = 168;
   if(g_sdui_chw > 1100)
      right_column_width = 240;

   g_sdui_cv_x = margin_px;
   g_sdui_cv_y = g_sdui_top_row + g_sdui_hdr + margin_px;
   g_sdui_cv_w = g_sdui_chw - right_column_width - 3 * margin_px;
   if(g_sdui_cv_w < 120)
      g_sdui_cv_w = 120;
   const int bottom_reserved_px = 92;
   g_sdui_cv_h = g_sdui_chh - g_sdui_cv_y - bottom_reserved_px - margin_px;
   if(g_sdui_cv_h < 100)
      g_sdui_cv_h = 100;

   g_sdui_right_x = g_sdui_cv_x + g_sdui_cv_w + margin_px;
   g_sdui_edit_w = g_sdui_chw - g_sdui_right_x - margin_px;
   if(g_sdui_edit_w < 96)
      g_sdui_edit_w = 96;
  }

//+------------------------------------------------------------------+
//| Map sample value to x pixel inside [left, left + plot_width).     |
//+------------------------------------------------------------------+
int SdUi_ValueToPx(const double value, const SdStatsSummary &ss, const int left, const int plot_width)
  {
   const double span = ss.vmax - ss.vmin;
   if(span <= 0.0 || !MathIsValidNumber(span))
      return left + plot_width / 2;
   double normalized = (value - ss.vmin) / span;
   if(normalized < 0.0)
      normalized = 0.0;
   if(normalized > 1.0)
      normalized = 1.0;
   return left + (int)(normalized * (double)plot_width);
  }

//+------------------------------------------------------------------+
//| Create controls once (positions updated in SdUi_PlaceControls).   |
//+------------------------------------------------------------------+
bool SdUi_CreateObjects(const long chart_id)
  {
   const string lbl_fun = SdUi_Name(chart_id, "lbl_fun");
   const string lbl_stats = SdUi_Name(chart_id, "lbl_stats");
   const string lbl_status = SdUi_Name(chart_id, "lbl_status");
   const string ed = SdUi_ExprObjectName(chart_id);

   if(ObjectFind(chart_id, lbl_fun) < 0)
      ObjectCreate(chart_id, lbl_fun, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(chart_id, lbl_fun, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chart_id, lbl_fun, OBJPROP_COLOR, SD_UI_TEXT_MAIN);
   ObjectSetInteger(chart_id, lbl_fun, OBJPROP_FONTSIZE, 9);
   ObjectSetString(chart_id, lbl_fun, OBJPROP_FONT, "Arial");
   ObjectSetString(chart_id, lbl_fun, OBJPROP_TEXT, "Function:");
   ObjectSetInteger(chart_id, lbl_fun, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chart_id, lbl_fun, OBJPROP_BACK, false);
   ObjectSetInteger(chart_id, lbl_fun, OBJPROP_ZORDER, SD_UI_Z_LABEL);

   if(ObjectFind(chart_id, lbl_stats) < 0)
      ObjectCreate(chart_id, lbl_stats, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(chart_id, lbl_stats, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chart_id, lbl_stats, OBJPROP_COLOR, SD_UI_TEXT_MAIN);
   ObjectSetInteger(chart_id, lbl_stats, OBJPROP_FONTSIZE, 9);
   ObjectSetString(chart_id, lbl_stats, OBJPROP_FONT, "Arial");
   ObjectSetString(chart_id, lbl_stats, OBJPROP_TEXT, ShortToString(0x200B));
   ObjectSetInteger(chart_id, lbl_stats, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chart_id, lbl_stats, OBJPROP_BACK, false);
   ObjectSetInteger(chart_id, lbl_stats, OBJPROP_ZORDER, SD_UI_Z_LABEL);

   if(ObjectFind(chart_id, lbl_status) < 0)
      ObjectCreate(chart_id, lbl_status, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(chart_id, lbl_status, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chart_id, lbl_status, OBJPROP_COLOR, SD_UI_TEXT_STATUS);
   ObjectSetInteger(chart_id, lbl_status, OBJPROP_FONTSIZE, 9);
   ObjectSetString(chart_id, lbl_status, OBJPROP_FONT, "Arial");
   ObjectSetString(chart_id, lbl_status, OBJPROP_TEXT, "Edit expression, then Enter (or click outside) to run.");
   ObjectSetInteger(chart_id, lbl_status, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chart_id, lbl_status, OBJPROP_BACK, false);
   ObjectSetInteger(chart_id, lbl_status, OBJPROP_ZORDER, SD_UI_Z_LABEL);

   if(ObjectFind(chart_id, ed) < 0)
      ObjectCreate(chart_id, ed, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(chart_id, ed, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chart_id, ed, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(chart_id, ed, OBJPROP_BGCOLOR, clrWhite);
   ObjectSetInteger(chart_id, ed, OBJPROP_BORDER_COLOR, clrDimGray);
   ObjectSetString(chart_id, ed, OBJPROP_FONT, "Arial");
   ObjectSetInteger(chart_id, ed, OBJPROP_FONTSIZE, 9);
   if(StringLen(ObjectGetString(chart_id, ed, OBJPROP_TEXT)) < 1)
      ObjectSetString(chart_id, ed, OBJPROP_TEXT, "Close");
   ObjectSetInteger(chart_id, ed, OBJPROP_READONLY, false);
   ObjectSetInteger(chart_id, ed, OBJPROP_BACK, false);
   ObjectSetInteger(chart_id, ed, OBJPROP_ZORDER, SD_UI_Z_EDIT);

   const string lbl_ex = SdUi_Name(chart_id, "lbl_ex_title");
   if(ObjectFind(chart_id, lbl_ex) < 0)
      ObjectCreate(chart_id, lbl_ex, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(chart_id, lbl_ex, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chart_id, lbl_ex, OBJPROP_COLOR, SD_UI_TEXT_MAIN);
   ObjectSetInteger(chart_id, lbl_ex, OBJPROP_FONTSIZE, 9);
   ObjectSetString(chart_id, lbl_ex, OBJPROP_FONT, "Arial");
   ObjectSetString(chart_id, lbl_ex, OBJPROP_TEXT, "Examples (tap to fill):");
   ObjectSetInteger(chart_id, lbl_ex, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chart_id, lbl_ex, OBJPROP_BACK, false);
   ObjectSetInteger(chart_id, lbl_ex, OBJPROP_ZORDER, SD_UI_Z_LABEL);

   for(int k = 0; k < SD_UI_EXAMPLE_COUNT; k++)
     {
      const string en = SdUi_Name(chart_id, "ex" + IntegerToString(k));
      if(ObjectFind(chart_id, en) < 0)
         ObjectCreate(chart_id, en, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(chart_id, en, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(chart_id, en, OBJPROP_COLOR, SD_UI_TEXT_LINK);
      ObjectSetInteger(chart_id, en, OBJPROP_FONTSIZE, 9);
      ObjectSetString(chart_id, en, OBJPROP_FONT, "Arial");
      ObjectSetString(chart_id, en, OBJPROP_TEXT, SdUi_ExampleAt(k));
      ObjectSetInteger(chart_id, en, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(chart_id, en, OBJPROP_BACK, false);
      ObjectSetInteger(chart_id, en, OBJPROP_ZORDER, SD_UI_Z_EXAMPLE);
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Move labels / edit from layout globals.                          |
//+------------------------------------------------------------------+
void SdUi_PlaceControls(const long chart_id)
  {
   const int top = g_sdui_top_row;
   const int rx = g_sdui_right_x;
   const int ey = top + 18;

   ObjectSetInteger(chart_id, SdUi_Name(chart_id, "lbl_fun"), OBJPROP_XDISTANCE, rx);
   ObjectSetInteger(chart_id, SdUi_Name(chart_id, "lbl_fun"), OBJPROP_YDISTANCE, top);

   ObjectSetInteger(chart_id, SdUi_ExprObjectName(chart_id), OBJPROP_XDISTANCE, rx);
   ObjectSetInteger(chart_id, SdUi_ExprObjectName(chart_id), OBJPROP_YDISTANCE, ey);
   ObjectSetInteger(chart_id, SdUi_ExprObjectName(chart_id), OBJPROP_XSIZE, g_sdui_edit_w);
   ObjectSetInteger(chart_id, SdUi_ExprObjectName(chart_id), OBJPROP_YSIZE, 20);

   ObjectSetInteger(chart_id, SdUi_Name(chart_id, "lbl_ex_title"), OBJPROP_XDISTANCE, rx);
   ObjectSetInteger(chart_id, SdUi_Name(chart_id, "lbl_ex_title"), OBJPROP_YDISTANCE, ey + 26);

   const int ex_title_y = ey + 26;
   const int ex_list_y = ex_title_y + 18;
   for(int k = 0; k < SD_UI_EXAMPLE_COUNT; k++)
     {
      ObjectSetInteger(chart_id, SdUi_Name(chart_id, "ex" + IntegerToString(k)), OBJPROP_XDISTANCE, rx);
      ObjectSetInteger(chart_id, SdUi_Name(chart_id, "ex" + IntegerToString(k)), OBJPROP_YDISTANCE, ex_list_y + k * 16);
     }

   // Stats line sits just below the plot bitmap so it does not overlap canvas labels / curve.
   const int stats_y = g_sdui_cv_y + g_sdui_cv_h + 8;
   const int status_y = stats_y + 18;
   ObjectSetInteger(chart_id, SdUi_Name(chart_id, "lbl_stats"), OBJPROP_XDISTANCE, g_sdui_cv_x);
   ObjectSetInteger(chart_id, SdUi_Name(chart_id, "lbl_stats"), OBJPROP_YDISTANCE, stats_y);

   ObjectSetInteger(chart_id, SdUi_Name(chart_id, "lbl_status"), OBJPROP_XDISTANCE, g_sdui_cv_x);
   ObjectSetInteger(chart_id, SdUi_Name(chart_id, "lbl_status"), OBJPROP_YDISTANCE, status_y);
  }

//+------------------------------------------------------------------+
//| Opaque strip over terminal time scale (not histogram axis).      |
//+------------------------------------------------------------------+
void SdUi_UpdateTimeCover(const long chart_id)
  {
   const string nm = SdUi_Name(chart_id, "time_cover");
   if(ObjectFind(chart_id, nm) < 0)
      ObjectCreate(chart_id, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(chart_id, nm, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(chart_id, nm, OBJPROP_XDISTANCE, 0);
   ObjectSetInteger(chart_id, nm, OBJPROP_YDISTANCE, 0);
   ObjectSetInteger(chart_id, nm, OBJPROP_XSIZE, g_sdui_chw);
   ObjectSetInteger(chart_id, nm, OBJPROP_YSIZE, SD_UI_TIME_COVER_H);
   ObjectSetInteger(chart_id, nm, OBJPROP_BGCOLOR, SD_UI_PANEL_BG);
   ObjectSetInteger(chart_id, nm, OBJPROP_BORDER_COLOR, SD_UI_PANEL_BG);
   ObjectSetInteger(chart_id, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(chart_id, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chart_id, nm, OBJPROP_BACK, false);
   ObjectSetInteger(chart_id, nm, OBJPROP_ZORDER, SD_UI_Z_TIMECOVER);
  }

//+------------------------------------------------------------------+
//| Full-screen panel + canvas size/position + controls.             |
//+------------------------------------------------------------------+
void SdUi_ApplyLayout(const long chart_id)
  {
   SdUi_ComputeLayout(chart_id);

   const string panel_name = SdUi_Name(chart_id, "panel_bg");
   if(ObjectFind(chart_id, panel_name) >= 0)
     {
      ObjectSetInteger(chart_id, panel_name, OBJPROP_XDISTANCE, 0);
      ObjectSetInteger(chart_id, panel_name, OBJPROP_YDISTANCE, 0);
      ObjectSetInteger(chart_id, panel_name, OBJPROP_XSIZE, g_sdui_chw);
      ObjectSetInteger(chart_id, panel_name, OBJPROP_YSIZE, g_sdui_chh);
      ObjectSetInteger(chart_id, panel_name, OBJPROP_BACK, false);
      ObjectSetInteger(chart_id, panel_name, OBJPROP_ZORDER, SD_UI_Z_PANEL);
     }

   const string canvas_object_name = SdUi_Name(chart_id, "canvas");
   if(ObjectFind(chart_id, canvas_object_name) >= 0)
     {
      ObjectSetInteger(chart_id, canvas_object_name, OBJPROP_XDISTANCE, g_sdui_cv_x);
      ObjectSetInteger(chart_id, canvas_object_name, OBJPROP_YDISTANCE, g_sdui_cv_y);
      ObjectSetInteger(chart_id, canvas_object_name, OBJPROP_XSIZE, g_sdui_cv_w);
      ObjectSetInteger(chart_id, canvas_object_name, OBJPROP_YSIZE, g_sdui_cv_h);
      ObjectSetInteger(chart_id, canvas_object_name, OBJPROP_BACK, false);
      ObjectSetInteger(chart_id, canvas_object_name, OBJPROP_ZORDER, SD_UI_Z_CANVAS);
     }

   SdUi_UpdateTimeCover(chart_id);

   if(g_sdui_canvas_ok)
     {
      g_sdui_canvas.Resize(g_sdui_cv_w, g_sdui_cv_h);
      if(g_sdui_last_stats_ok)
         SdUi_DrawDistribution(chart_id, g_sdui_last_stats);
      else
         SdUi_DrawCanvasPlaceholder(chart_id);
     }

   SdUi_PlaceControls(chart_id);
   ChartRedraw(chart_id);
  }

//+------------------------------------------------------------------+
//| Chart was resized — reflow overlay.                              |
//+------------------------------------------------------------------+
void SdUi_OnChartResize(const long chart_id)
  {
   if(!g_sdui_canvas_ok)
      return;
   SdUi_ApplyLayout(chart_id);
  }

//+------------------------------------------------------------------+
//| Initialize canvas + objects.                                     |
//+------------------------------------------------------------------+
bool SdUi_Init(const long chart_id)
  {
   Print("[SdUi_Init] START chart_id=", chart_id);
   
   g_sdui_canvas_ok = false;
   g_sdui_last_stats_ok = false;
   const string canvas_object_name = SdUi_Name(chart_id, "canvas");
   ObjectDelete(chart_id, canvas_object_name);

   SdUi_ComputeLayout(chart_id);
   Print("[SdUi_Init] Layout computed: chw=", g_sdui_chw, " chh=", g_sdui_chh,
         " cv_x=", g_sdui_cv_x, " cv_y=", g_sdui_cv_y,
         " cv_w=", g_sdui_cv_w, " cv_h=", g_sdui_cv_h);

   const string panel_name = SdUi_Name(chart_id, "panel_bg");
   ObjectDelete(chart_id, panel_name);
   ObjectCreate(chart_id, panel_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(chart_id, panel_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chart_id, panel_name, OBJPROP_XDISTANCE, 0);
   ObjectSetInteger(chart_id, panel_name, OBJPROP_YDISTANCE, 0);
   ObjectSetInteger(chart_id, panel_name, OBJPROP_XSIZE, g_sdui_chw);
   ObjectSetInteger(chart_id, panel_name, OBJPROP_YSIZE, g_sdui_chh);
   ObjectSetInteger(chart_id, panel_name, OBJPROP_BGCOLOR, SD_UI_PANEL_BG);
   ObjectSetInteger(chart_id, panel_name, OBJPROP_BORDER_COLOR, SD_UI_PANEL_BR);
   ObjectSetInteger(chart_id, panel_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(chart_id, panel_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chart_id, panel_name, OBJPROP_BACK, false);
   ObjectSetInteger(chart_id, panel_name, OBJPROP_ZORDER, SD_UI_Z_PANEL);

   Print("[SdUi_Init] Creating canvas bitmap: ", canvas_object_name, " at (", g_sdui_cv_x, ",", g_sdui_cv_y, ") size ", g_sdui_cv_w, "x", g_sdui_cv_h);
   if(!g_sdui_canvas.CreateBitmapLabel(chart_id, 0, canvas_object_name, g_sdui_cv_x, g_sdui_cv_y,
                                       g_sdui_cv_w, g_sdui_cv_h, COLOR_FORMAT_ARGB_NORMALIZE))
     {
      Print("[SdUi_Init] ERROR: CreateBitmapLabel failed for " + canvas_object_name);
      return false;
     }
   Print("[SdUi_Init] Canvas created successfully");
   
   ObjectSetInteger(chart_id, canvas_object_name, OBJPROP_ZORDER, SD_UI_Z_CANVAS);
   ObjectSetInteger(chart_id, canvas_object_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chart_id, canvas_object_name, OBJPROP_BACK, false);

   SdUi_UpdateTimeCover(chart_id);

   g_sdui_canvas_ok = true;
   Print("[SdUi_Init] g_sdui_canvas_ok = true");
   
   SdUi_DrawCanvasPlaceholder(chart_id);

   if(!SdUi_CreateObjects(chart_id))
     {
      Print("[SdUi_Init] ERROR: SdUi_CreateObjects failed");
      return false;
     }
   SdUi_PlaceControls(chart_id);
   ChartRedraw(chart_id);
   
   Print("[SdUi_Init] END - Success");
   return true;
  }

//+------------------------------------------------------------------+
//| Placeholder text inside histogram bitmap.                        |
//+------------------------------------------------------------------+
void SdUi_DrawCanvasPlaceholder(const long chart_id)
  {
   if(!g_sdui_canvas_ok)
      return;
   const int canvas_w = g_sdui_cv_w;
   const int canvas_h = g_sdui_cv_h;
   if(canvas_w < 4 || canvas_h < 4)
      return;

   g_sdui_canvas.Erase(ColorToARGB(clrWhite, 255));
   g_sdui_canvas.Rectangle(1, 1, canvas_w - 2, canvas_h - 2, ColorToARGB(clrSilver, 255));
   g_sdui_canvas.FontSet("Arial", 10);
   int text_y = canvas_h / 2 - 18;
   if(text_y < 8)
      text_y = 8;
   g_sdui_canvas.TextOut(14, text_y, "Histogram after Enter", ColorToARGB(clrDimGray, 255), 0);
   g_sdui_canvas.TextOut(14, text_y + 16, "(click field, then Enter)", ColorToARGB(clrDimGray, 255), 0);
   g_sdui_canvas.Update();
   ChartRedraw(chart_id);
  }

//+------------------------------------------------------------------+
//| Release canvas and UI objects.                                   |
//| CCanvas::Destroy() releases the bitmap; ObjectDelete removes     |
//| chart objects.                                                   |
//+------------------------------------------------------------------+
void SdUi_Deinit(const long chart_id)
  {
   if(g_sdui_canvas_ok)
     {
      g_sdui_canvas.Destroy();
      g_sdui_canvas_ok = false;
     }
   g_sdui_last_stats_ok = false;
   ObjectDelete(chart_id, SdUi_Name(chart_id, "canvas"));
   ObjectDelete(chart_id, SdUi_Name(chart_id, "panel_bg"));
   ObjectDelete(chart_id, SdUi_Name(chart_id, "time_cover"));
   ObjectDelete(chart_id, SdUi_ExprObjectName(chart_id));
   ObjectDelete(chart_id, SdUi_Name(chart_id, "lbl_fun"));
   ObjectDelete(chart_id, SdUi_Name(chart_id, "lbl_stats"));
   ObjectDelete(chart_id, SdUi_Name(chart_id, "lbl_status"));
   ObjectDelete(chart_id, SdUi_Name(chart_id, "lbl_ex_title"));
   for(int k = 0; k < SD_UI_EXAMPLE_COUNT; k++)
      ObjectDelete(chart_id, SdUi_Name(chart_id, "ex" + IntegerToString(k)));
   ChartRedraw(chart_id);
  }

//+------------------------------------------------------------------+
//| Write expression field (does not run the pipeline).              |
//+------------------------------------------------------------------+
void SdUi_SetExpressionText(const long chart_id, const string t)
  {
   ObjectSetString(chart_id, SdUi_ExprObjectName(chart_id), OBJPROP_TEXT, t);
   ChartRedraw(chart_id);
  }

//+------------------------------------------------------------------+
//| If sparam is an example label, copy text into the edit field.    |
//+------------------------------------------------------------------+
bool SdUi_TryExampleClick(const long chart_id, const string sparam)
  {
   for(int k = 0; k < SD_UI_EXAMPLE_COUNT; k++)
     {
      if(sparam == SdUi_Name(chart_id, "ex" + IntegerToString(k)))
        {
         SdUi_SetExpressionText(chart_id, SdUi_ExampleAt(k));
         SdUi_SetStatus(chart_id, "Example loaded — Enter (or click outside edit) to run.");
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Read trimmed expression from edit.                               |
//+------------------------------------------------------------------+
string SdUi_GetExpressionText(const long chart_id)
  {
   string t = ObjectGetString(chart_id, SdUi_ExprObjectName(chart_id), OBJPROP_TEXT);
   StringTrimLeft(t);
   StringTrimRight(t);
   return t;
  }

//+------------------------------------------------------------------+
//| Status line (errors / OK).                                       |
//+------------------------------------------------------------------+
void SdUi_SetStatus(const long chart_id, const string msg)
  {
   // Empty OBJPROP_TEXT shows the placeholder word "Label" in MT5.
   const string t = (StringLen(msg) > 0) ? msg : ShortToString(0x200B);
   ObjectSetString(chart_id, SdUi_Name(chart_id, "lbl_status"), OBJPROP_TEXT, t);
   ChartRedraw(chart_id);
  }

//+------------------------------------------------------------------+
//| Pipeline error: show status; do not draw invalid stats.            |
//| If a previous run succeeded, redraw that distribution so the     |
//| chart does not show a misleading blank or wrong plot.              |
//+------------------------------------------------------------------+
void SdUi_ReportPipelineFailure(const long chart_id, const SdResult &pipeline_result)
  {
   SdUi_SetStatus(chart_id, SdResult_FormatUserMessage(pipeline_result));
   if(g_sdui_canvas_ok && g_sdui_last_stats_ok)
     {
      SdUi_SetStats(chart_id, g_sdui_last_stats);
      SdUi_DrawDistribution(chart_id, g_sdui_last_stats);
     }
  }

//+------------------------------------------------------------------+
//| Numeric summary under the plot.                                  |
//+------------------------------------------------------------------+
void SdUi_SetStats(const long chart_id, const SdStatsSummary &ss)
  {
   string s = "";
   if(ss.has_data)
      s = StringFormat("n=%d  mean=%.5G  std=%.5G  min=%.5G  max=%.5G",
                       ss.count, ss.mean, ss.stdev, ss.vmin, ss.vmax);
   if(StringLen(s) < 1)
      s = ShortToString(0x200B);
   ObjectSetString(chart_id, SdUi_Name(chart_id, "lbl_stats"), OBJPROP_TEXT, s);
  }

//+------------------------------------------------------------------+
//| Format value to concise string (auto digits).                    |
//+------------------------------------------------------------------+
string SdUi_FormatValue(const double value)
  {
   const double av = MathAbs(value);
   int d = 2;
   if(av < 0.0001 && av > 0)
      d = 6;
   else if(av < 0.01)
      d = 5;
   else if(av < 1.0)
      d = 4;
   else if(av < 100.0)
      d = 2;
   else if(av < 10000.0)
      d = 1;
   else
      d = 0;
   return DoubleToString(value, d);
  }

//+------------------------------------------------------------------+
//| Percentile vertical: ghost LineThick (offset + reduced alpha), then main. |
//+------------------------------------------------------------------+
void SdUi_DrawBandVerticalDouble(const int pixel_x, const int y_top, const int y_bottom, const uint clr,
                                 const int thick, const int plot_left, const int plot_right)
  {
   if(pixel_x < plot_left || pixel_x > plot_right || thick < 1)
      return;
   const uint rgb = clr & 0x00FFFFFF;
   const uint clr_soft = rgb | (((uint)SD_UI_BAND_LINE_GHOST_ALPHA) << 24);
   const int offset_px = SD_UI_BAND_LINE_OFFSET;
   const int ghost_x = pixel_x + offset_px;
   if(ghost_x <= plot_right)
      g_sdui_canvas.LineThick(ghost_x, y_top, ghost_x, y_bottom, clr_soft, thick, STYLE_SOLID, LINE_END_BUTT);
   else if(pixel_x - offset_px >= plot_left)
      g_sdui_canvas.LineThick(pixel_x - offset_px, y_top, pixel_x - offset_px, y_bottom, clr_soft, thick, STYLE_SOLID, LINE_END_BUTT);
   g_sdui_canvas.LineThick(pixel_x, y_top, pixel_x, y_bottom, clr, thick, STYLE_SOLID, LINE_END_BUTT);
  }

//+------------------------------------------------------------------+
//| Band legend beside the vertical (not centered on the line).      |
//+------------------------------------------------------------------+
void SdUi_DrawBandLabelBeside(const int pixel_x, const int y_baseline, const string text, const uint clr,
                              const int plot_left, const int plot_right)
  {
   if(pixel_x < plot_left || pixel_x > plot_right)
      return;
   const int plot_mid_x = (plot_left + plot_right) / 2;
   const int gap_px = SD_UI_BAND_LBL_GAP;
   if(pixel_x < plot_mid_x)
     {
      const int label_x = pixel_x - gap_px;
      if(label_x < plot_left + 2)
         g_sdui_canvas.TextOut(pixel_x + gap_px, y_baseline, text, clr, TA_LEFT);
      else
         g_sdui_canvas.TextOut(label_x, y_baseline, text, clr, TA_RIGHT);
     }
   else if(pixel_x > plot_mid_x)
     {
      const int label_x = pixel_x + gap_px;
      if(label_x > plot_right - 2)
         g_sdui_canvas.TextOut(pixel_x - gap_px, y_baseline, text, clr, TA_RIGHT);
      else
         g_sdui_canvas.TextOut(label_x, y_baseline, text, clr, TA_LEFT);
     }
   else
      g_sdui_canvas.TextOut(pixel_x + gap_px, y_baseline, text, clr, TA_LEFT);
  }

//+------------------------------------------------------------------+
//| Tick + numeric label on the x baseline at the same pixel as the   |
//| vertical CI line (value = empirical percentile on the sample).    |
//+------------------------------------------------------------------+
void SdUi_DrawXAxisTickAligned(const int pixel_x, const int baseline_y, const double value,
                                const uint clr, const int plot_left, const int plot_right)
  {
   if(pixel_x < plot_left || pixel_x > plot_right)
      return;
   g_sdui_canvas.Line(pixel_x, baseline_y, pixel_x, baseline_y + 4, clr);
   g_sdui_canvas.TextOut(pixel_x, baseline_y + 4, SdUi_FormatValue(value), clr, TA_CENTER);
  }

//+------------------------------------------------------------------+
//| Centre of the histogram bin with largest count (empirical mode).    |
//| Falls back to median if bins are missing or empty.                 |
//+------------------------------------------------------------------+
double SdUi_HistogramModeCenter(const SdStatsSummary &ss)
  {
   if(!ss.has_data || ss.bin_count < 1)
      return ss.p50;
   int best_bin = 0;
   int best_count = -1;
   for(int bi = 0; bi < ss.bin_count; bi++)
     {
      if(ss.bin_counts[bi] > best_count)
        {
         best_count = ss.bin_counts[bi];
         best_bin = bi;
        }
     }
   if(best_count < 1)
      return ss.p50;
   const double lo = ss.bin_edges[best_bin];
   const double hi = ss.bin_edges[best_bin + 1];
   if(!MathIsValidNumber(lo) || !MathIsValidNumber(hi))
      return ss.p50;
   return 0.5 * (lo + hi);
  }

//+------------------------------------------------------------------+
//| Normal PDF overlay + empirical bands + axes (value vs frequency). |
//| PDF fill uses vertical strips (FillPolygon avoided — MT5 crash).  |
//+------------------------------------------------------------------+
void SdUi_DrawDistribution(const long chart_id, const SdStatsSummary &ss)
  {
   if(!g_sdui_canvas_ok)
      return;
   
   if(!ss.has_data)
      return;

   g_sdui_last_stats = ss;
   g_sdui_last_stats_ok = true;

   const int canvas_w = g_sdui_cv_w;
   const int canvas_h = g_sdui_cv_h;
   
   if(canvas_w < 100 || canvas_h < 100)
      return;

   g_sdui_canvas.Erase(ColorToARGB(clrWhite, 255));

   const int pad_left = 60;
   const int pad_top = 26;
   const int pad_right = 14;
   const int pad_bottom = 56;
   const int plot_left = pad_left;
   const int plot_top = pad_top;
   const int plot_right = canvas_w - pad_right;
   const int plot_bottom = canvas_h - pad_bottom;
   
   if(plot_right <= plot_left + 40 || plot_bottom <= plot_top + 40)
      return;

   const int plot_width = plot_right - plot_left;
   const int plot_height = plot_bottom - plot_top;
   const int baseline_y = plot_top + plot_height;

   g_sdui_canvas.FontSet("Arial", SD_UI_DIST_AXIS_LABEL_PT);

   if(!MathIsValidNumber(ss.mean) || !MathIsValidNumber(ss.vmin) || !MathIsValidNumber(ss.vmax))
     {
      g_sdui_canvas.TextOut(plot_left + plot_width / 2, plot_top + plot_height / 2, "Invalid data (NaN)", ColorToARGB(clrRed, 255), TA_CENTER);
      g_sdui_canvas.Update();
      ChartRedraw(chart_id);
      return;
     }

   const double mean = ss.mean;
   double sigma = ss.stdev;
   
   if(!MathIsValidNumber(sigma) || sigma <= 0.0)
     {
      const double sample_range = ss.vmax - ss.vmin;
      if(!MathIsValidNumber(sample_range) || sample_range <= 0.0)
         sigma = 1.0;
      else
         sigma = sample_range / 6.0;
     }

   // Horizontal view: anchor the IC band (p005..p995) with padding; place the mode (histogram peak)
   // at its true value. Asymmetric margins — symmetric half-width around the mode pulls the left edge
   // far below vmin when the right tail (to p995) is long, wasting empty space. Right edge is not
   // stretched to vmax (avoids re-squeezing); true min/max stay in the stats line.
   double x_axis_min;
   double x_axis_max;
   const bool pct_ok = MathIsValidNumber(ss.p005) && MathIsValidNumber(ss.p995)
                       && ss.p005 < ss.p995;

   if(pct_ok)
     {
      const double mode_center = SdUi_HistogramModeCenter(ss);
      const double ic_span = ss.p995 - ss.p005;
      const double pad = SD_UI_DIST_AXIS_MODE_PAD_FRAC * ic_span;
      const double vmin_slack = SD_UI_DIST_AXIS_VMIN_SLACK_FRAC * ic_span;
      const double left_lim_ic = ss.p005 - pad;
      const double left_lim_v = ss.vmin - vmin_slack;
      x_axis_min = left_lim_ic;
      if(x_axis_min < left_lim_v)
         x_axis_min = left_lim_v;
      x_axis_max = mode_center + (ss.p995 - mode_center) + pad;
      if(x_axis_min >= x_axis_max)
        {
         x_axis_min = ss.p005;
         x_axis_max = ss.p995;
        }
     }
   else
     {
      x_axis_min = mean - 4.0 * sigma;
      x_axis_max = mean + 4.0 * sigma;
      if(x_axis_min > ss.vmin)
         x_axis_min = ss.vmin;
      if(x_axis_max < ss.vmax)
         x_axis_max = ss.vmax;
      if(x_axis_min >= x_axis_max)
        {
         x_axis_min = mean - 4.0 * sigma;
         x_axis_max = mean + 4.0 * sigma;
         if(x_axis_min > ss.vmin)
            x_axis_min = ss.vmin;
         if(x_axis_max < ss.vmax)
            x_axis_max = ss.vmax;
        }
     }
   const double x_axis_span = x_axis_max - x_axis_min;
   
   if(!MathIsValidNumber(x_axis_span) || x_axis_span <= 0.0)
     {
      g_sdui_canvas.TextOut(plot_left + plot_width / 2, plot_top + plot_height / 2, "Invalid range", ColorToARGB(clrRed, 255), TA_CENTER);
      g_sdui_canvas.Update();
      ChartRedraw(chart_id);
      return;
     }

   const double inv_sqrt_2pi = 0.3989422804014327;
   const double pdf_at_mean = inv_sqrt_2pi / sigma;
   const double pdf_peak = pdf_at_mean;

   const uint fill_argb = ColorToARGB(C'198,230,240', 180);
   const uint curve_argb = ColorToARGB(C'0,128,132', 255);

   for(int column_x = plot_left; column_x <= plot_right; column_x++)
     {
      double horizontal_t = (plot_width <= 0) ? 0.0 : (double)(column_x - plot_left) / (double)plot_width;
      if(horizontal_t < 0.0)
         horizontal_t = 0.0;
      if(horizontal_t > 1.0)
         horizontal_t = 1.0;
      const double x_value = x_axis_min + horizontal_t * x_axis_span;
      const double z_score = (x_value - mean) / sigma;
      const double pdf_value = inv_sqrt_2pi / sigma * MathExp(-0.5 * z_score * z_score);
      double bar_height_px = pdf_value / pdf_peak * (double)plot_height;
      if(!MathIsValidNumber(bar_height_px))
         bar_height_px = 0.0;
      if(bar_height_px < 0.0)
         bar_height_px = 0.0;
      if(bar_height_px > (double)plot_height)
         bar_height_px = (double)plot_height;
      int bar_top_y = baseline_y - (int)MathRound(bar_height_px);
      if(bar_top_y < plot_top)
         bar_top_y = plot_top;
      if(bar_top_y > baseline_y)
         bar_top_y = baseline_y;
      if(bar_top_y < baseline_y)
         g_sdui_canvas.FillRectangle(column_x, bar_top_y, column_x, baseline_y, fill_argb);
     }

   int curve_x[];
   int curve_y[];
   int curve_point_count = plot_width;
   if(curve_point_count < 80)
      curve_point_count = 80;
   if(curve_point_count > 400)
      curve_point_count = 400;

   if(ArrayResize(curve_x, curve_point_count) != curve_point_count || ArrayResize(curve_y, curve_point_count) != curve_point_count)
      return;

   for(int segment_index = 0; segment_index < curve_point_count; segment_index++)
     {
      const double t_seg = (curve_point_count <= 1) ? 0.0 : (double)segment_index / (double)(curve_point_count - 1);
      int pixel_x = plot_left + (int)(t_seg * (double)(plot_width - 1));
      if(pixel_x < plot_left)
         pixel_x = plot_left;
      if(pixel_x > plot_right)
         pixel_x = plot_right;
      const double x_value = x_axis_min + t_seg * x_axis_span;
      const double z_score = (x_value - mean) / sigma;
      const double pdf_value = inv_sqrt_2pi / sigma * MathExp(-0.5 * z_score * z_score);
      double bar_height_px = pdf_value / pdf_peak * (double)plot_height;
      if(!MathIsValidNumber(bar_height_px))
         bar_height_px = 0.0;
      if(bar_height_px < 0.0)
         bar_height_px = 0.0;
      if(bar_height_px > (double)plot_height)
         bar_height_px = (double)plot_height;
      int pixel_y = baseline_y - (int)MathRound(bar_height_px);
      if(pixel_y < plot_top)
         pixel_y = plot_top;
      if(pixel_y > baseline_y)
         pixel_y = baseline_y;
      curve_x[segment_index] = pixel_x;
      curve_y[segment_index] = pixel_y;
     }

   for(int segment_index = 0; segment_index < curve_point_count - 1; segment_index++)
      g_sdui_canvas.LineThick(curve_x[segment_index], curve_y[segment_index],
                              curve_x[segment_index + 1], curve_y[segment_index + 1], curve_argb,
                               SD_UI_DIST_CURVE_LINE_PX, STYLE_SOLID, LINE_END_ROUND);

   const uint band_color_99 = ColorToARGB(C'255,102,102', 200);
   const uint band_color_95 = ColorToARGB(C'255,153,51', 200);
   const uint band_color_90 = ColorToARGB(C'255,204,0', 200);
   const uint band_color_85 = ColorToARGB(C'153,204,0', 200);
   const uint band_color_50 = ColorToARGB(C'0,153,76', 220);
   const uint band_color_median = ColorToARGB(clrBlue, 255);

   const int px_p005 = plot_left + (int)(((ss.p005 - x_axis_min) / x_axis_span) * (double)plot_width);
   const int px_p995 = plot_left + (int)(((ss.p995 - x_axis_min) / x_axis_span) * (double)plot_width);
   const int px_p025 = plot_left + (int)(((ss.p025 - x_axis_min) / x_axis_span) * (double)plot_width);
   const int px_p975 = plot_left + (int)(((ss.p975 - x_axis_min) / x_axis_span) * (double)plot_width);
   const int px_p05  = plot_left + (int)(((ss.p05 - x_axis_min) / x_axis_span) * (double)plot_width);
   const int px_p95  = plot_left + (int)(((ss.p95 - x_axis_min) / x_axis_span) * (double)plot_width);
   const int px_p075 = plot_left + (int)(((ss.p075 - x_axis_min) / x_axis_span) * (double)plot_width);
   const int px_p925 = plot_left + (int)(((ss.p925 - x_axis_min) / x_axis_span) * (double)plot_width);
   const int px_p25  = plot_left + (int)(((ss.p25 - x_axis_min) / x_axis_span) * (double)plot_width);
   const int px_p75  = plot_left + (int)(((ss.p75 - x_axis_min) / x_axis_span) * (double)plot_width);
   const int px_p50  = plot_left + (int)(((ss.p50 - x_axis_min) / x_axis_span) * (double)plot_width);

   if(px_p005 >= plot_left && px_p005 <= plot_right)
      SdUi_DrawBandVerticalDouble(px_p005, plot_top, baseline_y, band_color_99, SD_UI_DIST_BAND_LINE_PX, plot_left, plot_right);
   if(px_p995 >= plot_left && px_p995 <= plot_right)
      SdUi_DrawBandVerticalDouble(px_p995, plot_top, baseline_y, band_color_99, SD_UI_DIST_BAND_LINE_PX, plot_left, plot_right);

   if(px_p025 >= plot_left && px_p025 <= plot_right)
      SdUi_DrawBandVerticalDouble(px_p025, plot_top, baseline_y, band_color_95, SD_UI_DIST_BAND_LINE_PX, plot_left, plot_right);
   if(px_p975 >= plot_left && px_p975 <= plot_right)
      SdUi_DrawBandVerticalDouble(px_p975, plot_top, baseline_y, band_color_95, SD_UI_DIST_BAND_LINE_PX, plot_left, plot_right);

   if(px_p05 >= plot_left && px_p05 <= plot_right)
      SdUi_DrawBandVerticalDouble(px_p05, plot_top, baseline_y, band_color_90, SD_UI_DIST_BAND_LINE_PX, plot_left, plot_right);
   if(px_p95 >= plot_left && px_p95 <= plot_right)
      SdUi_DrawBandVerticalDouble(px_p95, plot_top, baseline_y, band_color_90, SD_UI_DIST_BAND_LINE_PX, plot_left, plot_right);

   if(px_p075 >= plot_left && px_p075 <= plot_right)
      SdUi_DrawBandVerticalDouble(px_p075, plot_top, baseline_y, band_color_85, SD_UI_DIST_BAND_LINE_PX, plot_left, plot_right);
   if(px_p925 >= plot_left && px_p925 <= plot_right)
      SdUi_DrawBandVerticalDouble(px_p925, plot_top, baseline_y, band_color_85, SD_UI_DIST_BAND_LINE_PX, plot_left, plot_right);

   if(px_p25 >= plot_left && px_p25 <= plot_right)
      SdUi_DrawBandVerticalDouble(px_p25, plot_top, baseline_y, band_color_50, SD_UI_DIST_BAND_LINE_PX, plot_left, plot_right);
   if(px_p75 >= plot_left && px_p75 <= plot_right)
      SdUi_DrawBandVerticalDouble(px_p75, plot_top, baseline_y, band_color_50, SD_UI_DIST_BAND_LINE_PX, plot_left, plot_right);

   if(px_p50 >= plot_left && px_p50 <= plot_right)
      SdUi_DrawBandVerticalDouble(px_p50, plot_top, baseline_y, band_color_median, SD_UI_DIST_BAND_LINE_PX, plot_left, plot_right);

   g_sdui_canvas.Rectangle(plot_left, plot_top, plot_right, baseline_y, ColorToARGB(clrBlack, 255));

   const int band_label_y = plot_top + 4;
   g_sdui_canvas.FontSet("Arial", SD_UI_DIST_BAND_LABEL_PT);
   if(px_p005 >= plot_left && px_p005 <= plot_right)
      SdUi_DrawBandLabelBeside(px_p005, band_label_y, "99%", band_color_99, plot_left, plot_right);
   if(px_p995 >= plot_left && px_p995 <= plot_right)
      SdUi_DrawBandLabelBeside(px_p995, band_label_y, "99%", band_color_99, plot_left, plot_right);
   if(px_p025 >= plot_left && px_p025 <= plot_right)
      SdUi_DrawBandLabelBeside(px_p025, band_label_y, "95%", band_color_95, plot_left, plot_right);
   if(px_p975 >= plot_left && px_p975 <= plot_right)
      SdUi_DrawBandLabelBeside(px_p975, band_label_y, "95%", band_color_95, plot_left, plot_right);
   if(px_p05 >= plot_left && px_p05 <= plot_right)
      SdUi_DrawBandLabelBeside(px_p05, band_label_y, "90%", band_color_90, plot_left, plot_right);
   if(px_p95 >= plot_left && px_p95 <= plot_right)
      SdUi_DrawBandLabelBeside(px_p95, band_label_y, "90%", band_color_90, plot_left, plot_right);
   if(px_p075 >= plot_left && px_p075 <= plot_right)
      SdUi_DrawBandLabelBeside(px_p075, band_label_y, "85%", band_color_85, plot_left, plot_right);
   if(px_p925 >= plot_left && px_p925 <= plot_right)
      SdUi_DrawBandLabelBeside(px_p925, band_label_y, "85%", band_color_85, plot_left, plot_right);
   if(px_p25 >= plot_left && px_p25 <= plot_right)
      SdUi_DrawBandLabelBeside(px_p25, band_label_y, "50%", band_color_50, plot_left, plot_right);
   if(px_p75 >= plot_left && px_p75 <= plot_right)
      SdUi_DrawBandLabelBeside(px_p75, band_label_y, "50%", band_color_50, plot_left, plot_right);
   if(px_p50 >= plot_left && px_p50 <= plot_right)
      SdUi_DrawBandLabelBeside(px_p50, band_label_y, "Median", band_color_median, plot_left, plot_right);

   const uint axis_color = ColorToARGB(clrBlack, 255);

   g_sdui_canvas.FontSet("Arial", SD_UI_DIST_AXIS_LABEL_PT);

   // Axis extents (PDF view range) — min/max at the plot edges.
   g_sdui_canvas.Line(plot_left, baseline_y, plot_left, baseline_y + 4, axis_color);
   g_sdui_canvas.TextOut(plot_left, baseline_y + 4, SdUi_FormatValue(x_axis_min), axis_color, TA_CENTER);
   g_sdui_canvas.Line(plot_right, baseline_y, plot_right, baseline_y + 4, axis_color);
   g_sdui_canvas.TextOut(plot_right, baseline_y + 4, SdUi_FormatValue(x_axis_max), axis_color, TA_CENTER);

   // Percentile / median values on the x-axis aligned with each vertical CI line (sample quantiles).
   const int edge_slack_px = 3;
   int tick_px[13];
   double tick_val[13];
   int tick_count = 0;
   if(px_p005 >= plot_left && px_p005 <= plot_right &&
      MathAbs(px_p005 - plot_left) > edge_slack_px && MathAbs(px_p005 - plot_right) > edge_slack_px)
     {
      tick_px[tick_count] = px_p005;
      tick_val[tick_count] = ss.p005;
      tick_count++;
     }
   if(px_p995 >= plot_left && px_p995 <= plot_right &&
      MathAbs(px_p995 - plot_left) > edge_slack_px && MathAbs(px_p995 - plot_right) > edge_slack_px)
     {
      tick_px[tick_count] = px_p995;
      tick_val[tick_count] = ss.p995;
      tick_count++;
     }
   if(px_p025 >= plot_left && px_p025 <= plot_right &&
      MathAbs(px_p025 - plot_left) > edge_slack_px && MathAbs(px_p025 - plot_right) > edge_slack_px)
     {
      tick_px[tick_count] = px_p025;
      tick_val[tick_count] = ss.p025;
      tick_count++;
     }
   if(px_p975 >= plot_left && px_p975 <= plot_right &&
      MathAbs(px_p975 - plot_left) > edge_slack_px && MathAbs(px_p975 - plot_right) > edge_slack_px)
     {
      tick_px[tick_count] = px_p975;
      tick_val[tick_count] = ss.p975;
      tick_count++;
     }
   if(px_p05 >= plot_left && px_p05 <= plot_right &&
      MathAbs(px_p05 - plot_left) > edge_slack_px && MathAbs(px_p05 - plot_right) > edge_slack_px)
     {
      tick_px[tick_count] = px_p05;
      tick_val[tick_count] = ss.p05;
      tick_count++;
     }
   if(px_p95 >= plot_left && px_p95 <= plot_right &&
      MathAbs(px_p95 - plot_left) > edge_slack_px && MathAbs(px_p95 - plot_right) > edge_slack_px)
     {
      tick_px[tick_count] = px_p95;
      tick_val[tick_count] = ss.p95;
      tick_count++;
     }
   if(px_p075 >= plot_left && px_p075 <= plot_right &&
      MathAbs(px_p075 - plot_left) > edge_slack_px && MathAbs(px_p075 - plot_right) > edge_slack_px)
     {
      tick_px[tick_count] = px_p075;
      tick_val[tick_count] = ss.p075;
      tick_count++;
     }
   if(px_p925 >= plot_left && px_p925 <= plot_right &&
      MathAbs(px_p925 - plot_left) > edge_slack_px && MathAbs(px_p925 - plot_right) > edge_slack_px)
     {
      tick_px[tick_count] = px_p925;
      tick_val[tick_count] = ss.p925;
      tick_count++;
     }
   if(px_p25 >= plot_left && px_p25 <= plot_right &&
      MathAbs(px_p25 - plot_left) > edge_slack_px && MathAbs(px_p25 - plot_right) > edge_slack_px)
     {
      tick_px[tick_count] = px_p25;
      tick_val[tick_count] = ss.p25;
      tick_count++;
     }
   if(px_p75 >= plot_left && px_p75 <= plot_right &&
      MathAbs(px_p75 - plot_left) > edge_slack_px && MathAbs(px_p75 - plot_right) > edge_slack_px)
     {
      tick_px[tick_count] = px_p75;
      tick_val[tick_count] = ss.p75;
      tick_count++;
     }
   if(px_p50 >= plot_left && px_p50 <= plot_right &&
      MathAbs(px_p50 - plot_left) > edge_slack_px && MathAbs(px_p50 - plot_right) > edge_slack_px)
     {
      tick_px[tick_count] = px_p50;
      tick_val[tick_count] = ss.p50;
      tick_count++;
     }

   for(int sort_i = 0; sort_i < tick_count - 1; sort_i++)
     {
      for(int sort_j = 0; sort_j < tick_count - 1 - sort_i; sort_j++)
        {
         if(tick_px[sort_j] > tick_px[sort_j + 1])
           {
            const int tmp_px = tick_px[sort_j];
            tick_px[sort_j] = tick_px[sort_j + 1];
            tick_px[sort_j + 1] = tmp_px;
            const double tmp_v = tick_val[sort_j];
            tick_val[sort_j] = tick_val[sort_j + 1];
            tick_val[sort_j + 1] = tmp_v;
           }
        }
     }

   for(int tick_i = 0; tick_i < tick_count; tick_i++)
     {
      if(tick_i > 0 && tick_px[tick_i] == tick_px[tick_i - 1])
         continue;
      SdUi_DrawXAxisTickAligned(tick_px[tick_i], baseline_y, tick_val[tick_i], axis_color, plot_left, plot_right);
     }

   g_sdui_canvas.TextOut(plot_left - 4, baseline_y, "0", axis_color, TA_RIGHT);

   for(int grid_row = 1; grid_row <= 4; grid_row++)
     {
      const int grid_y = plot_top + (plot_height * grid_row) / 4;
      g_sdui_canvas.Line(plot_left - 4, grid_y, plot_left, grid_y, axis_color);
     }

   g_sdui_canvas.TextOut(plot_left + plot_width / 2, baseline_y + 18, "Value", axis_color, TA_CENTER);

   g_sdui_canvas.TextOut(4, plot_top + plot_height / 2 - 6, "Frequency", axis_color, TA_LEFT);

   g_sdui_canvas.Update();
   ChartRedraw(chart_id);
  }

#endif
