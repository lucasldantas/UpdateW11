# ===================== LAUNCHER ROBUSTO (mostra UI na sessão ativa) =====================
$src = @"
using System;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;

public static class UserSessionLauncher {
  // ----- WTS / SYSTEM path -----
  [DllImport("kernel32.dll")] static extern uint WTSGetActiveConsoleSessionId();
  [DllImport("wtsapi32.dll", SetLastError=true)] static extern bool WTSQueryUserToken(uint SessionId, out IntPtr Token);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool DuplicateTokenEx(IntPtr hExistingToken, UInt32 dwDesiredAccess, IntPtr lpTokenAttributes, Int32 ImpersonationLevel, Int32 TokenType, out IntPtr phNewToken);
  [DllImport("userenv.dll", SetLastError=true)] static extern bool CreateEnvironmentBlock(out IntPtr lpEnvironment, IntPtr hToken, bool bInherit);
  [DllImport("userenv.dll", SetLastError=true)] static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern bool CreateProcessAsUser(IntPtr hToken, string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

  // ----- Non-SYSTEM fallback: explorer.exe token + CreateProcessWithTokenW -----
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr ProcessHandle, UInt32 DesiredAccess, out IntPtr TokenHandle);
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern bool CreateProcessWithTokenW(IntPtr hToken, UInt32 dwLogonFlags, string lpApplicationName, string lpCommandLine, UInt32 dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);

  [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr hObject);

  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  struct STARTUPINFO {
    public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
    public int dwX; public int dwY; public int dwXSize; public int dwYSize;
    public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute;
    public int dwFlags; public short wShowWindow; public short cbReserved2;
    public IntPtr lpReserved2; public IntPtr hStdInput; public IntPtr hStdOutput; public IntPtr hStdError;
  }
  [StructLayout(LayoutKind.Sequential)]
  struct PROCESS_INFORMATION { public IntPtr hProcess; public IntPtr hThread; public int dwProcessId; public int dwThreadId; }

  const UInt32 GENERIC_ALL = 0x10000000;
  const int SecurityImpersonation = 2;
  const int TokenPrimary = 1;
  const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
  const UInt32 LOGON_WITH_PROFILE = 0x00000001;
  const UInt32 CREATE_NEW_CONSOLE = 0x00000010;

  const UInt32 PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
  const UInt32 PROCESS_QUERY_INFORMATION = 0x0400;

  const UInt32 TOKEN_QUERY = 0x0008;
  const UInt32 TOKEN_DUPLICATE = 0x0002;
  const UInt32 TOKEN_ASSIGN_PRIMARY = 0x0001;
  const UInt32 TOKEN_ALL_ACCESS = 0xF01FF;

  static bool LaunchViaWTS(string cmdLine) {
    try {
      uint sessionId = WTSGetActiveConsoleSessionId();
      if (sessionId == 0xFFFFFFFF) return false;

      IntPtr userToken;
      if (!WTSQueryUserToken(sessionId, out userToken)) return false;

      IntPtr primaryToken;
      if (!DuplicateTokenEx(userToken, GENERIC_ALL, IntPtr.Zero, SecurityImpersonation, TokenPrimary, out primaryToken)) {
        CloseHandle(userToken);
        return false;
      }

      IntPtr env;
      CreateEnvironmentBlock(out env, primaryToken, false);

      STARTUPINFO si = new STARTUPINFO();
      si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
      si.lpDesktop = @"winsta0\default";

      PROCESS_INFORMATION pi;
      bool ok = CreateProcessAsUser(primaryToken, null, cmdLine, IntPtr.Zero, IntPtr.Zero, false, CREATE_UNICODE_ENVIRONMENT, env, null, ref si, out pi);

      if (ok) { CloseHandle(pi.hThread); CloseHandle(pi.hProcess); }

      if (env != IntPtr.Zero) DestroyEnvironmentBlock(env);
      CloseHandle(primaryToken);
      CloseHandle(userToken);
      return ok;
    } catch { return false; }
  }

  static bool LaunchViaExplorerToken(string cmdLine) {
    try {
      // pega a sessão da console
      uint active = WTSGetActiveConsoleSessionId();
      if (active == 0xFFFFFFFF) return false;

      // encontra explorer.exe nessa sessão
      var candidate = Process.GetProcessesByName("explorer")
                        .FirstOrDefault(p => { try { return (uint)p.SessionId == active; } catch { return false; } });
      if (candidate == null) return false;

      IntPtr hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_QUERY_INFORMATION, false, candidate.Id);
      if (hProc == IntPtr.Zero) return false;

      IntPtr hTok;
      bool gotTok = OpenProcessToken(hProc, TOKEN_DUPLICATE | TOKEN_ASSIGN_PRIMARY | TOKEN_QUERY, out hTok);
      CloseHandle(hProc);
      if (!gotTok) return false;

      // Usa CreateProcessWithTokenW (requer SeImpersonatePrivilege — admins elev. têm)
      STARTUPINFO si = new STARTUPINFO();
      si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
      si.lpDesktop = @"winsta0\default";
      PROCESS_INFORMATION pi;
      bool ok = CreateProcessWithTokenW(hTok, LOGON_WITH_PROFILE, null, cmdLine, CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_CONSOLE, IntPtr.Zero, null, ref si, out pi);

      if (ok) { CloseHandle(pi.hThread); CloseHandle(pi.hProcess); }
      CloseHandle(hTok);
      return ok;
    } catch { return false; }
  }

  public static bool LaunchInActiveSession(string cmdLine) {
    // 1) tenta via WTS (SYSTEM)
    if (LaunchViaWTS(cmdLine)) return true;
    // 2) fallback via token do explorer (admin elevado)
    if (LaunchViaExplorerToken(cmdLine)) return true;
    return false;
  }
}
"@
Add-Type -TypeDefinition $src -Language CSharp

# Garante que vamos chamar o PowerShell 64-bit mesmo se este script rodar em host 32-bit
$PS64 = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') { $PS64 = "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" }

$psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$UiScript`""
$cmd    = "`"$PS64`" $psArgs"

$ok = [UserSessionLauncher]::LaunchInActiveSession($cmd)
if (-not $ok) {
  Write-Warning "Ainda não consegui abrir o formulário na sessão do usuário (verifique: executar elevado, TermService ativo, há 'explorer.exe' na sessão ativa)."
  if (-not (Test-Path 'C:\ProgramData\Answer.txt')) { Set-Content -Path 'C:\ProgramData\Answer.txt' -Value 'NOUSER' -Encoding UTF8 }
} else {
  Write-Host "Form exibido para o usuário logado. Resposta irá para C:\ProgramData\Answer.txt"
}
