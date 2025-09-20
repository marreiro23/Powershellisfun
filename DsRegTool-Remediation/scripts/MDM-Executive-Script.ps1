#Requires -Version 5.1
<#
.SYNOPSIS
    Script Executor para Validação e Remediação MDM
    
.DESCRIPTION
    Script principal que executa validação seguida de remediação opcional
    Gera relatórios consolidados para Power BI Dashboard
    
.AUTHOR
    Sinqia IT Team
    
.VERSION
    1.0
    
.DATE
    2025-09-19
#>

param(
    [ValidateSet("Validation", "Remediation", "Both")]
    [string]$Mode = "Both",
    [string]$OutputDirectory = "$env:TEMP\MDM_Reports",
    [switch]$WhatIf = $false,
    [switch]$GenerateDashboardData = $true
)

# Função para logging
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

# Verificar se os scripts existem no mesmo diretório
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$validationScript = Join-Path $scriptPath "MDM-Validation-Script.ps1"
$remediationScript = Join-Path $scriptPath "MDM-Remediation-Script.ps1"

if (-not (Test-Path $validationScript)) {
    Write-Error "Script de validação não encontrado: $validationScript"
    exit 1
}

if (-not (Test-Path $remediationScript)) {
    Write-Error "Script de remediação não encontrado: $remediationScript"
    exit 1
}

