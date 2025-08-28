#requires -version 5.1
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ==================== TEXTOS / RÓTULOS ====================
$Txt_WindowTitle          = 'Agendar Execução'
$Txt_HeaderTitle          = 'Atualização Obrigatória'
$Txt_HeaderSubtitle       = 'Chegou a hora agendada. A execução é obrigatória.'
$Txt_ActionLabel          = 'Ação:'
$Txt_ActionLine1          = 'Realizar o update do Windows 10 para o Windows 11. Após iniciar o computador não pode ser desligado.'
$Txt_ActionLine2          = 'Tempo Estimado: 20 a 30 minutos'
$Txt_BtnNow               = 'Executar agora'

# ====== TIMER (5 minutos) ======
$TotalSeconds = 300  # 5 minutos
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
  try { [IO.File]::WriteAllText($AnswerPath, $text + [Environment]::NewLine, [Text.Encoding]::UTF8) } catch {}
}

# ==================== UI (WPF) ====================
Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

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
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="220"/>
        </Grid.ColumnDefinitions>

        <!-- Descrição -->
        <StackPanel Grid.Column="0" Margin="0,0,12,0">
          <TextBlock Text="$Txt_ActionLabel" Foreground="#cbd5e1" FontFamily="Segoe UI" FontSize="14" Margin="0,0,0,6"/>
          <TextBlock Text="$Txt_ActionLine1"
                     Foreground="#94a3b8" FontFamily="Consolas" FontSize="14"
                     Background="#0b1220" TextWrapping="Wrap" Margin="0,0,0,4"/>
          <TextBlock Text="$Txt_ActionLine2"
                     Foreground="#94a3b8" FontFamily="Consolas" FontSize="14"
                     Background="#0b1220" TextWrapping="Wrap"/>
        </StackPanel>

        <!-- Timer (contagem + progresso) -->
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

# Garantir foco/topmost
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

# ====== Controles ======
$BtnNow       = $window.FindName('BtnNow')
$LblCountdown = $window.FindName('LblCountdown')
$PbCountdown  = $window.FindName('PbCountdown')

# ====== Execução única (click ou timeout) ======
$script:done = $false
function Execute-Now {
  if ($script:done) { return }
  $script:done = $true
  try { $timer.Stop() } catch {}
  Save-Answer 'NOW'
  Allow-Close $window
  $window.Close()
}

# Botão/Enter disparam execução
$BtnNow.add_Click({ Execute-Now })
$window.Add_KeyDown({
  if ($_.Key -eq 'Enter') { Execute-Now }
})

# ====== Timer (DispatcherTimer 1s) ======
$script:remaining = $TotalSeconds
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)

$updateUi = {
  # Atualiza texto mm:ss e progresso
  $mm = [Math]::Floor($script:remaining / 60)
  $ss = $script:remaining % 60
  $LblCountdown.Text = ('{0:00}:{1:00}' -f $mm, $ss)
  $PbCountdown.Value = $TotalSeconds - $script:remaining
}

# Primeira pintura
& $updateUi

$timer.Add_Tick({
  if ($script:remaining -le 0) {
    # Timeout => executar automaticamente
    Execute-Now
    return
  }
  $script:remaining--
  & $updateUi
})

$timer.Start()

# Mostrar
$null = $window.ShowDialog()
