# Backup manifest, PowerShell profile editing and the elevated cleanup. Files only; no Windows needed.
BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
    . (Join-Path $root 'LinuxifyTerminal.ps1')
    . (Join-Path $root 'LinuxifyBackup.ps1')
    $script:latin1 = [System.Text.Encoding]::GetEncoding(28591)
}

Describe 'Get-LxFileEncoding' {
    BeforeEach { $script:sb = New-LxSandbox }
    AfterEach { Remove-Item $sb -Recurse -Force -ErrorAction SilentlyContinue }
    It 'recognises BOM, BOM-less UTF-8, ASCII and ANSI' {
        $f = Join-Path $sb 'a.txt'
        [IO.File]::WriteAllText($f, 'x', (New-Object System.Text.UTF8Encoding($true)));  (Get-LxFileEncoding $f).GetPreamble().Length | Should -Be 3
        [IO.File]::WriteAllText($f, ('caf' + [char]0xE9), (New-Object System.Text.UTF8Encoding($false)))
        (Get-LxFileEncoding $f).WebName | Should -Be 'utf-8'
        [IO.File]::WriteAllText($f, 'plain ascii', $latin1);  (Get-LxFileEncoding $f).WebName | Should -Be 'utf-8'
        [IO.File]::WriteAllBytes($f, [byte[]](0x63, 0x61, 0x66, 0xE9))   # "cafe" with an ANSI e-acute: invalid as UTF-8
        (Get-LxFileEncoding $f).WebName | Should -Not -Be 'utf-8'
        (Read-LxTextFile $f).Text | Should -Be ('caf' + [char]0xE9)
    }
}

Describe 'profile hook' {
    BeforeEach { $script:sb = New-LxSandbox; $script:prof = Join-Path $sb 'profile.ps1' }
    AfterEach { Remove-Item $sb -Recurse -Force -ErrorAction SilentlyContinue }

    It 'creates a missing profile, and removing the hook leaves it empty' {
        Add-LxProfileHook $prof
        Test-LxProfileHook $prof | Should -BeTrue
        Remove-LxProfileHook -Path $prof | Should -BeTrue
        Test-LxProfileHook $prof | Should -BeFalse
    }

    It 'appends to a UTF-8 profile with a BOM without changing its encoding or text' {
        $enc = New-Object System.Text.UTF8Encoding($true)
        [IO.File]::WriteAllText($prof, ("# caf" + [char]0xE9 + " " + [char]0x65E5 + "`r`nSet-Alias ll Get-ChildItem`r`n"), $enc)
        Add-LxProfileHook $prof
        $bytes = [IO.File]::ReadAllBytes($prof)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        $text = [IO.File]::ReadAllText($prof, $enc)
        $text | Should -Match ('caf' + [char]0xE9 + ' ' + [char]0x65E5)
        $text | Should -Match 'Set-Alias ll'
        $text | Should -Match 'Linuxify\\shell\\init\.ps1'
    }

    It 'keeps an ANSI profile in ANSI byte for byte (Add-Content/Set-Content would have rewritten it)' {
        $orig = $latin1.GetBytes("# caf" + [char]0xE9 + "`r`nfunction x { 1 }`r`n")
        [IO.File]::WriteAllBytes($prof, $orig)
        Add-LxProfileHook $prof
        $after = [IO.File]::ReadAllBytes($prof)
        $after[0..($orig.Length - 1)] | Should -Be $orig
        Remove-LxProfileHook -Path $prof | Should -BeFalse
        [IO.File]::ReadAllBytes($prof) | Should -Be $orig
    }

    It 'removes only Linuxify lines: a user starship line and other mentions of Linuxify stay' {
        $user = "Invoke-Expression (&starship init powershell)`r`n# I love Linuxify`r`n`$x = 'Linuxify'`r`n"
        [IO.File]::WriteAllText($prof, $user, (New-Object System.Text.UTF8Encoding($false)))
        Add-LxProfileHook $prof
        Remove-LxProfileHook -Path $prof | Should -BeFalse
        [IO.File]::ReadAllText($prof) | Should -Be $user
    }

    It 'keeps LF line endings and the lines around the hook' {
        [IO.File]::WriteAllText($prof, "a`nb`n", (New-Object System.Text.UTF8Encoding($false)))
        Add-LxProfileHook $prof
        Remove-LxProfileHook -Path $prof | Out-Null
        [IO.File]::ReadAllText($prof) | Should -Be "a`nb`n"
    }

    It 'is not added twice by Test-LxProfileHook gating, and a legacy hook is recognised' {
        [IO.File]::WriteAllText($prof, "`r`n# linuxify`r`n`$__li = Join-Path `$env:LOCALAPPDATA 'Linuxify\shell\init.ps1'; if (Test-Path `$__li) { . `$__li }`r`n")
        Test-LxProfileHook $prof | Should -BeTrue
    }
}

