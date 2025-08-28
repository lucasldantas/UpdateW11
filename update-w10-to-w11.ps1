#requires -version 5.1
param(
  [switch]$RePrompt,           # (interno) abre SOMENTE a UI de escolha (NOW/1h/2h)
  [switch]$ForcedPromptOnly    # (interno) abre SOMENTE a UI obrigatória (countdown)
)

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ==================== TEXTOS / RÓTULOS ====================
$Txt_WindowTitle          = 'Agendar Execução'
$Txt_HeaderTitle          = 'Atualização Obrigatória'
$Txt_HeaderSubtitle       = 'Você pode executar agora ou adiar por até 2 horas.'
$Txt_ActionLabel          = 'Ação:'
$Txt_ActionLine1          = 'Realizar o update do Windows 10 para o Windows 11'
$Txt_ActionLine2          = 'Tempo Estimado: 20 a 30 minutos'
$Txt_BtnNow               = 'Executar agora'
$Txt_BtnDelay1            = 'Adiar 1 hora'
$Txt_BtnDelay2            = 'Adiar 2 horas'
# ==========================================================

# ==================== CAMINHOS ====================
$BaseTemp   = 'C:\Temp\UpdateW11'
$AnswerPath = 'C:\ProgramData\answer.txt'             # NOW / 3600 / 7200
$WrapperCmd = 'C:\ProgramData\launch_ui_prompt.cmd'   # wrapper para o /TR
$TaskLog    = 'C:\ProgramData\ui_task.log'            # stdout/stderr da tarefa

foreach ($p in @('C:\ProgramData', $BaseTemp)) { if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null } }

# ==================== SO CHECK ====================
$osCaption = (Get-CimInstance Win32_OperatingSystem).Caption
if ($osCaption -match 'Windows 11') { Write-Host '✅ Já está no Windows 11. Nenhuma ação será tomada.'; if (-not ($RePrompt -or $ForcedPromptOnly)) { exit 0 } }
elseif ($osCaption -notmatch 'Windows 10') { Write-Host '⚠ Sistema não é Windows 10 nem 11. Abortando.'; if (-not ($RePrompt -or $ForcedPromptOnly)) { exit 1 } }
else { if (-not ($RePrompt -or $ForcedPromptOnly)) { Write-Host '▶ Sistema Windows 10 detectado. Continuando com o update...' } }

# ==================== HELPERS ====================
function Save-Answer([string]$text){
  try { [IO.File]::WriteAllText($AnswerPath, $text + [Environment]::NewLine, [Text.Encoding]::UTF8) } catch {}
}
function Read-Answer {
  try {
    if (Test-Path $AnswerPath) { return ([IO.File]::ReadAllText($AnswerPath,[Text.Encoding]::UTF8)).Trim() }
  } catch {}
  return $null
}

