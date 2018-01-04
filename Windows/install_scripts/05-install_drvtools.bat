setlocal EnableDelayedExpansion EnableExtensions

echo ==^> Installing misc tools

md c:\s2e
copy %~dp0\inst\devcon.exe c:\s2e\


echo ==^> Installing sysinternals

md c:\sysinternals
7z x -aoa -oc:\sysinternals %~dp0\inst\sysinternals.zip

dir c:\sysinternals