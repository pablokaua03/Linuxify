# The sign-in tray launch checks live in scripts\tray-boot.ps1 (plain assertions, one process each).
Describe 'tray launch at sign-in' {
    It 'passes every check in scripts\tray-boot.ps1' {
        $host_ = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $out = & $host_ -NoProfile -File (Join-Path (Join-Path $PSScriptRoot 'scripts') 'tray-boot.ps1') 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $out
        $out | Should -Match 'all passed'
    }
}
