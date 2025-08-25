#requires -version 5.1
param([switch]$RePrompt)

# ==================== CONFIG / PATHS ====================
$AppRoot      = 'C:\ProgramData\UpdateW11'
$TargetPath   = Join-Path $AppRoot 'ui.ps1'         # caminho final fixo deste script
$TaskName     = 'GDL-AgendarScriptTeste'
$PsExeFull    = Join-Path $PSHOME 'powershell.exe'  # caminho absoluto do powershell.exe
# Comando real que você quer executar ao clicar "Executar agora":
$CommandToRun = { & msg * 'Teste' }
# ==================== GITHUB (auto-atualização) =========
$RepoOwner    = 'lucasldantas'
$RepoName     = 'UpdateW11'
$RepoRef      = 'main'
$RepoFilePath = 'ui.ps1'
# =======================================================

# ---------- Fase 1: garantir que estamos rodando do arquivo físico ----------
# Detecta se este código foi carregado via IEX (sem $PSCommandPath) ou fora do arquivo destino
$SelfPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $null }

if (-not (Test-Path -LiteralPath $AppRoot)) {
  New-Item -Path $AppRoot -ItemType Directory -Force | Out-Null
}

# Se não estamos rodando a partir do arquivo destino (ou não temos caminho),
# baixar do GitHub e relançar como arquivo.
if ([string]::IsNullOrWhiteSpace($SelfPath) -or
    ((Resolve-Path $SelfPath -ErrorAction SilentlyContinue).Path -ne (Resolve-Path $TargetPath -ErrorAction SilentlyContinue))) {

  # Monta URL da API do GitHub
  $apiUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/contents/$RepoFilePath?ref=$RepoRef"

  # Cabeçalhos: usa o token $t se ele existir no escopo (o seu one-liner fornece)
  $headers = @{ 'User-Agent' = 'ps' }
  if ($script:t -and $t) { $headers['Authorization'] = "token $t" }

  try {
    $resp   = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
    $bytes  = [Convert]::FromBase64String($resp.content)
    [IO.File]::WriteAllBytes($TargetPath, $bytes)
  } catch {
    [System.Windows.MessageBox]::Show("Falha ao preparar a UI:`n$($_.Exception.Message)","Erro",'OK','Error') | Out-Null
    return
  }

  # Relança a partir do arquivo salvo (mantém -RePrompt se vier marcado)
  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File', $TargetPath)
  if ($RePrompt) { $args += '-RePrompt' }
  Start-Process -FilePath $PsExeFull -ArgumentList $args | Out-Null
  return
}

# Daqui pra baixo, já estamos executando de C:\ProgramData\UpdateW11\ui.ps1
$ScriptPath = (Resolve-Path -LiteralPath $TargetPath).Path

# ---------- Helpers ----------
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
  } catch {}
}
function Remove-RePromptTask {
  try { & schtasks.exe /Delete /TN $TaskName /F | Out-Null } catch {}
}

# Cria tarefa ONCE que reabre a UI com -RePrompt (sem re-adiar)
function New-RePromptTask {
  param([datetime]$when)
  Ensure-SchedulerRunning

  if (-not (Test-Path -LiteralPath $PsExeFull)) { throw "powershell.exe não encontrado em '$PsExeFull'." }
  if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "Script não encontrado em '$ScriptPath'." }

  $runLevel = if (Test-IsAdmin) {'HIGHEST'} else {'NORMAL'}
  $sd = $when.ToString('dd/MM/yyyy')
  $st = $when.ToString('HH:mm')

  # /TR deve ser 1 único token com aspas corretas:
  $trValue = '"' + $PsExeFull + '" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $ScriptPath + '" -RePrompt'

  try { & schtasks.exe /Delete /TN $TaskName /F | Out-Null } catch {}

  $args = @(
    '/Create',
    '/TN', $TaskName,
    '/TR', $trValue,
    '/SC', 'ONCE',
    '/SD', $sd,
    '/ST', $st,
    '/F',
    '/RL', $runLevel,
    '/IT'          # precisa de usuário logado no disparo para mostrar a UI
  )

  $output = & schtasks.exe @args 2>&1
  if ($LASTEXITCODE -ne 0) { throw "Falha ao criar a tarefa. Saída do schtasks:`n$output" }
}

