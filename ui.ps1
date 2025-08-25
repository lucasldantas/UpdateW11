#requires -version 5.1
param([switch]$RePrompt)

# --------------------------------------------------------------------
#   UI de agendamento/execução com WPF (PT-BR)
#   - Executar agora => roda $CommandToRun
#   - Adiar 1h / 2h  => agenda reabertura desta UI para confirmar/rodar
#   - Reaberta com -RePrompt => NÃO permite adiar de novo (só Executar)
#   - Bootstrap: se rodar via IEX, baixa/salva em C:\ProgramData\UpdateW11\ui.ps1 (UTF-8 BOM) e relança
#   - Tarefa: schtasks.exe /RU (usuário atual) + /IT (sem pedir senha; exige sessão)
#   - Janela sem “X” (WindowStyle=None) + arrastar pela área vazia + bloqueio Alt+F4
# --------------------------------------------------------------------

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ==================== CONFIG GERAL ====================
$AppRoot      = 'C:\ProgramData\UpdateW11'
$TargetPath   = Join-Path $AppRoot 'ui.ps1'
$TaskName     = 'GDL-AgendarScriptTeste'
$PsExeFull    = Join-Path $PSHOME 'powershell.exe'

# Comando real ao clicar "Executar agora":
$CommandToRun = { & msg * 'Teste' }   # <-- troque aqui pelo comando real

# Repo (ajuste se necessário)
$RepoOwner    = 'lucasldantas'
$RepoName     = 'UpdateW11'
$RepoRef      = 'main'                # branch
$RepoFilePath = 'ui.ps1'              # caminho do arquivo no repo
# =====================================================

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
      throw "Falha ao baixar UI.
Tentativas:
  1) API: $apiUrl
     Erro: $e1
  2) RAW: $rawUrl
     Erro: $e2"
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
    $bytes = Get-UiFromGitHub -Owner $RepoOwner -Repo $RepoName -Path $RepoFilePath -Ref $RepoRef
    $text  = [Text.Encoding]::UTF8.GetString($bytes)
    $utf8BOM = New-Object System.Text.UTF8Encoding($true)   # UTF-8 com BOM
    [IO.File]::WriteAllText($TargetPath, $text, $utf8BOM)
  } catch {
    Add-Type -AssemblyName PresentationFramework | Out-Null
    [System.Windows.MessageBox]::Show("Falha ao preparar a UI:`n$($_.Exception.Message)","Erro",'OK','Error') | Out-Null
    return
  }

  # Reabra a partir do arquivo salvo (com STA para WPF)
  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File', $TargetPath)
  if ($RePrompt) { $args += '-RePrompt' }
  Start-Process -FilePath $PsExeFull -ArgumentList $args | Out-Null
  return
}

# Agora estamos em C:\ProgramData\UpdateW11\ui.ps1
$ScriptPath = (Resolve-Path -LiteralPath $TargetPath).Path

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
  if (-not (Test-Path -LiteralPath $PsExeFull)) { throw "powershell.exe não encontrado em '$PsExeFull'." }
  if (-not (Test-Path -LiteralPath $ScriptPath)) { throw "Script não encontrado em '$ScriptPath'." }

  $ru = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
  if ([string]::IsNullOrWhiteSpace($ru)) { throw "Não foi possível resolver o usuário atual para /RU." }

  $runLevel = if (Test-IsAdmin) {'HIGHEST'} else {'NORMAL'}
  $sd = $when.ToString('dd/MM/yyyy')
  $st = $when.ToString('HH:mm')

  $trValue = '"' + $PsExeFull + '" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $ScriptPath + '" -RePrompt'

  try { & schtasks.exe /Delete /TN $TaskName /F | Out-Null } catch { }

  $args = @(
    '/Create','/TN',$TaskName,
    '/TR',$trValue,
    '/SC','ONCE','/SD',$sd,'/ST',$st,
    '/F','/RL',$runLevel,
    '/RU',$ru,'/IT'
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

# ==================== UI (WPF) ====================
Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Agendar Execução"
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
        <TextBlock Name="TitleText" Text="Atualização Obrigatória" Foreground="#e5e7eb"
                   FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Name="SubText" Text="Você pode executar agora ou adiar por até 2 horas."
                   Foreground="#9ca3af" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>

    <!-- Corpo -->
    <Border Grid.Row="2" CornerRadius="12" Background="#0b1220" Padding="16" Margin="0,16,0,16">
      <StackPanel>
        <TextBlock Text="Ação:" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" Margin="0,0,0,6"/>
        <TextBlock Text="Realizar o update do Windows 10 para o Windows 11"
                   Foreground="#94a3b8" FontFamily="Consolas" FontSize="14"
                   Background="#0b1220" TextWrapping="Wrap" Margin="0,0,0,4"/>
        <TextBlock Text="Tempo Estimado: 20 a 30 minutos"
                   Foreground="#94a3b8" FontFamily="Consolas" FontSize="14"
                   Background="#0b1220" TextWrapping="Wrap"/>
      </StackPanel>
    </Border>

    <!-- Botões -->
    <DockPanel Grid.Row="3">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="BtnNow" Content="Executar agora" Margin="8,0,0,0" Padding="16,8"
                Background="#22c55e" Foreground="White" FontFamily="Segoe UI" FontWeight="SemiBold"
                BorderBrush="#16a34a" BorderThickness="1" Cursor="Hand"/>
        <Button Name="BtnDelay1" Content="Adiar 1 hora" Margin="8,0,0,0" Padding="16,8"
                Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI"
                BorderBrush="#374151" BorderThickness="1" Cursor="Hand"/>
        <Button Name="BtnDelay2" Content="Adiar 2 horas" Margin="8,0,0,0" Padding="16,8"
                Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI"
                BorderBrush="#374151" BorderThickness="1" Cursor="Hand"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

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
  $TitleTxt.Text = "Confirmação de execução"
  $SubTxt.Text   = "Chegou a hora agendada. Confirme a execução agora."
  $BtnDelay1.Visibility = 'Collapsed'
  $BtnDelay2.Visibility = 'Collapsed'
}

# -------- Impedir fechar com Alt+F4/ESC/Close --------
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
    [System.Windows.MessageBox]::Show(("Agendado para {0:dd/MM/yyyy HH:mm}. A janela será reaberta nessa hora para confirmar a execução." -f $runAt),"Agendado",'OK','Information') | Out-Null
  } catch {
    [System.Windows.MessageBox]::Show("Falha ao agendar:`n$($_.Exception.Message)","Erro",'OK','Error') | Out-Null
  }
  Allow-Close $window
  $window.Close()
})

$BtnDelay2.Add_Click({
  $BtnDelay1.IsEnabled=$false; $BtnDelay2.IsEnabled=$false; $BtnNow.IsEnabled=$false
  try {
    $runAt=(Get-Date).AddHours(2)
    New-RePromptTask -when $runAt
    [System.Windows.MessageBox]::Show(("Agendado para {0:dd/MM/yyyy HH:mm}. A janela será reaberta nessa hora para confirmar a execução." -f $runAt),"Agendado",'OK','Information') | Out-Null
  } catch {
    [System.Windows.MessageBox]::Show("Falha ao agendar:`n$($_.Exception.Message)","Erro",'OK','Error') | Out-Null
  }
  Allow-Close $window
  $window.Close()
})

$null = $window.ShowDialog()
