Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot 'Edgey.psm1'
Import-Module $modulePath -Force

Describe 'Edgey module exports' {
    It 'does not export Start-Edge' {
        $exports = (Get-Module Edgey).ExportedFunctions.Keys
        $exports | Should -Not -Contain 'Start-Edge'
    }
}

Describe 'Pop-Edge stack behavior' {
    InModuleScope Edgey {
        It 'writes an empty array instead of null when popping the last backup' {
            $script:Edgey_UserRoot = Join-Path $TestDrive 'UserStore'
            $script:Edgey_AdminRoot = Join-Path $TestDrive 'MachineStore'

            $info = _EnsureStore -Scope User
            $entry = [pscustomobject]@{
                Id        = 'single'
                Timestamp = '20260613_000000'
                Note      = ''
                Scope     = 'User'
                PerUser   = $true
                Files     = @()
            }
            @($entry) | ConvertTo-Json -Depth 6 | Out-File -FilePath $info.Stack -Encoding UTF8

            Mock Stop-Edge {}

            $null = Pop-Edge -Scope User

            $raw = Get-Content -Path $info.Stack -Raw
            $raw | Should -Not -Match '\bnull\b'
            @($raw | ConvertFrom-Json).Count | Should -Be 0
        }
    }
}

Describe 'Restore-Edge behavior' {
    InModuleScope Edgey {
        It 'stops Edge before restoring' {
            $script:Edgey_UserRoot = Join-Path $TestDrive 'UserStoreRestore'
            $script:Edgey_AdminRoot = Join-Path $TestDrive 'MachineStoreRestore'

            $info = _EnsureStore -Scope User
            $entry = [pscustomobject]@{
                Id        = 'restore-id'
                Timestamp = '20260613_000000'
                Note      = ''
                Scope     = 'User'
                PerUser   = $true
                Files     = @()
            }
            @($entry) | ConvertTo-Json -Depth 6 | Out-File -FilePath $info.Stack -Encoding UTF8

            Mock Stop-Edge {}

            $null = Restore-Edge -Id 'restore-id' -Scope User

            Should -Invoke Stop-Edge -Times 1 -Exactly -ParameterFilter { $Scope -eq 'User' }
        }
    }
}

Describe 'Test-Edge output shape' {
    InModuleScope Edgey {
        It 'returns a PSCustomObject (not formatted output records)' {
            Mock _GetEdgeInstallRoots { @() }
            Mock _GetProfileVariations { @() }
            Mock Test-IsAdmin { $false }
            Mock _EnsureStore { @{ Root = (Join-Path $TestDrive 'DiagStore'); Stack = (Join-Path $TestDrive 'DiagStore\stack.json') } }
            Mock Get-Process { @() }
            Mock Get-ChildItem { @() }

            $result = Test-Edge

            $result.GetType().FullName | Should -Be 'System.Management.Automation.PSCustomObject'
            $result.PSObject.Properties.Name | Should -Contain 'Variations'
            $result.PSObject.Properties.Name | Should -Contain 'EdgeVersions'
        }
    }
}
