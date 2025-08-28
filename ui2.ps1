#requires -version 5.1
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ==================== TEXTOS / RÓTULOS ====================
$Txt_WindowTitle          = 'Agendar Execução'
$Txt_HeaderTitle          = 'Atualização Obrigatória'
$Txt_HeaderSubtitle       = 'Chegou a hora agendada. A execução é obrigatória.'
$Txt_ActionLabel          = 'Ação:'
$Txt_ActionLine1          = 'Realizar o update do Windows 10 para o Windows 11'
$Txt_ActionLine2          = 'Tempo Estimado: 20 a 30 minutos'
$Txt_BtnNow               = 'Executar agora'
# ==========================================================

# ---------- Garantir STA ----------
$PsExeFull = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
try {
  if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA' -and $PSCommandPath) {
    Start-Process -FilePath $PsExeFull -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File', $PSCommandPath) | Out-Null
    return
  }
} catch {}

# ---------- Salvar resposta ----------
$AnswerPath = 'C:\ProgramData\answer.txt'
if (-not (Test-Path 'C:\ProgramData')) {
  New-Item -Path 'C:\ProgramData' -ItemType Directory -Force | Out-Null
}
function Save-Answer([string]$text){
  try { [IO.File]::AppendAllText($AnswerPath, $text + [Environment]::NewLine, [Text.Encoding]::UTF8) } catch {}
}

# ==================== UI (WPF) ====================
Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Txt_WindowTitle"
        Width="520" MinHeight="250" SizeToContent="Height"
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
        <TextBlock Text="$Txt_HeaderTitle" Foreground="#e5e7eb"
                   FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Text="$Txt_HeaderSubtitle"
                   Foreground="#f87171" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
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

    <!-- Botão único -->
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

# Carrega a janela
$reader  = New-Object System.Xml.XmlNodeReader $xaml
$window  = [Windows.Markup.XamlReader]::Load($reader)
if (-not $window) { throw "Falha ao carregar a UI a partir do XAML." }

# Garantir foco
$window.Topmost = $true
$window.Add_Loaded({
  try { $this.Activate() | Out-Null; $this.BringIntoView() | Out-Null } catch {}
})

# Arrastar (sem barra de título)
$window.Add_MouseLeftButtonDown({
  if ($_.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) {
    try { $window.DragMove() } catch {}
  }
})

# Impedir fechar sem escolher
$script:closingHandler = [System.ComponentModel.CancelEventHandler]{ param($s,[System.ComponentModel.CancelEventArgs]$e) $e.Cancel = $true }
$window.add_Closing($script:closingHandler)
function Allow-Close([System.Windows.Window]$win) { if ($win -and $script:closingHandler) { $win.remove_Closing($script:closingHandler) } }

# Handler único
$BtnNow = $window.FindName('BtnNow')
$handlerNow = [System.Windows.RoutedEventHandler]{
  param($s,$e)
  Save-Answer 'Executar agora'
  Allow-Close $window
  $window.Close()
}
$BtnNow.add_Click($handlerNow)

# Mostrar
$null = $window.ShowDialog()
