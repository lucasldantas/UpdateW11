#requires -version 5.1
param([switch]$RePrompt)

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ==================== TEXTOS / RÓTULOS (customizáveis) ====================
$Txt_WindowTitle          = 'Agendar Execução'
$Txt_HeaderTitle          = 'Atualização Obrigatória'
$Txt_HeaderSubtitle       = 'Você pode executar agora ou adiar por até 2 horas.'
$Txt_ActionLabel          = 'Ação:'
$Txt_ActionLine1          = 'Realizar o update do Windows 10 para o Windows 11'
$Txt_ActionLine2          = 'Tempo Estimado: 20 a 30 minutos'

$Txt_BtnNow               = 'Executar agora'
$Txt_BtnDelay1            = 'Adiar 1 hora'
$Txt_BtnDelay2            = 'Adiar 2 horas'

$Txt_ConfirmTitle         = 'Confirmação de execução'
$Txt_ConfirmSubtitle      = 'Chegou a hora agendada. Confirme a execução agora.'

$Txt_ScheduledTitle       = 'Agendado'
$Txt_ScheduledFmt         = 'Agendado para {0:dd/MM/yyyy HH:mm}. A janela será reaberta nessa hora para confirmar a execução.'

$Txt_ErrorTitle           = 'Erro'
$Txt_ErrorPreparePrefix   = 'Falha ao preparar a UI:'
$Txt_ErrorSchedulePrefix  = 'Falha ao agendar:'
$Txt_ErrorRunPrefix       = 'Falha ao executar:'
$Txt_ErrorNoPS            = "powershell.exe não encontrado em '{0}'."
$Txt_ErrorNoScript        = "Script não encontrado em '{0}'."
$Txt_ErrorNoRU            = 'Não foi possível resolver o usuário atual para /RU.'
# ==========================================================================

# ==================== CONFIG GERAL ====================
$AppRoot         = 'C:\ProgramData\UpdateW11'
$TargetPath      = Join-Path $AppRoot 'ui.ps1'
$TaskNameUI      = 'GDL-AgendarScriptTeste'     # tarefa da UI (usuário)
$WorkerTaskName  = 'GDL-AgendarScriptWorker'    # tarefa do worker (SYSTEM)
$WorkerPath      = Join-Path $AppRoot 'worker.ps1'
$PsExeFull       = Join-Path $PSHOME 'powershell.exe'
$LogPath         = Join-Path $AppRoot 'ui.log'

# Comando real (fica no worker.ps1). Aqui só para bootstrap.
$DefaultWorkerBody = @'
# worker.ps1 (executa como SYSTEM)
# Troque o comando abaixo pelo real:
msg * "Executando tarefa elevada (SYSTEM) — exemplo"
'@

# Repo (ajuste se necessário) — usado no bootstrap quando rodar via IEX
$RepoOwner    = 'lucasldantas'
$RepoName     = 'UpdateW11'
$RepoRef      = 'main'         # branch
$RepoFilePath = 'ui.ps1'       # caminho do arquivo no repo
# =====================================================

# ---------- Log (opcional) ----------
function Write-UiLog([string]$msg) {
  try {
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -LiteralPath $LogPath -Value "[$stamp] $msg"
  } catch {}
}

# ---------- Garantir STA (WPF precisa) ----------
try {
  if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA' -and $PSCommandPath) {
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File', $PSCommandPath)
    if ($RePrompt) { $args += '-RePrompt' }
    Start-Process -FilePath $PsExeFull -ArgumentList $args | Out-Null
    return
  }
} catch { Write-UiLog "Falha STA: $($_.Exception.Message)" }

