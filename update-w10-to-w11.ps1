#requires -version 5.1
<#
  Envia Toast para usuários conectados a partir da Sessão 0 (SYSTEM).

  Estrategia:
   - Cria script auxiliar em C:\ProgramData\Toast\Show-Toast.ps1 que:
       * Ajusta registro HKCU p/ AppID (Action Center)
       * Testa push notifications
       * Monta XML e exibe Toast (WinRT)
   - Para cada usuário interativo conectado:
       * Cria/roda Tarefa Agendada com LogonType=InteractiveToken no contexto desse usuário
       * Remove a tarefa após execução

  Observações:
   - Sem dependências externas (não usa PsExec, ServiceUI, etc.)
   - Imagens podem ser caminhos locais ou URLs (http/https).
   - Se o AppID for novo, o Windows às vezes demora um pouco para "aceitar";
     mas a tarefa roda no HKCU do usuário, que é o requisito principal.
#>

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ===================== CONFIGURÁVEL (conteúdo do Toast) =====================
$Scenario              = 'reminder'                  # 'default' | 'reminder' | 'alarm' | etc.
$SilentAlarm           = 'true'                      # 'true' ou 'false' (string, pois vai para XML)

$AttributionText       = 'TI - Comunicado'
$HeaderText            = 'Atualização Obrigatória'
$TitleText             = 'Windows 10 → Windows 11'
$BodyText1             = 'Clique em "Ver detalhes" para iniciar o processo. Salve seu trabalho antes de prosseguir.'

# Imagens: podem ser caminho local (ex: C:\ProgramData\Toast\logo.png) ou URL https
$HeroImage             = 'https://i.imghippo.com/files/OhKb7339C.png'   # imagem grande (hero)
$LogoImage             = 'https://upload.wikimedia.org/wikipedia/commons/5/5f/Windows_logo_-_2021.svg'

# Botões (protocol handlers ou URLs)
$Action                = 'https://arco.educacao/migracao'               # botão 1
$ActionButtonContent   = 'Ver detalhes'
$Action2               = 'ToastReboot://'                               # Ex.: seu protocolo customizado
$Action2ButtonContent  = 'Reiniciar depois'

# AppID que figurará no Centro de Ações (mantive o do PowerShell clássico)
$AppIdForActionCenter  = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

# Diretório/arquivo do script auxiliar (roda no contexto de cada usuário)
$ToastWorkDir          = 'C:\ProgramData\Toast'
$ToastScriptPath       = Join-Path $ToastWorkDir 'Show-Toast.ps1'

# Nome base da tarefa (um sufixo por usuário será adicionado)
$TaskBaseName          = 'GDL-ShowToast'
# =================== FIM DA ÁREA CONFIGURÁVEL ==============================


# --- Garante pasta de trabalho ---
New-Item -Path $ToastWorkDir -ItemType Directory -Force | Out-Null


# --- Script auxiliar que roda no HKCU do usuário (UI visível no desktop do usuário) ---
$ToastScript = @"
param(
  [string]`$Scenario,
  [string]`$SilentAlarm,
  [string]`$AttributionText,
  [string]`$HeaderText,
  [string]`$TitleText,
  [string]`$BodyText1,
  [string]`$HeroImage,
  [string]`$LogoImage,
  [string]`$Action,
  [string]`$ActionButtonContent,
  [string]`$Action2,
  [string]`$Action2ButtonContent,
  [string]`$AppIdForActionCenter
)

# ========= Função de verificação (HKCU) =========
function Test-WindowsPushNotificationsEnabled {
    try {
        `$ToastEnabledKey = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name ToastEnabled -ErrorAction Ignore).ToastEnabled
        if (`$ToastEnabledKey -eq "1") { Write-Host "Notificações Toast estão habilitadas no Windows"; return `$true }
        elseif (`$ToastEnabledKey -eq "0") { Write-Host "Toast desabilitado. Pode não exibir."; return `$false }
        else { Write-Host "Estado do Toast desconhecido. Script seguirá."; return `$false }
    } catch { Write-Host "Falha ao consultar PushNotifications: `$($_.Exception.Message)"; return `$false }
}

