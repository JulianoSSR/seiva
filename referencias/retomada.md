# Retomada: confira antes de aproveitar

A sessão é descartável; a tarefa guarda contexto, base, escopo, tentativas e evidência. Pacotes, estado e relatórios de execução são privados e ignorados pelo git.

## Estado canônico

`estado.json` é a fonte de verdade. Guarda `schema`, `task_id`, caminho, repositório, base, escopos, etapas, dependências e tentativas. `progresso.md` é projeção gerada, não arquivo para editar à mão. `contexto-tarefa.md` resume objetivo, próxima ação, bloqueios e caminhos, sem substituir o JSON.

Uma etapa feita só é reutilizada quando os artefatos e as dependências continuam válidos. Hash alterado invalida a prova anterior e pede julgamento direcionado; não exige repetir toda a tarefa.

## Criar e delimitar

```bash
bash scripts/nova-tarefa.sh <pasta-de-trabalho> <slug>
bash scripts/base-tarefa.sh <tarefa> --exclusive caminho/arquivo outro/arquivo
```

A primeira chamada registra base e foto da árvore, preservando índice e alterações locais. A segunda adquire o escopo antes da edição e confere a base. Base e snapshot não provam autoria; arquivo alterado por outra sessão não passa a pertencer à tarefa. Conflito exige combinar a divisão.

`diff-tarefa.sh <tarefa> <arquivos>` usa a base e o escopo registrados. Em legado sem base confiável, interrompa para reconstruir a proveniência com o responsável; nunca substitua a base por HEAD atual silenciosamente.

## Registrar uma tentativa

```bash
python3 scripts/estado_tarefa.py attempt-start <tarefa> <id> <agente> <pacote> <relatorio>
python3 scripts/estado_tarefa.py attempt-complete <tarefa> <id> concluido --artifact <relatorio> --evidence '<comando e resultado>'
python3 scripts/estado_tarefa.py attempt-check <tarefa> <id>
```

Etapa de agente exige --attempt com terminal concluído válido e hashes dos artefatos. Etapa mecânica exige --evidence explícita e artefatos não vazios. Marcar feita apenas com texto de status não conclui. Grave pacote e próxima ação antes do disparo. O terminal vincula tarefa, tentativa, artefato, hash e evidência. O relatório exige conteúdo e última linha exata `<!-- seiva:fim TASK_ID ATTEMPT_ID -->`, produzida pelo agente ao finalizar com os IDs do pacote. Não acrescentar depois para aproveitar relatório velho; sem marcador válido, não conclui. O orquestrador confere o resultado do agente; não basta o agente declarar sucesso. Relatório velho, de tentativa anterior, ausente ou modificado não valida a tentativa atual.

## Conferir e retomar

```bash
bash scripts/progresso.sh <pasta-de-trabalho> pendentes
bash scripts/progresso.sh <tarefa> conferir
bash scripts/progresso.sh <tarefa> marcar <etapa> feita <artefatos> --attempt <id>
bash scripts/progresso.sh <tarefa> marcar 7 feita provas.txt --evidence 'comando executado: exit 0, resultado em provas.txt'
```

Sem caminho, liste pendentes; com várias tarefas, pergunte qual. Leia contexto curto e saída do conferir. Abra regras atuais exigidas pelo projeto e fontes necessárias à próxima ação. Não releia todo o histórico nem dispense leitura obrigatória do projeto.

### Tentativa cortada por limite ou sessão fechada

```bash
python3 scripts/estado_tarefa.py attempt-ping <tarefa> <id>                       # sinal de vida, a cada etapa do agente
python3 scripts/estado_tarefa.py attempt-sweep <tarefa> [--stale-minutos 15]      # na retomada: running sem sinal vira interrompida
python3 scripts/estado_tarefa.py attempt-interrupt <tarefa> <id> --motivo 'limite de 5h' [--tokens N]
python3 scripts/estado_tarefa.py attempt-start <tarefa> <novo-id> <agente> <pacote> <relatorio> --retoma <id-interrompida>
```

**Automático.** `progresso.sh <tarefa> conferir` já faz a varredura sozinho (só grava se achar algo) e `attempt-sweep` existe para chamá-la isolada. Ao abrir uma leva, suba o vigia em segundo plano com a ferramenta do harness (no Claude Code, `Bash` com `run_in_background` ou `Monitor`):

```bash
python3 scripts/estado_tarefa.py attempt-watch <tarefa> --intervalo 60 --duracao 3600
```

