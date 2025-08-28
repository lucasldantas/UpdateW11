#requires -version 5.1
param([switch]$UiOnly)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ====================== CONFIG / TEXTOS (edite aqui) ======================
$AnswerFile   = 'C:\ProgramData\Answer.txt'
$TaskPrefix   = 'ShowChoiceUI'              # prefixo das tarefas por sessão
$PsExe        = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') { $PsExe = "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" }

# textos
$Txt_WindowTitle    = 'Agendar Execução'
$Txt_HeaderTitle    = 'Atualização obrigatória'
$Txt_HeaderSubtitle = 'Você pode executar agora ou adiar por até 2 horas.'
$Txt_ActionLabel    = 'Ação:'
$Txt_ActionLine1    = 'Realizar o update do Windows 10 para o Windows 11'
$Txt_ActionLine2    = 'Tempo Estimado: 20 a 30 minutos'

$Txt_BtnNow         = 'Executar agora'
$Txt_Btn1H          = 'Adiar 1 hora'
$Txt_Btn2H          = 'Adiar 2 horas'
# ==========================================================================

# --------------------------------------------------------------------------
# MODO UI (mostra a janela ao usuário logado; grava C:\ProgramData\Answer.txt)
# --------------------------------------------------------------------------
if ($UiOnly) {
  try {
    # Garante STA
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
      Start-Process -FilePath $PsExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$PSCommandPath`"","-UiOnly") | Out-Null
      return
    }

    Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Txt_WindowTitle"
        Width="560" MinHeight="300" SizeToContent="Height"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" Background="#0f172a"
        WindowStyle="None" ShowInTaskbar="True"
        AllowsTransparency="False" Topmost="True">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Cabeçalho retangular (sem cantos arredondados) -->
    <Border Grid.Row="0" Background="#111827" Padding="16">
      <StackPanel>
        <TextBlock Name="TitleText" Text="$Txt_HeaderTitle" Foreground="#e5e7eb"
                   FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Name="SubText" Text="$Txt_HeaderSubtitle"
                   Foreground="#9ca3af" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>

    <!-- Corpo -->
    <Border Grid.Row="1" Background="#0b1220" Padding="16" Margin="0,16,0,16">
      <StackPanel>
        <TextBlock Text="$Txt_ActionLabel" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" Margin="0,0,0,6"/>
        <TextBlock Text="$Txt_ActionLine1" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" TextWrapping="Wrap" Margin="0,0,0,4"/>
        <TextBlock Text="$Txt_ActionLine2" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" TextWrapping="Wrap"/>
      </StackPanel>
    </Border>

    <!-- Botões retangulares -->
    <DockPanel Grid.Row="2">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="BtnNow" Content="$Txt_BtnNow" Margin="8,0,0,0" Padding="16,8"
                Background="#0078d4" Foreground="White" FontFamily="Segoe UI" FontWeight="SemiBold"
                BorderBrush="#0a5ea6" BorderThickness="1" Cursor="Hand" Width="170" Height="40"/>
        <Button Name="Btn1H" Content="$Txt_Btn1H" Margin="8,0,0,0" Padding="16,8"
                Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI"
                BorderBrush="#374151" BorderThickness="1" Cursor="Hand" Width="170" Height="40"/>
        <Button Name="Btn2H" Content="$Txt_Btn2H" Margin="8,0,0,0" Padding="16,8"
                Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI"
                BorderBrush="#374151" BorderThickness="1" Cursor="Hand" Width="170" Height="40"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@

    # Carrega janela
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # Impede fechar (sem escolha) — bloqueia Alt+F4 e X (não há X visível)
    $script:closingHandler = [System.ComponentModel.CancelEventHandler]{ param($s,[System.ComponentModel.CancelEventArgs]$e) $e.Cancel = $true }
    $window.add_Closing($script:closingHandler)
    function Allow-Close([System.Windows.Window]$win) { if ($win -and $script:closingHandler) { $win.remove_Closing($script:closingHandler) } }

    # Arrastar pela janela
    $window.Add_MouseLeftButtonDown({
      if ($_.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        try { $window.DragMove() } catch {}
      }
    })

    # Garante foco
    $window.Add_Loaded({
      try {
        $this.Activate() | Out-Null
        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(120)
        $t.Add_Tick({ param($s,$e) try { $this.Activate() | Out-Null } catch {} ; $s.Stop() })
        $t.Start()
      } catch {}
    })

    $BtnNow = $window.FindName('BtnNow')
    $Btn1H  = $window.FindName('Btn1H')
    $Btn2H  = $window.FindName('Btn2H')

    function Write-Answer([string]$val) {
      try {
        if (-not (Test-Path (Split-Path $AnswerFile))) { New-Item -ItemType Directory -Path (Split-Path $AnswerFile) -Force | Out-Null }
        [IO.File]::WriteAllText($AnswerFile, $val, [Text.Encoding]::UTF8)
      } catch {}
      Allow-Close $window
      $window.Close()
    }

    $BtnNow.Add_Click({ Write-Answer 'NOW' })
    $Btn1H.Add_Click({ Write-Answer '1H'  })
    $Btn2H.Add_Click({ Write-Answer '2H'  })

    $null = $window.ShowDialog()
  }
  catch {
    try {
      Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
      [System.Windows.MessageBox]::Show($_.Exception.Message, 'Erro na UI','OK','Error') | Out-Null
    } catch {}
  }
  return
}

# --------------------------------------------------------------------------
# MODO LAUNCHER (padrão): dispara a UI em TODAS as sessões com Explorer
# --------------------------------------------------------------------------

# Serviço Agendador
try {
  $svc = Get-Service -Name Schedule -ErrorAction Stop
  if ($svc.Status -ne 'Running') { Start-Service Schedule -ErrorAction Stop }
} catch {}

# Descobre usuários logados (usa explorer.exe, que só existe em sessões interativas)
$targets = @()
try {
  $procs = Get-Process -Name explorer -IncludeUserName -ErrorAction SilentlyContinue
  foreach ($p in $procs) {
    if ($p.UserName) {
      $targets += [pscustomobject]@{ User=$p.UserName; SessionId=$p.SessionId }
    }
  }
} catch {}

# Fallback: 'quser' para achar sessões ativas, caso IncludeUserName não esteja disponível
if (-not $targets -or $targets.Count -eq 0) {
  try {
    $lines = (quser) 2>$null
    foreach ($ln in $lines) {
      if ($ln -match '^\s*(\S+)\s+(\S+)\s+(\d+)\s+(Active|Ativa)') {
        $u = $Matches[1]; $sid = [int]$Matches[3]
        $dom = $env:USERDOMAIN
        if ([string]::IsNullOrWhiteSpace($dom)) { $dom = $env:COMPUTERNAME }
        $targets += [pscustomobject]@{ User="$dom\$u"; SessionId=$sid }
      }
    }
  } catch {}
}

if (-not $targets -or $targets.Count -eq 0) {
  Write-Warning "Nenhum usuário interativo encontrado."
  # Ainda assim, se não houver ninguém, grava marcador:
  if (-not (Test-Path $AnswerFile)) { try { [IO.File]::WriteAllText($AnswerFile,'NOUSER',[Text.Encoding]::UTF8) } catch {} }
  return
}

# Cria tarefa ONCE para cada usuário e dispara
$now = Get-Date
$start = $now.AddMinutes(1)  # agendar 1 min à frente (schtasks exige minuto cheio)
$st = $start.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
$sd = $start.ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)

$ok = 0; $fail = 0
$usedNames = @{}

foreach ($t in $targets | Sort-Object -Property SessionId -Unique) {
  $ru = $t.User
  if ([string]::IsNullOrWhiteSpace($ru)) { continue }

  # nome de tarefa único por sessão
  $tn = "$TaskPrefix-$($t.SessionId)"
  if ($usedNames[$tn]) { $tn = "$TaskPrefix-$($t.SessionId)-$([guid]::NewGuid().ToString('N').Substring(0,6))" }
  $usedNames[$tn] = $true

  $tr = "`"$PsExe`" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`" -UiOnly"

  try {
    schtasks /Delete /TN $tn /F 2>$null | Out-Null
  } catch {}

  $args = @('/Create','/TN',$tn,'/TR',$tr,'/SC','ONCE','/SD',$sd,'/ST',$st,'/RL','HIGHEST','/RU',$ru,'/IT','/F')
  $out = schtasks @args 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Falha ao criar tarefa para $ru: $($out -join ' ')"
    $fail++
    continue
  }

  schtasks /Run /TN $tn 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) { $ok++ } else { $fail++ }

  # limpeza opcional (deixa o agendamento para histórico se quiser remover esta linha)
  Start-Sleep -Milliseconds 200
  try { schtasks /Delete /TN $tn /F 2>$null | Out-Null } catch {}
}

Write-Host ("Sessões alvo: {0} | Disparadas com sucesso: {1} | Falhas: {2}" -f $targets.Count, $ok, $fail)
if ($fail -gt 0) { Write-Warning "Algumas sessões não aceitaram a UI (sem Explorer ou sem interação?)" }
