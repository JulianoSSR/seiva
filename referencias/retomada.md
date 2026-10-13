# Retomada: a sessão é descartável, a tarefa não

O estado de uma tarefa mora em arquivo, na pasta dela. A sessão do orquestrador pode cair por limite de uso, por contexto cheio ou porque o app fechou, e nada se perde nem se paga duas vezes. Funciona igual no terminal e no app desktop: são arquivos e scripts, sem statusline e sem hook.

## Os dois arquivos

- **`progresso.md`**: o checklist das etapas 0 a 9, escrito só pelo `scripts/progresso.sh`. Etapa feita leva o hash dos artefatos dela.
- **`contexto-tarefa.md`**: objetivo, nível e motivo, etapa atual, a próxima ação em até 3 linhas, as decisões que esperam o usuário, os arquivos-chave e o orçamento gasto. Alvo: até 1.500 tokens; o `progresso.sh conferir` estima o tamanho e avisa quando passa.

O `registro.md` continua sendo o histórico da tarefa (triagem, decisões, agentes, arquivos entregues). Para retomar, a sessão nova não o lê. Cada fato fica num lugar só: a próxima ação no contexto, o estado das etapas no progresso.

## Quando escrever

| Momento | O que fazer |
|---|---|
| Fechou uma etapa | `progresso.sh <pasta> marcar <n> feita <artefatos>`; reescreva o `contexto-tarefa.md` |
| Antes de cada leva | `orcamento-local.sh --tarefa <pasta>`; grave o pacote de cada agente em `relatorios/pacote-<papel>-r<n>.md`; atualize só a Próxima ação: quem vai ser disparado e o relatório que cada um deve deixar |
| Rodada nova num portão | `progresso.sh <pasta> marcar <n> "em-curso: rodada 2/2"` |
| Parada limpa | os dois arquivos em dia e uma linha na seção Retomada do `registro.md` |

A atualização antes da leva é uma edição de 3 linhas, não a reescrita do arquivo.

## Parada limpa

Os gatilhos vêm do `orcamento-local.sh`, que roda antes de cada leva: `parar` pela janela de 5 horas (85%, ou o aviso de limite batido) ou pelo contexto desta sessão em 70% da janela do modelo. A parada acontece na fronteira entre levas: o agente em curso termina.

1. Reescreva o `contexto-tarefa.md`, com a Próxima ação dizendo o que a sessão nova faz primeiro, e marque no `progresso.md` a etapa em curso.
2. Escreva uma linha na seção Retomada do `registro.md`: a data, o motivo e "retomar por contexto-tarefa.md".
3. Pare e diga ao usuário, com o caminho absoluto:
   - parada por contexto: `abra uma sessão nova agora e diga: retome <pasta>/contexto-tarefa.md`;
   - parada pela janela de 5 horas: `abra uma sessão nova depois das HH:MM e diga: retome <pasta>/contexto-tarefa.md`, com a hora que a linha do orçamento traz.

Nunca sugira "Tentar novamente" numa sessão grande. Depois da pausa, retomar a mesma sessão recria o cache do contexto inteiro: as maiores quebras medidas foram de 800 a 940 mil tokens (session-report, 30 dias, uma máquina, 2026-09-29). Parar com 70% de contexto também evita a compactação automática, que relê a conversa inteira para resumi-la e perde referências pelo caminho.

## Retomar

Vale para "retome <caminho>", para "continue" ou "tentar novamente" com tarefa em curso, para a sessão que voltou de pausa por limite de uso e para contexto compactado. O usuário não precisa pedir: o orquestrador percebe a situação e segue estes passos sozinho.

1. Sem caminho, rode `progresso.sh <pasta-de-trabalho> pendentes`. Com uma tarefa na lista, siga com ela. Com mais de uma, pergunte qual, numa pergunta só.
2. Leia o `contexto-tarefa.md` e rode `progresso.sh <pasta-da-tarefa> conferir`. Só isso: nem o `registro.md`, nem os relatórios, nem a conversa anterior.
3. Siga da linha `PROXIMA`. Etapa feita não roda de novo. Artefato que `MUDOU` depois de feito pede que você abra o artefato e decida, porque outra sessão ou uma rodada de correção pode tê-lo mudado de propósito; não é motivo para refazer a etapa.
4. Leva que caiu no meio: redispare só o agente cujo relatório não está em `relatorios/`, pelo pacote gravado em `relatorios/pacote-*.md`.
5. Abra outro arquivo só quando a Próxima ação pedir, e só o trecho necessário.

Se a mesma sessão voltou de uma pausa por limite de uso, rode o `orcamento-local.sh` antes de tudo. Com o contexto em 70% ou mais, faça a parada limpa em vez de seguir: a sessão nova sai mais barata que a velha.

Tarefa criada antes da 1.2.0 não tem `progresso.md`: retome pela seção Retomada do `registro.md`, como antes, e crie os dois arquivos ao fechar a etapa em curso (`progresso.sh marcar` cria o progresso pelo molde).

**Medida:** no ensaio de `testes/scripts/teste-progresso.sh`, uma tarefa N2 que caiu no meio da leva de ataque ao plano retoma lendo cerca de 700 tokens: o contexto, o progresso e a saída do `conferir`, estimados por bytes. Com o `contexto-tarefa.md` no teto de 1.500, a conta fica perto de 2.000. Fora dessa conta fica o contexto fixo que toda sessão nova carrega: instruções do projeto, memória e ferramentas.
