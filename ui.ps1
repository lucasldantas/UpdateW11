#requires -version 5.1
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Stop'

# ========== VARIÁVEIS (edite aqui) ==========
$AnswerFile  = 'C:\ProgramData\Answer.txt'
$UiScript    = 'C:\ProgramData\ShowChoice.ps1'

# Textos do UI
$TitleText   = 'Atualização obrigatória'
$MainText    = 'Você pode executar agora ou adiar.'
$SubText     = 'Escolha uma opção abaixo.'

# Rótulos dos botões
$BtnNowText  = 'Executar agora'
$Btn1HText   = 'Adiar 1 hora'
$Btn2HText   = 'Adiar 2 horas'
# ============================================

# ========= UI (compatível; sem cantos arredondados) =========
$ui = @'
param(
  [string]$TitleText,
  [string]$MainText,
  [string]$SubText,
  [string]$BtnNowText,
  [string]$Btn1HText,
  [string]$Btn2HText
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# mover janela sem borda (C# mínimo; sem System.Drawing.Drawing2D)
if (-not ([AppDomain]::CurrentDomain.GetAssemblies() | % { $_.GetType('GDL.Win.Move', $false) } | ? { $_ })) {
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace GDL.Win {
  public static class Move {
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);
    public const int WM_NCLBUTTONDOWN = 0xA1;
    public const int HTCAPTION = 0x2;
  }
}
"@
}

# Paleta (renomeadas para evitar conflito com textos)
$clrBg      = [System.Drawing.Color]::FromArgb(32,32,36)
$clrPanelBg = [System.Drawing.Color]::FromArgb(40,40,46)
$clrAccent  = [System.Drawing.Color]::FromArgb(0,120,212)
$clrText    = [System.Drawing.Color]::FromArgb(230,230,235)
$clrSubtxt  = [System.Drawing.Color]::FromArgb(180,180,190)
$clrBtnBg   = [System.Drawing.Color]::FromArgb(58,58,66)

# Controle de encerramento: só fecha se houve escolha
$script:ChoiceMade = $false

# Form
$form = New-Object System.Windows.Forms.Form
$form.Text = $TitleText
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(520,240)
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.BackColor = $clrBg
$form.FormBorderStyle = 'None'     # quadrado (sem cantos arredondados)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.KeyPreview = $true

# bloqueia ESC e Alt+F4
$form.Add_KeyDown({ param($s,$e) if ($e.KeyCode -eq 'Escape') { $e.Handled = $true } })
$form.Add_FormClosing({
  param($s,[System.Windows.Forms.FormClosingEventArgs]$e)
  if (-not $script:ChoiceMade) { $e.Cancel = $true }
})

# Title simples (sem botão fechar)
$title = New-Object System.Windows.Forms.Panel
$title.Height = 42; $title.Dock = 'Top'; $title.BackColor = $clrPanelBg
$form.Controls.Add($title)
$title.Add_MouseDown({ param($s,$e)
  if($e.Button -eq 'Left'){
    [GDL.Win.Move]::ReleaseCapture() | Out-Null
    [GDL.Win.Move]::SendMessage($form.Handle, [GDL.Win.Move]::WM_NCLBUTTONDOWN, [GDL.Win.Move]::HTCAPTION, 0) | Out-Null
  }
})

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = $TitleText
$lbl.AutoSize = $true
$lbl.ForeColor = $clrText
$lbl.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
$lbl.Location = New-Object System.Drawing.Point(14,10)
$title.Controls.Add($lbl)

# Corpo
$body = New-Object System.Windows.Forms.Panel
$body.Dock='Fill'; $body.Padding='20,16,20,20'; $body.BackColor=$clrBg
$form.Controls.Add($body)

$lbl1 = New-Object System.Windows.Forms.Label
$lbl1.Text = $MainText
$lbl1.ForeColor=$clrText; $lbl1.Font=New-Object System.Drawing.Font('Segoe UI Semibold',12)
$lbl1.AutoSize=$true; $lbl1.Location=New-Object System.Drawing.Point(8,8)
$body.Controls.Add($lbl1)

$lbl2 = New-Object System.Windows.Forms.Label
$lbl2.Text = $SubText              # <- agora é texto, não cor
$lbl2.ForeColor=$clrSubtxt; $lbl2.Font=New-Object System.Drawing.Font('Segoe UI',9)
$lbl2.AutoSize=$true; $lbl2.Location=New-Object System.Drawing.Point(8,36)
$body.Controls.Add($lbl2)

# Área dos botões
$flow = New-Object System.Windows.Forms.FlowLayoutPanel
$flow.Dock='Bottom'
$flow.Height=86
$flow.Padding='8,8,8,8'
$flow.FlowDirection='LeftToRight'
$flow.WrapContents=$false
$flow.BackColor=$clrBg
$body.Controls.Add($flow)

