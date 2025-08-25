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
$AppRoot      = 'C:\ProgramData\UpdateW11'
$TargetPath   = Join-Path $AppRoot 'ui.ps1'
$TaskName     = 'GDL-AgendarScriptTeste'
$PsExeFull    = Join-Path $PSHOME 'powershell.exe'
$LogPath      = Join-Path $AppRoot 'ui.log'

# Comando real ao clicar "Executar agora":
$CommandToRun = { & msg * 'Teste' }   # <-- troque aqui pelo comando real

# Repo (ajuste se necessário)
$RepoOwner    = 'lucasldantas'
$RepoName     = 'UpdateW11'
$RepoRef      = 'main'                # branch
$RepoFilePath = 'ui.ps1'              # caminho do arquivo no repo
# =====================================================

# Pequeno helper de log (opcional)
function Write-UiLog([string]$msg) {
  try {
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -LiteralPath $LogPath -Value "[$stamp] $msg"
  } catch { }
}

# ========== GARANTIR STA (WPF PRECISA) ==========
try {
  if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Write-UiLog "Relançando em STA. RePrompt=$RePrompt"
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File', $PSCommandPath)
    if ($RePrompt) { $args += '-RePrompt' }
    Start-Process -FilePath $PsExeFull -ArgumentList $args | Out-Null
    return
  }
} catch { Write-UiLog "Falha ao checar STA: $($_.Exception.Message)" }

# ========== Download robusto do GitHub ==========
function Get-UiFromGitHub {
  param([string]$Owner, [string]$Repo, [string]$Path, [string]$Ref)

  $apiUrl = "https://api.github.com/repos/$Owner/$Repo/contents/$Path?ref=$Ref"
  $rawUrl = "https://raw.githubusercontent.com/$Owner/$Repo/$Ref/$Path"

  $headers = @{ 'User-Agent'='ps'; 'Accept'='application/vnd.github+json' }
  if ($script:t -and $t) { $headers['Authorization'] = "token $t" }

  try {
    $resp = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
    if (-not $resp.content) { throw "Resposta sem 'content' em $apiUrl" }
    return ,([Convert]::FromBase64String($resp.content))
  } catch {
    $e1 = $_.Exception.Message
    try {
      $rawHeaders = @{ 'User-Agent'='ps' }
      if ($script:t -and $t) { $rawHeaders['Authorization'] = "token $t" }
      $resp2 = Invoke-WebRequest -Uri $rawUrl -Headers $rawHeaders -UseBasicParsing -ErrorAction Stop
      return ,([Text.Encoding]::UTF8.GetBytes($resp2.Content))
    } catch {
      $e2 = $_.Exception.Message
      throw "Falha ao baixar UI.`nTentativas:`n  1) API: $apiUrl`n     Erro: $e1`n  2) RAW: $rawUrl`n     Erro: $e2"
    }
  }
}

# ==================== Bootstrap local ====================
if (-not (Test-Path -LiteralPath $AppRoot)) {
  New-Item -Path $AppRoot -ItemType Directory -Force | Out-Null
}
$SelfPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }
$RunningFromTarget = $false
try {
  $RunningFromTarget = (Resolve-Path $SelfPath -ErrorAction SilentlyContinue).Path -eq (Resolve-Path $TargetPath -ErrorAction SilentlyContinue).Path
} catch { }

if (-not $RunningFromTarget) {
  try {
    Write-UiLog "Baixando e gravando UI em UTF-8 BOM."
    $bytes = Get-UiFromGitHub -Owner $RepoOwner -Repo $RepoName -Path $RepoFilePath -Ref $RepoRef
    $text  = [Text.Encoding]::UTF8.GetString($bytes)
    $utf8BOM = New-Object System.Text.UTF8Encoding($true)   # UTF-8 com BOM
    [IO.File]::WriteAllText($TargetPath, $text, $utf8BOM)
  } catch {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    [System.Windows.MessageBox]::Show("$Txt_ErrorPreparePrefix`n$($_.Exception.Message)", $Txt_ErrorTitle,'OK','Error') | Out-Null
    Write-UiLog "Falha no bootstrap: $($_.Exception.Message)"
    return
  }

  # Reabrir a partir do arquivo salvo (console oculto aqui é ok)
  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File', $TargetPath)
  if ($RePrompt) { $args += '-RePrompt' }
  Start-Process -FilePath $PsExeFull -ArgumentList $args | Out-Null
  Write-UiLog "Relançado do TargetPath."
  return
}

# Agora estamos em C:\ProgramData\UpdateW11\ui.ps1
$ScriptPath = (Resolve-Path -LiteralPath $TargetPath).Path
Write-UiLog "Iniciando UI. RePrompt=$RePrompt"

