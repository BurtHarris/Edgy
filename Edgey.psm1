```powershell
<#
.SYNOPSIS
Edgey - simple per-user-first tools to backup/disable/restore Edge variations seed files and diagnose state.
.DESCRIPTION
Auto-initializes per-user store on import. Elevates only for machine-level operations.
#>

# Config
$script:Edgey_UserRoot = Join-Path $env:USERPROFILE "EdgeyBackup"
$script:Edgey_AdminRoot = "C:\EdgeyBackup"
$script:Edgey_StackName = "stack.json"

# Helpers
function Test-IsAdmin { ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }

function _Invoke-Elevated {
    param($Func, $Args)
    $tmp = Join-Path $env:TEMP ("Edgey_Elevate_{0}.ps1" -f ([guid]::NewGuid()))
    $argLine = if ($Args) { $Args -join ' ' } else { '' }
    $script = "Import-Module `"$PSScriptRoot\Edgey.psm1`"`n& $Func $argLine"
    $script | Out-File -FilePath $tmp -Encoding UTF8
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tmp`"" -Verb RunAs -Wait
    Remove-Item $tmp -ErrorAction SilentlyContinue
}

function _EnsureStore {
    param([switch]$PerUser)
    $root = if ($PerUser) { $script:Edgey_UserRoot } else { $script:Edgey_AdminRoot }
    if (-not (Test-Path $root)) { New-Item -Path $root -ItemType Directory -Force | Out-Null }
    $stack = Join-Path $root $script:Edgey_StackName
    if (-not (Test-Path $stack)) { @() | ConvertTo-Json | Out-File -FilePath $stack -Encoding UTF8 }
    return @{ Root = $root; Stack = $stack }
}

function _ReadStack($stackFile) { if (-not (Test-Path $stackFile)) { @() } else { Get-Content $stackFile -Raw | ConvertFrom-Json } }
function _WriteStack($stackFile,$obj) { $obj | ConvertTo-Json -Depth 6 | Out-File -FilePath $stackFile -Encoding UTF8 }

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