function Run-Now {
  Remove-RePromptTask
  try { & $CommandToRun } catch {
    [System.Windows.MessageBox]::Show("Falha ao executar:`n$($_.Exception.Message)","Erro",'OK','Error') | Out-Null
  }
}

# ---------- UI (WPF) ----------
Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Agendar Execução" Height="300" Width="520" WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" Background="#0f172a">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" CornerRadius="12" Background="#111827" Padding="16">
      <StackPanel>
        <TextBlock Name="TitleText" Text="Atualização Obrigatória" Foreground="#e5e7eb" FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Name="SubText" Text="Você pode executar agora ou adiar por até 2 horas." Foreground="#9ca3af" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>
    <Border Grid.Row="2" CornerRadius="12" Background="#0b1220" Padding="16" Margin="0,16,0,16">
      <StackPanel>
        <TextBlock Text="Ação:" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" Margin="0,0,0,6"/>
        <TextBlock Text='Realizar o update do Windows 10 para o Windows 11' Foreground="#94a3b8" FontFamily="Consolas" FontSize="14" Background="#0b1220"/>
        <TextBlock Text='Tempo Estimado: 20 a 30 minutos' Foreground="#94a3b8" FontFamily="Consolas" FontSize="14" Background="#0b1220"/>
      </StackPanel>
    </Border>
    <DockPanel Grid.Row="3">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="BtnNow" Content="Executar agora" Margin="8,0,0,0" Padding="16,8" Background="#22c55e" Foreground="White" FontFamily="Segoe UI" FontWeight="SemiBold" BorderBrush="#16a34a" BorderThickness="1" Cursor="Hand"/>
        <Button Name="BtnDelay1" Content="Adiar 1 hora" Margin="8,0,0,0" Padding="16,8" Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI" BorderBrush="#374151" BorderThickness="1" Cursor="Hand"/>
        <Button Name="BtnDelay2" Content="Adiar 2 horas" Margin="8,0,0,0" Padding="16,8" Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI" BorderBrush="#374151" BorderThickness="1" Cursor="Hand"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$BtnNow=$window.FindName('BtnNow'); $BtnDelay1=$window.FindName('BtnDelay1'); $BtnDelay2=$window.FindName('BtnDelay2')
$TitleTxt=$window.FindName('TitleText'); $SubTxt=$window.FindName('SubText')

if ($RePrompt) {
  $TitleTxt.Text = "Confirmação de execução"
  $SubTxt.Text   = "Chegou a hora agendada. Confirme a execução agora."
  $BtnDelay1.Visibility = 'Collapsed'
  $BtnDelay2.Visibility = 'Collapsed'
}

# ---------- Eventos ----------
$BtnNow.Add_Click({ $window.Close(); Run-Now })

$BtnDelay1.Add_Click({
  $BtnDelay1.IsEnabled=$false; $BtnDelay2.IsEnabled=$false; $BtnNow.IsEnabled=$false
  try {
    $runAt=(Get-Date).AddHours(1)
    New-RePromptTask -when $runAt
    [System.Windows.MessageBox]::Show(("Atualização agendada para {0:dd/MM/yyyy HH:mm}." -f $runAt),"Agendado",'OK','Information') | Out-Null
  } catch { [System.Windows.MessageBox]::Show("Falha ao agendar:`n$($_.Exception.Message)","Erro",'OK','Error') | Out-Null }
  $window.Close()
})

$BtnDelay2.Add_Click({
  $BtnDelay1.IsEnabled=$false; $BtnDelay2.IsEnabled=$false; $BtnNow.IsEnabled=$false
  try {
    $runAt=(Get-Date).AddHours(2)
    New-RePromptTask -when $runAt
    [System.Windows.MessageBox]::Show(("Atualização agendada para {0:dd/MM/yyyy HH:mm}." -f $runAt),"Agendado",'OK','Information') | Out-Null
  } catch { [System.Windows.MessageBox]::Show("Falha ao agendar:`n$($_.Exception.Message)","Erro",'OK','Error') | Out-Null }
  $window.Close()
})

$null = $window.ShowDialog()
