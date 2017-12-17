setlocal EnableDelayedExpansion EnableExtensions

echo ==^> Installing .net

:: Windows XP does not support versions above 4.0
ver | find "5.1" > nul
if not %ERRORLEVEL% == 0 goto notxp
echo Installing .net 4.0
%~dp0\inst\dotNetFx40_Full_x86_x64.exe /Q /norestart
goto end

:notxp
echo Installing .net 4.5
%~dp0\inst\dotNetFx45_Full_x86_x64.exe /Q /norestart

:end
