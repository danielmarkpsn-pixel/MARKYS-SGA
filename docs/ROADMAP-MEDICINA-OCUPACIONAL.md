# MARKYS-SGA — auditoria funcional e roteiro de evolução para Medicina Ocupacional

Data da auditoria: 25/11/2026  
Branch auditada: `security/review-hardening-2026-11`  
Escopo: aplicação oficial da raiz do repositório (`./`), código, APIs, migrações e testes versionados. A pasta `online/` é tratada apenas como histórico/referência, conforme README.

## 1. Resumo executivo

O MARKYS-SGA possui hoje uma base operacional de atendimento, fila, sala de espera, painel profissional, administração de logins, financeiro, convênios, tabela de preços, documentos internos de serviço, catálogo de serviços e fundação multi-clínica.

Ainda não foi identificado no código e nas migrações examinados um núcleo especializado completo de Saúde Ocupacional. Em particular, não foi identificado um conjunto integrado de módulos para empresas clientes, estabelecimentos, trabalhadores e vínculos, cargos/funções/setores, riscos/GHE, PCMSO, prontuário ocupacional, ASO, gestão clínica de exames ocupacionais e integração eSocial SST.

Esta é uma auditoria estática de repositório. Não equivale a homologação funcional no navegador nem a uma validação clínica, jurídica ou regulatória.

## 2. Inventário do que já existe

| Área | Evidência no repositório | Avaliação |
|---|---|---|
| Recepção e cadastro de pacientes | `index.html`, fila e formulários | Implementado como atendimento geral; precisa evolução para trabalhador e vínculo com empresa |
| Fila e sala de espera | `index.html`, `sala/index.html`, APIs e RPCs de fila | Implementado; preservar projeção pública mínima |
| Painel profissional | `consultorio.html` | Implementado como fluxo de fila/atendimento; não é prontuário ocupacional completo |
| Autenticação e perfis | `markys-auth.js`, `admin-logins.html`, Edge Function `master-users` | Em endurecimento; manter Master separado de Administração Clínica |
| Financeiro | `financeiro.html` e migrações `markys_finance_*` | Módulo existente; precisa integração com empresa, contrato, serviço e faturamento ocupacional |
| Convênios e preços | `financeiro.html`, `markys_insurances`, `markys_insurance_exam_prices` | Implementado para convênios; não substitui contrato corporativo |
| Notas internas de serviço | `markys_service_documents` e RPC correspondente | Implementado; avaliar evolução para faturamento empresarial e vínculo a ordens/atendimentos |
| Catálogo de serviços | `markys_service_catalog` | Implementado como catálogo geral; precisa atributos ocupacionais, códigos e regras |
| Multi-clínica | `markys_clinics`, `clinic_id`, RLS, fila por clínica e Storage | Fundação implementada na branch; requer testes de isolamento completos |
| Mídia da sala | API de mídia e migração para bucket privado | Implementação preparada na branch; não presumir produção atualizada |
| Auditoria e proteção de exclusão | migrações de exclusão recente e testes SQL | Preparado na branch; confirmar execução apenas em ambiente isolado |
| Testes | `security-regression-check.mjs`, `scripts/check-security-basics.mjs`, `supabase/tests/security_regression.sql` | Existem verificações estáticas e SQL; falta pipeline real de PostgreSQL limpo + testes por papel/tenant |

### Limites importantes da base atual

- O cadastro de paciente não deve ser simplesmente renomeado para trabalhador: a relação com empresa, matrícula, lotação, função, exposição e histórico de vínculos exige modelo próprio.
- Convênio não é equivalente a empresa contratante. Uma empresa pode contratar serviços diretamente, possuir múltiplas unidades e condições comerciais próprias.
- Catálogo de serviços não equivale a matriz de riscos nem a um plano de exames por função/GHE.
- Nota interna de serviço não equivale, sozinha, a faturamento por contrato, medição de produção e conciliação empresarial.
- A fila pública não deve receber dados clínicos, diagnósticos, resultados, CPF, riscos ou detalhes de ASO.

## 3. Lacunas funcionais prioritárias

### P0 — fundação do domínio ocupacional

1. **Empresas e contratos**
   - empresa cliente, CNPJ e dados administrativos;
   - unidades/estabelecimentos e endereços;
   - responsáveis e contatos;
   - contratos, vigência, escopo, preços, franquias e regras de cobrança;
   - status e histórico contratual.