Describe 'backup manifest' {
    BeforeEach {
        $script:sb = New-LxSandbox
        $script:data = Join-Path $sb 'Linuxify'; New-Item -ItemType Directory -Force $data | Out-Null
        $script:manifest = Join-Path $data 'backups.txt'
    }
    AfterEach { Remove-Item $sb -Recurse -Force -ErrorAction SilentlyContinue }

    It 'records a file that did not exist as @absent, once' {
        $target = Join-Path $sb 'cfg.yaml'
        Backup-LxPath -Path $target -DataDir $data -Stamp 's1'
        Set-Content $target 'ours'                       # Linuxify then writes it
        Backup-LxPath -Path $target -DataDir $data -Stamp 's2'   # second install
        @(Get-LxManifestEntries $manifest).Count | Should -Be 1
        (Get-LxManifestEntries $manifest)[0].Backup | Should -Be '@absent'
        Test-Path (Join-Path $data 'backup\install-s2') | Should -BeFalse
    }

    It 'backs up the user original once and never backs up Linuxify output afterwards' {
        $target = Join-Path $sb 'cfg.yaml'
        Set-Content $target 'user original'
        Backup-LxPath -Path $target -DataDir $data -Stamp 's1'
        Set-Content $target 'linuxify v1'
        Backup-LxPath -Path $target -DataDir $data -Stamp 's2'
        Set-Content $target 'linuxify v2'
        Backup-LxPath -Path $target -DataDir $data -Stamp 's3'
        $e = @(Get-LxManifestEntries $manifest)
        $e.Count | Should -Be 1
        (Get-Content $e[0].Backup -Raw).Trim() | Should -Be 'user original'
        @(Get-ChildItem (Join-Path $data 'backup') -Directory).Count | Should -Be 1
    }

    It 'skips a file that already equals what is about to be written' {
        $target = Join-Path $sb 'cfg.yaml'; $new = Join-Path $sb 'new.yaml'
        Set-Content $target 'same'; Set-Content $new 'same'
        Backup-LxPath -Path $target -DataDir $data -Stamp 's1' -Replacement $new
        Test-Path $manifest | Should -BeFalse
    }

    It 'reads old manifests: first line per path wins, duplicates and blank lines ignored' {
        [IO.File]::WriteAllText($manifest, "C:\a|C:\b1`r`nC:\a|C:\b2`r`n`r`nC:\c|C:\d`r`n")
        $e = @(Get-LxManifestEntries $manifest)
        $e.Count | Should -Be 2
        $e[0].Backup | Should -Be 'C:\b1'
    }

    It 'keeps non-ASCII paths in the manifest readable' {
        $p = 'C:\Users\Jo' + [char]0xE3 + 'o\.glzr\x.yaml'
        Add-LxManifest $manifest $p 'C:\bk'
        Add-LxManifest $manifest 'C:\other' 'C:\bk2'
        (Get-LxManifestEntries $manifest)[0].Path | Should -Be $p
        Test-LxManifestHas $manifest $p | Should -BeTrue
    }
}

Describe 'elevated cleanup of the all-users profile' {
    BeforeEach { $script:sb = New-LxSandbox; $script:gp = Join-Path $sb 'profile.ps1' }
    AfterEach { Remove-Item $sb -Recurse -Force -ErrorAction SilentlyContinue }

    It 'the generated command removes the hook and nothing else' {
        $keep = "# machine wide`r`n`$env:FOO = 'a''b'`r`n# note about Linuxify`r`n"
        [IO.File]::WriteAllText($gp, $keep)
        Add-LxProfileHook $gp
        $cmd = New-LxProfileCleanupCommand -Path $gp
        $pwsh = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        & $pwsh -NoProfile -EncodedCommand ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))) | Out-Null
        [IO.File]::ReadAllText($gp) | Should -Be $keep
    }

    It 'passes the cleanup as -EncodedCommand and never writes a script file' {
        $before = @(Get-ChildItem ([IO.Path]::GetTempPath()) -Filter '*.ps1' -ErrorAction SilentlyContinue).Count
        $script:captured = $null
        function global:Start-Process { $script:captured = $args }
        try { Invoke-LxElevatedProfileCleanup -Path $gp } finally { Remove-Item function:global:Start-Process }
        $flat = @($captured | ForEach-Object { $_ })
        $flat | Should -Contain '-EncodedCommand'
        $flat | Should -Not -Contain '-File'
        $flat | Should -Contain 'RunAs'
        @(Get-ChildItem ([IO.Path]::GetTempPath()) -Filter '*.ps1' -ErrorAction SilentlyContinue).Count | Should -Be $before
    }

    It 'uninstall.ps1 no longer writes linuxify-gp.ps1 or matches every line containing "Linuxify"' {
        $src = [IO.File]::ReadAllText((Join-Path $root 'uninstall.ps1'))
        $src | Should -Not -Match 'linuxify-gp'
        $src | Should -Not -Match "notmatch 'Linuxify"
        $src | Should -Not -Match 'starship init powershell'
    }
}

Describe 'uninstall -RemoveApps' {
    It 'removes exactly what install.ps1 installs' {
        $inst = [IO.File]::ReadAllText((Join-Path $root 'install.ps1'))
        $installed = @([regex]::Matches($inst, "'([A-Za-z0-9-]+\.[A-Za-z0-9.-]+)'\s*=\s*'") | ForEach-Object { $_.Groups[1].Value })
        $installed += [regex]::Match($inst, '--id (DEVCOM\.[A-Za-z0-9.]+)').Groups[1].Value
        $un = [IO.File]::ReadAllText((Join-Path $root 'uninstall.ps1'))
        $line = ($un -split "`n" | Where-Object { $_ -match "foreach \(\`$id in '" } | Select-Object -First 1)
        $removed = @([regex]::Matches($line, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        $installed.Count | Should -Be 6
        ($removed | Sort-Object) | Should -Be ($installed | Sort-Object)
        $removed | Should -Not -Contain 'CharlesMilette.TranslucentTB'
        $removed | Should -Not -Contain 'Flow-Launcher.Flow-Launcher'
    }
}
