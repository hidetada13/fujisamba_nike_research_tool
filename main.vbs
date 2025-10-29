Dim objShell
Set objShell = CreateObject("WScript.Shell")

'コマンドプロンプトを最小化で起動
objShell.Run "cmd /c start /min ruby main.rb", 0, false

Set objShell = Nothing