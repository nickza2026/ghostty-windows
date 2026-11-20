@echo off
setlocal
if /i "%~1"=="--version" goto version
if /i "%~1"=="--install-only" goto install
if not "%~1"=="" goto usage
if exist "%~dp0bin\portable-data\shims\git.exe" if exist "%~dp0bin\portable-data\runtimes\git\cmd\git.exe" if exist "%~dp0bin\portable-data\runtimes\git\usr\bin\bash.exe" goto git_ready
call "%~dp0Install-Portable-Git.cmd"
if errorlevel 1 exit /b 1
:git_ready
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0support\herdr-portable.ps1" -PackageRoot "%~dp0."
set "herdr_exit=%errorlevel%"
if not "%herdr_exit%"=="0" pause
exit /b %herdr_exit%
:version
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0support\herdr-portable.ps1" -PackageRoot "%~dp0." -VersionOnly
exit /b %errorlevel%
:install
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0support\herdr-portable.ps1" -PackageRoot "%~dp0." -InstallOnly
exit /b %errorlevel%
:usage
echo Usage: Run-Herdr.cmd [--version ^| --install-only]
exit /b 2
