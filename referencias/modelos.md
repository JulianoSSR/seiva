# Categorias de modelo

O orquestrador pede uma **categoria**; o mapa abaixo, ou a seção M do perfil, resolve para o modelo do harness. Assim a skill não envelhece quando sai modelo novo: muda só o mapa.

| Categoria | Serve para | Sinal de categoria errada |
|---|---|---|
| `script` | contar, listar, hash, diff, rodar teste, lint e build, extrair campos | nenhum: se é mecânico, é script |
| `rapido` | localizar código, ler e resumir arquivos, medir premissa com comando, medir uma suspeita | precisou interpretar regra de negócio ou decidir entre caminhos |
| `padrao` | implementar tarefa bem descrita, escrever teste, lente em N2, verificação, montar o perfil | deu mais de duas voltas no mesmo erro |
| `forte` | plano (N2 e N3), adversário em N2, lente em N3, implementação delicada (migração, concorrência, cálculo), julgamento difícil | — |
| `profundo` | adversário em N3, decisão de arquitetura, bug que resistiu a duas tentativas | — |

O orquestrador é o modelo da sessão. Se a sessão está num modelo pequeno e a tarefa é N3, peça ao usuário uma sessão mais forte.

## Regras

1. **A categoria vem da tarefa, não do papel.** Implementar uma migração delicada é `forte`, mesmo sendo "só implementação".
2. **O revisor fica acima do construtor, ou em outro modelo.** Por isso, em N3, o construtor é `forte` e o adversário é `profundo`. Nunca é a mesma instância.
3. **Escalada**, a regra única para toda repetição (verificação que falhou, correção de achado, relatório sem prova):
   - rodada 2: agente novo, **mesma** categoria, com o erro anterior no pacote;
   - rodada 3: uma categoria acima;
   - `profundo` que falha: pare e leve ao usuário. Não existe categoria acima.
4. **Voltas custam mais que preço.** Se o `rapido` precisaria de um passo a passo longo demais para acertar, use o `padrao`.
5. **Modelo pequeno pede prompt explícito:** passos numerados, critério de pronto, o que não fazer e formato de saída.
6. **Independência declarada.** Da mais forte para a mais fraca: `outro-provedor`, `outro-modelo`, `mesmo-modelo-contexto-limpo`, `mesmo-contexto`. Toda revisão registra qual teve.
7. **Tokens:** quando o harness informa os tokens de cada subagente (o Claude Code informa na notificação de fim), anote no registro. É o dado que calibra o orçamento.

## Modelo indisponível

A conta pode não ter acesso a uma categoria (limite de uso, crédito, modelo que o harness não oferece). Indisponibilidade **não conta como falha** para a escalada. Quando acontecer:

1. Desça uma categoria (`profundo` → `forte` → `padrao`) e siga. Não tente de novo o mesmo modelo na mesma tarefa.
2. Registre em `registro.md` uma decisão: `D-n: profundo indisponível, usado forte — custo se errado: <o que a categoria de cima pegaria>`.
3. Se a descida deixar o revisor no mesmo modelo do construtor, mantenha o contexto limpo e declare `mesmo-modelo-contexto-limpo`. Em N3, ofereça a revisão por outro provedor ([harness](harness.md)).
4. Anote a indisponibilidade na seção M do perfil (`profundo → forte, desde AAAA-MM-DD`) para não pagar a falha em toda tarefa. Quando o usuário disser que o acesso voltou, apague a linha.
5. A entrega diz qual categoria foi rebaixada e em que etapa.

## Mapa por harness

Conferido em 2026-09. Os nomes do Claude Code são os aceitos pela ferramenta de subagente. Os demais vieram de documentação e de changelogs, parte deles de fontes secundárias; **confira antes do primeiro uso** e grave o mapa certo na seção M do perfil.

| Categoria | Claude Code | Codex CLI | Gemini CLI | Cursor / OpenCode |
|---|---|---|---|---|
| `rapido` | `haiku` | modelo rápido da família atual (em 2026-09, `gpt-6-luna`) | Flash | id do provedor, no formato do harness |
| `padrao` | `sonnet` | `gpt-6-sol` | Pro | idem |
| `forte` | `opus` | `gpt-6-astra`, esforço `medium` | Pro, esforço alto | idem |
| `profundo` | `fable` | `gpt-6-astra`, esforço `xhigh` | Deep Think | idem |

No Cursor, o esforço vai entre colchetes no id (`modelo[effort=high]`). No OpenCode, o formato é `provedor/modelo`, e subagente sem `model` herda o do agente que o chamou.
