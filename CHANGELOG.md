# Registro de mudanças

## 1.2.0 (2026-10-13)

Objetivo: o mesmo processo (revisão independente, prova, segurança) com menos tokens, e funcionando no app desktop do Claude Code, onde a statusline não roda. Plano de origem: `plano-execucao-otimizacao-seiva.md`, do autor.

- **Orçamento vivo pelos transcripts** (`scripts/orcamento-local.sh`). Lê os transcripts que o terminal e o app desktop gravam em `~/.claude/projects/`, estima o uso da janela de 5 horas e mede o contexto da sessão. Grava no formato do `orcamento.json` e passa a decisão ao `orcamento.sh`, com os mesmos limiares. Caso real: a seiva roda quase sempre no app desktop, onde o orçamento vivo da 1.1 ficava desligado. Medido nesta máquina: a 1ª varredura de 30 dias leva cerca de 5 segundos, e as seguintes, menos de 1.
  - Calibração automática: o transcript guarda "You've hit your session limit · resets <hora>", e o total de cada janela que bateu no limite vale 100%. Calibração manual por `--calibrar <percentual do /usage>`.
  - O peso padrão da leitura de cache é 0,01, e não 0,1 como o plano propunha: nas 53 vezes que a conta do autor bateu no limite, 0,01 deixou o total das janelas com dispersão de 28%, e 0,1, com 42%. `PESO_CACHE_LEITURA` muda o peso.
  - A janela de contexto vem do histórico do modelo (1 milhão para o que já passou de 200 mil), porque as sessões do autor passam de 600 mil tokens de contexto.
  - `orcamento.sh` aceita os campos novos `fonte`, `cinco_horas.motivo` e `contexto.desta_sessao`; com `fonte: "jsonl"` não dá os avisos de statusline nem de app desktop. Contexto desta sessão em 70% ou mais vira `parar`. Arquivo da statusline lido à mão se comporta como antes.
- **Retomada barata** (`scripts/progresso.sh`, `moldes/progresso.md`, `moldes/contexto-tarefa.md`, `referencias/retomada.md`). Cada tarefa nasce com o checklist das etapas, com hash dos artefatos, e um contexto de até 1.500 tokens. A sessão nova lê só os dois; etapa feita não roda de novo; leva que caiu redispara só quem não entregou. No ensaio automático, a retomada de uma N2 caída no meio da leva do plano lê cerca de 700 tokens. A seção Estado do registro foi para o `progresso.md`, e a Retomada do registro virou uma linha por parada.
- **Revisores sem o arquivo inteiro** (`scripts/ficha-tecnica.sh`). Fichas por arquivo (importa, exporta, assinaturas, linhas-chave) e trechos de ±10 linhas em volta de cada citação do batedor, por expressão regular, sem modelo, com segredo mascarado. Medido em arquivos reais do Ciclo Arboris: um arquivo de rotas de 73 KB vira uma ficha de 6 KB, e um documento de 451 KB, uma de 2 KB. Só o implementador lê inteiros os arquivos que vai mudar.
- **Portões enxutos** (`scripts/julgar-pre.sh`). Achados numerados com ID estável na tarefa e agrupados por lugar antes do julgamento; na conversa fica uma linha por achado. Teto de 2 rodadas por portão em N2 e 3 em N3. Em N2, o portão do código é o adversário em uma rodada, com lente só para sinal novo no diff, achado do plano conferido pelo ID em uma linha e 2ª rodada só por CRÍTICO.
- **Triagem e modelos.** Dúvida entre dois níveis vira uma pergunta de sim ou não. Pedido de rigor sem superfície sensível vale N1 com dois revisores. Em N2, construtor e adversário vão para `padrao`.
- **Aprendizado.** O registro anota as correções do usuário (`C-n`), que viram proposta no fechamento. A linha de `aprendizado.md` compara o custo real com o orçado e soma a sessão do orquestrador aos subagentes.
- Casos novos: T8, T9, C11 a C13, M3, O9 a O11, R1 a R4, E2 e E3; O1 a O8 e C4 atualizados. Testes automáticos novos: `teste-orcamento-local.sh`, `teste-progresso.sh`, `teste-ficha-tecnica.sh` e `teste-julgar-pre.sh`.

Fora desta versão, de propósito:
- O `sqz` não substituiu o `enxugar.sh` (motivos em FONTES.md): ele devolve à conversa a saída inteira, só que encolhida, enquanto o enxugar guarda a saída e devolve até 51 linhas; a referência de 13 tokens aponta para conteúdo que o subagente de contexto limpo nunca viu; e ele não mascara segredo.
- O claude-recall não foi adotado: instala hook e injeta regra em toda sessão. A captura de correções ficou no registro da tarefa.
- Gateways e roteadores (OmniRoute, LiteLLM, RouteLLM e outros) e cache semântico ficaram para uma fase opcional de infraestrutura, não feita.

Custo: a cada leva, uma chamada do `orcamento-local.sh` (menos de 1 segundo, uma linha na conversa) e uma edição de 3 linhas no `contexto-tarefa.md`; por etapa, uma chamada do `progresso.sh`; por rodada, uma do `julgar-pre.sh`. Em N2, a troca de `forte` para `padrao` no construtor e no adversário reduz a independência do portão do plano para `mesmo-modelo-contexto-limpo`. A meta do plano, N2 com até 40% dos tokens de antes, ainda não foi medida: depende das tarefas reais anotadas com a 1.2.0.

Revisão: nenhuma revisão independente. A versão foi escrita e testada pelo orquestrador (Opus) sozinho, sem enxame e sem revisor de contexto limpo. Os scripts têm teste automático e o `orcamento-local.sh` rodou no app desktop; as regras de texto só têm os casos de `testes/casos.md`, que ainda não foram rodados numa sessão real.

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
