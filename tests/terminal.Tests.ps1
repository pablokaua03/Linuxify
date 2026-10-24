# Windows Terminal handling: the Linux look is merged into the user's current settings, never copied over them.
BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
    . (Join-Path $root 'LinuxifyTerminal.ps1')
    $script:utf8 = New-Object System.Text.UTF8Encoding($false)
    function script:Write-Wt([string]$Path, [string]$Json) { [IO.File]::WriteAllText($Path, $Json, $script:utf8) }
}

Describe 'Build-LxTerminalVariant' {
    BeforeEach { $script:sb = New-LxSandbox }
    AfterEach { Remove-Item $script:sb -Recurse -Force -ErrorAction SilentlyContinue }

    It 'keeps profiles, actions and unknown keys, and adds the scheme and defaults' {
        $from = Join-Path $sb 'in.json'; $to = Join-Path $sb 'out.json'
        Write-Wt $from '{"theme":"light","actions":[{"command":"copy","keys":"ctrl+c"}],"profiles":{"defaults":{"fontFace":"Mine","cursorShape":"bar"},"list":[{"name":"PS"},{"name":"Ubuntu"}]},"schemes":[{"name":"Mine"}],"somethingNew":{"a":1}}'
        Build-LxTerminalVariant -From $from -To $to -OverlayDir (Join-Path $root 'configs\terminal')
        $o = [IO.File]::ReadAllText($to) | ConvertFrom-Json
        $o.actions[0].keys | Should -Be 'ctrl+c'
        @($o.profiles.list).name | Should -Be @('PS', 'Ubuntu')
        $o.somethingNew.a | Should -Be 1
        $o.profiles.defaults.cursorShape | Should -Be 'bar'      # not in the overlay: kept
        @($o.schemes).name | Should -Contain 'Mine'
        @($o.schemes).name | Should -Contain 'Catppuccin Mocha'
        $o.profiles.defaults.colorScheme | Should -Be 'Catppuccin Mocha'
    }

    It 'does not duplicate the scheme when built twice' {
        $from = Join-Path $sb 'in.json'; $to = Join-Path $sb 'out.json'; $to2 = Join-Path $sb 'out2.json'
        Write-Wt $from '{"profiles":{"list":[]}}'
        Build-LxTerminalVariant -From $from -To $to -OverlayDir (Join-Path $root 'configs\terminal')
        Build-LxTerminalVariant -From $to -To $to2 -OverlayDir (Join-Path $root 'configs\terminal')
        @(([IO.File]::ReadAllText($to2) | ConvertFrom-Json).schemes | Where-Object name -eq 'Catppuccin Mocha').Count | Should -Be 1
    }

    It 'keeps non-ASCII text from a BOM-less UTF-8 file intact' {
        $from = Join-Path $sb 'in.json'; $to = Join-Path $sb 'out.json'
        Write-Wt $from ('{"profiles":{"list":[{"name":"Caf' + [char]0xE9 + ' ' + [char]0x65E5 + [char]0x672C + '"}]}}')
        Build-LxTerminalVariant -From $from -To $to -OverlayDir (Join-Path $root 'configs\terminal')
        $name = @(([IO.File]::ReadAllText($to) | ConvertFrom-Json).profiles.list)[0].name
        $name | Should -Be ('Caf' + [char]0xE9 + ' ' + [char]0x65E5 + [char]0x672C)
        [IO.File]::ReadAllBytes($to)[0] | Should -Not -Be 0xEF    # no BOM, like Windows Terminal writes it
    }

    It 'reads a file that does have a BOM' {
        $from = Join-Path $sb 'in.json'; $to = Join-Path $sb 'out.json'
        [IO.File]::WriteAllText($from, '{"profiles":{"list":[{"name":"X"}]}}', (New-Object System.Text.UTF8Encoding($true)))
        { Build-LxTerminalVariant -From $from -To $to -OverlayDir (Join-Path $root 'configs\terminal') } | Should -Not -Throw
    }

    It 'does not mistake // inside a string (a URL) for a comment' {
        Test-LxJsonHasComments '{"commandline":"ssh https://example.test/x","a":"say \"//\" please"}' | Should -BeFalse
        Test-LxJsonHasComments "{ `"a`": 1 } // note" | Should -BeTrue
        Test-LxJsonHasComments "{ /* note */ `"a`": 1 }" | Should -BeTrue
    }

    It 'throws on settings it cannot parse (comments) instead of writing a half result' {
        $from = Join-Path $sb 'in.json'; $to = Join-Path $sb 'out.json'
        Write-Wt $from "{ // my notes`n `"profiles`":{`"list`":[]} }"
        { Build-LxTerminalVariant -From $from -To $to -OverlayDir (Join-Path $root 'configs\terminal') } | Should -Throw
        Test-Path $to | Should -BeFalse
    }
}

