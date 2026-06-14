# Edgey

Edgey is a PowerShell context for backing up, restoring, and diagnosing Edge variation state. This glossary defines the domain language used for diagnostics design decisions.

## Context Boundary

Edgey and WhyLog are distinct modules. Edgey is the Edge-specific command-and-control tool, while WhyLog is a reusable diagnostics/YAML logging module that Edgey consumes as an example integration.

## Language

**Diagnostics Report**:
A structured representation of runtime and environment findings collected by Edgey. It is the source model that gets rendered for humans.
_Avoid_: output, dump

**YAML Renderer**:
A component that transforms a Diagnostics Report into YAML text for human inspection. It owns rendering rules, not data collection.
_Avoid_: serializer, formatter

**Diagnostics Result**:
The canonical output of diagnostics commands, currently emitted as textual YAML by default. A later wrapper may expose parsed properties from this YAML.
_Avoid_: mandatory object surface, ad-hoc text

**Known-Good YAML Parser**:
A trusted parser dependency used to parse diagnostics YAML for validation and optional object projection. It is the single source of truth for parse behavior.
_Avoid_: custom parser, regex parser

**Validation Strictness Policy**:
A rule that YAML parsing is strict in CI and optionally soft in local development. The policy controls whether parse failures stop execution.
_Avoid_: always strict everywhere, always permissive

**Canonical Parser Stack**:
The parser implementation used as the contract authority for YAML validity and projection. Edgey uses powershell-yaml backed by YamlDotNet.
_Avoid_: parser switching by environment, parser ambiguity

**Deterministic Ordering**:
A renderer guarantee that key order is stable across runs so test snapshots and diffs remain meaningful.
_Avoid_: incidental ordering, runtime-dependent ordering

**Insertion-First Ordering**:
The renderer preserves insertion order as the primary ordering rule, with explicit targeted tweaks only where readability needs it.
_Avoid_: broad auto-sorting, implicit reordering

**Signal-Aware Emission**:
Diagnostics can route findings to host channels such as warning and error streams while still producing canonical YAML text.
_Avoid_: yaml-only signaling, stream-only signaling

**Native Detail Gating**:
Diagnostics detail levels are controlled with PowerShell conventions such as -Verbose and -Debug instead of custom switches.
_Avoid_: custom include-details flags, nonstandard verbosity knobs

**Detail Channel Split**:
Verbose output carries operational detail and passed-check expansion, while Debug output carries renderer and parse internals.
_Avoid_: mixed detail semantics, duplicated channel intent

**Mirrored Severity Model**:
Severity semantics are represented both in PowerShell streams and in YAML so diagnostics remain meaningful outside live terminal execution.
_Avoid_: stream-only severity, yaml-only severity

**Tagged Severity Notation**:
YAML may encode severity with bang tags such as !info, !warning, and !error when readability or semantic intent benefits.
_Avoid_: untagged ambiguity, tag semantics without parser policy

**Concise Severity Tags**:
Diagnostics prefer compact lowercase severity tags like !w and !e for readability and density when emitted as YAML text.
_Avoid_: verbose-only tags, inconsistent abbreviations, uppercase tags

**Tags-Only Severity Encoding**:
Severity is encoded exclusively through YAML tags rather than a separate severity field.
_Avoid_: dual encoding, duplicated severity fields

**Optional Severity Tagging**:
Findings may be tagged when severity signaling is needed, and may be untagged when they are purely narrative explanations.
_Avoid_: forced tagging of narrative-only content, unclear intent

**Dual Finding Model**:
The findings collection supports two classes: untagged narrative findings and tagged signal findings.
_Avoid_: single-class assumptions, mixed intent without distinction

**Stream Mapping Policy**:
Narrative findings emit in YAML only; tagged findings emit in YAML and map to corresponding PowerShell streams (!i to information, !w to warning, !e to error).
_Avoid_: stream emission for narrative lines, inconsistent tag-to-stream mapping

