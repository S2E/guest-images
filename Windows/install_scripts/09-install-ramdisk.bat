setlocal EnableDelayedExpansion EnableExtensions

echo ==^> Installing ImDisk
rem This must be the last step of the installation as ImDisk installer forces reboot

if exist "%SystemDrive%\Program Files (x86)" (
    %~dp0\inst\ImDiskTk-x64.exe /fullsilent
) else (
    %~dp0\inst\ImDiskTk.exe /fullsilent
)
