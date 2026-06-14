#!/usr/bin/env powershell
#Requires -Version 5.1

<#
.SYNOPSIS
WhyLog - Readable YAML diagnostics DSL for PowerShell troubleshooting.
.DESCRIPTION
New-WhyLog executes a scriptblock with ephemeral DSL helpers (I, W, E) and
emits scan-first YAML text suited for diagnosing issues in a terminal or editor.
The output is a top-level YAML sequence with insertion-ordered findings, minimal
quoting, and concise severity tags (!i, !w, !e).
#>

function ConvertTo-WhyLogYamlScalar {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return "''" }

    $needsQuote = (
        # Starts with a YAML structural or indicator character
        ($Value -match '^[:{}\[\]#!&\*\|>"%@`,]') -or
        # Starts with a single-quote (YAML flow scalar indicator)
        ($Value -match "^'") -or
        # Leading hyphen avoids sequence-indicator ambiguity
        ($Value -match '^-') -or
        # Colon-space is a mapping-key separator in YAML
        ($Value -match ': ') -or
        # Trailing colon would start a bare mapping key
        ($Value -match ':$') -or
        # Inline comment indicator
        ($Value -match ' #') -or
        # YAML reserved keywords (boolean / null)
        ($Value -imatch '^(true|false|null|~|yes|no|on|off)$') -or
        # Bare numeric literal (including scientific notation)
        ($Value -match '^[-+]?(\d+(\.\d*)?|\.\d+)([eE][-+]?\d+)?$') -or
        ($Value -match '^0[xXoObB]') -or
        # Leading or trailing whitespace
        ($Value -match '^\s' -or $Value -match '\s$')
    )

    if ($needsQuote) {
        $escaped = $Value -replace "'", "''"
        return "'" + $escaped + "'"
    }
    return $Value
}

function New-WhyLog {
    <#
    .SYNOPSIS
    Runs a diagnostics scriptblock and emits findings as scan-first YAML text.
    .DESCRIPTION
    New-WhyLog executes the given scriptblock with three ephemeral DSL helpers:

        I <message>   informational finding  → - !i <message>
        W <message>   warning finding        → - !w <message>
        E <message>   error finding          → - !e <message>

    Findings are collected in insertion order and returned as a top-level YAML
    sequence string. Scalar values use minimal quoting: plain where YAML allows,
    single-quoted only when the content requires it.

    .PARAMETER Script
    The diagnostics scriptblock to execute. Use I, W, and E inside it.

    .OUTPUTS
    System.String. YAML text, or nothing if no findings were recorded.

    .EXAMPLE
    New-WhyLog {
        I 'checking Edge installation'
        W 'variations seed not found'
        E 'Edge process still running'
    }
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [scriptblock]$Script
    )

    $findings = [System.Collections.Generic.List[pscustomobject]]::new()

    $addI = { param([string]$Message) $findings.Add([pscustomobject]@{ Tag = 'i'; Text = $Message }) }.GetNewClosure()
    $addW = { param([string]$Message) $findings.Add([pscustomobject]@{ Tag = 'w'; Text = $Message }) }.GetNewClosure()
    $addE = { param([string]$Message) $findings.Add([pscustomobject]@{ Tag = 'e'; Text = $Message }) }.GetNewClosure()

    $dsl = @{
        'I' = $addI
        'W' = $addW
        'E' = $addE
    }

    try {
        $null = $Script.InvokeWithContext($dsl, $null, @())
    } catch {
        $findings.Add([pscustomobject]@{ Tag = 'e'; Text = "Unhandled exception: $($_.Exception.Message)" })
    }

    if ($findings.Count -eq 0) { return }

    $lines = @(foreach ($f in $findings) {
        $scalar = ConvertTo-WhyLogYamlScalar -Value $f.Text
        "- !$($f.Tag) $scalar"
    })

    Write-Output ($lines -join "`n")
}

Export-ModuleMember -Function New-WhyLog
