# Every script parses, and the files Windows PowerShell 5.1 reads without a BOM stay ASCII.
BeforeDiscovery {
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:scripts = @(Get-ChildItem $root -Filter '*.ps1' -File | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
    $script:helpers = @('LinuxifyTerminal.ps1', 'LinuxifyBackup.ps1', 'LinuxifyAlpha.ps1' | ForEach-Object { @{ Name = $_; Path = (Join-Path $root $_) } })
}

Describe 'scripts' {
    It '<Name> parses without errors' -ForEach $scripts {
        $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errs)
        $errs | Should -BeNullOrEmpty
    }
    It '<Name> is ASCII only (5.1 would read it as ANSI)' -ForEach $helpers {
        $bad = [IO.File]::ReadAllBytes($Path) | Where-Object { $_ -gt 127 }
        $bad | Should -BeNullOrEmpty
    }
}
