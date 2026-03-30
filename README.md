# MetatraderDataAnalyzer

A **MetaTrader 5** Expert Advisor that evaluates a **numeric expression** over the last *N* **closed** bars of the current chart and draws the **empirical distribution** (compact histogram, reference curve, percentile bands) in an on-chart **canvas**.

**Does not place trades** — analysis and visualization only.

## Requirements

- MetaTrader 5 with MetaEditor to compile the `.mq5` file.
- No external dependencies (no DLLs or packages outside the terminal).

## Repository layout

| Path | Contents |
|------|----------|
| `MQL5/Experts/StatisticalDistributionEA/` | Main EA (`StatisticalDistributionEA.mq5`) and includes (`Include/*.mqh`) |

Copy the EA folder into your terminal’s `MQL5/Experts` directory (or open the project from there) and compile in MetaEditor.

## Usage

1. Attach the EA to the desired chart (symbol and timeframe define the data).
2. Edit the **expression** field and submit with **Enter** or on focus loss — the pipeline runs only on that event.
3. Adjust **Bars To Analyze** (default 100,000; hard cap configurable in `SD_Config.mqh`, up to 500,000).
4. **Persist last expression**: stores the bar count in a `GlobalVariable` (prefix `SDEA_`) and the last expression in `MQL5/Files/<key>.expr.txt` (see `SD_Persist.mqh`).

While active, the EA hides the native time/price scales to avoid confusion with the distribution axes; they are restored in `OnDeinit`.

## Expression language (summary)

Evaluation is **per closed bar** in the window: index `0` = most recent closed bar.

- **Series**: standard MT5 price and volume fields (see lexer/parser implementation).
- **Indicators**: including SMA, EMA, RSI, ATR, StdDev; **Bollinger** with `.Upper`, `.Lower`, `.Mid`.
- **Arithmetic**, parentheses, and **`[k]`** bar shift inside the window.

Full details are in the code (`SD_ExprLexer.mqh`, `SD_ExprParser.mqh`, `SD_ExprEval.mqh`).

## Statistics and visualization

- Sample excludes non-finite values and `EMPTY_VALUE`.
- Empirical percentiles (including IC-style bands) and a histogram whose bin count derives from *n* (clamped by `SD_HIST_MIN_BINS` / `SD_HIST_MAX_BINS`).
- Summary line (`n`, mean, stdev, min, max).
- Errors surfaced in the UI and **Experts** log via stable codes in `SD_Config.mqh` (`SdConfig_ErrorMessage`).
