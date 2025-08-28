function Send-RebootBroadcast {
    [CmdletBinding()]
    param(
        [string]$Title = "Atualização do Windows 11",
        [string]$Message = "Reinicie seu computador para concluir a atualização do Windows 11.",
        [int]$DelaySeconds = 3600,
        [int]$CleanupAfterMinutes = 10
    )

    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

    # --- 1) Script da UI que roda no contexto do usuário ---
    $UiPath = 'C:\ProgramData\UpdateW11\Show-RebootPrompt.ps1'
    $UiScript = @'
param(
    [string]$Title = "Atualização",
    [string]$Message = "Reinicie seu computador.",
    [int]$DelaySeconds = 3600
)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$form                  = New-Object System.Windows.Forms.Form
$form.Text             = $Title
$form.StartPosition    = "CenterScreen"
$form.TopMost          = $true
$form.FormBorderStyle  = "FixedDialog"
$form.MaximizeBox      = $false
$form.MinimizeBox      = $false
$form.Width            = 540
$form.Height           = 220

$lbl = New-Object System.Windows.Forms.Label
$lbl.AutoSize = $false
$lbl.Width  = 500
$lbl.Height = 70
$lbl.Left   = 20
$lbl.Top    = 20
$lbl.Font   = New-Object System.Drawing.Font("Segoe UI", 11)
$lbl.Text   = $Message
$form.Controls.Add($lbl)

$btnNow = New-Object System.Windows.Forms.Button
$btnNow.Text   = "Reiniciar agora"
$btnNow.Width  = 160
$btnNow.Height = 36
$btnNow.Left   = 100
$btnNow.Top    = 110
$form.Controls.Add($btnNow)

$btnDelay = New-Object System.Windows.Forms.Button
$mins = [math]::Round($DelaySeconds / 60.0)
if ($mins -lt 1) { $mins = 1 }
$btnDelay.Text   = "Reiniciar em $mins min"
$btnDelay.Width  = 160
$btnDelay.Height = 36
$btnDelay.Left   = 280
$btnDelay.Top    = 110
$form.Controls.Add($btnDelay)

$btnNow.Add_Click({
    try {
        Start-Process -FilePath "shutdown.exe" -ArgumentList '/r /t 0 /c "Reinício para concluir atualização"' -WindowStyle Hidden
    } catch {}
    $form.Close()
})

$btnDelay.Add_Click({
    try {
        Start-Process -FilePath "shutdown.exe" -ArgumentList "/r /t $DelaySeconds /c `"Reinício automático agendado`"" -WindowStyle Hidden
        [System.Windows.Forms.MessageBox]::Show("Reinício agendado para daqui a $mins minuto(s).","Agendado",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } catch {}
    $form.Close()
})

[void]$form.ShowDialog()
'@
    New-Item -ItemType Directory -Path (Split-Path $UiPath) -Force | Out-Null
    Set-Content -Path $UiPath -Value $UiScript -Encoding UTF8

    # --- 2) Descobrir sessões de usuário com desktop (explorer.exe) ---
    $explorers = Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -ne $null }
    if (-not $explorers) {
        Write-Host "Nenhuma sessão de usuário com desktop encontrada."
        return
    }

    # --- 3) Resolver SID a partir de 'DOM\user' ---
    function Get-SIDFromAccount([string]$account) {
        try {
            (New-Object System.Security.Principal.NTAccount($account)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        } catch { $null }
    }

    # --- 4) Criar e executar tarefa por sessão ---
    $targets = $explorers | Group-Object SessionId,UserName -NoElement | ForEach-Object {
        $parts = $_.Name -split ','
        [pscustomobject]@{ SessionId = [int]$parts[0]; UserName = $parts[1] }
    }

    foreach ($t in $targets) {
        $sid = Get-SIDFromAccount $t.UserName
        if (-not $sid) { Write-Host "Ignorando sessão $($t.SessionId): não foi possível obter SID de $($t.UserName)"; continue }

        $taskName = "UpdateW11-RebootPrompt-S$($t.SessionId)"
        try {
            $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$UiPath`" -Title `"$Title`" -Message `"$Message`" -DelaySeconds $DelaySeconds"
            $action    = New-ScheduledTaskAction  -Execute "powershell.exe" -Argument $arg
            $principal = New-ScheduledTaskPrincipal -UserId $sid -LogonType InteractiveToken -RunLevel Highest
            $settings  = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DisallowStartIfOnBatteries:$false
            $task      = New-ScheduledTask -Action $action -Principal $principal -Settings $settings

            Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
            Start-ScheduledTask    -TaskName $taskName
            Write-Host "✅ UI disparada para sessão $($t.SessionId) ($($t.UserName))"
        }
        catch {
            Write-Host "❌ Falha na sessão $($t.SessionId) ($($t.UserName)): $($_.Exception.Message)"
        }
    }

    # --- 5) Limpeza opcional das tarefas temporárias ---
    if ($CleanupAfterMinutes -gt 0) {
        Start-Job -ScriptBlock {
            param($minutes)
            Start-Sleep -Seconds ($minutes * 60)
            Get-ScheduledTask -TaskName 'UpdateW11-RebootPrompt-S*' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
        } -ArgumentList $CleanupAfterMinutes | Out-Null
    }
}

Send-RebootBroadcast
