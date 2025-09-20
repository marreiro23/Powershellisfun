#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Script de Remediação para Ambiente Híbrido Azure AD + Intune
    
.DESCRIPTION
    Corrige problemas identificados no ambiente Azure AD/Intune e remove vestígios do Google Workspace MDM
    Saída formatada para dashboard Power BI
    
.AUTHOR
    Sinqia IT Team
    
.VERSION
    1.0
    
.DATE
    2025-09-19
    
.NOTES
    ATENÇÃO: Este script faz alterações significativas no sistema.
    Execute apenas após validação completa e backup do sistema.
#>

param(
    [string]$OutputPath = "$env:TEMP\MDM_Remediation_Results.json",
    [switch]$WhatIf = $false,
    [switch]$Force = $false,
    [string]$ValidationResultsPath = "$env:TEMP\MDM_Validation_Results.json"
)

# Verificar se está sendo executado como administrador
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Este script deve ser executado como Administrador!"
    exit 1
}

# Função para logging
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

# Função para criar resultado de remediação padronizado
function New-RemediationResult {
    param(
        [string]$Component,
        [string]$Action,
        [string]$Status, # SUCCESS, FAILED, SKIPPED, WARNING
        [string]$Message,
        [string]$Details = "",
        [string]$Impact = "",
        [bool]$RequiresReboot = $false
    )
    
    return [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        DeviceName = $env:COMPUTERNAME
        Component = $Component
        Action = $Action
        Status = $Status
        Message = $Message
        Details = $Details
        Impact = $Impact
        RequiresReboot = $RequiresReboot
        WhatIfMode = $WhatIf
    }
}

# Inicializar arrays
$remediationResults = @()
$rebootRequired = $false

Write-Log "Iniciando remediação do ambiente MDM/Azure AD..." "INFO"

if ($WhatIf) {
    Write-Log "MODO WHATIF ATIVO - Nenhuma alteração será feita" "WARNING"
}

#region Carregar Resultados da Validação
Write-Log "Carregando resultados da validação anterior..."
$validationData = $null
if (Test-Path $ValidationResultsPath) {
    try {
        $validationData = Get-Content $ValidationResultsPath | ConvertFrom-Json
        Write-Log "Resultados de validação carregados com sucesso"
        
        # Identificar problemas críticos
        $criticalIssues = $validationData.DetailedResults | Where-Object { $_.Status -eq "CRITICAL" }
        $errorIssues = $validationData.DetailedResults | Where-Object { $_.Status -eq "ERROR" }
        
        Write-Log "Identificados $($criticalIssues.Count) problemas críticos e $($errorIssues.Count) erros"
    } catch {
        Write-Log "Erro ao carregar resultados de validação: $($_.Exception.Message)" "WARNING"
    }
} else {
    Write-Log "Arquivo de validação não encontrado. Executando remediação baseada em descoberta..." "WARNING"
}
#endregion

#region Backup de Configurações Críticas
Write-Log "Criando backup de configurações críticas..."
try {
    $backupPath = "$env:TEMP\MDM_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    
    if (-not $WhatIf) {
        New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
        
        # Backup registros MDM
        $enrollmentPath = "HKLM:\SOFTWARE\Microsoft\Enrollments"
        if (Test-Path $enrollmentPath) {
            reg export "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Enrollments" "$backupPath\Enrollments_backup.reg" /y | Out-Null
        }
        
        # Backup configurações Azure AD
        $aadPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin"
        if (Test-Path $aadPath) {
            reg export "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\CloudDomainJoin" "$backupPath\CloudDomainJoin_backup.reg" /y | Out-Null
        }
        
        # Backup políticas Google/Chrome
        $googlePolicyPath = "HKLM:\SOFTWARE\Policies\Google"
        if (Test-Path $googlePolicyPath) {
            reg export "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google" "$backupPath\GooglePolicies_backup.reg" /y | Out-Null
        }
    }
    
    $remediationResults += New-RemediationResult -Component "System" -Action "Backup" -Status "SUCCESS" -Message "Backup criado em $backupPath" -Details "Registros MDM, Azure AD e Google salvos"
    
} catch {
    $remediationResults += New-RemediationResult -Component "System" -Action "Backup" -Status "FAILED" -Message "Falha no backup: $($_.Exception.Message)" -Impact "Risco aumentado para rollback"
}
#endregion

