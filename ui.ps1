#requires -version 5.1
<#
  Tela de agendamento/execução com UI moderna (WPF)
  - Executar agora => roda "msg * Teste"
  - Adiar 1h / 2h => cria Tarefa Agendada que reabre esta mesma UI para confirmar/rodar
  - Na reabertura (via -RePrompt), **não permite adiar novamente** — apenas Executar agora
#>

param(
  [switch]$RePrompt  # setado quando a tarefa reabre a UI para confirmação final
)

# ============ CONFIG ============
$TaskName        = "GDL-AgendarScriptTeste"
$PsExeFull       = Join-Path $PSHOME 'powershell.exe'   # caminho absoluto do PowerShell
$ScriptPath      = "C:\Scripts\Agendar-Script.ps1"      # <-- AJUSTE para onde você salvar este script
$CommandToRun    = { & msg * 'Teste' }                  # <-- Troque pelo comando real quando quiser
# =================================

# ---------- Helpers ----------
function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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

# --------- Agendamento robusto ----------
function New-RePromptTask {
  param([datetime]$when)

  Ensure-SchedulerRunning

  if (-not (Test-Path -LiteralPath $PsExeFull)) {
    throw "powershell.exe não encontrado em '$PsExeFull'."
  }
  if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "Script não encontrado em '$ScriptPath'. Salve este arquivo nesse caminho ou ajuste `$ScriptPath."
  }

  $runLevel = if (Test-IsAdmin) { 'HIGHEST' } else { 'NORMAL' }
  $sd = $when.ToString('dd/MM/yyyy')  # pt-BR
  $st = $when.ToString('HH:mm')       # 24h

  # /TR precisa ser um ÚNICO valor (string) com EXE entre aspas + argumentos
  $trValue = '"' + $PsExeFull + '" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $ScriptPath + '" -RePrompt'

  # Remove tarefa anterior se existir (silencioso)
  try { & schtasks.exe /Delete /TN $TaskName /F | Out-Null } catch {}

  # Monta os parâmetros em ARRAY; cada item é um token seguro
  $args = @(
    '/Create',
    '/TN', $TaskName,
    '/TR', $trValue,
    '/SC', 'ONCE',
    '/SD', $sd,
    '/ST', $st,
    '/F',
    '/RL', $runLevel,
    '/IT'          # interativo: exige usuário logado no disparo para mostrar a UI
  )

  $output = & schtasks.exe @args 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Falha ao criar a tarefa. Saída do schtasks:`n$output"
  }
}

function Remove-RePromptTask {
  try { & schtasks.exe /Delete /TN $TaskName /F | Out-Null } catch {}
}

# --------- Execução do comando ----------
function Run-Now {
  Remove-RePromptTask
  try {
    & $CommandToRun
  } catch {
    [System.Windows.MessageBox]::Show("Falha ao executar o comando:`n$($_.Exception.Message)", "Erro", 'OK', 'Error') | Out-Null
  }
}

# --------- UI (WPF) ----------
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

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

    <!-- Cabeçalho -->
    <Border Grid.Row="0" CornerRadius="12" Background="#111827" Padding="16" >
      <StackPanel>
        <TextBlock Name="TitleText" Text="Atualização Obrigatória" Foreground="#e5e7eb" FontFamily="Segoe UI"
                   FontWeight="Bold" FontSize="20"/>
        <TextBlock Name="SubText" Text="Você pode executar agora ou adiar por até 2 horas."
                   Foreground="#9ca3af" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>

    <!-- Corpo -->
    <Border Grid.Row="2" CornerRadius="12" Background="#0b1220" Padding="16" Margin="0,16,0,16">
      <StackPanel>
        <TextBlock Text="Ação:" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" Margin="0,0,0,6"/>
        <TextBlock Text='Realizar o update do Windows 10 para o Windows 11' Foreground="#94a3b8" FontFamily="Consolas" FontSize="14" Background="#0b1220"/>
        <TextBlock Text='Tempo Estimado: 20 a 30 minutos' Foreground="#94a3b8" FontFamily="Consolas" FontSize="14" Background="#0b1220"/>
      </StackPanel>
    </Border>

    <!-- Botões -->
    <DockPanel Grid.Row="3">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" >
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

# --------- Criar Janela ---------
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$BtnNow   = $window.FindName('BtnNow')
$BtnDelay1= $window.FindName('BtnDelay1')
$BtnDelay2= $window.FindName('BtnDelay2')
$TitleTxt = $window.FindName('TitleText')
$SubTxt   = $window.FindName('SubText')

# Se foi reaberto pela tarefa (RePrompt), desabilita/remova botões de adiar
if ($RePrompt) {
  $TitleTxt.Text = "Confirmação de execução"
  $SubTxt.Text   = "Chegou a hora agendada. Confirme a execução agora."
  $BtnDelay1.Visibility = 'Collapsed'
  $BtnDelay2.Visibility = 'Collapsed'
}

# --------- Handlers ----------
$BtnNow.Add_Click({
  $window.Close()
  Run-Now
})

$BtnDelay1.Add_Click({
  $BtnDelay1.IsEnabled = $false; $BtnDelay2.IsEnabled = $false; $BtnNow.IsEnabled = $false
  try {
    $runAt = (Get-Date).AddHours(1)
    New-RePromptTask -when $runAt
    [System.Windows.MessageBox]::Show("Agendado para $($runAt.ToString('dd/MM/yyyy HH:mm')). A janela será reaberta nessa hora para confirmar a execução.", "Agendado", 'OK', 'Information') | Out-Null
  } catch {
    [System.Windows.MessageBox]::Show("Falha ao agendar: `n$($_.Exception.Message)", "Erro", 'OK', 'Error') | Out-Null
  }
  $window.Close()
})

$BtnDelay2.Add_Click({
  $BtnDelay1.IsEnabled = $false; $BtnDelay2.IsEnabled = $false; $BtnNow.IsEnabled = $false
  try {
    $runAt = (Get-Date).AddHours(2)
    New-RePromptTask -when $runAt
    [System.Windows.MessageBox]::Show("Agendado para $($runAt.ToString('dd/MM/yyyy HH:mm')). A janela será reaberta nessa hora para confirmar a execução.", "Agendado", 'OK', 'Information') | Out-Null
  } catch {
    [System.Windows.MessageBox]::Show("Falha ao agendar: `n$($_.Exception.Message)", "Erro", 'OK', 'Error') | Out-Null
  }
  $window.Close()
})

# Mostrar janela
$null = $window.ShowDialog()
