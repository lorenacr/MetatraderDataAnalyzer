//+------------------------------------------------------------------+
//| SD_Stats.mqh                                                     |
//| From raw samples: order statistics, Sturges histogram, percentiles.|
//| Invalid values (same filter as evaluation) are dropped first.     |
//+------------------------------------------------------------------+
#ifndef __SD_STATS_MQH__
#define __SD_STATS_MQH__

#include "SD_Config.mqh"
#include "SD_Types.mqh"

//+------------------------------------------------------------------+
//| Summary for drawing: normative stats + histogram buckets.         |
//+------------------------------------------------------------------+
struct SdStatsSummary
  {
   bool              has_data;
   int               count;
   double            mean;
   double            median;
   double            stdev;
   double            vmin;
   double            vmax;
   double            p005;
   double            p025;
   double            p05;
   double            p075;
   double            p10;
   double            p25;
   double            p50;
   double            p75;
   double            p90;
   double            p925;
   double            p95;
   double            p975;
   double            p99;
   double            p995;
   int               bin_count;
   double            bin_edges[SD_HIST_MAX_BINS + 1];
   int               bin_counts[SD_HIST_MAX_BINS];
  };

//+------------------------------------------------------------------+
bool SdStats_IsGoodValue(const double value)
  {
   if(value == EMPTY_VALUE)
      return false;
   if(!MathIsValidNumber(value))
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Linear interpolation on sorted array; p is percentile in [0,100].|
//+------------------------------------------------------------------+
double SdStats_PercentileLinear(double &sorted_asc[], const int n, const double percentile)
  {
   if(n <= 0)
      return 0.0;
   if(n == 1)
      return sorted_asc[0];
   const double position = (double)(n - 1) * (percentile / 100.0);
   const int lower_index = (int)MathFloor(position);
   const int upper_index = (int)MathCeil(position);
   if(lower_index == upper_index)
      return sorted_asc[lower_index];
   const double weight = position - (double)lower_index;
   return sorted_asc[lower_index] + (sorted_asc[upper_index] - sorted_asc[lower_index]) * weight;
  }

//+------------------------------------------------------------------+
void SdStats_Compute(double &raw_samples[], const int raw_sample_count, SdStatsSummary &out_summary, SdResult &result)
  {
   SdResult_SetOk(result);
   out_summary.has_data = false;
   out_summary.count = 0;
   out_summary.mean = 0;
   out_summary.median = 0;
   out_summary.stdev = 0;
   out_summary.vmin = 0;
   out_summary.vmax = 0;
   out_summary.p005 = out_summary.p025 = out_summary.p05 = out_summary.p075 = 0;
   out_summary.p10 = out_summary.p25 = out_summary.p50 = out_summary.p75 = out_summary.p90 = 0;
   out_summary.p925 = out_summary.p95 = out_summary.p975 = out_summary.p99 = out_summary.p995 = 0;
   out_summary.bin_count = 0;
   ArrayInitialize(out_summary.bin_edges, 0.0);
   ArrayInitialize(out_summary.bin_counts, 0);

   double valid_sorted_work[];
   int valid_count = 0;
   if(raw_sample_count < 1)
     {
      SdResult_SetError(result, SD_ERR_STATS_EMPTY, SdConfig_ErrorMessage(SD_ERR_STATS_EMPTY));
      return;
     }
   ArrayResize(valid_sorted_work, raw_sample_count);
   for(int i = 0; i < raw_sample_count; i++)
     {
      if(SdStats_IsGoodValue(raw_samples[i]))
        {
         valid_sorted_work[valid_count] = raw_samples[i];
         valid_count++;
        }
     }

   if(valid_count < 1)
     {
      SdResult_SetError(result, SD_ERR_STATS_EMPTY, SdConfig_ErrorMessage(SD_ERR_STATS_EMPTY));
      return;
     }
   ArrayResize(valid_sorted_work, valid_count);

   out_summary.vmin = valid_sorted_work[0];
   out_summary.vmax = valid_sorted_work[0];
   double sum = 0.0;
   for(int j = 0; j < valid_count; j++)
     {
      if(valid_sorted_work[j] < out_summary.vmin)
         out_summary.vmin = valid_sorted_work[j];
      if(valid_sorted_work[j] > out_summary.vmax)
         out_summary.vmax = valid_sorted_work[j];
      sum += valid_sorted_work[j];
     }
   out_summary.mean = sum / (double)valid_count;

   double sum_sq_dev = 0.0;
   for(int k = 0; k < valid_count; k++)
     {
      const double deviation = valid_sorted_work[k] - out_summary.mean;
      sum_sq_dev += deviation * deviation;
     }
   out_summary.stdev = MathSqrt(sum_sq_dev / (double)valid_count);

   ArraySort(valid_sorted_work);
   out_summary.median = SdStats_PercentileLinear(valid_sorted_work, valid_count, 50.0);
   out_summary.p005 = SdStats_PercentileLinear(valid_sorted_work, valid_count, 0.5);
   out_summary.p025 = SdStats_PercentileLinear(valid_sorted_work, valid_count, 2.5);
   out_summary.p05 = SdStats_PercentileLinear(valid_sorted_work, valid_count, 5.0);
   out_summary.p075 = SdStats_PercentileLinear(valid_sorted_work, valid_count, 7.5);
   out_summary.p10 = SdStats_PercentileLinear(valid_sorted_work, valid_count, 10.0);
   out_summary.p25 = SdStats_PercentileLinear(valid_sorted_work, valid_count, 25.0);
   out_summary.p50 = out_summary.median;
   out_summary.p75 = SdStats_PercentileLinear(valid_sorted_work, valid_count, 75.0);
   out_summary.p90 = SdStats_PercentileLinear(valid_sorted_work, valid_count, 90.0);
   out_summary.p925 = SdStats_PercentileLinear(valid_sorted_work, valid_count, 92.5);
   out_summary.p95 = SdStats_PercentileLinear(valid_sorted_work, valid_count, 95.0);
   out_summary.p975 = SdStats_PercentileLinear(valid_sorted_work, valid_count, 97.5);
   out_summary.p99 = SdStats_PercentileLinear(valid_sorted_work, valid_count, 99.0);
   out_summary.p995 = SdStats_PercentileLinear(valid_sorted_work, valid_count, 99.5);

   int bin_count_sturges = (int)MathCeil(MathSqrt((double)valid_count));
   if(bin_count_sturges < SD_HIST_MIN_BINS)
      bin_count_sturges = SD_HIST_MIN_BINS;
   if(bin_count_sturges > SD_HIST_MAX_BINS)
      bin_count_sturges = SD_HIST_MAX_BINS;
   out_summary.bin_count = bin_count_sturges;

   const double value_span = out_summary.vmax - out_summary.vmin;
   if(value_span <= 0.0 || !MathIsValidNumber(value_span))
     {
      out_summary.bin_edges[0] = out_summary.vmin;
      out_summary.bin_edges[1] = out_summary.vmin + 1.0;
      out_summary.bin_count = 1;
      out_summary.bin_counts[0] = valid_count;
     }
   else
     {
      const double bin_width = value_span / (double)bin_count_sturges;
      for(int edge_index = 0; edge_index <= bin_count_sturges; edge_index++)
         out_summary.bin_edges[edge_index] = out_summary.vmin + bin_width * (double)edge_index;

      for(int bin_index = 0; bin_index < bin_count_sturges; bin_index++)
         out_summary.bin_counts[bin_index] = 0;

      for(int sample_index = 0; sample_index < valid_count; sample_index++)
        {
         const double x = valid_sorted_work[sample_index];
         int bin_index = (int)MathFloor((x - out_summary.vmin) / bin_width);
         if(bin_index < 0)
            bin_index = 0;
         if(bin_index >= bin_count_sturges)
            bin_index = bin_count_sturges - 1;
         out_summary.bin_counts[bin_index]++;
        }
     }

   out_summary.has_data = true;
   out_summary.count = valid_count;
  }

#endif
