# Revisão: atacar, julgar, parar

## Por que o revisor é outro

Modelos avaliam melhor o próprio texto (autopreferência), tendem a concordar com quem pergunta (bajulação) e confundem texto longo com texto bom (verbosidade). Fontes: Zheng et al. 2023, Panickssery et al. 2024, Sharma et al. 2024. As defesas que funcionam:

- revisor de contexto limpo, que recebe o plano ou o diff, não a conversa;
- revisor em modelo diferente do construtor, e de outro provedor quando der;
- rubrica fechada (as perguntas da lente e a tabela de severidade), não "dê uma nota";
- prova obrigatória e limiar de confiança, contra o falso positivo;
- veredito final de quem tem o código na mão: o orquestrador.

## Portões

| Portão | Revisores | Entrada |
|---|---|---|
| Plano (etapa 4) | adversário + lentes acionadas | `plano.md` + relatório do batedor |
| Código (etapa 8) | lentes recalculadas pelo diff (+ adversário em N3, ou quando nenhuma lente acionar) | `diff.patch` (de `scripts/diff-tarefa.sh`) + `plano.md` |

Revisores rodam em paralelo e só leem. Nenhum revisor corrige o que audita.

## Julgamento (etapas 5 e 8)

Para cada achado, o orquestrador:

1. **Confere a prova.** Abre o `arquivo:linha` ou a seção citada. Barato e obrigatório para CRÍTICO e ALTO.
2. **Dá o veredito:** `confirmado`, `falso` (com o motivo) ou `incerto`. Incerto em CRÍTICO ou ALTO vira uma pergunta objetiva a um agente `rapido`, que mede com comando, ou ao usuário. O mesmo vale para **suspeita** (confiança abaixo de 7) de severidade CRÍTICA ou ALTA: é medida antes de ser descartada, porque o defeito grave com confiança 6 é justamente o que não pode sumir. Suspeita MÉDIA ou BAIXA só é anotada.
3. **Agrupa por causa.** Três achados com a mesma raiz são um conserto só.
4. **Escolhe a rota:**

| Rota | Quando | Efeito |
|---|---|---|
| `intencao` | Falta decisão de negócio, ou o pedido é ambíguo. | Pergunta ao usuário. |
| `plano` | O plano está errado ou incompleto de forma que muda tarefas. | O construtor revisa; conta uma rodada. |
| `ajuste` | Conserto pequeno que não muda a intenção. | No plano, o orquestrador corrige; no código, volta ao implementador. |
| `adiar` | Real, mas fora do escopo ou MÉDIO e caro agora. | Vira item no registro de status do projeto (seção R do perfil), com o número pela regra do projeto, e aparece na entrega. Ficar só em `achados.md` não conta: essa pasta pode nem ser versionada. |

5. **Registra** em `achados.md` uma linha de veredito por achado: `A-3 → confirmado · plano · agrupado com A-5 (mesma causa)`.

Nenhum achado some em silêncio.

## Critério de parada

- Teto de **3 rodadas** por portão.
- Uma rodada só é aberta por achado **CRÍTICO ou ALTO confirmado**.
- O portão fecha quando uma rodada termina sem CRÍTICO nem ALTO confirmado **novo**.
- Estourou o teto com CRÍTICO ou ALTO aberto: pare e leve ao usuário o achado, as tentativas e as opções.
- Revisão de uma rodada seguinte recebe só o que mudou (o registro de mudanças do plano, ou o diff novo) e os achados abertos, não tudo de novo.

O ganho da revisão cai rápido depois da segunda rodada; estudos de debate entre modelos mostram o platô por volta da terceira. Rodada a mais além disso é custo sem retorno.

## O que não é achado

Vale para todas as lentes:

- preferência de estilo sem regra escrita no projeto;
- risco teórico sem cenário concreto neste código;
- "falta teste" genérico, sem apontar o comportamento que ficaria descoberto;
- dependência desatualizada sem falha conhecida que se aplique aqui;
- negação de serviço teórica sem vetor;
- problema já existente antes da mudança e fora do escopo. Esse vira `adiar`, com a anotação "preexistente", e não bloqueia;
- arquivo que é só teste, a não ser que o teste esteja provando a coisa errada.

## Independência honesta

Cada portão registra a independência que teve de fato: `outro-provedor`, `outro-modelo`, `mesmo-modelo-contexto-limpo` ou `mesmo-contexto`. A entrega repete essa informação. Nunca diga "revisão independente" quando foi o mesmo modelo no mesmo contexto.
