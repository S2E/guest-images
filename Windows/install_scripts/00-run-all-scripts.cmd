@echo on
setlocal EnableDelayedExpansion EnableExtensions

PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\WindowsPowerShell\v1.0;%PATH%;%~dp0

set CMD_OPTS=/Q

cd /d %~dp0

echo.|time|findstr "current" > com1
echo %0: started. > com1
title Running %0, please wait...

dir /b /on %~dp0\*.bat %~dp0\*.cmd | findstr /v "^_" | findstr /i /v %~nx0 >"%TEMP%\runlist.txt"

type "%TEMP%\runlist.txt" > com1

for /F %%i in (%TEMP%\runlist.txt) do (
  echo.|time|findstr "current" > com1
  echo %0: executing %%~i > com1

  title Executing %%~i...
  cmd %CMD_OPTS% /c "%%~nxi" > com1 2>&1
  echo %0 %%~i returned errorlevel %ERRORLEVEL% > com1
)

del "%TEMP%\runlist.txt"

echo.|time|findstr "current" > com1
echo %0: finished. > com1
