# Solicitação de Permissões para Administração de Intune, Group Policy (ADDS) e SCCM Co-management

Prezados,

Solicito a concessão das permissões abaixo para administração dos ambientes de Intune, Group Policy do Active Directory Domain Services (ADDS) e SCCM Co-management, visando garantir a gestão adequada dos recursos sem atribuição de privilégios excessivos como Global Administrator ou Domain Admins.

## 1. Microsoft Intune

**Permissão Solicitada:**  
- **Intune Service Administrator**  
**Finalidade:**  
Permite gerenciar políticas de dispositivos, aplicativos, configurações de compliance e relatórios no Intune.  
**Justificativa:**  
Necessária para administrar dispositivos, criar e modificar políticas de configuração, realizar troubleshooting e gerar relatórios, sem acesso irrestrito ao tenant.

## 2. Active Directory Domain Services (ADDS) - Group Policy

**Permissão Solicitada:**  
- **Group Policy Creator Owners**  
- **Delegação específica em OUs (Unidades Organizacionais) para edição de GPOs**  
**Finalidade:**  
Permite criar, editar e vincular objetos de política de grupo (GPOs) nas OUs delegadas.  
**Justificativa:**  
Essas permissões são suficientes para gerenciar políticas de segurança e configuração dos computadores e usuários, sem acesso administrativo total ao domínio.

## 3. SCCM Co-management

**Permissão Solicitada:**  
- **SCCM Full Administrator** (no console do SCCM, não no AD)  
- **Permissões de leitura e escrita em coleções específicas**  
**Finalidade:**  
Permite administrar configurações de co-management, integrar SCCM com Intune, gerenciar dispositivos e políticas de compliance.  
**Justificativa:**  
Essas permissões garantem a administração do SCCM e sua integração com Intune, sem necessidade de permissões elevadas no AD ou no tenant.

## 4. Microsoft Graph Command Line Tools (PowerShell)

**Permissões Solicitadas:**
- DeviceManagementManagedDevices.Read.All
- DeviceManagementConfiguration.Read.All
- Device.Read.All (opcional para detalhes avançados)

**Finalidade:**
Permite a coleta de informações detalhadas de dispositivos, políticas de conformidade e configurações diretamente do Intune via scripts PowerShell utilizando Microsoft Graph, conforme descrito nos scripts do diretório.

**Justificativa:**
Essas permissões são necessárias para executar comandos e scripts que consultam dados do Intune, gerando relatórios e facilitando o troubleshooting, sem conceder acesso administrativo global ao tenant.

---

## Resumo das Roles Solicitadas (Atualizado)

| Ambiente      | Role/Permissão                                   | Finalidade Principal                          |
|---------------|--------------------------------------------------|-----------------------------------------------|
| Intune        | Intune Service Administrator                     | Gerenciar dispositivos, políticas e apps      |
| ADDS          | Group Policy Creator Owners                      | Criar/editar GPOs nas OUs delegadas           |
| SCCM          | SCCM Full Administrator (console)                | Gerenciar co-management e integração Intune   |
| Intune/Graph  | Permissões Microsoft Graph (PowerShell)          | Coleta de dados e relatórios via scripts      |

---

**Observação:**  
Todas as permissões solicitadas são restritas ao escopo de administração dos ambientes mencionados, evitando privilégios excessivos e alinhando-se às melhores práticas de segurança.

Atenciosamente,  
Daniel Marreiro
Consultor Okta7
25/09/2025