# ---------- Download robusto do GitHub ----------
function Get-UiFromGitHub {
  param([string]$Owner,[string]$Repo,[string]$Path,[string]$Ref)
  $apiUrl = "https://api.github.com/repos/$Owner/$Repo/contents/$Path?ref=$Ref"
  $rawUrl = "https://raw.githubusercontent.com/$Owner/$Repo/$Ref/$Path"
  $headers = @{ 'User-Agent'='ps'; 'Accept'='application/vnd.github+json' }
  if ($script:t -and $t) { $headers['Authorization'] = "token $t" }

  try {
    $resp = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
    if (-not $resp.content) { throw "Sem 'content' em $apiUrl" }
    return ,([Convert]::FromBase64String($resp.content))
  } catch {
    $e1=$_.Exception.Message
    try {
      $rawHeaders=@{ 'User-Agent'='ps' }; if ($script:t -and $t) { $rawHeaders['Authorization']="token $t" }
      $resp2 = Invoke-WebRequest -Uri $rawUrl -Headers $rawHeaders -UseBasicParsing -ErrorAction Stop
      return ,([Text.Encoding]::UTF8.GetBytes($resp2.Content))
    } catch { $e2=$_.Exception.Message; throw "Falha baixar UI:`n1) $apiUrl -> $e1`n2) $rawUrl -> $e2" }
  }
}

# ---------- Bootstrap local ----------
if (-not (Test-Path -LiteralPath $AppRoot)) { New-Item -Path $AppRoot -ItemType Directory -Force | Out-Null }
$SelfPath = $PSCommandPath ?? $MyInvocation.MyCommand.Path
$RunningFromTarget = $false
try {
  $RunningFromTarget = (Resolve-Path $SelfPath -ErrorAction SilentlyContinue).Path -eq (Resolve-Path $TargetPath -ErrorAction SilentlyContinue).Path
} catch {}

if (-not $RunningFromTarget) {
  try {
    $bytes = Get-UiFromGitHub -Owner $RepoOwner -Repo $RepoName -Path $RepoFilePath -Ref $RepoRef
    $text  = [Text.Encoding]::UTF8.GetString($bytes)
    $utf8BOM = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText($TargetPath, $text, $utf8BOM)
  } catch {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    [System.Windows.MessageBox]::Show("$Txt_ErrorPreparePrefix`n$($_.Exception.Message)", $Txt_ErrorTitle,'OK','Error') | Out-Null
    Write-UiLog "Bootstrap falhou: $($_.Exception.Message)"
    return
  }

  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File', $TargetPath)
  if ($RePrompt) { $args += '-RePrompt' }
  Start-Process -FilePath $PsExeFull -ArgumentList $args | Out-Null
  return
}

# Agora estamos em C:\ProgramData\UpdateW11\ui.ps1
$ScriptPath = (Resolve-Path $TargetPath).Path

