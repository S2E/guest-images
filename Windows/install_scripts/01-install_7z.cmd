setlocal EnableDelayedExpansion EnableExtensions

echo ==^> Installing 7z.exe
copy %~dp0\inst\7z.exe %windir%
copy %~dp0\inst\7z.dll %windir%
