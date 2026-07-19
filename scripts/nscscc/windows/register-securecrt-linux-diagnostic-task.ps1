$ErrorActionPreference = "Stop"
$root = "C:\Users\Henry\fpga-lab\diagnostic\linux"
$secureCrt = "$root\tools\securecrt\SecureCRTPortable\App\SecureCRT\SecureCRT.exe"
$arguments = @(
    "/SCRIPT", "`"$root\securecrt-linux-diagnostic.vbs`"",
    "/SERIAL", "COM4",
    "/BAUD", "115200",
    "/DATA", "8",
    "/PARITY", "NONE",
    "/STOP", "0",
    "/NOCTS", "/NODSR", "/NOXON"
) -join " "
$action = New-ScheduledTaskAction `
    -Execute $secureCrt `
    -Argument $arguments `
    -WorkingDirectory (Split-Path -Parent $secureCrt)
$principal = New-ScheduledTaskPrincipal `
    -UserId "HENRYWIN\henry" `
    -LogonType Interactive `
    -RunLevel Highest
Register-ScheduledTask `
    -TaskName "NSCSCC-Linux-Diagnostic" `
    -Action $action `
    -Principal $principal `
    -Force | Out-Null
Start-ScheduledTask -TaskName "NSCSCC-Linux-Diagnostic"
