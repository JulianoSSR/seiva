# Evolução: aprender com o que escapou

A seiva melhora por evidência medida em uso, não por opinião. O instrumento é um arquivo só, `aprendizado.md`, na pasta de trabalho do projeto. Nada é injetado nas sessões: ele só é lido quando uma tarefa fecha, quando a triagem procura escape ou quando o usuário pede uma revisão da skill. Se o projeto tem mais de um clone em uso, a pasta de trabalho deve ficar num lugar só (o perfil diz qual), senão cada clone aprende sozinho.

## Linha por tarefa

No fechamento de toda tarefa N1 ou acima, uma linha:

```
2026-09-27 · bug-088-errors · N3 · agentes r1 p3 f3 d1 (8 de 9 orçados) · tokens subagentes 410k + sessão 1,2 mi · rodadas plano 2 código 1 · lentes seguranca(rota nova) 2/0 dados(escrita em tabela) 1/1 adversario 1/0 · correções C-1 · escape —
```

- `r p f d` são as categorias `rapido`, `padrao`, `forte` e `profundo`; entre parênteses, quantos agentes a triagem orçou. É o custo real contra o orçamento.
- `tokens subagentes` é a soma do que o harness informou; `sessão` é o gasto da sessão do orquestrador com subagentes, pela nota `sessão ≈` do `orcamento-local.sh` (some as sessões, se a tarefa passou por parada limpa). Sem essa informação, escreva `—`, e os agentes e as rodadas servem de medida de custo.
- `correções` são as `C-n` do registro (abaixo).
- Cada lente aparece com o sinal que a acionou e `confirmados/falsos`. É isso que permite dizer, depois, que um sinal nunca rende achado.

## Como o escape é descoberto

Ninguém avisa a skill que um defeito escapou. A descoberta acontece na **triagem** da tarefa seguinte: quando a tarefa corrige defeito, o orquestrador procura os arquivos envolvidos na seção "Arquivos entregues" das tarefas anteriores.

```bash
grep -l -F -e 'caminho/do/arquivo.js' <pasta>/tarefas/*/registro.md
```

Achou: é escape da tarefa encontrada. O orquestrador registra antes de começar, e a tarefa nova sobe para N3. O mesmo vale quando o usuário diz que algo entregue pela seiva voltou a falhar.

## Escape

Escape é defeito encontrado **depois** da entrega (pelo usuário, em produção ou numa tarefa seguinte) numa área que uma tarefa da seiva tocou. É a medida que importa: o objetivo da skill é não voltar para consertar. Todo escape vira registro:

```
### E-1 · 2026-10-02 · origem: bug-088-errors · apareceu: produção
Defeito: <uma frase>
Etapa que deveria ter pego: <2 reconhecer | 3 plano | 4 lente X | 7 verificação | 8 lente X>
Por que passou: <lente não acionada | pergunta ausente na lente | premissa não medida | verificação sem teste | prova aceita sem conferir | outro>
Proposta: <pergunta nova na lente X | sinal novo na triagem | item no perfil | regra para o projeto>
Status: proposta | aprovada em AAAA-MM-DD | recusada: <motivo>
```

## Correção do usuário

Defeito que escapa é uma fonte de evidência; a outra é o usuário corrigindo a seiva no meio do trabalho: "isso não é N3", "essa lente não precisava", "pergunta antes de acionar", "o plano errou o fluxo". Quando a correção muda uma decisão da seiva (nível, lente, categoria, rota de achado, parada), o orquestrador anota na hora, na seção Decisões do registro:

```
C-1: <o que a seiva fez> → <o que o usuário corrigiu> — <a regra que levou ao erro, se der para dizer>
```

No fechamento, cada `C-n` vira uma proposta em `aprendizado.md`, no formato do escape, com `Por que passou: correção do usuário`. Se o projeto usa a memória automática do Claude Code, as memórias de tipo feedback criadas durante a tarefa também servem de fonte: são lidas no fechamento, nunca injetadas nas sessões. Nenhuma proposta se aplica sozinha.

Ferramentas que capturam correções por hook a cada mensagem e injetam regra em toda sessão (como o claude-recall) ficam de fora pela mesma razão dos hooks sempre ativos ([FONTES](../FONTES.md)): custo fixo de contexto e código de terceiro rodando a cada mensagem.

## Regras de ajuste

| Evidência | Proposta |
|---|---|
| Qualquer escape | Sempre gera proposta. |
| A mesma causa três vezes | Regra nova: para o projeto, pelo processo de evolução do próprio projeto; ou para a seiva. |
| Lente sem nenhum achado confirmado nas últimas 10 vezes que um sinal a acionou | Tirar aquele sinal da lente. Economiza tokens. |
| Lente com mais da metade dos achados julgados falsos | Rever as perguntas e as exclusões da lente. |
| Tarefas de um nível que usam bem menos agentes que o orçamento típico | Baixar o orçamento típico. |
| Custo real acima do orçado em 3 tarefas do mesmo nível | Rever o orçamento típico ou os gatilhos que levaram àquele nível. |
| A mesma correção do usuário (`C-n`) em 2 tarefas | Proposta de regra: na triagem, na lente ou no perfil do projeto. |
| Teto de rodadas atingido com frequência numa superfície | Reforçar o plano: a pergunta da lente entra como risco obrigatório no molde. |

## Para onde vai a proposta

- **Do projeto** (vale só aqui): vai para o perfil ou para os documentos do projeto, pelo protocolo de evolução que o próprio projeto tiver.
- **Da seiva** (vale em qualquer projeto): vira proposta no repositório da skill, com o caso que a motivou e um caso de teste novo em `testes/casos.md`.
- Nenhuma proposta se aplica sozinha. Quem desenvolve aprova, e a aprovação fica com data no registro do escape.
