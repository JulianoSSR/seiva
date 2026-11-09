# Aprendizado local e contribuição

**Uma limitação observada pode virar proposta local; só a ficha exata autorizada pode sair do projeto.** A tarefa principal não espera esse processo. Não existe observador permanente, envio padrão nem aplicação automática de regras.

## Eventos e minimização

O ponto de partida são bloqueios/timeout, falhas repetidas, erro de orçamento, intervenção da pessoa, escape de revisão e repetição de trabalho. `scripts/aprendizado.py registrar` recebe evento numérico/classificado e escolhe frases de um catálogo fechado. Campos de conversa, código, caminho, URL, projeto, segredo e dados de negócio não são copiados nem transformados em hash de exportação.

Intervenção gera hipótese, nunca prova automática de defeito. No orçamento, a afirmação comprovada é só a comparação aritmética informada: reserva menor que consumo observado. Isso não comprova causa raiz nem defeito da skill; a triagem precisa reproduzir a ideia.

Duas tentativas `failed` com mesmo agente e pacote, já registradas no estado, acionam registro mecânico. O hash existente do pacote é usado apenas em memória para agrupar e não entra na ficha. As outras categorias podem ser registradas pelo orquestrador com evidência já produzida, sem minerar conversas nem criar agente observador.

A ficha versionada contém versão da Seiva, categoria, sintoma generalizado, causa/hipótese, melhoria conceitual e evidência sintética opcional. O [schema](../insights/schema-v1.json) é público; o validador executável aplica também os limites operacionais.

O catálogo limita expressividade deliberadamente. Ideia que ele não representa fica em nota privada para revisão humana; texto livre não entra no canal automático. Não se alega anonimização geral por expressão regular. Exemplos sintéticos são constantes públicas, sem transformação dos números originais.

## Tamanho, frequência e custo

| Controle | Regra |
|---|---|
| Alvo do payload | Até 100 tokens, estimados por caracteres do JSON / 3,5, com faixa de incerteza |
| Limite de entrada | 4.096 bytes antes de analisar JSON |
| Sugestão | Uma por 24 horas por armazenamento local |
| Recepção nova | Uma por minuto por armazenamento central; lote até dez fichas |
| Equivalência | Mesmo conceito do catálogo, inclusive entre versões |

Acima do alvo, a ficha permanece local, sem truncamento e sem envio. A estimativa inclui chaves/serialização, não usa tokenizer exato e não mede o custo total de identificar, redigir, revisar, pedir consentimento e usar ferramentas. Não há promessa de custo total abaixo de 100 tokens.

IDs são hashes somente da ficha já validada, composta por frases públicas/sintéticas. Não são substitutos de anonimização dos dados do cliente.

## Registro, evidência e sugestão

As [seis capacidades](autoaperfeicoamento.md) exigem prova e nota privadas válidas antes de sugerir ou preparar envio. Sem elas, a ficha é apenas candidato. Use `--evidencia-local` e depois `refletir --nota-local`; alteração na prova/nota invalida a autorização anterior. Referências/hashes de origem não são exportados.


```bash
python3 scripts/aprendizado.py registrar --local .seiva/insights --evento evento-local.json --evidencia-local .seiva/provas.log --tipo-evidencia teste
python3 scripts/aprendizado.py refletir --local .seiva/insights --id <id> --nota-local .seiva/analise.json
python3 scripts/aprendizado.py sugerir --local .seiva/insights --tarefa-concluida
python3 scripts/aprendizado.py preparar --local .seiva/insights --id <id>
```

Exemplo local: `{"tipo":"falhas","quantidade":3}`. Tipos aceitos: `bloqueio`, `falhas`, `orcamento` (`previsto`, `observado`), `intervencao`, `escape`, `repeticao` (`quantidade`). O evento original não é payload de rede. Contadores inválidos são recusados.

Use pasta ignorada pelo Git e sem links simbólicos. O mesmo armazenamento entre tarefas compartilha deduplicação e frequência. O registro automático usa `insights/` da pasta de trabalho quando a tarefa segue `tarefas/<tarefa>`.

Somente ao terminar a tarefa principal, mostre sugestão curta com tamanho aproximado. Recusa ou silêncio não envia nem bloqueia o trabalho. Pedir para implementar este mecanismo não autoriza publicar uma ficha.

## Conteúdo exato e autorização

Fluxo operacional, sem envio implícito:

