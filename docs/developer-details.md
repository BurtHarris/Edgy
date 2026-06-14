# Developer Details (Preliminary)

This document captures implementation-facing direction for contributors while command contracts are still in flux.

## 1. Working Model

The workspace is transitioning from a single prototype module toward two distinct modules:

- Edgey module
  - Owns Edge-specific command and control behavior
  - Owns operational interactions with local Edge state
- WhyLog module
  - Owns diagnostics DSL, stream capture strategy, and YAML artifact generation
  - Is reusable and should remain free of Edge-specific assumptions

Dependency direction target: Edgey -> WhyLog.

## 2. Current Constraints

- Existing prototype module artifacts live under `prototypes/edgey/` and are not canonical architecture.
- Decision records and glossary are the authoritative planning source during transition.
- The team is prioritizing design convergence over immediate command-surface documentation.

## 3. Repository Structure (Current)

- `src/edgey/` - intended canonical Edgey source location
- `src/whylog/` - intended canonical WhyLog source location
- `prototypes/edgey/` - current prototype module and tests
- `docs/adr/` and `docs/pdr/` - design and progress decisions
- `.vscode/` plus `PSScriptAnalyzerSettings.psd1` - development environment support

Root-level module files were moved into `prototypes/edgey/` to keep the repo focused on the target architecture.

## 4. Diagnostics Direction

The intended diagnostics system is:

- Text-first output (YAML as primary artifact)
- PowerShell-native authoring ergonomics
- Compatible with standard PowerShell streams and pipelines
- Designed for parser-backed validation and optional projection workflows

Key characteristics under active design:

- Ordered output preserving emission sequence
- Minimal quoting policy (quote only when YAML correctness requires it)
- Support for narrative and signal-style entries
- Concise DSL aliases in controlled scope for authoring diagnostics

## 5. DSL and Entrypoints (Direction, Not Final Contract)

Expected core surface direction:

- New-WhyLog: produce YAML diagnostics artifact
- Read-WhyLog: deserialize YAML artifact for programmatic consumption

Additional helper behaviors are expected to be scoped to WhyLog execution contexts and should avoid global shell pollution.

## 6. Testing and Tooling Posture

Workspace support currently includes:

- Pester tasks for all tests and current file
- ScriptAnalyzer task using workspace settings file
- Launch profiles for script and Pester debugging

Contributors should prefer adding small, deterministic tests around behavior decisions as architecture stabilizes.

## 7. Recommended Next Implementation Steps

1. Begin moving canonical Edgey implementation from `prototypes/edgey/` into `src/edgey/`.
2. Create a minimal WhyLog skeleton in `src/whylog/`.
3. Extract diagnostics rendering and stream mapping logic out of Edgey prototype internals.
4. Keep command docs intentionally light until surface and semantics settle.

## 8. Source of Truth During Transition

Use these files to align changes:

- CONTEXT.md
- docs/adr/
- docs/pdr/

If implementation and decision records diverge, update records or code immediately so drift does not accumulate.