# ========= Garante AppID no Centro de Ações (HKCU) =========
try {
    `$RegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"
    if (-not (Test-Path -Path "`$RegPath\`$AppIdForActionCenter")) {
        New-Item -Path "`$RegPath\`$AppIdForActionCenter" -Force | Out-Null
        New-ItemProperty -Path "`$RegPath\`$AppIdForActionCenter" -Name "ShowInActionCenter" -Value 1 -PropertyType "DWORD" -Force | Out-Null
    } else {
        if ((Get-ItemProperty -Path "`$RegPath\`$AppIdForActionCenter" -Name "ShowInActionCenter" -ErrorAction SilentlyContinue).ShowInActionCenter -ne 1) {
            New-ItemProperty -Path "`$RegPath\`$AppIdForActionCenter" -Name "ShowInActionCenter" -Value 1 -PropertyType "DWORD" -Force | Out-Null
        }
    }
} catch {
    Write-Host "Falha ajustando Centro de Ações (HKCU): `$($_.Exception.Message)"
}

# ========= Checa Push Notifications =========
`$null = Test-WindowsPushNotificationsEnabled

# ========= Monta XML do Toast =========
[xml]`$Toast = @"
<toast scenario="`$Scenario">
  <visual>
    <binding template="ToastGeneric">
      <image placement="hero" src="`$HeroImage"/>
      <image id="1" placement="appLogoOverride" hint-crop="circle" src="`$LogoImage"/>
      <text placement="attribution">`$AttributionText</text>
      <text>`$HeaderText</text>
      <group>
        <subgroup>
          <text hint-style="title" hint-wrap="true">`$TitleText</text>
        </subgroup>
      </group>
      <group>
        <subgroup>
          <text hint-style="body" hint-wrap="true">`$BodyText1</text>
        </subgroup>
      </group>
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Looping.Alarm" silent="`$SilentAlarm"></audio>
  <actions>
    <action activationType="protocol" arguments="`$Action"  content="`$ActionButtonContent" />
    <action activationType="protocol" arguments="`$Action2" content="`$Action2ButtonContent" />
  </actions>
</toast>
"@

try {
    # ========= Carrega tipos WinRT e dispara =========
    `$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    `$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

    `$ToastXml = New-Object -TypeName Windows.Data.Xml.Dom.XmlDocument
    `$ToastXml.LoadXml(`$Toast.OuterXml)

    Write-Host "Tudo certo. Exibindo a notificação toast"
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(`$AppIdForActionCenter).Show(`$ToastXml)
} catch {
    Write-Host "Falha ao exibir Toast: `$($_.Exception.Message)"
}
"@

# Grava o script auxiliar
Set-Content -Path $ToastScriptPath -Value $ToastScript -Encoding UTF8 -Force


# --- Descobre usuários interativos conectados (Sessões ativas) ---
function Get-InteractiveUsers {
    # Usa WMI/CIM para sessões interativas (LogonType=2)
    $logons = Get-CimInstance Win32_LogonSession -Filter "LogonType=2"
    $links  = Get-CimInstance Win32_LoggedOnUser
    $pairs  = foreach ($l in $links) {
        try {
            $acc = $l.Antecedent | Get-CimInstance
            $ses = $l.Dependent  | Get-CimInstance
            if ($ses.LogonId -in $logons.LogonId) {
                [PSCustomObject]@{
                    Domain   = $acc.Domain
                    User     = $acc.Name
                    Sid      = $acc.SID
                }
            }
        } catch {}
    }
    # Remove duplicados
    $pairs | Where-Object { $_.User -and $_.Sid } | Sort-Object Sid -Unique
}

$users = Get-InteractiveUsers
if (-not $users) {
    Write-Host "Nenhum usuário interativo encontrado. Nada a fazer."
    return
}