2. **Trabalhadores e vínculos**
   - cadastro administrativo do trabalhador;
   - matrícula por empresa, datas de admissão/desligamento e situação;
   - histórico de vínculos sem sobrescrever vínculos anteriores;
   - unidade, setor, cargo/função e centro de custo;
   - importação em lote com validação e relatório de erros.

3. **Estrutura ocupacional**
   - cargos, funções, setores e estabelecimentos;
   - grupos homogêneos de exposição (GHE), quando aplicável;
   - riscos e fatores de exposição com fonte, intensidade/concentração quando pertinente, período e responsável pela avaliação;
   - histórico de alterações e vínculo com documentos técnicos.

4. **PCMSO e planejamento**
   - programas por empresa/estabelecimento e período de vigência;
   - responsável médico e versão;
   - matriz de exames por função/GHE/risco, periodicidade e critérios;
   - exceções justificadas, pendências e trilha de aprovação;
   - controle de revisão e histórico, sem gerar prescrição automática não validada.

5. **ASO e prontuário ocupacional**
   - fluxo de admissional, periódico, retorno ao trabalho, mudança de riscos ocupacionais e demissional;
   - dados exigidos no documento conforme regra vigente;
   - conclusão de aptidão e restrições registradas exclusivamente pelo profissional habilitado;
   - assinatura, emissão, retificação/cancelamento e histórico;
   - prontuário ocupacional com acesso restrito e trilha de auditoria.

6. **Exames e resultados**
   - solicitação, agendamento, execução, resultado, revisão e pendência;
   - catálogo de procedimentos e requisitos por tipo de exame;
   - vínculo a trabalhador, atendimento, PCMSO, empresa e contrato;
   - anexos privados, laudos e validade;
   - controle de repetição, recoleta e exame não realizado.

### P1 — operação, faturamento e conformidade

- Agenda por clínica, unidade, profissional, sala, equipamento e procedimento.
- Ordem de serviço por empresa e lote de trabalhadores.
- Check-in, triagem administrativa, execução por etapas e encerramento.
- Central de pendências por equipe, empresa, trabalhador e prazo.
- Faturamento a partir de serviços efetivamente executados, com regras contratuais, auditoria e prevenção de duplicidade.
- Portal empresarial com acesso segregado, importação, solicitações, agendamentos e documentos autorizados.
- Relatórios operacionais e gerenciais com agregação e controle de acesso.
- Preparação e integração de eventos eSocial SST conforme leiautes oficiais vigentes, com validação, transmissão quando contratada/autorizada, recibos, rejeições e retificações.

### P2 — diferenciais e expansão

- Gestão de estoque, insumos e EPI.
- Equipamentos, calibração, manutenção e vencimentos.
- Gestão comercial de propostas e renovações.
- Qualidade, não conformidades e planos de ação.
- BI de produção, receita, custos, produtividade e indicadores ocupacionais agregados.
- IA apenas como assistente de tarefas administrativas e análise documental controlada; nunca como decisor de diagnóstico ou aptidão.

## 4. Modelo de domínio proposto

Entidades principais (nomes conceituais; não criar tabelas sem desenho e revisão):

- `companies`: empresa contratante.
- `company_sites`: estabelecimentos/unidades da empresa.
- `company_contacts`: responsáveis e contatos.
- `company_contracts` e `contract_items`: vigência, escopo e condições comerciais.
- `workers`: identidade administrativa do trabalhador.
- `worker_employments`: vínculos históricos por empresa/unidade.
- `occupational_sectors`, `job_roles`, `work_shifts`: estrutura organizacional.
- `exposure_groups` e `occupational_hazards`: GHE e riscos/exposições.
- `pcmso_programs`, `pcmso_versions`, `pcmso_exam_rules`: programas, versões e planejamento.
- `occupational_orders` e `occupational_order_workers`: ordens e lotes.
- `occupational_appointments`: agendamentos.
- `occupational_exams`, `exam_results`, `exam_attachments`: execução e resultados.
- `occupational_records`: prontuário ocupacional restrito.
- `asos` e `aso_events`: emissão, assinatura, retificação e histórico.
- `esocial_events`, `esocial_receipts`, `esocial_attempts`: integração e rastreabilidade.
- `billing_batches`, `billing_items`: medição e faturamento.
- `audit_events`: trilha de ações sensíveis, com acesso restrito.

Todas as entidades de negócio devem ser vinculadas a `clinic_id`; entidades ligadas à empresa devem carregar também a chave de empresa/unidade quando aplicável. Restrições compostas e validações no banco devem impedir referências cruzadas entre clínicas. Não confiar apenas em filtros da interface.

## 5. Regras de segurança e privacidade obrigatórias

