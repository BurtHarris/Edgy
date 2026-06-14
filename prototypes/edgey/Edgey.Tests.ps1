Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot 'Edgey.psm1'
Import-Module $modulePath -Force

Describe 'Edgey module exports' {
    It 'does not export Start-Edge' {
        $exports = (Get-Module Edgey).ExportedFunctions.Keys
        $exports | Should -Not -Contain 'Start-Edge'
    }
}

Describe 'Static regression guards' {
    It 'does not reintroduce legacy elevated helper tokens' {
        $currentModulePath = Join-Path $PSScriptRoot 'Edgey.psm1'
        $moduleText = Get-Content -Path $currentModulePath -Raw

        $moduleText | Should -Not -Match 'function\s+_Invoke-Elevated\b'
        $moduleText | Should -Not -Match '\$Args\b'
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

Describe 'Machine scope elevation delegation' {
    InModuleScope Edgey {
        It 'Backup-Edge delegates to Invoke-EdgeyElevated when not admin' {
            Mock Test-IsAdmin { $false }
            Mock Invoke-EdgeyElevated {}

            $null = Backup-Edge -Note 'n' -Scope Machine

            Should -Invoke Invoke-EdgeyElevated -Times 1 -Exactly -ParameterFilter {
                $Func -eq 'Backup-Edge' -and
                $Parameters[0] -eq '-Note' -and
                $Parameters[1] -eq 'n' -and
                $Parameters[2] -eq '-Scope' -and
                $Parameters[3] -eq 'Machine'
            }
        }

        It 'Restore-Edge delegates to Invoke-EdgeyElevated when not admin' {
            Mock Test-IsAdmin { $false }
            Mock Invoke-EdgeyElevated {}

            $null = Restore-Edge -Id 'x' -Scope Machine

            Should -Invoke Invoke-EdgeyElevated -Times 1 -Exactly -ParameterFilter {
                $Func -eq 'Restore-Edge' -and
                $Parameters[0] -eq '-Id' -and
                $Parameters[1] -eq 'x' -and
                $Parameters[2] -eq '-Scope' -and
                $Parameters[3] -eq 'Machine'
            }
        }
    }
}

Describe 'Edge diagnostics reports' {
    InModuleScope Edgey {
        It 'summarizes dsregcmd diagnostics from status lines' {
            Mock Get-EdgeDsregcmdStatusLines { @('AzureAdJoined : YES', 'WorkplaceJoined : NO', 'WorkplaceTenantId : 123') }

            $report = Get-EdgeDsregcmdDiagnosticsReport

            $report.command | Should -Be 'dsregcmd /status'
            $report.status | Should -Be 'ok'
            @($report.summary).Count | Should -Be 3
            $report.summary[0] | Should -Match 'AzureAdJoined'
        }

        It 'returns YAML text from Test-Edge' {
            Mock Get-EdgeDsregcmdStatusLines { @('AzureAdJoined : YES', 'WorkplaceJoined : NO') }
            Mock Get-EdgeInstallDiagnosticsReport { [ordered]@{ roots = @('C:\Edge'); versions = @([ordered]@{ path = 'C:\Edge'; version = '1.2.3.4' }) } }
            Mock Get-EdgeVariationDiagnosticsReport { [ordered]@{ paths = @('C:\Users\User\AppData\Local\Microsoft\Edge\User Data\Default\Variations'); files = @() } }
            Mock Get-EdgeProcessDiagnosticsReport { [ordered]@{ name = 'msedge'; processes = @() } }
            Mock Get-EdgeBackupDiagnosticsReport { [ordered]@{ user = [ordered]@{ root = 'C:\EdgeyBackup'; backups = @() }; machine = [ordered]@{ root = 'requires elevation'; backups = @() } } }
            Mock Test-IsAdmin { $false }

            $result = Test-Edge

            $result.GetType().FullName | Should -Be 'System.String'
            $result | Should -Match '(?m)^generatedAt: '
            $result | Should -Match '(?m)^dsregcmd:$'
            $result | Should -Match '(?m)^  command: '
            $result | Should -Match '(?m)^edge:$'
            $result | Should -Match '(?m)^variations:$'
            $result | Should -Match '(?m)^processes:$'
            $result | Should -Match '(?m)^backups:$'
            $result | Should -Match '(?m)^  machine:$'
        }

        It 'renders null YAML values without throwing' {
            $yaml = ConvertTo-EdgeDiagnosticsYamlText -InputObject ([ordered]@{ example = $null })

            $yaml | Should -Match '(?m)^example: null$'
        }

        It 'normalizes empty backup collections to arrays' {
            Mock _EnsureStore { @{ Root = (Join-Path $TestDrive 'EmptyBackupRoot'); Stack = (Join-Path $TestDrive 'EmptyBackupRoot\stack.json') } }
            Mock Test-IsAdmin { $false }

            $report = Get-EdgeBackupDiagnosticsReport

            @($report.user.backups).Count | Should -Be 0
            @($report.machine.backups).Count | Should -Be 0
        }
    }
}
