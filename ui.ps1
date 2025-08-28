#requires -version 5.1
<#
  Show-ChoiceToAllSessions.ps1
  - Exibe um formulário com 3 opções para cada sessão de usuário ATIVA
  - Grava a escolha em C:\ProgramData\answer.txt
  - Compatível com execução via PS Remoting (sem UI local)
#>

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Stop'

$ProgData      = 'C:\ProgramData'
$AnswerPath    = Join-Path $ProgData 'answer.txt'
$UiScriptPath  = Join-Path $ProgData 'ShowChoice-UI.ps1'
$HelperPath    = Join-Path $ProgData 'ShowChoice-Helper.ps1'
$TaskName      = 'GDL-ShowChoiceAllSessions-TEMP'

if (-not (Test-Path $ProgData)) { New-Item -Path $ProgData -ItemType Directory -Force | Out-Null }

# --- 1) Script da UI (executa no contexto de cada sessão de usuário)
$uiScript = @'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$AnswerFile = "C:\ProgramData\answer.txt"

# Form
$form              = New-Object System.Windows.Forms.Form
$form.StartPosition= 'CenterScreen'
$form.Text         = 'Ação requerida'
$form.Width        = 420
$form.Height       = 240
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox  = $false
$form.TopMost      = $true

# Label
$lbl               = New-Object System.Windows.Forms.Label
$lbl.Text          = "Escolha uma opção:"
$lbl.AutoSize      = $true
$lbl.Font          = New-Object System.Drawing.Font('Segoe UI', 12,[System.Drawing.FontStyle]::Bold)
$lbl.Location      = New-Object System.Drawing.Point(20,20)
$form.Controls.Add($lbl)

# Botões
$btnNow = New-Object System.Windows.Forms.Button
$btnNow.Text = 'Executar agora'
$btnNow.Width = 350
$btnNow.Height= 36
$btnNow.Location = New-Object System.Drawing.Point(30,70)

$btnD1  = New-Object System.Windows.Forms.Button
$btnD1.Text = 'Adiar 1 hora'
$btnD1.Width = 350
$btnD1.Height= 36
$btnD1.Location = New-Object System.Drawing.Point(30,115)

$btnD2  = New-Object System.Windows.Forms.Button
$btnD2.Text = 'Adiar 2 horas'
$btnD2.Width = 350
$btnD2.Height= 36
$btnD2.Location = New-Object System.Drawing.Point(30,160)

$form.Controls.AddRange(@($btnNow,$btnD1,$btnD2))

function Save-Answer($text){
  try {
    $line = $text
    [IO.File]::AppendAllText($AnswerFile, $line + [Environment]::NewLine, [Text.Encoding]::UTF8)
  } catch {}
}

$btnNow.Add_Click({ Save-Answer 'Executar agora'; $form.Close() })
$btnD1.Add_Click ({ Save-Answer 'Adiar 1 hora';   $form.Close() })
$btnD2.Add_Click ({ Save-Answer 'Adiar 2 horas';  $form.Close() })

[void]$form.ShowDialog()
'@
Set-Content -LiteralPath $UiScriptPath -Value $uiScript -Encoding UTF8 -Force

# --- 2) Helper que injeta o processo nas sessões ativas (requer SYSTEM)
$helperScript = @'
using namespace System
using namespace System.Runtime.InteropServices

Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
using System;
using System.Runtime.InteropServices;

public class NativeMethods {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct STARTUPINFO {
    public int cb;
    public string lpReserved;
    public string lpDesktop;
    public string lpTitle;
    public int dwX;
    public int dwY;
    public int dwXSize;
    public int dwYSize;
    public int dwXCountChars;
    public int dwYCountChars;
    public int dwFillAttribute;
    public int dwFlags;
    public short wShowWindow;
    public short cbReserved2;
    public IntPtr lpReserved2;
    public IntPtr hStdInput;
    public IntPtr hStdOutput;
    public IntPtr hStdError;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct PROCESS_INFORMATION {
    public IntPtr hProcess;
    public IntPtr hThread;
    public int dwProcessId;
    public int dwThreadId;
  }

  [DllImport("wtsapi32.dll", SetLastError=true)]
  public static extern bool WTSQueryUserToken(uint SessionId, out IntPtr phToken);

  [DllImport("advapi32.dll", SetLastError=true)]
  public static extern bool DuplicateTokenEx(
      IntPtr hExistingToken,
      uint dwDesiredAccess,
      IntPtr lpTokenAttributes,
      int ImpersonationLevel,
      int TokenType,
      out IntPtr phNewToken);

  [DllImport("userenv.dll", SetLastError=true)]
  public static extern bool CreateEnvironmentBlock(out IntPtr lpEnvironment, IntPtr hToken, bool bInherit);

  [DllImport("userenv.dll", SetLastError=true)]
  public static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);

  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CreateProcessAsUser(
      IntPtr hToken,
      string lpApplicationName,
      string lpCommandLine,
      IntPtr lpProcessAttributes,
      IntPtr lpThreadAttributes,
      bool bInheritHandles,
      uint dwCreationFlags,
      IntPtr lpEnvironment,
      string lpCurrentDirectory,
      ref STARTUPINFO lpStartupInfo,
      out PROCESS_INFORMATION lpProcessInformation);

  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr hObject);
}
"@

