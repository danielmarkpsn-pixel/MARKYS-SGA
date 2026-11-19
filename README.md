# MARKYS SGA — Sistema de Gestão de Atendimento

O MARKYS SGA possui dois modos separados:

- **Modo local:** aplicação HTML/PowerShell para uso na rede local, com dados locais em arquivos do servidor.
- **Modo online:** aplicação Vite em `online/`, publicada pelo Vercel e conectada exclusivamente ao Supabase `vibybosdqavejvqsuvph`.

## Acesso online
- Aplicação: https://markyssga.vercel.app/
- Recepção: https://markyssga.vercel.app/recepcao
- Profissional: https://markyssga.vercel.app/profissional
- Sala de espera pública: https://markyssga.vercel.app/sala
- Administração Master: https://markyssga.vercel.app/master

## Modo local
Execute `INICIAR-MARKYS-SGA.bat` no Windows. O servidor local usa a porta 2222 e mantém os dados na pasta de trabalho local. O modo local não inicializa nenhum cliente Supabase.

## Arquitetura online
- Frontend Vite em `online/`.
- Supabase Auth para login e recuperação de senha.
- PostgreSQL com RLS habilitada e forçada.
- Edge Function `master-users` para administração pelo Master.
- Tela pública de chamadas com dados minimizados.
- Documentos PDF em bucket privado.

## Desenvolvimento
Dentro de `online/`:
1. Copie `.env.example` para `.env.local`.
2. Preencha as duas variáveis públicas do Supabase.
3. Execute `npm install`, `npm run check` e `npm run build`.

Nunca coloque chaves secret/service_role no frontend, em `VITE_*` ou no Git.