1. Separação por clínica aplicada no banco (RLS, constraints e RPCs), APIs, Storage e Realtime.
2. Separação entre dados administrativos de RH e dados pessoais sensíveis de saúde.
3. Prontuário, resultados e anexos clínicos com permissões específicas por função e necessidade de acesso.
4. Portal da empresa limitado a dados administrativos e documentos expressamente permitidos; não expor prontuário, diagnóstico ou resultado clínico irrestrito.
5. Acesso de profissionais limitado à sua atribuição e finalidade assistencial, com auditoria de leitura e alteração.
6. ASO e conclusões clínicas não podem ser decididos por automação ou IA.
7. URLs assinadas de curta duração, buckets privados e validação de propriedade/tenant no servidor.
8. Exportações, impressão, downloads, compartilhamento e consultas em massa auditáveis.
9. Política de retenção, descarte, backup e restauração testada.
10. Dados sintéticos nos testes; nunca copiar prontuários reais para ambientes de desenvolvimento.

## 6. Estratégia técnica de implementação

- Continuar exclusivamente na branch `security/review-hardening-2026-11` até revisão e aprovação.
- Não alterar `main`, não fazer merge, não publicar e não executar `db push` ou `migration repair` como parte deste roteiro.
- Não criar branch de teste Supabase.
- Usar a aplicação da raiz como alvo oficial; `online/` permanece referência histórica.
- Antes de novas tabelas: revisar schema atual e chaves, desenhar ERD, mapear RLS e testar isolamento.
- Criar migrações incrementais novas; nunca editar migrações históricas já aplicadas.
- Adicionar CI com PostgreSQL efêmero para aplicar todas as migrações canônicas da raiz e executar testes SQL.
- Testar cada papel: Master, Administração Clínica, Recepção, Profissional, usuário inativo e anon.
- Testar duas clínicas sintéticas e provar que leituras, gravações, RPCs, Storage, relatórios e Realtime não atravessam tenants.
- Integrar primeiro o cadastro de empresas/trabalhadores à recepção existente, evitando duplicar pessoas e cadastros.
- Entregar cada fase com testes, evidência e revisão antes de avançar à seguinte.

## 7. Sequência de entregas recomendada

| Etapa | Entrega | Critério de aceite |
|---|---|---|
| A | Auditoria e mapa de dependências | Inventário de telas, funções, tabelas, APIs e permissões revisado |
| B | Arquitetura e modelo de dados | ERD, dicionário de dados, matriz de acesso e plano de migrações aprovados |
| C | Empresas, unidades e contratos | CRUD, histórico, tenant isolation, importação e testes |
| D | Trabalhadores e vínculos | Histórico preservado, deduplicação e integração com recepção |
| E | Cargos, setores, GHE e riscos | Histórico e trilha de validação técnica |
| F | PCMSO e matriz de exames | Vigência, versões, periodicidade e aprovação profissional |
| G | Exames, prontuário e ASO | Fluxos completos, permissões clínicas e documentos assinados |
| H | Agenda, ordens e pendências | Fluxo operacional integrado à fila e profissionais |
| I | Faturamento e portal empresarial | Contrato → serviço realizado → medição → cobrança, com portal segregado |
| J | eSocial SST e BI | Leiautes vigentes, recibos/erros, indicadores e auditoria |

## 8. Critérios de pronto para qualquer fase

Uma fase não será considerada concluída apenas porque a tela abre. Deve cumprir:

- migração testada em PostgreSQL limpo;
- RLS e permissões validadas com papéis distintos;
- teste de isolamento com pelo menos duas clínicas;
- testes de sucesso, erro, concorrência e duplicidade;
- acessibilidade e responsividade básicas;
- logs sem dados sensíveis;
- auditoria de ações críticas;
- compatibilidade com fluxos já existentes;
- evidência de CI aprovado;
- documentação de operação e reversão.

## 9. Fontes normativas a validar durante a implementação

- NR-7 e texto vigente do PCMSO;
- NR-1 e Gerenciamento de Riscos Ocupacionais/PGR;
- regras e leiautes vigentes do eSocial SST (S-2210, S-2220, S-2221 quando aplicável e S-2240);
- LGPD e orientações aplicáveis da ANPD;
- requisitos de assinatura eletrônica e guarda documental aplicáveis aos documentos emitidos.

A validação normativa deve ocorrer no momento de implementar cada fluxo, usando fontes oficiais atualizadas e revisão de profissional habilitado. Este documento é um roteiro técnico-funcional, não um parecer jurídico ou médico.
