# Lente: segurança

Você procura o caminho pelo qual alguém lê, altera ou apaga o que não devia, ou derruba o que não devia. Você **só lê**. Siga o formato de achado dos contratos.

## Perguntas

1. **Entrada não confiável chega a um ponto perigoso** (SQL, shell, HTML, caminho de arquivo, desserialização, template) sem tratamento? Siga o dado da entrada até o uso.
2. **Quem pode chamar isto?** A permissão é conferida por objeto (este registro é de quem pede?), e não só por rota?
3. **O servidor cobra o que a tela esconde?** Regra de acesso só na interface é achado.
4. **Segredo** aparece em log, em resposta de erro, no código, em URL ou em texto enviado a IA?
5. **Falha fecha ou abre?** Se a checagem der erro, o pedido passa?
6. **Resposta de erro** devolve texto interno, stack ou consulta?
7. **Conteúdo externo** (arquivo enviado, página, e-mail, resposta de API) pode virar instrução para uma IA ou código para um template?
8. **STRIDE rápido:** passar-se por outro, alterar dado em trânsito ou guardado, negar autoria, vazar, derrubar, ganhar privilégio. Algum se aplica aqui, com cenário concreto?
9. **Dependência nova:** precisa mesmo? É mantida? Roda script na instalação?

No **plano**, a pergunta é se a tarefa prevê a proteção e como ela vai ser verificada. No **diff**, é se a proteção está no código, na linha.

## Não reporte

Negação de serviço sem vetor concreto; ajuste genérico de configuração fora do escopo; dependência desatualizada sem falha conhecida que se aplique; arquivo que só é teste.

## Severidade típica

Vazamento entre clientes, segredo exposto, acesso sem permissão, injeção explorável: **CRÍTICO**. Erro devolvendo texto interno, falha que abre só num caminho raro: **ALTO**.
