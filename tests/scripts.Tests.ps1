# Every script parses, and stays ASCII: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI, so any
# non-ASCII character in one would turn into something else on the user's machine.
BeforeDiscovery {
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:scripts = @(Get-ChildItem $root -Filter '*.ps1' -File | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

Describe 'scripts' {
    It '<Name> parses without errors' -ForEach $scripts {
        $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errs)
        $errs | Should -BeNullOrEmpty
    }
    It '<Name> is ASCII only' -ForEach $scripts {
        $bad = [IO.File]::ReadAllBytes($Path) | Where-Object { $_ -gt 127 }
        $bad | Should -BeNullOrEmpty
    }
}