# --- Função: cria/roda tarefa no contexto do usuário (InteractiveToken) ---
function Invoke-InUserContext {
    param(
        [Parameter(Mandatory=$true)] [string] $UserSid,
        [Parameter(Mandatory=$true)] [string] $TaskNameSuffix,
        [Parameter(Mandatory=$true)] [string] $ToastScriptPath,
        [Parameter(Mandatory=$true)] [hashtable] $ToastParams
    )

    $svc = New-Object -ComObject 'Schedule.Service'
    $svc.Connect()
    $root = $svc.GetFolder('\')
    $task = $svc.NewTask(0)

    # Metadados
    $task.RegistrationInfo.Description = 'Mostra uma notificação Toast no contexto do usuário logado.'
    $task.Settings.Enabled = $true
    $task.Settings.Hidden  = $true
    $task.Settings.StartWhenAvailable = $true
    $task.Settings.DisallowStartIfOnBatteries = $false
    $task.Settings.StopIfGoingOnBatteries = $false
    $task.Settings.MultipleInstances = 0 # Ignorar nova instância

    # Executa SOMENTE quando usuário estiver logado; não pede senha
    $task.Principal.UserId    = $UserSid
    $task.Principal.LogonType = 3   # TASK_LOGON_INTERACTIVE_TOKEN
    $task.Principal.RunLevel  = 0   # LeastPrivilege

    # Dispara imediatamente (TimeTrigger agora + 5s)
    $trg = $task.Triggers.Create(1) # TIME_TRIGGER
    $trg.StartBoundary = (Get-Date).AddSeconds(5).ToString('s')
    $trg.Enabled = $true

    # Monta argumentos para o script auxiliar
    $argList = @(
        '-NoProfile',
        '-WindowStyle', 'Hidden',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $ToastScriptPath),
        ('-Scenario "{0}"'             -f $ToastParams.Scenario),
        ('-SilentAlarm "{0}"'          -f $ToastParams.SilentAlarm),
        ('-AttributionText "{0}"'      -f $ToastParams.AttributionText),
        ('-HeaderText "{0}"'           -f $ToastParams.HeaderText),
        ('-TitleText "{0}"'            -f $ToastParams.TitleText),
        ('-BodyText1 "{0}"'            -f $ToastParams.BodyText1),
        ('-HeroImage "{0}"'            -f $ToastParams.HeroImage),
        ('-LogoImage "{0}"'            -f $ToastParams.LogoImage),
        ('-Action "{0}"'               -f $ToastParams.Action),
        ('-ActionButtonContent "{0}"'  -f $ToastParams.ActionButtonContent),
        ('-Action2 "{0}"'              -f $ToastParams.Action2),
        ('-Action2ButtonContent "{0}"' -f $ToastParams.Action2ButtonContent),
        ('-AppIdForActionCenter "{0}"' -f $ToastParams.AppIdForActionCenter)
    ) -join ' '

    $act = $task.Actions.Create(0) # EXEC
    $act.Path = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $act.Arguments = $argList

    $taskName = "$TaskBaseName-$TaskNameSuffix"
    # 6 = TASK_CREATE_OR_UPDATE | 3 = TASK_LOGON_INTERACTIVE_TOKEN
    $null = $root.RegisterTaskDefinition($taskName, $task, 6, $null, $null, 3)

    # Executa imediatamente e depois agenda remoção
    try {
        $reg = $root.GetTask("\$taskName")
        $null = $reg.Run($null)
        Start-Sleep -Seconds 10
    } catch {
        Write-Host "Falha ao rodar tarefa $taskName: $($_.Exception.Message)"
    } finally {
        try { $root.DeleteTask($taskName, 0) | Out-Null } catch {}
    }
}

# Parâmetros para o script auxiliar
$toastParams = @{
    Scenario             = $Scenario
    SilentAlarm          = $SilentAlarm
    AttributionText      = $AttributionText
    HeaderText           = $HeaderText
    TitleText            = $TitleText
    BodyText1            = $BodyText1
    HeroImage            = $HeroImage
    LogoImage            = $LogoImage
    Action               = $Action
    ActionButtonContent  = $ActionButtonContent
    Action2              = $Action2
    Action2ButtonContent = $Action2ButtonContent
    AppIdForActionCenter = $AppIdForActionCenter
}

# Dispara para cada usuário interativo
foreach ($u in $users) {
    try {
        $suffix = ($u.Sid -replace '[^0-9A-F]', '').Substring([Math]::Max(0, ($u.Sid.Length - 6)))
        Write-Host "Disparando Toast para $($u.Domain)\$($u.User) (SID=$($u.Sid))..."
        Invoke-InUserContext -UserSid $u.Sid -TaskNameSuffix $suffix -ToastScriptPath $ToastScriptPath -ToastParams $toastParams
    } catch {
        Write-Host "Erro ao preparar Toast p/ $($u.Domain)\$($u.User): $($_.Exception.Message)"
    }
}

Write-Host "Concluído."
