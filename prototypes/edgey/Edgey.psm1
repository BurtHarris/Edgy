#!/usr/bin/env powershell
#Requires -Version 5.1

<#
.SYNOPSIS
Edgey - simple scope-based tools to backup/disable/restore Edge variations seed files and diagnose state.
.DESCRIPTION
Initializes per-scope store on demand. Elevates only for machine-level operations.
#>

# Config
$script:Edgey_UserRoot = Join-Path $env:USERPROFILE "EdgeyBackup"
$script:Edgey_AdminRoot = "C:\EdgeyBackup"
$script:Edgey_StackName = "stack.json"
$script:Edgey_ModulePath = $PSCommandPath

# Helpers
function Test-IsAdmin { ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }

function Invoke-EdgeyElevated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Func,
        [object[]]$Parameters
    )

    $sessionRoot = Join-Path $env:TEMP ("Edgey_Elevate_{0}" -f ([guid]::NewGuid()))
    $payloadPath = Join-Path $sessionRoot "payload.clixml"
    $statusPath = Join-Path $sessionRoot "status.txt"

    try {
        New-Item -Path $sessionRoot -ItemType Directory -Force | Out-Null
        [pscustomobject]@{
            Func = $Func
            Parameters = @($Parameters)
        } | Export-Clixml -Path $payloadPath

        $modulePath = $script:Edgey_ModulePath.Replace("'", "''")
        $payloadLiteral = $payloadPath.Replace("'", "''")
        $statusLiteral = $statusPath.Replace("'", "''")

        $elevatedCommand = @"
`$ErrorActionPreference = 'Stop'
try {
    `$payload = Import-Clixml -Path '$payloadLiteral'
    Import-Module -Force '$modulePath'
    & `$payload.Func @(`$payload.Parameters)
    'OK' | Out-File -FilePath '$statusLiteral' -Encoding UTF8 -Force
} catch {
    (`$_ | Out-String) | Out-File -FilePath '$statusLiteral' -Encoding UTF8 -Force
    exit 1
}
"@

        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($elevatedCommand))
        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded) -Verb RunAs -Wait -PassThru

        $status = if (Test-Path $statusPath) { Get-Content -Path $statusPath -Raw } else { $null }
        if ($proc.ExitCode -ne 0 -or -not $status -or $status.Trim() -ne "OK") {
            throw "Elevated operation '$Func' failed."
        }
    } finally {
        Remove-Item -Path $sessionRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function _EnsureStore {
    param(
        [ValidateSet('User','Machine')]
        [string]$Scope = 'User'
    )
    $root = if ($Scope -eq 'User') { $script:Edgey_UserRoot } else { $script:Edgey_AdminRoot }
    if (-not (Test-Path $root)) { New-Item -Path $root -ItemType Directory -Force | Out-Null }
    $stack = Join-Path $root $script:Edgey_StackName
    if (-not (Test-Path $stack)) { @() | ConvertTo-Json | Out-File -FilePath $stack -Encoding UTF8 }
    return @{ Root = $root; Stack = $stack }
}

function _ReadStack($stackFile) {
    if (-not (Test-Path $stackFile)) { return @() }
    $raw = Get-Content $stackFile -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $parsed = $raw | ConvertFrom-Json
    if ($null -eq $parsed) { return @() }
    return @($parsed)
}
function _WriteStack($stackFile,$obj) {
    $normalized = if ($null -eq $obj) { @() } else { @($obj) }
    $normalized | ConvertTo-Json -Depth 6 | Out-File -FilePath $stackFile -Encoding UTF8
}

function _GetEdgeInstallRoots {
    @("C:\Program Files (x86)\Microsoft\Edge\Application","C:\Program Files\Microsoft\Edge\Application") | ForEach-Object {
        if (Test-Path $_) { Get-ChildItem -Path $_ -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } }
    }
}

function _GetProfileVariations {
    $ud = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data"
    if (-not (Test-Path $ud)) { return @() }
    Get-ChildItem -Path $ud -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $v = Join-Path $_.FullName "Variations"
        if (Test-Path $v) { $v }
    }
}

function Stop-Edge {
    [CmdletBinding()]
    param(
        [ValidateSet('User','Machine')]
        [string]$Scope = 'User'
    )
    if ($Scope -eq 'User') {
        $sid = (Get-Process -Id $PID).SessionId
        Get-Process -Name msedge -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sid } | Stop-Process -Force -ErrorAction SilentlyContinue
    } else {
        Get-Process -Name msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

# Core commands
function Backup-Edge {
    [CmdletBinding()]
    param(
        [string]$Note = "",
        [ValidateSet('User','Machine')]
        [string]$Scope = 'User'
    )
    if ($Scope -eq 'Machine' -and -not (Test-IsAdmin)) { Invoke-EdgeyElevated -Func "Backup-Edge" -Parameters @("-Note", $Note, "-Scope", "Machine"); return }

    $info = _EnsureStore -Scope $Scope
    Stop-Edge -Scope $Scope
    $paths = if ($Scope -eq 'User') { _GetProfileVariations } else { _GetEdgeInstallRoots | ForEach-Object { Join-Path $_ "Variations" } }
    if (-not $paths) { Write-Output "No variations paths found."; return }

    $id = [guid]::NewGuid().ToString(); $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $dest = Join-Path $info.Root ("backup_{0}_{1}" -f $ts,$id); New-Item -Path $dest -ItemType Directory -Force | Out-Null
    $col = @()
    foreach ($v in $paths) {
        if (Test-Path $v) {
            Get-ChildItem -Path $v -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'seed|variations_seed' } | ForEach-Object {
                $sub = Split-Path $v -Leaf
                $td = Join-Path $dest $sub; if (-not (Test-Path $td)) { New-Item -Path $td -ItemType Directory | Out-Null }
                $t = Join-Path $td $_.Name
                Copy-Item -Path $_.FullName -Destination $t -Force -ErrorAction SilentlyContinue
                $h = (Get-FileHash -Path $t -Algorithm SHA256).Hash
                $col += [pscustomobject]@{ Source = $_.FullName; Backup = $t; Hash = $h }
            }
        }
    }
    $entry = [pscustomobject]@{ Id=$id; Timestamp=$ts; Note=$Note; Scope=$Scope; PerUser=($Scope -eq 'User'); Files=$col }
    $stack = _ReadStack $info.Stack; $stack = ,$entry + $stack; _WriteStack $info.Stack $stack
    return $entry
}

function Push-Edge {
    [CmdletBinding()]
    param(
        [string]$Note = "",
        [ValidateSet('User','Machine')]
        [string]$Scope = 'User'
    )
    if ($Scope -eq 'Machine' -and -not (Test-IsAdmin)) { Invoke-EdgeyElevated -Func "Push-Edge" -Parameters @("-Note", $Note, "-Scope", "Machine"); return }
    $b = Backup-Edge -Note $Note -Scope $Scope
    if (-not $b) { throw "Backup failed." }
    foreach ($f in $b.Files) { if (Test-Path $f.Source) { Rename-Item -Path $f.Source -NewName ($([IO.Path]::GetFileName($f.Source) + ".bak")) -ErrorAction SilentlyContinue } }
    Write-Output "Pushed: $($b.Id)"
}

function Pop-Edge {
    [CmdletBinding()]
    param(
        [ValidateSet('User','Machine')]
        [string]$Scope = 'User'
    )
    if ($Scope -eq 'Machine' -and -not (Test-IsAdmin)) { Invoke-EdgeyElevated -Func "Pop-Edge" -Parameters @("-Scope", "Machine"); return }
    $info = _EnsureStore -Scope $Scope
    Stop-Edge -Scope $Scope
    $stack = _ReadStack $info.Stack
    if (-not $stack -or $stack.Count -eq 0) { throw "No backups." }
    $entry = $stack[0]
    foreach ($f in $entry.Files) {
        if (Test-Path $f.Backup) {
            try { Copy-Item -Path $f.Backup -Destination $f.Source -Force -ErrorAction SilentlyContinue } catch {
                $leaf = Split-Path $f.Source -Leaf
                $cands = if ($Scope -eq 'User') { _GetProfileVariations } else { _GetEdgeInstallRoots | ForEach-Object { Join-Path $_ "Variations" } }
                foreach ($c in $cands) { $cand = Join-Path $c $leaf; Copy-Item -Path $f.Backup -Destination $cand -Force -ErrorAction SilentlyContinue }
            }
        }
        $bak = $f.Source + ".bak"; if (Test-Path $bak) { Remove-Item $bak -Force -ErrorAction SilentlyContinue }
    }
    $new = @($stack | Select-Object -Skip 1); _WriteStack $info.Stack $new
    Write-Output "Restored: $($entry.Id)"
}

function Get-EdgeBackups {
    param(
        [ValidateSet('User','Machine')]
        [string]$Scope = 'User'
    )
    $info = _EnsureStore -Scope $Scope
    _ReadStack $info.Stack
}

function Restore-Edge {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [ValidateSet('User','Machine')]
        [string]$Scope = 'User'
    )
    if ($Scope -eq 'Machine' -and -not (Test-IsAdmin)) { Invoke-EdgeyElevated -Func "Restore-Edge" -Parameters @("-Id", $Id, "-Scope", "Machine"); return }
    $info = _EnsureStore -Scope $Scope
    Stop-Edge -Scope $Scope
    $stack = _ReadStack $info.Stack
    $entry = $stack | Where-Object { $_.Id -eq $Id }
    if (-not $entry) { throw "Not found." }
    foreach ($f in $entry.Files) {
        if (Test-Path $f.Backup) {
            try { Copy-Item -Path $f.Backup -Destination $f.Source -Force -ErrorAction SilentlyContinue } catch {
                $leaf = Split-Path $f.Source -Leaf
                $cands = if ($Scope -eq 'User') { _GetProfileVariations } else { _GetEdgeInstallRoots | ForEach-Object { Join-Path $_ "Variations" } }
                foreach ($c in $cands) { $cand = Join-Path $c $leaf; Copy-Item -Path $f.Backup -Destination $cand -Force -ErrorAction SilentlyContinue }
            }
        }
    }
    Write-Output "Restored id: $Id"
}

function Get-EdgeDsregcmdStatusLines {
    [CmdletBinding()]
    param()
    try {
        @(dsregcmd /status 2>&1 | ForEach-Object { $_.ToString() })
    } catch {
        @()
    }
}

function Get-EdgeDsregcmdDiagnosticsReport {
    [CmdletBinding()]
    param()

    $lines = @(Get-EdgeDsregcmdStatusLines)
    $summary = @(
        $lines |
            Where-Object { $_ -match '^\s*(AzureAdJoined|WorkplaceJoined|WorkplaceTenantId)\s*:\s*.+$' }
    )
    if ($null -eq $summary) { $summary = @() }

    [ordered]@{
        command = 'dsregcmd /status'
        status  = if ($lines.Count -gt 0) { 'ok' } else { 'unavailable' }
        summary  = $summary
    }
}

function Get-EdgeInstallDiagnosticsReport {
    [CmdletBinding()]
    param()

    $roots = @(_GetEdgeInstallRoots)
    $versions = foreach ($root in $roots) {
        $exe = Join-Path $root 'msedge.exe'
        if (Test-Path $exe) {
            [ordered]@{
                path    = $root
                version = (Get-Item $exe).VersionInfo.ProductVersion
            }
        }
    }

    [ordered]@{
        roots    = $roots
        versions = if ($null -eq $versions) { @() } else { @($versions) }
    }
}

function Get-EdgeVariationDiagnosticsReport {
    [CmdletBinding()]
    param()

    $roots = @(_GetEdgeInstallRoots)
    $candidatePaths = @(_GetProfileVariations) + @($roots | ForEach-Object { Join-Path $_ 'Variations' })
    $paths = @($candidatePaths | Select-Object -Unique)
    $files = foreach ($path in $paths) {
        if (Test-Path $path) {
            Get-ChildItem -Path $path -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'seed|variations_seed' } |
                ForEach-Object {
                    [ordered]@{
                        folder = $path
                        file   = $_.Name
                        hash   = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
                        size   = $_.Length
                    }
                }
        }
    }

    [ordered]@{
        paths = $paths
        files = if ($null -eq $files) { @() } else { @($files) }
    }
}

function Get-EdgeProcessDiagnosticsReport {
    [CmdletBinding()]
    param()

    $processes = @(Get-Process -Name msedge -ErrorAction SilentlyContinue | Select-Object Id,StartTime,Path -ErrorAction SilentlyContinue)
    if ($null -eq $processes) { $processes = @() }

    [ordered]@{
        name      = 'msedge'
        processes = $processes
    }
}

function Get-EdgeBackupDiagnosticsReport {
    [CmdletBinding()]
    param()

    $userInfo = _EnsureStore -Scope User
    $adminInfo = if (Test-IsAdmin) { _EnsureStore -Scope Machine } else { $null }
    $userBackups = @()
    if (Test-Path $userInfo.Root) {
        $userBackups = @(Get-ChildItem -Path $userInfo.Root -Directory -ErrorAction SilentlyContinue | Select-Object Name,LastWriteTime)
        if ($null -eq $userBackups) { $userBackups = @() }
    }

    $machineRoot = 'requires elevation'
    $machineBackups = @()
    if ($adminInfo) {
        $machineRoot = $adminInfo.Root
        if (Test-Path $adminInfo.Root) {
            $machineBackups = @(Get-ChildItem -Path $adminInfo.Root -Directory -ErrorAction SilentlyContinue | Select-Object Name,LastWriteTime)
            if ($null -eq $machineBackups) { $machineBackups = @() }
        }
    }

    [ordered]@{
        user = [ordered]@{
            root    = $userInfo.Root
            backups = $userBackups
        }
        machine = [ordered]@{
            root    = $machineRoot
            backups = $machineBackups
        }
    }
}

function New-EdgeDiagnosticsReport {
    [CmdletBinding()]
    param()

    [ordered]@{
        generatedAt = (Get-Date).ToString('o')
        computer    = $env:COMPUTERNAME
        user        = $env:USERNAME
        dsregcmd    = Get-EdgeDsregcmdDiagnosticsReport
        edge        = Get-EdgeInstallDiagnosticsReport
        variations  = Get-EdgeVariationDiagnosticsReport
        processes   = Get-EdgeProcessDiagnosticsReport
        backups     = Get-EdgeBackupDiagnosticsReport
    }
}

function Test-IsEdgeDiagnosticsScalar {
    param([object]$Value)

    if ($null -eq $Value) { return $true }
    if ($Value -is [string]) { return $true }
    if ($Value -is [char]) { return $true }
    if ($Value -is [bool]) { return $true }
    if ($Value -is [datetime]) { return $true }
    if ($Value -is [datetimeoffset]) { return $true }
    if ($Value -is [guid]) { return $true }
    if ($Value -is [timespan]) { return $true }
    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [short] -or $Value -is [ushort] -or $Value -is [int] -or $Value -is [uint] -or $Value -is [long] -or $Value -is [ulong] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) { return $true }
    return $false
}

function ConvertTo-EdgeDiagnosticsArray {
    param([object]$Value)

    if ($null -eq $Value) { return @() }
    if ($Value -is [array]) { return @($Value) }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) { return @($Value) }
    return @($Value)
}

function ConvertTo-EdgeDiagnosticsYamlScalar {
    param([object]$Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [datetime] -or $Value -is [datetimeoffset]) { return "'$($Value.ToString('o'))'" }
    if ($Value -is [guid] -or $Value -is [timespan]) { return "'$($Value.ToString())'" }
    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [short] -or $Value -is [ushort] -or $Value -is [int] -or $Value -is [uint] -or $Value -is [long] -or $Value -is [ulong] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $Value))
    }

    $text = [string]$Value
    return "'$( $text -replace "'", "''" )'"
}

function ConvertTo-EdgeDiagnosticsYamlLines {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,
        [int]$Indent = 0
    )

    $pad = ' ' * $Indent

    if (Test-IsEdgeDiagnosticsScalar $InputObject) {
        return @("$pad$(ConvertTo-EdgeDiagnosticsYamlScalar $InputObject)")
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $lines = @()
        foreach ($key in $InputObject.Keys) {
            $value = $InputObject[$key]
            $lines += ConvertTo-EdgeDiagnosticsYamlEntry -Name ([string]$key) -Value $value -Indent $Indent
        }
        return $lines
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $items = @($InputObject)
        if ($items.Count -eq 0) { return @("$pad[]") }

        $lines = @()
        foreach ($item in $items) {
            if (Test-IsEdgeDiagnosticsScalar $item) {
                $lines += "${pad}- $(ConvertTo-EdgeDiagnosticsYamlScalar $item)"
            } else {
                $lines += "${pad}-"
                $lines += ConvertTo-EdgeDiagnosticsYamlLines -InputObject $item -Indent ($Indent + 2)
            }
        }
        return $lines
    }

    $properties = @($InputObject.PSObject.Properties)
    if ($properties.Count -eq 0) {
        return @("$pad{}")
    }

    $lines = @()
    foreach ($property in $properties) {
        $lines += ConvertTo-EdgeDiagnosticsYamlEntry -Name $property.Name -Value $property.Value -Indent $Indent
    }
    return $lines
}

function ConvertTo-EdgeDiagnosticsYamlEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [object]$Value,
        [int]$Indent = 0
    )

    $pad = ' ' * $Indent

    if ($null -eq $Value) {
        return @("${pad}${Name}: null")
    }

    if (Test-IsEdgeDiagnosticsScalar $Value) {
        return @("${pad}${Name}: $(ConvertTo-EdgeDiagnosticsYamlScalar $Value)")
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $items = @($Value.Keys)
        if ($items.Count -eq 0) { return @("${pad}${Name}: {}") }

        $lines = @("${pad}${Name}:")
        $lines += ConvertTo-EdgeDiagnosticsYamlLines -InputObject $Value -Indent ($Indent + 2)
        return $lines
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return @("${pad}${Name}: []") }

        $lines = @("${pad}${Name}:")
        foreach ($item in $items) {
            if (Test-IsEdgeDiagnosticsScalar $item) {
                $lines += "$((' ' * ($Indent + 2)))- $(ConvertTo-EdgeDiagnosticsYamlScalar $item)"
            } else {
                $lines += "$((' ' * ($Indent + 2)))-"
                $lines += ConvertTo-EdgeDiagnosticsYamlLines -InputObject $item -Indent ($Indent + 4)
            }
        }
        return $lines
    }

    $lines = @("${pad}${Name}:")
    $lines += ConvertTo-EdgeDiagnosticsYamlLines -InputObject $Value -Indent ($Indent + 2)
    return $lines
}

function ConvertTo-EdgeDiagnosticsYamlText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    @(ConvertTo-EdgeDiagnosticsYamlLines -InputObject $InputObject) -join "`n"
}

function Test-Edge {
    [CmdletBinding()]
    param()
    $report = New-EdgeDiagnosticsReport
    ConvertTo-EdgeDiagnosticsYamlText -InputObject $report
}

Export-ModuleMember -Function Backup-Edge, Push-Edge, Pop-Edge, Get-EdgeBackups, Restore-Edge, Test-Edge, Stop-Edge
