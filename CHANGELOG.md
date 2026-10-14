# Registro de mudanças

## 1.2.3 (2026-10-14)

Correções da 1ª revisão independente dos scripts da 1.2.0 à 1.2.2 (diff `96f8523^..e2a5bbb`, lentes contrato, operação e segurança): 15 itens, 2 ALTO e 7 MÉDIO confirmados, 4 BAIXO ou incertos, 2 falsos. Todos os confirmados e os adiados entraram.

- `julgar-pre.sh`: a severidade vale em qualquer caixa e com ou sem acento. Caso real (reproduzido): um `[A-2] Crítico` sumia sem aviso, e o Onde e o Defeito dele caíam por cima do achado anterior. O cabeçalho vale com qualquer prefixo antes do `[A-n]` (`1)`, `Achado`, negrito, crase). O que não fecha (cabeçalho sem severidade, bloco sem Onde nem Defeito, `Onde:` sem cabeçalho reconhecido) não conta, sai listado com `relatório:linha` e nunca cai por cima do achado anterior. Também lê `REFERÊNCIAS: A-n → ...` na linha do título, numera a partir só das linhas de achado que ele mesmo escreveu (um "A-9999" citado num Defeito não puxa mais a numeração), mascara os textos do revisor campo a campo (lente, Onde, Defeito, referência) e cria o `achados.md` com modo 600. A máscara por campo veio da 2ª rodada: mascarar o bloco inteiro deixava um `MINHA_KEY` no Defeito apagar a origem da linha, e um BEGIN de chave sem END no texto apagava todos os achados seguintes do `achados.md`.
- `orcamento-local.sh`: leitura do `/usage` errada tem volta. A linha de cada leitura nova diz a hora gravada e o comando para desfazer, e avisa quando o limite que ela dá passa do dobro ou fica abaixo da metade dos outros pontos. `--leituras` lista e `--descartar <hora|ultima>` apaga. Caso real: num ensaio do revisor, um 91% digitado como 19% deixava a janela seguinte em `ok` com a conta quase no limite, e nem o `--calibrar auto` apagava a leitura.
- `orcamento-local.sh`: calibração ilegível ou de forma desconhecida é guardada como `calibracao.json.invalido-<epoch>-<pid>` e refeita, com aviso em todas as saídas, inclusive `--leituras`, `--descartar` e erro do `--calibrar`. Antes era regravada por cima em silêncio, ou deixava o estado em `desligado` com a causa errada em toda execução. A leitura da 1.2.0 (campo `manual`) vira a 1ª leitura.
- `orcamento-local.sh`: duas execuções ao mesmo tempo esperam uma pela outra (`flock`); `.trava` que não se abre deixa seguir sem trava, com aviso, em vez de dizer que outra execução a segura. Antes, uma execução lenta apagava a leitura que outra tinha acabado de gravar (provado pelo revisor; o teste novo reprova a versão antiga).
- `orcamento-local.sh`: transcript desta sessão com resposta do modelo e nenhum registro de uso reconhecível dá `desligado` ("o formato do Claude Code pode ter mudado"), em vez de `ok` com 0%. Resposta de erro da API (529 e afins) não conta como resposta, para uma sessão que começou com erro não acusar formato.
- `orcamento-local.sh`: a janela de contexto de 1 milhão se prova pela própria sessão acima de 200 mil. O histórico do modelo só vale por 30 dias e sai marcado como `janela deduzida`. Medido em 2026-10-14: o transcript grava o mesmo nome de modelo nas janelas de 200 mil e de 1 milhão (nem `message.model` nem `requestedModel` trazem o `[1m]`). O `contexto_max` da 1.2.2 é migrado.
- `orcamento-local.sh`: com acento no caminho do projeto, a sessão deduzida procura a pasta com um hífen por caractere e, de reserva, um por byte.
- `ficha-tecnica.sh`: citação com caminho absoluto de fora, com `..` ou por link que sai do repositório não é lida, e aparece como pulada, "fora do repositório". A chave privada é trocada linha a linha, mantendo a numeração, antes de cortar o trecho. Além do corpo da chave em claro que o revisor apontou, o teste novo achou outro defeito: um trecho com o BEGIN e sem o END engolia todos os trechos seguintes do `trechos.md`.
- `progresso.sh`: `pendentes` deixa de listar tarefa com a etapa 9 `pulada`, como o `conferir` já fazia.
- Casos C14, C15, O12 e O13 em `testes/casos.md`; 51 casos novos em `teste-orcamento-local.sh`, 28 em `teste-julgar-pre.sh`, 10 em `teste-ficha-tecnica.sh` e 1 em `teste-progresso.sh`. Rodada contra os scripts da 1.2.2, a suíte nova reprova 51 casos. Os outros 39 cobrem o que a 1.2.2 já fazia certo e a 1ª versão desta correção quebrou: os 8 casos de prefixo antes do `[A-n]` passam na 1.2.2 e reprovavam a correção da 1ª rodada (regressão achada pela 2ª revisão, A-16).