**Diagnostics Module Split**:
Diagnostics are organized as a module with two parts: an outer wrapper that intercepts and formats streams, and concise commands used directly inside tests.
_Avoid_: command-only architecture, blurred wrapper-command boundaries

**Two-Module Architecture**:
The repository contains two distinct modules: Edgey for Edge operations and WhyLog for diagnostics DSL and YAML reporting.
_Avoid_: collapsing concerns into one module, Edge-specific logic inside WhyLog

**Module Dependency Direction**:
Edgey depends on WhyLog for diagnostics output behavior; WhyLog must remain reusable and independent of Edge-specific command logic.
_Avoid_: reverse dependency, cross-module circular coupling

**Stream Intercept Wrapper**:
An outer component that captures stream activity and emits canonical YAML-oriented diagnostics output.
_Avoid_: unmanaged stream leakage, formatting logic scattered across commands

**Minimal Quoting Policy**:
Diagnostics output prefers plain and block-plain YAML scalars, using quotes only when YAML syntax requires them.
_Avoid_: blanket quoting, unnecessary escaping

**Diagnostic Alias Verbs**:
Inside the wrapper scriptblock, short aliases I, W, and E are available to emit informational, warning, and error findings concisely.
_Avoid_: verbose-only authoring, alias names that conflict with severity intent

**Pipeline Block Capture**:
Traditional PowerShell pipeline output inside the wrapper scriptblock can be preserved as its normal formatted text and emitted inside a YAML block scalar.
_Avoid_: forcing pipeline objects into artificial finding schemas, lossy reformatting

**Pipeline Modality Support**:
The wrapper supports pipeline output that is object-only, string-only, or mixed object and string streams.
_Avoid_: assuming a single output modality, coercing all pipeline output to strings too early

**Emission Order Fidelity**:
Mixed output preserves the exact original emission order across object-rendered text and raw string content.
_Avoid_: post-format reordering, grouped-by-type output reshaping

**Top-Level Sequence Document**:
The canonical diagnostics YAML document is a top-level ordered sequence of entries.
_Avoid_: mandatory top-level mapping wrappers, nested list indirection by default

**Ordered Rich Entry Notation**:
Complex diagnostics are expressed as sequence entries with structured payloads, preserving scanability through repeated leading dashes.
_Avoid_: hiding complex entries behind detached sections, losing chronological flow

**Progress Persistence Default**:
Write-Progress is treated as live operator UX by default and is not persisted into canonical YAML output.
_Avoid_: always-on progress persistence, noisy progress artifacts

**Error Trace Progress Capture**:
When failures occur, a compact progress trace may be included to provide execution context for diagnostics.
_Avoid_: full progress spam dumps, missing failure context

**Progress Trace Deferral (v1)**:
Progress trace capture is optional and deferred for the first iteration unless error investigations prove it necessary.
_Avoid_: premature trace complexity, blocking v1 on low-value details

**Constructor-Style Entrypoint Naming**:
The primary wrapper command should use New-style naming rather than Invoke-style naming to match preferred ergonomics.
_Avoid_: Invoke-prefixed primary entrypoints, ambiguous verb intent

**WhyLog Entrypoint**:
The preferred primary wrapper command name is New-WhyLog.
_Avoid_: overly generic diagnostics names for the primary entrypoint

**Scriptblock Local Aliases**:
Inside New-WhyLog scriptblocks, concise local helper aliases I, W, E, and P are available for informational, warning, error, and progress signaling.
_Avoid_: verbose-only emission syntax, aliases that leak globally

**Local Helper Naming**:
Helpers visible only inside the scriptblock do not require a WhyLog prefix.
_Avoid_: redundant internal prefixes, global command-surface clutter

**Ephemeral DSL Scope**:
DSL helpers are created only for the duration of New-WhyLog execution and are removed immediately afterward.
_Avoid_: persistent helper leakage, ambient global DSL state

**PowerShell-Native DSL Style**:
The DSL should feel idiomatic to PowerShell and may draw inspiration from tools like Pester without duplicating their execution model.
_Avoid_: non-PowerShell syntax, framework model cloning

