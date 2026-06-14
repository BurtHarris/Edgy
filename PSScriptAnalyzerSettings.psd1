@{
    IncludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseSingularNouns',
        'PSUseApprovedVerbs',
        'PSAvoidUsingCmdletAliases',
        'PSAvoidGlobalVars',
        'PSUseConsistentQuotes',
        'PSUseLiteralInitializerForHashtable'
    )

    Rules = @{
        PSUseConsistentQuotes = @{
            Enable = $true
            CheckSingleQuote = $true
            CheckDoubleQuote = $true
        }
    }
}
