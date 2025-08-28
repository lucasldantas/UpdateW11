#requires -version 5.1
<#
Uso:
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\BroadcastPrompt.ps1

Comportamento:
  - Mostra uma mensagem com botões Sim/Não/Cancelar em TODAS as sessões ativas/conectadas:
      Sim      = Executar agora   (grava NOW)
      Não      = Adiar 1 hora     (grava 1H)
      Cancelar = Adiar 2 horas    (grava 2H)
  - Grava apenas uma vez em C:\ProgramData\Answer.txt (primeiro que responder vence).
#>

param(
  [switch]$ForSession,         # interno
  [int]$SessionId,             # interno
  [string]$AnswerFile = 'C:\ProgramData\Answer.txt'
)

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ---------- Textos editáveis ----------
$title   = 'Agendar Execução'
$body    = @"
Atualização obrigatória

Você pode executar agora ou adiar por até 2 horas.

Escolha uma opção:
  - SIM      = Executar agora
  - NÃO      = Adiar 1 hora
  - CANCELAR = Adiar 2 horas
"@.Trim()
# --------------------------------------

# --- Interop mínimo com WTS (Win32) ---
# (precisa desses imports para enviar a msgbox para outras sessões)
$wtsSrc = @"
using System;
using System.Runtime.InteropServices;

public static class WTS {
  public const int WTS_CURRENT_SERVER_HANDLE = 0;
  public enum WTS_CONNECTSTATE_CLASS { Active=0, Connected=1, ConnectQuery=2, Shadow=3, Disconnected=4, Idle=5, Listen=6, Reset=7, Down=8, Init=9 }

  [StructLayout(LayoutKind.Sequential)]
  public struct WTS_SESSION_INFO {
    public int SessionId;
    [MarshalAs(UnmanagedType.LPTStr)] public string pWinStationName;
    public WTS_CONNECTSTATE_CLASS State;
  }

  [DllImport("wtsapi32.dll", SetLastError=true)]
  public static extern bool WTSEnumerateSessions(
    IntPtr hServer, int Reserved, int Version,
    out IntPtr ppSessionInfo, out int pCount
  );

  [DllImport("wtsapi32.dll")] public static extern void WTSFreeMemory(IntPtr pMemory);

  [DllImport("wtsapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool WTSSendMessage(
    IntPtr hServer,
    int SessionId,
    string pTitle, int TitleLength,
    string pMessage, int MessageLength,
    int Style, int Timeout,
    out int pResponse, bool bWait
  );
}
"@

Add-Type -TypeDefinition $wtsSrc -ErrorAction Stop | Out-Null

function Get-WTSSessions {
  $pp = [IntPtr]::Zero
  $count = 0
  $ok = [WTS]::WTSEnumerateSessions([IntPtr]::Zero, 0, 1, [ref]$pp, [ref]$count)
  if (-not $ok -or $pp -eq [IntPtr]::Zero -or $count -le 0) { return @() }
  try {
    $size = [Runtime.InteropServices.Marshal]::SizeOf([type][WTS+WTS_SESSION_INFO])
    $list = New-Object System.Collections.Generic.List[Object]
    for ($i=0; $i -lt $count; $i++) {
      $itemPtr = [IntPtr]::Add($pp, $i * $size)
      $info = [Runtime.InteropServices.Marshal]::PtrToStructure($itemPtr, [type][WTS+WTS_SESSION_INFO])
      $list.Add($info)
    }
    return $list
  } finally {
    [WTS]::WTSFreeMemory($pp)
  }
}

function Send-Prompt-ToSession {
  param([int]$Sid)

  # Botões: MB_YESNOCANCEL (0x00000003). Ícone pergunta (0x00000020). Topmost (0x00040000).
  $MB_YESNOCANCEL = 0x00000003
  $MB_ICONQUESTION = 0x00000020
  $MB_TOPMOST = 0x00040000
  $style = $MB_YESNOCANCEL -bor $MB_ICONQUESTION -bor $MB_TOPMOST

  # Timeout em segundos (opcional). 0 = infinito.
  $timeoutSec = 0

  $resp = 0
  $ok = [WTS]::WTSSendMessage([IntPtr]::Zero, $Sid, $title, $title.Length, $body, $body.Length, $style, $timeoutSec, [ref]$resp, $true)
  if (-not $ok) { return $null }

  # Mapear resposta para NOW/1H/2H
  switch ($resp) {
    6 { return 'NOW' }   # IDYES
    7 { return '1H' }    # IDNO
    2 { return '2H' }    # IDCANCEL
    default { return $null }
  }
}

function Try-Write-AnswerOnce {
  param([string]$Value, [string]$Path)

  try {
    # CreateNew -> falha se já existir (primeiro a escrever vence)
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
      $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
      $fs.Write($bytes, 0, $bytes.Length)
      $fs.Flush()
      return $true
    } finally { $fs.Dispose() }
  } catch {
    return $false
  }
}

# ============== Modo por sessão (interno) ==============
if ($ForSession) {
  # Garante pasta do arquivo
  try {
    $dir = Split-Path -LiteralPath $AnswerFile -ErrorAction SilentlyContinue
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  } catch {}

  $ans = Send-Prompt-ToSession -Sid $SessionId
  if ($ans) { [void](Try-Write-AnswerOnce -Value $ans -Path $AnswerFile) }
  exit 0
}

# ============== Modo Broadcast (padrão) ==============
# 1) Descobre sessões de usuário (ativas ou conectadas), exceto 0
$sessions = Get-WTSSessions | Where-Object { $_.SessionId -ne 0 -and ( $_.State -eq [WTS+WTS_CONNECTSTATE_CLASS]::Active -or $_.State -eq [WTS+WTS_CONNECTSTATE_CLASS]::Connected ) }

if (-not $sessions -or $sessions.Count -eq 0) {
  Write-Host "Nenhuma sessão de usuário ativa/conectada encontrada."
  exit 1
}

# 2) Lança um powershell destacado por sessão (não bloqueia a console atual)
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') { $psExe = "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" }
$self  = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }

foreach ($s in $sessions) {
  Start-Process -FilePath $psExe -ArgumentList @(
    '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
    '-File',"`"$self`"",
    '-ForSession',
    '-SessionId',"$($s.SessionId)",
    '-AnswerFile',"`"$AnswerFile`""
  ) -WindowStyle Hidden | Out-Null
}

Write-Host ("Disparado para {0} sessão(ões): {1}" -f $sessions.Count, ($sessions.SessionId -join ', '))
exit 0