# Descobrir o usuário interativo ativo (corrige WORKGROUP -> NomeDoPC)
function Get-ActiveInteractiveUser {
  $res = [ordered]@{ User=$null; Domain=$null; EffectiveDomain=$null; RU=$null; SessionId=$null }
  $quser = try { & quser 2>$null } catch { $null }
  if ($quser) {
    $line = ($quser -split "`r?`n" | Where-Object { $_ -match '(?i)\s(Active|Ativo)\s' } | Select-Object -First 1)
    if ($line) {
      $tokens = ($line -replace '^\s*>\s*','') -split '\s+'
      $userTok = $tokens[0]
      $idTok   = ($tokens | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
      if ($userTok) {
        if ($userTok -match '\\') { $res.Domain,$res.User = $userTok -split '\\',2 }
        else { $res.User = $userTok; $res.Domain = $env:USERDOMAIN }
      }
      if ($idTok) { $res.SessionId = [int]$idTok }
    }
  }
  if (-not $res.User) {
    $ud = try { (Get-CimInstance Win32_ComputerSystem).UserName } catch { $null }
    if ($ud) {
      if ($ud -match '\\') { $res.Domain,$res.User = $ud -split '\\',2 }
      else { $res.User = $ud; $res.Domain = $env:USERDOMAIN }
    }
  }
  $machine = try { (Get-CimInstance Win32_ComputerSystem).Name } catch { $env:COMPUTERNAME }
  $dom = if ([string]::IsNullOrWhiteSpace($res.Domain) -or $res.Domain -eq 'WORKGROUP') { $machine } else { $res.Domain }
  $res.EffectiveDomain = $dom
  if ($res.User) { $res.RU = "$dom\$($res.User)" }
  return [pscustomobject]$res
}

# Garante STA quando exibindo UI diretamente (nos modos -RePrompt / -ForcedPromptOnly)
$PsExeFull = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
if (($RePrompt -or $ForcedPromptOnly) -and [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA' -and $PSCommandPath) {
  $reArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File', $PSCommandPath)
  if ($RePrompt) { $reArgs += '-RePrompt' }
  if ($ForcedPromptOnly) { $reArgs += '-ForcedPromptOnly' }
  Start-Process -FilePath $PsExeFull -ArgumentList $reArgs -WindowStyle Normal | Out-Null
  return
}

# ==================== UI WPF ====================
Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

function Show-ChoicePrompt {
  [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Txt_WindowTitle" Width="520" MinHeight="300" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Background="#0f172a"
        WindowStyle="None" ShowInTaskbar="True">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" CornerRadius="12" Background="#111827" Padding="16">
      <StackPanel>
        <TextBlock Text="$Txt_HeaderTitle" Foreground="#e5e7eb" FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Text="$Txt_HeaderSubtitle" Foreground="#9ca3af" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
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
        <Button Name="BtnNow"    Content="$Txt_BtnNow"    Margin="8,0,0,0" Padding="16,8" Background="#22c55e" Foreground="White" FontFamily="Segoe UI" FontWeight="SemiBold" BorderBrush="#16a34a" BorderThickness="1" Cursor="Hand"/>
        <Button Name="BtnDelay1" Content="$Txt_BtnDelay1" Margin="8,0,0,0" Padding="16,8" Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI" BorderBrush="#374151" BorderThickness="1" Cursor="Hand"/>
        <Button Name="BtnDelay2" Content="$Txt_BtnDelay2" Margin="8,0,0,0" Padding="16,8" Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI" BorderBrush="#374151" BorderThickness="1" Cursor="Hand"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@
  $reader = New-Object System.Xml.XmlNodeReader $xaml
  $window = [Windows.Markup.XamlReader]::Load($reader)
  if (-not $window) { throw 'Falha ao carregar a UI (Choice).' }

  $window.Topmost = $true
  $window.Add_Loaded({ try { $this.Activate() | Out-Null } catch {} })
  $window.Add_MouseLeftButtonDown({ if ($_.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed){ try { $window.DragMove() } catch {} } })

  $BtnNow    = $window.FindName('BtnNow')
  $BtnDelay1 = $window.FindName('BtnDelay1')
  $BtnDelay2 = $window.FindName('BtnDelay2')

  $closingHandler = [System.ComponentModel.CancelEventHandler]{ param($s,[System.ComponentModel.CancelEventArgs]$e) $e.Cancel = $true }
  $window.add_Closing($closingHandler)
  function Allow-Close([System.Windows.Window]$w){ if ($w -and $closingHandler){ $w.remove_Closing($closingHandler) } }

  $BtnNow.add_Click(   { Save-Answer 'NOW';   Allow-Close $window; $window.Close() })
  $BtnDelay1.add_Click({ Save-Answer '3600';  Allow-Close $window; $window.Close() })
  $BtnDelay2.add_Click({ Save-Answer '7200';  Allow-Close $window; $window.Close() })

  $null = $window.ShowDialog()
}

function Show-ForcedPrompt {
  $TotalSeconds = 300
  [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Txt_WindowTitle" Width="560" MinHeight="300" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" Background="#0f172a"
        WindowStyle="None" ShowInTaskbar="True">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" CornerRadius="12" Background="#111827" Padding="16">
      <StackPanel>
        <TextBlock Text="$Txt_HeaderTitle" Foreground="#e5e7eb" FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Text="Chegou a hora agendada. A execução é obrigatória." Foreground="#f87171" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>
    <Border Grid.Row="2" CornerRadius="12" Background="#0b1220" Padding="16" Margin="0,16,0,16">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="220"/></Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" Margin="0,0,12,0">
          <TextBlock Text="$Txt_ActionLabel" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" Margin="0,0,0,6"/>
          <TextBlock Text="$Txt_ActionLine1" Foreground="#94a3b8" FontFamily="Consolas" FontSize="14" Background="#0b1220" TextWrapping="Wrap" Margin="0,0,0,4"/>
          <TextBlock Text="$Txt_ActionLine2" Foreground="#94a3b8" FontFamily="Consolas" FontSize="14" Background="#0b1220" TextWrapping="Wrap"/>
        </StackPanel>
        <Border Grid.Column="1" Background="#0f172a" CornerRadius="12" Padding="12">
          <StackPanel>
            <TextBlock Text="Início automático em:" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="12"/>
            <TextBlock Name="LblCountdown" Text="05:00" Foreground="#e5e7eb" FontFamily="Segoe UI" FontWeight="Bold" FontSize="28" Margin="0,4,0,10" HorizontalAlignment="Center"/>
            <ProgressBar Name="PbCountdown" Minimum="0" Maximum="$TotalSeconds" Height="16" Foreground="#22c55e" Background="#1f2937" BorderBrush="#111827" Value="0"/>
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
  if (-not $window) { throw 'Falha ao carregar a UI (Forced).' }

  $window.Topmost = $true
  $window.Add_Loaded({ try { $this.Activate() | Out-Null } catch {} })
  $window.Add_MouseLeftButtonDown({ if ($_.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed){ try { $window.DragMove() } catch {} } })

  $BtnNow       = $window.FindName('BtnNow')
  $LblCountdown = $window.FindName('LblCountdown')
  $PbCountdown  = $window.FindName('PbCountdown')

  $closingHandler = [System.ComponentModel.CancelEventHandler]{ param($s,[System.ComponentModel.CancelEventArgs]$e) $e.Cancel = $true }
  $window.add_Closing($closingHandler)
  function Allow-Close([System.Windows.Window]$w){ if ($w -and $closingHandler){ $w.remove_Closing($closingHandler) } }

  $done = $false
  function Execute-Now {
    if ($done) { return }
    $script:done = $true
    try { $timer.Stop() } catch {}
    Save-Answer 'NOW'
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

# ==================== EXECUTAR UI NA SESSÃO DO USUÁRIO ATIVO (via Tarefa) ====================
function Start-UiForActiveUser([ValidateSet('choice','forced')]$Mode, [int]$TimeoutSec = 900) {
  $who = Get-ActiveInteractiveUser
  if (-not $who.RU) { Write-Host '⚠ Nenhum usuário interativo ativo encontrado.'; return $false }
  Write-Host "👤 Usuário ativo: $($who.RU)  (SessãoID=$($who.SessionId))"

  # Caminho físico do script: se rodou via IEX, persistimos este conteúdo
  $psPath = $PSCommandPath
  if (-not $psPath) {
    $psPath = Join-Path $BaseTemp 'UpdateW11_UI.ps1'
    $self = $MyInvocation.MyCommand.Definition
    [IO.File]::WriteAllText($psPath, $self, [Text.Encoding]::UTF8)
  }

  # Wrapper .CMD para o /TR (sem briga de aspas). Registra saída no TaskLog.
  $argSwitch = if ($Mode -eq 'choice') { '-RePrompt' } else { '-ForcedPromptOnly' }
  $psExe     = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
  $wrapper   = @(
    '@echo off'
    'setlocal'
    ('"{0}" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Normal -File "{1}" {2} >> "{3}" 2>>&1' -f $psExe, $psPath, $argSwitch, $TaskLog)
  ) -join "`r`n"
  [IO.File]::WriteAllText($WrapperCmd, $wrapper, [Text.Encoding]::ASCII)

  $taskName  = "\GDL\UpdateW11-UI-$([guid]::NewGuid())"
  $startTime = (Get-Date).AddMinutes(2).ToString('HH:mm')

  $createCmd = @(
    '/Create','/TN', $taskName,
    '/SC','ONCE','/ST', $startTime,
    '/TR', "`"$WrapperCmd`"",
    '/RL','LIMITED',            # evita desktop elevado/UAC
    '/RU', $who.RU,
    '/IT',
    '/F'
  )

  # Cria/roda e espera resposta
  schtasks @createCmd | Out-Null
  schtasks /Run /TN $taskName | Out-Null

  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    if (Read-Answer) { break }
  }

  schtasks /Delete /TN $taskName /F | Out-Null
  return [bool](Read-Answer)
}

# ==================== PASSO 1: Download/Montagem da ISO (corrigido) ====================
function Do-Step1 {
  param(
    [Parameter(Mandatory=$true)][string]$IsoUrl,
    [string]$Dest = $BaseTemp,
    [string]$IsoName = 'Win11_24H2_BrazilianPortuguese_x64.iso',
    [UInt64]$MinSizeBytes = 5GB
  )

  New-Item -ItemType Directory -Path $Dest -Force | Out-Null
  $isoPath = Join-Path $Dest $IsoName

  # Se nossa ISO já estiver montada, desmonta (sempre com -ImagePath)
  try {
    $imgMine = Get-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    if ($imgMine -and $imgMine.Attached) {
      Write-Host "⏏ Desmontando ISO anterior deste script..."
      Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
      Start-Sleep -Seconds 2
    }
  } catch {}

  # Verifica/baixa
  $needDownload = $true
  if (Test-Path $isoPath) {
    try {
      $size = (Get-Item $isoPath).Length
      if ($size -ge $MinSizeBytes) { Write-Host "⚡ ISO válida encontrada em $isoPath — pulando download."; $needDownload = $false }
      else { Write-Host "🧹 ISO incompleta. Rebaixando..."; Remove-Item $isoPath -Force -ErrorAction SilentlyContinue }
    } catch {}
  }
  if ($needDownload) {
    Write-Host '⏬ Baixando ISO...'
    Start-BitsTransfer -Source $IsoUrl -Destination $isoPath
    $size = (Get-Item $isoPath).Length
    if ($size -lt $MinSizeBytes) { throw "Download da ISO concluído, porém tamanho inesperado ($size bytes < $MinSizeBytes)." }
    Write-Host "✅ Download OK ($([Math]::Round($size/1GB,2)) GB)."
  }

  # Se X: estiver ocupado por outra coisa, tenta liberar
  $volX = Get-Volume -DriveLetter X -ErrorAction SilentlyContinue
  if ($volX) {
    try {
      Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='X:'" |
        Set-CimInstance -Property @{ DriveLetter = $null } -ErrorAction SilentlyContinue | Out-Null
      Start-Sleep -Seconds 1
    } catch {}
  }

  # Monta nossa ISO
  Write-Host '💿 Montando ISO...'
  Mount-DiskImage -ImagePath $isoPath | Out-Null

  # Letra atribuída e tentativa de forçar X:
  $img = Get-DiskImage -ImagePath $isoPath
  $vol = $img | Get-Volume
  $assigned = $vol.DriveLetter + ':'
  if ($assigned -ne 'X:') {
    try {
      Get-CimInstance -Class Win32_Volume | Where-Object { $_.DriveLetter -eq $assigned } |
        Set-CimInstance -Property @{ DriveLetter = 'X:' } -ErrorAction Stop | Out-Null
      $assigned = 'X:'
    } catch {
      Write-Host "ℹ Não foi possível usar X:. Usando $assigned."
    }
  }

  Write-Host "✅ ISO pronta em $assigned"
  return $assigned
}

# ==================== PASSO 2: Setup.exe ====================
function Do-Step2 {
  param(
    [string]$Drive = 'X:',
    [string]$LogPath = (Join-Path $BaseTemp 'logs.log')
  )
  Write-Host '▶ Iniciando atualização do Windows...'
  $setupArgs = "/auto upgrade /DynamicUpdate disable /ShowOOBE none /noreboot /compat IgnoreWarning /BitLocker TryKeepActive /EULA accept /CopyLogs `"$LogPath`""
  Start-Process -FilePath (Join-Path $Drive 'Setup.exe') -ArgumentList $setupArgs -Wait
  Write-Host '✔ Instalação iniciada. Reiniciando máquina...'
  Restart-Computer -Timeout 10 -Force
}

# ==================== ENTRADAS DOS MODOS INTERNOS (UI direta) ====================
if ($RePrompt)         { Show-ChoicePrompt;        exit 0 }
if ($ForcedPromptOnly) { Show-ForcedPrompt;        exit 0 }

# ==================== FLUXO PRINCIPAL ====================
$isoUrl = 'https://temp-arco-itops.s3.us-east-1.amazonaws.com/Win11_24H2_BrazilianPortuguese_x64.iso'
$driveX = Do-Step1 -IsoUrl $isoUrl -Dest $BaseTemp

# 1) Mostra pergunta NOW/1h/2h para o USUÁRIO ATIVO (a partir de SYSTEM/remoto)
Remove-Item $AnswerPath -ErrorAction SilentlyContinue
$shown = Start-UiForActiveUser -Mode 'choice' -TimeoutSec 1800
if (-not $shown) { Write-Host '⚠ UI não abriu ou sem resposta; prosseguindo NOW.'; Save-Answer 'NOW' }

# 2) Decide
$choice = Read-Answer
switch ($choice) {
  'NOW'   {
    Remove-Item $AnswerPath -ErrorAction SilentlyContinue
    Start-UiForActiveUser -Mode 'forced' -TimeoutSec 600 | Out-Null
    Do-Step2 -Drive $driveX
  }
  '3600'  {
    Write-Host '⏳ Aguardando 1 hora antes da execução...'
    Start-Sleep -Seconds 60
    Remove-Item $AnswerPath -ErrorAction SilentlyContinue
    Start-UiForActiveUser -Mode 'forced' -TimeoutSec 600 | Out-Null
    Do-Step2 -Drive $driveX
  }
  '7200'  {
    Write-Host '⏳ Aguardando 2 horas antes da execução...'
    Start-Sleep -Seconds 120
    Remove-Item $AnswerPath -ErrorAction SilentlyContinue
    Start-UiForActiveUser -Mode 'forced' -TimeoutSec 600 | Out-Null
    Do-Step2 -Drive $driveX
  }
  default {
    Write-Host '⚠ Resposta inválida/ausente; executando NOW.'
    Remove-Item $AnswerPath -ErrorAction SilentlyContinue
    Start-UiForActiveUser -Mode 'forced' -TimeoutSec 600 | Out-Null
    Do-Step2 -Drive $driveX
  }
}