# Inicia um processo (cmdline) dentro da sessão do usuário
function Start-ProcessInSession {
  param(
    [uint32]$SessionId,
    [string]$CommandLine
  )

  $TOKEN_ASSIGN_PRIMARY = 0x0001
  $TOKEN_DUPLICATE      = 0x0002
  $TOKEN_QUERY          = 0x0008
  $TOKEN_ADJUST_DEFAULT = 0x0080
  $TOKEN_ADJUST_SESSION = 0x0100
  $MAXIMUM_ALLOWED      = 0x02000000
  $DesiredAccess = $TOKEN_ASSIGN_PRIMARY -bor $TOKEN_DUPLICATE -bor $TOKEN_QUERY -bor $TOKEN_ADJUST_DEFAULT -bor $TOKEN_ADJUST_SESSION -bor $MAXIMUM_ALLOWED

  $SECURITY_IMPERSONATION = 2
  $TOKEN_TYPE_PRIMARY     = 1
  $CREATE_UNICODE_ENVIRONMENT = 0x00000400
  $CREATE_NEW_CONSOLE          = 0x00000010

  $hUserToken = [IntPtr]::Zero
  if (-not ([Win32.NativeMethods]::WTSQueryUserToken($SessionId, [ref]$hUserToken))) {
    return $false
  }

  $hPrimary = [IntPtr]::Zero
  if (-not ([Win32.NativeMethods]::DuplicateTokenEx($hUserToken, $DesiredAccess, [IntPtr]::Zero, $SECURITY_IMPERSONATION, $TOKEN_TYPE_PRIMARY, [ref]$hPrimary))) {
    [Win32.NativeMethods]::CloseHandle($hUserToken) | Out-Null
    return $false
  }

  $envPtr = [IntPtr]::Zero
  [Win32.NativeMethods]::CreateEnvironmentBlock([ref]$envPtr, $hPrimary, $true) | Out-Null

  $si = New-Object Win32.NativeMethods+STARTUPINFO
  $si.cb = [Runtime.InteropServices.Marshal]::SizeOf([type]Win32.NativeMethods+STARTUPINFO)
  $si.lpDesktop = "winsta0\default"
  $pi = New-Object Win32.NativeMethods+PROCESS_INFORMATION

  $ok = [Win32.NativeMethods]::CreateProcessAsUser(
    $hPrimary,
    $null,
    $CommandLine,
    [IntPtr]::Zero,
    [IntPtr]::Zero,
    $false,
    ($CREATE_UNICODE_ENVIRONMENT -bor $CREATE_NEW_CONSOLE),
    $envPtr,
    "C:\Windows\System32",
    [ref]$si,
    [ref]$pi
  )

  if ($envPtr -ne [IntPtr]::Zero) { [Win32.NativeMethods]::DestroyEnvironmentBlock($envPtr) | Out-Null }
  if ($pi.hThread -ne [IntPtr]::Zero) { [Win32.NativeMethods]::CloseHandle($pi.hThread) | Out-Null }
  if ($pi.hProcess -ne [IntPtr]::Zero){ [Win32.NativeMethods]::CloseHandle($pi.hProcess) | Out-Null }
  if ($hPrimary -ne [IntPtr]::Zero)    { [Win32.NativeMethods]::CloseHandle($hPrimary) | Out-Null }
  if ($hUserToken -ne [IntPtr]::Zero)  { [Win32.NativeMethods]::CloseHandle($hUserToken) | Out-Null }

  return $ok
}

# Descobre sessões ativas via "quser" (funciona em PT/EN)
$activeSessionIds = @()
$quser = & quser 2>$null
if ($quser) {
  foreach($line in $quser) {
    # Ex.: "> user            rdp-tcp#1         2  Ativo   ... "  ou "... Active ..."
    if ($line -match '\s(\d+)\s+(Ativo|Active)\b') {
      $sid = [uint32]($Matches[1])
      if ($sid -gt 0) { $activeSessionIds += $sid }
    }
  }
}
$activeSessionIds = $activeSessionIds | Sort-Object -Unique
if (-not $activeSessionIds) { return }

$uiPath = "C:\ProgramData\ShowChoice-UI.ps1"
$cmd    = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$uiPath`""

foreach($sid in $activeSessionIds) {
  try { Start-ProcessInSession -SessionId $sid -CommandLine $cmd | Out-Null } catch {}
}
'@
Set-Content -LiteralPath $HelperPath -Value $helperScript -Encoding UTF8 -Force

# --- 3) Se já for SYSTEM, executa helper direto; senão cria/agora uma tarefa como SYSTEM
function Test-IsSystem {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return ($id.User.Value -eq 'S-1-5-18')
}

if (Test-IsSystem) {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HelperPath
} else {
  # Cria/roda tarefa como SYSTEM para executar o helper (que injeta o form nas sessões)
  $startTime = (Get-Date).AddMinutes(1).ToString('HH:mm')
  try { schtasks /Delete /TN $TaskName /F 1>$null 2>$null } catch {}
  schtasks /Create /TN $TaskName /SC ONCE /ST $startTime /RL HIGHEST /RU SYSTEM /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$HelperPath`"" | Out-Null
  schtasks /Run /TN $TaskName | Out-Null
  Start-Sleep -Seconds 3
  # (opcional) limpar tarefa após alguns minutos
  Start-Job -ScriptBlock { Start-Sleep 300; schtasks /Delete /TN 'GDL-ShowChoiceAllSessions-TEMP' /F 1>$null 2>$null } | Out-Null
}

Write-Host "Formulário enviado para as sessões ativas. As respostas serão salvas em $AnswerPath"
