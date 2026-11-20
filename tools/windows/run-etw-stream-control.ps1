$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$prepared=@(& (Join-Path $PSScriptRoot 'prepare-etw-stream.ps1') -Mode control)
$paths=@($prepared|Where-Object{$_ -is [string] -and $_.StartsWith('STREAM_PREPARED=')})
if($paths.Count -ne 1){throw 'No unique prepared stream control'}
$root=$paths[0].Substring('STREAM_PREPARED='.Length)
Set-Content (Join-Path $repo 'zig-out/etw-stream-control-current.txt') $root -Encoding UTF8
$supervisor=Join-Path $root 'etw-stream-supervise.ps1';$config=Join-Path $root 'config.json'
$p=Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-File',('"'+$supervisor+'"'),'-Config',('"'+$config+'"')) -Verb RunAs -WindowStyle Hidden -PassThru
$null=$p.Handle
if(-not $p.WaitForExit(45000)){throw 'Streaming control supervisor did not complete'}
$p.Dispose()
$s=Get-Content (Join-Path $root 'supervisor.json') -Raw|ConvertFrom-Json
if($s.timeout -or $s.cleanup_exit -ne 0 -or -not $s.root_exit_confirmed -or $s.exit -ne 0){$s|ConvertTo-Json -Compress;throw 'Streaming control/cleanup failed; no terminal'}
if(@(Get-ChildItem $root -File -Filter '*.etl').Count){throw 'Unexpected raw ETL; no terminal'}
Write-Output ('ETW_STREAM_CONTROL_PRIVATE='+$root)
& (Join-Path $PSScriptRoot 'qualify-etw-handle-control.ps1') -Root $root -DecodedLeaf 'decoded.jsonl'
if($LASTEXITCODE){throw 'Streaming caller qualification failed; no terminal'}
