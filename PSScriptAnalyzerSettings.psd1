@{
    IncludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseSingularNouns',
        'PSUseApprovedVerbs',
        'PSAvoidUsingCmdletAliases',
        'PSAvoidGlobalVars',
        'PSUseConsistentIndentation',
        'PSUseConsistentWhitespace',
        'PSUseConsistentQuotes',
        'PSUseLiteralInitializerForHashtable'
    )

    Rules = @{
        PSUseConsistentIndentation = @{
            Enable = $true
            Kind = 'space'
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
        }

        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckPipeForRedundantWhitespace = $true
            CheckSeparator = $true
        }

        PSUseConsistentQuotes = @{
            Enable = $true
            CheckSingleQuote = $true
            CheckDoubleQuote = $true
        }
    }
}
