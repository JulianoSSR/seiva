---
name: seiva
description: |
  Orquestra trabalho de desenvolvimento com um enxame de subagentes que se molda às regras do
  projeto. Mede o risco da tarefa, escolhe para cada passo o modelo mais barato que dá conta, faz
  um agente propor o plano e outros o atacarem por lentes (segurança, dados, design, desempenho,
  operação, contrato) antes e depois do código, e só entrega com prova. Use em tarefa de porte
  médio ou maior, em mudança que toque área sensível (permissão, dados, dinheiro, migração,
  deploy, integração externa), em bug que já voltou, ou quando pedirem "seiva", "enxame",
  "planeja e revisa" ou "sem retrabalho". Em tarefa trivial, manda fazer direto.
license: MIT
compatibility: Subagentes com modelo próprio no Claude Code, Codex CLI, Gemini CLI, Cursor e OpenCode; modo sequencial nos demais. Precisa de git e bash.
metadata:
  version: "1.0.0"
---

# Seiva

A seiva sobe pela árvore e toma a forma dela. Esta skill trabalha do mesmo jeito: não traz regra de domínio nem estrutura pronta. Lê as leis do projeto em que está, ocupa cada vão do trabalho com o agente certo e não deixa nada instalado no repositório: nenhum hook, nenhum agente fixo, nenhuma regra carregada em toda sessão.

Este arquivo é para o **orquestrador**, a sessão principal. Ele classifica, delega, confere prova e decide. Cada subagente recebe só o pedaço dele, no formato de [contratos](referencias/contratos.md).

## Leis da seiva

1. **O projeto manda.** Antes de qualquer passo valem as regras do projeto (`CLAUDE.md`, `AGENTS.md`, constituição, `CONTRIBUTING`). Se uma regra daqui divergir de uma de lá, vale a de lá, e a entrega diz qual regra da seiva ficou de lado.
2. **Cerimônia proporcional ao risco.** Enxame custa caro: a Anthropic mediu que um sistema multiagente gasta cerca de 15 vezes os tokens de um chat. Tarefa trivial se faz direto. O nível sobe com o risco, nunca para parecer rigoroso.
3. **Script antes de modelo.** Contar, listar, calcular hash, gerar diff, rodar teste, lint e build é trabalho de comando. Modelo é para julgamento.
4. **O modelo mais barato que dá conta.** A categoria vem da tarefa, não do papel. Conte as voltas, não só o preço: o modelo pequeno que erra três vezes sai mais caro que o médio que acerta na primeira.
5. **Quem constrói não aprova.** Revisor é outro agente, de contexto limpo, sem o histórico da conversa e, de preferência, de outro modelo. Toda revisão declara a independência que teve de fato.
6. **Sem prova não conta.** Achado sem evidência (`arquivo:linha`, comando e saída) não bloqueia. "Pronto" sem comando e saída não conclui.
7. **Arquivo, não conversa.** Entre agentes circulam caminhos de arquivo e relatórios curtos. O diff vai em arquivo, a lei vai por ID do perfil e documento grande nunca vai inteiro.
8. **Um dono por arquivo.** Só roda em paralelo o que não toca o mesmo arquivo. Arquivo compartilhado é do orquestrador.
9. **Revisão com teto.** No máximo 3 rodadas por portão. Só achado CRÍTICO ou ALTO confirmado reabre rodada. O resto vira registro, não loop.
10. **Premissa se mede.** Cada premissa do plano traz o comando que a mediu e o resultado, ou fica marcada como suposição.
11. **Nada escondido.** Limitação, suposição, risco aceito, achado não corrigido e decisão tomada sem o usuário aparecem na entrega, em texto.
12. **Evolui por evidência.** Defeito que escapou vira pergunta de lente; lente que nunca acha nada perde gatilho. Regra só muda com aprovação de quem desenvolve ([evolução](referencias/evolucao.md)).

## Fluxo

