############################### Script de Update Windows 10 -> Windows 11 ###############################
#====================================================================
# Atualização com UI (agendamento/contagem), ISO reaproveitada (>=5GB),
# montagem preferencial em X:, UI na sessão do usuário atual via schtasks
# com wrapper .CMD para garantir quotes/redirecionamento corretos.
# Logs: C:\Temp\UpdateW11\ui.log  e  C:\Temp\UpdateW11\ui_task.log
#====================================================================

#requires -version 5.1
param(
  [switch]$ShowPromptOnly,  # usado pela tarefa para abrir SOMENTE a primeira UI
  [switch]$ShowForcedOnly   # usado pela tarefa para abrir SOMENTE a UI obrigatória (countdown)
)

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ----------------- CHECAGEM DO SISTEMA OPERACIONAL -----------------
$osCaption = (Get-CimInstance Win32_OperatingSystem).Caption
if ($osCaption -match "Windows 11") {
  Write-Host "✅ Já está no Windows 11. Nenhuma ação será tomada."
  if (-not ($ShowPromptOnly -or $ShowForcedOnly)) { exit 0 }
} elseif ($osCaption -notmatch "Windows 10") {
  Write-Host "⚠ Sistema não é Windows 10 nem 11. Abortando."
  if (-not ($ShowPromptOnly -or $ShowForcedOnly)) { exit 1 }
} else {
  if (-not ($ShowPromptOnly -or $ShowForcedOnly)) {
    Write-Host "▶ Sistema Windows 10 detectado. Continuando com o update..."
  }
}

# ----------------- BASE EM TEMP -----------------
$BaseTemp   = 'C:\Temp\UpdateW11'
if (-not (Test-Path $BaseTemp)) { New-Item -Path $BaseTemp -ItemType Directory -Force | Out-Null }

$AnswerPath = Join-Path $BaseTemp 'answer.txt'         # NOW / 3600 / 7200
$UiLogPath  = Join-Path $BaseTemp 'ui.log'
$TaskLog    = Join-Path $BaseTemp 'ui_task.log'

# ----------------- LOG SIMPLES -----------------
function Write-UiLog([string]$msg) {
  try {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $UiLogPath -Value "[$ts] $msg"
  } catch {}
}

# ----------------- HELPERS -----------------
function Write-Answer([string]$text) {
  try {
    $dir = Split-Path -Path $AnswerPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($AnswerPath, $text + [Environment]::NewLine, [Text.Encoding]::UTF8)
    Write-UiLog "Write-Answer: $text"
  } catch {}
}
function Read-Answer {
  try {
    if (Test-Path $AnswerPath) {
      $v = ([IO.File]::ReadAllText($AnswerPath,[Text.Encoding]::UTF8)).Trim()
      if ($v) { Write-UiLog "Read-Answer: $v" }
      return $v
    }
  } catch {}
  return $null
}

function Invoke-InSTA([ScriptBlock]$ScriptToRun) {
  # Garante STA; janela visível
  $PsExeFull = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
  if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $tmp = [IO.Path]::GetTempFileName().Replace(".tmp",".ps1")
    [IO.File]::WriteAllText($tmp, $ScriptToRun.ToString(), [Text.Encoding]::UTF8)
    Write-UiLog "Invoke-InSTA: relaunching in -STA ($tmp)"
    Start-Process -FilePath $PsExeFull -ArgumentList @(
      '-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Normal','-File', $tmp
    ) -Wait | Out-Null
    Remove-Item $tmp -ErrorAction SilentlyContinue
    return $true
  } else {
    try { & $ScriptToRun }
    catch {
      Write-UiLog ("Invoke-InSTA inner error: " + $_.Exception.Message)
      Start-Sleep -Seconds 3
    }
    return $false
  }
}

