#requires -version 5.1
<#
    Single-file: Launcher + UI
    - Executa UI WPF em TODAS as sessões interativas.
    - UI é TopMost, sem fechar sem escolha, sem cantos arredondados.
    - Grava C:\ProgramData\Answer.txt com NOW / 1H / 2H.
#>

param(
  [switch]$UiOnly  # uso interno: modo UI apenas (o launcher chama este mesmo arquivo com -UiOnly)
)

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Stop'

# ==================== CONFIG / TEXTOS (edite aqui) ====================
$AnswerFile   = 'C:\ProgramData\Answer.txt'
$AppRoot      = 'C:\ProgramData\UpdateW11'  # usado só para salvar logs/artefatos se quiser expandir

# Textos do UI
$Txt_WindowTitle    = 'Agendar Execução'
$Txt_HeaderTitle    = 'Atualização Obrigatória'
$Txt_HeaderSubtitle = 'Você pode executar agora ou adiar por até 2 horas.'
$Txt_ActionLabel    = 'Ação:'
$Txt_ActionLine1    = 'Realizar o update do Windows 10 para o Windows 11'
$Txt_ActionLine2    = 'Tempo Estimado: 20 a 30 minutos'

# Rótulos dos botões
$Txt_BtnNow   = 'Executar agora'
$Txt_Btn1H    = 'Adiar 1 hora'
$Txt_Btn2H    = 'Adiar 2 horas'
# =====================================================================

# Garante diretórios
try { if (-not (Test-Path -LiteralPath (Split-Path $AnswerFile))) { New-Item -ItemType Directory -Path (Split-Path $AnswerFile) -Force | Out-Null } } catch {}