| Etapa | Quem faz | Produz | N0 | N1 | N2 | N3 |
|---|---|---|---|---|---|---|
| 0 Terreno | script + `padrao` | `perfil.md` (cache) | usa se existir | ✓ | ✓ | ✓ |
| 1 Triagem | orquestrador | `registro.md` | de cabeça | ✓ | ✓ | ✓ |
| 2 Reconhecer | batedor `rapido` | mapa + premissas medidas | — | se preciso | ✓ | ✓ |
| 3 Propor | construtor `forte` | `plano.md` | — | 5 linhas no registro | ✓ | ✓ |
| 4 Atacar o plano | adversário + lentes | achados | — | — | ✓ | ✓ |
| 5 Decidir | orquestrador + usuário | plano aprovado | — | — | ✓ | ✓ |
| 6 Construir | implementador | código + relatório | o orquestrador | ✓ | ✓ | ✓ |
| 7 Verificar | verificador | prova | comandos do projeto | ✓ | ✓ | outro modelo |
| 8 Atacar o código | lentes (+ adversário) | achados | — | 1 revisor | ✓ | lentes + adversário |
| 9 Entregar e aprender | orquestrador | entrega + aprendizado | ✓ | ✓ | ✓ | ✓ |

Os níveis estão em [triagem](referencias/triagem.md). Na dúvida, o maior.

### 0 · Terreno

1. Confirme que o repositório é o vivo. **Antes** dos comandos, releia o que as instruções do projeto e a memória da sessão dizem sobre onde ele fica. Depois rode `git rev-parse --show-toplevel`, `git log -1 --format='%h %cs %s'` e `git status --short`. Pare e avise se o caminho diverge do que a memória cita, ou se o último commit é antigo demais para o que se sabe do projeto. Um repositório git válido não prova que é o certo. Git recusando por "dubious ownership": veja [terreno](referencias/terreno.md), sem mexer na configuração global.
2. Pasta de trabalho: `.claude/seiva/` quando o git já ignora `.claude/`; senão `.seiva/`, e pergunte ao usuário se ela deve ser ignorada ou versionada.
3. Perfil: se `perfil.md` existe, rode `scripts/impressao.sh` sobre as fontes listadas nele. Impressões iguais: use o perfil como está. Diferentes: refaça só as seções da fonte que mudou. Sem perfil: crie seguindo [terreno](referencias/terreno.md). Na criação, e sempre que uma atualização mudar as seções L, P, V ou E, mostre ao usuário o que mudou antes de usar. Um erro no perfil se propaga para todos os agentes.

### 1 · Triagem

1. Crie a pasta da tarefa com `scripts/nova-tarefa.sh <pasta> <slug>`. O script grava no registro a foto do `git status` de agora, que separa depois o que é desta tarefa do que é de outra sessão.
2. Classifique nível, superfícies, lentes (com o sinal que acionou cada uma), categoria de cada papel e orçamento de agentes ([triagem](referencias/triagem.md)). Se o projeto já registrou o item com gravidade, parta dela; divergir exige uma linha de motivo.
3. **Escape:** se a tarefa corrige defeito, procure os arquivos envolvidos na seção "Arquivos entregues" das tarefas anteriores (`tarefas/*/registro.md`). Achou: registre o escape antes de começar ([evolução](referencias/evolucao.md)).
4. Diga ao usuário, em até 5 linhas: nível e motivo, lentes, orçamento e em que pontos vai parar para ouvi-lo. Se o perfil exige pergunta antes de acionar skill ou operação cara, faça aqui, numa pergunta só. Skill que aparecer como necessária mais adiante é perguntada na hora, pelo protocolo do projeto.

O nível sobe sozinho quando uma etapa encontra superfície sensível. Descer exige dizer ao usuário por quê.

### 2 · Reconhecer

