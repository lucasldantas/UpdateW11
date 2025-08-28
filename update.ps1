#====================================================================
# Script de Update Windows 10 1945 para Windows 11
# Autor: Lucas Lopes Dantas
#====================================================================

#--------------- Passo 1 - Download e Montagem da ISO ---------------

$dest    = 'C:\Temp\UpdateW11'
$isoUrl  = 'https://temp-arco-itops.s3.us-east-1.amazonaws.com/Win11_24H2_BrazilianPortuguese_x64.iso'
$isoPath = Join-Path $dest 'Win11_24H2_BrazilianPortuguese_x64.iso'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Path $dest -Force | Out-Null

if (Get-PSDrive -Name X -ErrorAction SilentlyContinue) {
    Write-Host "Desmontando imagem anterior em X:..."
    $mountedImg = Get-DiskImage | Get-Volume | Where-Object { $_.DriveLetter -eq 'X' }
    if ($mountedImg) {
        Dismount-DiskImage -ImagePath $mountedImg.Path -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

# Só baixa se não existir
if (-not (Test-Path $isoPath)) {
    Write-Host "Baixando ISO..."
    Start-BitsTransfer -Source $isoUrl -Destination $isoPath
} else {
    Write-Host "✅ ISO já existe em $isoPath, pulando download."
}

Mount-DiskImage -ImagePath $isoPath
$vol    = Get-DiskImage -ImagePath $isoPath | Get-Volume
$oldDrv = $vol.DriveLetter + ':'
$newDrv = 'X:'

Get-CimInstance -Class Win32_Volume |
    Where-Object { $_.DriveLetter -eq $oldDrv } |
    Set-CimInstance -Arguments @{ DriveLetter = $newDrv }

Write-Host "✅ ISO montada em $newDrv"

#------------------------ Passo 2 - Execução ------------------------

Write-Host "▶ Iniciando atualização do Windows..."

$setupArgs = "/auto upgrade /DynamicUpdate disable /ShowOOBE none /noreboot /compat IgnoreWarning /BitLocker TryKeepActive /EULA accept /CopyLogs C:\Temp\UpdateW11\logs.log"

Start-Process -FilePath "X:\Setup.exe" -ArgumentList $setupArgs -Wait

Write-Host "✔ Instalação iniciada. Reiniciando máquina..."
MSG * "FIM"
#Restart-Computer -Timeout 10 -Force
