# Registro de mudanças

## 1.1.1 (2026-10-01)

- O app desktop não chama a statusline, e isso agora está confirmado. Caso real: numa sessão nova do app, com a `statusLine` no `settings.json` e o script instalado funcionando quando rodado à mão, nenhum arquivo de orçamento foi gravado depois de várias mensagens. No app, o orçamento vivo fica desligado. A exceção é o dado que uma sessão do terminal gravou antes: ele vale como piso, mas não se atualiza.
- O `orcamento.sh` dá o motivo certo. Ele reconhece o app pela variável `CLAUDE_CODE_ENTRYPOINT=claude-desktop`, que não é documentada e foi medida nesta sessão. Sem arquivo, diz que o app não chama a statusline. Com um arquivo gravado antes pelo terminal, avisa que o dado não se atualiza no app. O estado e o código de saída não mudam. Fora do app, o motivo genérico também passa a citar o app.
- Sem dado confiável de orçamento (`desligado`, `sem-dado`, ou `ok` com o aviso do app), a seiva grava a Retomada antes de cada leva de N2 ou N3. `restrito` e `parar` com o aviso seguem o limiar, porque o percentual é piso. Na tarefa da 1.1.0 houve duas quedas por limite de uso no meio de uma leva, e foi a Retomada que salvou o trabalho nas duas. Custo: uma escrita curta no `registro.md` por leva, sem agente a mais. O molde do registro cita o gatilho novo.
- O caso O3 mudou, entrou o caso O8 e há 9 casos novos em `testes/scripts/teste-orcamento.sh`.

Adiado: com `--tarefa` no app, o leitor termina com "retomar não gravado: a pasta do orçamento não existe". Esse "retomar" é o arquivo da barra, mas pode ser lido como falha da Retomada do registro. Suspeita do revisor (confiança 6), não medida.

Revisão: tarefa N1, construída pelo orquestrador. O diff foi revisado por um agente sonnet de contexto limpo, com as lentes de contrato e operação. Ele rodou o leitor em 7 ambientes isolados e achou 1 MÉDIO e 2 BAIXO, todos corrigidos: a regra misturava o aviso do app com `restrito`; o texto público dizia "sempre desligado"; faltava o custo. Corrigida também uma suspeita: o texto não dizia que a cautela some se a variável do app mudar. Independência: outro modelo e contexto limpo em relação ao orquestrador. Os ajustes depois da revisão não passaram por nova rodada.

## 1.1.0 (2026-09-30)

- Orçamento vivo, só no Claude Code: a statusline (scripts/statusline-orcamento.sh, que o usuário instala por cópia) grava o uso das janelas de 5 horas e de 7 dias e o contexto da sessão, e scripts/orcamento.sh lê esse arquivo antes de cada leva de agentes. Com 70% da janela de 5 horas, só N0 e N1 seguem, com a Retomada gravada antes; com 85%, parada limpa e sessão nova. Caso real: ao retomar sessões gigantes com "Tentar novamente", o cache foi recriado em quebras de 800 a 940 mil tokens (session-report, 30 dias, uma máquina, medido em 2026-09-29). Sem a statusline, nada muda.
- scripts/enxugar.sh: a saída longa de um comando fica inteira em saidas/ da pasta da tarefa, com os segredos de padrão conhecido mascarados (chave privada, tokens com prefixo, atribuição a nome de segredo); na conversa voltam o resumo e o caminho. Segredo sem padrão conhecido, como um cabeçalho Authorization ou um cookie, passa: por isso o enxugar recusa pasta versionada e grava em modo 600.
- scripts/checar-skill.sh ignora a pasta de trabalho da seiva (.seiva/ e .claude/) e passa a conferir a sintaxe dos testes em testes/scripts/.
- Papel invasor: varredura de segurança do código com relatório de conserto, conferido por um revisor antes de virar conserto. Entrou no commit 1a762b2 sem subir a versão; fica registrado aqui.
- Dez casos de teste novos e testes automáticos dos scripts em testes/scripts/.

Adiado: o papel invasor ainda não tem caso de teste em testes/casos.md.

Revisão: tarefa N3. O plano foi atacado pelo adversário e pelas lentes de segurança, operação e contrato (opus, contexto limpo; o profundo não está disponível na conta). No código, um verificador opus (outro modelo que os implementadores sonnet) e três rodadas de ataque ao diff (adversário e lente de segurança, opus). Cada rodada achou um caminho para a chave privada escapar da máscara, e todos foram corrigidos com teste. Independência: outro modelo em relação aos implementadores; mesmo modelo, de contexto limpo, em relação aos consertos do orquestrador. Sem revisão por outro provedor (Gemini e Codex ausentes).

## 1.0.0 (2026-09-26)

Primeira versão.

- Doze leis, com o projeto em primeiro lugar: as regras do repositório valem mais que as da skill.
- Fluxo de dez etapas (terreno, triagem, reconhecer, propor, atacar o plano, decidir, construir, verificar, atacar o código, entregar e aprender), dimensionado em quatro níveis de risco, com critérios de N3 que se verificam.
- Perfil do projeto montado a partir das fontes de lei, com impressão digital por arquivo ou por seção para reler só o que mudou.
- Cinco categorias de modelo (`script`, `rapido`, `padrao`, `forte`, `profundo`), uma regra única de escalada, descida de categoria quando o modelo está indisponível e mapa por harness.
- Cinco papéis (batedor, construtor, adversário, implementador, verificador) e seis lentes (segurança, dados, design, desempenho, operação, contrato).
- Contratos de ida e volta, formato de achado com confiança mínima 7, suspeita grave medida antes de descartar, tabela de severidade e critério de parada em três rodadas.
- Suporte a Claude Code, Codex CLI, Gemini CLI, Cursor e OpenCode, com modo sequencial para harness sem subagentes e revisão por outro provedor.
- Evolução por escape, descoberto na triagem da tarefa seguinte, com aprovação de quem desenvolve.
- Quatro scripts: impressão das fontes, pasta da tarefa com foto inicial da árvore, diff da tarefa com arquivo novo e checagem da própria skill.
- Trinta casos de teste.

Antes de publicar, a versão passou pelo próprio processo: um adversário (Opus, contexto limpo) e um ensaio de mesa num bug real do Ciclo Arboris (Sonnet). Os dezoito achados confirmados foram corrigidos nesta versão. Entre eles: revisor sem saída quando o modelo mais caro está indisponível; diff que perdia arquivo novo e pegava mudança de outra sessão; perfil invalidado a cada commit; escape que nunca era detectado; e clone velho aceito por ser um repositório git válido.

## Propostas recusadas

Nenhuma ainda.
