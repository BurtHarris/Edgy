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

function _Invoke-Elevated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Func,
        [object[]]$Args
    )

    $sessionRoot = Join-Path $env:TEMP ("Edgey_Elevate_{0}" -f ([guid]::NewGuid()))
    $payloadPath = Join-Path $sessionRoot "payload.clixml"
    $statusPath = Join-Path $sessionRoot "status.txt"

    try {
        New-Item -Path $sessionRoot -ItemType Directory -Force | Out-Null
        [pscustomobject]@{
            Func = $Func
            Args = @($Args)
        } | Export-Clixml -Path $payloadPath

        $modulePath = $script:Edgey_ModulePath.Replace("'", "''")
        $payloadLiteral = $payloadPath.Replace("'", "''")
        $statusLiteral = $statusPath.Replace("'", "''")

        $elevatedCommand = @"
`$ErrorActionPreference = 'Stop'
try {
    `$payload = Import-Clixml -Path '$payloadLiteral'
    Import-Module -Force '$modulePath'
    & `$payload.Func @(`$payload.Args)
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
    if ($Scope -eq 'Machine' -and -not (Test-IsAdmin)) { _Invoke-Elevated -Func "Backup-Edge" -Args @("-Note", $Note, "-Scope", "Machine"); return }

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
    if ($Scope -eq 'Machine' -and -not (Test-IsAdmin)) { _Invoke-Elevated -Func "Push-Edge" -Args @("-Note", $Note, "-Scope", "Machine"); return }
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
    if ($Scope -eq 'Machine' -and -not (Test-IsAdmin)) { _Invoke-Elevated -Func "Pop-Edge" -Args @("-Scope", "Machine"); return }
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
    if ($Scope -eq 'Machine' -and -not (Test-IsAdmin)) { _Invoke-Elevated -Func "Restore-Edge" -Args @("-Id", $Id, "-Scope", "Machine"); return }
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

function Test-Edge {
    [CmdletBinding()]
    param()
    $o = [ordered]@{}
    try { $ds = dsregcmd /status 2>&1; $o.Dsreg = ($ds | Select-String -Pattern 'AzureAdJoined|WorkplaceJoined|WorkplaceTenantId' -SimpleMatch).ToString() } catch { $o.Dsreg = "dsregcmd unavailable" }
    $roots = _GetEdgeInstallRoots; $o.EdgeRoots = $roots
    $vers = @(); foreach ($r in $roots) { $exe = Join-Path $r "msedge.exe"; if (Test-Path $exe) { $vers += [pscustomobject]@{ Path=$r; Version=(Get-Item $exe).VersionInfo.ProductVersion } } }
    $o.EdgeVersions = $vers
    $vars = @(); $cands = @(_GetProfileVariations) + @($roots | ForEach-Object { Join-Path $_ "Variations" })
    foreach ($v in $cands | Select-Object -Unique) { if (Test-Path $v) { Get-ChildItem -Path $v -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'seed|variations_seed' } | ForEach-Object { $h=(Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash; $vars += [pscustomobject]@{ Folder=$v; File=$_.Name; Hash=$h; Size=$_.Length } } } }
    $o.Variations = $vars
    $o.Processes = Get-Process -Name msedge -ErrorAction SilentlyContinue | Select-Object Id,StartTime,Path -ErrorAction SilentlyContinue
    $userInfo = _EnsureStore -Scope User; $o.UserBackupRoot = $userInfo.Root; $o.UserBackups = if (Test-Path $userInfo.Root) { Get-ChildItem -Path $userInfo.Root -Directory -ErrorAction SilentlyContinue | Select-Object Name,LastWriteTime } else { @() }
    if (Test-IsAdmin) { $adm = _EnsureStore -Scope Machine; $o.AdminBackupRoot = $adm.Root; $o.AdminBackups = if (Test-Path $adm.Root) { Get-ChildItem -Path $adm.Root -Directory -ErrorAction SilentlyContinue | Select-Object Name,LastWriteTime } else { @() } } else { $o.AdminBackupRoot = "requires elevation" }
    [PSCustomObject]$o
}

Export-ModuleMember -Function Backup-Edge, Push-Edge, Pop-Edge, Get-EdgeBackups, Restore-Edge, Test-Edge, Stop-Edge
