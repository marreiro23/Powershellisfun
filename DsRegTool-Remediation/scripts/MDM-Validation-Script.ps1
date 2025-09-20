#Requires -Version 5.1
<#
.SYNOPSIS
    Script de Validação para Ambiente Híbrido Azure AD + Intune
    
.DESCRIPTION
    Valida configurações de Azure AD Join, MDM Intune e identifica vestígios de Google Workspace MDM
    Saída formatada para dashboard Power BI
    
.AUTHOR
    Sinqia IT Team
    
.VERSION
    1.0
    
.DATE
    2025-09-19
#>

param(
    [string]$OutputPath = "$env:TEMP\MDM_Validation_Results.json",
    [switch]$Detailed = $false
)

# Função para logging
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

# Função para criar objeto de resultado padronizado
function New-ValidationResult {
    param(
        [string]$Component,
        [string]$Check,
        [string]$Status, # OK, WARNING, CRITICAL, ERROR
        [string]$Message,
        [string]$Details = "",
        [string]$Recommendation = "",
        [int]$Score = 0 # 0-100
    )
    
    return [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        DeviceName = $env:COMPUTERNAME
        Component = $Component
        Check = $Check
        Status = $Status
        Message = $Message
        Details = $Details
        Recommendation = $Recommendation
        Score = $Score
        Priority = switch($Status) {
            "CRITICAL" { 1 }
            "ERROR" { 2 }
            "WARNING" { 3 }
            "OK" { 4 }
            default { 5 }
        }
    }
}

# Inicializar array de resultados
$validationResults = @()

Write-Log "Iniciando validação do ambiente MDM/Azure AD..."

#region Azure AD Join Status
Write-Log "Verificando status do Azure AD Join..."
try {
    $dsregStatus = dsregcmd /status
    $azureAdJoined = ($dsregStatus | Select-String "AzureAdJoined\s*:\s*YES") -ne $null
    $domainJoined = ($dsregStatus | Select-String "DomainJoined\s*:\s*YES") -ne $null
    $deviceAuthStatus = ($dsregStatus | Select-String "DeviceAuthStatus\s*:\s*SUCCESS") -ne $null
    
    if ($azureAdJoined -and $deviceAuthStatus) {
        $validationResults += New-ValidationResult -Component "AzureAD" -Check "DeviceJoin" -Status "OK" -Message "Dispositivo conectado ao Azure AD com sucesso" -Score 100
    } elseif ($azureAdJoined) {
        $validationResults += New-ValidationResult -Component "AzureAD" -Check "DeviceJoin" -Status "WARNING" -Message "Dispositivo conectado mas com problemas de autenticação" -Recommendation "Verificar certificados e conectividade" -Score 70
    } else {
        $validationResults += New-ValidationResult -Component "AzureAD" -Check "DeviceJoin" -Status "CRITICAL" -Message "Dispositivo não está conectado ao Azure AD" -Recommendation "Executar dsregcmd /join" -Score 0
    }
    
    # Verificar configuração híbrida
    if ($azureAdJoined -and $domainJoined) {
        $validationResults += New-ValidationResult -Component "AzureAD" -Check "HybridConfig" -Status "OK" -Message "Configuração híbrida detectada" -Score 100
    }
    
} catch {
    $validationResults += New-ValidationResult -Component "AzureAD" -Check "DeviceJoin" -Status "ERROR" -Message "Erro ao verificar status Azure AD: $($_.Exception.Message)" -Score 0
}
#endregion

#region PRT (Primary Refresh Token) Status
Write-Log "Verificando status do Primary Refresh Token (PRT)..."
try {
    # Executar como usuário atual (não admin) para verificar PRT
    $prtStatus = dsregcmd /status
    $azurePrt = ($prtStatus | Select-String "AzureAdPrt\s*:\s*YES") -ne $null
    $prtError = ($prtStatus | Select-String "0x80070520") -ne $null
    
    if ($azurePrt) {
        $validationResults += New-ValidationResult -Component "Authentication" -Check "PRT" -Status "OK" -Message "Primary Refresh Token ativo" -Score 100
    } elseif ($prtError) {
        $validationResults += New-ValidationResult -Component "Authentication" -Check "PRT" -Status "CRITICAL" -Message "Falha crítica no PRT - Erro 0x80070520" -Recommendation "Verificar mapeamento UPN e sincronização Azure AD Connect" -Score 0
    } else {
        $validationResults += New-ValidationResult -Component "Authentication" -Check "PRT" -Status "WARNING" -Message "PRT não disponível" -Recommendation "Verificar autenticação do usuário" -Score 30
    }
} catch {
    $validationResults += New-ValidationResult -Component "Authentication" -Check "PRT" -Status "ERROR" -Message "Erro ao verificar PRT: $($_.Exception.Message)" -Score 0
}
#endregion