# ----------------- UI: PRIMEIRA PERGUNTA (NOW / 1h / 2h) -----------------
function Show-ChoicePrompt {
  $ui = {
    Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

    $Txt_WindowTitle='Agendar Execução'
    $Txt_HeaderTitle='Atualização Obrigatória'
    $Txt_HeaderSub='Você pode executar agora ou adiar por até 2 horas.'
    $Txt_ActionLabel='Ação:'
    $Txt_ActionLine1='Realizar o update do Windows 10 para o Windows 11'
    $Txt_ActionLine2='Tempo Estimado: 20 a 30 minutos'
    $Txt_BtnNow='Executar agora'
    $Txt_BtnDelay1='Adiar 1 hora'
    $Txt_BtnDelay2='Adiar 2 horas'

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
    <Border Grid.Row="0" CornerRadius="12" Background="#111827" Padding="16">
      <StackPanel>
        <TextBlock Text="$Txt_HeaderTitle" Foreground="#e5e7eb" FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Text="$Txt_HeaderSub" Foreground="#9ca3af" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>
    <Border Grid.Row="2" CornerRadius="12" Background="#0b1220" Padding="16" Margin="0,16,0,16">
      <StackPanel>
        <TextBlock Text="$Txt_ActionLabel" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" Margin="0,0,0,6"/>
        <TextBlock Text="$Txt_ActionLine1" Foreground="#94a3b8" FontFamily="Consolas" FontSize="14" Background="#0b1220" TextWrapping="Wrap" Margin="0,0,0,4"/>
        <TextBlock Text="$Txt_ActionLine2" Foreground="#94a3b8" FontFamily="Consolas" FontSize="14" Background="#0b1220" TextWrapping="Wrap"/>
      </StackPanel>
    </Border>
    <DockPanel Grid.Row="3">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="BtnNow" Content="$Txt_BtnNow" Margin="8,0,0,0" Padding="16,8" Background="#22c55e" Foreground="White" FontFamily="Segoe UI" FontWeight="SemiBold" BorderBrush="#16a34a" BorderThickness="1" Cursor="Hand"/>
        <Button Name="BtnDelay1" Content="$Txt_BtnDelay1" Margin="8,0,0,0" Padding="16,8" Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI" BorderBrush="#374151" BorderThickness="1" Cursor="Hand"/>
        <Button Name="BtnDelay2" Content="$Txt_BtnDelay2" Margin="8,0,0,0" Padding="16,8" Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI" BorderBrush="#374151" BorderThickness="1" Cursor="Hand"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    if (-not $window) { throw "Falha ao carregar a UI (ChoicePrompt)." }

    $window.Topmost = $true
    $window.Add_Loaded({ try { $this.Activate() | Out-Null } catch {} })

    $BtnNow    = $window.FindName('BtnNow')
    $BtnDelay1 = $window.FindName('BtnDelay1')
    $BtnDelay2 = $window.FindName('BtnDelay2')

    $script:closingHandler = [System.ComponentModel.CancelEventHandler]{ param($s,[System.ComponentModel.CancelEventArgs]$e) $e.Cancel = $true }
    $window.add_Closing($script:closingHandler)
    function Allow-Close([System.Windows.Window]$w){ if ($w -and $script:closingHandler){ $w.remove_Closing($script:closingHandler) } }

    $BtnNow.add_Click({ Write-Answer 'NOW';   Allow-Close $window; $window.Close() })
    $BtnDelay1.add_Click({ Write-Answer '3600'; Allow-Close $window; $window.Close() })
    $BtnDelay2.add_Click({ Write-Answer '7200'; Allow-Close $window; $window.Close() })

    Start-Sleep -Milliseconds 300
    $null = $window.ShowDialog()
  }
  Invoke-InSTA $ui | Out-Null
}