**Alias Collision Deferral (v1)**:
Handling of pre-existing I/W/E/P names is non-blocking and may be deferred if robust isolation is costly.
_Avoid_: delaying v1 on low-likelihood collisions, premature scope-hardening complexity

**Separate Deserialization Command**:
New-WhyLog returns YAML text by default, and YAML-to-object projection is provided by a dedicated deserialization cmdlet rather than runtime switches.
_Avoid_: multiplexed return-mode switches, mixed-type default outputs

**Deserializer Naming**:
The dedicated YAML-to-object cmdlet is named Read-WhyLog.
_Avoid_: inconsistent paired naming, ambiguous parser command names

**Deserializer Input Modes**:
Read-WhyLog accepts both piped YAML text and explicit file path input.
_Avoid_: single-mode parsing workflows, unnecessary IO friction

**Concise Test Commands**:
Small composable commands optimized for direct use in tests and for producing minimal, explicit findings.
_Avoid_: monolithic test helpers, hidden side effects

**Severity Tag Vocabulary (v1)**:
The initial supported severity tags are exactly !i, !w, and !e.
_Avoid_: extra tags in v1, synonym tags

**Primary Emission Path**:
Diagnostics emit YAML text through Write-Output by default as the easiest and most direct user experience.
_Avoid_: mandatory stream multiplexing, non-output defaults

**Tag-Centric Contract**:
Severity tags carry the primary semantic contract, while the surrounding YAML shape remains intentionally lightweight and adaptable.
_Avoid_: rigid heavyweight schemas, semantics hidden outside tags

**Minimal Structure Bias**:
Diagnostics favor the smallest useful structure needed for readability and parseability instead of enforcing exhaustive field schemas.
_Avoid_: mandatory verbose fields, over-specified finding envelopes

**Scalar Style Policy**:
Renderers prefer plain and block-plain scalar styles, using quoted scalars only when required for YAML correctness.
_Avoid_: blanket quoting, style loss from unnecessary escaping

**Ordered Findings Collection**:
Findings are emitted in a stable insertion-ordered sequence so narrative flow and causality remain readable.
_Avoid_: regrouping by severity, post-hoc resorting

**Line Finding Form**:
The default concise representation is one finding per line item with an explicit severity tag.
_Avoid_: multiline-by-default finding payloads, implicit severity

**Rich Event Finding Form**:
Complex findings may use a typed event notation that starts with a sequence item and event type token, followed by structured properties.
_Avoid_: untyped rich payloads, inconsistent event headers

**Mixed Findings Syntax**:
The preferred findings list mixes concise line findings with richer typed event findings in a single ordered collection.
_Avoid_: separate rich-only sections, mutually exclusive forms

**Tag-First Rich Event Header**:
Rich event findings place the severity tag before the event type marker for scan-first readability.
_Avoid_: event-first headers, buried severity markers

**Optional Inline Rich Payload**:
Rich event properties may be emitted inline in braced form when short, otherwise emitted as indented block properties.
_Avoid_: forced multiline payloads, forced single-line payloads

**Inline Threshold Policy**:
Inline rich payloads are allowed only below a defined complexity threshold and can be tuned later without changing the overall findings syntax.
_Avoid_: hard-coded irreversible limits, undocumented threshold behavior

**Profile-Owned Thresholds**:
Inline and formatting thresholds are configured by Rendering Profile rather than hard-coded command logic.
_Avoid_: fixed constants in command flow, per-call threshold noise

**Canonical Event Tokens**:
Rich event and line-finding type names use concise lowercase tokens by default, with optional dot qualification only when needed for disambiguation.
_Avoid_: verbose always-qualified names, case-variant duplicates

**Token Escalation Rule**:
Findings start as single lowercase tokens and escalate to dotted qualification only on ambiguity or collision; once published, token names do not downgrade.
_Avoid_: premature qualification, unstable token renaming

**Rendering Profile**:
A named set of YAML rendering rules such as quoting, null style, ordering, and readability conventions. Profiles make output behavior explicit.
_Avoid_: mode, flavor