#region MDM Enrollment Status
Write-Log "Verificando status do MDM (Intune)..."
try {
    $mdmEnrollments = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Enrollments" -ErrorAction SilentlyContinue
    $intuneEnrollment = $false
    $googleWorkspaceResidue = $false
    
    foreach ($enrollment in $mdmEnrollments) {
        $properties = Get-ItemProperty $enrollment.PSPath -ErrorAction SilentlyContinue
        if ($properties.ProviderID -like "*microsoft*" -or $properties.ProviderID -like "*intune*") {
            $intuneEnrollment = $true
        }
        if ($properties.ProviderID -like "*google*" -or $properties.ProviderID -like "*workspace*") {
            $googleWorkspaceResidue = $true
        }
    }
    
    if ($intuneEnrollment -and -not $googleWorkspaceResidue) {
        $validationResults += New-ValidationResult -Component "MDM" -Check "IntuneEnrollment" -Status "OK" -Message "Dispositivo registrado no Intune" -Score 100
    } elseif ($intuneEnrollment -and $googleWorkspaceResidue) {
        $validationResults += New-ValidationResult -Component "MDM" -Check "IntuneEnrollment" -Status "WARNING" -Message "Intune ativo mas vestígios Google Workspace detectados" -Recommendation "Limpar registros MDM residuais" -Score 60
    } elseif ($googleWorkspaceResidue) {
        $validationResults += New-ValidationResult -Component "MDM" -Check "IntuneEnrollment" -Status "CRITICAL" -Message "Vestígios Google Workspace sem Intune ativo" -Recommendation "Limpeza completa e re-enrollment" -Score 20
    } else {
        $validationResults += New-ValidationResult -Component "MDM" -Check "IntuneEnrollment" -Status "ERROR" -Message "Nenhum enrollment MDM detectado" -Recommendation "Configurar enrollment Intune" -Score 0
    }
    
} catch {
    $validationResults += New-ValidationResult -Component "MDM" -Check "IntuneEnrollment" -Status "ERROR" -Message "Erro ao verificar enrollment MDM: $($_.Exception.Message)" -Score 0
}
#endregion

#region Google Workspace Residue Check
Write-Log "Verificando vestígios do Google Workspace..."
try {
    $chromeServices = Get-Service | Where-Object { $_.DisplayName -like "*Google*" -or $_.DisplayName -like "*Chrome*" }
    $chromeProcesses = Get-Process | Where-Object { $_.ProcessName -eq "chrome" } -ErrorAction SilentlyContinue
    
    # Verificar políticas Chrome
    $chromePolicies = Get-ChildItem "HKLM:\SOFTWARE\Policies\Google" -ErrorAction SilentlyContinue
    
    $residueScore = 100
    $residueDetails = @()
    
    if ($chromeServices.Count -gt 0) {
        $residueScore -= 20
        $residueDetails += "Serviços Chrome ativos: $($chromeServices.Count)"
    }
    
    if ($chromeProcesses.Count -gt 0) {
        $residueScore -= 10
        $residueDetails += "Processos Chrome em execução: $($chromeProcesses.Count)"
    }
    
    if ($chromePolicies.Count -gt 0) {
        $residueScore -= 30
        $residueDetails += "Políticas Chrome detectadas: $($chromePolicies.Count)"
    }
    
    $status = if ($residueScore -eq 100) { "OK" } elseif ($residueScore -gt 60) { "WARNING" } else { "CRITICAL" }
    $message = if ($residueDetails.Count -eq 0) { "Nenhum vestígio Google Workspace detectado" } else { "Vestígios Google Workspace encontrados" }
    
    $validationResults += New-ValidationResult -Component "Legacy" -Check "GoogleWorkspaceResidue" -Status $status -Message $message -Details ($residueDetails -join "; ") -Recommendation "Avaliar necessidade de limpeza" -Score $residueScore
    
} catch {
    $validationResults += New-ValidationResult -Component "Legacy" -Check "GoogleWorkspaceResidue" -Status "ERROR" -Message "Erro ao verificar vestígios: $($_.Exception.Message)" -Score 0
}
#endregion

