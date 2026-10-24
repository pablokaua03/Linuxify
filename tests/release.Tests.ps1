# The release script: a zip that contains everything the installer needs, and a SHA256SUMS that verifies.
BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:script = Join-Path (Join-Path $root 'scripts') 'New-Release.ps1'
    $script:pwsh = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'New-Release.ps1' {
    BeforeAll {
        $script:out = New-LxSandbox
        $script:fakeExe = Join-Path $out 'in\Linuxify.exe'
        New-Item -ItemType Directory -Force (Split-Path $fakeExe) | Out-Null
        [IO.File]::WriteAllBytes($fakeExe, [byte[]](1..200))
        $script:dist = Join-Path $out 'dist'
        & $pwsh -NoProfile -File $script -Version 9.9.9 -Exe $fakeExe -OutDir $dist | Out-Null
        $script:LASTEXIT = $LASTEXITCODE
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $dist 'Linuxify-9.9.9.zip'))
        $script:names = @($z.Entries | ForEach-Object FullName)
        $z.Dispose()
    }
    AfterAll { Remove-Item $out -Recurse -Force -ErrorAction SilentlyContinue }

    It 'runs cleanly' { $LASTEXIT | Should -Be 0 }

    It 'writes SHA256SUMS in sha256sum format, and the hashes are right' {
        $lines = @([IO.File]::ReadAllText((Join-Path $dist 'SHA256SUMS')) -split "`n" | Where-Object { $_ })
        $lines.Count | Should -Be 2
        foreach ($l in $lines) {
            $l | Should -Match '^[0-9a-f]{64}  \S+$'
            $hash, $name = $l -split '  ', 2
            (Get-FileHash (Join-Path $dist $name) -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $hash
        }
        [IO.File]::ReadAllText((Join-Path $dist 'SHA256SUMS')) | Should -Not -Match "`r"
        ($lines | ForEach-Object { ($_ -split '  ', 2)[1] }) | Should -Be @('Linuxify-9.9.9.zip', 'Linuxify.exe')
    }

    It 'is verified by sha256sum when it is available' -Skip:(-not (Get-Command sha256sum -ErrorAction SilentlyContinue)) {
        Push-Location $dist
        try { & sha256sum -c SHA256SUMS | Out-Null; $LASTEXITCODE | Should -Be 0 } finally { Pop-Location }
    }

    It 'has forward-slash entry names and nothing from tests, .git or dist' {
        $names | Should -Not -Match '\\'
        $names | Should -Not -Match '^(tests|\.git|dist|scripts)/'
        $names | Should -Contain 'install.ps1'
        $names | Should -Contain 'configs/terminal/global.json'
        $names | Should -Contain 'Linuxify.exe'
    }

    It 'contains every file install.ps1 dot-sources or copies' {
        $inst = [IO.File]::ReadAllText((Join-Path $root 'install.ps1'))
        $sourced = [regex]::Matches($inst, 'Join-Path \$Src ''([^'']+\.ps1)''') | ForEach-Object { $_.Groups[1].Value }
        $copyList = [regex]::Match($inst, 'foreach \(\$f in ([^{]+)\{').Groups[1].Value
        $copied = [regex]::Matches($copyList, '''([^'']+)''') | ForEach-Object { $_.Groups[1].Value }
        $needed = @($sourced) + @($copied)
        $needed.Count | Should -BeGreaterThan 8
        foreach ($n in ($needed | ForEach-Object { $_.Replace('\', '/') } | Sort-Object -Unique)) { $names | Should -Contain $n }
    }

    It 'rejects a bad version' {
        & $pwsh -NoProfile -File $script -Version 'v1' -OutDir (Join-Path $out 'x') 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
    }
}
