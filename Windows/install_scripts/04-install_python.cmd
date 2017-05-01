setlocal EnableDelayedExpansion EnableExtensions

echo ==^> Installing Python 2.7.13

if exist "%SystemDrive%\Program Files (x86)" (
    msiexec /i %~dp0\inst\python-2.7.13.amd64.msi /qn /norestart
) else (
    msiexec /i %~dp0\inst\python-2.7.13.msi /qn /norestart
)


