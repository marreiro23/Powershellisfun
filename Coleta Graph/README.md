# Documentação dos Scripts de Relatórios Microsoft Graph

## Scripts Criados

### 1. `Validate-GraphModules.ps1` - Validador de Módulos
**Funcionalidade:**
- ✅ Verifica a presença dos módulos Microsoft.Graph necessários
- ✅ Valida se os comandos críticos estão disponíveis
- ✅ Testa a importação dos módulos
- ✅ Verifica conectividade existente ao Microsoft Graph
- ✅ Valida escopos/permissões configurados
- ✅ Testa queries básicas (se conectado)
- ✅ Verifica versão do PowerShell e política de execução

**Como usar:**
```powershell
.\Validate-GraphModules.ps1
```

### 2. `Graph-Reports-Clean.ps1` - Script Principal de Relatórios
**Funcionalidade:**
- ✅ Validação automática de módulos na execução
- ✅ Instalação automática de módulos em falta
- ✅ Conectividade robusta com tratamento de erros
- ✅ Queries otimizadas com retry automático
- ✅ Relatórios executivos e detalhados
- ✅ Análise de conformidade e sincronização
- ✅ Exportação para CSV
- ✅ Interface colorida e intuitiva

**Como usar:**
```powershell
.\Graph-Reports-Clean.ps1
```

## Validações Implementadas

### ✅ Validação de Módulos
- Verifica presença de `Microsoft.Graph.Authentication`
- Verifica presença de `Microsoft.Graph.DeviceManagement`
- Testa importação sem erros
- Valida comandos críticos disponíveis

### ✅ Validação de Conectividade
- Detecta conexões existentes
- Verifica escopos/permissões necessárias
- Testa autenticação automática
- Permite reconexão se necessário

### ✅ Validação de Queries
- Queries com retry automático (até 3 tentativas)
- Tratamento de erros específicos
- Otimização de propriedades requisitadas
- Validação de resultados antes de processar

### ✅ Validação de Ambiente
- Verifica versão do PowerShell (5.1+)
- Valida política de execução
- Testa encoding e caracteres especiais
- Suporte a diferentes shells (PowerShell Core/Windows PowerShell)

## Melhorias Implementadas

### 🔧 Queries Otimizadas
**Antes:**
```powershell
Invoke-MSGraphRequest -Url "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
```

**Depois:**
```powershell
Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop
```

### 🔧 Tratamento de Erros
- Retry automático com backoff
- Mensagens específicas por tipo de erro
- Validação de dados antes de processamento
- Logs detalhados para troubleshooting

### 🔧 Relatórios Aprimorados
- Estatísticas executivas (percentuais)
- Análise por Sistema Operacional
- Identificação de dispositivos "perdidos"
- Relatório detalhado com encoding correto
- Opção de exportação CSV

## Escopos/Permissões Necessárias

```powershell
$requiredScopes = @(
    "DeviceManagementManagedDevices.Read.All",
    "DeviceManagementConfiguration.Read.All"
)
```

## Status de Validação

| Componente | Status | Observações |
|------------|---------|-------------|
| Módulos Microsoft.Graph | ✅ Validado | v2.30.0 instalada |
| Comandos críticos | ✅ Validado | Todos disponíveis |
| Sintaxe do script | ✅ Validado | Sem erros de parsing |
| Encoding/Caracteres | ✅ Corrigido | Suporte UTF-8 |
| Tratamento de erros | ✅ Implementado | Retry + logging |
| Interface do usuário | ✅ Melhorada | Cores + feedback |

## Próximos Passos

1. **Execute a validação:**
   ```powershell
   .\Validate-GraphModules.ps1
   ```

2. **Se a validação passou, execute o script principal:**
   ```powershell
   .\Graph-Reports-Clean.ps1
   ```

3. **Autentique-se quando solicitado** (primeira execução)

4. **Revise os relatórios gerados** e opte pela exportação CSV se necessário

## Troubleshooting

### Erro: "Módulo não encontrado"
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser -Force
```

### Erro: "Permissões insuficientes"
- Reconecte com escopos adequados
- Verifique permissões no Azure AD

### Erro: "Falha na query"
- Verifique conectividade de rede
- Valide token de autenticação
- Tente novamente (retry automático implementado)