setlocal EnableDelayedExpansion EnableExtensions

echo ==^> Installing Visual Studio Redistributable Package

%~dp0\inst\vs2015_vcredist_x86.exe /Q
%~dp0\inst\vs2013_vcredist_x86.exe /Q
%~dp0\inst\vs2008_vcredist_x86.exe /Q

if exist "%SystemDrive%\Program Files (x86)" (
    %~dp0\inst\vs2015_vcredist_x64.exe /Q
    %~dp0\inst\vs2013_vcredist_x64.exe /Q
    %~dp0\inst\vs2008_vcredist_x64.exe /Q
)