Batedor `rapido`, somente leitura ([papel](papeis/batedor.md)). Ele mapeia onde está o código, quem chama, quem depende e o que já existe de parecido, usando a ferramenta de exploração que o perfil indicar. Também mede cada premissa com um comando. Em bug, descreve o defeito como padrão, busca esse padrão no sistema inteiro, conta as ocorrências e separa por risco. Entrega em `relatorios/batedor-1.md`.

### 3 · Propor

Construtor `forte` ([papel](papeis/construtor.md)) escreve `plano.md` a partir do [molde](moldes/plano.md). Recebe o pedido literal, os IDs do perfil que valem e o caminho do relatório do batedor. O plano planta as perguntas das lentes acionadas como riscos com mitigação verificável: segurança e dados entram no plano, não depois. Em N2 ou acima, comportamento novo sem teste vira tarefa de teste, ou uma decisão `D-n` que o usuário aceita.

### 4 · Atacar o plano

Em paralelo, somente leitura, contexto limpo:

- **Adversário** ([papel](papeis/adversario.md)): pre-mortem ("isto já quebrou em produção; por quê?") e verificação de trás para a frente (cada critério de aceite sai mesmo das tarefas?). Categoria `forte` em N2 e `profundo` em N3, acima do construtor e em outro modelo.
- **Lentes acionadas** ([papeis/lentes](papeis/lentes/)), mais as lentes do projeto listadas no perfil. Categoria `padrao` em N2 e `forte` em N3.

Cada um recebe o caminho do plano e do relatório do batedor, os IDs do perfil, o próprio papel, o formato de achado ([contratos](referencias/contratos.md)) e a lista "O que não é achado" ([revisão](referencias/revisao.md)). Não recebe a conversa.

### 5 · Decidir

O orquestrador julga cada achado ([revisão](referencias/revisao.md)). Abre o `arquivo:linha` citado, dá veredito (confirmado, falso ou incerto), agrupa por causa e manda cada grupo para uma rota:

- `intencao`: lacuna de negócio ou de intenção. Vai para o usuário.
- `plano`: o construtor revisa. É nova rodada, até 3.
- `ajuste`: correção pequena que não muda a intenção. O orquestrador faz.
- `adiar`: vira item no registro de status do projeto (seção R do perfil). Não bloqueia, mas aparece na entrega.

Suspeita CRÍTICA ou ALTA (confiança abaixo de 7) vira uma medição por agente `rapido` antes de ser descartada. Nenhum achado some em silêncio: cada um ganha uma linha de veredito em `achados.md`. Em N2 e N3 o plano vai ao usuário antes de qualquer código, com intenção, tarefas, riscos, adiados e decisões tomadas. Sem aprovação, não se escreve código.

### 6 · Construir

Implementadores ([papel](papeis/implementador.md)), um por tarefa ou por grupo de tarefas que dividem arquivo. Tarefas independentes rodam em ondas paralelas; dependentes, em sequência. O pacote leva passos numerados e o critério de pronto. Se o projeto tem teste para a área, o teste vem primeiro. Se o plano se mostrar errado no meio, o implementador para e devolve com a evidência, em vez de improvisar.

### 7 · Verificar

Verificador ([papel](papeis/verificador.md)): outro agente que não o implementador e, em N3, outro modelo. Roda os comandos de verificação do perfil, confere cada critério de aceite e cada mitigação de risco do plano e pergunta: "se este comportamento quebrasse, algum teste acusaria?". Separa o que passou, o que falhou e o que só se prova rodando (esse fica para o usuário testar). Falha volta para a etapa 6 com a saída do erro, até 3 rodadas, pela regra de escalada de [modelos](referencias/modelos.md).

### 8 · Atacar o código

Monte o diff com `scripts/diff-tarefa.sh <pasta-da-tarefa> <arquivos entregues>`. O script inclui arquivo novo e deixa de fora o que outra sessão mexeu. Recalcule as lentes pelo diff real, porque ele pode tocar mais do que o plano previa; se nenhuma lente acionar, o adversário revisa o diff. Em N3, o adversário revisa sempre. O julgamento segue a etapa 5; correções voltam ao implementador, até 3 rodadas.