Ele varre a cada intervalo, imprime `INTERROMPIDA <id>` quando acha uma tentativa sem sinal e termina sozinho quando não há `running` ou a duração acaba (e então avisa que ficou sem vigia). Não é daemon, não instala hook e morre com a sessão: se a sessão fecha, a próxima retomada recupera pelo `conferir`. Sinal de vida é o `attempt-ping` **ou** a última gravação do relatório.

Registro `running` não prova processo vivo. Ao retomar, rode `attempt-sweep` antes de ler relatório ou redisparar: tentativa sem sinal por mais de 15 minutos vira `interrompida`, com os tokens já gastos anotados (desconhecidos quando a ferramenta não mostra, nunca zero). `conferir` lista as interrompidas e falha enquanto houver `running` sem sinal. Redisparar o mesmo trabalho exige `--retoma <id>`, decisão explícita que fecha a tentativa antiga como substituída; sem ela o `attempt-start` recusa.

**Relatório de agente interrompido.** Se o relatório está completo e a última linha é o marcador `<!-- seiva:fim TASK_ID ATTEMPT_ID -->` com os IDs certos, vale: o agente só o escreve ao terminar, então a morte veio depois da entrega. O orquestrador fecha com `attempt-complete ... concluido`, e o estado grava `completed_after_interruption`. Sem marcador, truncado ou de outra tentativa, não vale e a decisão é redisparar com `--retoma` ou fechar como `parcial`. O orquestrador nunca acrescenta o marcador.

**Etapa interrompida.** `marcar N 'interrompida: motivo'` registra a etapa cortada; ela não é feita nem pulada e continua sendo o ponto de retomada.

### Contexto, modelo e paralelismo

`attempt-start` aceita `--categoria` (script, rapido, padrao, forte, profundo), `--modelo` e `--contexto-tokens` (tamanho do que o agente herda; ausente fica registrado como não informado). Pacote mais contexto acima de 150 mil tokens recusa o disparo: divida a tarefa ou grave o contexto curto e abra outra sessão; `--acima-do-limite 'motivo'` autoriza e fica registrado. Mais de 3 tentativas `running` ao mesmo tempo recusam (`--max-paralelo` muda, com motivo). O tamanho do pacote é estimado por bytes, não é contagem oficial.

### Medição da tarefa

```bash
python3 scripts/estado_tarefa.py usage antes  <tarefa> --fonte '/usage da sessão' --entrada N --saida N --cache-leitura N --modelo M
python3 scripts/estado_tarefa.py usage depois <tarefa> --fonte '/usage da sessão' --entrada N --saida N --cache-leitura N --modelo M
```

O `depois` calcula a diferença só dos campos medidos nos dois lados e imprime a linha `FECHAMENTO` para o registro. A fonte é obrigatória. O `/usage` da sessão inclui outras tarefas se a sessão não foi exclusiva; diga isso na linha.

Uma leva interrompida é retomada por **tentativas válidas**, não pela presença de relatórios. Reutilize terminais verificados; redispare apenas a tentativa sem conclusão válida, com novo ID quando necessário. Resultado tardio da tentativa antiga não conclui a nova.

## Migração e parada limpa

Os wrappers preservam os comandos básicos e migram estado legado de forma explícita. Conclusão feita legada sem comprovação fica não comprovada e exige revalidação; o histórico permanece preservado. Migração não inventa base, propriedade de arquivos, aceite ou prova. Preserve originais e declare campos sem evidência; o estado só avança depois de conferir os requisitos faltantes. `conferir` só lê a tarefa legada; a primeira marcação cria `estado.json` e guarda o original em `progresso.legado.md`. `PROXIMA` aponta a primeira etapa que não está feita nem pulada, e as legadas sem prova aparecem à parte, para revalidar sem refazer. Etapa `pulada` exige motivo (`pulada: motivo`).

**Tarefa criada sem as etapas iniciais marcadas** (estado nascido de um `attempt-start`, com trabalho já feito fora dele): marque cada etapa com `--retroativa --evidence 'onde e quando foi feita'` e os artefatos reais. A marca vale como prova de evidência, não de tentativa, aparece como RETROATIVA no `conferir` e perde a validade se o artefato mudar. O `conferir` avisa quando há tentativas e a etapa 0 segue pendente. A migração não inventa o que não tem evidência.

Ao chegar ao teto de custo, contexto, rodadas ou capacidade: não abra outra leva; guarde próxima ação, tentativas em curso, achados abertos, orçamento e artefatos. Diga motivo e caminho absoluto para retomar. Uma pausa não aprova o portão e não autoriza rebaixamento.

Intervalo de tarefa e sessão são distintos. Ao medir, use as marcas verificáveis da tarefa; se só houver uma marca, não atribua a sessão inteira sem demonstrar exclusividade.
