# 📊 GUIA DE IMPLEMENTAÇÃO - DASHBOARD POWER BI PARA MDM/INTUNE

## 🎯 **VISÃO GERAL**

Este guia detalha como criar um dashboard no Power BI para monitoramento do ambiente Azure AD + Intune baseado nos scripts de validação e remediação fornecidos.

## 📁 **ESTRUTURA DE ARQUIVOS GERADOS**

### **Arquivos JSON (Dados Detalhados)**

- `Validation_Results_YYYYMMDD_HHMMSS.json` - Resultados completos da validação
- `Remediation_Results_YYYYMMDD_HHMMSS.json` - Resultados detalhados da remediação  
- `PowerBI_Dashboard_Data_YYYYMMDD_HHMMSS.json` - Dados consolidados para dashboard

### **Arquivo CSV (Importação Direta)**

- `PowerBI_Summary_YYYYMMDD_HHMMSS.csv` - Dados resumidos para importação fácil

---

## 🔧 **SETUP DO POWER BI**

### **1. CONECTORES DE DADOS**

#### **Opção A: Arquivo CSV (Recomendado para início)**

```powerbi
// M Query para importar CSV
let
    Source = Csv.Document(File.Contents("C:\Temp\MDM_Reports\PowerBI_Summary_*.csv"),[Delimiter=",", Columns=14, Encoding=1252, QuoteStyle=QuoteStyle.None]),
    #"Promoted Headers" = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    #"Changed Type" = Table.TransformColumnTypes(#"Promoted Headers",{
        {"DeviceName", type text},
        {"ExecutionDate", type date},
        {"ExecutionTime", type time},
        {"OverallHealthScore", type number},
        {"HealthStatus", type text},
        {"CriticalIssues", Int64.Type},
        {"ErrorIssues", Int64.Type},
        {"WarningIssues", Int64.Type},
        {"HealthyChecks", Int64.Type},
        {"RemediationStatus", type text},
        {"SuccessfulActions", Int64.Type},
        {"FailedActions", Int64.Type},
        {"RebootRequired", type logical},
        {"ExecutionMode", type text},
        {"WhatIfMode", type logical}
    })
in
    #"Changed Type"
```

#### **Opção B: JSON (Para dados detalhados)**

```powerbi
// M Query para importar JSON consolidado
let
    Source = Json.Document(File.Contents("C:\Temp\MDM_Reports\PowerBI_Dashboard_Data_*.json")),
    ExecutionInfo = Source[ExecutionInfo],
    ValidationData = Source[ValidationData],
    RemediationData = Source[RemediationData],
    PowerBIDashboardData = Source[PowerBIDashboardData]
in
    PowerBIDashboardData
```

### **2. TRANSFORMAÇÕES DE DADOS**

#### **Medidas DAX Principais**

```dax
// Saúde Geral - Score
Health Score = 
AVERAGE('MDM_Summary'[OverallHealthScore])

// Status de Saúde - Classificação
Health Status Color = 
SWITCH(
    MAX('MDM_Summary'[HealthStatus]),
    "EXCELLENT", "#00A651",
    "GOOD", "#32CD32", 
    "FAIR", "#FFD700",
    "POOR", "#FF8C00",
    "CRITICAL", "#DC143C",
    "#808080"
)

// Total de Problemas
Total Issues = 
SUM('MDM_Summary'[CriticalIssues]) + 
SUM('MDM_Summary'[ErrorIssues]) + 
SUM('MDM_Summary'[WarningIssues])

// Taxa de Sucesso da Remediação
Remediation Success Rate = 
DIVIDE(
    SUM('MDM_Summary'[SuccessfulActions]),
    SUM('MDM_Summary'[SuccessfulActions]) + SUM('MDM_Summary'[FailedActions]),
    0
) * 100

// Tendência de Saúde (para múltiplas execuções)
Health Trend = 
VAR CurrentScore = [Health Score]
VAR PreviousScore = 
    CALCULATE(
        [Health Score],
        DATEADD('MDM_Summary'[ExecutionDate], -1, DAY)
    )
RETURN
    IF(
        ISBLANK(PreviousScore), 0,
        CurrentScore - PreviousScore
    )

// Dispositivos Críticos
Critical Devices = 
CALCULATE(
    DISTINCTCOUNT('MDM_Summary'[DeviceName]),
    'MDM_Summary'[CriticalIssues] > 0
)

// Necessita Reboot
Devices Requiring Reboot = 
CALCULATE(
    DISTINCTCOUNT('MDM_Summary'[DeviceName]),
    'MDM_Summary'[RebootRequired] = TRUE()
)
```

---

## 📊 **LAYOUT DO DASHBOARD**

### **PÁGINA 1: VISÃO GERAL EXECUTIVA**

#### **Cards de Resumo (Topo)**

- **Health Score Geral** - Gauge visual (0-100)
- **Total de Dispositivos** - Card
- **Problemas Críticos** - Card com alerta vermelho
- **Taxa de Sucesso Remediação** - Card com %

#### **Gráficos Principais**

1. **Donut Chart**: Distribuição por Status de Saúde
   - Excellent, Good, Fair, Poor, Critical
   - Cores: Verde → Vermelho

2. **Gráfico de Barras**: Problemas por Componente
   - AzureAD, MDM, Authentication, Network, Security
   - Stacked: Critical, Error, Warning

3. **Linha do Tempo**: Evolução do Health Score
   - Eixo X: Data/Hora de execução
   - Eixo Y: Score de 0-100

