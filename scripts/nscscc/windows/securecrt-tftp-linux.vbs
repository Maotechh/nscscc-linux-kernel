#$language = "VBScript"
#$interface = "1.0"

Const LogDirectory = "C:\Users\Henry\fpga-lab\diagnostic\linux\logs"
Const ManifestPath = "C:\Users\Henry\fpga-lab\diagnostic\linux\manifests\current-linux.manifest"
Const UbootPrompt = "u-boot@LoongsonSoC# "
Const LinuxPrompt = "/ # "

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

Function LoadManifest(fs, path)
    Dim values, input, line, separator, key, value
    Set values = CreateObject("Scripting.Dictionary")
    values.CompareMode = 1
    If Not fs.FileExists(path) Then
        Set LoadManifest = Nothing
        Exit Function
    End If

    Set input = fs.OpenTextFile(path, 1, False)
    Do Until input.AtEndOfStream
        line = Trim(input.ReadLine)
        separator = InStr(line, "=")
        If separator > 1 Then
            key = Trim(Left(line, separator - 1))
            value = Trim(Mid(line, separator + 1))
            values(key) = value
        End If
    Loop
    input.Close
    Set LoadManifest = values
End Function

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
    Dim output, markerSeen, expectedSeen, successSeen
    crt.Sleep 500
    Call SendSlow(command & "; rc=$?; echo " & marker & " rc=$rc")
    output = crt.Screen.ReadString(LinuxPrompt, timeoutSeconds)
    markerSeen = InStr(output, marker) > 0
    expectedSeen = (expectedText = "") Or (InStr(output, expectedText) > 0)
    successSeen = InStr(output, marker & " rc=0") > 0
    WriteStatus statusFile, "command=" & command
    WriteStatus statusFile, "output_begin"
    statusFile.WriteLine output
    WriteStatus statusFile, "output_end"
    WriteStatus statusFile, "marker_seen=" & markerSeen
    If expectedText <> "" Then
        WriteStatus statusFile, "expected_seen=" & expectedSeen & " expected=" & expectedText
    End If
    WriteStatus statusFile, "command_success=" & successSeen
    RunLinuxCommand = markerSeen And expectedSeen And successSeen
End Function

