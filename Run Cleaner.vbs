Option Explicit

Dim shell, fso, scriptDir, scriptPath, command, i
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(scriptDir, "src\WindowsCleaner.ps1")
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File " & QuoteArgument(scriptPath)

For i = 0 To WScript.Arguments.Count - 1
    command = command & " " & QuoteArgument(WScript.Arguments(i))
Next

shell.Run command, 0, False

Function QuoteArgument(value)
    QuoteArgument = Chr(34) & Replace(value, Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function