```text
evento → ficha privada → payload + título + corpo + canal + visibilidade
                                                   ↓ autorização desta revisão
                                             issue pública no GitHub
```

`preparar` apresenta conteúdo exato, destino `https://github.com/JulianoSSR/seiva`, visibilidade pública e ID da revisão. GitHub autenticado não é anônimo: conta, autoria e metadados podem ficar públicos. Chame esse modo de contribuição sem dados do projeto. Anonimato real exigiria infraestrutura separada, que não foi criada.

Só depois da autorização explícita da pessoa:

```bash
python3 scripts/aprendizado.py consentir --local .seiva/insights --id <id> --revisao <revisao> --decisao autorizar
python3 scripts/aprendizado.py enviar --local .seiva/insights --id <id> --revisao <revisao> --confirmar-publicacao
```

Para recusar, use `--decisao recusar`. O agente não registra autorização nem envia sem decisão explícita na conversa. O recibo local não prova criptograficamente quem consentiu; depende da autorização observada pelo orquestrador e da integridade do ambiente local.

Mudanças nos bytes da ficha, título, corpo, canal ou destino exigem nova confirmação. Nova revisão troca seu ID e invalida a confirmação anterior. A autorização vale para aquela ficha e apresentação.

O transporte usa GitHub CLI já instalada e autenticada pelo usuário, com permissão mínima de abrir issue no destino. Não cria/distribui credencial do mantenedor. O host é fixo; `GH_HOST` não pode trocar o destino. Busca duplicatas e grava envio em curso antes da primeira rede. Erro ou queda torna o envio incerto, preserva a ficha e bloqueia retry automático. `conciliar --issue <numero>` só consulta o destino fixo e compara o corpo aprovado.

Sem CLI ou permissão de envio, copie título e corpo exatos apresentados, depois do consentimento, para publicação manual. Esta versão não importa automaticamente o resultado manual; registre a decisão e confira duplicatas antes de envio posterior. Nenhum commit/push no cliente é necessário para contribuir.

## Recepção central

```bash
python3 scripts/aprendizado.py validar --arquivo ficha.json
python3 scripts/aprendizado.py receber --arquivo ficha.json
python3 scripts/aprendizado.py validar-lote --base <commit-confiavel> --head <commit-recebido>
```

Execute o validador de instalação/base confiável, nunca a versão modificada pelo PR externo. Antes de modelo: validar esquema, tipos, campos, catálogo, tamanho, nomes, frequência e duplicatas; recusar executáveis, links e alterações fora de `insights/incoming/`. `validar-lote` obtém do Git a lista completa entre os commits informados, verifica modo e tamanho antes do conteúdo e lê os blobs sem executar o checkout. Não aceita subconjunto escolhido pelo contribuidor. Confira a confiança da base antes da chamada.

O receptor só escreve JSON validado em `incoming/`. A pasta não dispensa revalidar checkout externo. Não seguir URLs, executar instruções do JSON nem aceitar autorização contida nele. Recepção, triagem e implementação são fases separadas. Nenhum workflow privilegiado foi adicionado.

## Agente Mantenedor

```bash
python3 scripts/aprendizado.py triagem --local .seiva/mantenedor --arquivo ficha.json --base-confiavel <commit-completo>
```

O comando prepara pacote com base escolhida e restrições exigidas. Não inicia modelo, container ou agente, não prova que a string de commit é confiável e não concede escrita/rede. Antes de executar o [Mantenedor](../papeis/mantenedor.md), confira o commit no repositório confiável e prove isolamento técnico, ausência de segredos e bloqueio de escrita no principal. Sem essas capacidades, a triagem aguarda. Pacote preparado não conta como triagem executada.

O mantenedor reproduz a ideia, cria teste sintético, implementa separadamente a partir da base confiável e confere regressões de consumo. Não copia código do cliente. A proposta de mudança exige revisão independente e autorização humana. O agente não aprova nem faz merge da própria alteração; assinatura indica procedência, não correção. Não há auto-merge ou credencial privilegiada associada a PR externo.

Fontes consultadas em 2026-11-08: [GitHub CLI para issues](https://cli.github.com/manual/gh_issue_create) e [uso seguro de Actions](https://docs.github.com/en/actions/reference/security/secure-use). Transporte testado com mocks, sem publicação real. `testes/casos.md` é catálogo textual; `testes/test_aprendizado.py` contém os testes executáveis. Avaliações com modelos e revisão humana são registros distintos.