### 9 · Entregar e aprender

- Atualize o status nos registros que o perfil manda (seção R), no mesmo trabalho. Número de item novo (bug, incidente, decisão) segue a regra de numeração da seção R; sem regra, confira o maior número em uso no arquivo como está agora, nunca pelo histórico do git, porque outra sessão pode ter acabado de usar o próximo.
- Entregue pelas regras do projeto (seção E), por exemplo: bloco de commit para o usuário rodar, se o projeto proíbe o agente de commitar.
- A entrega diz: o que mudou; a prova; decisões tomadas sem o usuário (`D-n`, com custo se errado); limitações e suposições; achados não corrigidos e onde ficaram registrados; categorias rebaixadas por indisponibilidade; a independência de cada revisão.
- Preencha "Arquivos entregues" no registro e anote uma linha em `aprendizado.md` ([evolução](referencias/evolucao.md)).

## Orquestrador enxuto

- Lê perfil, registro e relatórios. Arquivo grande não é lido inteiro.
- Confere prova por amostra: abre o `arquivo:linha` citado ou roda de novo o comando mais barato.
- Não delega o que um comando resolve.
- Cada subagente recebe o pacote de ida e nada mais. Pacote para modelo pequeno leva passos numerados.
- Relatório longo fica em arquivo; na conversa volta no máximo 25 linhas.
- Quando o harness informa os tokens gastos por subagente, anote no registro. Orçamento da triagem estourado: avise antes de continuar.
- Contexto compactado ou sessão retomada: releia `registro.md` (seção Retomada) e siga.

## Quando parar e perguntar

- Dúvida de regra de negócio ou de intenção.
- Premissa medida desmentiu o pedido.
- Mudança de tela ou de fluxo, quando o projeto exige aprovação de design.
- Risco que só o dono pode aceitar, como um inegociável do projeto.
- Teto de rodadas atingido com achado CRÍTICO ou ALTO aberto.
- Orçamento estourado.

O subagente não fala com o usuário. Dúvida dele volta como `STATUS: bloqueado`, e quem pergunta é o orquestrador.

## Categorias de modelo

| Categoria | Para quê | Claude Code |
|---|---|---|
| `script` | contar, listar, hash, diff, teste, lint, build | comando |
| `rapido` | achar código, resumir arquivo, medir premissa | `haiku` |
| `padrao` | implementar tarefa bem descrita, teste, lente em N2, verificação, perfil | `sonnet` |
| `forte` | plano, adversário em N2, lente em N3, implementação delicada | `opus` |
| `profundo` | adversário em N3, decisão de arquitetura, bug que resistiu a duas tentativas | `fable` |

Escalada, modelo indisponível, independência e outros harnesses: [modelos](referencias/modelos.md) e [harness](referencias/harness.md). Categoria sem acesso na conta desce um nível, e isso é dito na entrega. Sem subagentes, use o modo sequencial descrito em harness.

## Arquivos

| Caminho | Quando ler |
|---|---|
| `referencias/terreno.md` | criar ou atualizar o perfil |
| `referencias/triagem.md` | classificar a tarefa |
| `referencias/modelos.md` | escolher categoria, escalar, modelo indisponível |
| `referencias/contratos.md` | montar pacote, ler relatório, formato de achado |
| `referencias/revisao.md` | julgar achados, critério de parada |
| `referencias/harness.md` | disparar subagentes neste harness |
| `referencias/evolucao.md` | fechar a tarefa, registrar escape |
| `papeis/*.md`, `papeis/lentes/*.md` | colar no pacote do subagente |
| `moldes/*.md` | perfil, plano e registro |
| `scripts/*.sh` | impressão das fontes, pasta da tarefa, diff da tarefa, checagem da skill |
