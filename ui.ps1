#requires -version 5.1
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ===================== CONFIG =====================
$AnswerFile = 'C:\ProgramData\Answer.txt'
$UiScript   = 'C:\ProgramData\ShowChoice.ps1'

# ===================== UI (Win11-like) =====================
$ui = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function New-RoundRegion([System.Drawing.Rectangle]`$rect, [int]`$radius){
  `$gp = New-Object System.Drawing.Drawing2D.GraphicsPath
  `$d = `$radius * 2
  `$gp.AddArc(`$rect.X, `$rect.Y, `$d, `$d, 180, 90)
  `$gp.AddArc(`$rect.Right-`$d, `$rect.Y, `$d, `$d, 270, 90)
  `$gp.AddArc(`$rect.Right-`$d, `$rect.Bottom-`$d, `$d, `$d, 0, 90)
  `$gp.AddArc(`$rect.X, `$rect.Bottom-`$d, `$d, `$d, 90, 90)
  `$gp.CloseFigure()
  return `$gp
}

# P/Invoke para dark mode
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class DwmUtil {
  [DllImport("dwmapi.dll", PreserveSig=true)]
  public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
  public const int DWMWA_USE_IMMERSIVE_DARK_MODE_OLD = 19;
  public const int DWMWA_USE_IMMERSIVE_DARK_MODE_NEW = 20;
}
"@

# Paleta
`$bg      = [System.Drawing.Color]::FromArgb(32,32,36)
`$panelBg = [System.Drawing.Color]::FromArgb(40,40,46)
`$accent  = [System.Drawing.Color]::FromArgb(0,120,212)
`$text    = [System.Drawing.Color]::FromArgb(230,230,235)
`$subtext = [System.Drawing.Color]::FromArgb(180,180,190)
`$border  = [System.Drawing.Color]::FromArgb(60,60,70)

# Form
`$form = New-Object System.Windows.Forms.Form
`$form.Text = 'Agendamento'
`$form.FormBorderStyle = 'None'
`$form.StartPosition = 'CenterScreen'
`$form.Size = New-Object System.Drawing.Size(520,280)
`$form.TopMost = `$true
`$form.BackColor = `$bg
`$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

# Ativar dark
try {
  `$dark = 1
  [void][DwmUtil]::DwmSetWindowAttribute(`$form.Handle, [DwmUtil]::DWMWA_USE_IMMERSIVE_DARK_MODE_NEW, [ref]`$dark, 4)
  [void][DwmUtil]::DwmSetWindowAttribute(`$form.Handle, [DwmUtil]::DWMWA_USE_IMMERSIVE_DARK_MODE_OLD, [ref]`$dark, 4)
} catch {}

# Bordas arredondadas
`$form.add_Shown({
  `$r = New-Object System.Drawing.Rectangle(0,0,`$form.Width,`$form.Height)
  `$form.Region = New-Object System.Drawing.Region( (New-RoundRegion `$r 18) )
})
`$form.add_Resize({
  `$r = New-Object System.Drawing.Rectangle(0,0,`$form.Width,`$form.Height)
  `$form.Region = New-Object System.Drawing.Region( (New-RoundRegion `$r 18) )
})

