# MARKYS SGA — Sistema de Gestão de Atendimento

O **aplicativo oficial do MARKYS SGA** é a aplicação HTML da raiz do repositório (./), baseada no fluxo operacional do FAVMED e com identidade visual própria do MARKYS SGA.

## Produção

- **Vercel:** projeto `markyssga`, Root Directory `./`, branch `main`.
- **Aplicação:** https://markyssga.vercel.app/
- **Recepção:** https://markyssga.vercel.app/
- **Painel profissional:** https://markyssga.vercel.app/consultorio.html
- **Sala de espera pública:** https://markyssga.vercel.app/sala/
- **Administração Master:** https://markyssga.vercel.app/admin-logins.html
- **Supabase exclusivo do SGA:** `vibybosdqavejvqsuvph`.

## Identidade e funcionamento

O objetivo é manter as telas, os fluxos, as regras e os recursos operacionais do aplicativo de referência. As diferenças de produto devem ficar restritas à marca, aos nomes e à identidade visual MARKYS SGA (azul-marinho e branco).

A integração online da raiz usa:
- Supabase Auth para login, sessão e recuperação de senha.
- Perfil ativo em `public.profiles` para autorização de Master, Recepção e Profissional.
- Fila operacional em `app_private.markys_sga_queue_state`, com RPCs protegidas e controle de concorrência.
- Supabase Realtime para avisos de atualização da fila.
- Bucket privado `markys-sga-documents` para documentos.
- Bucket separado `markys-sga-media` para fotos e vídeos exibidos na sala pública.
- API `/api/public-queue` para entregar somente os campos necessários à tela pública.

A sala de espera não exige login e recebe somente a fila de chamadas do dia. Documentos e dados privados dos pacientes não são retornados por essa API.

## Supabase e preservação de dados

Este repositório usa exclusivamente o Supabase do MARKYS SGA. O projeto FAVMED é apenas referência de código e comportamento; seus dados, chaves e serviços não são usados pela aplicação MARKYS.

As migrações da integração da raiz estão em `supabase/migrations/`. Elas acrescentam a fila e o armazenamento específicos do SGA, sem substituir as tabelas relacionais existentes de pacientes, atendimentos, exames, profissionais, perfis ou salas. A rotina diária remove somente snapshots antigos da fila JSON; nunca apaga pacientes, atendimentos ou exames das tabelas relacionais.

## Modo local

Execute `INICIAR-MARKYS-SGA.bat` no Windows. O servidor local usa a porta 2222 e mantém os dados locais na pasta de trabalho. O modo local não inicializa o cliente Supabase.

## Pasta `online/`

A pasta `online/` contém a implementação web anterior e permanece no repositório como histórico/referência. **Ela não é o diretório de publicação da produção.** Não alterar o Root Directory da Vercel para `online/`.

## Segurança

- Nunca colocar chaves `service_role` ou secret no frontend ou no Git.
- A chave publicável pode ser usada no navegador; a API da sala usa somente a chave publicável.
- A autorização administrativa é feita pela Edge Function `master-users`, que valida o token e o perfil Master ativo.
