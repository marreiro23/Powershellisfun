#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Script para executar todas as opções do DSRegTool.ps1 em lote

.DESCRIPTION
    Este script executa automaticamente todas as funcionalidades do DSRegTool:
    1. Troubleshoot Microsoft Entra Register
    2. Troubleshoot Microsoft Entra join device  
    3. Troubleshoot Microsoft Entra hybrid join
    4. Verify Service Connection Point (SCP)
    5. Verify the health status of the device
    6. Verify Primary Refresh Token (PRT)
    7. Collect the logs

.EXAMPLE
    .\DSRegTool-BatchExecution.ps1
    
.NOTES
    Deve ser executado como Administrador
#>

param(
    [Parameter(Mandatory = $false, HelpMessage = "Diretório de saída para relatórios")]
    [string]$OutputDir = ".\DSRegTool_Reports\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

# Criar diretório de saída
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DSRegTool - Execução em Lote Iniciada" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Relatórios serão salvos em: $OutputDir" -ForegroundColor Yellow
Write-Host ""

# Carregear o script DSRegTool.ps1
$DSRegToolPath = Join-Path $PSScriptRoot "DSRegTool.ps1"
if (!(Test-Path $DSRegToolPath)) {
    Write-Error "DSRegTool.ps1 não encontrado no mesmo diretório!"
    exit 1
}

# Importar todas as funções do DSRegTool
. $DSRegToolPath

# Função para capturar saída e salvar em arquivo
function Invoke-DSRegFunction {
    param(
        [string]$FunctionName,
        [string]$Description,
        [string]$OutputFile
    )
    
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] Executando: $Description" -ForegroundColor Green
    
    try {
        # Redirecionar saída para arquivo
        Start-Transcript -Path $OutputFile -Append | Out-Null
        
        # Executar função baseada no nome
        switch ($FunctionName) {
            "WPJTS" { 
                DSRegToolStart
                WPJTS 
            }
            "AADJ" { 
                DSRegToolStart
                AADJ 
            }
            "DJ++TS" { 
                DSRegToolStart
                & "DJ++TS"
            }
            "VerifySCP" { 
                DSRegToolStart
                VerifySCP 
            }
            "DJ++" { 
                DSRegToolStart
                & "DJ++"
            }
            "CheckPRT" { 
                DSRegToolStart
                CheckPRT 
            }
            "LogsCollection" { 
                DSRegToolStart
                LogsCollection 
            }
        }
        
        Stop-Transcript | Out-Null
        Write-Host "✓ Concluído: $Description" -ForegroundColor Green
        
    } catch {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        Write-Warning "Erro ao executar $Description`: $($_.Exception.Message)"
    }
    
    Write-Host ""
}

# Executar todas as opções
$functions = @(
    @{Name="WPJTS"; Description="1. Troubleshoot Microsoft Entra Register"; File="$OutputDir\01_EntraRegister.log"},
    @{Name="AADJ"; Description="2. Troubleshoot Microsoft Entra Join Device"; File="$OutputDir\02_EntraJoin.log"},
    @{Name="DJ++TS"; Description="3. Troubleshoot Microsoft Entra Hybrid Join"; File="$OutputDir\03_EntraHybridJoin.log"},
    @{Name="VerifySCP"; Description="4. Verify Service Connection Point (SCP)"; File="$OutputDir\04_VerifySCP.log"},
    @{Name="DJ++"; Description="5. Verify Device Health Status"; File="$OutputDir\05_DeviceHealth.log"},
    @{Name="CheckPRT"; Description="6. Verify Primary Refresh Token (PRT)"; File="$OutputDir\06_CheckPRT.log"},
    @{Name="LogsCollection"; Description="7. Collect System Logs"; File="$OutputDir\07_LogsCollection.log"}
)

foreach ($func in $functions) {
    Invoke-DSRegFunction -FunctionName $func.Name -Description $func.Description -OutputFile $func.File
}

# Gerar relatório resumo
$summaryFile = "$OutputDir\00_Summary_Report.txt"
@"
========================================
RELATÓRIO RESUMO - DSRegTool Batch Execution
========================================
Data/Hora: $(Get-Date)
Computador: $env:COMPUTERNAME
Usuário: $(whoami)

Arquivos Gerados:
"@ | Out-File $summaryFile

Get-ChildItem $OutputDir -Filter "*.log" | ForEach-Object {
    "- $($_.Name) ($('{0:N2}' -f ($_.Length/1KB)) KB)" | Out-File $summaryFile -Append
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "EXECUÇÃO EM LOTE CONCLUÍDA!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Todos os relatórios foram salvos em:" -ForegroundColor Yellow
Write-Host $OutputDir -ForegroundColor White
Write-Host ""
Write-Host "Verifique o arquivo 00_Summary_Report.txt para um resumo completo." -ForegroundColor Yellow