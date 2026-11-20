@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0support\install-portable-git.ps1" -PackageRoot "%~dp0."
exit /b %errorlevel%
