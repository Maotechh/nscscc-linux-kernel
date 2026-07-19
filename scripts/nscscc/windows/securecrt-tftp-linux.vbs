#$language = "VBScript"
#$interface = "1.0"

Const LogDirectory = "C:\Users\Henry\fpga-lab\diagnostic\linux\logs"
Const UbootPrompt = "u-boot@LoongsonSoC# "
Const LinuxPrompt = "/ # "
Const KernelFile = "vmlinux-db7abacb8-display-ps2-evdev"
Const KernelSize = "16286576"
Const KernelSha256 = "68498149d0ede8840851804deb642592f04940d76c5d10ee2c0b605c15fca4b3"
Const KernelCrc32 = "d2b95f90"

Function TwoDigits(value)
    TwoDigits = Right("0" & CStr(value), 2)
End Function

Function Timestamp()
    Dim current
    current = Now
    Timestamp = CStr(Year(current)) & TwoDigits(Month(current)) & _
        TwoDigits(Day(current)) & "-" & TwoDigits(Hour(current)) & _
        TwoDigits(Minute(current)) & TwoDigits(Second(current))
End Function

Sub WriteStatus(fileObject, message)
    fileObject.WriteLine Now & " " & message
End Sub

Sub SendSlow(text)
    Dim index
    For index = 1 To Len(text)
        crt.Screen.Send Mid(text, index, 1)
        crt.Sleep 2
    Next
    crt.Screen.Send vbCr
End Sub

Function AcquireUbootPrompt(statusFile, attempts)
    Dim index
    AcquireUbootPrompt = False
    For index = 1 To attempts
        crt.Screen.Send vbCr
        If crt.Screen.WaitForString(UbootPrompt, 1) Then
            WriteStatus statusFile, "uboot_prompt_attempt=" & index
            AcquireUbootPrompt = True
            Exit Function
        End If
    Next
End Function

Function RunUbootCommand(statusFile, command, marker, timeoutSeconds, expectedText)
    Dim output, markerSeen, expectedSeen
    Call SendSlow(command & "; echo " & marker)
    output = crt.Screen.ReadString(UbootPrompt, timeoutSeconds)
    markerSeen = InStr(output, marker) > 0
    expectedSeen = (expectedText = "") Or (InStr(output, expectedText) > 0)
    WriteStatus statusFile, "command=" & command
    WriteStatus statusFile, "output_begin"
    statusFile.WriteLine output
    WriteStatus statusFile, "output_end"
    WriteStatus statusFile, "marker_seen=" & markerSeen
    If expectedText <> "" Then
        WriteStatus statusFile, "expected_seen=" & expectedSeen & " expected=" & expectedText
    End If
    RunUbootCommand = markerSeen And expectedSeen
End Function

Function RunLinuxCommand(statusFile, command, marker, timeoutSeconds, expectedText)
    Dim output, markerSeen, expectedSeen
    crt.Sleep 500
    Call SendSlow(command & "; echo " & marker)
    output = crt.Screen.ReadString(LinuxPrompt, timeoutSeconds)
    markerSeen = InStr(output, marker) > 0
    expectedSeen = (expectedText = "") Or (InStr(output, expectedText) > 0)
    WriteStatus statusFile, "command=" & command
    WriteStatus statusFile, "output_begin"
    statusFile.WriteLine output
    WriteStatus statusFile, "output_end"
    WriteStatus statusFile, "marker_seen=" & markerSeen
    If expectedText <> "" Then
        WriteStatus statusFile, "expected_seen=" & expectedSeen & " expected=" & expectedText
    End If
    RunLinuxCommand = markerSeen And expectedSeen
End Function

