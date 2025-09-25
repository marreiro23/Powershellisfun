#requires -Version 5.1
<#
.SYNOPSIS
    Script para relatórios do Microsoft Graph - Gerenciamento de Dispositivos
.DESCRIPTION
    Este script coleta informações de dispositivos gerenciados pelo Intune/Endpoint Manager
    e gera relatórios de conformidade e sincronização com validação completa
.NOTES
    Autor: PowerShell is Fun
    Versão: 2.0
    Permissões necessárias: 
    - DeviceManagementManagedDevices.Read.All
    - DeviceManagementConfiguration.Read.All
    - Device.Read.All (opcional para mais detalhes)
#>

# Função para verificar e instalar módulos necessários
function Test-RequiredModules {
    param(
        [string[]]$ModuleNames
    )
    
    Write-Host "=== Validação de Módulos Microsoft Graph ===" -ForegroundColor Magenta
    $missingModules = @()
    
    foreach ($module in $ModuleNames) {
        Write-Host "Verificando módulo: $module" -ForegroundColor Cyan
        
        $installedModule = Get-Module -ListAvailable -Name $module | Sort-Object Version -Descending | Select-Object -First 1
        
        if (!$installedModule) {
            Write-Warning "Módulo $module não encontrado!"
            $missingModules += $module
        } else {
            Write-Host "✓ $module (v$($installedModule.Version)) encontrado" -ForegroundColor Green
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Host "`nInstalando módulos em falta..." -ForegroundColor Yellow
        foreach ($module in $missingModules) {
            try {
                Write-Host "Instalando $module..." -ForegroundColor Yellow
                Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
                Write-Host "✓ $module instalado com sucesso" -ForegroundColor Green
            }
            catch {
                Write-Error "Erro ao instalar $module : $($_.Exception.Message)"
                return $false
            }
        }
    }
    return $true
}

# Função para testar conectividade com Microsoft Graph
function Test-GraphConnection {
    try {
        $context = Get-MgContext -ErrorAction SilentlyContinue
        if ($context) {
            Write-Host "✓ Conectado ao Microsoft Graph como: $($context.Account)" -ForegroundColor Green
            Write-Host "  - Tenant: $($context.TenantId)" -ForegroundColor Gray
            Write-Host "  - Scopes: $($context.Scopes -join ', ')" -ForegroundColor Gray
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

# Função para obter dados de dispositivos com tratamento de erro
function Get-DeviceData {
    param(
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 2
    )
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-Host "Tentativa $i/$MaxRetries - Obtendo dispositivos gerenciados..." -ForegroundColor Cyan
            
            # Query otimizada com filtros específicos
            $devices = Get-MgDeviceManagementManagedDevice -All -Property @(
                'Id', 'DeviceName', 'UserDisplayName', 'UserPrincipalName',
                'OperatingSystem', 'OSVersion', 'LastSyncDateTime', 
                'ComplianceState', 'ManagementAgent', 'EnrolledDateTime',
                'SerialNumber', 'Model', 'Manufacturer', 'IsEncrypted',
                'JailBroken', 'DeviceType', 'DeviceRegistrationState'
            ) -ErrorAction Stop
            
            Write-Host "✓ $($devices.Count) dispositivos obtidos com sucesso" -ForegroundColor Green
            return $devices
        }
        catch {
            Write-Warning "Tentativa $i falhou: $($_.Exception.Message)"
            if ($i -lt $MaxRetries) {
                Write-Host "Aguardando $DelaySeconds segundos antes da próxima tentativa..." -ForegroundColor Yellow
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }
    
    Write-Error "Falha ao obter dados dos dispositivos após $MaxRetries tentativas"
    return $null
}
}

# Função para obter políticas de conformidade
function Get-ComplianceData {
    try {
        Write-Host "Obtendo políticas de conformidade..." -ForegroundColor Cyan
        
        $policies = Get-MgDeviceManagementDeviceCompliancePolicy -All -Property @(
            'Id', 'DisplayName', 'Description', 'CreatedDateTime', 
            'LastModifiedDateTime', 'ScheduledActionsForRule'
        ) -ErrorAction Stop
        
        Write-Host "✓ $($policies.Count) políticas de conformidade obtidas" -ForegroundColor Green
        return $policies
    }
    catch {
        Write-Warning "Erro ao obter políticas de conformidade: $($_.Exception.Message)"
        return @()
    }
}

# Função para gerar relatório detalhado
function New-DeviceReport {
    param(
        [array]$Devices,
        [array]$CompliancePolicies
    )
    
    if (!$Devices -or $Devices.Count -eq 0) {
        Write-Warning "Nenhum dispositivo encontrado para gerar relatório"
        return
    }
    
    # Estatísticas gerais
    Write-Host "`n" + "=" * 80 -ForegroundColor Magenta
    Write-Host "RELATÓRIO EXECUTIVO - DISPOSITIVOS GERENCIADOS" -ForegroundColor Magenta
    Write-Host "=" * 80 -ForegroundColor Magenta
    
    $totalDevices = $Devices.Count
    $compliantDevices = ($Devices | Where-Object { $_.ComplianceState -eq 'Compliant' }).Count
    $nonCompliantDevices = ($Devices | Where-Object { $_.ComplianceState -eq 'Noncompliant' }).Count
    $unknownDevices = ($Devices | Where-Object { $_.ComplianceState -notin @('Compliant', 'Noncompliant') }).Count
    
    Write-Host "Total de Dispositivos: $totalDevices" -ForegroundColor White
    Write-Host "✓ Conformes: $compliantDevices ($([math]::Round(($compliantDevices/$totalDevices)*100,1))%)" -ForegroundColor Green
    Write-Host "✗ Não Conformes: $nonCompliantDevices ($([math]::Round(($nonCompliantDevices/$totalDevices)*100,1))%)" -ForegroundColor Red
    Write-Host "? Status Desconhecido: $unknownDevices ($([math]::Round(($unknownDevices/$totalDevices)*100,1))%)" -ForegroundColor Yellow
    
    # Análise por Sistema Operacional
    Write-Host "`n--- Distribuição por Sistema Operacional ---" -ForegroundColor Yellow
    $osGroups = $Devices | Group-Object OperatingSystem | Sort-Object Count -Descending
    foreach ($os in $osGroups) {
        $percentage = [math]::Round(($os.Count/$totalDevices)*100,1)
        Write-Host "$($os.Name): $($os.Count) ($percentage%)" -ForegroundColor Cyan
    }
    
    # Dispositivos com problemas de sincronização (mais de 7 dias)
    Write-Host "`n--- Dispositivos com Problemas de Sincronização ---" -ForegroundColor Yellow
    $outdatedSync = $Devices | Where-Object { 
        $_.LastSyncDateTime -and 
        (Get-Date) - [DateTime]$_.LastSyncDateTime -gt [TimeSpan]::FromDays(7) 
    }
    
    if ($outdatedSync.Count -gt 0) {
        Write-Host "Dispositivos sem sincronização há mais de 7 dias: $($outdatedSync.Count)" -ForegroundColor Red
        foreach ($device in $outdatedSync | Select-Object -First 10) {
            $daysSinceSync = [math]::Floor(((Get-Date) - [DateTime]$device.LastSyncDateTime).TotalDays)
            Write-Host "  • $($device.DeviceName) - $daysSinceSync dias" -ForegroundColor Red
        }
        if ($outdatedSync.Count -gt 10) {
            Write-Host "  ... e mais $($outdatedSync.Count - 10) dispositivos" -ForegroundColor Gray
        }
    } else {
        Write-Host "✓ Todos os dispositivos sincronizaram recentemente" -ForegroundColor Green
    }
    
    # Relatório detalhado por dispositivo
    Write-Host "`n" + "=" * 80 -ForegroundColor Magenta
    Write-Host "RELATÓRIO DETALHADO POR DISPOSITIVO" -ForegroundColor Magenta
    Write-Host "=" * 80 -ForegroundColor Magenta
    
    foreach ($device in $Devices | Sort-Object DeviceName) {
        $lastSync = if ($device.LastSyncDateTime) { 
            [DateTime]$device.LastSyncDateTime
            $syncDisplay = $lastSync.ToString("dd/MM/yyyy HH:mm:ss")
            $daysSinceSync = [math]::Floor(((Get-Date) - $lastSync).TotalDays)
            if ($daysSinceSync -gt 0) {
                $syncDisplay += " ($daysSinceSync dias atrás)"
            }
        } else { 
            $syncDisplay = "Nunca sincronizado"
        }
        
        # Cor baseada no status de conformidade
        $deviceColor = switch ($device.ComplianceState) {
            'Compliant' { 'Green' }
            'Noncompliant' { 'Red' }
            default { 'Yellow' }
        }
        
        Write-Host "`nDispositivo: $($device.DeviceName)" -ForegroundColor $deviceColor
        Write-Host "  📱 Modelo: $($device.Manufacturer) $($device.Model)" -ForegroundColor White
        Write-Host "  👤 Usuário: $($device.UserDisplayName) ($($device.UserPrincipalName))" -ForegroundColor White
        Write-Host "  💻 SO: $($device.OperatingSystem) $($device.OSVersion)" -ForegroundColor White
        Write-Host "  🔄 Última Sync: $syncDisplay" -ForegroundColor White
        Write-Host "  ✅ Conformidade: $($device.ComplianceState)" -ForegroundColor $deviceColor
        Write-Host "  📊 Gerenciado por: $($device.ManagementAgent)" -ForegroundColor White
        Write-Host "  🔒 Criptografado: $(if($device.IsEncrypted){'Sim'}else{'Não'})" -ForegroundColor $(if($device.IsEncrypted){'Green'}else{'Red'})
        if ($device.SerialNumber) {
            Write-Host "  🏷️  Serial: $($device.SerialNumber)" -ForegroundColor Gray
        }
    }
    
    # Resumo de políticas de conformidade
    if ($CompliancePolicies.Count -gt 0) {
        Write-Host "`n" + "=" * 80 -ForegroundColor Magenta
        Write-Host "POLÍTICAS DE CONFORMIDADE ATIVAS" -ForegroundColor Magenta
        Write-Host "=" * 80 -ForegroundColor Magenta
        
        foreach ($policy in $CompliancePolicies | Sort-Object DisplayName) {
            Write-Host "`nPolítica: $($policy.DisplayName)" -ForegroundColor Cyan
            if ($policy.Description) {
                Write-Host "  📝 Descrição: $($policy.Description)" -ForegroundColor White
            }
            Write-Host "  📅 Criada em: $([DateTime]$policy.CreatedDateTime)" -ForegroundColor Gray
            Write-Host "  🔄 Modificada em: $([DateTime]$policy.LastModifiedDateTime)" -ForegroundColor Gray
        }
    }
}

# ============================================================================
# EXECUÇÃO PRINCIPAL
# ============================================================================

# Verificar módulos necessários
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.DeviceManagement'
)

if (!(Test-RequiredModules -ModuleNames $requiredModules)) {
    Write-Error "Falha na verificação/instalação dos módulos. Abortando execução."
    exit 1
}

# Importar módulos
Write-Host "`n=== Importando Módulos ===" -ForegroundColor Magenta
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop
    Write-Host "✓ Módulos importados com sucesso" -ForegroundColor Green
}
catch {
    Write-Error "Erro ao importar módulos: $($_.Exception.Message)"
    exit 1
}

# Verificar conexão existente
Write-Host "`n=== Verificando Conexão ===" -ForegroundColor Magenta
if (Test-GraphConnection) {
    $reconnect = Read-Host "Deseja reconectar? (s/N)"
    if ($reconnect -eq 's' -or $reconnect -eq 'S') {
        Disconnect-MgGraph
    }
}

# Conectar se necessário
if (!(Test-GraphConnection)) {
    Write-Host "Conectando ao Microsoft Graph..." -ForegroundColor Cyan
    try {
        Connect-MgGraph -Scopes @(
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementConfiguration.Read.All",
            "Device.Read.All"
        ) -NoWelcome -ErrorAction Stop
        
        if (Test-GraphConnection) {
            Write-Host "✓ Conectado com sucesso ao Microsoft Graph" -ForegroundColor Green
        } else {
            throw "Falha na autenticação"
        }
    }
    catch {
        Write-Error "Erro ao conectar ao Microsoft Graph: $($_.Exception.Message)"
        exit 1
    }
}

# Coletar dados
Write-Host "`n=== Coletando Dados ===" -ForegroundColor Magenta
$devices = Get-DeviceData
$compliancePolicies = Get-ComplianceData

# Gerar relatório
if ($devices) {
    New-DeviceReport -Devices $devices -CompliancePolicies $compliancePolicies
    
    # Opção para exportar dados
    Write-Host "`n=== Opções de Exportação ===" -ForegroundColor Magenta
    $export = Read-Host "Deseja exportar os dados para CSV? (s/N)"
    if ($export -eq 's' -or $export -eq 'S') {
        $exportPath = Join-Path $PSScriptRoot "DeviceReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        try {
            $devices | Select-Object DeviceName, UserDisplayName, OperatingSystem, LastSyncDateTime, ComplianceState, ManagementAgent | 
                Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
            Write-Host "✓ Dados exportados para: $exportPath" -ForegroundColor Green
        }
        catch {
            Write-Warning "Erro ao exportar dados: $($_.Exception.Message)"
        }
    }
} else {
    Write-Error "Não foi possível coletar dados dos dispositivos"
}

Write-Host "`n=== Script Finalizado ===" -ForegroundColor Magenta