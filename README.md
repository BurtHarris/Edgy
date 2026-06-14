# Edgy (Preliminary)

Edgy is currently evolving into a two-module PowerShell workspace:

- Edgey: Edge-focused command and control workflows (backup, restore, and operational diagnostics around Edge state)
- WhyLog: a reusable diagnostics DSL and YAML-oriented logging/reporting module that Edgey will consume

This repository is in early shaping mode. The current module and tests are prototype-grade and intentionally being refactored toward clearer boundaries.

## Repository Layout (Current)

- `src/edgey/` - canonical destination for Edgey module source
- `src/whylog/` - canonical destination for WhyLog module source
- `prototypes/edgey/` - current prototype module and tests moved out of root to reduce distraction
- `docs/adr/` - architecture decisions
- `docs/pdr/` - product/progress decision notes
- `.vscode/` - workspace tooling for PowerShell development

## Current Direction

- Separate domain operations from diagnostics infrastructure
- Keep diagnostics output text-first (YAML) with parser-backed validation paths
- Build an ergonomic PowerShell-native DSL for concise diagnostics authoring
- Preserve stream and pipeline fidelity while producing structured diagnostic artifacts

## Repository Status

What exists now:

- Prototype Edge module and tests under `prototypes/edgey/`
- Context language and decision records
- VS Code PowerShell development environment scaffold

What is not finalized yet:

- Stable command surface
- Final module layout for Edgey vs WhyLog
- Formal command-level user documentation

## Design Artifacts

- Context glossary: CONTEXT.md
- Architecture decision records: docs/adr/
- Product/progress decision records: docs/pdr/

## Near-Term Goals

- Continue extracting canonical code into `src/edgey/` and `src/whylog/`
- Move diagnostics concerns out of Edgey-specific implementation areas
- Establish a minimal, testable WhyLog core with New-WhyLog and Read-WhyLog entry points
- Iterate on syntax and rendering profiles using prototype feedback

## Development Environment

The workspace includes VS Code settings, tasks, launch profiles, and ScriptAnalyzer settings tuned for PowerShell development.

- Workspace config: .vscode/
- Analyzer profile: PSScriptAnalyzerSettings.psd1

This README is intentionally preliminary and will be tightened as the module split lands.
