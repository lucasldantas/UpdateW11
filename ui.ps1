#requires -version 5.1
param([switch]$RePrompt)

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
# ==========================================================

# ==================== CONFIG GERAL ====================
$AppRoot         = 'C:\ProgramData\UpdateW11'
$TargetPath      = Join-Path $AppRoot 'ui.ps1'
$TaskNameUI      = 'UpdateW11-UI'               # tarefa da UI (usuário)
$WorkerTaskName  = 'UpdateW11-Worker'           # tarefa do worker (SYSTEM)
$WorkerPath      = Join-Path $AppRoot 'worker.ps1'
$WorkerCMD       = Join-Path $AppRoot 'WorkerBootstrap.cmd'
$LogPath         = Join-Path $AppRoot 'ui.log'
$PsExeFull       = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'

# ---- Pré-download/ISO (usado no pré-popup E pelo worker) ----
$IsoWorkDir  = 'C:\Temp\UpdateW11'
$IsoUrl      = 'https://temp-arco-itops.s3.us-east-1.amazonaws.com/Win11_24H2_BrazilianPortuguese_x64.iso'
$IsoPath     = Join-Path $IsoWorkDir 'Win11_24H2_BrazilianPortuguese_x64.iso'
$IsoMinSize  = 5GB  # 5.368.709.120 bytes
$IsoDrive    = 'X'  # letra alvo da imagem
# =====================================================

# ---------- Log ----------
function Write-UiLog([string]$msg) {
  try {
    if (-not (Test-Path -LiteralPath $AppRoot)) { New-Item -Path $AppRoot -ItemType Directory -Force | Out-Null }
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Add-Content -LiteralPath $LogPath -Value "[$stamp] $msg"
  } catch {}
}

# ---------- Garantir STA ----------
try {
  if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA' -and $PSCommandPath) {
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File', $PSCommandPath)
    if ($RePrompt) { $args += '-RePrompt' }
    Start-Process -FilePath $PsExeFull -ArgumentList $args | Out-Null
    return
  }
} catch { Write-UiLog "Falha STA: $($_.Exception.Message)" }

# ---------- Download robusto do GitHub (opcional) ----------
$RepoOwner    = 'lucasldantas'
$RepoName     = 'UpdateW11'
$RepoRef      = 'main'
$RepoFilePath = 'ui.ps1'
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
      $rawHeaders=@{ 'User-Agent'='ps' }
      if ($script:t -and $t) { $rawHeaders['Authorization']="token $t" }
      $resp2 = Invoke-WebRequest -Uri $rawUrl -Headers $rawHeaders -UseBasicParsing -ErrorAction Stop
      return ,([Text.Encoding]::UTF8.GetBytes($resp2.Content))
    } catch { $e2=$_.Exception.Message; throw "Falha baixar UI:`n1) $apiUrl -> $e1`n2) $rawUrl -> $e2" }
  }
}

# ---------- Bootstrap local ----------
if (-not (Test-Path -LiteralPath $AppRoot)) { New-Item -Path $AppRoot -ItemType Directory -Force | Out-Null }
if ($PSCommandPath) { $SelfPath = $PSCommandPath } else { $SelfPath = $MyInvocation.MyCommand.Path }

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

# ==================== PRÉ-POPUP: checagem + download ISO ====================
function Test-Build19045 {
  try {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $buildStr = $cv.CurrentBuild
    if (-not $buildStr) { $buildStr = $cv.CurrentBuildNumber }
    $build = [int]$buildStr
    return ($build -eq 19045),$build
  } catch { return $false,$null }
}

function Dismount-IfMountedX {
  try {
    # Desmonta especificamente o que estiver em X:, se houver
    $vol = Get-Volume -DriveLetter $IsoDrive -ErrorAction SilentlyContinue
    if ($vol) {
      try {
        $img = $vol | Get-DiskImage -ErrorAction SilentlyContinue
        if ($img) { Dismount-DiskImage -ImagePath $img.ImagePath -ErrorAction SilentlyContinue }
      } catch {}
      # como belt-and-suspenders, tenta limpar a letra
      try {
        $vol | Set-CimInstance -Arguments @{ DriveLetter = $null } -ErrorAction SilentlyContinue | Out-Null
      } catch {}
      Start-Sleep -Seconds 2
    }
  } catch {}
}

