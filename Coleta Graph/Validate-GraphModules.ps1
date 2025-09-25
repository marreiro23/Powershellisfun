#requires -Version 5.1
<#
.SYNOPSIS
    Script de Validação para Módulos Microsoft Graph
.DESCRIPTION
    Este script valida a presença e funcionalidade dos módulos do Microsoft Graph
    antes da execução do script principal de relatórios
.NOTES
    Autor: PowerShell is Fun
    Versão: 1.0
#>

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   VALIDADOR DE MODULOS MICROSOFT GRAPH" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

# Lista de módulos necessários com suas respectivas funções críticas
$moduleValidation = @{
    'Microsoft.Graph.Authentication' = @('Connect-MgGraph', 'Get-MgContext', 'Disconnect-MgGraph')
    'Microsoft.Graph.DeviceManagement' = @('Get-MgDeviceManagementManagedDevice', 'Get-MgDeviceManagementDeviceCompliancePolicy')
}

$allModulesValid = $true

foreach ($module in $moduleValidation.Keys) {
    Write-Host "`n--- Validando $module ---" -ForegroundColor Yellow
    
    # Verificar se o módulo está disponível
    $availableModule = Get-Module -ListAvailable -Name $module | Sort-Object Version -Descending | Select-Object -First 1
    
    if (!$availableModule) {
        Write-Host "ERRO: Modulo $module nao encontrado!" -ForegroundColor Red
        Write-Host "Execute: Install-Module -Name $module -Scope CurrentUser" -ForegroundColor Yellow
        $allModulesValid = $false
        continue
    }
    
    Write-Host "OK: $module (v$($availableModule.Version)) encontrado" -ForegroundColor Green
    
    # Tentar importar o módulo
    try {
        Import-Module $module -Force -ErrorAction Stop
        Write-Host "OK: Modulo importado com sucesso" -ForegroundColor Green
    }
    catch {
        Write-Host "ERRO: Falha ao importar modulo - $($_.Exception.Message)" -ForegroundColor Red
        $allModulesValid = $false
        continue
    }
    
    # Validar comandos críticos
    $commands = $moduleValidation[$module]
    foreach ($command in $commands) {
        if (Get-Command $command -ErrorAction SilentlyContinue) {
            Write-Host "  OK: Comando $command disponivel" -ForegroundColor Green
        } else {
            Write-Host "  ERRO: Comando $command NAO disponivel" -ForegroundColor Red
            $allModulesValid = $false
        }
    }
}

# Teste de conectividade básica (sem autenticação completa)
Write-Host "`n--- Validando Conectividade ---" -ForegroundColor Yellow

try {
    # Verificar se já está conectado
    $context = Get-MgContext -ErrorAction SilentlyContinue
    if ($context) {
        Write-Host "OK: Ja conectado ao Microsoft Graph" -ForegroundColor Green
        Write-Host "  - Conta: $($context.Account)" -ForegroundColor Cyan
        Write-Host "  - Tenant: $($context.TenantId)" -ForegroundColor Cyan
        Write-Host "  - Scopes: $($context.Scopes -join ', ')" -ForegroundColor Cyan
        
        # Validar escopo necessário
        $requiredScopes = @(
            "DeviceManagementManagedDevices.Read.All",
            "DeviceManagementConfiguration.Read.All"
        )
        
        $missingScopes = @()
        foreach ($scope in $requiredScopes) {
            if ($scope -notin $context.Scopes) {
                $missingScopes += $scope
            }
        }
        
        if ($missingScopes.Count -gt 0) {
            Write-Host "AVISO: Escopos em falta: $($missingScopes -join ', ')" -ForegroundColor Yellow
            Write-Host "Execute novamente Connect-MgGraph com todos os escopos necessarios" -ForegroundColor Yellow
        } else {
            Write-Host "OK: Todos os escopos necessarios estao presentes" -ForegroundColor Green
        }
        
    } else {
        Write-Host "INFO: Nenhuma conexao ativa encontrada" -ForegroundColor Cyan
        Write-Host "Sera necessario autenticar ao executar o script principal" -ForegroundColor Cyan
    }
}
catch {
    Write-Host "ERRO: Falha ao verificar conectividade - $($_.Exception.Message)" -ForegroundColor Red
    $allModulesValid = $false
}

# Teste básico de queries (se conectado)
if ($context) {
    Write-Host "`n--- Validando Queries Basicas ---" -ForegroundColor Yellow
    
    try {
        # Teste simples para verificar se a API responde
        Write-Host "Testando acesso a dispositivos gerenciados..." -ForegroundColor Cyan
        $testDevices = Get-MgDeviceManagementManagedDevice -Top 1 -ErrorAction Stop
        Write-Host "OK: Query de dispositivos funcionando" -ForegroundColor Green
        
        Write-Host "Testando acesso a politicas de conformidade..." -ForegroundColor Cyan
        $testPolicies = Get-MgDeviceManagementDeviceCompliancePolicy -Top 1 -ErrorAction Stop
        Write-Host "OK: Query de politicas funcionando" -ForegroundColor Green
        
    }
    catch {
        Write-Host "ERRO: Falha nas queries de teste - $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Verifique as permissoes e escopos necessarios" -ForegroundColor Yellow
        $allModulesValid = $false
    }
}

# Validação de versão do PowerShell
Write-Host "`n--- Validando Ambiente PowerShell ---" -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
Write-Host "Versao PowerShell: $psVersion" -ForegroundColor Cyan

if ($psVersion.Major -ge 5) {
    Write-Host "OK: Versao do PowerShell compativel" -ForegroundColor Green
} else {
    Write-Host "AVISO: Versao do PowerShell pode ser incompativel (requerido 5.1+)" -ForegroundColor Yellow
}

# Verificar política de execução
$executionPolicy = Get-ExecutionPolicy
Write-Host "Politica de Execucao: $executionPolicy" -ForegroundColor Cyan

if ($executionPolicy -in @('RemoteSigned', 'Unrestricted', 'Bypass')) {
    Write-Host "OK: Politica de execucao permite scripts" -ForegroundColor Green
} else {
    Write-Host "AVISO: Politica de execucao restritiva - pode impedir execucao de scripts" -ForegroundColor Yellow
    Write-Host "Execute: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Yellow
}

# Resumo final
Write-Host "`n===============================================" -ForegroundColor Cyan
if ($allModulesValid) {
    Write-Host "RESULTADO: VALIDACAO CONCLUIDA COM SUCESSO!" -ForegroundColor Green
    Write-Host "O ambiente esta pronto para executar os scripts do Microsoft Graph" -ForegroundColor Green
    
    Write-Host "`nProximo passo:" -ForegroundColor Yellow
    Write-Host "Execute: .\Graph-Reports-Clean.ps1" -ForegroundColor White
} else {
    Write-Host "RESULTADO: VALIDACAO FALHOU!" -ForegroundColor Red
    Write-Host "Corrija os problemas indicados antes de executar os scripts" -ForegroundColor Red
    
    Write-Host "`nComandos sugeridos para correcao:" -ForegroundColor Yellow
    Write-Host "Install-Module Microsoft.Graph -Scope CurrentUser -Force" -ForegroundColor White
    Write-Host "Import-Module Microsoft.Graph.Authentication" -ForegroundColor White
    Write-Host "Import-Module Microsoft.Graph.DeviceManagement" -ForegroundColor White
}
Write-Host "===============================================" -ForegroundColor Cyan