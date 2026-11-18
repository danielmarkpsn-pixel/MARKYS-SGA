# MARKYS SGA - SISTEMA DE GESTAO DE PACIENTES


   - Recepção: `http://IP:PORTA/`
   - Sala de espera: `http://IP:PORTA/?painel=1`
   - Profissional: `http://IP:PORTA/consultorio`
4. Para acesso remoto, os dispositivos devem estar na mesma rede local. Mantenha o servidor aberto.

## Recursos incorporados do fluxo MARKYS
- Cadastro com múltiplos serviços por paciente e consultório opcional.
- edição de nome e serviços, prioridade e busca.
- Painel profissional separado: “Chamar na sala”, “Atender”, “Cancelar chamado” e “Liberar”.
- Status por serviço; o paciente só é concluído quando todos os serviços forem liberados.
- Horário de saída, retenção de atendidos na recepção e opção para reabrir.
- Tela pública com chamada atual e próximos pacientes, sem mostrar atendimentos concluídos.
- Anúncio por voz com seleção automática/manual de voz disponível, teste e repetição.
- Exportação CSV, relatório PDF A4 vertical e backup JSON.
- Atualização automática entre recepção, painel profissional e sala de espera.
- Chamadas da recepção para Recepção 1, 2 e 3; marcador de ASO pendente; anexos PDF opcionais de até 10 MB.
- Exames específicos adicionais de laboratório e exames complementares.




Crédito: Desenvolvido por Daniel Marques via IA.


## Prévia web da interface local (Vercel)


- Recepção: `/`
- Sala de espera: `/sala`
- Painel profissional: `/consultorio`
- Em hospedagem estática, a fila usa `localStorage` do navegador para permitir testar o fluxo entre páginas abertas no mesmo navegador.
- Essa prévia **não sincroniza dados entre dispositivos**, não oferece autenticação e não deve ser usada para atendimentos reais. Upload de documentos e mídia depende de uma API ainda não portada.
- No servidor PowerShell local, a aplicação continua usando as rotas locais existentes.

A etapa seguinte é integrar a autenticação e a persistência compartilhada no Supabase, mantendo os arquivos originais da interface e respeitando as políticas RLS já existentes.