function New-ChoiceButton([string]$text,[System.Drawing.Color]$bgColor,[System.Drawing.Color]$fgColor){
  $b = New-Object System.Windows.Forms.Button
  $b.Text=$text
  $b.Width=160; $b.Height=44
  $b.Margin='8,8,8,8'
  $b.FlatStyle='Flat'
  $b.FlatAppearance.BorderSize=0
  $b.BackColor=$bgColor
  $b.ForeColor=$fgColor
  return $b
}

function Write-Answer([string]$val){
  try { [System.IO.File]::WriteAllText('[[ANSWERFILE]]',$val,[Text.Encoding]::UTF8) } catch {}
  $script:ChoiceMade = $true
  $form.Close()
}

$btnNow = New-ChoiceButton $BtnNowText  $clrAccent ([System.Drawing.Color]::White)
$btn1H  = New-ChoiceButton $Btn1HText   $clrBtnBg   $clrText
$btn2H  = New-ChoiceButton $Btn2HText   $clrBtnBg   $clrText

$btnNow.Add_Click({ Write-Answer 'NOW' })
$btn1H.Add_Click({ Write-Answer '1H' })
$btn2H.Add_Click({ Write-Answer '2H' })

$flow.Controls.AddRange(@($btnNow,$btn1H,$btn2H))

[void][System.Windows.Forms.Application]::Run($form)
'@

# injeta caminho do arquivo
$ui = $ui.Replace('[[ANSWERFILE]]', $AnswerFile)

# garante pasta
$dir = Split-Path $UiScript
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Set-Content -Path $UiScript -Value $ui -Encoding UTF8 -Force

