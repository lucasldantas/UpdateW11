#requires -version 5.1
param([switch]$Spawned)  # interno: indica que já estamos no processo destacado

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ====================== VARIÁVEIS EDITÁVEIS ======================
$AnswerFile         = 'C:\ProgramData\Answer.txt'

$Txt_WindowTitle    = 'Agendar Execução'
$Txt_HeaderTitle    = 'Atualização obrigatória'
$Txt_HeaderSubtitle = 'Você pode executar agora ou adiar por até 2 horas.'
$Txt_ActionLabel    = 'Ação:'
$Txt_ActionLine1    = 'Realizar o update do Windows 10 para o Windows 11'
$Txt_ActionLine2    = 'Tempo Estimado: 20 a 30 minutos'

$Txt_BtnNow         = 'Executar agora'
$Txt_Btn1H          = 'Adiar 1 hora'
$Txt_Btn2H          = 'Adiar 2 horas'
# ================================================================

# --- evita bloquear sua console: se não for Spawned, relança oculto e sai ---
if (-not $Spawned) {
  $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') { $psExe = "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" }
  $self  = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
  Start-Process -FilePath $psExe -ArgumentList @(
    '-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden',
    '-File',"`"$self`"","-Spawned"
  ) -WindowStyle Hidden | Out-Null
  return
}

# --- a partir daqui é só a UI (no processo destacado) ---
# garante pasta do arquivo
try {
  $dir = Split-Path -LiteralPath $AnswerFile
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
} catch {}

Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Txt_WindowTitle"
        Width="600" Height="260"
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

    <!-- Cabeçalho (sem cantos arredondados) -->
    <Border Grid.Row="0" Background="#111827" Padding="16">
      <StackPanel>
        <TextBlock Name="TitleText" Text="$Txt_HeaderTitle"
                   Foreground="#e5e7eb" FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Name="SubText" Text="$Txt_HeaderSubtitle"
                   Foreground="#9ca3af" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>

    <!-- Corpo -->
    <Border Grid.Row="1" Background="#0b1220" Padding="16" Margin="0,12,0,12">
      <StackPanel>
        <TextBlock Text="$Txt_ActionLabel" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" Margin="0,0,0,6"/>
        <TextBlock Text="$Txt_ActionLine1" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" TextWrapping="Wrap" Margin="0,0,0,4"/>
        <TextBlock Text="$Txt_ActionLine2" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" TextWrapping="Wrap"/>
      </StackPanel>
    </Border>

    <!-- Botões (retangulares, tamanhos fixos) -->
    <DockPanel Grid.Row="2">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button Name="BtnNow" Content="$Txt_BtnNow" Margin="8,0,0,0" Padding="16,8"
                Background="#0078d4" Foreground="White" FontFamily="Segoe UI" FontWeight="SemiBold"
                BorderBrush="#0a5ea6" BorderThickness="1" Cursor="Hand" Width="180" Height="40"/>
        <Button Name="Btn1H" Content="$Txt_Btn1H" Margin="8,0,0,0" Padding="16,8"
                Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI"
                BorderBrush="#374151" BorderThickness="1" Cursor="Hand" Width="180" Height="40"/>
        <Button Name="Btn2H" Content="$Txt_Btn2H" Margin="8,0,0,0" Padding="16,8"
                Background="#1f2937" Foreground="#e5e7eb" FontFamily="Segoe UI"
                BorderBrush="#374151" BorderThickness="1" Cursor="Hand" Width="180" Height="40"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
"@

# Instancia a janela
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Bloqueia fechar sem escolha (Alt+F4)
$script:closingHandler = [System.ComponentModel.CancelEventHandler]{ param($s,[System.ComponentModel.CancelEventArgs]$e) $e.Cancel = $true }
$window.add_Closing($script:closingHandler)
function Allow-Close([System.Windows.Window]$win) { if ($win -and $script:closingHandler) { $win.remove_Closing($script:closingHandler) } }

# Arrastar janela
$window.Add_MouseLeftButtonDown({
  if ($_.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) {
    try { $window.DragMove() } catch {}
  }
})

# Garante foco/topmost real
$window.Add_Loaded({
  try {
    $this.Activate() | Out-Null
    $t = New-Object System.Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(120)
    $t.Add_Tick({ param($s,$e) try { $this.Activate() | Out-Null } catch {} ; $s.Stop() })
    $t.Start()
  } catch {}
})

# Botões
$BtnNow = $window.FindName('BtnNow')
$Btn1H  = $window.FindName('Btn1H')
$Btn2H  = $window.FindName('Btn2H')

function Write-Answer([string]$val) {
  try { [IO.File]::WriteAllText($AnswerFile, $val, [Text.Encoding]::UTF8) } catch {}
  Allow-Close $window
  $window.Close()
}

$BtnNow.Add_Click({ Write-Answer 'NOW' })
$Btn1H.Add_Click({ Write-Answer '1H'  })
$Btn2H.Add_Click({ Write-Answer '2H'  })

# Exibe
$null = $window.ShowDialog()
