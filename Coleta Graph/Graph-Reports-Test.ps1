#Instação do módulo Microsoft Graph
Get-Module -ListAvailable Microsoft.Graph*
$PSVersionTable.PSVersion; Get-ExecutionPolicy
Get-InstalledModule Microsoft.Graph* | Select-Object Name, Version
Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force -AllowClobber

# Importação do módulo e autenticação
Write-Host "Aguardando instalação..." ; Start-Sleep -Seconds 10
Install-Module -Name Microsoft.Graph.DeviceManagement -Scope CurrentUser -Force
Get-InstalledModule Microsoft.Graph*

Install-Module Microsoft.Graph -Scope CurrentUser
Import-Module Microsoft.Graph
# Permissões necessárias: DeviceManagementManagedDevices.Read.All, DeviceManagementConfiguration.Read.All

# Importar módulos necessários
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.DeviceManagement

# Autenticação com Microsoft Graph
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", "DeviceManagementConfiguration.Read.All"

# Listar dispositivos gerenciados
Write-Host "Obtendo lista de dispositivos..." -ForegroundColor Green
$devices = Get-MgDeviceManagementManagedDevice

# Status de conformidade
Write-Host "Obtendo status de conformidade..." -ForegroundColor Green
$compliancePolicies = Get-MgDeviceManagementDeviceCompliancePolicy

# Exibir status de conformidade
foreach ($policy in $compliancePolicies) {
    Write-Host "Política: $($policy.DisplayName)" -ForegroundColor Cyan
    Write-Host "  - Descrição: $($policy.Description)" -ForegroundColor White
    Write-Host "  - Última Modificação: $($policy.LastModifiedDateTime)" -ForegroundColor White
    Write-Host ""
}

# Relatório de dispositivos e última sincronização
Write-Host "`nRelatório de Dispositivos:" -ForegroundColor Yellow
Write-Host "=" * 50 -ForegroundColor Yellow

foreach ($device in $devices) {
    $lastSync = if ($device.LastSyncDateTime) { 
        $device.LastSyncDateTime.ToString("dd/MM/yyyy HH:mm:ss") 
    } else { 
        "Nunca sincronizado" 
    }
    
    Write-Host "Dispositivo: $($device.DeviceName)" -ForegroundColor Cyan
    Write-Host "  - Usuário: $($device.UserDisplayName)" -ForegroundColor White
    Write-Host "  - SO: $($device.OperatingSystem)" -ForegroundColor White
    Write-Host "  - Última Sync: $lastSync" -ForegroundColor White
    Write-Host "  - Status de Conformidade: $($device.ComplianceState)" -ForegroundColor White
    Write-Host "  - Gerenciado por: $($device.ManagementAgent)" -ForegroundColor White
    Write-Host ""
}

Write-Host "Total de dispositivos encontrados: $($devices.Count)" -ForegroundColor Green