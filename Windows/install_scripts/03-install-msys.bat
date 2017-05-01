setlocal EnableDelayedExpansion EnableExtensions

echo ==^> Installing Msys

7z x -oc:\ %~dp0\inst\msys.7z

dir c:\
