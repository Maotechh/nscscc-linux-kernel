#$language = "VBScript"
#$interface = "1.0"

Const LogDirectory = "C:\Users\Henry\fpga-lab\diagnostic\linux\logs"
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

Sub SendSlow(text)
    Dim index
    For index = 1 To Len(text)
        crt.Screen.Send Mid(text, index, 1)
        crt.Sleep 2
    Next
    crt.Screen.Send vbCr
End Sub

Function RunLinuxCommand(statusFile, command, marker, timeoutSeconds)
    Dim output, markerSeen
    crt.Sleep 500
    Call SendSlow(command & "; rc=$?; echo " & marker & " rc=$rc")
    output = crt.Screen.ReadString(LinuxPrompt, timeoutSeconds)
    markerSeen = InStr(output, marker) > 0
    WriteStatus statusFile, "command=" & command
    WriteStatus statusFile, "output_begin"
    statusFile.WriteLine output
    WriteStatus statusFile, "output_end"
    WriteStatus statusFile, "marker_seen=" & markerSeen
    RunLinuxCommand = markerSeen
End Function

Sub Main
    Dim fs, statusFile, stamp, statusPath, serialPath
    Dim gotShell, ok, commandOk

    Set fs = CreateObject("Scripting.FileSystemObject")
    stamp = Timestamp()
    statusPath = LogDirectory & "\linux-diagnostic-status-" & stamp & ".txt"
    serialPath = LogDirectory & "\linux-diagnostic-serial-" & stamp & ".txt"
    Set statusFile = fs.CreateTextFile(statusPath, True)

    WriteStatus statusFile, "connected=" & crt.Session.Connected
    If Not crt.Session.Connected Then
        WriteStatus statusFile, "result=error not_connected"
        statusFile.Close
        Exit Sub
    End If

    crt.Screen.Synchronous = True
    crt.Session.LogFileName = serialPath
    crt.Session.Log True
    crt.Screen.Send vbCr
    gotShell = crt.Screen.WaitForString(LinuxPrompt, 30)
    WriteStatus statusFile, "linux_shell=" & gotShell
    If Not gotShell Then
        WriteStatus statusFile, "result=error no_linux_shell"
        crt.Session.Log False
        crt.Session.Disconnect
        statusFile.Close
        Exit Sub
    End If

    ok = True
    commandOk = RunLinuxCommand(statusFile, "set +m", "__SETM__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "uname -a", "__UNAME__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "cat /proc/interrupts", "__IRQ_BEFORE__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "cat /sys/class/net/eth0/statistics/rx_packets /sys/class/net/eth0/statistics/tx_packets /sys/class/net/eth0/statistics/rx_bytes /sys/class/net/eth0/statistics/tx_bytes /sys/class/net/eth0/statistics/rx_errors /sys/class/net/eth0/statistics/tx_errors", "__NET_BEFORE__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "ping -c 1 -W 2 10.90.50.43", "__PING_ONE_A__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "ping -c 1 -W 2 10.90.50.43", "__PING_ONE_B__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "ping -c 1 -W 2 10.90.50.43", "__PING_ONE_C__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "ping -c 1 -W 2 10.90.50.43", "__PING_THREE__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "sh -c 'trap ""echo ALARM_HANDLED"" 14; kill -14 $$; echo AFTER_ALARM'", "__SIGNAL_IMMEDIATE__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "sh -c 'trap ""echo TIMER_SIGNAL_HANDLED"" 14; (sleep 1; kill -14 $$) & wait; echo AFTER_TIMER_SIGNAL'", "__SIGNAL_TIMER__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "nscscc-board read", "__BOARD_READ__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "cat /sys/class/chiplab_confreg/chiplab_confreg/device_info", "__CONFREG_INFO__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "cat /sys/class/chiplab_confreg/chiplab_confreg/all_inputs", "__CONFREG_INPUTS__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "nscscc-board led 0x0000a55a", "__BOARD_LED__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "nscscc-board display 0x20260719", "__BOARD_DISPLAY__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "cat /sys/class/chiplab_confreg/chiplab_confreg/led /sys/class/chiplab_confreg/chiplab_confreg/display", "__CONFREG_OUTPUTS__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "dd if=/dev/chiplab_confreg bs=4 skip=1024 count=1 2>/dev/null | hexdump -v -e '1/4 ""%08x\n""'", "__CONFREG_CHAR_READ__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "cat /sys/class/net/eth0/statistics/rx_packets /sys/class/net/eth0/statistics/tx_packets /sys/class/net/eth0/statistics/rx_bytes /sys/class/net/eth0/statistics/tx_bytes /sys/class/net/eth0/statistics/rx_errors /sys/class/net/eth0/statistics/tx_errors", "__NET_AFTER__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "cat /proc/interrupts", "__IRQ_AFTER__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "dmesg | tail -100", "__DMESG__", 90)
    If Not commandOk Then ok = False

    If ok Then
        WriteStatus statusFile, "result=success"
    Else
        WriteStatus statusFile, "result=error command_marker_missing"
    End If
    crt.Session.Log False
    crt.Session.Disconnect
    statusFile.Close
End Sub