# Titlebar
`$titleBar = New-Object System.Windows.Forms.Panel
`$titleBar.Height = 42; `$titleBar.Dock = 'Top'; `$titleBar.BackColor = `$panelBg
`$form.Controls.Add(`$titleBar)
`$titleBar.Paint += {
  param(`$s,`$e)
  `$e.Graphics.SmoothingMode = 'AntiAlias'
  `$pen = New-Object System.Drawing.Pen(`$border)
  `$e.Graphics.DrawLine(`$pen, 0, `$titleBar.Height-1, `$titleBar.Width, `$titleBar.Height-1)
  `$pen.Dispose()
}
`$lblTitle = New-Object System.Windows.Forms.Label
`$lblTitle.Text = 'Atualização obrigatória'
`$lblTitle.ForeColor = `$text
`$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
`$lblTitle.AutoSize = `$true
`$lblTitle.Location = New-Object System.Drawing.Point(18, 11)
`$titleBar.Controls.Add(`$lblTitle)
`$btnClose = New-Object System.Windows.Forms.Button
`$btnClose.Text = '✕'
`$btnClose.FlatStyle = 'Flat'
`$btnClose.FlatAppearance.BorderSize = 0
`$btnClose.ForeColor = `$subtext
`$btnClose.BackColor = `$panelBg
`$btnClose.Width = 40; `$btnClose.Height = 32
`$btnClose.Location = New-Object System.Drawing.Point(`$form.Width-50,5)
`$btnClose.Anchor = 'Top,Right'
`$btnClose.Add_MouseEnter({ `$btnClose.ForeColor = [System.Drawing.Color]::White })
`$btnClose.Add_MouseLeave({ `$btnClose.ForeColor = `$subtext })
`$btnClose.Add_Click({ `$form.Close() })
`$titleBar.Controls.Add(`$btnClose)
# Drag da janela
`$mouseDown = `$false; `$pt = New-Object System.Drawing.Point
`$titleBar.Add_MouseDown({ param(`$s,`$e) if(`$e.Button -eq 'Left'){ `$mouseDown=`$true; `$pt=`$e.Location } })
`$titleBar.Add_MouseMove({ param(`$s,`$e) if(`$mouseDown){ `$form.Left += (`$e.X - `$pt.X); `$form.Top += (`$e.Y - `$pt.Y) } })
`$titleBar.Add_MouseUp({ `$mouseDown=`$false })

# Conteúdo
`$content = New-Object System.Windows.Forms.Panel
`$content.Dock = 'Fill'; `$content.Padding = '22,18,22,22'; `$content.BackColor = `$bg
`$form.Controls.Add(`$content)
`$card = New-Object System.Windows.Forms.Panel
`$card.BackColor = `$panelBg; `$card.Dock = 'Fill'; `$card.Padding = '22,18,22,22'
`$card.add_Paint({
  param(`$s,`$e)
  `$rect = New-Object System.Drawing.Rectangle(0,0,`$card.Width-1,`$card.Height-1)
  `$gp = New-RoundRegion `$rect 16
  `$e.Graphics.SmoothingMode = 'AntiAlias'
  `$e.Graphics.FillPath( (New-Object System.Drawing.SolidBrush `$panelBg), `$gp)
  `$e.Graphics.DrawPath( (New-Object System.Drawing.Pen `$border), `$gp)
  `$gp.Dispose()
})
`$content.Controls.Add(`$card)
`$lblMain = New-Object System.Windows.Forms.Label
`$lblMain.Text = 'Você pode executar agora ou adiar.'
`$lblMain.ForeColor = `$text
`$lblMain.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 12)
`$lblMain.AutoSize = `$true
`$lblMain.Location = New-Object System.Drawing.Point(12,10)
`$card.Controls.Add(`$lblMain)
`$lblSub = New-Object System.Windows.Forms.Label
`$lblSub.Text = 'Escolha uma opção abaixo. A operação é segura e rápida.'
`$lblSub.ForeColor = `$subtext
`$lblSub.Font = New-Object System.Drawing.Font('Segoe UI', 9)
`$lblSub.AutoSize = `$true
`$lblSub.Location = New-Object System.Drawing.Point(12,38)
`$card.Controls.Add(`$lblSub)

# Botões
`$btnPanel = New-Object System.Windows.Forms.FlowLayoutPanel
`$btnPanel.FlowDirection = 'LeftToRight'; `$btnPanel.WrapContents = `$false
`$btnPanel.Dock = 'Bottom'; `$btnPanel.Height = 80; `$btnPanel.Padding = '8,8,8,8'
`$card.Controls.Add(`$btnPanel)

function New-PillButton([string]`$text,[System.Drawing.Color]`$bg,[System.Drawing.Color]`$fg,[System.Drawing.Color]`$hoverBg){
  `$b = New-Object System.Windows.Forms.Button
  `$b.Text = `$text
  `$b.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
  `$b.FlatStyle = 'Flat'
  `$b.FlatAppearance.BorderSize = 0
  `$b.BackColor = `$bg
  `$b.ForeColor = `$fg
  `$b.Width = 150; `$b.Height = 40; `$b.Margin = '8,8,8,8'
  `$b.add_Paint({
    param(`$s,`$e)
    `$btn = `$s -as [System.Windows.Forms.Button]
    `$e.Graphics.SmoothingMode = 'AntiAlias'
    `$rect = New-Object System.Drawing.Rectangle(0,0,`$btn.Width-1,`$btn.Height-1)
    `$gp = New-RoundRegion `$rect 20
    `$e.Graphics.FillPath( (New-Object System.Drawing.SolidBrush `$btn.BackColor), `$gp )
    `$outline = [System.Drawing.Color]::FromArgb(80, `$border.R, `$border.G, `$border.B)
    `$e.Graphics.DrawPath( (New-Object System.Drawing.Pen `$outline), `$gp )
    `$gp.Dispose()
    `$fmt = New-Object System.Drawing.StringFormat
    `$fmt.Alignment = 'Center'; `$fmt.LineAlignment = 'Center'
    `$e.Graphics.DrawString(`$btn.Text, `$btn.Font, (New-Object System.Drawing.SolidBrush `$btn.ForeColor), `$rect, `$fmt)
    `$fmt.Dispose()
  })
  `$b.Add_MouseEnter({ param(`$s,`$e) `$s.BackColor = `$hoverBg })
  `$b.Add_MouseLeave({ param(`$s,`$e) `$s.BackColor = `$bg })
  return `$b
}

function Write-Answer([string]`$val){
  try { [System.IO.File]::WriteAllText('@@ANSWERFILE@@', `$val, [Text.Encoding]::UTF8) } catch {}
  `$form.Close()
}

`$btnNow = New-PillButton 'Executar agora' `$accent [System.Drawing.Color]::White ([System.Drawing.Color]::FromArgb(0,99,175))
`$btn1H  = New-PillButton 'Adiar 1 hora' ([System.Drawing.Color]::FromArgb(58,58,66)) `$text ([System.Drawing.Color]::FromArgb(75,75,86))
`$btn2H  = New-PillButton 'Adiar 2 horas' ([System.Drawing.Color]::FromArgb(58,58,66)) `$text ([System.Drawing.Color]::FromArgb(75,75,86))

`$btnNow.Add_Click({ Write-Answer 'NOW' })
`$btn1H.Add_Click({ Write-Answer '1H' })
`$btn2H.Add_Click({ Write-Answer '2H' })

`$btnPanel.Controls.Add(`$btnNow)
`$btnPanel.Controls.Add(`$btn1H)
`$btnPanel.Controls.Add(`$btn2H)

