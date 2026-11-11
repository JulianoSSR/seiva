# Ajustes locais automáticos (canal A)

**A Seiva instalada se ajusta sozinha dentro de uma lista fechada, e cada ajuste é reversível e aparece no fechamento da tarefa.** Isso é separado do envio de sugestão ao GitHub (canal B, [aprendizado](aprendizado.md)), que continua exigindo revisão da ficha exata e consentimento específico. O canal A nunca dispara o B, e o B nunca altera a instalação.

## Onde vive

`ajustes.json` na pasta de trabalho privada do projeto (a que contém `tarefas/`, ignorada pelo git). Os arquivos da skill — `SKILL.md`, scripts, papéis — não são tocados. Arquivo inválido ou valor fora do intervalo é ignorado e a Seiva roda com os padrões.

## O que pode mudar

| Parâmetro | Padrão | Intervalo | Efeito |
|---|---|---|---|
| `stale_minutes` | 15 | 5–60 | tempo sem sinal até a tentativa virar `interrompida` |
| `context_limit` | 150000 | 50000–150000 | tokens de pacote + contexto acima dos quais o disparo é recusado (só pode apertar, nunca afrouxar) |
| nota por lente | — | até 200 caracteres | aviso lido na triagem ("nesta base a lente X não achou nada em N tarefas") |

Fora da lista nada muda automaticamente: tetos de rodada, critérios de aprovação, independência, níveis, o detector e esta própria lista. Mudar isso é decisão do usuário ou do mantenedor.

## Como um ajuste entra e sai

1. **Evidência medida em duas tarefas diferentes** (`ajustes.py evidencia`). Uma só não aplica nada; a mesma tarefa não conta duas vezes.
2. **Um ajuste em teste por vez.** O segundo espera a decisão do primeiro. Entre dois valores sugeridos vale o mais próximo do padrão.
3. **Linha de base:** precisam existir ao menos 2 tarefas registradas antes (`ajustes.py tarefa`, no fechamento, com quedas, rodadas e tokens).
4. **Observação:** nas 2 tarefas seguintes, se quedas ou rodadas subirem, ou se os tokens passarem de 120% da linha de base, o ajuste é **revertido sozinho**; senão, mantido.
5. **Reversão manual** a qualquer hora: `ajustes.py reverter --param P --motivo '...'`.

## Transparência

No fechamento, rode `python3 scripts/ajustes.py mostrar --trabalho <pasta>` e leve a linha para a resposta ao usuário, na mesma entrega. Sem ajuste, ela diz "nenhum em vigor". Silêncio sobre ajuste ativo é falha de entrega.

## Limites

- Duas tarefas é amostra pequena: pode confundir ruído com padrão. A reversão automática reduz o dano, não o elimina.
- A comparação mede quedas, rodadas e tokens, não qualidade da entrega; tarefas de tamanho muito diferente distorcem a comparação.
- Nota por lente é texto lido pelo orquestrador, sem força de código.
