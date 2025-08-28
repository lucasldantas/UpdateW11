#requires -version 5.1
param(
  [switch]$UiOnly
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ==================== CONFIG / TEXTOS ====================
$AnswerFile   = 'C:\ProgramData\Answer.txt'
$AppRoot      = 'C:\ProgramData\UpdateW11'
$UiLog        = Join-Path $AppRoot 'ui-debug.log'

$Txt_WindowTitle    = 'Agendar Execução'
$Txt_HeaderTitle    = 'Atualização Obrigatória'
$Txt_HeaderSubtitle = 'Você pode executar agora ou adiar por até 2 horas.'
$Txt_ActionLabel    = 'Ação:'
$Txt_ActionLine1    = 'Realizar o update do Windows 10 para o Windows 11'
$Txt_ActionLine2    = 'Tempo Estimado: 20 a 30 minutos'

$Txt_BtnNow   = 'Executar agora'
$Txt_Btn1H    = 'Adiar 1 hora'
$Txt_Btn2H    = 'Adiar 2 horas'
# =========================================================

# pastas
try {
  $dirAns = Split-Path $AnswerFile
  if ($dirAns -and -not (Test-Path $dirAns)) { New-Item -ItemType Directory -Path $dirAns -Force | Out-Null }
  if (-not (Test-Path $AppRoot)) { New-Item -ItemType Directory -Path $AppRoot -Force | Out-Null }
} catch {}

function Write-UiLog([string]$msg){
  try {
    $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    Add-Content -LiteralPath $UiLog -Value "[$stamp] $msg" -Encoding UTF8
  } catch {}
}

# -------------------------- MODO UI --------------------------
if ($UiOnly) {
  try {
    # força STA
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
      $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
      Write-UiLog "Rerun UI in STA"
      Start-Process -FilePath $ps -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$PSCommandPath`"","-UiOnly") | Out-Null
      return
    }

    Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

    # trata exceções não tratadas do WPF (evita fechar mudo)
    [System.Windows.Application]::Current.DispatcherUnhandledException += {
      param($s,[System.Windows.Threading.DispatcherUnhandledExceptionEventArgs]$e)
      Write-UiLog ("DispatcherUnhandledException: " + $e.Exception.Message)
      try { [System.Windows.MessageBox]::Show($e.Exception.ToString(),'Erro na UI','OK','Error') | Out-Null } catch {}
      $e.Handled = $true
    }

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

    <Border Grid.Row="0" Background="#111827" Padding="16">
      <StackPanel>
        <TextBlock Name="TitleText" Text="$Txt_HeaderTitle" Foreground="#e5e7eb"
                   FontFamily="Segoe UI" FontWeight="Bold" FontSize="20"/>
        <TextBlock Name="SubText" Text="$Txt_HeaderSubtitle"
                   Foreground="#9ca3af" FontFamily="Segoe UI" FontSize="12" Margin="0,6,0,0"/>
      </StackPanel>
    </Border>

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

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    if (-not $window) { throw "Falha ao carregar XAML (window nulo)." }

    # impedir fechar sem escolha
    $script:closingHandler = [System.ComponentModel.CancelEventHandler]{ param($s,[System.ComponentModel.CancelEventArgs]$e) $e.Cancel = $true }
    $window.add_Closing($script:closingHandler)
    function Allow-Close([System.Windows.Window]$win) { if ($win -and $script:closingHandler) { $win.remove_Closing($script:closingHandler) } }

    # arrastar
    $window.Add_MouseLeftButtonDown({
      if ($_.ButtonState -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        try { $window.DragMove() } catch {}
      }
    })

    # foco garantido
    $window.Add_Loaded({
      try {
        $this.Activate() | Out-Null
        $t = New-Object System.Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(150)
        $t.Add_Tick({ param($s,$e) try { $this.Activate() | Out-Null } catch {} ; $s.Stop() })
        $t.Start()
      } catch {}
    })

    $BtnNow = $window.FindName('BtnNow')
    $Btn1H  = $window.FindName('Btn1H')
    $Btn2H  = $window.FindName('Btn2H')

    function Write-Answer([string]$val) {
      try { [IO.File]::WriteAllText($AnswerFile, $val, [Text.Encoding]::UTF8) } catch { Write-UiLog "Write Answer failed: $($_.Exception.Message)" }
      Allow-Close $window
      $window.Close()
    }

    $BtnNow.Add_Click({ Write-Answer 'NOW' })
    $Btn1H.Add_Click({ Write-Answer '1H'  })
    $Btn2H.Add_Click({ Write-Answer '2H'  })

    Write-UiLog "ShowDialog()"
    $null = $window.ShowDialog()
    Write-UiLog "UI closed by user choice."
  }
  catch {
    $msg = "Falha ao exibir UI:`n$($_.Exception.Message)"
    Write-UiLog $msg
    try {
      Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue | Out-Null
      [System.Windows.MessageBox]::Show($msg,'Erro','OK','Error') | Out-Null
    } catch {}
    Start-Sleep -Seconds 2
  }
  return
}

# -------------------------- MODO LAUNCHER --------------------------
# caminho PS 64-bit
$Ps64 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') { $Ps64 = "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" }

# comando para chamar o próprio arquivo com -UiOnly
$Self = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$cmd  = "`"$Ps64`" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$Self`" -UiOnly"

# C# para lançar nas sessões (namespace novo p/ evitar conflitos)
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
      IntPtr hp = OpenProcess(0x1000|0x0400,false,pid);
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

if (-not ([AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetType('XLaunch.V2.Native', $false) } | Where-Object { $_ })) {
  Add-Type -TypeDefinition $source -Language CSharp
}

try { Start-Service -Name TermService -ErrorAction SilentlyContinue | Out-Null } catch {}

$wtsTuples = [XLaunch.V2.Native]::EnumerateSessions()
$wts = foreach($s in $wtsTuples){ if ($s) { [uint32]$s.Item1 } }
$exp = [XLaunch.V2.Native]::ExplorerSessions()
$sessions = ($wts + $exp) | Sort-Object -Unique

$ok=@(); $fail=@()
foreach($sid in $sessions){
  $expPid = (Get-Process explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sid } | Select-Object -First 1).Id
  $launched = $false
  if ($expPid) { $launched = [XLaunch.V2.Native]::LaunchWithExplorerToken($expPid, $cmd) }
  if (-not $launched) { $launched = [XLaunch.V2.Native]::LaunchViaWTS([uint32]$sid, $cmd) }
  if ($launched) { $ok += $sid } else { $fail += $sid }
}

Write-Host ("Sessões: {0} | Sucesso: {1} | Falha: {2}" -f $sessions.Count, $ok.Count, $fail.Count)
if ($fail.Count) { Write-Warning ("Falhas: " + ($fail -join ',')) }

if (($ok.Count -eq 0) -and -not (Test-Path -LiteralPath $AnswerFile)) {
  try { [IO.File]::WriteAllText($AnswerFile,'NOUSER',[Text.Encoding]::UTF8) } catch {}
}
