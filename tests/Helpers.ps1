# Shared by the Pester tests. Loads single functions out of the kit's scripts without running the
# scripts themselves (they start a tray, touch the registry, ...), so the tests need no Windows shell.
function Import-LxFunction {
    param([Parameter(Mandatory)][string]$Script, [Parameter(Mandatory)][string[]]$Name)
    $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$null, [ref]$errs)
    if ($errs) { throw ($errs | ForEach-Object { $_.ToString() } | Out-String) }
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($n in $Name) {
        $fn = $defs | Where-Object { $_.Name -eq $n } | Select-Object -First 1
        if (-not $fn) { throw "function $n not found in $Script" }
        # define it in the caller's scope
        $sb = [scriptblock]::Create("function global:$n " + $fn.Extent.Text.Substring($fn.Extent.Text.IndexOf($n) + $n.Length))
        . $sb
    }
}

function New-LxSandbox {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('lx-test-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $tmp
}