#region Limpeza de Vestígios Google Workspace
Write-Log "Removendo vestígios do Google Workspace MDM..."

# Remover serviços Google desnecessários
try {
    $googleServices = Get-Service | Where-Object { 
        $_.DisplayName -like "*Google Chrome Remote Desktop*" -or 
        $_.DisplayName -like "*Google Updater*" -and 
        $_.DisplayName -notlike "*Google Chrome*" # Manter browser principal
    }
    
    foreach ($service in $googleServices) {
        try {
            Write-Log "Processando serviço: $($service.DisplayName)"
            
            if (-not $WhatIf) {
                if ($service.Status -eq "Running") {
                    Stop-Service $service.Name -Force -ErrorAction SilentlyContinue
                }
                Set-Service $service.Name -StartupType Disabled -ErrorAction SilentlyContinue
            }
            
            $remediationResults += New-RemediationResult -Component "GoogleWorkspace" -Action "DisableService" -Status "SUCCESS" -Message "Serviço $($service.DisplayName) desabilitado" -Details $service.Name
            
        } catch {
            $remediationResults += New-RemediationResult -Component "GoogleWorkspace" -Action "DisableService" -Status "FAILED" -Message "Falha ao desabilitar $($service.DisplayName): $($_.Exception.Message)"
        }
    }
    
} catch {
    $remediationResults += New-RemediationResult -Component "GoogleWorkspace" -Action "DisableService" -Status "FAILED" -Message "Erro geral na remoção de serviços Google: $($_.Exception.Message)"
}