`$form.KeyPreview = `$true
`$form.Add_KeyDown({ param(`$s,`$e) if(`$e.KeyCode -eq 'Escape'){ `$form.Close() } })

[void]`$form.ShowDialog()
"@

# Inserir caminho do arquivo no here-string da UI
$ui = $ui -replace '@@ANSWERFILE@@', ($AnswerFile -replace '\\','\\')

# Gravar UI
Set-Content -Path $UiScript -Value $ui -Encoding UTF8 -Force

# ===================== LAUNCHER (sessão do usuário) =====================
$src = @"
using System;
using System.Runtime.InteropServices;

public static class UserSessionLauncher {
  [DllImport("kernel32.dll")] static extern uint WTSGetActiveConsoleSessionId();
  [DllImport("wtsapi32.dll", SetLastError=true)] static extern bool WTSQueryUserToken(uint SessionId, out IntPtr Token);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool DuplicateTokenEx(IntPtr hExistingToken, UInt32 dwDesiredAccess, IntPtr lpTokenAttributes, Int32 ImpersonationLevel, Int32 TokenType, out IntPtr phNewToken);
  [DllImport("userenv.dll", SetLastError=true)] static extern bool CreateEnvironmentBlock(out IntPtr lpEnvironment, IntPtr hToken, bool bInherit);
  [DllImport("userenv.dll", SetLastError=true)] static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);
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
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern bool CreateProcessAsUser(IntPtr hToken, string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes, bool bInheritHandles, uint dwCreationFlags, IntPtr lpEnvironment, string lpCurrentDirectory, ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr hObject);

  const UInt32 GENERIC_ALL = 0x10000000;
  const int SecurityImpersonation = 2;
  const int TokenPrimary = 1;
  const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;

  public static bool LaunchInActiveSession(string cmdLine) {
    uint sessionId = WTSGetActiveConsoleSessionId();
    if (sessionId == 0xFFFFFFFF) return false;

    IntPtr userToken;
    if (!WTSQueryUserToken(sessionId, out userToken)) return false;

    IntPtr primaryToken;
    if (!DuplicateTokenEx(userToken, GENERIC_ALL, IntPtr.Zero, SecurityImpersonation, TokenPrimary, out primaryToken)) { CloseHandle(userToken); return false; }

    IntPtr env; CreateEnvironmentBlock(out env, primaryToken, false);

    STARTUPINFO si = new STARTUPINFO(); si.cb = Marshal.SizeOf(typeof(STARTUPINFO)); si.lpDesktop = @"winsta0\default";
    PROCESS_INFORMATION pi;
    bool ok = CreateProcessAsUser(primaryToken, null, cmdLine, IntPtr.Zero, IntPtr.Zero, false, CREATE_UNICODE_ENVIRONMENT, env, null, ref si, out pi);
    if (ok) { CloseHandle(pi.hThread); CloseHandle(pi.hProcess); }

    if (env != IntPtr.Zero) DestroyEnvironmentBlock(env);
    CloseHandle(primaryToken); CloseHandle(userToken);
    return ok;
  }
}
"@
Add-Type -TypeDefinition $src -Language CSharp

# Monta e lança o PowerShell na sessão do usuário
$psExe  = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$UiScript`""
$cmd    = "`"$psExe`" $psArgs"

$ok = [UserSessionLauncher]::LaunchInActiveSession($cmd)
if (-not $ok) {
  Write-Warning "Nenhum usuário logado ou falha ao abrir o formulário."
  if (-not (Test-Path $AnswerFile)) { Set-Content -Path $AnswerFile -Value 'NOUSER' -Encoding UTF8 }
} else {
  Write-Host "Form Win11 exibido. A resposta irá para $AnswerFile"
}
