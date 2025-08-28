#requires -version 5.1
param([switch]$RePrompt)

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

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

# ==================== Descobrir usuário interativo ativo ====================
function Get-ActiveInteractiveUser {
  $res = [ordered]@{ User=$null; Domain=$null; EffectiveDomain=$null; RU=$null; SessionId=$null }

  $quser = try { & quser 2>$null } catch { $null }
  if ($quser) {
    $line = ($quser -split "`r?`n" |
             Where-Object { $_ -match '(?i)\s(Active|Ativo)\s' } |
             Select-Object -First 1)
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

# ==================== Se NÃO for -RePrompt, garante que rode na sessão do usuário ativo ====================
if (-not $RePrompt) {
  $who = Get-ActiveInteractiveUser
  $curDom = if ([string]::IsNullOrWhiteSpace($env:USERDOMAIN) -or $env:USERDOMAIN -eq 'WORKGROUP') { $env:COMPUTERNAME } else { $env:USERDOMAIN }
  $curRU  = "$curDom\$env:USERNAME"

  # Se já estamos na sessão do usuário interativo, abre direto; senão agenda e sai.
  if ($who.RU -and ($who.RU -ne $curRU)) {
    Write-Host "👤 Usuário interativo ativo: $($who.RU)  (SessãoID=$($who.SessionId))"
    # Caminho físico deste script
    $psPath = $PSCommandPath
    if (-not $psPath) {
      $psPath = 'C:\ProgramData\W11_UI_Prompt.ps1'
      $self   = $MyInvocation.MyCommand.Definition
      [IO.File]::WriteAllText($psPath, $self, [Text.Encoding]::UTF8)
    }

    # Monta o /TR como UM ÚNICO argumento (sem wrapper)
    $psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $tr    = "$psExe -NoProfile -ExecutionPolicy Bypass -STA -File `"$psPath`" -RePrompt"

    $taskName  = "\GDL\UpdateW11-UI-$([guid]::NewGuid())"
    $startTime = (Get-Date).AddMinutes(1).ToString('HH:mm')

    $argsCreate = @(
      '/Create','/TN', $taskName,
      '/SC','ONCE','/ST', $startTime,
      '/TR', $tr,                # <- UM argumento só!
      '/RL','LIMITED',
      '/RU', $who.RU,
      '/IT',
      '/F'
    )
    # Cria e executa
    schtasks @argsCreate | Out-Null
    schtasks /Run /TN $taskName | Out-Null
    Write-Host "🗓️  Tarefa criada/executada para $($who.RU): $taskName"
    return
  }
}

# ---------- Apenas salvar a resposta ----------
$AnswerPath = 'C:\ProgramData\answer.txt'
if (-not (Test-Path 'C:\ProgramData')) { New-Item -Path 'C:\ProgramData' -ItemType Directory -Force | Out-Null }
function Save-Answer([string]$text){
  try { [IO.File]::WriteAllText($AnswerPath, $text + [Environment]::NewLine, [Text.Encoding]::UTF8) } catch {}
}

# ---------- Garantir STA (apenas quando vamos exibir UI) ----------
$PsExeFull = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
try {
  if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA' -and $PSCommandPath) {
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File', $PSCommandPath)
    if ($RePrompt) { $args += '-RePrompt' }
    Start-Process -FilePath $PsExeFull -ArgumentList $args -WindowStyle Normal | Out-Null
    return
  }
} catch {}

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

# Garantir foco rápido
$window.Topmost = $true
$window.Add_Loaded({
  try {
    $this.Activate()      | Out-Null
    $this.BringIntoView() | Out-Null
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(150)
    $t.Add_Tick({ param($s,$e) try { $this.Activate() | Out-Null } catch {} ; $s.Stop() })
    $t.Start()
  } catch {}
})

# Arrastar (sem barra de título)
$window.Add_MouseLeftButtonDown({
  if ($_.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) {
    try { $window.DragMove() } catch {}
  }
})

# Controles
$BtnNow    = $window.FindName('BtnNow')
$BtnDelay1 = $window.FindName('BtnDelay1')
$BtnDelay2 = $window.FindName('BtnDelay2')

# (Opcional) bloquear fechar no X: o usuário deve escolher uma opção
$script:closingHandler = [System.ComponentModel.CancelEventHandler]{ param($s,[System.ComponentModel.CancelEventArgs]$e) $e.Cancel = $true }
$window.add_Closing($script:closingHandler)
function Allow-Close([System.Windows.Window]$win) { if ($win -and $script:closingHandler) { $win.remove_Closing($script:closingHandler) } }

# -------- Eventos (UI thread com Add_Click) --------
$handlerNow = [System.Windows.RoutedEventHandler]{
  param($s,$e)
  Save-Answer 'NOW'
  Allow-Close $window
  $window.Close()
}
$handlerD1 = [System.Windows.RoutedEventHandler]{
  param($s,$e)
  Save-Answer '3600'
  Allow-Close $window
  $window.Close()
}
$handlerD2 = [System.Windows.RoutedEventHandler]{
  param($s,$e)
  Save-Answer '7200'
  Allow-Close $window
  $window.Close()
}

$BtnNow.add_Click($handlerNow)
$BtnDelay1.add_Click($handlerD1)
$BtnDelay2.add_Click($handlerD2)

# Mostrar
$null = $window.ShowDialog()
