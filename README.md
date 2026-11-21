# MARKYS SGA — Sistema de Gestão de Atendimento

O **aplicativo oficial do MARKYS SGA** é a aplicação HTML da raiz do repositório (./), baseada no fluxo operacional do FAVMED e com identidade visual própria do MARKYS SGA.

## Produção

- **Vercel:** projeto `markyssga`, Root Directory `./`, branch `main`

## Identidade e funcionamento

A sala de espera não exige login e recebe somente a fila de chamadas do dia. Documentos e dados privados dos pacientes não são retornados por essa API.

## Supabase e preservação de dados

## Modo local

Execute `INICIAR-MARKYS-SGA.bat` no Windows. O servidor local usa a porta 2222 e mantém os dados locais na pasta de trabalho. O modo local não inicializa o cliente Supabase.

## Pasta `online/`

A pasta `online/` contém a implementação web anterior e permanece no repositório como histórico/referência. **Ela não é o diretório de publicação da produção.** Não alterar o Root Directory da Vercel para `online/`.

## Segurança

- Nunca colocar chaves `service_role` ou secret no frontend ou no Git.
- A chave publicável pode ser usada no navegador; a API da sala usa somente a chave publicável.
- A autorização administrativa é feita pela Edge Function `master-users`, que valida o token e o perfil Master ativo.