# ------------------------- MODO UI -------------------------
if ($UiOnly) {
  # Garante STA
  if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    Start-Process -FilePath $ps -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$PSCommandPath`"","-UiOnly") | Out-Null
    return
  }

  Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

  # XAML (sem cantos arredondados, TopMost, sem botão fechar)
  [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Txt_WindowTitle"
        Width="540" MinHeight="300" SizeToContent="Height"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" Background="#0f172a"
        WindowStyle="None" ShowInTaskbar="True"
        AllowsTransparency="False"
        Topmost="True">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Cabeçalho (retangular) -->
    <Border Grid.Row="0" Background="#111827" Padding="16">
      <StackPanel>
        <TextBlock Name="TitleText" Text="$Txt_HeaderTitle" Foreground="#e5e7eb"
                   FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Name="SubText" Text="$Txt_HeaderSubtitle"
                   Foreground="#9ca3af" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>

    <!-- Corpo -->
    <Border Grid.Row="2" Background="#0b1220" Padding="16" Margin="0,16,0,16">
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

    <!-- Botões (retangulares) -->
    <DockPanel Grid.Row="3">
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

  # Carrega a janela
  $reader = New-Object System.Xml.XmlNodeReader $xaml
  $window = [Windows.Markup.XamlReader]::Load($reader)

  # Impede fechar (sem escolha)
  $script:closingHandler = [System.ComponentModel.CancelEventHandler]{ param($s,[System.ComponentModel.CancelEventArgs]$e) $e.Cancel = $true }
  $window.add_Closing($script:closingHandler)
  function Allow-Close([System.Windows.Window]$win) { if ($win -and $script:closingHandler) { $win.remove_Closing($script:closingHandler) } }

  # Arraste da janela (clique em qualquer lugar)
  $window.Add_MouseLeftButtonDown({
    if ($_.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) { try { $window.DragMove() } catch {} }
  })

  # Foco após abrir
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

  # Botões
  $BtnNow = $window.FindName('BtnNow')
  $Btn1H  = $window.FindName('Btn1H')
  $Btn2H  = $window.FindName('Btn2H')

  # Escrita segura do Answer.txt
  function Write-Answer([string]$val) {
    try { [IO.File]::WriteAllText($AnswerFile, $val, [Text.Encoding]::UTF8) } catch {}
    Allow-Close $window
    $window.Close()
  }

  $BtnNow.Add_Click({ Write-Answer 'NOW' })
  $Btn1H.Add_Click({ Write-Answer '1H'  })
  $Btn2H.Add_Click({ Write-Answer '2H'  })

  $null = $window.ShowDialog()
  return
}

# ------------------------- MODO LAUNCHER (default) -------------------------
# PowerShell 64-bit para lançar a UI
$Ps64 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') { $Ps64 = "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" }

# Comando para chamar ESTE arquivo com -UiOnly
$Self = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$cmd  = "`"$Ps64`" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$Self`" -UiOnly"

# C#: enumerar sessões + lançar em cada uma (namespace novo para evitar conflito)
$source = @"
using System;
using System.Linq;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.Collections.Generic;

namespace XLaunch.V2 {

  public enum WTS_CONNECTSTATE_CLASS { Active, Connected, ConnectQuery, Shadow, Disconnected, Idle, Listen, Reset, Down, Init }

  [StructLayout(LayoutKind.Sequential)]
  public struct WTS_SESSION_INFO {
    public Int32 SessionID;
    public IntPtr pWinStationName;
    public WTS_CONNECTSTATE_CLASS State;
  }

  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct STARTUPINFO {
    public int cb; public string lpReserved, lpDesktop, lpTitle;
    public int dwX,dwY,dwXSize,dwYSize,dwXCountChars,dwYCountChars,dwFillAttribute,dwFlags;
    public short wShowWindow, cbReserved2;
    public IntPtr lpReserved2,hStdInput,hStdOutput,hStdError;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct PROCESS_INFORMATION { public IntPtr hProcess,hThread; public int dwProcessId,dwThreadId; }

  public static class Native {
    [DllImport("wtsapi32.dll", SetLastError=true)] public static extern bool WTSEnumerateSessions(IntPtr h, int r, int v, out IntPtr p, out int c);
    [DllImport("wtsapi32.dll")] public static extern void WTSFreeMemory(IntPtr p);
    [DllImport("wtsapi32.dll", SetLastError=true)] public static extern bool WTSQueryUserToken(uint s, out IntPtr t);
    [DllImport("userenv.dll", SetLastError=true)] public static extern bool CreateEnvironmentBlock(out IntPtr e, IntPtr t, bool i);
    [DllImport("userenv.dll", SetLastError=true)] public static extern bool DestroyEnvironmentBlock(IntPtr e);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool CreateProcessAsUser(IntPtr t, string app, string cmd, IntPtr pa, IntPtr ta, bool inh, uint flags, IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr p, UInt32 a, out IntPtr t);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool i, int pid);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool CreateProcessWithTokenW(IntPtr t, UInt32 f, string app, string cmd, UInt32 cf, IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);

    public const UInt32 TOKEN_ASSIGN_PRIMARY=0x0001, TOKEN_QUERY=0x0008;
    public const UInt32 CREATE_UNICODE_ENVIRONMENT=0x00000400, CREATE_NEW_CONSOLE=0x00000010, LOGON_WITH_PROFILE=0x1;

    public static IEnumerable<Tuple<uint,WTS_CONNECTSTATE_CLASS>> EnumerateSessions() {
      IntPtr p; int n; if(!WTSEnumerateSessions(IntPtr.Zero,0,1,out p,out n)) yield break;
      int sz = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
      try {
        for(int i=0;i<n;i++){
          var rec=new IntPtr(p.ToInt64()+i*sz);
          var si=(WTS_SESSION_INFO)Marshal.PtrToStructure(rec,typeof(WTS_SESSION_INFO));
          yield return Tuple.Create((uint)si.SessionID, si.State);
        }
      } finally { WTSFreeMemory(p); }
    }

    public static IEnumerable<uint> ExplorerSessions() {
      return Process.GetProcessesByName("explorer").Select(p => (uint)p.SessionId).Distinct();
    }

    public static bool LaunchWithExplorerToken(int pid, string cmd){
      IntPtr hp = OpenProcess(0x1000|0x0400,false,pid); // QUERY_LIMITED_INFORMATION | QUERY_INFORMATION
      if(hp==IntPtr.Zero) return false;
      IntPtr ht; bool ok = OpenProcessToken(hp, TOKEN_ASSIGN_PRIMARY|TOKEN_QUERY, out ht);
      CloseHandle(hp); if(!ok) return false;
      var si=new STARTUPINFO(); si.cb=Marshal.SizeOf(typeof(STARTUPINFO)); si.lpDesktop=@"winsta0\default";
      PROCESS_INFORMATION pi;
      ok = CreateProcessWithTokenW(ht, LOGON_WITH_PROFILE, null, cmd, CREATE_UNICODE_ENVIRONMENT|CREATE_NEW_CONSOLE, IntPtr.Zero, null, ref si, out pi);
      if(ok){ CloseHandle(pi.hThread); CloseHandle(pi.hProcess); }
      CloseHandle(ht); return ok;
    }

    public static bool LaunchViaWTS(uint sid, string cmd){
      IntPtr ut; if(!WTSQueryUserToken(sid,out ut)) return false;
      IntPtr env; CreateEnvironmentBlock(out env, ut, false);
      var si=new STARTUPINFO(); si.cb=Marshal.SizeOf(typeof(STARTUPINFO)); si.lpDesktop=@"winsta0\default";
      PROCESS_INFORMATION pi;
      bool ok=CreateProcessAsUser(ut,null,cmd,IntPtr.Zero,IntPtr.Zero,false,CREATE_UNICODE_ENVIRONMENT|CREATE_NEW_CONSOLE,env,null,ref si,out pi);
      if(ok){ CloseHandle(pi.hThread); CloseHandle(pi.hProcess); }
      if(env!=IntPtr.Zero) DestroyEnvironmentBlock(env);
      CloseHandle(ut);
      return ok;
    }
  }
}
"@
# Compila apenas se ainda não existir
if (-not ([AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetType('XLaunch.V2.Native', $false) } | Where-Object { $_ })) {
  Add-Type -TypeDefinition $source -Language CSharp
}

# Inicia TermService para WTS fallback
try { Start-Service -Name TermService -ErrorAction SilentlyContinue | Out-Null } catch {}

# Coleta sessões: corrige retorno em tupla
$wtsTuples = [XLaunch.V2.Native]::EnumerateSessions()
$wts = foreach($s in $wtsTuples){ if ($s) { [uint32]$s.Item1 } }
$exp = [XLaunch.V2.Native]::ExplorerSessions()
$sessions = ($wts + $exp) | Sort-Object -Unique

$ok=@(); $fail=@()
foreach($sid in $sessions){
  # Tenta com token do Explorer da própria sessão
  $expPid = (Get-Process explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sid } | Select-Object -First 1).Id
  $launched = $false
  if ($expPid) { $launched = [XLaunch.V2.Native]::LaunchWithExplorerToken($expPid, $cmd) }
  if (-not $launched) { $launched = [XLaunch.V2.Native]::LaunchViaWTS([uint32]$sid, $cmd) }
  if ($launched) { $ok += $sid } else { $fail += $sid }
}

Write-Host ("Sessões: {0} | Sucesso: {1} | Falha: {2}" -f $sessions.Count, $ok.Count, $fail.Count)
if ($fail.Count) { Write-Warning ("Falhas: " + ($fail -join ',')) }

# Se não abriu em ninguém, grava um marcador
if (($ok.Count -eq 0) -and -not (Test-Path -LiteralPath $AnswerFile)) {
  try { [IO.File]::WriteAllText($AnswerFile,'NOUSER',[Text.Encoding]::UTF8) } catch {}
}
