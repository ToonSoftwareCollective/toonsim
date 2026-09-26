# Starts the simulator hidden for a few seconds and prints the distinct problems it reports -
# the loop for bringing up the stand-in modules one error at a time. Reads the process's own error
# output, so a failure before the log file is opened is not missed.
param([int]$Seconds = 12, [int]$Max = 40, [string[]]$Extra = @(), [switch]$All)
$root = Split-Path -Parent $PSScriptRoot
$qt = "$env:USERPROFILE\Qt\5.15.2\mingw81_64"
$env:PATH = "$qt\bin;$env:USERPROFILE\Qt\Tools\mingw810_64\bin;$env:PATH"
$env:QT_PLUGIN_PATH = "$qt\plugins"
$env:QML2_IMPORT_PATH = "$qt\qml"
Get-Process toonsim -ErrorAction SilentlyContinue | Stop-Process -Force
$err = Join-Path $env:TEMP "toonsim_run.txt"
$args_ = @("--hidden", "--control-port", "0") + $Extra
$p = Start-Process "$root\bin\toonsim.exe" -ArgumentList $args_ -PassThru -NoNewWindow -RedirectStandardError $err
$null = $p.WaitForExit($Seconds * 1000)
$state = if ($p.HasExited) { "exited with $($p.ExitCode)" } else { "running after $Seconds s" }
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; Start-Sleep -Milliseconds 300 }
$lines = Get-Content $err
"$state; $($lines.Count) lines of output"
$seen = @{}
$pattern = if ($All) { '.' } else { 'warning|critical|error|not installed|is not a type|Cannot|failed|undefined|not defined|unhandled|not found' }
$lines | Where-Object { $_ -match $pattern -and $_ -notmatch 'Implicitly defined onFoo' } | ForEach-Object {
  $msg = ($_ -replace '^\S+ \S+ ', '')
  if (-not $seen.ContainsKey($msg)) { $seen[$msg] = 1; $msg }
} | Select-Object -First $Max | ForEach-Object { $_.Substring(0, [Math]::Min(260, $_.Length)) }
