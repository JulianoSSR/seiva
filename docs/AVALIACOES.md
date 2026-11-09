# Avaliações de consumo e qualidade

O objetivo é reduzir consumo total sem perder qualidade. O protocolo distingue evidência funcional, ensaio simulado e comparação real. Esta mudança não demonstra economia de tokens: os testes do agregador validam o protocolo com dados sintéticos.

## Comparação

Compare três modos: `direta` (sem revisão por outro agente), `um-revisor` e `seiva`. Use o mesmo caso, base, ambiente, critérios de aceite, limites e ferramentas, registrando modelos e esforço de cada participante. Separe casos de `calibracao` dos de `avaliacao`; um caso não pode aparecer nos dois conjuntos.

Cubra os tipos `simples`, `varios-arquivos`, `autorizacao-isolamento`, `dados`, `integracao` e `retomada`. Inclua dependente omitido pelo batedor, indisponibilidade de modelo N3, grave anterior sem prova, teto com pendência, relatório de tentativa antiga, reserva concorrente e duas tarefas na mesma sessão.

Repita as corridas e alterne a ordem dos modos. Um avaliador que não construiu a solução aplica os mesmos critérios; quando viável, desconhece o modo que a gerou. Fixe condições comparáveis e registre diferenças. Não use quantidade de achados como nota: falsos positivos também custam.

## Registro aceito pelo agregador

`scripts/avaliar.py` lê uma corrida por linha JSONL:

| Campo | Conteúdo |
|---|---|
| `run`, `case` | identificação da repetição e do caso |
| `kind` | um dos seis tipos acima |
| `split` | `calibracao` ou `avaliacao` |
| `mode` | `direta`, `um-revisor` ou `seiva` |
| `real` | booleano; false para fixture, simulação ou número inventado |
| `models` | lista com `app`, `version`, `model`, `effort` por participante |
| `conditions` | base, ambiente, ferramentas, limites, ordem e diferenças relevantes |
| `acceptance` | critérios equivalentes nos três modos |
| `passed` | resultado comprovado dos critérios e do portão de qualidade |
| `tokens` | `input`, `output`, `cache_read`, `cache_write` e `total` normalizado |
| `monitor_tokens` | consumo do monitor e acompanhamento, já incluído no total |
| `duration_seconds` | tempo de parede |
| `defects_detected`, `defects_escaped`, `false_positives` | defeitos confirmados, escapes e falsos positivos |
| `rework_tokens` | retrabalho, já incluído no total |
| `evidence` | caminhos de evidências sanitizadas e respectivas fontes |

O produtor normaliza tokens conforme o provedor: entrada pode incluir cache, e somar todos os campos sem conhecer a semântica pode duplicar consumo. Inclua orquestrador, todos os agentes, tentativas interrompidas, revisão, cache e retomadas. Não some token bruto com unidade ponderada ou dinheiro.

Uma corrida com métrica indisponível permanece em registro exploratório separado, com campos nulos e motivo. O agregador exige métricas completas e recusa nulo, negativo ou não finito; nunca preencha zero para conseguir aprovação. Dinheiro, se medido, fica separado com moeda, tabela de preço, data e cobertura.

```bash
python3 scripts/avaliar.py <resultados.jsonl> --saida <resumo.json>
```

A ferramenta valida campos, duplicatas, separação dos conjuntos e equivalência de condições/aceite. Só compara grupos completos dos três modos e mantém diferenças negativas ou positivas. Simulação não pode provar economia real.

## Portão de qualidade

Preencha `passed` somente com critérios, regressões e revisão exigida satisfeitos; graves precisam de correção verificada ou aceite explícito permitido, com evidência. O agregador confere o formato e a equivalência declarada; não executa modelos nem decide sozinho se a prova funcional é verdadeira. Outra instância precisa julgar as evidências.

Corrida interrompida permanece no consumo total e não conta como entrega válida. Compare tokens por entrega válida, taxa de conclusão, retrabalho, falsos positivos e escapes. Mostre resultados por caso e sua distribuição. Preço menor pode significar economia financeira sem reduzir consumo.

Uma comparação pareada não estabelece significância estatística. Sem base e cobertura equivalentes, ou sem amostra suficiente, o resultado é inconclusivo. Não transforme `economy_proven` do resumo em garantia geral de economia ou qualidade: ele se refere somente aos grupos fornecidos e às condições declaradas.

## Evidência disponível nesta mudança

- Testes sintéticos do agregador validam recusa de dados inválidos, falta de equivalência, duplicação e falsa economia por simulação.
- O monitor tem fixtures de parser e capacidade por integração; o grau de validação de cada uma fica em [harness](../referencias/harness.md).
- Não há aqui comparação real pareada dos três modos em tarefas completas. Testes de scripts ou consulta de catálogo não são demonstração de economia.

## Dados privados

Fixtures contêm só dados sintéticos. Pacotes, prompts, transcripts, caminhos pessoais, quotas da conta, segredos, relatórios de brechas e `julianossr.md` permanecem privados e ignorados pelo git. Publique protocolo, casos e resultados sanitizados com evidência reproduzível. Não copie histórico local para justificar um número público.
