<# 
Intune_Troubleshooting_Sequence.ps1
Script de alto nível para executar em sequência os principais diagnósticos de Intune/Autopilot/Compliance.
Inclui:
- Análise de logs do Intune Management Extension
- Report de dispositivos e perfis do Autopilot
- Verificação de usuários primários
- Relatório de dispositivos não conformes
- Análise de dsreg (AzureAD/Intune Join)
Ajuste os caminhos dos scripts conforme sua organização de arquivos.
#>

# Requisitos: Microsoft.Graph, ImportExcel (para relatórios XLSX), permissões administrativas.

# Variáveis de saída
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportDir = ".\Intune_Troubleshooting_Reports\$timestamp"
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

# 1. Análise de logs do Intune Management Extension
Write-Host "Analisando logs do Intune Management Extension..." -ForegroundColor Cyan
. ".\Show Intune Management Extension Logs\Show-IntuneManagementExtensionLog.ps1" -All

# 2. Report de dispositivos Autopilot
Write-Host "Gerando relatório de dispositivos e perfis Autopilot..." -ForegroundColor Cyan
$autopilotReport = "$reportDir\Autopilot_Report.xlsx"
. ".\Windows Autopilot Report\Windows_Autopilot_Report.ps1" -OutputFileName $autopilotReport

# 3. Verificação de usuário primário do Intune
Write-Host "Recuperando usuários primários dos dispositivos Intune..." -ForegroundColor Cyan
$primaryUserReport = "$reportDir\PrimaryUser_Report.csv"
. ".\Retrieve Intune Primary User\Get-IntunePrimaryUser.ps1" -OutputFileName $primaryUserReport

# 4. Report de dispositivos não conformes
Write-Host "Listando dispositivos não conformes e razões..." -ForegroundColor Cyan
$noncompliantReport = "$reportDir\NonCompliantDevices_Report.csv"
. ".\Report on Non-Compliant Intune devices\Get-IntuneNonCompliantDevices.ps1" -outputfile $noncompliantReport

# 5. Análise de dsreg (estado de registro do dispositivo)
Write-Host "Executando análise de dsreg..." -ForegroundColor Cyan
$dsregReport = "$reportDir\dsreg_report.txt"
dsregcmd /status | Out-File $dsregReport

# 6. (Opcional) Executar script de detecção de WinGet (para verificar apps gerenciados)
Write-Host "Executando detecção de apps WinGet via Intune..." -ForegroundColor Cyan
. ".\Deploy and automatically update WinGet apps in Intune\Detection.ps1"

# 7. Análise avançada do dsreg (Device Registration)
Write-Host "Executando análise detalhada de dsreg..." -ForegroundColor Cyan
. ".\dsreg.ps1" -OutputFileName "$reportDir\dsreg_detalhado.txt"

# 8. Listar todas as políticas de compliance do Intune
Write-Host "Listando todas as políticas de compliance aplicadas..." -ForegroundColor Cyan
. ".\Check-CompliancePolicies.ps1" -OutputFileName "$reportDir\CompliancePolicies.csv"

Write-Host "Relatórios e logs salvos em $reportDir" -ForegroundColor Green