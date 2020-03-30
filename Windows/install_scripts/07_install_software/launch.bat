setlocal EnableDelayedExpansion EnableExtensions

echo ==^> Setting resolution
resolution.exe 1024 768 24 0

echo ==^> Installing 7z.exe
copy d:\7z.exe %windir%
copy d:\7z.dll %windir%

echo ==^> Installing Msys
7z x -oc:\ d:\msys.7z

echo ==^> Installing Python 2.7.13
if exist "%SystemDrive%\Program Files (x86)" (
    msiexec /i d:\python-2.7.13.amd64.msi /qn /norestart
) else (
    msiexec /i d:\python-2.7.13.msi /qn /norestart
)

echo ==^> Installing s2e tools
copy e:\*.exe c:\s2e\
copy e:\*.sys c:\s2e\
copy e:\*.inf c:\s2e\

echo ==^> Installing misc tools
copy d:\devcon.exe c:\s2e\

echo ==^> Installing sysinternals
md c:\sysinternals
7z x -aoa -oc:\sysinternals d:\sysinternals.zip
dir c:\sysinternals

echo ==^> Installing Visual Studio Redistributable Package

d:\vs2015_vcredist_x86.exe /Q /norestart
d:\vs2013_vcredist_x86.exe /Q /norestart
d:\vs2008_vcredist_x86.exe /Q /norestart

if exist "%SystemDrive%\Program Files (x86)" (
    d:\vs2015_vcredist_x64.exe /Q /norestart
    d:\vs2013_vcredist_x64.exe /Q /norestart
    d:\vs2008_vcredist_x64.exe /Q /norestart
)

echo ==^> Installing ImDisk
:: This must be the last step of the installation as ImDisk installer forces reboot

if exist "%SystemDrive%\Program Files (x86)" (
    d:\ImDiskTk-x64.exe /fullsilent
) else (
    d:\ImDiskTk.exe /fullsilent
)

shutdown /r /t 0
