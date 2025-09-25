#requires -Version 5.1
<#
.SYNOPSIS
    Script para relatórios do Microsoft Graph - Gerenciamento de Dispositivos
.DESCRIPTION
    Este script coleta informações de dispositivos gerenciados pelo Intune/Endpoint Manager
.NOTES
    Autor: PowerShell is Fun
    Versão: 2.0
    Permissões necessárias: 
    - DeviceManagementManagedDevices.Read.All
    - DeviceManagementConfiguration.Read.All
#>

# Função para verificar e instalar módulos necessários
function Test-RequiredModules {
    param([string[]]$ModuleNames)
    
    Write-Host "=== Validacao de Modulos Microsoft Graph ===" -ForegroundColor Magenta
    $missingModules = @()
    
    foreach ($module in $ModuleNames) {
        Write-Host "Verificando modulo: $module" -ForegroundColor Cyan
        
        $installedModule = Get-Module -ListAvailable -Name $module | Sort-Object Version -Descending | Select-Object -First 1
        
        if (!$installedModule) {
            Write-Warning "Modulo $module nao encontrado!"
            $missingModules += $module
        } else {
            Write-Host "OK $module (v$($installedModule.Version)) encontrado" -ForegroundColor Green
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Host "Instalando modulos em falta..." -ForegroundColor Yellow
        foreach ($module in $missingModules) {
            try {
                Write-Host "Instalando $module..." -ForegroundColor Yellow
                Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
                Write-Host "OK $module instalado com sucesso" -ForegroundColor Green
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
            Write-Host "OK Conectado ao Microsoft Graph como: $($context.Account)" -ForegroundColor Green
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
            
            $devices = Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop
            
            Write-Host "OK $($devices.Count) dispositivos obtidos com sucesso" -ForegroundColor Green
            return $devices
        }
        catch {
            Write-Warning "Tentativa $i falhou: $($_.Exception.Message)"
            if ($i -lt $MaxRetries) {
                Write-Host "Aguardando $DelaySeconds segundos antes da proxima tentativa..." -ForegroundColor Yellow
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }
    
    Write-Error "Falha ao obter dados dos dispositivos apos $MaxRetries tentativas"
    return $null
}

# Função para obter políticas de conformidade
function Get-ComplianceData {
    try {
        Write-Host "Obtendo politicas de conformidade..." -ForegroundColor Cyan
        $policies = Get-MgDeviceManagementDeviceCompliancePolicy -All -ErrorAction Stop
        Write-Host "OK $($policies.Count) politicas de conformidade obtidas" -ForegroundColor Green
        return $policies
    }
    catch {
        Write-Warning "Erro ao obter politicas de conformidade: $($_.Exception.Message)"
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
        Write-Warning "Nenhum dispositivo encontrado para gerar relatorio"
        return
    }
    
    # Estatísticas gerais
    Write-Host "`n" + "=" * 80 -ForegroundColor Magenta
    Write-Host "RELATORIO EXECUTIVO - DISPOSITIVOS GERENCIADOS" -ForegroundColor Magenta
    Write-Host "=" * 80 -ForegroundColor Magenta
    
    $totalDevices = $Devices.Count
    $compliantDevices = ($Devices | Where-Object { $_.ComplianceState -eq 'Compliant' }).Count
    $nonCompliantDevices = ($Devices | Where-Object { $_.ComplianceState -eq 'Noncompliant' }).Count
    $unknownDevices = ($Devices | Where-Object { $_.ComplianceState -notin @('Compliant', 'Noncompliant') }).Count
    
    Write-Host "Total de Dispositivos: $totalDevices" -ForegroundColor White
    
    if ($totalDevices -gt 0) {
        $compliantPerc = [math]::Round(($compliantDevices/$totalDevices)*100,1)
        $nonCompliantPerc = [math]::Round(($nonCompliantDevices/$totalDevices)*100,1)
        $unknownPerc = [math]::Round(($unknownDevices/$totalDevices)*100,1)
        
        Write-Host "OK Conformes: $compliantDevices ($compliantPerc%)" -ForegroundColor Green
        Write-Host "X Nao Conformes: $nonCompliantDevices ($nonCompliantPerc%)" -ForegroundColor Red
        Write-Host "? Status Desconhecido: $unknownDevices ($unknownPerc%)" -ForegroundColor Yellow
    }
    
    # Análise por Sistema Operacional
    Write-Host "`n--- Distribuicao por Sistema Operacional ---" -ForegroundColor Yellow
    $osGroups = $Devices | Group-Object OperatingSystem | Sort-Object Count -Descending
    foreach ($os in $osGroups) {
        if ($totalDevices -gt 0) {
            $percentage = [math]::Round(($os.Count/$totalDevices)*100,1)
            Write-Host "$($os.Name): $($os.Count) ($percentage%)" -ForegroundColor Cyan
        }
    }
    
    # Dispositivos com problemas de sincronização
    Write-Host "`n--- Dispositivos com Problemas de Sincronizacao ---" -ForegroundColor Yellow
    $outdatedSync = $Devices | Where-Object { 
        $_.LastSyncDateTime -and 
        (Get-Date) - [DateTime]$_.LastSyncDateTime -gt [TimeSpan]::FromDays(7) 
    }
    
    if ($outdatedSync.Count -gt 0) {
        Write-Host "Dispositivos sem sincronizacao ha mais de 7 dias: $($outdatedSync.Count)" -ForegroundColor Red
        foreach ($device in $outdatedSync | Select-Object -First 5) {
            $daysSinceSync = [math]::Floor(((Get-Date) - [DateTime]$device.LastSyncDateTime).TotalDays)
            Write-Host "  - $($device.DeviceName) - $daysSinceSync dias" -ForegroundColor Red
        }
    } else {
        Write-Host "OK Todos os dispositivos sincronizaram recentemente" -ForegroundColor Green
    }
    
    # Relatório detalhado por dispositivo
    Write-Host "`n" + "=" * 80 -ForegroundColor Magenta
    Write-Host "RELATORIO DETALHADO POR DISPOSITIVO" -ForegroundColor Magenta
    Write-Host "=" * 80 -ForegroundColor Magenta
    
    foreach ($device in $Devices | Sort-Object DeviceName | Select-Object -First 10) {
        $syncDisplay = "Nunca sincronizado"
        if ($device.LastSyncDateTime) { 
            $lastSync = [DateTime]$device.LastSyncDateTime
            $syncDisplay = $lastSync.ToString("dd/MM/yyyy HH:mm:ss")
            $daysSinceSync = [math]::Floor(((Get-Date) - $lastSync).TotalDays)
            if ($daysSinceSync -gt 0) {
                $syncDisplay += " ($daysSinceSync dias atras)"
            }
        }
        
        $deviceColor = 'White'
        switch ($device.ComplianceState) {
            'Compliant' { $deviceColor = 'Green' }
            'Noncompliant' { $deviceColor = 'Red' }
            default { $deviceColor = 'Yellow' }
        }
        
        Write-Host "`nDispositivo: $($device.DeviceName)" -ForegroundColor $deviceColor
        Write-Host "  Usuario: $($device.UserDisplayName)" -ForegroundColor White
        Write-Host "  SO: $($device.OperatingSystem) $($device.OSVersion)" -ForegroundColor White
        Write-Host "  Ultima Sync: $syncDisplay" -ForegroundColor White
        Write-Host "  Conformidade: $($device.ComplianceState)" -ForegroundColor $deviceColor
        Write-Host "  Gerenciado por: $($device.ManagementAgent)" -ForegroundColor White
        if ($device.SerialNumber) {
            Write-Host "  Serial: $($device.SerialNumber)" -ForegroundColor Gray
        }
    }
    
    if ($Devices.Count -gt 10) {
        Write-Host "`n... e mais $($Devices.Count - 10) dispositivos" -ForegroundColor Gray
    }
}

# ============================================================================
# EXECUCAO PRINCIPAL
# ============================================================================

# Verificar módulos necessários
$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.DeviceManagement'
)

Write-Host "Iniciando validacao do script..." -ForegroundColor Cyan

if (!(Test-RequiredModules -ModuleNames $requiredModules)) {
    Write-Error "Falha na verificacao/instalacao dos modulos. Abortando execucao."
    exit 1
}

# Importar módulos
Write-Host "`n=== Importando Modulos ===" -ForegroundColor Magenta
try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop
    Write-Host "OK Modulos importados com sucesso" -ForegroundColor Green
}
catch {
    Write-Error "Erro ao importar modulos: $($_.Exception.Message)"
    exit 1
}

# Verificar conexão existente
Write-Host "`n=== Verificando Conexao ===" -ForegroundColor Magenta
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
            "DeviceManagementConfiguration.Read.All"
        ) -NoWelcome -ErrorAction Stop
        
        if (Test-GraphConnection) {
            Write-Host "OK Conectado com sucesso ao Microsoft Graph" -ForegroundColor Green
        } else {
            throw "Falha na autenticacao"
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
    Write-Host "`n=== Opcoes de Exportacao ===" -ForegroundColor Magenta
    $export = Read-Host "Deseja exportar os dados para CSV? (s/N)"
    if ($export -eq 's' -or $export -eq 'S') {
        $exportPath = Join-Path $PSScriptRoot "DeviceReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        try {
            $devices | Select-Object DeviceName, UserDisplayName, OperatingSystem, LastSyncDateTime, ComplianceState, ManagementAgent | 
                Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
            Write-Host "OK Dados exportados para: $exportPath" -ForegroundColor Green
        }
        catch {
            Write-Warning "Erro ao exportar dados: $($_.Exception.Message)"
        }
    }
} else {
    Write-Error "Nao foi possivel coletar dados dos dispositivos"
}

Write-Host "`n=== Script Finalizado ===" -ForegroundColor Magenta