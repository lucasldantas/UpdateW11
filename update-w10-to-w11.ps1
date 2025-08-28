############################### Script de Update Windows 10 -> Windows 11 ###############################
#====================================================================
# Script de Update Windows 10 -> Windows 11 (com UI de agendamento)
# Autor: Lucas Lopes Dantas (adaptação com funções de UI e fluxo)
# *** Usa SOMENTE C:\Temp\UpdateW11 para arquivos temporários ***
# *** Reaproveita ISO se já existir e valida tamanho mínimo (5 GB) ***
# *** Garante que a UI aparece no USUÁRIO ATUAL via Tarefa Interativa ***
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
}
elseif ($osCaption -notmatch "Windows 10") {
    Write-Host "⚠ Sistema não é Windows 10 nem 11. Abortando."
    if (-not ($ShowPromptOnly -or $ShowForcedOnly)) { exit 1 }
}
else {
    if (-not ($ShowPromptOnly -or $ShowForcedOnly)) {
      Write-Host "▶ Sistema Windows 10 detectado. Continuando com o update..."
    }
}

# ----------------- BASE EM TEMP -----------------
$BaseTemp   = 'C:\Temp\UpdateW11'
if (-not (Test-Path $BaseTemp)) { New-Item -Path $BaseTemp -ItemType Directory -Force | Out-Null }

# Tudo que antes ia para ProgramData agora vai para TEMP
$AnswerPath = Join-Path $BaseTemp 'answer.txt'  # Onde salvamos NOW / 3600 / 7200

# ----------------- HELPERS -----------------
function Write-Answer([string]$text) {
  try {
    $dir = Split-Path -Path $AnswerPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($AnswerPath, $text + [Environment]::NewLine, [Text.Encoding]::UTF8)
  } catch {}
}
function Read-Answer {
  try {
    if (Test-Path $AnswerPath) {
      return ([IO.File]::ReadAllText($AnswerPath,[Text.Encoding]::UTF8)).Trim()
    }
  } catch {}
  return $null
}

function Invoke-InSTA([ScriptBlock]$ScriptToRun) {
  # Garante STA para WPF; se não for, relança powershell.exe em STA e sai
  $PsExeFull = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
  if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $tmp = [IO.Path]::GetTempFileName().Replace(".tmp",".ps1")
    [IO.File]::WriteAllText($tmp, $ScriptToRun.ToString(), [Text.Encoding]::UTF8)
    Start-Process -FilePath $PsExeFull -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File', $tmp) -Wait | Out-Null
    Remove-Item $tmp -ErrorAction SilentlyContinue
    return $true
  }
  else {
    & $ScriptToRun
    return $false
  }
}

# ----------------- UI: PRIMEIRA PERGUNTA (NOW / 1h / 2h) -----------------
function Show-ChoicePrompt {
  $ui = {
    Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

    $Txt_WindowTitle   = 'Agendar Execução'
    $Txt_HeaderTitle   = 'Atualização Obrigatória'
    $Txt_HeaderSub     = 'Você pode executar agora ou adiar por até 2 horas.'
    $Txt_ActionLabel   = 'Ação:'
    $Txt_ActionLine1   = 'Realizar o update do Windows 10 para o Windows 11'
    $Txt_ActionLine2   = 'Tempo Estimado: 20 a 30 minutos'
    $Txt_BtnNow        = 'Executar agora'
    $Txt_BtnDelay1     = 'Adiar 1 hora'
    $Txt_BtnDelay2     = 'Adiar 2 horas'

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
        <TextBlock Text="$Txt_HeaderTitle" Foreground="#e5e7eb"
                   FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Text="$Txt_HeaderSub"
                   Foreground="#9ca3af" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>

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
    if (-not $window) { throw "Falha ao carregar a UI (ChoicePrompt)." }

    $window.Topmost = $true
    $window.Add_Loaded({ try { $this.Activate() | Out-Null } catch {} })

    $BtnNow    = $window.FindName('BtnNow')
    $BtnDelay1 = $window.FindName('BtnDelay1')
    $BtnDelay2 = $window.FindName('BtnDelay2')

    $script:closingHandler = [System.ComponentModel.CancelEventHandler]{ param($s,[System.ComponentModel.CancelEventArgs]$e) $e.Cancel = $true }
    $window.add_Closing($script:closingHandler)
    function Allow-Close([System.Windows.Window]$w){ if ($w -and $script:closingHandler){ $w.remove_Closing($script:closingHandler) } }

    $BtnNow.add_Click({
      Write-Answer 'NOW'
      Allow-Close $window
      $window.Close()
    })
    $BtnDelay1.add_Click({
      Write-Answer '3600'
      Allow-Close $window
      $window.Close()
    })
    $BtnDelay2.add_Click({
      Write-Answer '7200'
      Allow-Close $window
      $window.Close()
    })

    $null = $window.ShowDialog()
  }
  Invoke-InSTA $ui | Out-Null
}