# ========= BROADCAST (todas as sessões) =========
# C# mínimo (sem System.Drawing) para lançar nas sessões
$launcherLoaded = [AppDomain]::CurrentDomain.GetAssemblies() | % { $_.GetType('GDL.Broadcast.AllSessions', $false) } | ? { $_ }
if (-not $launcherLoaded) {
  $src = @"
using System;
using System.Diagnostics;
using System.Linq;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace GDL.Broadcast {

  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct STARTUPINFO {
    public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
    public int dwX; public int dwY; public int dwXSize; public int dwYSize;
    public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute;
    public int dwFlags; public short wShowWindow; public short cbReserved2;
    public IntPtr lpReserved2; public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct PROCESS_INFORMATION { public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId; }

  public enum WTS_CONNECTSTATE_CLASS { Active, Connected, ConnectQuery, Shadow, Disconnected, Idle, Listen, Reset, Down, Init }
  [StructLayout(LayoutKind.Sequential)]
  public struct WTS_SESSION_INFO {
    public Int32 SessionID;
    public IntPtr pWinStationName;
    public WTS_CONNECTSTATE_CLASS State;
  }

  public static class Native {
    [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);
    [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr ProcessHandle, UInt32 DesiredAccess, out IntPtr TokenHandle);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool CreateProcessWithTokenW(IntPtr hToken, UInt32 dwLogonFlags, string lpApplicationName, string lpCommandLine, UInt32 dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("wtsapi32.dll", SetLastError=true)] public static extern bool WTSEnumerateSessions(IntPtr hServer, int Reserved, int Version, out IntPtr ppSessionInfo, out int pCount);
    [DllImport("wtsapi32.dll")] public static extern void WTSFreeMemory(IntPtr pMemory);
    [DllImport("wtsapi32.dll", SetLastError=true)] public static extern bool WTSQueryUserToken(uint SessionId, out IntPtr Token);
    [DllImport("userenv.dll", SetLastError=true)] public static extern bool CreateEnvironmentBlock(out IntPtr lpEnvironment, IntPtr hToken, bool bInherit);
    [DllImport("userenv.dll", SetLastError=true)] public static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool CreateProcessAsUser(IntPtr hToken, string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

    public const UInt32 LOGON_WITH_PROFILE = 0x00000001;
    public const UInt32 CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    public const UInt32 CREATE_NEW_CONSOLE = 0x00000010;

    public static IEnumerable<uint> EnumerateSessions() {
      IntPtr pInfo; int count;
      if (!WTSEnumerateSessions(IntPtr.Zero, 0, 1, out pInfo, out count)) yield break;
      int size = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
      try {
        for (int i=0;i<count;i++){
          IntPtr rec = new IntPtr(pInfo.ToInt64() + i*size);
          WTS_SESSION_INFO si = (WTS_SESSION_INFO)Marshal.PtrToStructure(rec, typeof(WTS_SESSION_INFO));
          yield return (uint)si.SessionID;
        }
      } finally { WTSFreeMemory(pInfo); }
    }

    public static bool LaunchWithExplorerToken(int pid, string cmdLine) {
      IntPtr hProc = OpenProcess(0x1000 | 0x0400, false, pid); // QUERY_LIMITED_INFORMATION | QUERY_INFORMATION
      if (hProc == IntPtr.Zero) return false;
      IntPtr hTok;
      bool okTok = OpenProcessToken(hProc, 0x0001 | 0x0008, out hTok); // ASSIGN_PRIMARY | QUERY
      CloseHandle(hProc);
      if (!okTok) return false;

      STARTUPINFO si = new STARTUPINFO(); si.cb = Marshal.SizeOf(typeof(STARTUPINFO)); si.lpDesktop = @"winsta0\default";
      PROCESS_INFORMATION pi;
      bool ok = CreateProcessWithTokenW(hTok, LOGON_WITH_PROFILE, null, cmdLine, CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_CONSOLE, IntPtr.Zero, null, ref si, out pi);
      if (ok) { CloseHandle(pi.hThread); CloseHandle(pi.hProcess); }
      CloseHandle(hTok);
      return ok;
    }

    public static bool LaunchViaWTS(uint sessionId, string cmdLine) {
      IntPtr userToken;
      if (!WTSQueryUserToken(sessionId, out userToken)) return false;

      IntPtr env; CreateEnvironmentBlock(out env, userToken, false);
      STARTUPINFO si = new STARTUPINFO(); si.cb = Marshal.SizeOf(typeof(STARTUPINFO)); si.lpDesktop = @"winsta0\default";
      PROCESS_INFORMATION pi;
      bool ok = CreateProcessAsUser(userToken, null, cmdLine, IntPtr.Zero, IntPtr.Zero, false, CREATE_UNICODE_ENVIRONMENT, env, null, ref si, out pi);
      if (ok) { CloseHandle(pi.hThread); CloseHandle(pi.hProcess); }
      if (env != IntPtr.Zero) DestroyEnvironmentBlock(env);
      CloseHandle(userToken);
      return ok;
    }
  }

  public static class AllSessions {
    public static IEnumerable<uint> ExplorerSessions() {
      return Process.GetProcessesByName("explorer").Select(p => (uint)p.SessionId).Distinct();
    }
    public static bool LaunchInSession(uint sessionId, string cmdLine) {
      var exp = Process.GetProcessesByName("explorer").FirstOrDefault(p => (uint)p.SessionId == sessionId);
      if (exp != null && Native.LaunchWithExplorerToken(exp.Id, cmdLine)) return true;
      return Native.LaunchViaWTS(sessionId, cmdLine); // requer SYSTEM
    }
  }
}
"@
  Add-Type -TypeDefinition $src -Language CSharp
}

# Sobe TermService (para WTS fallback)
try { Start-Service -Name TermService -ErrorAction SilentlyContinue | Out-Null } catch {}

# PowerShell 64-bit (caso host 32-bit)
$PS64 = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') { $PS64 = "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" }

# grava UI
$null = New-Item -ItemType Directory -Path (Split-Path $UiScript) -Force -ErrorAction SilentlyContinue
Set-Content -Path $UiScript -Value $ui -Encoding UTF8 -Force

# monta comando, passando textos como parâmetros
$psArgs = @(
  '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$UiScript`"",
  '-TitleText',"`"$TitleText`"",
  '-MainText',"`"$MainText`"",
  '-SubText',"`"$SubText`"",
  '-BtnNowText',"`"$BtnNowText`"",
  '-Btn1HText',"`"$Btn1HText`"",
  '-Btn2HText',"`"$Btn2HText`""
) -join ' '
$cmd = "`"$PS64`" $psArgs"

# sessões via WTS + com explorer
$wts = [GDL.Broadcast.Native]::EnumerateSessions() | Select-Object -Unique
$exp = [GDL.Broadcast.AllSessions]::ExplorerSessions()
$sessions = ($wts + $exp) | Select-Object -Unique | Sort-Object

$ok=@(); $fail=@()
foreach($sid in $sessions){
  if([GDL.Broadcast.AllSessions]::LaunchInSession([uint32]$sid, $cmd)){ $ok+=$sid } else { $fail+=$sid }
}

Write-Host ("Sessões: {0} | Sucesso: {1} | Falha: {2}" -f $sessions.Count, $ok.Count, $fail.Count)
if($fail.Count -gt 0){ Write-Warning ("Falharam: " + ($fail -join ',')) }

# Se nada abriu, grava NOUSER
if(($ok.Count -eq 0) -and -not (Test-Path $AnswerFile)){
  Set-Content -Path $AnswerFile -Value 'NOUSER' -Encoding UTF8
}
