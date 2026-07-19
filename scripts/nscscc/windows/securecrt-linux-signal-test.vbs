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
    statusPath = LogDirectory & "\linux-signal-test-status-" & stamp & ".txt"
    serialPath = LogDirectory & "\linux-signal-test-serial-" & stamp & ".txt"
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
    commandOk = RunLinuxCommand(statusFile, "tftp -g -r signal-test -l /tmp/signal-test 10.90.50.43", "__TFTP_SIGNAL_TEST__", 60)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "chmod 0755 /tmp/signal-test", "__CHMOD_SIGNAL_TEST__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "ls -l /tmp/signal-test", "__LS_SIGNAL_TEST__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "/tmp/signal-test", "__SIGNAL_RAISE__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "/tmp/signal-test timer", "__SIGNAL_TIMER__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "tftp -g -r busybox-1.33-static -l /tmp/busybox-new 10.90.50.43", "__TFTP_BUSYBOX__", 90)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "chmod 0755 /tmp/busybox-new", "__CHMOD_BUSYBOX__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "/tmp/busybox-new sh -c 'trap ""echo NEW_BUSYBOX_ALARM_HANDLED"" 14; kill -14 $$; echo NEW_BUSYBOX_AFTER_ALARM'", "__BUSYBOX_SIGNAL__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "/tmp/busybox-new ping -c 3 -W 2 10.90.50.43", "__BUSYBOX_PING__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "/tmp/busybox-new ip -s link show eth0", "__BUSYBOX_IP_STATS__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "cat /proc/interrupts", "__SIGNAL_IRQ__", 30)
    If Not commandOk Then ok = False
    commandOk = RunLinuxCommand(statusFile, "dmesg | tail -40", "__SIGNAL_DMESG__", 60)
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
