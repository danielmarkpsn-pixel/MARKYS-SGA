# MARKYS SGA — baseline e migrações do banco

## Projeto de destino
- Supabase: `MARKYS SGA`
- Project ref: `vibybosdqavejvqsuvph`
- Estado inicial verificado: projeto ativo, schema `public` sem tabelas e histórico de migrações vazio.

## Estratégia
Este é um banco novo e independente. Não há histórico remoto a preservar nem dados de pacientes a migrar. O schema será construído somente com migrações versionadas neste repositório.

1. `20261028134244_markys_sga_profiles_baseline.sql`: cria `private`, tabela `profiles`, RLS e leitura do próprio perfil.
2. `20261028160000_restore_service_role_profiles_privileges.sql`: concede privilégios administrativos à role de serviço.
3. `20261029150000_operational_foundation.sql`: cria pacientes, profissionais, salas, atendimentos, exames, políticas RLS, grants e gatilhos.
4. Migrações incrementais seguintes: integridade de timestamps, painel público sanitizado, status de chamada, campos de recepção, documentos, múltiplas salas, permissões e Realtime.

Migrações de fila JSON legada e buckets de mídia não usados pela aplicação Vite não devem ser aplicadas automaticamente. A aplicação online usa as tabelas normalizadas e o bucket privado `patient-documents`.

## Regras
- Aplicar migrações em ordem e registrar cada uma no histórico remoto.
- Não aplicar SQL legado de fila JSON no banco operacional sem revisão específica.
- Não criar usuários Master com senha padrão ou credenciais no código.
- Não inserir dados reais até concluir os testes de autorização com contas sintéticas.
- Toda tabela exposta no schema `public` deve ter RLS habilitada e políticas revisadas.
