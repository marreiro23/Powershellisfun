#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Script para executar DSRegTool.ps1 automaticamente com todas as opções

.DESCRIPTION
    Este script executa o DSRegTool.ps1 múltiplas vezes, simulando a entrada do usuário
    para cada uma das 7 opções disponíveis.

.EXAMPLE
    .\DSRegTool-AutoRun.ps1
    
.NOTES
    Deve ser executado como Administrador no mesmo diretório que o DSRegTool.ps1
#>

param(
    [Parameter(Mandatory = $false, HelpMessage = "Diretório de saída para relatórios")]
    [string]$OutputDir = ".\DSRegTool_AutoRun_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

# Criar diretório de saída
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Verificar se DSRegTool.ps1 existe
$DSRegToolPath = Join-Path $PSScriptRoot "DSRegTool.ps1"
if (!(Test-Path $DSRegToolPath)) {
    Write-Error "DSRegTool.ps1 não encontrado no mesmo diretório!"
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DSRegTool - Execução Automatizada" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Relatórios serão salvos em: $OutputDir" -ForegroundColor Yellow
Write-Host ""

# Definir as opções a serem executadas
$options = @(
    @{Number="1"; Name="Microsoft Entra Register"; File="01_EntraRegister.txt"},
    @{Number="2"; Name="Microsoft Entra Join Device"; File="02_EntraJoin.txt"},
    @{Number="3"; Name="Microsoft Entra Hybrid Join"; File="03_EntraHybridJoin.txt"},
    @{Number="4"; Name="Service Connection Point (SCP)"; File="04_VerifySCP.txt"},
    @{Number="5"; Name="Device Health Status"; File="05_DeviceHealth.txt"},
    @{Number="6"; Name="Primary Refresh Token (PRT)"; File="06_CheckPRT.txt"},
    @{Number="7"; Name="Collect System Logs"; File="07_LogsCollection.txt"}
)

foreach ($option in $options) {
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] Executando opção $($option.Number): $($option.Name)" -ForegroundColor Green
    
    $outputFile = Join-Path $OutputDir $option.File
    
    try {
        # Criar ProcessStartInfo para controle completo
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-ExecutionPolicy Bypass -File `"$DSRegToolPath`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        
        # Iniciar processo
        $process = [System.Diagnostics.Process]::Start($psi)
        
        # Enviar a opção selecionada para o processo
        $process.StandardInput.WriteLine($option.Number)
        $process.StandardInput.Close()
        
        # Capturar saída
        $output = $process.StandardOutput.ReadToEnd()
        $errors = $process.StandardError.ReadToEnd()
        
        # Aguardar conclusão (timeout de 5 minutos por opção)
        if (!$process.WaitForExit(300000)) {
            $process.Kill()
            Write-Warning "Timeout na execução da opção $($option.Number). Processo finalizado."
        } else {
            # Salvar saída no arquivo
            $output | Out-File $outputFile -Encoding UTF8
            if ($errors) {
                "`n--- ERRORS ---`n$errors" | Out-File $outputFile -Append -Encoding UTF8
            }
        }
        
        Write-Host "✓ Concluído: $($option.Name)" -ForegroundColor Green
        
    } catch {
        Write-Warning "Erro ao executar opção $($option.Number): $($_.Exception.Message)"
    }
    
    Start-Sleep -Seconds 2
    Write-Host ""
}

# Executar dsregcmd /status básico
Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] Executando dsregcmd /status..." -ForegroundColor Green
try {
    dsregcmd /status | Out-File (Join-Path $OutputDir "00_dsregcmd_status.txt") -Encoding UTF8
    Write-Host "✓ dsregcmd /status salvo" -ForegroundColor Green
} catch {
    Write-Warning "Erro ao executar dsregcmd /status: $($_.Exception.Message)"
}

# Gerar relatório resumo
$summaryFile = Join-Path $OutputDir "00_Summary_Report.txt"
@"
========================================
RELATÓRIO RESUMO - DSRegTool Auto Execution
========================================
Data/Hora: $(Get-Date)
Computador: $env:COMPUTERNAME
Usuário: $(whoami)
PowerShell: $($PSVersionTable.PSVersion)

Arquivos Gerados:
"@ | Out-File $summaryFile -Encoding UTF8

Get-ChildItem $OutputDir -Filter "*.txt" | Sort-Object Name | ForEach-Object {
    "- $($_.Name) ($('{0:N2}' -f ($_.Length/1KB)) KB)" | Out-File $summaryFile -Append -Encoding UTF8
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "EXECUÇÃO AUTOMATIZADA CONCLUÍDA!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Todos os relatórios foram salvos em:" -ForegroundColor Yellow
Write-Host $OutputDir -ForegroundColor White
Write-Host ""
Write-Host "Arquivos principais:" -ForegroundColor Yellow
Write-Host "- 00_Summary_Report.txt (resumo)" -ForegroundColor White
Write-Host "- 00_dsregcmd_status.txt (status básico)" -ForegroundColor White
Write-Host "- 01-07_*.txt (relatórios por opção)" -ForegroundColor White