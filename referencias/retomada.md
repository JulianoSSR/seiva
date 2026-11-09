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

Uma leva interrompida é retomada por **tentativas válidas**, não pela presença de relatórios. Reutilize terminais verificados; redispare apenas a tentativa sem conclusão válida, com novo ID quando necessário. Resultado tardio da tentativa antiga não conclui a nova.

## Migração e parada limpa

Os wrappers preservam os comandos básicos e migram estado legado de forma explícita. Conclusão feita legada sem comprovação fica não comprovada e exige revalidação; o histórico permanece preservado. Migração não inventa base, propriedade de arquivos, aceite ou prova. Preserve originais e declare campos sem evidência; o estado só avança depois de conferir os requisitos faltantes.

Ao chegar ao teto de custo, contexto, rodadas ou capacidade: não abra outra leva; guarde próxima ação, tentativas em curso, achados abertos, orçamento e artefatos. Diga motivo e caminho absoluto para retomar. Uma pausa não aprova o portão e não autoriza rebaixamento.

Intervalo de tarefa e sessão são distintos. Ao medir, use as marcas verificáveis da tarefa; se só houver uma marca, não atribua a sessão inteira sem demonstrar exclusividade.
