timeout 5

cd c:\s2e

:: ###########################################################################
:: This is used during installation
if exist d:\s2e_startup.bat (
    cmd /c d:\s2e_startup.bat > com1 2>&1
    exit
)

:: ###########################################################################
:: Windows XP has a problem with slow device manager on fresh installs.
:: The first driver load will get stuck for a long time.
:: We don't want that in a ready snapshot, so we wait before saving it.
ver | find "5.1" > nul

if not %ERRORLEVEL% == 0 goto notxp

:: Get the device manager unstuck by disabling/enabling the pcnet nic
devcon disable *"PCI\VEN_1022&DEV_2000"
devcon enable *"PCI\VEN_1022&DEV_2000"

:: services.exe eats up 100% cpu for several minutes.
devcon disable *"PCI\VEN_1022&DEV_2000"

:: Wait for services.exe to calm down
timeout 600
:notxp


:: ###########################################################################
:: Save the ready snapshot

set SECRET_MESSAGE_KILL="?!?MAGIC?!?k 0 "
set SECRET_MESSAGE_SAVEVM="?!?MAGIC?!?s ready "

echo %SECRET_MESSAGE_SAVEVM% > com1 2>&1

:: ###########################################################################
:: This is where we should be after resuming the snapshot

s2eget bootstrap.sh

:: Need to use call, otherwise msys.bat would just close the terminal
call c:\msys\1.0\msys.bat /c/s2e/bootstrap.sh > com1 2>&1

s2ecmd kill 0 "Bootstrap script terminated"