# ----------------- UI: COUNTDOWN OBRIGATÓRIO -----------------
function Show-ForcedPrompt {
  $ui = {
    Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

    $Txt_WindowTitle='Agendar Execução'
    $Txt_HeaderTitle='Atualização Obrigatória'
    $Txt_HeaderSub='Chegou a hora agendada. A execução é obrigatória.'
    $Txt_ActionLabel='Ação:'
    $Txt_ActionLine1='Realizar o update do Windows 10 para o Windows 11'
    $Txt_ActionLine2='Tempo Estimado: 20 a 30 minutos'
    $Txt_BtnNow='Executar agora'
    $TotalSeconds=300

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Txt_WindowTitle"
        Width="560" MinHeight="300" SizeToContent="Height"
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
    <Border Grid.Row="0" CornerRadius="12" Background="#111827" Padding="16">
      <StackPanel>
        <TextBlock Text="$Txt_HeaderTitle" Foreground="#e5e7eb" FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Text="$Txt_HeaderSub" Foreground="#f87171" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>
    <Border Grid.Row="2" CornerRadius="12" Background="#0b1220" Padding="16" Margin="0,16,0,16">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="220"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" Margin="0,0,12,0">
          <TextBlock Text="$Txt_ActionLabel" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" Margin="0,0,0,6"/>
          <TextBlock Text="$Txt_ActionLine1" Foreground="#94a3b8" FontFamily="Consolas" FontSize="14" Background="#0b1220" TextWrapping="Wrap" Margin="0,0,0,4"/>
          <TextBlock Text="$Txt_ActionLine2" Foreground="#94a3b8" FontFamily="Consolas" FontSize="14" Background="#0b1220" TextWrapping="Wrap"/>
        </StackPanel>
        <Border Grid.Column="1" Background="#0f172a" CornerRadius="12" Padding="12">
          <StackPanel>
            <TextBlock Text="Início automático em:" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="12" />
            <TextBlock Name="LblCountdown" Text="05:00" Foreground="#e5e7eb" FontFamily="Segoe UI" FontWeight="Bold" FontSize="28" Margin="0,4,0,10" HorizontalAlignment="Center"/>
            <ProgressBar Name="PbCountdown" Minimum="0" Maximum="$TotalSeconds" Height="16" Foreground="#22c55e" Background="#1f2937" BorderBrush="#111827" Value="0" />
            <TextBlock Text="Se nada for escolhido, será executado automaticamente." Foreground="#94a3b8" FontFamily="Segoe UI" FontSize="11" Margin="0,8,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>
    <DockPanel Grid.Row="3">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="BtnNow" Content="$Txt_BtnNow" Margin="8,0,0,0" Padding="16,8" Background="#22c55e" Foreground="White" FontFamily="Segoe UI" FontWeight="SemiBold" BorderBrush="#16a34a" BorderThickness="1" Cursor="Hand"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    if (-not $window) { throw "Falha ao carregar a UI (ForcedPrompt)." }

    $window.Topmost = $true
    $window.Add_Loaded({ try { $this.Activate() | Out-Null } catch {} })

    $BtnNow       = $window.FindName('BtnNow')
    $LblCountdown = $window.FindName('LblCountdown')
    $PbCountdown  = $window.FindName('PbCountdown')

    $script:closingHandler = [System.ComponentModel.CancelEventHandler]{ param($s,[System.ComponentModel.CancelEventArgs]$e) $e.Cancel = $true }
    $window.add_Closing($script:closingHandler)
    function Allow-Close([System.Windows.Window]$w){ if ($w -and $script:closingHandler){ $w.remove_Closing($script:closingHandler) } }

    $script:done = $false
    function Execute-Now {
      if ($script:done) { return }
      $script:done = $true
      try { $timer.Stop() } catch {}
      Write-Answer 'NOW'
      Allow-Close $window
      $window.Close()
    }

    $BtnNow.add_Click({ Execute-Now })
    $window.Add_KeyDown({ if ($_.Key -eq 'Enter') { Execute-Now } })

    $script:remaining = $TotalSeconds
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1)

    $updateUi = {
      $mm = [Math]::Floor($script:remaining / 60)
      $ss = $script:remaining % 60
      $LblCountdown.Text = ('{0:00}:{1:00}' -f $mm, $ss)
      $PbCountdown.Value = $TotalSeconds - $script:remaining
    }

    & $updateUi
    $timer.Add_Tick({
      if ($script:remaining -le 0) { Execute-Now; return }
      $script:remaining--
      & $updateUi
    })
    $timer.Start()

    Start-Sleep -Milliseconds 300
    $null = $window.ShowDialog()
  }
  Invoke-InSTA $ui | Out-Null
}

