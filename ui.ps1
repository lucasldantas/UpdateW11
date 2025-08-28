# Cria o script que será executado localmente pelo usuário
$scriptContent = @'
Add-Type -AssemblyName System.Windows.Forms

$form = New-Object System.Windows.Forms.Form
$form.Text = "Escolha uma opção"
$form.Size = New-Object System.Drawing.Size(300,200)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true

$btn1 = New-Object System.Windows.Forms.Button
$btn1.Text = "Executar agora"
$btn1.Location = New-Object System.Drawing.Point(30,30)
$btn1.Size = New-Object System.Drawing.Size(100,30)
$btn1.Add_Click({ Set-Content -Path "C:\ProgramData\answer.txt" -Value "Executar agora"; $form.Close() })

$btn2 = New-Object System.Windows.Forms.Button
$btn2.Text = "Adiar 1 hora"
$btn2.Location = New-Object System.Drawing.Point(150,30)
$btn2.Size = New-Object System.Drawing.Size(100,30)
$btn2.Add_Click({ Set-Content -Path "C:\ProgramData\answer.txt" -Value "Adiar 1 hora"; $form.Close() })

$btn3 = New-Object System.Windows.Forms.Button
$btn3.Text = "Adiar 2 horas"
$btn3.Location = New-Object System.Drawing.Point(90,80)
$btn3.Size = New-Object System.Drawing.Size(100,30)
$btn3.Add_Click({ Set-Content -Path "C:\ProgramData\answer.txt" -Value "Adiar 2 horas"; $form.Close() })

$form.Controls.Add($btn1)
$form.Controls.Add($btn2)
$form.Controls.Add($btn3)

$form.ShowDialog()
'@

# Salva o script em um local acessível
$localPath = "C:\ProgramData\showForm.ps1"
Set-Content -Path $localPath -Value $scriptContent

# Lista sessões interativas
$query = "SELECT * FROM Win32_LogonSession WHERE LogonType = 2"
$sessions = Get-WmiObject -Query $query

# Mapeia sessões para usuários
$logonUsers = Get-WmiObject -Class Win32_LoggedOnUser
foreach ($entry in $logonUsers) {
    $session = $entry.Antecedent -replace '.*="([^"]+)"', '$1'
    $user = $entry.Dependent -replace '.*="([^"]+)"', '$1'

    # Executa o script como o usuário logado
    $taskName = "ShowFormTask_$user"
    $time = (Get-Date).AddMinutes(1).ToString("HH:mm")

    schtasks /Create /TN $taskName /TR "powershell.exe -ExecutionPolicy Bypass -File `"$localPath`"" /SC ONCE /ST $time /RU $user /RL HIGHEST /F
    schtasks /Run /TN $taskName
}
