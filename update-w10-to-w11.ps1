# Requisitos: executar como Admin/SYSTEM
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# 1) Provider NuGet + PSGallery confiável (silencioso)
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
    Register-PSRepository -Default
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# 2) Instala módulos necessários para TODOS os usuários
$mods = 'BurntToast','RunAsUser'
foreach ($m in $mods) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Install-Module -Name $m -Force -Scope AllUsers -AllowClobber
    }
}

# 3) Registrar o protocolo ToastReboot: (HKCR = Classes, requer admin)
New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -ErrorAction SilentlyContinue | Out-Null
if (-not (Get-Item 'HKCR:\ToastReboot' -ErrorAction SilentlyContinue)) {
    New-Item 'HKCR:\ToastReboot' -Force | Out-Null
    Set-ItemProperty 'HKCR:\ToastReboot' -Name '(default)' -Value 'url:ToastReboot' -Force
    Set-ItemProperty 'HKCR:\ToastReboot' -Name 'URL Protocol' -Value '' -Force
    New-ItemProperty -Path 'HKCR:\ToastReboot' -PropertyType DWord -Name 'EditFlags' -Value 2162688 -Force | Out-Null
    New-Item 'HKCR:\ToastReboot\Shell\Open\command' -Force | Out-Null
    # Use aspas no caminho:
    Set-ItemProperty 'HKCR:\ToastReboot\Shell\Open\command' -Name '(default)' -Value '"C:\Windows\System32\shutdown.exe" -r -t 00' -Force
}

# 4) Executar NA sessão do usuário logado (RunAsUser)
Import-Module RunAsUser -Force

Invoke-AsCurrentUser -ScriptBlock {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    # Garantir BurntToast para o usuário atual
    if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
            Register-PSRepository -Default
        }
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Install-Module -Name BurntToast -Force -Scope CurrentUser -AllowClobber
    }

    Import-Module BurntToast -Force

    # (Opcional) Habilitar toasts no perfil do usuário, caso políticas tenham desativado
    reg add HKCU\Software\Microsoft\Windows\CurrentVersion\PushNotifications /v ToastEnabled /t REG_DWORD /d 1 /f | Out-Null
    reg add HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings /v NOC_GLOBAL_SETTING_TOASTS_ENABLED /t REG_DWORD /d 1 /f | Out-Null

    # Conteúdo do toast
    $Hero = New-BTImage -Source 'https://media.giphy.com/media/eiwIMNkeJ2cu5MI2XC/giphy.gif' -HeroImage
    $T1   = New-BTText -Content "Message from IT"
    $T2   = New-BTText -Content "Updates foram instaladas em $(Get-Date). Reboot agora ou adie este lembrete."

    # Seleções (renomeadas para nomes válidos)
    $Min5  = New-BTSelectionBoxItem -Id 5    -Content '5 minutes'
    $Min10 = New-BTSelectionBoxItem -Id 10   -Content '10 minutes'
    $Hr1   = New-BTSelectionBoxItem -Id 60   -Content '1 hour'
    $Hr4   = New-BTSelectionBoxItem -Id 240  -Content '4 hours'
    $Day1  = New-BTSelectionBoxItem -Id 1440 -Content '1 day'
    $Items = $Min5, $Min10, $Hr1, $Hr4, $Day1

    $Input = New-BTInput -Id 'SnoozeTime' -DefaultSelectionBoxItemId 10 -Items $Items

    # Botões (observe o -ActivationType e o -Snooze)
    $BtnSnooze = New-BTButton -Content "Snooze" -Snooze -Id 'SnoozeTime'
    $BtnReboot = New-BTButton -Content "Reboot now" -Arguments "ToastReboot:" -ActivationType Protocol

    $Actions = New-BTAction -Buttons $BtnSnooze, $BtnReboot -Inputs $Input

    $Binding = New-BTBinding -Children $T1, $T2 -HeroImage $Hero
    $Visual  = New-BTVisual -BindingGeneric $Binding

    $Content = New-BTContent -Visual $Visual -Actions $Actions
    Submit-BTNotification -Content $Content
}
