Ótimo! Vou te mostrar exemplos práticos para incorporar mais scripts e customizar relatórios no seu fluxo de troubleshooting do Intune/Autopilot, incluindo como integrar novos diagnósticos ou adaptar saídas para diferentes formatos.

---

## **1. Como incorporar scripts extras à rotina**

Suponha que você tenha um script chamado `dsreg.ps1` para análise avançada do Device Registration e um outro chamado `Check-CompliancePolicies.ps1` para listar todas as políticas de compliance aplicadas. Veja como adicionar esses ao seu script principal:

```powershell name=Intune_Troubleshooting_Sequence.ps1
# ... etapas anteriores

# 6. Análise avançada do dsreg (Device Registration)
Write-Host "Executando análise detalhada de dsreg..." -ForegroundColor Cyan
. ".\dsreg.ps1" -OutputFileName "$reportDir\dsreg_detalhado.txt"

# 7. Listar todas as políticas de compliance do Intune
Write-Host "Listando todas as políticas de compliance aplicadas..." -ForegroundColor Cyan
. ".\Check-CompliancePolicies.ps1" -OutputFileName "$reportDir\CompliancePolicies.csv"
```

---

## **2. Como customizar relatórios para XLSX, CSV ou HTML**

Suponha que você queira salvar relatórios em múltiplos formatos (XLSX, CSV e HTML):

```powershell
# Exportar relatório de dispositivos não conformes em múltiplos formatos
$total | Export-Excel -Path "$reportDir\NonCompliantDevices.xlsx" -WorksheetName "NonCompliant" -AutoFilter -AutoSize
$total | Export-Csv -Path "$reportDir\NonCompliantDevices.csv" -NoTypeInformation -Encoding UTF8
$total | ConvertTo-Html | Out-File "$reportDir\NonCompliantDevices.html"
```

---

## **3. Como enviar relatório por email automaticamente**

Se quiser que o script envie o relatório por email após a execução:

```powershell
# Parâmetros de email
$mailParams = @{
    SmtpServer = "smtp.seudominio.com"
    From = "intune-reports@seudominio.com"
    To = "seuemail@seudominio.com"
    Subject = "Relatório de Troubleshooting Intune - $timestamp"
    Body = "Segue em anexo os relatórios gerados automaticamente."
    Attachments = @("$reportDir\NonCompliantDevices.xlsx", "$reportDir\dsreg_detalhado.txt")
}
Send-MailMessage @mailParams
```

---

## **4. Como executar scripts em múltiplas máquinas (remoto)**

Se você quiser rodar o script em várias máquinas via PowerShell Remoting:

```powershell
$computers = @("PC01", "PC02", "PC03")
Invoke-Command -ComputerName $computers -FilePath ".\Intune_Troubleshooting_Sequence.ps1"
```

---

## **5. Como registrar logs das execuções**

Adicione uma função para registrar logs de execução:

```powershell
function Write-Log {
    param([string]$message)
    Add-Content -Path "$reportDir\execucao.log" -Value "$(Get-Date -Format 'u'): $message"
}

Write-Log "Iniciando diagnóstico de Intune..."
# ... em cada etapa chame Write-Log
```

---

## **Exemplo de integração de script customizado**

Suponha que você tem um script para buscar eventos específicos no Event Viewer (`Search-IntuneEvents.ps1`):

```powershell
Write-Host "Buscando eventos críticos de Intune no Event Viewer..." -ForegroundColor Cyan
. ".\Search-IntuneEvents.ps1" -OutputFileName "$reportDir\IntuneEvents.csv"
```

---

## **Resumo**

- **Para incorporar mais scripts:** Basta adicionar as chamadas (`. "<caminho_script>" <parametros>`) na sequência desejada.
- **Para customizar relatórios:** Use `Export-Excel`, `Export-Csv`, `ConvertTo-Html` ou outras funções.
- **Para automação e integração:** Adicione envio de email, execução remota ou logging conforme sua necessidade.

Se quiser exemplos de scripts específicos para compliance, dsreg, eventos, ou integração com outros sistemas, só pedir!