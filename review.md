# Edgey.psm1 — Code Review

**File reviewed:** `Edgey.psm1`  
**Date:** 2026-06-13  
**Scope:** Bugs, security, design correctness, PowerShell conventions

---

## Summary

| Severity | Count |
|---|---|
| Critical (bugs) | 4 |
| High (security) | 2 |
| Medium (design) | 3 |
| Low (conventions) | 4 |

---

## Critical — Bugs

### 1. `Start-Edgey` exported but never defined

`Export-ModuleMember` at the bottom of the file lists `Start-Edgey`, but no such function exists anywhere in the module. Importing the module succeeds, but calling `Start-Edgey` throws a `CommandNotFoundException`.

**Fix:** Remove `Start-Edgey` from `Export-ModuleMember`, or implement the function.

```powershell
# Current (line ~170)
Export-ModuleMember -Function Backup-Edgey, Push-Edgey, Pop-Edgey, Get-EdgeyBackups, Restore-Edgey, Test-Edgey, Stop-Edgey, Start-Edgey

# Fixed
Export-ModuleMember -Function Backup-Edgey, Push-Edgey, Pop-Edgey, Get-EdgeyBackups, Restore-Edgey, Test-Edgey, Stop-Edgey
```

---

### 2. `Pop-Edgey` writes `null` to the stack when the last entry is popped

`$stack | Select-Object -Skip 1` on a single-element array returns `$null` in PowerShell, not `@()`. `_WriteStack` then serializes `null` to JSON. On the next call, `_ReadStack` returns `$null` instead of an empty array, breaking all subsequent stack operations (`$stack.Count`, indexing, etc.).

**Fix:** Force an array with the unary array operator:

```powershell
# Current
$new = $stack | Select-Object -Skip 1; _WriteStack $info.Stack $new

# Fixed
$new = @($stack | Select-Object -Skip 1); _WriteStack $info.Stack $new
```

---

### 3. `Restore-Edgey` does not stop Edge before restoring

`Pop-Edgey` calls `Stop-Edgey -PerUser:$PerUser` before copying files back. `Restore-Edgey` does not. Edge holds open file handles on the seed files; the copy either fails silently (`-ErrorAction SilentlyContinue`) or Edge overwrites the restored file within seconds of restarting.

**Fix:** Add `Stop-Edgey` at the start of `Restore-Edgey`:

```powershell
function Restore-Edgey {
    param([Parameter(Mandatory=$true)][string]$Id, [switch]$PerUser)
    if (-not $PerUser -and -not (Test-IsAdmin)) { ... }
    $info = _EnsureStore -PerUser:$PerUser
    Stop-Edgey -PerUser:$PerUser   # <-- add this
    ...
```

---

### 4. Null array concatenation crash in `Test-Edgey`

```powershell
$cands = _GetProfileVariations + ($roots | ForEach-Object { Join-Path $_ "Variations" })
```

When `_GetProfileVariations` returns `$null` (no `User Data` directory found), PowerShell evaluates `$null + @(...)` as `@($null, item1, item2, ...)`, injecting a `$null` element. The subsequent `foreach ($v in $cands | Select-Object -Unique)` passes `$null` to `Test-Path`, which throws a terminating error.

**Fix:**

```powershell
$cands = @(_GetProfileVariations) + @($roots | ForEach-Object { Join-Path $_ "Variations" })
```

---

## High — Security

### 5. Argument injection in `_Invoke-Elevated`

Parameters (including `$Note`) are string-interpolated directly into the body of a temp `.ps1` file that is then executed elevated:

```powershell
$argLine = if ($Args) { $Args -join ' ' } else { '' }
$script = "Import-Module `"$PSScriptRoot\Edgey.psm1`"`n& $Func $argLine"
$script | Out-File -FilePath $tmp ...
Start-Process ... -Verb RunAs ...
```

A caller passing `-Note 'clean"; Remove-Item C:\ -Recurse -Force #'` would inject arbitrary PowerShell into the elevated script.

**Fix:** Avoid string interpolation for arguments. Use `-EncodedCommand` with a base64-encoded script block, or serialize arguments to a CliXml file and read them back in the elevated script:

```powershell
# Safer pattern — encode everything
$scriptBlock = "Import-Module '$PSScriptRoot\Edgey.psm1'; & $Func @args"
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptBlock))
# Pass $Args via a CliXml side-file, not inline
```

---

### 6. TOCTOU race on the temp elevation script

