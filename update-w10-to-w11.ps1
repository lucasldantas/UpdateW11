#requires -version 5.1
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# 0) Verifica sessão interativa (explorer)
$explorer = Get-Process explorer -IncludeUserName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $explorer) { Write-Host "Nenhuma sessão interativa encontrada."; exit 1 }

# 1) Deixa PSGallery confiável e NuGet instalado (silencioso)
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) { Register-PSRepository -Default }
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# 2) Garante BurntToast disponível para TODOS os usuários
if (-not (Get-Module -ListAvailable -Name BurntToast)) {
  Install-Module -Name BurntToast -Force -Scope AllUsers -AllowClobber
}

# 3) C# helper para CreateProcessAsUser
$src = @"
using System;
using System.Runtime.InteropServices;

public class UA {
  [StructLayout(LayoutKind.Sequential)]
  public struct STARTUPINFO {
    public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
    public uint dwX,dwY,dwXSize,dwYSize,dwXCountChars,dwYCountChars,dwFillAttribute,dwFlags;
    public ushort wShowWindow,cbReserved2; public IntPtr lpReserved2,hStdInput,hStdOutput,hStdError;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct PROCESS_INFORMATION { public IntPtr hProcess,hThread; public uint dwProcessId,dwThreadId; }

  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint da,bool ih,int pid);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr ph, uint da, out IntPtr th);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool DuplicateTokenEx(IntPtr et, uint da, IntPtr ta, int il, int tt, out IntPtr nt);
  [DllImport("userenv.dll", SetLastError=true)] static extern bool CreateEnvironmentBlock(out IntPtr env, IntPtr token, bool inherit);
  [DllImport("userenv.dll", SetLastError=true)] static extern bool DestroyEnvironmentBlock(IntPtr env);
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern bool CreateProcessAsUser(IntPtr token,string app,string cmd, IntPtr pa,IntPtr ta,bool ih,uint flags,IntPtr env,string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr h);

  const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
  const uint TOKEN_ASSIGN_PRIMARY=0x0001, TOKEN_DUPLICATE=0x0002, TOKEN_QUERY=0x0008, TOKEN_ADJUST_DEFAULT=0x0080, TOKEN_ADJUST_SESSIONID=0x0100;
  const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;

  public static bool RunInUser(int pid, string cmd) {
    IntPtr p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,false,pid); if(p==IntPtr.Zero) return false;
    IntPtr t; if(!OpenProcessToken(p, TOKEN_QUERY|TOKEN_DUPLICATE|TOKEN_ASSIGN_PRIMARY|TOKEN_ADJUST_DEFAULT|TOKEN_ADJUST_SESSIONID, out t)) { CloseHandle(p); return false; }
    IntPtr pt; if(!DuplicateTokenEx(t, 0xF01FF, IntPtr.Zero, 2, 1, out pt)) { CloseHandle(t); CloseHandle(p); return false; }
    IntPtr env; if(!CreateEnvironmentBlock(out env, pt, false)) { CloseHandle(pt); CloseHandle(t); CloseHandle(p); return false; }

    STARTUPINFO si = new STARTUPINFO(); si.cb = Marshal.SizeOf(typeof(STARTUPINFO)); si.lpDesktop = "winsta0\\default";
    PROCESS_INFORMATION pi;
    bool ok = CreateProcessAsUser(pt, null, cmd, IntPtr.Zero, IntPtr.Zero, false, CREATE_UNICODE_ENVIRONMENT, env, null, ref si, out pi);

    DestroyEnvironmentBlock(env);
    if(pi.hThread!=IntPtr.Zero) CloseHandle(pi.hThread);
    if(pi.hProcess!=IntPtr.Zero) CloseHandle(pi.hProcess);
    CloseHandle(pt); CloseHandle(t); CloseHandle(p);
    return ok;
  }
}
"@
Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop

# 4) Comando a executar NA sessão do usuário (mostra o toast)
$cmd = @'
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
 "try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{}; ^
  Import-Module BurntToast -Force; ^
  reg add HKCU\Software\Microsoft\Windows\CurrentVersion\PushNotifications /v ToastEnabled /t REG_DWORD /d 1 /f | Out-Null; ^
  reg add HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings /v NOC_GLOBAL_SETTING_TOASTS_ENABLED /t REG_DWORD /d 1 /f | Out-Null; ^
  New-BurntToastNotification -Text 'BEMVINDO','Seja bem-vindo ao sistema!'; "
'@

if ([UA]::RunInUser($explorer.Id, $cmd)) {
  Write-Host "✅ Toast disparado na sessão do usuário (PID explorer: $($explorer.Id), Sessão: $($explorer.SessionId))."
} else {
  Write-Host "❌ Falha ao criar processo na sessão do usuário."
  exit 2
}
