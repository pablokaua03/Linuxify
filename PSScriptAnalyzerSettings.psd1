@{
    # Errors fail the build. Warnings are listed in the log; most of them are style rules this
    # code base has never followed (Write-Host in installers, empty catch blocks around best-effort calls).
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidGlobalVars'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseSingularNouns'
        'PSAvoidUsingWriteHost'
    )
}