function Stop-Edgey {
    param([switch]$PerUser)
    if ($PerUser) {
        $sid = (Get-Process -Id $PID).SessionId
        Get-Process -Name msedge -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sid } | Stop-Process -Force -ErrorAction SilentlyContinue
    } else {
        Get-Process -Name msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

# Auto-init on import
_EnsureStore -PerUser | Out-Null

# Core commands
function Backup-Edgey {
    [CmdletBinding()]
    param([string]$Note = "", [switch]$PerUser)
    if (-not $PerUser -and -not (Test-IsAdmin)) { _Invoke-Elevated -Func "Backup-Edgey" -Args @("-Note `"$Note`"","-PerUser:$false"); return }

    $info = _EnsureStore -PerUser:$PerUser
    Stop-Edgey -PerUser:$PerUser
    $paths = if ($PerUser) { _GetProfileVariations } else { _GetEdgeInstallRoots | ForEach-Object { Join-Path $_ "Variations" } }
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
    $entry = [pscustomobject]@{ Id=$id; Timestamp=$ts; Note=$Note; PerUser=$PerUser.IsPresent; Files=$col }
    $stack = _ReadStack $info.Stack; $stack = ,$entry + $stack; _WriteStack $info.Stack $stack
    return $entry
}

function Push-Edgey {
    [CmdletBinding()]
    param([string]$Note = "", [switch]$PerUser)
    if (-not $PerUser -and -not (Test-IsAdmin)) { _Invoke-Elevated -Func "Push-Edgey" -Args @("-Note `"$Note`"","-PerUser:$false"); return }
    $b = Backup-Edgey -Note $Note -PerUser:$PerUser
    if (-not $b) { throw "Backup failed." }
    foreach ($f in $b.Files) { if (Test-Path $f.Source) { Rename-Item -Path $f.Source -NewName ($([IO.Path]::GetFileName($f.Source) + ".bak")) -ErrorAction SilentlyContinue } }
    Write-Output "Pushed: $($b.Id)"
}

function Pop-Edgey {
    [CmdletBinding()]
    param([switch]$PerUser)
    if (-not $PerUser -and -not (Test-IsAdmin)) { _Invoke-Elevated -Func "Pop-Edgey" -Args @("-PerUser:$false"); return }
    $info = _EnsureStore -PerUser:$PerUser
    Stop-Edgey -PerUser:$PerUser
    $stack = _ReadStack $info.Stack
    if (-not $stack -or $stack.Count -eq 0) { throw "No backups." }
    $entry = $stack[0]
    foreach ($f in $entry.Files) {
        if (Test-Path $f.Backup) {
            try { Copy-Item -Path $f.Backup -Destination $f.Source -Force -ErrorAction SilentlyContinue } catch {
                $leaf = Split-Path $f.Source -Leaf
                $cands = if ($PerUser) { _GetProfileVariations } else { _GetEdgeInstallRoots | ForEach-Object { Join-Path $_ "Variations" } }
                foreach ($c in $cands) { $cand = Join-Path $c $leaf; Copy-Item -Path $f.Backup -Destination $cand -Force -ErrorAction SilentlyContinue }
            }
        }
        $bak = $f.Source + ".bak"; if (Test-Path $bak) { Remove-Item $bak -Force -ErrorAction SilentlyContinue }
    }
    $new = $stack | Select-Object -Skip 1; _WriteStack $info.Stack $new
    Write-Output "Restored: $($entry.Id)"
}

function Get-EdgeyBackups { param([switch]$PerUser) $info = _EnsureStore -PerUser:$PerUser; _ReadStack $info.Stack }

function Restore-Edgey {
    param([Parameter(Mandatory=$true)][string]$Id, [switch]$PerUser)
    if (-not $PerUser -and -not (Test-IsAdmin)) { _Invoke-Elevated -Func "Restore-Edgey" -Args @("-Id `"$Id`"","-PerUser:$false"); return }
    $info = _EnsureStore -PerUser:$PerUser
    $stack = _ReadStack $info.Stack
    $entry = $stack | Where-Object { $_.Id -eq $Id }
    if (-not $entry) { throw "Not found." }
    foreach ($f in $entry.Files) {
        if (Test-Path $f.Backup) {
            try { Copy-Item -Path $f.Backup -Destination $f.Source -Force -ErrorAction SilentlyContinue } catch {
                $leaf = Split-Path $f.Source -Leaf
                $cands = if ($PerUser) { _GetProfileVariations } else { _GetEdgeInstallRoots | ForEach-Object { Join-Path $_ "Variations" } }
                foreach ($c in $cands) { $cand = Join-Path $c $leaf; Copy-Item -Path $f.Backup -Destination $cand -Force -ErrorAction SilentlyContinue }
            }
        }
    }
    Write-Output "Restored id: $Id"
}

function Diagnose-Edgey {
    [CmdletBinding()]
    param()
    $o = [ordered]@{}
    try { $ds = dsregcmd /status 2>&1; $o.Dsreg = ($ds | Select-String -Pattern 'AzureAdJoined|WorkplaceJoined|WorkplaceTenantId' -SimpleMatch).ToString() } catch { $o.Dsreg = "dsregcmd unavailable" }
    $roots = _GetEdgeInstallRoots; $o.EdgeRoots = $roots
    $vers = @(); foreach ($r in $roots) { $exe = Join-Path $r "msedge.exe"; if (Test-Path $exe) { $vers += [pscustomobject]@{ Path=$r; Version=(Get-Item $exe).VersionInfo.ProductVersion } } }
    $o.EdgeVersions = $vers
    $vars = @(); $cands = _GetProfileVariations + ($roots | ForEach-Object { Join-Path $_ "Variations" })
    foreach ($v in $cands | Select-Object -Unique) { if (Test-Path $v) { Get-ChildItem -Path $v -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'seed|variations_seed' } | ForEach-Object { $h=(Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash; $vars += [pscustomobject]@{ Folder=$v; File=$_.Name; Hash=$h; Size=$_.Length } } } }
    $o.Variations = $vars
    $o.Processes = Get-Process -Name msedge -ErrorAction SilentlyContinue | Select-Object Id,StartTime,Path -ErrorAction SilentlyContinue
    $userInfo = _EnsureStore -PerUser; $o.UserBackupRoot = $userInfo.Root; $o.UserBackups = if (Test-Path $userInfo.Root) { Get-ChildItem -Path $userInfo.Root -Directory -ErrorAction SilentlyContinue | Select-Object Name,LastWriteTime } else { @() }
    if (Test-IsAdmin) { $adm = _EnsureStore -PerUser:$false; $o.AdminBackupRoot = $adm.Root; $o.AdminBackups = if (Test-Path $adm.Root) { Get-ChildItem -Path $adm.Root -Directory -ErrorAction SilentlyContinue | Select-Object Name,LastWriteTime } else { @() } } else { $o.AdminBackupRoot = "requires elevation" }
    $o | Format-List
}

Export-ModuleMember -Function Backup-Edgey, Push-Edgey, Pop-Edgey, Get-EdgeyBackups, Restore-Edgey, Diagnose-Edgey, Stop-Edgey, Start-Edgey
```