#region Group Policy MDM Configuration
Write-Log "Verificando configurações MDM via Group Policy..."
try {
    $gpResult = gpresult /r /scope:computer 2>$null
    $mdmPolicyActive = ($gpResult | Select-String "MDM.*ativad") -ne $null
    
    # Verificar registry para configuração MDM automática
    $mdmAutoEnroll = $null
    try {
        $mdmAutoEnroll = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM" -Name "AutoEnrollMDM" -ErrorAction SilentlyContinue
    } catch { }
    
    if ($mdmAutoEnroll -and $mdmAutoEnroll.AutoEnrollMDM -eq 1) {
        $validationResults += New-ValidationResult -Component "GroupPolicy" -Check "MDMAutoEnroll" -Status "OK" -Message "Política MDM automática ativa" -Score 100
    } else {
        $validationResults += New-ValidationResult -Component "GroupPolicy" -Check "MDMAutoEnroll" -Status "WARNING" -Message "Política MDM automática não configurada" -Recommendation "Verificar GPO 'ENDUSER INTUNE v2'" -Score 50
    }
    
} catch {
    $validationResults += New-ValidationResult -Component "GroupPolicy" -Check "MDMAutoEnroll" -Status "ERROR" -Message "Erro ao verificar Group Policy: $($_.Exception.Message)" -Score 0
}
#endregion

#region Certificate Validation
Write-Log "Verificando certificados do dispositivo..."
try {
    $dsregStatus = dsregcmd /status
    $certThumbprint = ($dsregStatus | Select-String "Thumbprint\s*:\s*(.+)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() })
    $certValidity = ($dsregStatus | Select-String "DeviceCertificateValidity\s*:\s*\[(.*)\]" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() })
    
    if ($certThumbprint -and $certValidity) {
        # Verificar se certificado está próximo do vencimento
        $certEndDate = [DateTime]::ParseExact($certValidity.Split(' -- ')[1], "yyyy-MM-dd HH:mm:ss.fff UTC", $null)
        $daysToExpiry = ($certEndDate - (Get-Date)).Days
        
        if ($daysToExpiry -gt 365) {
            $validationResults += New-ValidationResult -Component "Security" -Check "DeviceCertificate" -Status "OK" -Message "Certificado válido por $daysToExpiry dias" -Score 100
        } elseif ($daysToExpiry -gt 30) {
            $validationResults += New-ValidationResult -Component "Security" -Check "DeviceCertificate" -Status "WARNING" -Message "Certificado expira em $daysToExpiry dias" -Recommendation "Monitorar renovação automática" -Score 80
        } else {
            $validationResults += New-ValidationResult -Component "Security" -Check "DeviceCertificate" -Status "CRITICAL" -Message "Certificado expira em $daysToExpiry dias" -Recommendation "Renovar certificado urgentemente" -Score 30
        }
    } else {
        $validationResults += New-ValidationResult -Component "Security" -Check "DeviceCertificate" -Status "ERROR" -Message "Certificado do dispositivo não encontrado" -Recommendation "Verificar enrollment do dispositivo" -Score 0
    }
    
} catch {
    $validationResults += New-ValidationResult -Component "Security" -Check "DeviceCertificate" -Status "ERROR" -Message "Erro ao verificar certificado: $($_.Exception.Message)" -Score 0
}
#endregion

#region Connectivity Tests
Write-Log "Testando conectividade com endpoints Azure/Intune..."
try {
    $endpoints = @(
        "login.microsoftonline.com",
        "device.login.microsoftonline.com", 
        "enterpriseregistration.windows.net",
        "enrollment.manage.microsoft.com"
    )
    
    $connectivityScore = 0
    $failedEndpoints = @()
    
    foreach ($endpoint in $endpoints) {
        try {
            $result = Test-NetConnection $endpoint -Port 443 -WarningAction SilentlyContinue
            if ($result.TcpTestSucceeded) {
                $connectivityScore += 25
            } else {
                $failedEndpoints += $endpoint
            }
        } catch {
            $failedEndpoints += $endpoint
        }
    }
    
    if ($connectivityScore -eq 100) {
        $validationResults += New-ValidationResult -Component "Network" -Check "EndpointConnectivity" -Status "OK" -Message "Conectividade com todos endpoints OK" -Score 100
    } elseif ($connectivityScore -gt 50) {
        $validationResults += New-ValidationResult -Component "Network" -Check "EndpointConnectivity" -Status "WARNING" -Message "Conectividade parcial" -Details "Falhas: $($failedEndpoints -join ', ')" -Score $connectivityScore
    } else {
        $validationResults += New-ValidationResult -Component "Network" -Check "EndpointConnectivity" -Status "CRITICAL" -Message "Falhas críticas de conectividade" -Details "Falhas: $($failedEndpoints -join ', ')" -Recommendation "Verificar firewall e proxy" -Score $connectivityScore
    }
    
} catch {
    $validationResults += New-ValidationResult -Component "Network" -Check "EndpointConnectivity" -Status "ERROR" -Message "Erro no teste de conectividade: $($_.Exception.Message)" -Score 0
}
#endregion

