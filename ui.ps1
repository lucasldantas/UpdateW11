# Define o conteúdo do script que será executado nas sessões de usuário
$formScript = @'
Add-Type -AssemblyName System.Windows.Forms

$form = New-Object System.Windows.Forms.Form
$form.Text = "Escolha uma opção"
$form.Size = New-Object System.Drawing.Size(300,200)
$form.StartPosition = "CenterScreen"

$btnExecutar = New-Object System.Windows.Forms.Button
$btnExecutar.Text = "Executar agora"
$btnExecutar.Location = New-Object System.Drawing.Point(30,30)
$btnExecutar.Size = New-Object System.Drawing.Size(100,30)
$btnExecutar.Add_Click({
    Set-Content -Path "C:\ProgramData\answer.txt" -Value "Executar agora"
    $form.Close()
})

$btnAdiar1 = New-Object System.Windows.Forms.Button
$btnAdiar1.Text = "Adiar 1 hora"
$btnAdiar1.Location = New-Object System.Drawing.Point(150,30)
$btnAdiar1.Size = New-Object System.Drawing.Size(100,30)
$btnAdiar1.Add_Click({
    Set-Content -Path "C:\ProgramData\answer.txt" -Value "Adiar 1 hora"
    $form.Close()
})

$btnAdiar2 = New-Object System.Windows.Forms.Button
$btnAdiar2.Text = "Adiar 2 horas"
$btnAdiar2.Location = New-Object System.Drawing.Point(90,80)
$btnAdiar2.Size = New-Object System.Drawing.Size(100,30)
$btnAdiar2.Add_Click({
    Set-Content -Path "C:\ProgramData\answer.txt" -Value "Adiar 2 horas"
    $form.Close()
})

$form.Controls.Add($btnExecutar)
$form.Controls.Add($btnAdiar1)
$form.Controls.Add($btnAdiar2)

$form.Topmost = $true
$form.ShowDialog()
'@

# Salva o script temporariamente
$tempScriptPath = "$env:temp\showForm.ps1"
Set-Content -Path $tempScriptPath -Value $formScript

# Envia para todas as sessões de usuário ativas
$query = "SELECT * FROM Win32_LogonSession WHERE LogonType = 2"
$activeSessions = Get-WmiObject -Query $query

foreach ($session in $activeSessions) {
    $sessionId = $session.__RELPATH -replace '.*="(\d+)"', '$1'
    try {
        schtasks /Create /TN "ShowFormTask_$sessionId" /TR "powershell.exe -ExecutionPolicy Bypass -File `"$tempScriptPath`"" /SC ONCE /ST 00:00 /RU "INTERACTIVE" /RL HIGHEST /F /IT
        schtasks /Run /TN "ShowFormTask_$sessionId"
    } catch {
        Write-Warning "Falha ao agendar tarefa para sessão ${sessionId}: $_"
    }
}
