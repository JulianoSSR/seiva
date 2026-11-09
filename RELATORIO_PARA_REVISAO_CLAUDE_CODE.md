# Relatório para revisão independente do Claude Code

**A revisão independente do Claude Code (2026-11-09) concluiu "mudanças necessárias": dez defeitos confirmados, dois deles de severidade alta e já ativos nas sessões do usuário.** Os 180 testes Python e as 11 suítes shell passam no `9d773be`, mas não cobrem os cenários abaixo. Detalhes, reproduções e correções na seção [Revisão do Claude Code](#revisão-do-claude-code-2026-11-09).

**Data:** 2026-11-09, America/Sao_Paulo. **Estado:** entrega enviada no commit `9d773be`; revisão do Claude Code feita, com mudanças necessárias. Não houve commit, push, publicação, instalação global, hook ou serviço persistente.

## Base e identificação da entrega

- Repositório local: clone de trabalho do usuário, remoto `https://github.com/JulianoSSR/seiva.git`.
- Commit-base: `a181dc83b913f8123875ac8544f97e8a1c211ef2`. Entrega: commit `9d773be`, já em `main`.
- A primeira consulta encontrou árvore limpa. O índice permaneceu sem alterações. Não se atribuiu autoria por `git status`: a divisão de escrita foi explícita por arquivos entre as instâncias desta sessão.
- Identificação de conteúdo: `docs/validacao/estado-final.json`, com SHA-256 por arquivo e digest do conjunto. Exclui este relatório e o próprio manifesto para evitar autorreferência. O relatório não é um certificado independente.
- Diff para revisar: `.seiva/evidencias-evolucao/diff-revisao.patch`, montado após congelar os arquivos e verificado por aplicação numa cópia temporária da base. Essa entrega começou antes de o contrato novo existir: sua proveniência é a árvore inicialmente limpa, o commit-base e a divisão registrada nesta sessão; não é um snapshot retroativo produzido pelo novo script.

## Objetivo e mudanças

A Seiva continua escolhendo processo, agente e modelo conforme risco e qualidade, buscando reduzir o consumo total de execução, revisão, tentativas, retomada e fechamento. Preço e tokens são métricas separadas. Não há percentual de economia medido nesta entrega.

O núcleo ganhou base verificável e escopo por arquivo, diff atômico, estado JSON canônico, tentativas identificadas, relatório com marcador final e provas vinculadas aos hashes. Markdown permanece legível, como projeção ou contexto. O monitor coleta eventos locais incrementalmente, deduplica metadados numéricos e conserva cotas, contexto e créditos em campos distintos. A seleção exige capacidades atuais, requisitos, autorização e reserva de saldo incluindo revisão, correção e fechamento.

O SKILL permanece enxuto, com detalhes carregados pelas referências. Revisores podem ampliar a investigação. O Resina continua hacker defensivo: rastreia entrada, validação, autorização e operação sensível; prova executável exige isolamento, dados sintéticos e autorização. Outra instância julga os achados. Grave aberto impede fechamento, salvo aceite explícito permitido pelo projeto; teto interrompe.

## Arquivos e razões

| Arquivos | Razão |
|---|---|
| `scripts/estado_tarefa.py`, `base-tarefa.sh`, `diff-tarefa.sh`, `progresso.sh`, `nova-tarefa.sh` | Base, escopo, atomicidade, tentativas, invalidação e migração de estado |
| `scripts/adaptadores.py` | Extração de métricas por aplicativo e consulta temporária de catálogo/cota do Codex |
| `scripts/monitor.py` | Coleta incremental, leitura de orçamento, seleção e reservas compartilhadas |
| `scripts/avaliar.py`, `docs/AVALIACOES.md` | Protocolo pareado e validação de resultados; simulação nunca comprova economia real |
| `scripts/testar.sh`, `testes/test_*.py` | Verificação determinística dos novos contratos, adaptadores e seleção |
| `testes/scripts/teste-diff-tarefa.sh`, `teste-progresso.sh` | Migração das expectativas ao contrato mais rigoroso, preservando casos válidos |
| `testes/scripts/teste-orcamento.sh`, `testes/fixtures/harness-statusline-legado.txt` | Preservar testes históricos de statusline sem depender de exemplos removidos da documentação operacional; executam apenas em diretório temporário |
| `README.md`, `SKILL.md`, `referencias/*.md`, papéis alterados, moldes alterados, `testes/casos.md` | Eliminar contradições de leitura, armazenamento, seleção, fechamento e atribuição de consumo |
| `assets/identidade/seiva-simbolo-escuro.svg` | Original fornecido, sem redesenho nem alteração de cores/proporções |
| `.gitignore` | Separar execução privada e caches dos documentos versionáveis |
| `CHANGELOG.md`, `MEMORY.md`, este relatório, `docs/validacao/estado-final.json` | Histórico não publicado, continuidade e identificação verificável |

A lista de conteúdo está no manifesto; relatório e próprio manifesto são excluídos do digest e acompanham o patch integral. `medir.sh`, `orcamento-local.sh`, `orcamento.sh`, statusline e demais scripts legados não receberam reescrita.

## Problemas confirmados na base

Linhas desta tabela referem-se ao commit-base, não às linhas após a mudança. Evidência completa em `.seiva/evidencias-evolucao/linhas-base.txt` e `reproducoes-base.json`.

| Local na base | Cenário e resultado observado | Esperado / correção |
|---|---|---|
| `scripts/diff-tarefa.sh:41` | Alteração anterior e alteração da tarefa no README entram juntas no patch; reprodução isolada retorna 0 | Comparar bytes da base adquirida antes da edição, sem tocar índice ou atribuir autoria |
| `scripts/diff-tarefa.sh:37`, `:46` | Git falso emite saída parcial e sai 2; script sai 0 e perde último diff válido | Distinguir retorno 1 de diferença dos erros; publicar por troca atômica somente após sucesso |
| `scripts/diff-tarefa.sh:49` | Caminho inexistente não impede aparente sucesso | Recusar caminho ausente da base e do final; arquivos excluídos da base continuam suportados |
| `scripts/progresso.sh:138`, `:210` | Checklist vazio retorna 0 e `PROXIMA nenhuma`; marcar feita podia não exigir artefato ou conclusão | JSON validado, prova explícita e tentativa terminal vinculada; legado não comprovado não conclui |
| `scripts/progresso.sh:151` | Atualizações sem trava e retorno de publicação não propagado de forma segura | Trava, publicação atômica, falha visível e teste de escrita interrompida |
| `scripts/progresso.sh:99` | Busca limitada aos 20 diretórios recentes podia esconder pendências mais antigas | Examinar candidatas e ordenar pelo estado canônico; apresentar até cinco pendências |
| `scripts/nova-tarefa.sh:4`, `SKILL.md:65`, `:108` | Texto prometia separar autoria por fotografia de status/HEAD | Base e política explícita de exclusividade; concorrência não cooperativa exige isolamento |
| `SKILL.md:72` | Proibição de arquivo inteiro limita dependentes e autorização fora do mapa do batedor | Expansão justificada permitida, evitando repetição desnecessária |
| `referencias/harness.md:22`, `:64` | Notificação tratada como custo e texto contraditório sobre intervalo/sessão | Contabilidade por fonte, cobertura e intervalo; notificação serve ao acompanhamento |
| `referencias/harness.md:8`, `SKILL.md:148` | Instalação de agentes globais presumida e rebaixamento automático | Descobrir capacidade; sem instalação global implícita ou perda de qualidade sensível |
| `referencias/revisao.md:52` | Ausência de grave novo podia sugerir fechar enquanto grave anterior continuava aberto | Fechamento depende de resolver/verificar graves ou aceite permitido e explícito |

Não foi confirmada a hipótese de que os testes legados de orçamento já falhavam: os **11 scripts passaram numa cópia pristina do commit-base**. A execução inicial compartilhada leu documentação em alteração. Os logs `base-pristina-*.log` são a referência válida.

## Contratos e compatibilidade de comandos

1. `nova-tarefa.sh` guarda a base antes de editar produto; `base-tarefa.sh TASK --exclusive FILE...` adquire escopo. Não edite antes da aquisição. Registry fica no diretório Git comum e não altera índice.
2. Diff suporta criação, exclusão, binários, modo executável, links e espaços. Rename é representado de forma aplicável por exclusão+adição dos dois caminhos, sem depender da heurística de renomeação.
3. `attempt-start` identifica tarefa, tentativa, agente, pacote e relatório. Sobreposição com tentativa registrada em curso bloqueia redisparo. Consulte o runtime: registro `running` não prova processo vivo, e mtime não prova morte.
4. O produtor finaliza relatório com `<!-- seiva:fim TASK_ID ATTEMPT_ID -->`. Corpo vazio, marcador ausente/incompatível, relatório antigo e status parcial não concluem. `attempt-complete` publica o terminal com hashes e evidência. O orquestrador não acrescenta marcador a relatório alheio.
5. `progresso.sh TASK marcar N feita ARTIFACT... --attempt ID` exige terminal válido; etapa mecânica pode usar `--evidence 'comando e resultado'`. Isso é declaração explícita, não verificação semântica automática do conteúdo.
6. Verificações dependem dos hashes indicados em `--depends`; alterações invalidam as verificações afetadas. Dependência omitida pelo responsável não pode ser inferida pelo script.
7. Legado sem prova é preservado como não comprovado, para revalidação. Não se inventa baseline de tarefa antiga por HEAD atual.

Os nomes dos comandos básicos foram mantidos; a exigência de prova é uma migração intencional e documentada. Baselines contêm bytes em base64 e podem crescer: são privados, lidos por script, nunca devem ser colados integralmente no contexto nem publicados.

## Testes e evidências

Comando completo, sem chamadas de modelo:

```bash
cd seiva   # raiz do clone
bash scripts/testar.sh
```

Também podem ser repetidos separadamente:

```bash
python3 -m unittest discover -s testes -p 'test_*.py' -v
bash scripts/checar-skill.sh
git diff --check
```

Resultado final: **180 testes Python (67 de aprendizado) e 11 suítes shell passaram**, execução completa em 32,217 s. A contagem de 1.162 verificações shell pertence à primeira validação; não foi recontada na execução final. Checagem da skill, sintaxe e `git diff --check` passaram. Resumo sanitizado: `docs/validacao/resultados.json`.

Resultado final e duração: `.seiva/evidencias-evolucao/validacao-seis-capacidades.json`; saída completa: `validacao-seis-capacidades.log`. Os testes cobrem pré-alterações staged/unstaged, índice preservado, conflitos de escopo, falha Git, escrita/saída parcial, binários, links, nomes com espaços, relatório vazio/truncado/antigo, tentativa em curso, conclusão válida, artefato/dependência alterados, migração e retomadas repetidas.

Monitor e adaptadores cobrem ausência, antiguidade, malformação, deduplicação, rotação curta de logs, acumuladores separados por sessão/modelo, reinício de janela, concorrência, falha de autenticação/RPC, paginação, timeout e encerramento do subprocesso. Seleção cobre indisponibilidade de modelo equivalente, ferramenta não detectada, dependências, tarefa já concluída, orçamento sem unidade, reservas concorrentes e consumo de revisão/correção.

As revisões internas encontraram cinco defeitos no monitor e três nos adaptadores; foram corrigidos com regressões direcionadas. Registros: `revisao-monitor.md` e `revisao-adaptadores.md`, na pasta privada de evidências. Foram instâncias separadas, mas com o mesmo modelo herdado; não equivalem à revisão solicitada ao Claude Code. O núcleo recebeu autoconferência do orquestrador e testes, sem alegar uma revisão externa completa.

## Matriz por aplicativo

| Aplicativo | Validação nesta entrega | Lacunas |
|---|---|---|
| Claude Code 2.1.282 | Versão conferida, scripts legados preservados e suites determinísticas; parser novo por fixtures | Parser novo não teve transcript real elegível nesta validação; não houve tarefa completa medida no app |
| Codex 0.167.0-alpha.3.2 | RPC real `initialize`, `model/list`, `account/rateLimits/read`; oito modelos retornados e nenhum erro; parser reconheceu sete eventos de um rollout local | Rollout é formato local experimental; amostra não mede a tarefa toda. Contadores/quotas variam por versão/conta. Campos de isolamento, ferramentas e paralelismo não detectados ficam desconhecidos |
| Gemini CLI | Adaptador de resultado JSON/fixtures documentadas | Executável não localizado nos caminhos conferidos; sem validação real. Export sem timestamp reconhecível é excluído do intervalo |
| OpenCode | Adaptador de exportação/fixtures documentadas | Executável não localizado; sem validação real nem servidor instalado. Semântica de timestamp é validada pelo formato suportado |
| Cursor | Formato público consultado; recusa explícita de token usage não exposto | Não suportado para tokens nesta versão; não substitui ausência por zero |
| Generic/outros terminais | Contrato de evento numérico e testes sintéticos | Precisa de produtor compatível, identificação, horário e fonte; não descobre magicamente métricas privadas |

Fontes oficiais e data de consulta (2026-11-08): [Codex App Server](https://learn.chatgpt.com/docs/app-server), [Gemini headless](https://geminicli.com/docs/cli/headless/), [Cursor output](https://cursor.com/docs/cli/reference/output-format), [OpenCode](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/session/message.ts), [Claude streaming](https://platform.claude.com/docs/en/build-with-claude/streaming). A fonte Claude API não especifica todo transcript local: reconhecimento depende do formato testado.

## Consumo, seleção e avaliações

Tokens de entrada, saída e cache não são somados cegamente: o Codex/Gemini podem incluir cache na entrada, enquanto outras fontes o separam. Contexto é a leitura da sessão; cota é percentual/janela/reinício; créditos são outra unidade; custo financeiro só aparece quando a fonte o informa. Cada leitura inclui origem, instante, escopo, unidade e natureza. Sem fonte, é indisponível.

O monitor não chama modelos para contabilidade. Reaproveita offsets, deduplica eventos e usa cache numérico privado. `vigiar` é processo ativo com prazo, sem daemon; requer acionamento explícito. Atualize antes de despachar, ao concluir, na retomada e durante execução ativa quando viável. Não há garantia de interromper agente em voo. Mudança de formato inválido falha sem substituir a última leitura válida.

A seleção usa modelos atuais, ferramentas detectadas, contexto e qualidade declarada para a tarefa, risco/complexidade, dependências e autorização. Histórico comparável inclui falhas e tokens por sucesso; sem amostra suficiente, reserva conservadora com faixa e tamanho da amostra. Três falhas sem sucesso não viram opção barata. Dinheiro é exibido separadamente da minimização de tokens. As reservas são compartilhadas pelo repositório/worktrees e expiram em 15 minutos; outros repositórios precisam receber saldo já descontado.

**Limites:** qualidade e capacidade por tipo de tarefa ainda exigem evidência/julgamento humano; catálogo não prova qualidade. Histórico novo é entrada sanitizada, não treinamento automático universal. Quota percentual não fornece saldo exato em tokens: a seleção recusa orçamento ausente/antigo e só reserva saldo explícito com fonte/unidade/horário. Ferramentas não detectadas bloqueiam requisitos correspondentes. A previsão é heurística, sem garantia de economia.

Na primeira parte foram usadas três subtarefas por arquivos disjuntos: contratos/estado, documentação/identidade, parsers. A divisão permitiu investigação e revisão cruzada sem sobreposição. Todos herdaram o modelo da sessão; não foi inventada vantagem de custo por um suposto modelo mais barato. Leituras ampliadas foram necessárias para localizar consumidores e comparar contratos entre arquivos. Não houve enxame para demonstrar a Seiva nem chamada paga extensa de avaliação.

O consumo total de modelos desta própria tarefa, com todas as instâncias e retomadas, **não foi atribuído de forma completa**. A consulta de orçamento real e a amostra de rollout não o substituem. Não se informou zero, custo financeiro ou percentual de economia fictício.

`docs/AVALIACOES.md` define seis classes, critérios equivalentes, três fluxos e separação calibração/avaliação. `avaliar.py` valida resultados pareados e mostra quando Seiva gasta mais. Seus testes são sintéticos e não demonstram economia real. As execuções comparativas com modelos reais continuam pendentes de orçamento e condições autorizados; o protocolo é reproduzível sem iniciá-las automaticamente.

## Identidade e limites operacionais

O SVG original foi preservado byte a byte (SHA-256 `d58f601be681546fe5f9734ac8ab4c94229b30b66f34857d20d4f222864c0dde`), com verde `#081C15` e dourado `#E3A72F`. README usa caminho relativo, alt e largura 96. Foram geradas prévias privadas 32/64/96; 32 e 96 foram inspecionadas visualmente. Não foi criada variante.

`julianossr.md` é aprendizado privado por tarefa e escapes, não cadastro nem telemetria. Foi lido somente para compreender seu papel, preservado e não publicado. Autoria JulianoSSR, licença, origem e história permanecem. Resina mantém nome, especialidade defensiva, evidência e julgamento por outra instância.

Outros limites concretos a avaliar:

- Locks de arquivos e reserva são cooperativos. Não impedem um editor externo que ignore o protocolo; use worktree/cópia isolada quando não houver exclusividade combinada. Snapshot sozinho nunca separa edições posteriores.
- O baseline guarda bytes privados e a primeira captura percorre arquivos Git pertinentes; projetos grandes precisam avaliar custo local e armazenamento. Não ler o JSON inteiro no prompt.
- Estado/monitor usam `fcntl`: Linux/macOS, ou WSL no Windows. Monitor exige tarefa ignorada dentro do repositório; fallback externo do núcleo não é aceito por ele nesta versão.
- A coleta só cobre as fontes informadas. Intervalo não prova exclusividade da sessão; faltas de fontes de agentes e sobreposição precisam aparecer como cobertura parcial.
- Marcas e evidências comprovam versão/contrato, não a verdade semântica de um relatório, que continua exigindo julgamento independente.
- Sem evento ou serviço oficial de uso disponível, a atualização é polling limitado sobre fontes fornecidas. Não há integração de controle/interrupção de agentes nem automação global instalada.

## Complementos 13–14 e seis capacidades aprovadas

**A comunicação foi incorporada e o aprendizado só pode sugerir uma ficha após prova e reflexão privadas válidas.** O formato amplo de telemetria com logs, hash de origem e caminhos não foi adotado: o usuário escolheu manter minimização de dados e consentimento específico ao incorporar as seis capacidades.

| Entrega | Arquivos responsáveis | Verificação |
|---|---|---|
| Comunicação didática | `referencias/comunicacao.md`, SKILL, README e documentos do complemento | Leitura humana; conclusão destacada primeiro, tabelas simples e fluxos textuais conceituais; sem alegar teste semântico automático |
| Registro por eventos | `scripts/aprendizado.py`, integração em `estado_tarefa.py` | Falhas equivalentes e bloqueios geram candidatos; demais eventos usam o raciocínio já disponível, sem observador permanente |
| Evidência e reflexão | `registrar --evidencia-local`, `refletir --nota-local` | Fonte privada versionada por hash local; comparação plano/execução, regra operacional curta e alvo pontual; sem aplicar regras |
| Extração mecânica | `scripts/extrair-insight.sh` | Compara caches privados; exporta somente ocorrência/conceito, nunca diff, caminho ou hash da origem |
| Consentimento e transporte | `preparar`, `consentir`, `enviar`, `conciliar` | Ficha/título/corpo/canal/destino exatos; ausência e recusa bloqueiam rede; mutações invalidam e falha preserva sem retry cego |
| Recepção de dados | `insights/schema-v1.json`, `receber`, `validar-lote` | Esquema, tamanho, catálogo, frequência, deduplicação, modos e revisão Git inteira antes de modelo; lê blobs, sem executar checkout |
| Mantenedor | `papeis/mantenedor.md`, comando `triagem` | Prepara pacote e restrições; execução real aguarda runtime isolado verificado; sem privilégio de aprovação/merge |

O fluxo abaixo é conceitual; não representa automação de julgamento ou implantação:

```text
evento → evidência privada → reflexão + instrução pontual → ficha conceitual
                                                              ↓ revisão exata e consentimento
                                                            issue pública
                                                              ↓ validação antes do modelo
                                          triagem isolada → teste → mudança separada → revisão humana
```

As seis capacidades estão em `referencias/autoaperfeicoamento.md`: reflexão pós-tarefa, extração estrutural, gargalo de evidência, ajuste textual pontual, abstração com baixo consumo e reconstrução isolada. Os rótulos de pesquisas foram fornecidos pelo usuário; não se afirma equivalência científica às implementações citadas. O adversário já existente foi reaproveitado para revisão e reflexão do consentimento, sem criar agente de formatação ou varredor permanente.

A reflexão do P1 identificou uma hipótese de causa: o contrato tratava “ficha exata” como se cobrisse toda a saída, esquecendo o título. A instrução pontual proposta foi conferir todos os campos que saem do processo e derivá-los do pacote exibido. A reprodução demonstra a lacuna, sem provar o raciocínio interno que a originou.

### Privacidade, tamanho e consentimento

O payload usa catálogo fechado e esquema versionado com somente versão da Seiva, categoria, sintoma, causa/hipótese, melhoria conceitual e evidência sintética opcional. Informações do projeto não são copiadas nem transformadas em hash para exportação. Intervenção permanece hipótese; a causa comprovada em orçamento significa só a comparação aritmética informada, não validação de causa raiz.

Logs exatos, feedback e contexto podem continuar nos artefatos privados já existentes. Seus caminhos/hashes ficam apenas no estado local e são filtrados até da apresentação de revisão para envio. Arquivo presente e hash válido comprovam versão, não significado ou verdade: a prova e a análise ainda exigem julgamento. Evidência ausente, nota ausente ou alteração posterior impedem sugestão/preparo/envio. Candidatos não interrompem a tarefa principal.

O alvo de 100 tokens é apenas do payload, estimado por caracteres do JSON / 3,5, com faixa de incerteza. Não foi instalado tokenizer. Tamanho acima do alvo mantém a proposta local sem truncagem. Não há medição do custo total de reflexão, redação, apresentação, revisão e consentimento; não há promessa de quase zero tokens ou custo total abaixo de 100.

Envio usa apenas GitHub CLI já instalada/autenticada pelo usuário e URL fixa de `JulianoSSR/seiva`, com visibilidade pública declarada. Conta/autoria/metadados podem ficar públicos; não é anonimato. Não se distribui credencial do mantenedor e não se faz commit/push no cliente para contribuir. A CLI não foi localizada no ambiente testado: transporte foi exercitado com mocks, sem autenticação ou publicação real; título e corpo exatos permitem procedimento manual depois de consentimento.

O recibo depende da integridade do ambiente local e da decisão humana observada pelo orquestrador; não é comprovação criptográfica da identidade de quem autorizou. O receptor não aceita autorização alegada dentro da ficha. Revalidamos dados e fontes imediatamente antes do despacho; não há garantia de revogar uma requisição em voo se um arquivo mudar depois dessa conferência.

### Achados e validação do complemento

Uma instância separada, com o mesmo modelo herdado, revisou publicação/consentimento e fez revisões direcionadas:

- **P1 corrigido:** categoria editável no estado local podia escapar no título sem aparecer na autorização. Título agora deriva só do payload validado e é apresentado e vinculado ao recibo.
- **P2 corrigido:** prova/nota podiam mudar durante a consulta remota de duplicatas. Ficha, fontes e recibo são relidos e comparados antes de criar issue ou concluir por duplicação. Os testes reproduzem ambas as mutações sem rede.
- Na revisão focada final, o revisor executou **67 testes de aprendizado**, todos passaram. Evidência local: `.seiva/evidencias-evolucao/revisao-aprendizado.md`; suíte integral final: `validacao-seis-capacidades.json` e `.log`.

O catálogo textual `testes/casos.md` permanece separado dos testes executáveis, das avaliações com modelos e da revisão humana. Os testes cobrem todos os critérios do complemento, incluindo payload grande, dados sensíveis extras, hipóteses, duplicatas, frequência, consentimento ausente/recusado/antigo, mudança após aprovação e durante busca, erro de rede, lote externo, instrução maliciosa, executáveis, links e ausência de execução privilegiada ou merge autônomo.

Limites ainda abertos: catálogo restringe a expressividade; a análise local específica não é exportada, de modo que o mantenedor pode precisar de reprodução adicional. O extrator detecta mudança, sem deduzir significado. Triagem é pacote, não execução de agente/sandbox; a string de commit deve ser conferida contra a base confiável pelo mantenedor. Não foi instalado GitHub Actions nem criado serviço de anonimização. Nenhuma proposta mudou regras automaticamente, executou modelo de manutenção ou publicou dados.

O usuário pediu bloco de commit para executar pessoalmente. O bloco está em `.seiva/evidencias-evolucao/bloco-commit.sh`, com arquivos explícitos, conferência de hashes/estatística, pausa e comandos encadeados; o agente não executou commit nem push. Uma falha de conferência deve interromper a sequência.

## Como reproduzir e reverter apenas esta entrega

1. Confira HEAD/base e o manifesto. Havendo nova alteração em um arquivo da entrega, compare-a antes de reverter. Não use restore/reset geral.
2. Rode `bash scripts/testar.sh`; abra a evidência dos casos relevantes e confira os contratos diretamente no código.
3. Revise `.seiva/evidencias-evolucao/diff-revisao.patch`, inclusive arquivos novos e a fixture histórica de teste.
4. Para reverter, somente depois de conferir a árvore atual:

```bash
git apply --reverse --check .seiva/evidencias-evolucao/diff-revisao.patch &&
git apply --reverse --binary .seiva/evidencias-evolucao/diff-revisao.patch
```

Uma falha interrompe a reversão; não force nem apague arquivos de outra sessão. O patch não remove evidências privadas nem configurações preexistentes, e não modifica o índice. Não há publicação a desfazer.

## Revisão do Claude Code (2026-11-09)

**Veredito: mudanças necessárias.** A revisão foi feita por outra instância, em outro harness e outro modelo (Claude Code), sobre o diff `a181dc8..9d773be`. Ela não aceitou este relatório como prova: leu o código novo, reproduziu cada defeito em cópia temporária e não usou dado de produção. As linhas abaixo se referem ao `9d773be`.

**Contexto que o relatório omitiu:** `~/.claude/skills/seiva` é um link simbólico para o clone. "Sem instalação global" é verdade, mas o push fez o comportamento novo valer na hora em todas as sessões do Claude Code do usuário, inclusive nas tarefas em curso do Ciclo Arboris.

### O que foi reproduzido

| Item | Resultado |
|---|---|
| `bash scripts/testar.sh` numa cópia limpa do `9d773be` | Saída 0: 180 testes Python, 11 suítes shell (1.162 casos), `checar-skill` em ordem; 58,4 s |
| RPC real do Codex, revisões internas, prévias do SVG | Não reproduzidos; só registrados |
| Gemini, OpenCode, Cursor em aplicativo real | Não testados por nenhuma das duas partes |

### Onde a entrega falhou

| # | Sev. | Local no `9d773be` | Cenário que reproduz | O que aconteceu | Por que os testes não pegaram |
|---|---|---|---|---|---|
| 1 | Alta | `scripts/estado_tarefa.py:110-129`, `:412-415`, `:468-473` | Cópia das tarefas reais do Ciclo (`.claude/seiva/tarefas/*`) e `progresso.sh <tarefa> conferir` | Sai com 2: `artefato fora do escopo: ../../perfil.md`. A migração deixa `repository` vazio e o perfil da pasta de trabalho fica fora das raízes. Antes de falhar, grava `estado.json` e reescreve o `progresso.md`, que perde o cabeçalho. `pendentes` aponta "0 Terreno · feita" e esconde "6 Construir · em-curso: adendo D-41 parcial". Na base `a181dc8`, a mesma cópia responde `PROXIMA 6 Construir` | Os testes de migração usam artefatos dentro da pasta da tarefa; nenhum usa o perfil compartilhado, que era o padrão da etapa 0 na base |
| 2 | Alta | `scripts/adaptadores.py:44-49`, `:189`; `scripts/monitor.py:140-144` | Transcript do Claude Code com mensagem `"model": "<synthetic>"` (23 linhas em 8 dos 40 transcripts reais mais recentes da máquina) | `_label` recusa `<`/`>`, o `ingest` aborta a coleta inteira e não avança o offset: a fonte fica bloqueada para sempre. Sem a linha, a mesma fonte soma input 30 e output 12 | O parser do Claude foi validado só com fixtures, sem transcript real; o relatório reconhece isso na matriz |
| 3 | Média | `scripts/aprendizado.py:504` | Commit que troca a ficha A pela ficha B em `insights/incoming/` | `git diff --name-only` usa detecção de renomeação e lista só B; `--no-renames --name-status` mostra `D A` e `A B`. O validador aceita, embora o código pretenda recusar exclusão | Nenhum teste combina exclusão e adição semelhantes no mesmo lote |
| 4 | Média | `scripts/estado_tarefa.py:387-389` | Marcar as dez etapas como `pulada`, sem motivo nem artefato | `conferir` sai com 0, `PROXIMA nenhuma`, e a tarefa some de `pendentes`. A regra "prova antes de concluir" é contornada | Só se testou `pulada` com motivo |
| 5 | Média | `scripts/estado_tarefa.py:86-87`, `:208-219`; `scripts/nova-tarefa.sh:83` | Repositório com submódulo e `nova-tarefa.sh` | Sai com 2 (`o escopo exige arquivo regular`), porque o gitlink é um diretório. A pasta da tarefa fica pela metade, sem `estado.json`; repetir dá `já existe` | Nenhum repositório de teste tem submódulo |
| 6 | Média | `scripts/aprendizado.py:426`, `:430-432`, `:280-285` | Autorizar, depois simular a rede caindo já na busca de duplicata, antes de qualquer `issue create` | O status vira `incerto` embora nada tenha sido publicado. Daí em diante, preparar, refletir e enviar são recusados, e `conciliar` exige uma issue que não existe. Como a equivalência é só por categoria, um evento novo da mesma categoria responde `duplicada` para sempre; o mesmo vale depois de `recusado`. Na prática, são seis fichas em toda a vida da instalação | Os testes de falha de rede param na marcação `incerto` e não verificam se há saída dela |
| 7 | Baixa | `SKILL.md` (regra removida); `scripts/medir.sh:265` | Ler as duas versões | A regra "a descrição do agente começa pelo papel" saiu do SKILL, mas o `medir.sh` ainda separa papéis pela primeira palavra da descrição. Só o Resina manteve o prefixo. O `medir.sh` não foi executado na revisão | `checar-skill` não confere essa dependência |
| 8 | Baixa | `scripts/nova-tarefa.sh:63`, `scripts/estado_tarefa.py:180-181` | Criar tarefa nova | Toda tarefa nova sai com `migrated_from: progresso.md`, porque o molde é copiado antes do `init` | Nenhum teste olha esse campo em tarefa nova |
| 9 | Baixa | `SKILL.md` (`version`), `.claude-plugin/plugin.json` | Ler a versão | Continua 1.5.0 com contrato incompatível (`marcar feita` exige `--attempt` ou `--evidence`). A ficha de aprendizado manda `versao_seiva` 1.5.0 para código que não é o 1.5.0 publicado | Não se aplica |
| 10 | Baixa | `MEMORY.md`, este relatório | Ler os arquivos publicados | Notas de sessão (túnel, Ciclo Arboris, transferência) e caminho local absoluto foram para o repositório público. Não há segredo, mas é metadado de sessão | Não se aplica |

### Observações sem defeito confirmado

- **Seleção por capacidade:** `capacidades` devolve `models: []` para o Claude e deixa `tools` e `clean_context` nulos. Sem um arquivo escrito à mão, `selecionar` não escolhe nada no Claude Code e descarta toda tarefa `independent`, inclusive revisor. Hoje a seleção só funciona de fato com o Codex, e isso precisa estar dito assim.
- **Base completa:** num repositório sintético de 15 MB, o `estado.json` ficou com 20 MB, e cada comando levou cerca de 0,4 s. O desempenho está bom. Duas coisas pesam: o arquivo inteiro é regravado a cada marcação, e entram bytes de arquivo não rastreado e não ignorado, o que pode copiar um segredo mal ignorado para a pasta privada.
- **Valor da ficha:** o payload só tem texto de catálogo. A privacidade está bem amarrada, porque a validação exige as frases exatas e só a versão varia. Em troca, o mantenedor recebe quase nenhuma informação, e o custo de reflexão e consentimento não foi medido.
- **Robustez de `pendentes`:** um único `estado.json` inválido derruba a listagem de todas as tarefas.
- **Hash legado:** a migração aceita hash de 12 a 64 caracteres, mas a validação seguinte só aceita 12 ou 64.

### O que se sustentou

- Consentimento: o título deriva do payload, há hashes de título, corpo e fontes, e tudo é relido antes do `create`. Os achados P1 e P2 da revisão interna continuam corrigidos.
- Recepção: o validador lê blobs sem checkout, e o pacote de triagem não executa, não aprova e não faz merge.
- O diff atômico preserva o `diff.patch` anterior quando falha.
- O Resina manteve nome, papel defensivo e julgamento por outro agente.

### Correções preparadas pelo Claude Code

**Os dez itens foram corrigidos e validados na árvore de trabalho, ainda sem commit.** O usuário escolheu a regra de deduplicação descrita no item 6.

| # | Correção | Arquivos |
|---|---|---|
| 1 | Raízes de artefato incluem o repositório da própria tarefa; a migração grava `repository`; `conferir` só lê tarefa legada; a 1ª gravação guarda `progresso.legado.md`; artefato fora das raízes vira `FORA-DO-ESCOPO` em vez de exceção; `PROXIMA` e `pendentes` apontam a etapa real e listam o legado sem prova à parte; `pendentes` mostra a tarefa inválida sem derrubar as outras; a validação aceita hash de 12 a 64 caracteres, como a migração | `scripts/estado_tarefa.py` |
| 2 | Mensagem `<synthetic>` do Claude Code é ignorada | `scripts/adaptadores.py` |
| 3 | `validar-lote` usa `--no-renames --name-status` e recusa tudo que não for `A` | `scripts/aprendizado.py` |
| 4 | `pulada` exige motivo; sem motivo, não vale como etapa resolvida | `scripts/estado_tarefa.py` |
| 5 | Gitlink registrado como `160000` (só o que o `git ls-files -s` marca assim) e recusado como escopo de arquivo; `nova-tarefa.sh` apaga a pasta que criou se o `init` falhar | `scripts/estado_tarefa.py`, `scripts/nova-tarefa.sh` |
| 6 | Falha antes do `create` devolve a ficha a `local` e anula a autorização; `conciliar-ausente --confirmo-que-nao-existe` tira do `incerto`. Deduplicação por **meio-termo**, decidido pelo usuário: mesma categoria é a mesma ficha, exceto quando a anterior foi enviada e a versão mudou; recusa vale em qualquer versão | `scripts/aprendizado.py`, `referencias/aprendizado.md` |
| 7 | A regra da descrição começando pelo papel volta ao SKILL, na frase do `medir.sh` | `SKILL.md` |
| 8 | `nova-tarefa.sh` não copia o molde de `progresso.md`; o arquivo nasce do `estado.json` | `scripts/nova-tarefa.sh` |
| 9 | Versão 1.6.0 no SKILL e no `plugin.json`; CHANGELOG com a seção 1.6.0 | `SKILL.md`, `.claude-plugin/plugin.json`, `CHANGELOG.md` |
| 10 | Caminhos absolutos saíram deste relatório; notas de túnel saíram do `MEMORY.md` | este relatório, `MEMORY.md` |

**Validação (reproduzida pelo Claude Code):** `bash scripts/testar.sh` saiu com 0, com 189 testes Python e 11 suítes shell (`teste-nova-tarefa.sh` foi de 30 para 37 casos), `checar-skill` em ordem e `git diff --check` limpo.

- **Testes novos:** tarefa legada com `../../perfil.md` retomando na etapa real; `pendentes` com uma tarefa inválida; `pulada` sem motivo; submódulo; linha `<synthetic>`; troca de ficha no lote; saída do `incerto`; ficha enviada voltando em versão nova; recusa valendo em versão nova; tarefa nova sem `migrated_from`; `init` que falha sem deixar pasta.
- **Testes antigos com nova expectativa** (comportamento mudado de propósito, nenhum perdeu proteção): três de falha de rede esperam `local` quando a falha vem antes do `create`, e o de conciliação chega ao `incerto` por falha durante o `create`; quatro de lote simulam `--name-status`; o de migração confere que `conferir` não grava e que a 1ª marcação guarda o original.
- **Reproduções originais repetidas contra a árvore corrigida:** nas cópias das tarefas do Ciclo, `conferir` responde `PROXIMA 6 Construir` (ou `3 Propor`), sem criar `estado.json` e sem tocar o `progresso.md`. O parser não recusa nenhum dos 40 transcripts reais, e o `coletar` com linha `<synthetic>` soma input 30 e output 12. O lote com troca de ficha é recusado. A queda de rede antes do `create` deixa a ficha em `local`.

**Limites que continuam:**

- `conferir` em tarefa legada sai com 1 enquanto houver etapa sem prova. Para fechar, cada etapa precisa ser marcada de novo com `--evidence` ou `--attempt`.
- O monitor continua abortando por qualquer outra linha completa que não seja JSON válido; só o caso `<synthetic>` foi tratado.
- `conciliar-ausente` confia na conferência manual da pessoa, sem consultar o GitHub.
- `docs/validacao/estado-final.json` e `resultados.json` descrevem o `9d773be` e não foram regenerados para estas correções.

Lição para quem constrói: os testes cobriram bem os contratos novos, mas quase nunca rodaram contra dado real ou contra o formato que a versão anterior produzia. Três dos defeitos (1, 2 e 5) aparecem na primeira tentativa com tarefas reais, transcripts reais ou um repositório com submódulo. Antes de declarar compatibilidade, rode os scripts novos contra uma cópia de `.claude/seiva` de um projeto em uso e contra transcripts do próprio aplicativo.

## Pedido ao Claude Code

Avalie também clareza didática, custo adicional de apresentação/reflexão/aprendizado, validade das alegações de privacidade, consentimento de envio e separação entre dados recebidos e execução privilegiada. Confira a adaptação das seis capacidades e seus limites; não aceite o pacote de triagem como prova de sandbox executado.

Revise estas mudanças de forma independente. Não aceite este relatório como prova suficiente: confira o diff, os contratos e os testes relevantes. Julgue correção, economia total de tokens, seleção de agentes, precisão e limites do monitoramento, compatibilidade entre aplicativos, preservação da identidade de julianossr e papel do Resina. Para cada achado, apresente severidade, arquivo:linha, cenário reproduzível, evidência e correção proposta. Conclua com aprovado, aprovado com ressalvas ou mudanças necessárias. Não altere os arquivos durante esta primeira avaliação.