# ---------- Helpers ----------
function Test-IsAdmin {
  $id=[Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Ensure-SchedulerRunning {
  try { $svc = Get-Service -Name 'Schedule' -ErrorAction Stop; if ($svc.Status -ne 'Running'){ Start-Service 'Schedule'; $svc.WaitForStatus('Running','00:00:05') | Out-Null } } catch {}
}
function Remove-UiTask { try { schtasks /Delete /TN $TaskNameUI /F | Out-Null } catch {} }

# Usuário ativo da console (não SYSTEM)
function Get-ActiveConsoleUser {
  try {
    $expl = Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($expl -and $expl.UserName) { return $expl.UserName }
  } catch {}

  try {
    $out = (quser) 2>$null
    foreach ($line in $out) {
      if ($line -match '^\s*(\S+)\s+(\S+)\s+(\S+)') {
        $user=$Matches[1]; $state=$Matches[3]
        if ($state -match 'Active|Ativa') {
          if ($env:USERDOMAIN) { return "$env:USERDOMAIN\$user" }
          else { return "$env:COMPUTERNAME\$user" }
        }
      }
    }
  } catch {}

  return [Security.Principal.WindowsIdentity]::GetCurrent().Name
}

# Garante o worker SYSTEM + arquivo worker.ps1
function Ensure-WorkerScript {
  if (-not (Test-Path -LiteralPath $WorkerPath)) {
    $utf8BOM = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText($WorkerPath, $DefaultWorkerBody, $utf8BOM)
  }
}
function Ensure-WorkerTask {
  Ensure-WorkerScript
  $trValue = '"' + $PsExeFull + '" -NoProfile -ExecutionPolicy Bypass -File "' + $WorkerPath + '"'
  $exists = (schtasks /Query /TN $WorkerTaskName 2>$null)
  if (-not $?) {
    schtasks /Create /TN $WorkerTaskName /TR $trValue /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /RU SYSTEM /F | Out-Null
  } else {
    # Se já existe, atualiza ação caso mude o caminho
    schtasks /Change /TN $WorkerTaskName /TR $trValue | Out-Null
  }
}

# Cria a tarefa de REPROMPT (UI, usuário logado, interativa, com janela visível)
function New-RePromptTask {
  param([datetime]$when)

  Ensure-SchedulerRunning
  if (-not (Test-Path -LiteralPath $PsExeFull)) { throw ($Txt_ErrorNoPS -f $PsExeFull) }
  if (-not (Test-Path -LiteralPath $ScriptPath)) { throw ($Txt_ErrorNoScript -f $ScriptPath) }

  $ru = Get-ActiveConsoleUser
  if ([string]::IsNullOrWhiteSpace($ru)) { throw $Txt_ErrorNoRU }

  $sd = $when.ToString('dd/MM/yyyy'); $st = $when.ToString('HH:mm')
  $trValue = '"' + $PsExeFull + '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -STA -File "' + $ScriptPath + '" -RePrompt'

  try { schtasks /Delete /TN $TaskNameUI /F | Out-Null } catch {}

  schtasks /Create /TN $TaskNameUI /TR $trValue /SC ONCE /SD $sd /ST $st /RL HIGHEST /RU $ru /IT /F | Out-Null
}

# -------- Execução do comando (agora dispara o worker SYSTEM) --------
function Run-Now {
  try {
    Ensure-WorkerTask
    schtasks /Run /TN $WorkerTaskName | Out-Null
  } catch {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    [System.Windows.MessageBox]::Show("$Txt_ErrorRunPrefix`n$($_.Exception.Message)", $Txt_ErrorTitle,'OK','Error') | Out-Null
  } finally {
    Remove-UiTask
  }
}

# ==================== UI (WPF) ====================
Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Txt_WindowTitle"
        Width="520" MinHeight="300" SizeToContent="Height"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" Background="#0f172a"
        WindowStyle="None" ShowInTaskbar="True">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Cabeçalho -->
    <Border Grid.Row="0" CornerRadius="12" Background="#111827" Padding="16">
      <StackPanel>
        <TextBlock Name="TitleText" Text="$Txt_HeaderTitle" Foreground="#e5e7eb"
                   FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Name="SubText" Text="$Txt_HeaderSubtitle"
                   Foreground="#9ca3af" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>

    <!-- Corpo -->
    <Border Grid.Row="2" CornerRadius="12" Background="#0b1220" Padding="16" Margin="0,16,0,16">
      <StackPanel>
        <TextBlock Text="$Txt_ActionLabel" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" Margin="0,0,0,6"/>
        <TextBlock Text="$Txt_ActionLine1"
                   Foreground="#94a3b8" FontFamily="Consolas" FontSize="14"
                   Background="#0b1220" TextWrapping="Wrap" Margin="0,0,0,4"/>
        <TextBlock Text="$Txt_ActionLine2"
                   Foreground="#94a3b8" FontFamily="Consolas" FontSize="14"
                   Background="#0b1220" TextWrapping="Wrap"/>
      </StackPanel>
    </Border>

    <!-- Botões -->
    <DockPanel Grid.Row="3">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="BtnNow" Content="$Txt_BtnNow" Margin="8,0,0,0" Padding="16,8"
                Background="#22c55e" Foreground="White" FontFamily="Segoe UI" FontWeight="SemiBold"
                BorderBrush="#16a34a" BorderThickness="1" Cursor="Hand"/>
        <Button Name="BtnDelay1" Content="$Txt_BtnDelay1" Margin="8,0,0,0" Padding="16,8"
                Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI"
                BorderBrush="#374151" BorderThickness="1" Cursor="Hand"/>
        <Button Name="BtnDelay2" Content="$Txt_BtnDelay2" Margin="8,0,0,0" Padding="16,8"
                Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI"
                BorderBrush="#374151" BorderThickness="1" Cursor="Hand"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Garantir visibilidade e foco
$window.Topmost = $true
$window.Loaded.Add({
  try {
    $null = $window.Activate()
    $null = $window.BringIntoView()
    [System.Windows.Threading.DispatcherTimer]::new([TimeSpan]::FromMilliseconds(150), 'Normal', {
      try { $null = $window.Activate() } catch {}
    }, $window.Dispatcher) | Out-Null
  } catch {}
})

# Arrastar (sem barra de título)
$window.Add_MouseLeftButtonDown({
  if ($_.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) {
    try { $window.DragMove() } catch {}
  }
})

$BtnNow    = $window.FindName('BtnNow')
$BtnDelay1 = $window.FindName('BtnDelay1')
$BtnDelay2 = $window.FindName('BtnDelay2')
$TitleTxt  = $window.FindName('TitleText')
$SubTxt    = $window.FindName('SubText')

# RePrompt: sem adiar
if ($RePrompt) {
  $TitleTxt.Text = $Txt_ConfirmTitle
  $SubTxt.Text   = $Txt_ConfirmSubtitle
  $BtnDelay1.Visibility = 'Collapsed'
  $BtnDelay2.Visibility = 'Collapsed'
}

# Bloquear fechar por X/Alt+F4
$script:closingHandler = [System.ComponentModel.CancelEventHandler]{ param($s,[System.ComponentModel.CancelEventArgs]$e) $e.Cancel = $true }
$window.add_Closing($script:closingHandler)
function Allow-Close([System.Windows.Window]$win) { if ($win -and $script:closingHandler) { $win.remove_Closing($script:closingHandler) } }

# -------- Eventos --------
$BtnNow.Add_Click({
  Allow-Close $window; $window.Close(); Run-Now
})

$BtnDelay1.Add_Click({
  $BtnDelay1.IsEnabled=$false; $BtnDelay2.IsEnabled=$false; $BtnNow.IsEnabled=$false
  try {
    $runAt=(Get-Date).AddMinutes(2)   # use .AddMinutes(2) para teste rápido
    New-RePromptTask -when $runAt
    [System.Windows.MessageBox]::Show(($Txt_ScheduledFmt -f $runAt), $Txt_ScheduledTitle,'OK','Information') | Out-Null
  } catch {
    [System.Windows.MessageBox]::Show("$Txt_ErrorSchedulePrefix`n$($_.Exception.Message)", $Txt_ErrorTitle,'OK','Error') | Out-Null
  }
  Allow-Close $window; $window.Close()
})

$BtnDelay2.Add_Click({
  $BtnDelay1.IsEnabled=$false; $BtnDelay2.IsEnabled=$false; $BtnNow.IsEnabled=$false
  try {
    $runAt=(Get-Date).AddHours(2)
    New-RePromptTask -when $runAt
    [System.Windows.MessageBox]::Show(($Txt_ScheduledFmt -f $runAt), $Txt_ScheduledTitle,'OK','Information') | Out-Null
  } catch {
    [System.Windows.MessageBox]::Show("$Txt_ErrorSchedulePrefix`n$($_.Exception.Message)", $Txt_ErrorTitle,'OK','Error') | Out-Null
  }
  Allow-Close $window; $window.Close()
})

$null = $window.ShowDialog()