Sub Main
    Dim fs, statusFile, stamp, statusPath, serialPath
    Dim manifest, requiredKeys, key
    Dim KernelFile, KernelSize, KernelSha256, KernelCrc32, KernelCommit
    Dim gotPrompt, gotBanner, gotIssue, gotShell, ok

    Set fs = CreateObject("Scripting.FileSystemObject")
    stamp = Timestamp()
    statusPath = LogDirectory & "\tftp-linux-net-status-" & stamp & ".txt"
    serialPath = LogDirectory & "\tftp-linux-net-serial-" & stamp & ".txt"
    Set statusFile = fs.CreateTextFile(statusPath, True)

    Set manifest = LoadManifest(fs, ManifestPath)
    If manifest Is Nothing Then
        WriteStatus statusFile, "result=error manifest_not_found path=" & ManifestPath
        statusFile.Close
        crt.Quit
        Exit Sub
    End If

    requiredKeys = Array("artifact", "size", "sha256", "crc32", "kernel_commit")
    For Each key In requiredKeys
        If Not manifest.Exists(key) Then
            WriteStatus statusFile, "result=error manifest_key_missing key=" & key
            statusFile.Close
            crt.Quit
            Exit Sub
        End If
    Next

    KernelFile = fs.GetFileName(Replace(manifest("artifact"), "/", "\"))
    KernelSize = manifest("size")
    KernelSha256 = manifest("sha256")
    KernelCrc32 = manifest("crc32")
    KernelCommit = manifest("kernel_commit")

    WriteStatus statusFile, "connected=" & crt.Session.Connected
    WriteStatus statusFile, "manifest=" & ManifestPath
    WriteStatus statusFile, "kernel_file=" & KernelFile
    WriteStatus statusFile, "kernel_size=" & KernelSize
    WriteStatus statusFile, "kernel_sha256=" & KernelSha256
    WriteStatus statusFile, "kernel_crc32=" & KernelCrc32
    WriteStatus statusFile, "kernel_commit=" & KernelCommit
    If manifest.Exists("bitstream") Then WriteStatus statusFile, "bitstream=" & manifest("bitstream")
    If manifest.Exists("bitstream_sha256") Then WriteStatus statusFile, "bitstream_sha256=" & manifest("bitstream_sha256")
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
    gotBanner = crt.Screen.WaitForString("Linux version", 240)
    WriteStatus statusFile, "linux_banner=" & gotBanner
    gotIssue = crt.Screen.WaitForString("NSCSCC LoongArch32 Reduced Linux", 60)
    WriteStatus statusFile, "linux_issue=" & gotIssue
    gotShell = crt.Screen.WaitForString(LinuxPrompt, 30)
    WriteStatus statusFile, "linux_shell=" & gotShell
    If Not gotBanner Or Not gotIssue Or Not gotShell Then
        WriteStatus statusFile, "result=error no_linux_shell"
        crt.Session.Log False
        crt.Session.Disconnect
        statusFile.Close
        crt.Quit
        Exit Sub
    End If

    ok = RunLinuxCommand(statusFile, "set +m", "__DONE_SETM__", 30, "")
    If ok Then ok = RunLinuxCommand(statusFile, "uname -a", "__DONE_UNAME__", 30, "Linux")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /proc/cpuinfo", "__DONE_CPUINFO__", 30, "processor")
    If ok Then ok = RunLinuxCommand(statusFile, "grep -E '^(MemTotal|MemFree|MemAvailable):' /proc/meminfo", "__DONE_MEM__", 30, "MemTotal")
    If ok Then ok = RunLinuxCommand(statusFile, "dmesg | grep -E 'Memory: .*131072K'", "__DONE_MEMORY_PHYSICAL__", 30, "131072K")
    If ok Then ok = RunLinuxCommand(statusFile, "dmesg | grep -E 'NR_IRQS|Constant clock event|Constant clock source'", "__DONE_EXCEPTION_TIMER__", 30, "Constant clock event")
    If ok Then ok = RunLinuxCommand(statusFile, "dmesg | grep 'Run /init as init process'", "__DONE_INITRAMFS__", 30, "Run /init")
    If ok Then ok = RunLinuxCommand(statusFile, "mount", "__DONE_MOUNT__", 30, "devtmpfs")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /etc/nscscc/build-info", "__DONE_BUILD_INFO__", 30, KernelCommit)
    If ok Then ok = RunLinuxCommand(statusFile, "cat /sys/class/chiplab_confreg/chiplab_confreg/device_info", "__DONE_CONFREG_INFO__", 30, "Physical base")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /sys/class/chiplab_confreg/chiplab_confreg/all_inputs", "__DONE_CONFREG_INPUTS__", 30, "switches=")
    If ok Then ok = RunLinuxCommand(statusFile, "ip addr show", "__DONE_IP_ADDR__", 30, "10.90.50.44/24")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /sys/class/net/eth0/statistics/rx_packets /sys/class/net/eth0/statistics/tx_packets /sys/class/net/eth0/statistics/rx_errors /sys/class/net/eth0/statistics/tx_errors", "__DONE_IP_LINK__", 30, "")
    If ok Then ok = RunLinuxCommand(statusFile, "test ""$(cat /sys/class/net/eth0/carrier)"" = 1 && echo CARRIER_OK", "__DONE_CARRIER__", 30, "CARRIER_OK")
    If ok Then ok = RunLinuxCommand(statusFile, "test ""$(cat /sys/class/net/eth0/statistics/rx_errors)"" = 0 && test ""$(cat /sys/class/net/eth0/statistics/tx_errors)"" = 0 && echo NETWORK_ERRORS_ZERO", "__DONE_NET_ERRORS_BEFORE__", 30, "NETWORK_ERRORS_ZERO")
    If ok Then ok = RunLinuxCommand(statusFile, "ETH_IRQ_BEFORE=$(awk '$NF == ""eth0"" {print $2}' /proc/interrupts); test -n ""$ETH_IRQ_BEFORE"" && echo ETH_IRQ_BEFORE=$ETH_IRQ_BEFORE", "__DONE_IRQ_BEFORE__", 30, "ETH_IRQ_BEFORE=")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /proc/interrupts", "__DONE_IRQ_BEFORE__", 30, "timer")
    If ok Then ok = RunLinuxCommand(statusFile, "ping -c 1 -W 2 10.90.50.43", "__DONE_PING_A__", 30, "0% packet loss")
    If ok Then ok = RunLinuxCommand(statusFile, "ping -c 1 -W 2 10.90.50.43", "__DONE_PING_B__", 30, "0% packet loss")
    If ok Then ok = RunLinuxCommand(statusFile, "ping -c 1 -W 2 10.90.50.43", "__DONE_PING_C__", 30, "0% packet loss")
    If ok Then ok = RunLinuxCommand(statusFile, "ETH_IRQ_AFTER=$(awk '$NF == ""eth0"" {print $2}' /proc/interrupts); test ""$ETH_IRQ_AFTER"" -gt ""$ETH_IRQ_BEFORE"" && echo ETH_IRQ_DELTA_OK before=$ETH_IRQ_BEFORE after=$ETH_IRQ_AFTER", "__DONE_IRQ_DELTA__", 30, "ETH_IRQ_DELTA_OK")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /proc/interrupts", "__DONE_IRQ_AFTER__", 30, "timer")
    If ok Then ok = RunLinuxCommand(statusFile, "nscscc-board read", "__DONE_BOARD_READ__", 30, "switches=")
    If ok Then ok = RunLinuxCommand(statusFile, "nscscc-board led 0x0000a55a", "__DONE_LED__", 30, "")
    If ok Then ok = RunLinuxCommand(statusFile, "nscscc-board display 0x20260719", "__DONE_DISPLAY__", 30, "")
    If ok Then ok = RunLinuxCommand(statusFile, "cat /sys/class/chiplab_confreg/chiplab_confreg/led /sys/class/chiplab_confreg/chiplab_confreg/display", "__DONE_CONFREG_OUTPUTS__", 30, "0x")
    If ok Then ok = RunLinuxCommand(statusFile, "dd if=/dev/chiplab_confreg bs=4 skip=1024 count=1 2>/dev/null | hexdump -v -e '1/4 ""%08x\n""'", "__DONE_CONFREG_CHAR_READ__", 30, "0000a55a")
    If ok Then ok = RunLinuxCommand(statusFile, "sh -c 'trap ""echo SIGNAL_HANDLED"" 14; kill -14 $$; echo SIGNAL_RETURNED'", "__DONE_SIGNAL__", 30, "SIGNAL_RETURNED")
    If ok Then ok = RunLinuxCommand(statusFile, "sh -c 'trap ""echo TIMER_SIGNAL_HANDLED"" 14; (sleep 1; kill -14 $$) & wait; echo TIMER_SIGNAL_RETURNED'", "__DONE_TIMER_SIGNAL__", 30, "TIMER_SIGNAL_RETURNED")
    If ok Then ok = RunLinuxCommand(statusFile, "dmesg | grep -E 'altera_ps2|serio|atkbd'", "__DONE_PS2_PROBE__", 30, "1fe04000.ps2")
    If ok Then ok = RunLinuxCommand(statusFile, "PS2_IRQ_BEFORE=$(awk '$NF == ""1fe04000.ps2"" {print $2}' /proc/interrupts); sleep 2; PS2_IRQ_AFTER=$(awk '$NF == ""1fe04000.ps2"" {print $2}' /proc/interrupts); test ""$PS2_IRQ_BEFORE"" = 0 && test ""$PS2_IRQ_AFTER"" = ""$PS2_IRQ_BEFORE"" && echo PS2_IDLE_OK", "__DONE_PS2_IDLE__", 30, "PS2_IDLE_OK")
    If ok Then ok = RunLinuxCommand(statusFile, "test ""$(cat /sys/class/net/eth0/statistics/rx_errors)"" = 0 && test ""$(cat /sys/class/net/eth0/statistics/tx_errors)"" = 0 && echo NETWORK_ERRORS_ZERO", "__DONE_NET_ERRORS_AFTER__", 30, "NETWORK_ERRORS_ZERO")
    If ok Then ok = RunLinuxCommand(statusFile, "if dmesg | grep -E 'BUG:|Oops:|Kernel panic|Call Trace:'; then exit 1; else echo KERNEL_ERRORS_NONE; fi", "__DONE_KERNEL_ERRORS__", 30, "KERNEL_ERRORS_NONE")
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