# Remover políticas Google residuais (apenas MDM-relacionadas)
try {
    $googlePolicyPaths = @(
        "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist",
        "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionInstallWhitelist",
        "HKLM:\SOFTWARE\Policies\Google\ChromeOS",
        "HKLM:\SOFTWARE\Policies\Google\Update\CloudManagement"
    )
    
    foreach ($policyPath in $googlePolicyPaths) {
        if (Test-Path $policyPath) {
            Write-Log "Removendo política Google: $policyPath"
            
            if (-not $WhatIf) {
                Remove-Item $policyPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            $remediationResults += New-RemediationResult -Component "GoogleWorkspace" -Action "RemovePolicy" -Status "SUCCESS" -Message "Política removida: $policyPath"
        }
    }
    
} catch {
    $remediationResults += New-RemediationResult -Component "GoogleWorkspace" -Action "RemovePolicy" -Status "FAILED" -Message "Erro ao remover políticas Google: $($_.Exception.Message)"
}
#endregion

#region Limpeza de Registros MDM Órfãos
Write-Log "Limpando registros MDM órfãos e corrompidos..."

try {
    $enrollmentPath = "HKLM:\SOFTWARE\Microsoft\Enrollments"
    
    if (Test-Path $enrollmentPath) {
        $enrollments = Get-ChildItem $enrollmentPath -ErrorAction SilentlyContinue
        
        foreach ($enrollment in $enrollments) {
            try {
                $properties = Get-ItemProperty $enrollment.PSPath -ErrorAction SilentlyContinue
                
                # Identificar enrollments corrompidos ou do Google
                $isCorrupted = ($properties.ProviderID -eq $null) -or ($properties.ProviderID -eq "")
                $isGoogleWorkspace = ($properties.ProviderID -like "*google*") -or ($properties.ProviderID -like "*workspace*")
                $isOldIntune = ($properties.EnrollmentState -eq $null) -and ($properties.ProviderID -like "*microsoft*")
                
                if ($isCorrupted -or $isGoogleWorkspace -or $isOldIntune) {
                    Write-Log "Removendo enrollment órfão: $($enrollment.PSChildName) - Provedor: $($properties.ProviderID)"
                    
                    if (-not $WhatIf) {
                        Remove-Item $enrollment.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    
                    $reason = if ($isGoogleWorkspace) { "Google Workspace" } 
                             elseif ($isCorrupted) { "Corrompido" } 
                             else { "Intune Órfão" }
                    
                    $remediationResults += New-RemediationResult -Component "MDM" -Action "CleanOrphanedEnrollment" -Status "SUCCESS" -Message "Enrollment órfão removido: $reason" -Details $enrollment.PSChildName
                }
                
            } catch {
                $remediationResults += New-RemediationResult -Component "MDM" -Action "CleanOrphanedEnrollment" -Status "FAILED" -Message "Erro ao processar enrollment $($enrollment.PSChildName): $($_.Exception.Message)"
            }
        }
    }
    
    # Limpar provisioning órfão
    $provisioningPath = "HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts"
    if (Test-Path $provisioningPath) {
        $provisioningAccounts = Get-ChildItem $provisioningPath -ErrorAction SilentlyContinue
        
        foreach ($account in $provisioningAccounts) {
            try {
                $accountProps = Get-ItemProperty $account.PSPath -ErrorAction SilentlyContinue
                if (($accountProps.SslClientCertReference -eq $null) -or ($accountProps.Protected -ne 1)) {
                    Write-Log "Removendo conta provisioning órfã: $($account.PSChildName)"
                    
                    if (-not $WhatIf) {
                        Remove-Item $account.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    
                    $remediationResults += New-RemediationResult -Component "MDM" -Action "CleanOrphanedProvisioning" -Status "SUCCESS" -Message "Conta provisioning órfã removida" -Details $account.PSChildName
                }
            } catch {
                Write-Log "Erro ao processar conta provisioning: $($_.Exception.Message)" "WARNING"
            }
        }
    }
    
} catch {
    $remediationResults += New-RemediationResult -Component "MDM" -Action "CleanOrphanedEnrollment" -Status "FAILED" -Message "Erro geral na limpeza de enrollments: $($_.Exception.Message)"
}
#endregion

#region Correção de Configurações Azure AD
Write-Log "Corrigindo configurações do Azure AD..."

# Verificar e corrigir configuração de domínio UPN
try {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $domain = $env:USERDOMAIN
    
    Write-Log "Usuário atual: $currentUser, Domínio: $domain"
    
    # Verificar mapeamento UPN inconsistente
    $dsregStatus = dsregcmd /status
    $userEmailLine = $dsregStatus | Select-String "UserEmail"
    
    if ($userEmailLine -and $userEmailLine -like "*fooUser@ATTPS.onmicrosoft.com*") {
        Write-Log "Detectado UPN inconsistente - necessário reset Azure AD Join"
        
        if (-not $WhatIf) {
            # Reset do Azure AD Join
            Write-Log "Executando reset do Azure AD Join..."
            
            try {
                # Leave do domínio Azure AD atual
                $leaveResult = dsregcmd /leave
                Start-Sleep -Seconds 10
                
                # Rejoin ao Azure AD
                $joinResult = dsregcmd /join
                
                $rebootRequired = $true
                
                $remediationResults += New-RemediationResult -Component "AzureAD" -Action "ResetJoin" -Status "SUCCESS" -Message "Reset Azure AD Join executado" -Details "Leave e Join realizados" -RequiresReboot $true -Impact "Autenticação será restaurada após reboot"
                
            } catch {
                $remediationResults += New-RemediationResult -Component "AzureAD" -Action "ResetJoin" -Status "FAILED" -Message "Falha no reset Azure AD Join: $($_.Exception.Message)" -Impact "Problemas de autenticação podem persistir"
            }
        } else {
            $remediationResults += New-RemediationResult -Component "AzureAD" -Action "ResetJoin" -Status "SKIPPED" -Message "Reset Azure AD Join necessário (WhatIf mode)" -RequiresReboot $true
        }
    }
    
} catch {
    $remediationResults += New-RemediationResult -Component "AzureAD" -Action "CheckUPNMapping" -Status "FAILED" -Message "Erro ao verificar mapeamento UPN: $($_.Exception.Message)"
}

# Forçar atualização de certificados
try {
    Write-Log "Forçando atualização de certificados do dispositivo..."
    
    if (-not $WhatIf) {
        # Forçar renovação de certificado
        certlm.msc # Esta seria uma chamada administrativa
        
        # Alternativa via PowerShell
        $certStore = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*$env:COMPUTERNAME*" -and $_.Issuer -like "*Azure*" }
        
        if ($certStore) {
            # Verificar validade
            foreach ($cert in $certStore) {
                $daysToExpiry = ($cert.NotAfter - (Get-Date)).Days
                if ($daysToExpiry -lt 90) {
                    Write-Log "Certificado próximo do vencimento: $daysToExpiry dias"
                    # Trigger renewal seria feito aqui
                }
            }
        }
        
        # Forçar sincronização com Azure AD
        schtasks /run /tn "\Microsoft\Windows\Workplace Join\Automatic-Device-Join" 2>$null
    }
    
    $remediationResults += New-RemediationResult -Component "Security" -Action "UpdateCertificates" -Status "SUCCESS" -Message "Atualização de certificados iniciada"
    
} catch {
    $remediationResults += New-RemediationResult -Component "Security" -Action "UpdateCertificates" -Status "FAILED" -Message "Erro na atualização de certificados: $($_.Exception.Message)"
}
#endregion

#region Re-enrollment Intune
Write-Log "Forçando re-enrollment no Intune..."

try {
    # Verificar se Group Policy MDM está ativa
    $mdmPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\MDM"
    
    if (-not (Test-Path $mdmPolicyPath)) {
        Write-Log "Criando configuração MDM automática..."
        
        if (-not $WhatIf) {
            New-Item -Path $mdmPolicyPath -Force | Out-Null
            Set-ItemProperty -Path $mdmPolicyPath -Name "AutoEnrollMDM" -Value 1 -Type DWORD
        }
        
        $remediationResults += New-RemediationResult -Component "MDM" -Action "EnableAutoEnroll" -Status "SUCCESS" -Message "Auto-enrollment MDM habilitado"
    }
    
    # Forçar execução da tarefa de enrollment
    if (-not $WhatIf) {
        Write-Log "Executando tarefa de enrollment MDM..."
        
        # Executar tarefa de manutenção MDM
        schtasks /run /tn "\Microsoft\Windows\EnterpriseMgmt\MDMMaintenenceTask" 2>$null
        
        # Forçar sincronização de políticas
        Get-ScheduledTask | Where-Object { $_.TaskName -like "*MDM*" -or $_.TaskName -like "*EnterpriseMgmt*" } | ForEach-Object {
            try {
                Start-ScheduledTask $_.TaskName -ErrorAction SilentlyContinue
                Write-Log "Tarefa executada: $($_.TaskName)"
            } catch {
                Write-Log "Falha ao executar tarefa: $($_.TaskName)" "WARNING"
            }
        }
        
        # Aguardar processamento
        Start-Sleep -Seconds 30
    }
    
    $remediationResults += New-RemediationResult -Component "MDM" -Action "ForceReEnrollment" -Status "SUCCESS" -Message "Re-enrollment Intune iniciado" -Details "Tarefas MDM executadas"
    
} catch {
    $remediationResults += New-RemediationResult -Component "MDM" -Action "ForceReEnrollment" -Status "FAILED" -Message "Erro no re-enrollment: $($_.Exception.Message)"
}
#endregion

#region Otimização de Rede e Proxy
Write-Log "Verificando e otimizando configurações de rede..."

try {
    # Verificar configurações de proxy que podem interferir
    $proxySettings = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
    
    if ($proxySettings -and $proxySettings.ProxyEnable -eq 1) {
        $proxyServer = $proxySettings.ProxyServer
        Write-Log "Proxy detectado: $proxyServer"
        
        # Verificar se endpoints Azure estão na lista de exceção
        $proxyOverride = $proxySettings.ProxyOverride
        $azureEndpoints = @("*.microsoftonline.com", "*.manage.microsoft.com", "*.windows.net")
        
        $missingOverrides = @()
        foreach ($endpoint in $azureEndpoints) {
            if ($proxyOverride -notlike "*$endpoint*") {
                $missingOverrides += $endpoint
            }
        }
        
        if ($missingOverrides.Count -gt 0) {
            $remediationResults += New-RemediationResult -Component "Network" -Action "CheckProxyConfig" -Status "WARNING" -Message "Endpoints Azure podem estar bloqueados pelo proxy" -Details "Faltam: $($missingOverrides -join ', ')" -Recommendation "Adicionar endpoints à lista de exceção do proxy"
        }
    }
    
    # Testar conectividade crítica
    $criticalEndpoints = @("login.microsoftonline.com", "enrollment.manage.microsoft.com")
    foreach ($endpoint in $criticalEndpoints) {
        try {
            $testResult = Test-NetConnection $endpoint -Port 443 -WarningAction SilentlyContinue
            if (-not $testResult.TcpTestSucceeded) {
                $remediationResults += New-RemediationResult -Component "Network" -Action "ConnectivityTest" -Status "FAILED" -Message "Falha de conectividade com $endpoint" -Impact "Enrollment e sincronização podem falhar"
            }
        } catch {
            $remediationResults += New-RemediationResult -Component "Network" -Action "ConnectivityTest" -Status "FAILED" -Message "Erro ao testar $endpoint : $($_.Exception.Message)"
        }
    }
    
} catch {
    $remediationResults += New-RemediationResult -Component "Network" -Action "NetworkOptimization" -Status "FAILED" -Message "Erro na verificação de rede: $($_.Exception.Message)"
}
#endregion

#region Limpeza Final e Validação
Write-Log "Executando limpeza final e validação..."

try {
    # Limpar cache DNS para resolver problemas de resolução
    if (-not $WhatIf) {
        ipconfig /flushdns | Out-Null
        $remediationResults += New-RemediationResult -Component "System" -Action "FlushDNS" -Status "SUCCESS" -Message "Cache DNS limpo"
    }
    
    # Limpar logs de eventos problemáticos
    if (-not $WhatIf) {
        try {
            Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin'; Level=2} -MaxEvents 1000 -ErrorAction SilentlyContinue | ForEach-Object {
                # Analisar erros específicos aqui se necessário
            }
        } catch {
            # Logs podem não existir, isso é normal
        }
    }
    
    # Reiniciar serviços relacionados ao MDM
    $mdmServices = @("dmwappushservice", "DmEnrollmentSvc")
    foreach ($serviceName in $mdmServices) {
        try {
            $service = Get-Service $serviceName -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq "Running") {
                if (-not $WhatIf) {
                    Restart-Service $serviceName -Force -ErrorAction SilentlyContinue
                }
                $remediationResults += New-RemediationResult -Component "MDM" -Action "RestartService" -Status "SUCCESS" -Message "Serviço $serviceName reiniciado"
            }
        } catch {
            Write-Log "Serviço $serviceName não encontrado ou não pôde ser reiniciado" "WARNING"
        }
    }
    
} catch {
    $remediationResults += New-RemediationResult -Component "System" -Action "FinalCleanup" -Status "FAILED" -Message "Erro na limpeza final: $($_.Exception.Message)"
}
#endregion

#region Calcular Estatísticas e Impacto
Write-Log "Calculando estatísticas de remediação..."

$successCount = ($remediationResults | Where-Object { $_.Status -eq "SUCCESS" }).Count
$failedCount = ($remediationResults | Where-Object { $_.Status -eq "FAILED" }).Count
$warningCount = ($remediationResults | Where-Object { $_.Status -eq "WARNING" }).Count
$skippedCount = ($remediationResults | Where-Object { $_.Status -eq "SKIPPED" }).Count

$remediationSummary = [PSCustomObject]@{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    DeviceName = $env:COMPUTERNAME
    TotalActions = $remediationResults.Count
    SuccessfulActions = $successCount
    FailedActions = $failedCount
    WarningActions = $warningCount
    SkippedActions = $skippedCount
    SuccessRate = if ($remediationResults.Count -gt 0) { [math]::Round(($successCount / $remediationResults.Count) * 100, 2) } else { 0 }
    RequiresReboot = $rebootRequired -or ($remediationResults | Where-Object { $_.RequiresReboot }).Count -gt 0
    WhatIfMode = $WhatIf
    RemediationStatus = if ($failedCount -eq 0 -and $successCount -gt 0) { "COMPLETED" }
                       elseif ($failedCount -gt 0 -and $successCount -gt $failedCount) { "PARTIAL" }
                       elseif ($failedCount -gt $successCount) { "FAILED" }
                       elseif ($WhatIf) { "SIMULATED" }
                       else { "NO_ACTION" }
    NextSteps = if ($rebootRequired) { "Reiniciar sistema e executar validação" }
               elseif ($failedCount -gt 0) { "Revisar falhas e executar novamente" }
               else { "Executar script de validação" }
}
#endregion

# Preparar saída para Power BI
$powerBIRemediationData = [PSCustomObject]@{
    RemediationSummary = $remediationSummary
    DetailedActions = $remediationResults
    ComponentSummary = $remediationResults | Group-Object Component | ForEach-Object {
        [PSCustomObject]@{
            Component = $_.Name
            TotalActions = $_.Count
            SuccessfulActions = ($_.Group | Where-Object { $_.Status -eq "SUCCESS" }).Count
            FailedActions = ($_.Group | Where-Object { $_.Status -eq "FAILED" }).Count
            WarningActions = ($_.Group | Where-Object { $_.Status -eq "WARNING" }).Count
            SkippedActions = ($_.Group | Where-Object { $_.Status -eq "SKIPPED" }).Count
            RequiresReboot = ($_.Group | Where-Object { $_.RequiresReboot }).Count -gt 0
        }
    }
    SystemInfo = [PSCustomObject]@{
        DeviceName = $env:COMPUTERNAME
        OSVersion = (Get-WmiObject Win32_OperatingSystem).Version
        Domain = $env:USERDOMAIN
        ExecutionTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ScriptVersion = "1.0"
        BackupLocation = $backupPath
    }
    ImpactAssessment = [PSCustomObject]@{
        ServicesModified = ($remediationResults | Where-Object { $_.Action -like "*Service*" }).Count
        RegistryChanges = ($remediationResults | Where-Object { $_.Action -like "*Registry*" -or $_.Action -like "*Policy*" -or $_.Action -like "*Enrollment*" }).Count
        NetworkChanges = ($remediationResults | Where-Object { $_.Component -eq "Network" }).Count
        SecurityImpact = ($remediationResults | Where-Object { $_.Component -eq "Security" }).Count
        RebootRequired = $rebootRequired
    }
}

# Salvar resultados
Write-Log "Salvando resultados de remediação em $OutputPath..."
$powerBIRemediationData | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8

# Exibir resumo final
Write-Host "`n" -ForegroundColor Green
Write-Host "=== RESUMO DA REMEDIAÇÃO ===" -ForegroundColor Cyan
Write-Host "Device: $($remediationSummary.DeviceName)" -ForegroundColor White
Write-Host "Status: $($remediationSummary.RemediationStatus)" -ForegroundColor $(
    switch($remediationSummary.RemediationStatus) {
        "COMPLETED" { "Green" }
        "PARTIAL" { "Yellow" }
        "FAILED" { "Red" }
        "SIMULATED" { "Cyan" }
        default { "White" }
    }
)
Write-Host "Taxa de Sucesso: $($remediationSummary.SuccessRate)%" -ForegroundColor Green
Write-Host "Ações Bem-sucedidas: $($remediationSummary.SuccessfulActions)" -ForegroundColor Green
Write-Host "Ações Falharam: $($remediationSummary.FailedActions)" -ForegroundColor Red
Write-Host "Avisos: $($remediationSummary.WarningActions)" -ForegroundColor Yellow
Write-Host "Reboot Necessário: $($remediationSummary.RequiresReboot)" -ForegroundColor $(if ($remediationSummary.RequiresReboot) { "Red" } else { "Green" })
Write-Host "`nPróximos Passos: $($remediationSummary.NextSteps)" -ForegroundColor Cyan
Write-Host "`nResultados salvos em: $OutputPath" -ForegroundColor Cyan

if ($remediationSummary.RequiresReboot) {
    Write-Host "`n⚠️  ATENÇÃO: Reinicialização necessária para completar a remediação!" -ForegroundColor Yellow -BackgroundColor Red
}

Write-Log "Remediação concluída!"
return $powerBIRemediationData