# ==================== Helpers ====================
function Test-IsAdmin {
  $id=[Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Ensure-SchedulerRunning {
  try {
    $svc = Get-Service -Name 'Schedule' -ErrorAction Stop
    if ($svc.Status -ne 'Running') {
      Start-Service -Name 'Schedule' -ErrorAction Stop
      $svc.WaitForStatus('Running','00:00:05') | Out-Null
    }
  } catch { }
}
function Remove-RePromptTask { try { & schtasks.exe /Delete /TN $TaskName /F | Out-Null } catch { } }

function New-RePromptTask {
  param([datetime]$when)

  Ensure-SchedulerRunning
  if (-not (Test-Path -LiteralPath $PsExeFull)) { throw ($Txt_ErrorNoPS -f $PsExeFull) }
  if (-not (Test-Path -LiteralPath $ScriptPath)) { throw ($Txt_ErrorNoScript -f $ScriptPath) }

  $ru = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  if ([string]::IsNullOrWhiteSpace($ru)) { throw $Txt_ErrorNoRU }

  $runLevel = if (Test-IsAdmin) {'HIGHEST'} else {'NORMAL'}
  $sd = $when.ToString('dd/MM/yyyy')
  $st = $when.ToString('HH:mm')

  # Para tarefa: janela visível (NÃO usar -WindowStyle Hidden)
  $trValue = '"' + $PsExeFull + '" -NoProfile -ExecutionPolicy Bypass -STA -File "' + $ScriptPath + '" -RePrompt'

  try { & schtasks.exe /Delete /TN $TaskName /F | Out-Null } catch { }

  $args = @('/Create','/TN',$TaskName,'/TR',$trValue,'/SC','ONCE','/SD',$sd,'/ST',$st,'/F','/RL',$runLevel,'/RU',$ru,'/IT')
  $output = & schtasks.exe @args 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Falha ao criar a tarefa. Saída do schtasks:`n$output" }
  Write-UiLog "Tarefa criada para $sd $st como $ru."
}

function Run-Now {
  Remove-RePromptTask
  try { & $CommandToRun } catch {
    [System.Windows.MessageBox]::Show("$Txt_ErrorRunPrefix`n$($_.Exception.Message)", $Txt_ErrorTitle,'OK','Error') | Out-Null
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

# Garantir visibilidade (traz pra frente e dá foco)
$window.Topmost = $true
$window.Loaded.Add({
  try {
    $window.Activate()      | Out-Null
    $window.BringIntoView() | Out-Null
  } catch { }
})

# Permitir arrastar a janela (sem barra de título)
$window.Add_MouseLeftButtonDown({
  if ($_.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) {
    try { $window.DragMove() } catch { }
  }
})

$BtnNow    = $window.FindName('BtnNow')
$BtnDelay1 = $window.FindName('BtnDelay1')
$BtnDelay2 = $window.FindName('BtnDelay2')
$TitleTxt  = $window.FindName('TitleText')
$SubTxt    = $window.FindName('SubText')

# RePrompt: sem opções de adiar
if ($RePrompt) {
  $TitleTxt.Text = $Txt_ConfirmTitle
  $SubTxt.Text   = $Txt_ConfirmSubtitle
  $BtnDelay1.Visibility = 'Collapsed'
  $BtnDelay2.Visibility = 'Collapsed'
}

# Bloquear fechar (Alt+F4 etc.) — janela só fecha pelos botões
$script:closingHandler = [System.ComponentModel.CancelEventHandler]{
  param($sender, [System.ComponentModel.CancelEventArgs]$e)
  $e.Cancel = $true
}
$window.add_Closing($script:closingHandler)
function Allow-Close([System.Windows.Window]$win) {
  if ($win -and $script:closingHandler) { $win.remove_Closing($script:closingHandler) }
}

# -------- Eventos --------
$BtnNow.Add_Click({
  Allow-Close $window
  $window.Close()
  Run-Now
})

$BtnDelay1.Add_Click({
  $BtnDelay1.IsEnabled=$false; $BtnDelay2.IsEnabled=$false; $BtnNow.IsEnabled=$false
  try {
    $runAt=(Get-Date).AddHours(1)
    New-RePromptTask -when $runAt
    [System.Windows.MessageBox]::Show(($Txt_ScheduledFmt -f $runAt), $Txt_ScheduledTitle,'OK','Information') | Out-Null
  } catch {
    [System.Windows.MessageBox]::Show("$Txt_ErrorSchedulePrefix`n$($_.Exception.Message)", $Txt_ErrorTitle,'OK','Error') | Out-Null
  }
  Allow-Close $window
  $window.Close()
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
  Allow-Close $window
  $window.Close()
})

$null = $window.ShowDialog()