# Criar diretório de saída
if (-not (Test-Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportData = @{}

Write-Log "Iniciando execução no modo: $Mode"

# Executar Validação
if ($Mode -in @("Validation", "Both")) {
    Write-Log "Executando script de validação..."
    
    $validationOutputPath = Join-Path $OutputDirectory "Validation_Results_$timestamp.json"
    
    try {
        $validationResult = & $validationScript -OutputPath $validationOutputPath -Detailed
        $reportData["Validation"] = Get-Content $validationOutputPath | ConvertFrom-Json
        Write-Log "Validação concluída com sucesso"
    } catch {
        Write-Log "Erro na execução da validação: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

# Executar Remediação (se solicitado)
if ($Mode -in @("Remediation", "Both")) {
    $validationResultsPath = if ($Mode -eq "Both") { 
        Join-Path $OutputDirectory "Validation_Results_$timestamp.json"
    } else {
        # Procurar o arquivo de validação mais recente
        $latestValidation = Get-ChildItem $OutputDirectory -Filter "Validation_Results_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latestValidation) { $latestValidation.FullName } else { $null }
    }
    
    Write-Log "Executando script de remediação..."
    
    $remediationOutputPath = Join-Path $OutputDirectory "Remediation_Results_$timestamp.json"
    
    try {
        $remediationParams = @{
            OutputPath = $remediationOutputPath
            WhatIf = $WhatIf
        }
        
        if ($validationResultsPath -and (Test-Path $validationResultsPath)) {
            $remediationParams["ValidationResultsPath"] = $validationResultsPath
        }
        
        $remediationResult = & $remediationScript @remediationParams
        $reportData["Remediation"] = Get-Content $remediationOutputPath | ConvertFrom-Json
        Write-Log "Remediação concluída"
    } catch {
        Write-Log "Erro na execução da remediação: $($_.Exception.Message)" "ERROR"
    }
}

# Gerar dados consolidados para Dashboard Power BI
if ($GenerateDashboardData) {
    Write-Log "Gerando dados consolidados para Power BI Dashboard..."
    
    $dashboardData = [PSCustomObject]@{
        ExecutionInfo = [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            DeviceName = $env:COMPUTERNAME
            ExecutionMode = $Mode
            ScriptVersion = "1.0"
            WhatIfMode = $WhatIf
            OutputDirectory = $OutputDirectory
        }
        ValidationData = if ($reportData.ContainsKey("Validation")) { $reportData["Validation"] } else { $null }
        RemediationData = if ($reportData.ContainsKey("Remediation")) { $reportData["Remediation"] } else { $null }
    }
    
    # Adicionar métricas consolidadas
    if ($reportData.ContainsKey("Validation")) {
        $validationSummary = $reportData["Validation"].ValidationSummary
        
        $dashboardData | Add-Member -MemberType NoteProperty -Name "HealthMetrics" -Value ([PSCustomObject]@{
            OverallHealthScore = $validationSummary.OverallScore
            HealthStatus = $validationSummary.HealthStatus
            TotalIssues = $validationSummary.CriticalIssues + $validationSummary.ErrorIssues + $validationSummary.WarningIssues
            CriticalIssues = $validationSummary.CriticalIssues
            ErrorIssues = $validationSummary.ErrorIssues
            WarningIssues = $validationSummary.WarningIssues
            HealthyChecks = $validationSummary.OkChecks
        })
    }
    
    if ($reportData.ContainsKey("Remediation")) {
        $remediationSummary = $reportData["Remediation"].RemediationSummary
        
        $dashboardData | Add-Member -MemberType NoteProperty -Name "RemediationMetrics" -Value ([PSCustomObject]@{
            RemediationStatus = $remediationSummary.RemediationStatus
            SuccessRate = $remediationSummary.SuccessRate
            TotalActions = $remediationSummary.TotalActions
            SuccessfulActions = $remediationSummary.SuccessfulActions
            FailedActions = $remediationSummary.FailedActions
            RequiresReboot = $remediationSummary.RequiresReboot
        })
    }
    
    # Dados específicos para dashboards
    $dashboardData | Add-Member -MemberType NoteProperty -Name "PowerBIDashboardData" -Value ([PSCustomObject]@{
        # Tabela principal para cards de resumo
        SummaryCards = [PSCustomObject]@{
            DeviceName = $env:COMPUTERNAME
            LastExecution = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            OverallHealth = if ($reportData.ContainsKey("Validation")) { $reportData["Validation"].ValidationSummary.HealthStatus } else { "N/A" }
            HealthScore = if ($reportData.ContainsKey("Validation")) { $reportData["Validation"].ValidationSummary.OverallScore } else { 0 }
            RemediationStatus = if ($reportData.ContainsKey("Remediation")) { $reportData["Remediation"].RemediationSummary.RemediationStatus } else { "N/A" }
            CriticalIssues = if ($reportData.ContainsKey("Validation")) { $reportData["Validation"].ValidationSummary.CriticalIssues } else { 0 }
            RebootRequired = if ($reportData.ContainsKey("Remediation")) { $reportData["Remediation"].RemediationSummary.RequiresReboot } else { $false }
        }
        
        # Dados para gráficos de componentes
        ComponentHealth = if ($reportData.ContainsKey("Validation")) { 
            $reportData["Validation"].ComponentSummary | ForEach-Object {
                [PSCustomObject]@{
                    Component = $_.Component
                    HealthScore = $_.AverageScore
                    TotalChecks = $_.TotalChecks
                    CriticalCount = $_.CriticalCount
                    ErrorCount = $_.ErrorCount
                    WarningCount = $_.WarningCount
                    OkCount = $_.OkCount
                    Status = if ($_.CriticalCount -gt 0) { "Critical" }
                            elseif ($_.ErrorCount -gt 0) { "Error" }
                            elseif ($_.WarningCount -gt 0) { "Warning" }
                            else { "Healthy" }
                }
            }
        } else { @() }
        
        # Timeline de ações de remediação
        RemediationTimeline = if ($reportData.ContainsKey("Remediation")) {
            $reportData["Remediation"].DetailedActions | ForEach-Object {
                [PSCustomObject]@{
                    Timestamp = $_.Timestamp
                    Component = $_.Component
                    Action = $_.Action
                    Status = $_.Status
                    Message = $_.Message
                    Impact = $_.Impact
                    RequiresReboot = $_.RequiresReboot
                }
            }
        } else { @() }
        
        # Dados para alertas e recomendações
        ActiveAlerts = if ($reportData.ContainsKey("Validation")) {
            $reportData["Validation"].DetailedResults | Where-Object { $_.Status -in @("CRITICAL", "ERROR") } | ForEach-Object {
                [PSCustomObject]@{
                    Severity = $_.Status
                    Component = $_.Component
                    Check = $_.Check
                    Message = $_.Message
                    Recommendation = $_.Recommendation
                    Priority = $_.Priority
                }
            }
        } else { @() }
    })
    
    # Salvar dados consolidados
    $dashboardOutputPath = Join-Path $OutputDirectory "PowerBI_Dashboard_Data_$timestamp.json"
    $dashboardData | ConvertTo-Json -Depth 15 | Out-File -FilePath $dashboardOutputPath -Encoding UTF8
    
    Write-Log "Dados do dashboard salvos em: $dashboardOutputPath"
    
    # Criar arquivo CSV para importação fácil no Power BI
    $csvOutputPath = Join-Path $OutputDirectory "PowerBI_Summary_$timestamp.csv"
    
    $csvData = [PSCustomObject]@{
        DeviceName = $env:COMPUTERNAME
        ExecutionDate = (Get-Date).ToString("yyyy-MM-dd")
        ExecutionTime = (Get-Date).ToString("HH:mm:ss")
        OverallHealthScore = if ($reportData.ContainsKey("Validation")) { $reportData["Validation"].ValidationSummary.OverallScore } else { 0 }
        HealthStatus = if ($reportData.ContainsKey("Validation")) { $reportData["Validation"].ValidationSummary.HealthStatus } else { "N/A" }
        CriticalIssues = if ($reportData.ContainsKey("Validation")) { $reportData["Validation"].ValidationSummary.CriticalIssues } else { 0 }
        ErrorIssues = if ($reportData.ContainsKey("Validation")) { $reportData["Validation"].ValidationSummary.ErrorIssues } else { 0 }
        WarningIssues = if ($reportData.ContainsKey("Validation")) { $reportData["Validation"].ValidationSummary.WarningIssues } else { 0 }
        HealthyChecks = if ($reportData.ContainsKey("Validation")) { $reportData["Validation"].ValidationSummary.OkChecks } else { 0 }
        RemediationStatus = if ($reportData.ContainsKey("Remediation")) { $reportData["Remediation"].RemediationSummary.RemediationStatus } else { "N/A" }
        SuccessfulActions = if ($reportData.ContainsKey("Remediation")) { $reportData["Remediation"].RemediationSummary.SuccessfulActions } else { 0 }
        FailedActions = if ($reportData.ContainsKey("Remediation")) { $reportData["Remediation"].RemediationSummary.FailedActions } else { 0 }
        RebootRequired = if ($reportData.ContainsKey("Remediation")) { $reportData["Remediation"].RemediationSummary.RequiresReboot } else { $false }
        ExecutionMode = $Mode
        WhatIfMode = $WhatIf
    }
    
    $csvData | Export-Csv -Path $csvOutputPath -NoTypeInformation -Encoding UTF8
    Write-Log "Arquivo CSV para Power BI salvo em: $csvOutputPath"
}

# Exibir resumo final
Write-Host "`n" -ForegroundColor Green
Write-Host "=== EXECUÇÃO CONCLUÍDA ===" -ForegroundColor Cyan
Write-Host "Modo de Execução: $Mode" -ForegroundColor White
Write-Host "Diretório de Saída: $OutputDirectory" -ForegroundColor White

if ($reportData.ContainsKey("Validation")) {
    $healthStatus = $reportData["Validation"].ValidationSummary.HealthStatus
    $healthScore = $reportData["Validation"].ValidationSummary.OverallScore
    Write-Host "Status de Saúde: $healthStatus ($healthScore/100)" -ForegroundColor $(
        switch($healthStatus) {
            "EXCELLENT" { "Green" }
            "GOOD" { "Green" }
            "FAIR" { "Yellow" }
            "POOR" { "Red" }
            "CRITICAL" { "Red" }
            default { "White" }
        }
    )
}

if ($reportData.ContainsKey("Remediation")) {
    $remediationStatus = $reportData["Remediation"].RemediationSummary.RemediationStatus
    Write-Host "Status da Remediação: $remediationStatus" -ForegroundColor $(
        switch($remediationStatus) {
            "COMPLETED" { "Green" }
            "PARTIAL" { "Yellow" }
            "FAILED" { "Red" }
            "SIMULATED" { "Cyan" }
            default { "White" }
        }
    )
}

Write-Host "`n📊 Arquivos gerados para Power BI:" -ForegroundColor Cyan
Get-ChildItem $OutputDirectory -Filter "*$timestamp*" | ForEach-Object {
    Write-Host "  - $($_.Name)" -ForegroundColor Gray
}

Write-Host "`n✅ Execução finalizada com sucesso!" -ForegroundColor Green