# ----------------- DESCOBRIR USUÁRIO/SID/SESSÃO ATIVOS -----------------
function Get-ActiveLogon {
  $result = [ordered]@{
    User=$null; Domain=$null; EffectiveDomain=$null; UserDomain=$null
    SID=$null; SessionId=$null
  }

  $quser = (& quser 2>$null)
  if ($quser) {
    $lines = $quser -split "`r?`n" | Where-Object { $_ -match '\s+(Active|Ativo)\s' }
    if ($lines) {
      $line = $lines | Select-Object -First 1
      $parts = ($line -replace '^\s*>\s*','') -split '\s+'
      $userToken = $parts[0]
      $idToken   = ($parts | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
      if ($userToken) {
        if ($userToken -match '\\') {
          $result.UserDomain = $userToken
          $result.Domain,$result.User = $userToken -split '\\',2
        } else {
          $result.User = $userToken
          $result.Domain = $env:USERDOMAIN
          $result.UserDomain = "$($result.Domain)\$($result.User)"
        }
      }
      if ($idToken) { $result.SessionId = [int]$idToken }
    }
  }

  if (-not $result.UserDomain) {
    $ud = (Get-CimInstance Win32_ComputerSystem).UserName
    if ($ud) {
      $result.UserDomain = $ud
      $result.Domain,$result.User = $ud -split '\\',2
    }
  }

  $machine = (Get-CimInstance Win32_ComputerSystem).Name
  $domain  = $result.Domain
  if (-not $domain -or $domain -eq 'WORKGROUP') { $domain = $machine }
  $result.EffectiveDomain = $domain

  if ($result.User) {
    try {
      $nt = New-Object System.Security.Principal.NTAccount("$($result.EffectiveDomain)\$($result.User)")
      $sid = $nt.Translate([System.Security.Principal.SecurityIdentifier])
      $result.SID = $sid.Value
    } catch { $result.SID = $null }
  }

  return [pscustomobject]$result
}

# ----------------- EXECUTAR UI NA SESSÃO ATIVA (com wrapper .CMD) -----------------
function Start-UiInActiveSession([ValidateSet('choice','forced')]$Mode, [int]$TimeoutSec = 900) {
  $info = Get-ActiveLogon
  if (-not $info.User -or -not $info.EffectiveDomain) {
    Write-Host "⚠ Nenhum usuário ativo encontrado. Não será possível exibir UI." -ForegroundColor Yellow
    Write-UiLog "Start-UiInActiveSession: nenhum usuário ativo"
    return $false
  }

  $ru = "$($info.EffectiveDomain)\$($info.User)"  # PC\user (workgroup) ou DOM\user (AD)
  Write-Host "👤 Usuário ativo: $ru  (SessãoID=$($info.SessionId))"
  Write-UiLog  "Usuário ativo: $ru | SessãoID=$($info.SessionId)"

  $taskName = "\GDL\UpdateW11-UI-$([guid]::NewGuid())"

  # Garante script físico quando rodou via IEX
  $psPath = $PSCommandPath
  if (-not $psPath) {
    $psPath = Join-Path $BaseTemp "UpdateW11_Run.ps1"
    $self = $MyInvocation.MyCommand.Definition
    [IO.File]::WriteAllText($psPath, $self, [Text.Encoding]::UTF8)
    Write-UiLog "PSCommandPath inexistente; script salvo em $psPath"
  }

  $argSwitch = if ($Mode -eq 'choice') { '-ShowPromptOnly' } else { '-ShowForcedOnly' }
  $psExe     = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

  # Cria um wrapper .CMD para evitar problemas de aspas/escapes no /TR
  $wrapperPath = Join-Path $BaseTemp ("launch_ui_{0}.cmd" -f $Mode)
  $wrapper = @(
    '@echo off'
    'setlocal'
    ('"{0}" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Normal -File "{1}" {2} >> "{3}" 2>>&1' -f $psExe, $psPath, $argSwitch, $TaskLog)
  ) -join "`r`n"
  [IO.File]::WriteAllText($wrapperPath, $wrapper, [Text.Encoding]::ASCII)

  # /SC ONCE pede horário futuro: agora +2 min
  $startTime = (Get-Date).AddMinutes(2).ToString('HH:mm')

  $createCmd = @(
    '/Create','/TN', $taskName,
    '/SC','ONCE','/ST', $startTime,
    '/TR', "`"$wrapperPath`"",
    '/RL','LIMITED',   # evita desktop elevado/UAC
    '/RU', $ru,
    '/IT',
    '/F'
  )

  try {
    schtasks @createCmd | Out-Null
    Write-UiLog "Tarefa criada: $taskName | RU=$ru | ST=$startTime | TR=$wrapperPath"
  } catch {
    Write-UiLog "Falha ao criar tarefa: $($_.Exception.Message)"
    Write-Host "❌ Falha ao criar tarefa para UI: $($_.Exception.Message)" -ForegroundColor Red
    return $false
  }

  # Limpa resposta anterior e dispara a tarefa
  Remove-Item $AnswerPath -ErrorAction SilentlyContinue
  schtasks /Run /TN $taskName | Out-Null
  Write-UiLog "Tarefa executada: $taskName"

  # Espera resposta ou timeout
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    if (Read-Answer) { break }
  }

  schtasks /Delete /TN $taskName /F | Out-Null
  Write-UiLog "Tarefa deletada: $taskName"

  return [bool](Read-Answer)
}

# ----------------- PASSO 1: Download/Montagem da ISO (corrigido) -----------------
function Do-Step1 {
  param(
    [Parameter(Mandatory=$true)][string]$IsoUrl,
    [string]$Dest = $BaseTemp,
    [string]$IsoName = 'Win11_24H2_BrazilianPortuguese_x64.iso',
    [UInt64]$MinSizeBytes = 5GB
  )

  New-Item -ItemType Directory -Path $Dest -Force | Out-Null
  $isoPath = Join-Path $Dest $IsoName

  # 0) Se nossa ISO já estiver montada, desmonta (sempre com -ImagePath)
  try {
    $imgMine = Get-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    if ($imgMine -and $imgMine.Attached) {
      Write-Host "⏏ Desmontando ISO anterior deste script..."
      Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 2
    }
  } catch {}

  # 1) Verifica/baixa ISO
  $needDownload = $true
  if (Test-Path $isoPath) {
    try {
      $size = (Get-Item $isoPath).Length
      if ($size -ge $MinSizeBytes) {
        Write-Host "⚡ ISO válida encontrada em $isoPath — pulando download."
        $needDownload = $false
      } else {
        Write-Host "🧹 ISO existente parece incompleta ($size bytes). Rebaixando..."
        Remove-Item $isoPath -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }

  if ($needDownload) {
    Write-Host "⏬ Baixando ISO..."
    Start-BitsTransfer -Source $IsoUrl -Destination $isoPath
    $size = (Get-Item $isoPath).Length
    if ($size -lt $MinSizeBytes) { throw "Download da ISO concluído, porém tamanho inesperado ($size bytes < $MinSizeBytes)." }
    Write-Host "✅ Download OK ($([Math]::Round($size/1GB,2)) GB)."
  }

  # 2) Se X: estiver ocupado por OUTRA coisa, tenta liberar a letra
  $volX = Get-Volume -DriveLetter X -ErrorAction SilentlyContinue
  if ($volX) {
    try {
      Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='X:'" |
        Set-CimInstance -Property @{ DriveLetter = $null } -ErrorAction SilentlyContinue | Out-Null
      Start-Sleep -Seconds 1
    } catch {}
  }

  # 3) Monta nossa ISO
  Write-Host "💿 Montando ISO..."
  Mount-DiskImage -ImagePath $isoPath | Out-Null

  # 4) Descobre a letra e tenta ajustar para X:
  $img = Get-DiskImage -ImagePath $isoPath
  $vol = $img | Get-Volume
  $assigned = $vol.DriveLetter + ':'

  if ($assigned -ne 'X:') {
    try {
      Get-CimInstance -Class Win32_Volume |
        Where-Object { $_.DriveLetter -eq $assigned } |
        Set-CimInstance -Property @{ DriveLetter = 'X:' } -ErrorAction Stop | Out-Null
      $assigned = 'X:'
    } catch {
      Write-Host "ℹ Não foi possível usar X:. Usando $assigned."
    }
  }

  Write-UiLog "ISO pronta em $assigned (path=$isoPath)"
  Write-Host "✅ ISO pronta em $assigned"
  return $assigned
}

# ----------------- PASSO 2: Setup.exe -----------------
function Do-Step2 {
  param(
    [string]$Drive = 'X:',
    [string]$LogPath = (Join-Path $BaseTemp 'logs.log')
  )
  Write-Host "▶ Iniciando atualização do Windows..."
  Write-UiLog "Start-Process Setup.exe ($Drive)"
  $setupArgs = "/auto upgrade /DynamicUpdate disable /ShowOOBE none /noreboot /compat IgnoreWarning /BitLocker TryKeepActive /EULA accept /CopyLogs `"$LogPath`""
  Start-Process -FilePath (Join-Path $Drive 'Setup.exe') -ArgumentList $setupArgs -Wait
  Write-Host "✔ Instalação iniciada. Reiniciando máquina..."
  Write-UiLog "Restart-Computer em 10s"
  Restart-Computer -Timeout 10 -Force
}

# ============================== ROTINAS CHAMADAS PELAS TAREFAS ==============================
if ($ShowPromptOnly) { Write-UiLog "ShowPromptOnly iniciado"; Show-ChoicePrompt;  Write-UiLog "ShowPromptOnly finalizado"; exit 0 }
if ($ShowForcedOnly) { Write-UiLog "ShowForcedOnly iniciado"; Show-ForcedPrompt; Write-UiLog "ShowForcedOnly finalizado"; exit 0 }

# ============================== FLUXO PRINCIPAL ==============================
$isoUrl  = 'https://temp-arco-itops.s3.us-east-1.amazonaws.com/Win11_24H2_BrazilianPortuguese_x64.iso'
$driveX  = Do-Step1 -IsoUrl $isoUrl -Dest $BaseTemp

Remove-Item $AnswerPath -ErrorAction SilentlyContinue
$shown = Start-UiInActiveSession -Mode 'choice' -TimeoutSec 1800
if (-not $shown) {
  Write-Host "⚠ Não foi possível exibir a UI ao usuário atual. Prosseguindo com execução obrigatória."
  Write-UiLog "Falha ao exibir UI inicial; fallback NOW"
  Write-Answer 'NOW'
}

$choice = Read-Answer
switch ($choice) {
  'NOW'   {
    Remove-Item $AnswerPath -ErrorAction SilentlyContinue
    Start-UiInActiveSession -Mode 'forced' -TimeoutSec 600 | Out-Null
    Do-Step2 -Drive $driveX
  }
  '3600'  {
    Write-Host "⏳ Aguardando 1 hora antes da execução..."; Write-UiLog "Delay 3600s"
    Start-Sleep -Seconds 60
    Remove-Item $AnswerPath -ErrorAction SilentlyContinue
    Start-UiInActiveSession -Mode 'forced' -TimeoutSec 600 | Out-Null
    Do-Step2 -Drive $driveX
  }
  '7200'  {
    Write-Host "⏳ Aguardando 2 horas antes da execução..."; Write-UiLog "Delay 7200s"
    Start-Sleep -Seconds 120
    Remove-Item $AnswerPath -ErrorAction SilentlyContinue
    Start-UiInActiveSession -Mode 'forced' -TimeoutSec 600 | Out-Null
    Do-Step2 -Drive $driveX
  }
  default {
    Write-Host "⚠ Resposta inválida ou ausente. Prosseguindo com execução obrigatória."
    Write-UiLog "Resposta inválida/ausente; executando NOW"
    Remove-Item $AnswerPath -ErrorAction SilentlyContinue
    Start-UiInActiveSession -Mode 'forced' -TimeoutSec 600 | Out-Null
    Do-Step2 -Drive $driveX
  }
}
