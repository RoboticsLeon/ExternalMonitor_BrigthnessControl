# ExternalMonitor_BrigthnessControl
Portable (No Installation Required) Windows Application that create a tray icon for brightness control of external monitors trough CCD/CI commands on PS1 script.

It is targeting corporative environment where not whitelisted executables are forbidden with AppLocker by IT rules.

It is recommended to use it by configuring automatic startup of it during Windows bootup. For this:
1) Windows+R: shell:startup
2) Create shortcut -> Location to the objet field: "C:\Windows\System32\WindowsPowershell\v1.0\powershell.exe -NoProfile -STA -WindowStyle Hidden -File <absolute path to ps1 script>"