#### **Tabela de Alertas**

- Lista dispositivos com problemas críticos
- Colunas: Device, Component, Issue, Recommendation

### **PÁGINA 2: DETALHES TÉCNICOS**

#### **Matriz de Componentes**

- Linhas: Dispositivos
- Colunas: Componentes (AzureAD, MDM, Auth, etc.)
- Valores: Status (cores condicionais)

#### **Timeline de Remediação**

- Gráfico de Gantt ou Timeline
- Ações executadas por dispositivo
- Status: Success, Failed, Warning

#### **Filtros Laterais**

- Data Range Picker
- Device Name (Multi-select)
- Health Status
- Execution Mode

---

## 🎨 **CONFIGURAÇÕES DE FORMATO**

### **Cores do Tema**

```json
{
  "name": "MDM Monitoring Theme",
  "dataColors": [
    "#00A651",  // Excellent/Success
    "#32CD32",  // Good
    "#FFD700",  // Fair/Warning  
    "#FF8C00",  // Poor
    "#DC143C",  // Critical/Failed
    "#4472C4",  // Info/Primary
    "#70AD47",  // Secondary
    "#FFC000"   // Accent
  ]
}
```

### **Formatação Condicional**

#### **Health Score Gauge**

- Verde (90-100): Excellent
- Verde Claro (70-89): Good  
- Amarelo (50-69): Fair
- Laranja (30-49): Poor
- Vermelho (0-29): Critical

#### **Status Icons**

- ✅ Success/OK
- ⚠️ Warning
- ❌ Critical/Error
- 🔄 In Progress
- 🛡️ Security Related

---

## 📅 **AUTOMAÇÃO E REFRESH**

### **Power BI Service (Recomendado)**

1. **Gateway Configuration**
   - Install Power BI Gateway no servidor
   - Configure acesso aos diretórios de logs

2. **Dataset Refresh Schedule**

   ```json
   {
     "refreshSchedule": {
       "frequency": "Daily",
       "times": ["06:00", "12:00", "18:00"],
       "timezone": "E. South America Standard Time"
     }
   }
   ```

3. **Alertas Automáticos**
   - Critical Issues > 0
   - Health Score < 70
   - Devices Requiring Reboot > 5

### **Power Automate Integration**

```json
{
  "trigger": "When a file is created",
  "path": "/MDM_Reports/",
  "action": "Refresh Power BI Dataset",
  "notification": "Send email if critical issues found"
}
```

---

## 📱 **MOBILE LAYOUT**

### **Configuração Responsiva**

- Cards principais em layout vertical
- Gráficos simplificados para tela pequena
- Navegação por swipe entre páginas
- Alerts push para problemas críticos

---

## 🔐 **SEGURANÇA E ACESSO**

### **Row Level Security (RLS)**

```dax
// Filtro por domínio/localização
[Domain] = USERNAME()

// Filtro por grupo de dispositivos  
PATHCONTAINS(
    LOOKUPVALUE(UserAccess[DeviceGroups], UserAccess[User], USERNAME()),
    'MDM_Summary'[DeviceName]
)
```

### **Controle de Acesso**

- **Administradores**: Acesso total + remediação
- **Técnicos**: Visualização + alertas
- **Gestores**: Dashboard executivo apenas

---

## 📈 **MÉTRICAS E KPIs**

### **KPIs Principais**

1. **Uptime Score**: % dispositivos saudáveis
2. **MTTR**: Tempo médio para correção
3. **Compliance Rate**: % conformidade com políticas
4. **Automation Rate**: % problemas resolvidos automaticamente

### **SLAs Sugeridos**

- Critical Issues: Resolução em 4h
- Health Score: Manter > 85%
- Compliance: > 95%
- Remediation Success: > 90%

---

## 🚀 **EXEMPLO DE EXECUÇÃO**

### **Script de Coleta Automatizada**

```powershell
# Agendamento via Task Scheduler
$scriptPath = "C:\Scripts\MDM-Executive-Script.ps1"
$outputPath = "C:\Reports\MDM_Reports"

# Executar validação + remediação
& $scriptPath -Mode "Both" -OutputDirectory $outputPath -GenerateDashboardData

# Upload para SharePoint (opcional)
$latestReport = Get-ChildItem $outputPath -Filter "PowerBI_Summary_*.csv" | Sort-Object LastWriteTime -Desc | Select-Object -First 1
# Upload logic here...
```

### **Estrutura de Pastas Recomendada**

C:\Reports\MDM_Reports\
├── Archive\
│   ├── 2025-09\
│   └── 2025-10\
├── Current\
│   ├── PowerBI_Summary_latest.csv
│   └── PowerBI_Dashboard_Data_latest.json
└── Scripts\
    ├── MDM-Validation-Script.ps1
    ├── MDM-Remediation-Script.ps1
    └── MDM-Executive-Script.ps1

---

## 🏁 **PRÓXIMOS PASSOS**

1. **Implementar scripts** nos dispositivos de teste
2. **Configurar coleta automatizada** via Task Scheduler
3. **Criar workspace** no Power BI Service
4. **Desenvolver dashboard** seguindo o layout sugerido
5. **Configurar alertas** para problemas críticos
6. **Treinar equipe** no uso do dashboard
7. **Estabelecer SLAs** e processos de resposta

---

**📞 Suporte**: Para dúvidas sobre implementação, consulte a documentação técnica dos scripts ou entre em contato com a equipe de TI.
