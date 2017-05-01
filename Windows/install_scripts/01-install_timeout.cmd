setlocal EnableDelayedExpansion EnableExtensions

echo ==^> Installing timeout.exe
if not exist "%windir%\system32\timeout.exe" (
   copy %~dp0\inst\timeout.exe %windir%\system32
)