function Ensure-IsoDownloaded {
  param([string]$Url,[string]$Path,[UInt64]$MinBytes)

  if (-not (Test-Path -LiteralPath (Split-Path -Parent $Path))) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
  }

  $downloadNeeded = $true
  if (Test-Path -LiteralPath $Path) {
    try {
      $sz = (Get-Item -LiteralPath $Path).Length
      if ($sz -ge $MinBytes) { $downloadNeeded = $false; Write-UiLog "ISO já presente (${sz} bytes) — pulando download." }
      else { Write-UiLog "ISO presente porém menor que mínimo (${sz} < $MinBytes). Rebaixando..." }
    } catch {}
  }

  if ($downloadNeeded) {
    Write-UiLog "Baixando ISO de $Url para $Path ..."
    try {
      Import-Module BitsTransfer -ErrorAction SilentlyContinue | Out-Null
      Start-BitsTransfer -Source $Url -Destination $Path -RetryInterval 60 -RetryTimeout 1800
    } catch {
      Write-UiLog "BITS falhou: $($_.Exception.Message). Tentando Invoke-WebRequest."
      Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -TimeoutSec 0
    }
    # valida tamanho
    $final = (Get-Item -LiteralPath $Path).Length
    if ($final -lt $MinBytes) { throw "Download concluído porém tamanho inesperado ($final bytes) < mínimo ($MinBytes)." }
    Write-UiLog "Download OK (${final} bytes)."
  }
}

# Executa pré-popup (oculto ao usuário)
$ok,$foundBuild = Test-Build19045
if (-not $ok) {
  try { msg * /time:10 "Windows 10 incompatível (build $foundBuild). Requer 19045." } catch {}
  Write-UiLog "Build incompatível: $foundBuild. Abortando."
  return
}
Write-UiLog "Build validada: $foundBuild (OK)."
Dismount-IfMountedX
try { Ensure-IsoDownloaded -Url $IsoUrl -Path $IsoPath -MinBytes $IsoMinSize } catch { Write-UiLog "Falha no download ISO: $($_.Exception.Message)"; return }