The temp file is written to the user's shared `$env:TEMP` directory, then a brief window exists before `Start-Process` picks it up. Another process (or a pre-positioned malicious file with a predicted name) could replace the content. Because the script runs elevated, this is a privilege-escalation vector.

**Fix:** Either write to a uniquely named subdirectory that only the current user can access, or eliminate the file entirely by using `-EncodedCommand` (which also resolves finding #5).

---

## Medium — Design

### 7. `Test-Edgey` returns formatting output, not objects

```powershell
$o | Format-List
```

`Format-List` produces `Microsoft.PowerShell.Commands.Internal.Format.*` objects. These cannot be piped to `Select-Object`, `Export-Csv`, `ConvertTo-Json`, or any downstream command. The function is effectively write-only.

**Fix:** Return the raw object and let callers decide formatting:

```powershell
return [PSCustomObject]$o
```

---

### 8. Silent side effect on module import

```powershell
# Auto-init on import
_EnsureStore -PerUser | Out-Null
```

This runs unconditionally at module scope, creating `~/EdgeyBackup/` and `~/EdgeyBackup/stack.json` the moment someone imports the module — even if they only wanted to inspect exported commands. Each exported function already calls `_EnsureStore` internally, making this line redundant.

**Fix:** Remove the module-scope call. Add a comment in `_EnsureStore` that it is idempotent (safe to call multiple times).

---

### 9. No error propagation from `_Invoke-Elevated`

After `Start-Process ... -Wait`, the parent process discards the elevated child's exit code and has no way to tell whether the operation succeeded, was cancelled by UAC, or threw an exception.

**Fix:** Write a status file to `$env:TEMP` inside the elevated script and read it back in the caller:

```powershell
# In elevated script (last line)
"OK" | Out-File $statusFile

# In caller, after Start-Process -Wait
if (-not (Test-Path $statusFile) -or (Get-Content $statusFile) -ne 'OK') {
    Write-Warning "Elevated operation may have failed."
}
```

---

## Low — PowerShell Conventions

### 10. `_Prefix` naming is non-standard

Private helpers (`_EnsureStore`, `_ReadStack`, `_WriteStack`, `_GetEdgeInstallRoots`, `_GetProfileVariations`, `_Invoke-Elevated`) use a leading underscore, which is a Python/JavaScript convention. PowerShell private helpers are simply unexported functions — no prefix needed.

**Fix (optional):** Rename to standard verb-noun (e.g., `Initialize-EdgeyStore`, `Read-EdgeyStack`, `Write-EdgeyStack`) and omit from `Export-ModuleMember`.

---

### 11. `Stop-Edgey` and `Push-Edgey` lack `[CmdletBinding()]`

`Backup-Edgey`, `Pop-Edgey`, and `Test-Edgey` all declare `[CmdletBinding()]`. `Stop-Edgey` and `Push-Edgey` do not, making them inconsistent and preventing `-Verbose`/`-WhatIf` support in future.

**Fix:** Add `[CmdletBinding()]` to both functions.

---

### 12. `Write-Output` used for user-facing status messages

```powershell
Write-Output "Pushed: $($b.Id)"
Write-Output "Restored: $($entry.Id)"
```

`Write-Output` sends objects into the pipeline. Callers who capture the function result (e.g., `$result = Pop-Edgey`) will receive a status string mixed with any structured return value. Use `Write-Host` for console-only messages, or `Write-Information` for suppressible informational output.

---

### 13. No `#Requires` statement

The module uses `[ordered]` hashtables, `ConvertTo-Json -Depth`, and other features that require PowerShell 5.1+. Without a `#Requires` directive, loading on an older host gives confusing errors.

**Fix:** Add at the top of the file:

```powershell
#Requires -Version 5.1
```

---

## Verification Checklist (after applying fixes)

1. `Import-Module .\Edgey.psm1` — no errors or warnings
2. `(Get-Module Edgey).ExportedFunctions.Keys` — `Start-Edgey` is absent
3. `Backup-Edgey -PerUser; Pop-Edgey -PerUser` — `stack.json` contains `[]`, not `null`
4. `Test-Edgey | Select-Object -Property EdgeVersions` — returns structured data, not an empty result
5. `Backup-Edgey -Note 'test"injection; Write-Host INJECTED'` — elevation script is not broken or hijacked
6. `Restore-Edgey -Id <id>` while Edge is running — Edge is stopped before files are copied
