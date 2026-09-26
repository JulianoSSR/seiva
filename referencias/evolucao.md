# Evolução: aprender com o que escapou

A seiva melhora por evidência medida em uso, não por opinião. O instrumento é um arquivo só, `aprendizado.md`, na pasta de trabalho do projeto. Nada é injetado nas sessões: ele só é lido quando uma tarefa fecha, quando a triagem procura escape ou quando o usuário pede uma revisão da skill. Se o projeto tem mais de um clone em uso, a pasta de trabalho deve ficar num lugar só (o perfil diz qual), senão cada clone aprende sozinho.

## Linha por tarefa

No fechamento de toda tarefa N1 ou acima, uma linha:

```
2026-09-27 · bug-088-errors · N3 · agentes r1 p3 f3 d1 · tokens 410k · rodadas plano 2 código 1 · lentes seguranca(rota nova) 2/0 dados(escrita em tabela) 1/1 adversario 1/0 · escape —
```

- `r p f d` são as categorias `rapido`, `padrao`, `forte` e `profundo`.
- `tokens` é a soma do que o harness informou; sem essa informação, escreva `—`, e os agentes e as rodadas servem de medida de custo.
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

## Regras de ajuste

| Evidência | Proposta |
|---|---|
| Qualquer escape | Sempre gera proposta. |
| A mesma causa três vezes | Regra nova: para o projeto, pelo processo de evolução do próprio projeto; ou para a seiva. |
| Lente sem nenhum achado confirmado nas últimas 10 vezes que um sinal a acionou | Tirar aquele sinal da lente. Economiza tokens. |
| Lente com mais da metade dos achados julgados falsos | Rever as perguntas e as exclusões da lente. |
| Tarefas de um nível que usam bem menos agentes que o orçamento típico | Baixar o orçamento típico. |
| Teto de rodadas atingido com frequência numa superfície | Reforçar o plano: a pergunta da lente entra como risco obrigatório no molde. |

## Para onde vai a proposta

- **Do projeto** (vale só aqui): vai para o perfil ou para os documentos do projeto, pelo protocolo de evolução que o próprio projeto tiver.
- **Da seiva** (vale em qualquer projeto): vira proposta no repositório da skill, com o caso que a motivou e um caso de teste novo em `testes/casos.md`.
- Nenhuma proposta se aplica sozinha. Quem desenvolve aprova, e a aprovação fica com data no registro do escape.