Sub Main
    Dim fs, statusFile, stamp, statusPath, serialPath
    Dim gotPrompt, gotBanner, gotShell, ok

    Set fs = CreateObject("Scripting.FileSystemObject")
    stamp = Timestamp()
    statusPath = LogDirectory & "\tftp-linux-net-status-" & stamp & ".txt"
    serialPath = LogDirectory & "\tftp-linux-net-serial-" & stamp & ".txt"
    Set statusFile = fs.CreateTextFile(statusPath, True)

    WriteStatus statusFile, "connected=" & crt.Session.Connected
    WriteStatus statusFile, "kernel_file=" & KernelFile
    WriteStatus statusFile, "kernel_size=" & KernelSize
    WriteStatus statusFile, "kernel_sha256=" & KernelSha256
    WriteStatus statusFile, "kernel_crc32=" & KernelCrc32
    If Not crt.Session.Connected Then
        WriteStatus statusFile, "result=error not_connected"
        statusFile.Close
        crt.Quit
        Exit Sub
    End If

    crt.Screen.Synchronous = True
    crt.Session.LogFileName = serialPath
    crt.Session.Log True

    gotPrompt = AcquireUbootPrompt(statusFile, 180)
    WriteStatus statusFile, "uboot_prompt=" & gotPrompt
    If Not gotPrompt Then
        WriteStatus statusFile, "result=error no_uboot_prompt"
        crt.Session.Log False
        crt.Session.Disconnect
        statusFile.Close
        crt.Quit
        Exit Sub
    End If

    ok = RunUbootCommand(statusFile, "setenv ipaddr 10.90.50.44", "__SET_IP__", 10, "")
    If ok Then ok = RunUbootCommand(statusFile, "setenv serverip 10.90.50.43", "__SET_SERVER__", 10, "")
    If ok Then ok = RunUbootCommand(statusFile, "setenv netmask 255.255.255.0", "__SET_MASK__", 10, "")
    If ok Then ok = RunUbootCommand(statusFile, "setenv ethaddr 00:98:76:64:32:19", "__SET_MAC__", 10, "")
    If ok Then ok = RunUbootCommand(statusFile, "ping 10.90.50.43", "__PING_DONE__", 45, "is alive")
    If ok Then ok = RunUbootCommand(statusFile, "tftpboot 0xa3000000 " & KernelFile, "__TFTP_DONE__", 180, "Bytes transferred = " & KernelSize)
    If ok Then ok = RunUbootCommand(statusFile, "crc32 0xa3000000 ${filesize}", "__CRC_DONE__", 90, KernelCrc32)

    If Not ok Then
        WriteStatus statusFile, "result=error uboot_validation_failed"
        crt.Session.Log False
        crt.Session.Disconnect
        statusFile.Close
        crt.Quit
        Exit Sub
    End If

    Call SendSlow("bootelf -p 0xa3000000 g console=ttyS0,115200 rdinit=/init loglevel=8")
    WriteStatus statusFile, "bootelf_sent=true"
    gotBanner = crt.Screen.WaitForString("NSCSCC LoongArch32 Reduced Linux", 240)
    WriteStatus statusFile, "linux_banner=" & gotBanner
    gotShell = crt.Screen.WaitForString(LinuxPrompt, 30)
    WriteStatus statusFile, "linux_shell=" & gotShell
    If Not gotBanner Or Not gotShell Then
        WriteStatus statusFile, "result=error no_linux_shell"
        crt.Session.Log False
        crt.Session.Disconnect
        statusFile.Close
        crt.Quit
        Exit Sub
    End If

    ok = RunLinuxCommand(statusFile, "set +m", "__DONE_SETM__", 30, "")
    If ok Then ok = RunLinuxCommand(statusFile, "uname -a", "__DONE_UNAME__", 30, "Linux")
    If ok Then ok = RunLinuxCommand(statusFile, "grep -E '^(MemTotal|MemFree|MemAvailable):' /proc/meminfo", "__DONE_MEM__", 30, "MemTotal")
    If ok Then ok = RunLinuxCommand(statusFile, "mount", "__DONE_MOUNT__", 30, "devtmpfs")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /etc/nscscc/build-info", "__DONE_BUILD_INFO__", 30, "db7abacb8820fd0ca5212e2930d74118be7d8a8e")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /sys/class/chiplab_confreg/chiplab_confreg/device_info", "__DONE_CONFREG_INFO__", 30, "Physical base")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /sys/class/chiplab_confreg/chiplab_confreg/all_inputs", "__DONE_CONFREG_INPUTS__", 30, "switches=")
    If ok Then ok = RunLinuxCommand(statusFile, "ip addr show", "__DONE_IP_ADDR__", 30, "10.90.50.44/24")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /sys/class/net/eth0/statistics/rx_packets /sys/class/net/eth0/statistics/tx_packets /sys/class/net/eth0/statistics/rx_errors /sys/class/net/eth0/statistics/tx_errors", "__DONE_IP_LINK__", 30, "")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /sys/class/net/eth0/carrier", "__DONE_CARRIER__", 30, "1")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /proc/interrupts", "__DONE_IRQ_BEFORE__", 30, "timer")
    If ok Then ok = RunLinuxCommand(statusFile, "ping -c 1 -W 2 10.90.50.43", "__DONE_PING_A__", 30, "0% packet loss")
    If ok Then ok = RunLinuxCommand(statusFile, "ping -c 1 -W 2 10.90.50.43", "__DONE_PING_B__", 30, "0% packet loss")
    If ok Then ok = RunLinuxCommand(statusFile, "ping -c 1 -W 2 10.90.50.43", "__DONE_PING_C__", 30, "0% packet loss")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /proc/interrupts", "__DONE_IRQ_AFTER__", 30, "timer")
    If ok Then ok = RunLinuxCommand(statusFile, "nscscc-board read", "__DONE_BOARD_READ__", 30, "switches=")
    If ok Then ok = RunLinuxCommand(statusFile, "nscscc-board led 0x0000a55a", "__DONE_LED__", 30, "")
    If ok Then ok = RunLinuxCommand(statusFile, "nscscc-board display 0x20260719", "__DONE_DISPLAY__", 30, "")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /sys/class/chiplab_confreg/chiplab_confreg/led /sys/class/chiplab_confreg/chiplab_confreg/display", "__DONE_CONFREG_OUTPUTS__", 30, "0x")
    If ok Then ok = RunLinuxCommand(statusFile, "ls -l /dev/nt35510", "__DONE_LCD_DEVICE__", 30, "nt35510")
    If ok Then ok = RunLinuxCommand(statusFile, "dd if=/dev/zero of=/dev/nt35510 bs=768000 count=1", "__DONE_LCD_WRITE__", 60, "")
    If ok Then ok = RunLinuxCommand(statusFile, "dmesg | grep -E 'nt35510|altera_ps2|serio'", "__DONE_INPUT_DEVICES__", 30, "")
    If ok Then ok = RunLinuxCommand(statusFile, "ls -l /dev/input", "__DONE_INPUT_DIR__", 30, "")
    If ok Then ok = RunLinuxCommand(statusFile, "dmesg | tail -100", "__DONE_DMESG__", 90, "ITC MAC")
    If ok Then ok = RunLinuxCommand(statusFile, "sync", "__DONE_SYNC__", 30, "")

    If ok Then
        WriteStatus statusFile, "result=success"
    Else
        WriteStatus statusFile, "result=error linux_command_failed"
    End If
    crt.Session.Log False
    crt.Session.Disconnect
    statusFile.Close
    crt.Quit
End Sub