Limitações que ficam: a janela deduzida ainda erra para quem alterna entre 200 mil e 1 milhão no mesmo modelo dentro de 30 dias (`SEIVA_JANELA_CONTEXTO` resolve); a regra do Claude Code para nome de pasta com caractere fora do ASCII e para caminho muito longo não foi medida; sem `flock` (macOS sem util-linux) a trava não existe, e a linha avisa; o aviso de formato só olha o transcript desta sessão e não pega a troca do campo `type`.

Revisão: duas rodadas de subagente de contexto limpo, em outro modelo (Sonnet; o construtor foi Opus). A 1ª revisou os scripts da 1.2.0 à 1.2.2 (250.709 tokens, 15 itens). A 2ª revisou a correção (202.887 tokens): os 13 achados confirmados ou adiados ficaram mitigados, e ela achou 3 defeitos novos, dois ALTO no `julgar-pre.sh` (um deles regressão da própria correção) e um MÉDIO no `orcamento-local.sh`, além de 2 suspeitas que também entraram. A correção desses 3 e das 2 suspeitas não teve revisor: pela regra do N2, só CRÍTICO abre 3ª rodada. Foi conferida pelos testes escritos antes do conserto (cada um reprovou a versão anterior) e pelos dois relatórios reais da revisão, que o `julgar-pre.sh` lê com 15 e 3 achados e 12 referências, sem aviso falso.

## 1.2.2 (2026-10-13)

- Leitura do `/usage` como âncora. Caso real: a 2ª leitura (90% às 11:21, contra 73% às 11:04) não fechou com a 1ª em nenhum peso não negativo para a escrita de cache, com a leitura de cache entre 0,01 e 0,1. O mais provável é gasto na janela que os transcripts não veem, como o chat do claude.ai. Com uma leitura dentro da janela aberta, o percentual parte do valor lido, e só o gasto depois dela é estimado, sobre o menor limite entre os pontos. Logo depois de calibrar, a linha deu 93%: os 90% lidos mais 3% estimados.
- O "Em aberto" da 1.2.1 fica sem medida: as duas leituras não permitem isolar o peso da escrita de cache.
- 3 casos novos e 5 ajustados em `teste-orcamento-local.sh`.

Revisão: nenhuma revisão independente; feita pelo orquestrador, com os testes automáticos.

## 1.2.1 (2026-10-13)

- Calibração por pontos. Caso real: na primeira conferência com o `/usage`, a regra da 1.2.0 (mediana dos 20 limites batidos mais recentes) dava cerca de 40% quando o oficial marcava 73%, e nenhum peso testado explicou a diferença. Agora cada leitura do `/usage` também vale como ponto (`--calibrar <pct> --em <hora do relatório>`, contando só o gasto da janela até aquela hora), e o limite é o menor dos 5 pontos mais recentes.
- Pausa longa também é parada: com contexto acima de 200 mil, a entrega avisa que voltar depois de 1 hora recria o cache inteiro. Caso real: na mesma sessão, a volta de uma pausa de 70 minutos gravou 373.540 tokens de cache numa resposta só.
- Caso R5 novo e O11 reescrito; 11 casos novos em `teste-orcamento-local.sh`.

Em aberto: com a leitura de 73% como base, aquela resposta levou a estimativa a mais de 100% sem a conta bater no limite: a escrita de cache pesa menos na conta oficial do que o peso 1 do script. Uma 2ª leitura do `/usage` mede quanto.

Revisão: nenhuma revisão independente; feita pelo orquestrador, com os testes automáticos.

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
