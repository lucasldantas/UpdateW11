#requires -version 5.1
$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ====================== VARIÁVEIS EDITÁVEIS ======================
$AnswerFile         = 'C:\ProgramData\Answer.txt'

$Txt_WindowTitle    = 'Agendar Execução'
$Txt_HeaderTitle    = 'Atualização obrigatória'
$Txt_HeaderSubtitle = 'Você pode executar agora ou adiar por até 2 horas.'
$Txt_ActionLine1    = 'Realizar o update do Windows 10 para o Windows 11'
$Txt_ActionLine2    = 'Tempo Estimado: 20 a 30 minutos'

$Txt_BtnNow         = 'Executar agora'
$Txt_Btn1H          = 'Adiar 1 hora'
$Txt_Btn2H          = 'Adiar 2 horas'
# ================================================================

# --- Garante STA (necessário para UI estável) ---
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') { $psExe = "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe" }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $self = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$self`"") -WindowStyle Hidden | Out-Null
    return
}

# --- Dependências WinForms ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Prepara pasta do arquivo ---
try {
    $dir = Split-Path -LiteralPath $AnswerFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
} catch {}

# --- Função para gravar e fechar com segurança ---
$script:allowClose = $false
function Write-Answer([string]$text, [System.Windows.Forms.Form]$form) {
    try {
        [System.IO.File]::WriteAllText($AnswerFile, $text, [System.Text.Encoding]::UTF8)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Falha ao gravar $AnswerFile`n$($_.Exception.Message)", "Erro", 'OK', 'Error') | Out-Null
    }
    $script:allowClose = $true
    try { $form.Close() } catch {}
}

# --- Form principal (sem botão fechar) ---
$form                  = New-Object System.Windows.Forms.Form
$form.Text             = $Txt_WindowTitle
$form.StartPosition    = 'CenterScreen'
$form.FormBorderStyle  = 'FixedDialog'
$form.ControlBox       = $false          # remove fechar/min/max
$form.MinimizeBox      = $false
$form.MaximizeBox      = $false
$form.TopMost          = $true
$form.BackColor        = [System.Drawing.ColorTranslator]::FromHtml('#0f172a')
$form.ClientSize       = New-Object System.Drawing.Size(600,260)

# Impede Alt+F4 / fechar sem escolher
$form.Add_FormClosing({
    param($s,$e)
    if (-not $script:allowClose) { $e.Cancel = $true }
})

# Cabeçalho (retangular)
$header = New-Object System.Windows.Forms.Panel
$header.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#111827')
$header.Size      = New-Object System.Drawing.Size(568,60)
$header.Location  = New-Object System.Drawing.Point(16,16)
$form.Controls.Add($header)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = $Txt_HeaderTitle
$lblTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#e5e7eb')
$lblTitle.Font      = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$lblTitle.AutoSize  = $true
$lblTitle.Location  = New-Object System.Drawing.Point(12,10)
$header.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text      = $Txt_HeaderSubtitle
$lblSub.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#9ca3af')
$lblSub.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
$lblSub.AutoSize  = $true
$lblSub.Location  = New-Object System.Drawing.Point(12,33)
$header.Controls.Add($lblSub)

# Corpo
$body = New-Object System.Windows.Forms.Panel
$body.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0b1220')
$body.Size      = New-Object System.Drawing.Size(568,100)
$body.Location  = New-Object System.Drawing.Point(16,86)
$form.Controls.Add($body)

$lblL1 = New-Object System.Windows.Forms.Label
$lblL1.Text      = $Txt_ActionLine1
$lblL1.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#cbd5e1')
$lblL1.Font      = New-Object System.Drawing.Font('Segoe UI', 10)
$lblL1.AutoSize  = $true
$lblL1.Location  = New-Object System.Drawing.Point(12,14)
$body.Controls.Add($lblL1)

$lblL2 = New-Object System.Windows.Forms.Label
$lblL2.Text      = $Txt_ActionLine2
$lblL2.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#cbd5e1')
$lblL2.Font      = New-Object System.Drawing.Font('Segoe UI', 10)
$lblL2.AutoSize  = $true
$lblL2.Location  = New-Object System.Drawing.Point(12,40)
$body.Controls.Add($lblL2)

# Botões (retangulares, tamanhos fixos)
$btnNow             = New-Object System.Windows.Forms.Button
$btnNow.Text        = $Txt_BtnNow
$btnNow.Size        = New-Object System.Drawing.Size(180,40)
$btnNow.Location    = New-Object System.Drawing.Point(16+568- (180*3 + 8*2), 200)
$btnNow.BackColor   = [System.Drawing.ColorTranslator]::FromHtml('#0078d4')
$btnNow.ForeColor   = [System.Drawing.Color]::White
$btnNow.FlatStyle   = 'Standard'

$btn1h              = New-Object System.Windows.Forms.Button
$btn1h.Text         = $Txt_Btn1H
$btn1h.Size         = New-Object System.Drawing.Size(180,40)
$btn1h.Location     = New-Object System.Drawing.Point($btnNow.Location.X + 180 + 8, 200)
$btn1h.BackColor    = [System.Drawing.ColorTranslator]::FromHtml('#1f2937')
$btn1h.ForeColor    = [System.Drawing.ColorTranslator]::FromHtml('#e5e7eb')
$btn1h.FlatStyle    = 'Standard'

$btn2h              = New-Object System.Windows.Forms.Button
$btn2h.Text         = $Txt_Btn2H
$btn2h.Size         = New-Object System.Drawing.Size(180,40)
$btn2h.Location     = New-Object System.Drawing.Point($btn1h.Location.X + 180 + 8, 200)
$btn2h.BackColor    = [System.Drawing.ColorTranslator]::FromHtml('#1f2937')
$btn2h.ForeColor    = [System.Drawing.ColorTranslator]::FromHtml('#e5e7eb')
$btn2h.FlatStyle    = 'Standard'

$form.Controls.AddRange(@($btnNow,$btn1h,$btn2h))

# Eventos
$btnNow.Add_Click({ Write-Answer 'NOW' $form })
$btn1h.Add_Click({ Write-Answer '1H'  $form })
$btn2h.Add_Click({ Write-Answer '2H'  $form })

# Permite arrastar a janela clicando no cabeçalho
$header.Add_MouseDown({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $form.Capture = $false
        $msg = 0xA1; $wparam = 2; $lparam = 0
        [void][System.Windows.Forms.SendKeys]::Flush()
        [void][System.Windows.Forms.NativeWindow]::FromHandle($form.Handle)
        # Move via WinAPI simples:
        Add-Type -Name N -Namespace Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool ReleaseCapture(); [DllImport("user32.dll")] public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);' -UsingNamespace System.Runtime.InteropServices -ErrorAction SilentlyContinue | Out-Null
        [Win.N]::ReleaseCapture() | Out-Null
        [Win.N]::SendMessage($form.Handle, $msg, $wparam, $lparam) | Out-Null
    }
})

# Exibe
[void][System.Windows.Forms.Application]::Run($form)