# ==================== HELPERS PÓS-BOOTSTRAP ====================
function Ensure-SchedulerRunning {
  try {
    $svc = Get-Service -Name 'Schedule' -ErrorAction Stop
    if ($svc.Status -ne 'Running') {
      Start-Service 'Schedule' -ErrorAction Stop
      $svc.WaitForStatus('Running','00:00:05') | Out-Null
    }
  } catch {}
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

# --- Conteúdo do worker (executa a atualização) ---
$DefaultWorkerBody = @"
#requires -version 5.1
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

\$IsoWorkDir = '$IsoWorkDir'
\$IsoUrl     = '$IsoUrl'
\$IsoPath    = '$IsoPath'
\$IsoMinSize = [UInt64]$IsoMinSize
\$IsoDrive   = '$IsoDrive'

function Write-WorkerLog(\$m){
  try {
    \$root = '$AppRoot'
    if (-not (Test-Path -LiteralPath \$root)) { New-Item -Path \$root -ItemType Directory -Force | Out-Null }
    Add-Content -LiteralPath (Join-Path \$root 'worker.log') -Value "[(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] \$m"
  } catch {}
}

function Ensure-IsoReady {
  if (-not (Test-Path -LiteralPath \$IsoPath)) { throw "ISO não encontrada em \$IsoPath" }
  \$len = (Get-Item -LiteralPath \$IsoPath).Length
  if (\$len -lt \$IsoMinSize) { throw "ISO menor que o mínimo (\$len < \$IsoMinSize)" }
}

function Mount-IsoX {
  try {
    # desmonta X: se houver
    \$vol = Get-Volume -DriveLetter \$IsoDrive -ErrorAction SilentlyContinue
    if (\$vol) {
      try {
        \$img = \$vol | Get-DiskImage -ErrorAction SilentlyContinue
        if (\$img) { Dismount-DiskImage -ImagePath \$img.ImagePath -ErrorAction SilentlyContinue }
      } catch {}
      try { \$vol | Set-CimInstance -Arguments @{ DriveLetter = \$null } -ErrorAction SilentlyContinue | Out-Null } catch {}
      Start-Sleep -Seconds 2
    }

    Mount-DiskImage -ImagePath \$IsoPath -ErrorAction Stop
    \$volNew = Get-DiskImage -ImagePath \$IsoPath | Get-Volume
    \$oldDrv = \$volNew.DriveLetter + ':'
    \$newDrv = \$IsoDrive + ':'

    Get-CimInstance -Class Win32_Volume |
      Where-Object { \$_.DriveLetter -eq \$oldDrv } |
      Set-CimInstance -Arguments @{ DriveLetter = \$newDrv }

    Write-WorkerLog ("ISO montada em {0} (antes: {1})." -f \$newDrv, \$oldDrv)
    return (\$IsoDrive + ':\')
  } catch {
    Write-WorkerLog "Falha ao montar ISO: \$($_.Exception.Message)"
    throw
  }
}

function Start-Upgrade(\$setupRoot){
  \$setupArgs = "/auto upgrade /DynamicUpdate disable /ShowOOBE none /noreboot /compat IgnoreWarning /BitLocker TryKeepActive /EULA accept /CopyLogs C:\Temp\UpdateW11\logs.log"
  Write-WorkerLog "Iniciando Setup: `"\$setupRoot\Setup.exe`" \$setupArgs"
  Start-Process -FilePath (Join-Path \$setupRoot 'Setup.exe') -ArgumentList \$setupArgs -Wait
  Write-WorkerLog "Setup finalizado (fase inicial). Reiniciando..."
}

try {
  Write-WorkerLog "Worker START"
  Ensure-IsoReady
  \$root = Mount-IsoX
  Start-Upgrade -setupRoot \$root
  Start-Sleep -Seconds 10
  Restart-Computer -Force
} catch {
  Write-WorkerLog "ERRO: \$($_.Exception.Message)"
  # Opcionalmente, sinalize ao usuário:
  try { msg * /time:10 "Falha ao iniciar atualização do Windows: \$($_.Exception.Message)" } catch {}
  exit 1
}
"@

# --- Sincroniza worker.ps1 (atualiza se mudou) ---
function Ensure-WorkerScript {
  $utf8BOM = New-Object System.Text.UTF8Encoding($true)
  $current = ''
  if (Test-Path -LiteralPath $WorkerPath) { try { $current = Get-Content -LiteralPath $WorkerPath -Raw -ErrorAction Stop } catch {} }
  if ($current -ne $DefaultWorkerBody) {
    [IO.File]::WriteAllText($WorkerPath, $DefaultWorkerBody, $utf8BOM)
  }
}

# --- Bootstrap .cmd que chama o PowerShell 64-bit e loga tudo ---
function Ensure-WorkerBootstrapCmd {
  $cmd = @(
    '@echo off',
    'setlocal',
    'set APPROOT=C:\ProgramData\UpdateW11',
    'set LOG=%APPROOT%\worker-bootstrap.log',
    'echo [%date% %time%] Bootstrap START >> "%LOG%"',
    'set PSEXEPATH=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
    'if not exist "%PSEXEPATH%" set PSEXEPATH=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe',
    'echo [%date% %time%] Using "%PSEXEPATH%" >> "%LOG%"',
    'if not exist "%APPROOT%\worker.ps1" ( echo [%date% %time%] ERRO: worker.ps1 ausente >> "%LOG%" & exit /b 2 )',
    '"%PSEXEPATH%" -NoProfile -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File "%APPROOT%\worker.ps1" >> "%LOG%" 2>&1',
    'echo [%date% %time%] DONE code=%errorlevel% >> "%LOG%"',
    'endlocal',
    'exit /b %errorlevel%'
  ) -join "`r`n"
  [IO.File]::WriteAllText($WorkerCMD, $cmd, (New-Object System.Text.UTF8Encoding($true)))
}

# --- Valida a existência dos artefatos; recria se necessário ---
function Ensure-WorkerArtifacts {
  if (-not (Test-Path -LiteralPath $AppRoot)) {
    New-Item -Path $AppRoot -ItemType Directory -Force | Out-Null
  }
  Ensure-WorkerScript
  Ensure-WorkerBootstrapCmd
  $missing = @()
  if (-not (Test-Path -LiteralPath $WorkerPath)) { $missing += $WorkerPath }
  if (-not (Test-Path -LiteralPath $WorkerCMD))  { $missing += $WorkerCMD }
  if ($missing.Count -gt 0) {
    $msg = "Artefatos ausentes: " + ($missing -join ', ')
    Write-UiLog $msg
    throw $msg
  }
  try {
    $wp = Get-Item -LiteralPath $WorkerPath
    $wc = Get-Item -LiteralPath $WorkerCMD
    Write-UiLog ("WorkerPath={0} ({1} bytes); WorkerCMD={2} ({3} bytes)" -f $wp.FullName,$wp.Length,$wc.FullName,$wc.Length)
  } catch {}
}

# --- Cria/REcria a tarefa do Worker apontando para o .CMD ---
function Ensure-WorkerTask {
  Ensure-WorkerArtifacts

  $trValue = '"' + $WorkerCMD + '"'
  try { schtasks /Delete /TN $WorkerTaskName /F | Out-Null } catch {}

  $argsCreate = @('/Create','/TN',$WorkerTaskName,'/TR',$trValue,'/SC','ONCE','/SD','01/01/2099','/ST','00:00','/RL','HIGHEST','/RU','SYSTEM','/F')
  $outCreate  = schtasks @argsCreate 2>&1
  $rcCreate   = $LASTEXITCODE
  Write-UiLog ("Create Worker rc={0} out={1}" -f $rcCreate, ($outCreate -join ' '))

  if ($rcCreate -ne 0) {
    throw ("Falha ao criar Worker. Saída:`n{0}" -f ($outCreate -join [Environment]::NewLine))
  }

  $outQuery = schtasks /Query /TN $WorkerTaskName /V /FO LIST 2>&1
  Write-UiLog ("Query Worker ->`n{0}" -f ($outQuery -join [Environment]::NewLine))
}

# ---------- Utilidades para agendar no minuto correto ----------
function Round-ToSchtasksMinute([datetime]$dt) {
  $rounded = $dt.AddSeconds(-$dt.Second).AddMilliseconds(-$dt.Millisecond)
  if ($dt -gt $rounded) { $rounded = $rounded.AddMinutes(1) }
  return $rounded
}
function Format-DateVariants([datetime]$when) {
  $ddMMyyyy = $when.ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
  $MMddyyyy = $when.ToString('MM/dd/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
  return @($ddMMyyyy, $MMddyyyy)
}

# Cria a tarefa de REPROMPT (UI do usuário, sem console do host)
function New-RePromptTask {
  param([datetime]$when)

  Ensure-SchedulerRunning
  if (-not (Test-Path -LiteralPath $PsExeFull)) { throw ($Txt_ErrorNoPS -f $PsExeFull) }
  if (-not (Test-Path -LiteralPath $ScriptPath)) { throw ($Txt_ErrorNoScript -f $ScriptPath) }

  $ru = Get-ActiveConsoleUser
  if ([string]::IsNullOrWhiteSpace($ru)) { throw $Txt_ErrorNoRU }

  $now    = Get-Date
  $target = Round-ToSchtasksMinute $when
  if ($target -le $now) { $target = Round-ToSchtasksMinute($now.AddMinutes(2)) }

  $dates = Format-DateVariants $target
  $st    = $target.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)

  $trValue = '"' + $PsExeFull + '" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "' + $ScriptPath + '" -RePrompt'

  try { schtasks /Delete /TN $TaskNameUI /F | Out-Null } catch {}

  $created = $false
  foreach ($sd in $dates) {
    $args   = @('/Create','/TN',$TaskNameUI,'/TR',$trValue,'/SC','ONCE','/SD',$sd,'/ST',$st,'/RL','HIGHEST','/RU',$ru,'/IT','/F')
    $output = schtasks @args 2>&1
    if ($LASTEXITCODE -eq 0) {
      $created = $true
      Write-UiLog ("Tarefa UI criada: SD={0} ST={1} RU={2}" -f $sd, $st, $ru)
      break
    } else {
      Write-UiLog ("Falha criar UI com SD={0}: {1}" -f $sd, ($output -join ' '))
    }
  }

  if (-not $created) { throw "Falha ao criar a tarefa UI." }
}

# -------- Executar agora: prepara Worker e dispara --------
function Run-Now {
  try {
    Ensure-WorkerTask
    $outRun = schtasks /Run /TN $WorkerTaskName 2>&1
    $rcRun  = $LASTEXITCODE
    Write-UiLog ("Run Worker rc={0} out={1}" -f $rcRun, ($outRun -join ' '))
    if ($rcRun -ne 0) {
      throw ("Falha ao iniciar Worker (rc={0}). Saída:`n{1}" -f $rcRun, ($outRun -join [Environment]::NewLine))
    }
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

# Carrega a janela
$reader  = New-Object System.Xml.XmlNodeReader $xaml
$window  = [Windows.Markup.XamlReader]::Load($reader)
if (-not $window) { throw "Falha ao carregar a UI a partir do XAML." }

# Garantir visibilidade e foco
$window.Topmost = $true
$window.Add_Loaded({
  try {
    $this.Activate()      | Out-Null
    $this.BringIntoView() | Out-Null
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({ param($s,$e) try { $this.Activate() | Out-Null } catch {} ; $s.Stop() })
    $timer.Start()
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
    $runAt=(Get-Date).AddMinutes(2)
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