Describe 'Linux mode on and off' {
    BeforeAll {
        # Registry, process and service cmdlets are stubbed; the real Enable-Linux / Disable-Linux run on files only.
        function global:Set-ItemProperty { }
        function global:Remove-ItemProperty { }
        function global:Start-Process { }
        function global:Stop-Process { }
        function global:Get-Service { $null }
        function global:Get-Process { $null }
        Import-LxFunction -Script (Join-Path $root 'Linuxify.ps1') -Name 'Get-LinuxState', 'Find-Exe', 'Set-Windhawk', 'Start-Zebar', 'Set-LxTerminalLinux', 'Enable-Linux', 'Disable-Linux', 'Write-LxStartup'
    }
    BeforeEach {
        $script:sb = New-LxSandbox
        $script:prevPF = $env:ProgramFiles; $script:prevLA = $env:LOCALAPPDATA
        $env:ProgramFiles = $sb; $env:LOCALAPPDATA = $sb
        $global:Data = Join-Path $sb 'Linuxify'; New-Item -ItemType Directory -Force $Data | Out-Null
        $global:State = Join-Path $Data 'state.txt'
        $global:WtSet = Join-Path $sb 'settings.json'
        $global:Run = 'HKCU:\fake'
        $global:Apps = @(@{ Key = 'Linuxify.GlazeWM'; Proc = 'glazewm'; Exe = (Join-Path $sb 'nope\glazewm.exe') })
        New-Item -ItemType Directory -Force (Join-Path $Data 'configs') | Out-Null
        Copy-Item (Join-Path $root 'configs\terminal') (Join-Path $Data 'configs\terminal') -Recurse
        Write-Wt $WtSet '{"theme":"dark","profiles":{"list":[{"name":"PS"}]}}'
        # what install.ps1 leaves behind
        Copy-Item $WtSet (Join-Path $Data 'wt.settings.original.json')
        Build-LxTerminalVariant -From $WtSet -To (Join-Path $Data 'wt.settings.linux.json') -OverlayDir (Join-Path $Data 'configs\terminal')
    }
    AfterEach {
        $env:ProgramFiles = $script:prevPF; $env:LOCALAPPDATA = $script:prevLA
        Remove-Item $sb -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'keeps a profile added after install when turning Linux mode on' {
        Write-Wt $WtSet '{"theme":"dark","font":{"size":16},"profiles":{"list":[{"name":"PS"},{"name":"MY-NEW-PROFILE"}]}}'
        Set-Content $State 'off'
        Enable-Linux
        $o = [IO.File]::ReadAllText($WtSet) | ConvertFrom-Json
        @($o.profiles.list).name | Should -Contain 'MY-NEW-PROFILE'
        $o.font.size | Should -Be 16
        $o.profiles.defaults.colorScheme | Should -Be 'Catppuccin Mocha'
        (Get-Content $State -Raw).Trim() | Should -Be 'on'
    }

    It 'puts the settings from before Linux mode back, and keeps what was edited while it was on' {
        Write-Wt $WtSet '{"theme":"dark","profiles":{"list":[{"name":"PS"},{"name":"BEFORE"}]}}'
        Set-Content $State 'off'
        Enable-Linux
        $on = [IO.File]::ReadAllText($WtSet) | ConvertFrom-Json
        $on.profiles.list += [pscustomobject]@{ name = 'WHILE-ON' }
        Write-Wt $WtSet ($on | ConvertTo-Json -Depth 32)
        Disable-Linux
        $off = [IO.File]::ReadAllText($WtSet) | ConvertFrom-Json
        @($off.profiles.list).name | Should -Be @('PS', 'BEFORE')
        $off.profiles.PSObject.Properties['defaults'] | Should -BeNullOrEmpty
        $saved = Get-ChildItem (Join-Path $Data 'backup') -Filter 'wt-while-on-*.json'
        $saved.Count | Should -Be 1
        [IO.File]::ReadAllText($saved[0].FullName) | Should -Match 'WHILE-ON'
        (Get-Content $State -Raw).Trim() | Should -Be 'off'
    }

    It 'saves nothing extra when the settings were not touched while on' {
        Set-Content $State 'off'
        Enable-Linux
        Disable-Linux
        Test-Path (Join-Path $Data 'backup') | Should -BeFalse
    }

    It 'does not snapshot the Linux look as the original when Enable runs while already on' {
        Set-Content $State 'off'
        Enable-Linux
        $snap = [IO.File]::ReadAllText((Join-Path $Data 'wt.settings.original.json'))
        Enable-Linux
        [IO.File]::ReadAllText((Join-Path $Data 'wt.settings.original.json')) | Should -Be $snap
        $snap | Should -Not -Match 'Catppuccin'
    }

    It 'leaves Windows Terminal alone when its settings cannot be parsed' {
        $text = "{ // keep me`n `"profiles`":{`"list`":[{`"name`":`"PS`"}]} }"
        Write-Wt $WtSet $text
        Set-Content $State 'off'
        Enable-Linux
        [IO.File]::ReadAllText($WtSet) | Should -Be $text
        (Get-Content $State -Raw).Trim() | Should -Be 'on'
        [IO.File]::ReadAllText((Join-Path $Data 'startup.log')) | Should -Match 'theme not applied'
    }

    It 'backs up at most five copies of edits made while on' {
        $bd = Join-Path $Data 'backup'
        New-Item -ItemType Directory -Force $bd | Out-Null
        1..8 | ForEach-Object {
            Write-Wt $WtSet ('{"n":' + $_ + '}')
            Backup-LxTerminalEdits -WtSettings $WtSet -LinuxVariant (Join-Path $Data 'wt.settings.linux.json') -BackupDir $bd | Out-Null
            Start-Sleep -Milliseconds 5
        }
        @(Get-ChildItem $bd -Filter 'wt-while-on-*.json').Count | Should -Be 5
    }
}
