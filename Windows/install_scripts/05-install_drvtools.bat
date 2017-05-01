setlocal EnableDelayedExpansion EnableExtensions

echo ==^> Installing S2E guest tools

md c:\s2e
copy %~dp0\inst\devcon.exe c:\s2e\
