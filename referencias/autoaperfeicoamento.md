# Seis capacidades de aperfeiçoamento

**As seis capacidades produzem propostas com prova local, sem alterar a Seiva durante a tarefa do cliente.** Esta é a adaptação aprovada pelo usuário: minimização de dados, evidência privada e consentimento específico prevalecem sobre o blueprint de telemetria com logs e hash de origem.

Os nomes Reflexion, ExpeL, DSPy/ProTeM e SWE-abstraction são rótulos fornecidos no pedido. Não se afirma que esta implementação reproduz essas pesquisas, nem que elas comprovam economia ou segurança.

| Capacidade | Aplicação na Seiva | Limite |
|---|---|---|
| Reflexão pós-tarefa | No fechamento, bloqueio/timeout ou intervenção, comparar plano e execução. O adversário já convocado responde por que o plano não antecipou o erro; sem instância disponível, o orquestrador registra a pergunta e aproveita raciocínio já produzido | Nenhuma nova instância automática só para fabricar aprendizado; sem erro evidenciado, não gerar proposta |
| Extração estrutural, ExpeL | Nota privada registra uma instrução operacional curta, derivada da correção observada, e separa causa comprovada de hipótese | Não minerar conversas integrais nem aplicar instrução como regra |
| Gargalo de evidência | Ficha só pode ser sugerida/preparada com artefato privado de execução, teste ou feedback e análise local ainda válidos | Presença/hash comprovam versão do artefato, não sua verdade semântica ou causalidade |
| Ajuste textual pontual | Nota indica alvo local e microajuste conceitual; mantenedor julga a seção na base confiável e pede regressões | Não reescrever lentes ou editar caches/regras do cliente durante a tarefa |
| Abstração com baixo consumo | `extrair-insight.sh` compara caches privados e seleciona somente um conceito do catálogo, sem imprimir diff/log/caminho/hash da origem | Detecta mudança, não deduz seu significado; alvo de 100 tokens vale só para payload estimado |
| Reconstrução isolada | Receptor valida antes de modelo; Mantenedor reproduz contra base confiável, cria teste sintético e prepara mudança separada | Pacote não cria sandbox. Nenhum workflow privilegiado, modelo, auto-merge ou infraestrutura foi iniciado |

Fluxo conceitual; análise e aprovação são decisões humanas/de agentes autorizados:

```text
evento → prova privada + comparação plano/execução + instrução pontual
                                     ↓ validação local de versão
                              ficha conceitual pequena
                                     ↓ revisão exata + consentimento
                              recebimento de dados
                                     ↓ runtime isolado verificado
                          reprodução → teste → proposta separada
```

## Evidência e nota privadas

Guardar stdout de falha, resultado de teste ou feedback negativo no artefato privado já produzido pela tarefa. Não copiar isso para a ficha. `registrar --evidencia-local <arquivo> --tipo-evidencia execucao|teste|feedback` vincula a prova sem duplicar seu conteúdo. Referências e hashes de origem ficam somente no estado privado; não saem no payload, corpo, título ou apresentação da revisão de envio.

Sem prova, o candidato fica `aguarda-evidencia`; com prova, `aguarda-analise`. Nenhum deles dispara sugestão ou envio. No encerramento de tentativas, falhas equivalentes e bloqueios podem registrar o candidato; registro de bloqueio não prova defeito da skill.

A nota JSON privada tem somente `plano_vs_execucao`, `regra_operacional`, `alvo_local` e `grau` (`hipotese` ou `comprovada`). A regra é uma instrução curta, com até 240 caracteres; os outros textos também têm limite. Use evidência/raciocínio já disponíveis, sem ler toda a base para preencher a nota.

```bash
python3 scripts/aprendizado.py registrar --local .seiva/insights --evento evento-local.json --evidencia-local .seiva/provas.log --tipo-evidencia teste
python3 scripts/aprendizado.py refletir --local .seiva/insights --id <id> --nota-local .seiva/analise.json
bash scripts/extrair-insight.sh --antes .seiva/cache-antes.md --depois .seiva/cache-depois.md --local .seiva/insights --evidencia-local .seiva/provas.log --tipo-evidencia execucao
```

A nota é dado privado e não é executada. Com prova/nota alterada, a revisão anterior deixa de valer. Atualizar a prova exige nova análise e confirmação; o módulo não migra autorização antiga automaticamente. Evidência deve ser arquivo regular não vazio, ignorado pelo Git, sem links e de até 16 MiB. A conferência semântica continua com o responsável: um arquivo arbitrário não passa a ser prova só porque tem hash.

## Exportação e manutenção

O blueprint de entrada com `origin_hash`, caminhos de lentes, logs exatos e contexto de intervenção não é formato de exportação. Não foi implementado, por escolha explícita do usuário. Mantém-se o [schema mínimo](../insights/schema-v1.json): frases generalizadas do catálogo e exemplo sintético opcional. A análise local pode ser específica; a contribuição permanece conceitual. Isso limita expressividade e pode exigir reprodução adicional pelo mantenedor.

Cliente não compila nem implementa a correção da Seiva. Desenvolvimento autorizado no próprio repositório da Seiva é outro contexto: mudança nasce na base confiável, com testes e revisão independente. `testes/casos.md` é catálogo, não suíte executável; a suíte é `bash scripts/testar.sh`.

GitHub Actions não foi configurado implicitamente. Se adotado depois, deverá executar código confiável sem segredos/escrita privilegiada, sem rodar workflow ou script alterado por contribuidor. Ausência de runtime isolado bloqueia a execução do Mantenedor, sem bloquear a tarefa principal.

Não há medição de custo total deste ciclo nem promessa de quase zero tokens. Tamanho da ficha, processamento local, raciocínio de reflexão, revisão e consentimento são custos diferentes. O [aprendizado](aprendizado.md) mantém transporte, frequência e consentimento.
