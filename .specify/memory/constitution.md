# MetatraderDataAnalyzer — Project Constitution

*Engineering standards for this repository. All source code and embedded documentation (comments, function headers) **MUST** be in **English**, as required in section IV below.*

Engineering standards for MQL5 Experts and includes in this repository.  
**Scope**: Expert Advisors and related modules (e.g. statistical distribution EA). **Out of scope**: third-party DLLs unless explicitly approved.

---

## Core Principles

### I. Terminal safety and responsiveness

The terminal must remain usable. Avoid unbounded loops, excessive allocations inside hot paths (`OnTick`, tight `OnChartEvent` handlers), and blocking waits. Long work should be bounded by input limits (e.g. max bars) and reuse buffers (`ArrayResize` once per size change where possible). Never assume unlimited history or symbol availability—validate and fail with clear user-facing feedback.

### II. Deterministic resource lifecycle

Every acquired resource **MUST** be released or invalidated in `OnDeinit` (and on re-init paths if applicable): indicator handles (`IndicatorRelease`), chart objects, canvas detachment, timers, and global state that would leak across reloads. Create handles lazily or in `OnInit` with a clear ownership map; do not recreate heavy handles on every keystroke without caching strategy.

### III. Spec- and contract-driven behavior

Implementation **MUST** follow the active feature spec (`specs/…/spec.md`) and contracts (`specs/…/contracts/`). Expression language, UI layout, and error semantics are **not** improvised at implementation time—extend the contract first, then code. The EA **MUST NOT** execute trades unless a future spec explicitly requires it; analysis-only tools stay analysis-only.

### IV. English documentation in source (NON-NEGOTIABLE)

All **user-facing technical documentation embedded in code** **MUST** be written in **English**:

- Every **function** (including `static` / file-local helpers): a short English description of purpose, parameters, return value, and failure modes where non-obvious.
- **Non-obvious** logic: a **brief** English comment (one line is enough if it explains *why* or *invariant*, not what the next line literally does).
- **Obvious** code (e.g. `i++`) **MUST NOT** be commented.

Use a consistent style: prefer a block above each function (`//` or `///` lines) listing purpose, params, and return; use inline `//` only for localized non-obvious notes. This keeps MetaEditor tooltips and cross-team review consistent.

### V. Simplicity, explicitness, and MQL5 idioms

Prefer clear, boring MQL5 over clever abstractions. Use `input` for tunables, `enum` for discrete modes, early returns for errors, and explicit `bool`/`int` result codes where the platform expects them. Follow official MQL5 naming sensibilities: readable identifiers, no Hungarian notation unless already project-wide. YAGNI: do not add frameworks, DLLs, or generic “engines” unless the spec demands them.

### VI. Performant, non-blocking execution (preference)

We **prefer** code that is **fast** and **does not freeze** the terminal or chart UI. Treat responsiveness as a default design constraint, not an afterthought:

- Keep heavy work off the critical path where possible: batch series computation, cache indicator handles and buffers, avoid redundant full-chart redraws and redundant `Copy*` calls.
- Do not block the main thread on hypothetical “fix later” optimizations—if an operation can exceed interactive budgets (see feature success criteria), structure work so the user still gets progress or clear feedback.
- When trading clarity against speed, **document** the tradeoff in English (brief comment) and favor approaches that preserve snappy submit-to-result behavior for the configured bar count.

Principle I (terminal safety) and this principle reinforce each other: performant code should also avoid hangs and runaway complexity.

---

## MQL5 Engineering Standards

### Language and build

- Target **MetaTrader 5** / **MQL5** only unless a spec says otherwise.
- Use `#property strict` where compatible with the codebase; fix all compiler warnings that indicate real issues.
- `#include` paths must resolve in MetaEditor from the Expert’s directory or standard `Include` layout documented in `plan.md` / `quickstart.md`.

### Indicators and series

- Prefer **handles** + `CopyBuffer` / `Copy*` with documented shift semantics aligned with the feature spec (e.g. closed bars only, window index vs server shift).
- **Bands / multi-buffer indicators**: map buffers explicitly (e.g. Mid/Upper/Lower) per contract—no magic indices without a named constant or comment.
- Check copy counts and `BarsCalculated` / history sufficiency; propagate structured errors to the UI instead of silent zeros.

### UI (canvas, objects, events)

- Layout and behavior **MUST** match `ui-channels.md` (regions, Enter-to-submit, status strip).
- Object names: use a **unique prefix** per EA instance to avoid collisions on the chart.
- `OnChartEvent`: handle only events the EA subscribes to; debounce or guard so partial state does not corrupt the pipeline.

### Error handling and logging

- Distinguish **user-recoverable** errors (bad expression, insufficient bars) from **internal** errors; surface the former in the status area in clear language (product may localize messages later—implementation messages and comments remain English).
- Use `GetLastError()` / return codes where appropriate; log to `Print` only when useful for diagnostics, not in tight loops.

### Performance

- **Default stance**: write **performant** code—minimize work per user action, avoid accidental O(n²) patterns over bars, and prefer single passes where a spec allows.
- Respect **measurable** targets in the active spec (e.g. time from confirm to updated histogram for N bars). If a path risks exceeding them, optimize or split work before shipping.
- **No freezes**: long loops or huge allocations must stay bounded by inputs; never spin waiting on external conditions in `OnTick` / `OnChartEvent` without a guard.
- **Redraw discipline**: redraw the canvas and recreate objects only when inputs or computed data change; avoid repainting identical frames every tick.
- **Indicator access**: reuse handles; avoid creating/releasing handles inside inner loops over bars when parameters are fixed for a given expression evaluation.

---

## Development Workflow and Quality Gates

- **Before merge / handoff**: compiles with **0 errors** in MetaEditor; manual smoke test on chart per `quickstart.md` when the feature is executable.
- **Constitution over ad-hoc rules**: if a shortcut conflicts with this document, update the constitution via an explicit amendment (version bump) rather than ignoring it.
- **Spec Kit alignment**: new features follow `/speckit.*` artifacts when the team uses Spec Kit; code structure mirrors `plan.md` / `tasks.md` for traceability.

---

## Governance

- This constitution **supersedes** informal coding habits for this repository.
- **Amendments**: change this file, bump **Version** and **Last Amended**, and note the rationale in the commit message.
- **Reviews**: reviewers check resource lifecycle, English doc comments on new/changed functions, spec/contract alignment for behavioral changes, and obvious performance anti-patterns (redundant copies, unbounded work, unnecessary redraws).

**Version**: 1.0.1 | **Ratified**: 2026-03-24 | **Last Amended**: 2026-03-24