#region Overall Health Score Calculation
Write-Log "Calculando score geral de saúde..."
$totalScore = ($validationResults | Where-Object { $_.Score -ne $null } | Measure-Object -Property Score -Average).Average
$criticalIssues = ($validationResults | Where-Object { $_.Status -eq "CRITICAL" }).Count
$errorIssues = ($validationResults | Where-Object { $_.Status -eq "ERROR" }).Count
$warningIssues = ($validationResults | Where-Object { $_.Status -eq "WARNING" }).Count
$okIssues = ($validationResults | Where-Object { $_.Status -eq "OK" }).Count

$overallHealth = [PSCustomObject]@{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    DeviceName = $env:COMPUTERNAME
    OverallScore = [math]::Round($totalScore, 2)
    TotalChecks = $validationResults.Count
    CriticalIssues = $criticalIssues
    ErrorIssues = $errorIssues
    WarningIssues = $warningIssues
    OkChecks = $okIssues
    HealthStatus = if ($totalScore -ge 90) { "EXCELLENT" } 
                  elseif ($totalScore -ge 70) { "GOOD" }
                  elseif ($totalScore -ge 50) { "FAIR" }
                  elseif ($totalScore -ge 30) { "POOR" }
                  else { "CRITICAL" }
    RecommendedActions = if ($criticalIssues -gt 0) { "Ação imediata necessária" }
                        elseif ($errorIssues -gt 0) { "Correções urgentes requeridas" }
                        elseif ($warningIssues -gt 0) { "Monitoramento e otimização" }
                        else { "Sistema em bom estado" }
}
#endregion

# Preparar saída para Power BI
$powerBIData = [PSCustomObject]@{
    ValidationSummary = $overallHealth
    DetailedResults = $validationResults
    ComponentSummary = $validationResults | Group-Object Component | ForEach-Object {
        [PSCustomObject]@{
            Component = $_.Name
            TotalChecks = $_.Count
            AverageScore = [math]::Round(($_.Group | Measure-Object Score -Average).Average, 2)
            CriticalCount = ($_.Group | Where-Object { $_.Status -eq "CRITICAL" }).Count
            ErrorCount = ($_.Group | Where-Object { $_.Status -eq "ERROR" }).Count
            WarningCount = ($_.Group | Where-Object { $_.Status -eq "WARNING" }).Count
            OkCount = ($_.Group | Where-Object { $_.Status -eq "OK" }).Count
        }
    }
    SystemInfo = [PSCustomObject]@{
        DeviceName = $env:COMPUTERNAME
        OSVersion = (Get-WmiObject Win32_OperatingSystem).Version
        Domain = $env:USERDOMAIN
        LastBoot = (Get-WmiObject Win32_OperatingSystem).ConvertToDateTime((Get-WmiObject Win32_OperatingSystem).LastBootUpTime)
        ExecutionTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ScriptVersion = "1.0"
    }
}

# Salvar resultados
Write-Log "Salvando resultados em $OutputPath..."
$powerBIData | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8

# Exibir resumo
Write-Host "`n" -ForegroundColor Green
Write-Host "=== RESUMO DA VALIDAÇÃO ===" -ForegroundColor Cyan
Write-Host "Device: $($overallHealth.DeviceName)" -ForegroundColor White
Write-Host "Score Geral: $($overallHealth.OverallScore)/100 ($($overallHealth.HealthStatus))" -ForegroundColor $(
    switch($overallHealth.HealthStatus) {
        "EXCELLENT" { "Green" }
        "GOOD" { "Green" }
        "FAIR" { "Yellow" }
        "POOR" { "Red" }
        "CRITICAL" { "Red" }
    }
)
Write-Host "Problemas Críticos: $($overallHealth.CriticalIssues)" -ForegroundColor Red
Write-Host "Erros: $($overallHealth.ErrorIssues)" -ForegroundColor Red
Write-Host "Avisos: $($overallHealth.WarningIssues)" -ForegroundColor Yellow
Write-Host "OK: $($overallHealth.OkChecks)" -ForegroundColor Green
Write-Host "`nResultados salvos em: $OutputPath" -ForegroundColor Cyan

if ($Detailed) {
    Write-Host "`n=== DETALHES ===" -ForegroundColor Cyan
    $validationResults | Format-Table Component, Check, Status, Message -AutoSize
}

Write-Log "Validação concluída com sucesso!"
return $powerBIData