# ----------------- UI: PERGUNTA DE EXECUÇÃO (COUNTDOWN 5 min) -----------------
function Show-ForcedPrompt {
  $ui = {
    Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

    $Txt_WindowTitle   = 'Agendar Execução'
    $Txt_HeaderTitle   = 'Atualização Obrigatória'
    $Txt_HeaderSub     = 'Chegou a hora agendada. A execução é obrigatória.'
    $Txt_ActionLabel   = 'Ação:'
    $Txt_ActionLine1   = 'Realizar o update do Windows 10 para o Windows 11'
    $Txt_ActionLine2   = 'Tempo Estimado: 20 a 30 minutos'
    $Txt_BtnNow        = 'Executar agora'
    $TotalSeconds      = 300

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
        <TextBlock Text="$Txt_HeaderTitle" Foreground="#e5e7eb"
                   FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Text="$Txt_HeaderSub"
                   Foreground="#f87171" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
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
          <TextBlock Text="$Txt_ActionLine1"
                     Foreground="#94a3b8" FontFamily="Consolas" FontSize="14"
                     Background="#0b1220" TextWrapping="Wrap" Margin="0,0,0,4"/>
          <TextBlock Text="$Txt_ActionLine2"
                     Foreground="#94a3b8" FontFamily="Consolas" FontSize="14"
                     Background="#0b1220" TextWrapping="Wrap"/>
        </StackPanel>

        <Border Grid.Column="1" Background="#0f172a" CornerRadius="12" Padding="12">
          <StackPanel>
            <TextBlock Text="Início automático em:" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="12" />
            <TextBlock Name="LblCountdown" Text="05:00" Foreground="#e5e7eb" FontFamily="Segoe UI"
                       FontWeight="Bold" FontSize="28" Margin="0,4,0,10" HorizontalAlignment="Center"/>
            <ProgressBar Name="PbCountdown" Minimum="0" Maximum="$TotalSeconds" Height="16"
                         Foreground="#22c55e" Background="#1f2937" BorderBrush="#111827"
                         Value="0" />
            <TextBlock Text="Se nada for escolhido, será executado automaticamente."
                       Foreground="#94a3b8" FontFamily="Segoe UI" FontSize="11" Margin="0,8,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>

    <DockPanel Grid.Row="3">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="BtnNow" Content="$Txt_BtnNow" Margin="8,0,0,0" Padding="16,8"
                Background="#22c55e" Foreground="White" FontFamily="Segoe UI" FontWeight="SemiBold"
                BorderBrush="#16a34a" BorderThickness="1" Cursor="Hand"/>
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

    $null = $window.ShowDialog()
  }
  Invoke-InSTA $ui | Out-Null
}

# ----------------- DESCOBRIR USUÁRIO/SID/SESSÃO ATIVOS -----------------
function Get-ActiveLogon {
  $result = [ordered]@{ User=$null; Domain=$null; UserDomain=$null; SID=$null; SessionId=$null }
  $quser = (& quser 2>$null)
  if ($quser) {
    $lines = $quser -split "`r?`n" | Where-Object { $_ -match '\s+Active\s' }
    if ($lines) {
      $line = $lines | Select-Object -First 1
      $parts = $line -split '\s+'
      # formato típico: USERNAME  SESSIONNAME  ID  STATE  IDLE  LOGON TIME
      $user = $parts[0]
      $id   = ($parts | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
      if ($user) {
        if ($user -match '\\') {
          $result.UserDomain = $user
          $result.Domain,$result.User = $user -split '\\',2
        } else {
          $result.User = $user
          $result.Domain = $env:USERDOMAIN
          $result.UserDomain = "$($result.Domain)\$($result.User)"
        }
      }
      if ($id) { $result.SessionId = [int]$id }
    }
  }
  if (-not $result.UserDomain) {
    $ud = (Get-CimInstance Win32_ComputerSystem).UserName
    if ($ud) {
      $result.UserDomain = $ud
      $result.Domain,$result.User = $ud -split '\\',2
    }
  }
  if ($result.UserDomain) {
    try {
      $nt = New-Object System.Security.Principal.NTAccount($result.UserDomain)
      $sid = $nt.Translate([System.Security.Principal.SecurityIdentifier])
      $result.SID = $sid.Value
    } catch {}
  }
  return [pscustomobject]$result
}

# ----------------- EXECUTAR UI NA SESSÃO ATIVA VIA TAREFA -----------------
function Start-UiInActiveSession([ValidateSet('choice','forced')]$Mode, [int]$TimeoutSec = 900) {
  $info = Get-ActiveLogon
  if (-not $info.UserDomain) {
    Write-Host "⚠ Nenhum usuário ativo encontrado. Não será possível exibir UI." -ForegroundColor Yellow
    return $false
  }
  Write-Host "👤 Usuário ativo: $($info.UserDomain)  (SID=$($info.SID))  SessãoID=$($info.SessionId)"

  $taskName = "\GDL\UpdateW11-UI-$([guid]::NewGuid())"
  $tmpXml   = Join-Path $BaseTemp "ui_$([guid]::NewGuid()).xml"

  $psPath = $PSCommandPath
  if (-not $psPath) {
    # salva cópia temporária do script atual se foi colado interativo
    $psPath = Join-Path $BaseTemp "UpdateW11_Run.ps1"
    $self = $MyInvocation.MyCommand.Definition
    [IO.File]::WriteAllText($psPath, $self, [Text.Encoding]::UTF8)
  }

  $argSwitch =
    if ($Mode -eq 'choice') { '-ShowPromptOnly' } else { '-ShowForcedOnly' }

  $action = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$psPath`" $argSwitch"

  # Se tivermos SID do usuário, usamos no XML; senão, deixamos sem UserId (o Windows resolve pelo token interativo)
  $principalUserId = if ($info.SID) { "UserId=""$($info.SID)""" } else { "" }

  $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Exibe UI UpdateW11 na sessão do usuário atual</Description>
  </RegistrationInfo>
  <Triggers />
  <Principals>
    <Principal id="InteractiveUser" $principalUserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT30M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="InteractiveUser">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$psPath" $argSwitch</Arguments>
      <WorkingDirectory>$BaseTemp</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

  # Grava XML em UTF-16 (schtasks exige)
  [IO.File]::WriteAllText($tmpXml, $xml, [Text.Encoding]::Unicode)

  try {
    schtasks /Create /TN $taskName /XML $tmpXml /F | Out-Null
  } catch {
    Write-Host "❌ Falha ao criar tarefa para UI: $($_.Exception.Message)" -ForegroundColor Red
    return $false
  } finally {
    Remove-Item $tmpXml -ErrorAction SilentlyContinue
  }

  # Limpa resposta anterior e dispara a UI
  Remove-Item $AnswerPath -ErrorAction SilentlyContinue
  schtasks /Run /TN $taskName | Out-Null

  # Espera até o usuário responder ou até expirar Timeout
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    $ans = Read-Answer
    if ($ans) { break }
    # opcional: pode checar Status da tarefa, mas monitorar o arquivo já é suficiente
  }

  # Apaga a tarefa
  schtasks /Delete /TN $taskName /F | Out-Null

  # Retorna true se houve resposta
  return [bool](Read-Answer)
}

# ----------------- PASSO 1: Download/Montagem da ISO (com verificação) -----------------
function Do-Step1 {
  param(
    [Parameter(Mandatory=$true)][string]$IsoUrl,
    [string]$Dest = $BaseTemp,
    [string]$IsoName = 'Win11_24H2_BrazilianPortuguese_x64.iso',
    [UInt64]$MinSizeBytes = 5GB  # valida ISO >= 5 GB
  )

  New-Item -ItemType Directory -Path $Dest -Force | Out-Null
  $isoPath = Join-Path $Dest $IsoName

  # Se X: já estiver em uso por uma ISO anterior, desmonta
  if (Get-PSDrive -Name X -ErrorAction SilentlyContinue) {
    Write-Host "⏏ Desmontando imagem anterior em X:..."
    $mountedVol = Get-Volume -DriveLetter X -ErrorAction SilentlyContinue
    if ($mountedVol) {
      $prevImg = (Get-DiskImage | Where-Object { $_.Attached } | Where-Object { (Get-Volume -DiskImage $_).DriveLetter -eq 'X' } | Select-Object -First 1)
      if ($prevImg) { Dismount-DiskImage -ImagePath $prevImg.ImagePath -ErrorAction SilentlyContinue }
      Start-Sleep -Seconds 2
    }
  }

  # Verifica se já existe ISO válida (>= 5 GB)
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

    # Confere tamanho após download
    $size = (Get-Item $isoPath).Length
    if ($size -lt $MinSizeBytes) {
      throw "Download da ISO concluído, porém tamanho inesperado ($size bytes < $MinSizeBytes)."
    }
    Write-Host "✅ Download OK ($([Math]::Round($size/1GB,2)) GB)."
  }

  # Monta ISO (ou reaproveita se já anexada)
  $img = Get-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
  if ($img -and $img.Attached) {
    Write-Host "💿 ISO já montada. Ajustando letra para X: se necessário..."
    $vol = $img | Get-Volume
  } else {
    Write-Host "💿 Montando ISO..."
    Mount-DiskImage -ImagePath $isoPath | Out-Null
    $img = Get-DiskImage -ImagePath $isoPath
    $vol = $img | Get-Volume
  }

  $oldDrv = $vol.DriveLetter + ':'
  $newDrv = 'X:'
  if ($oldDrv -ne $newDrv) {
    Get-CimInstance -Class Win32_Volume |
      Where-Object { $_.DriveLetter -eq $oldDrv } |
      Set-CimInstance -Arguments @{ DriveLetter = $newDrv }
  }

  Write-Host "✅ ISO pronta em $newDrv"
  return $newDrv
}

# ----------------- PASSO 2: Execução Setup.exe -----------------
function Do-Step2 {
  param(
    [string]$Drive = 'X:',
    [string]$LogPath = (Join-Path $BaseTemp 'logs.log')
  )
  Write-Host "▶ Iniciando atualização do Windows..."
  $setupArgs = "/auto upgrade /DynamicUpdate disable /ShowOOBE none /noreboot /compat IgnoreWarning /BitLocker TryKeepActive /EULA accept /CopyLogs `"$LogPath`""
  Start-Process -FilePath (Join-Path $Drive 'Setup.exe') -ArgumentList $setupArgs -Wait
  Write-Host "✔ Instalação iniciada. Reiniciando máquina..."
  Restart-Computer -Timeout 10 -Force
}

# ============================== ROTINAS CHAMADAS PELAS TAREFAS ==============================
if ($ShowPromptOnly) {
  Show-ChoicePrompt
  exit 0
}
if ($ShowForcedOnly) {
  Show-ForcedPrompt
  exit 0
}

# ============================== FLUXO PRINCIPAL ==============================
# 1) Passo 1 (automático) — usa TEMP e reaproveita ISO válida
$isoUrl  = 'https://temp-arco-itops.s3.us-east-1.amazonaws.com/Win11_24H2_BrazilianPortuguese_x64.iso'
$driveX  = Do-Step1 -IsoUrl $isoUrl -Dest $BaseTemp

# 2) Primeira pergunta (NOW / 1h / 2h) — SEMPRE na sessão do usuário ativo
Remove-Item $AnswerPath -ErrorAction SilentlyContinue
$shown = Start-UiInActiveSession -Mode 'choice' -TimeoutSec 1800  # espera até 30 min pela resposta
if (-not $shown) {
  Write-Host "⚠ Não foi possível exibir a UI ao usuário atual. Prosseguindo com execução obrigatória."
  Write-Answer 'NOW'
}

# 3) Ler resposta e decidir
$choice = Read-Answer
switch ($choice) {
  'NOW'   {
    # Tela obrigatória (countdown) na sessão do usuário
    Remove-Item $AnswerPath -ErrorAction SilentlyContinue
    Start-UiInActiveSession -Mode 'forced' -TimeoutSec 600 | Out-Null
    Do-Step2 -Drive $driveX
  }
  '3600'  {
    Write-Host "⏳ Aguardando 1 hora antes da execução..."
    Start-Sleep -Seconds 60
    Remove-Item $AnswerPath -ErrorAction SilentlyContinue
    Start-UiInActiveSession -Mode 'forced' -TimeoutSec 600 | Out-Null
    Do-Step2 -Drive $driveX
  }
  '7200'  {
    Write-Host "⏳ Aguardando 2 horas antes da execução..."
    Start-Sleep -Seconds 120
    Remove-Item $AnswerPath -ErrorAction SilentlyContinue
    Start-UiInActiveSession -Mode 'forced' -TimeoutSec 600 | Out-Null
    Do-Step2 -Drive $driveX
  }
  default {
    Write-Host "⚠ Resposta inválida ou ausente. Prosseguindo com execução obrigatória."
    Remove-Item $AnswerPath -ErrorAction SilentlyContinue
    Start-UiInActiveSession -Mode 'forced' -TimeoutSec 600 | Out-Null
    Do-Step2 -Drive $driveX
  }
}
