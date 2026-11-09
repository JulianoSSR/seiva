# Registro de mudanças

## Em desenvolvimento

- Seis capacidades adaptadas com prova/reflexão privadas obrigatórias, candidato não comprovado sem sugestão, extração mecânica de cache e microajuste apenas conceitual. Logs/caminhos/hashes da origem não são exportados; ajuste de regras e execução privilegiada não ocorrem durante a tarefa cliente.

- Comunicação didática: conclusão primeiro, linguagem simples e visuais conforme dados/fluxo, sem agentes adicionais de formatação.
- Aprendizado por eventos, catálogo fechado sem conteúdo do projeto, alvo estimado de 100 tokens, deduplicação e frequência limitada. Consentimento vinculado à ficha/título/corpo/canal; falha preserva sem retry cego.
- Recepção validada de dados e papel Mantenedor separados da execução privilegiada; pacote de triagem não inicia modelo nem habilita merge.

- Núcleo independente de aplicativo, menor e carregado por assunto. Modelos são escolhidos pela capacidade e pelo consumo total previsto, incluindo revisão, retrabalho e retomada; preço por token fica separado.
- Revisão pode conferir o mapa do batedor, descobrir dependentes e ampliar a leitura até arquivo inteiro com motivo breve. Graves exigem correção verificada ou aceite explícito permitido; teto interrompe sem aprovar.
- Estado canônico em JSON, base da tarefa e escopo explícito. Conclusão vincula tentativa, artefatos, hashes e evidência; Markdown é projeção. Migração legada preserva histórico e exige revalidar conclusão sem prova.
- Monitor e seleção entram sob demanda, com capacidades detectadas, fonte e intervalo de uso, reserva compartilhada e duração de acompanhamento delimitada. Sem agentes ou configuração global persistente.
- Resina acompanha entrada, validação, autorização e sink. Prova executável requer escopo autorizado, isolamento e dados sintéticos; outra instância julga.
- Execução e aprendizado local são privados; documentação, casos e avaliações sanitizados são versionáveis. Notificação de término e sessão inteira não substituem contabilidade atribuída à tarefa.
- Símbolo original incorporado sem mudar geometria ou cores; README usa caminho relativo e texto alternativo.
- Protocolo de avaliação em `docs/AVALIACOES.md` distingue validação funcional de economia demonstrada. Novos casos cobrem independência, fechamento, tentativas antigas, concorrência, isolamento, custo e monitor.

## 1.5.0 (2026-11-02)

O mestre invasor, apelidado Resina, pedido em 2026-10-28: "testar ao limite como invadir e/ou corromper o projeto, listar todas as falhas e traçar um plano de correção".

- `papeis/invasor.md` reescrito. Sai a regra de domínio que o texto antigo trazia de um projeto (fere L2): o que não pode vazar ou quebrar vem agora das seções L, S e R do perfil. Dois modos, **varredura** (o sistema inteiro) e **mudança** (o diff e o caminho que ele abre). O método tem 5 passos: modelo de ameaça, mapa de portas, falha conhecida com teste de alcance, dia zero e prova por `arquivo:linha`. No dia zero entram as famílias de antes e técnicas novas: variante de bug já registrado, cadeia de dois achados menores, invariante do perfil, corrida, limite, estado pulado, dois leitores, erro que se esconde, valor fixo silencioso e dígito não conferido. As três últimas vieram de casos reais de projeto, escritas sem domínio.
- A saída ganha `COMANDOS RODADOS`, `FALHA CONHECIDA`, `MAPA DE PORTAS` e `PLANO DE CORREÇÃO`. O plano cita só o ID do achado, para o `julgar-pre.sh` não contar em dobro, e põe primeiro o que se alcança sem login.
- O Resina só lê: não roda código, teste nem script do projeto, porque teste de projeto pode ler configuração real e alcançar a produção. Também não usa rede, e essa é outra regra do papel (ver Ficou de fora). A auditoria de dependências do ecossistema é do orquestrador, antes do disparo, com a saída em arquivo; sem ela, o relatório diz "falha conhecida não coberta".
- Gatilhos (`SKILL.md` etapas 0.3 e 8, `referencias/triagem.md`, `referencias/revisao.md`, `referencias/terreno.md`, `moldes/perfil.md`):
  - varredura na criação do perfil, uma vez em projeto cuja linha `Varredura do Resina` diz `nunca` ou `adiada` ou não existe, a pedido e em N3 cujo objeto é segurança (endurecer o sistema, fechar brecha);
  - modo mudança no portão do código de N2 e N3 quando a lente de segurança acionou, no lugar dela; em N2 entra mesmo que a lente já tenha atacado o plano (exceção nova em `referencias/revisao.md`), e não entra no diff do conserto de uma varredura da mesma tarefa;
  - na 1ª varredura, sem histórico de custo do Resina, o `--leva` não o conta: o orquestrador diz que o custo é desconhecido e pergunta;
  - o perfil grava a resposta, e com `recusada` a varredura só volta a pedido;
  - `forte` nos dois modos, por decisão do usuário ("para evitar que agente deixe passar algo"), e o revisor do relatório em `padrao`, de contexto limpo.
- `referencias/contratos.md`: regra do pacote do Resina (primeiro ID livre, auditoria que só lê manifesto e lockfile, relatório fora do commit enquanto houver brecha aberta). `testes/casos.md`: seção Segurança, casos S1 a S8. Casos automáticos novos: `teste-medir.sh` (S7, a descrição `Mestre invasor (Resina):` conta como invasor) e `teste-julgar-pre.sh` (JP-R, relatório com plano de correção conta cada achado uma vez; JP-R2, com `achados.md` já preenchido, o ID que o relatório cita é o que fica gravado).
- **Projeto que já usa a seiva:** o perfil não tem a linha `Varredura do Resina`, então a próxima tarefa oferece a varredura uma vez. Ela é cara (ver Custo).
- **Ficou de fora:** a prova executada numa cópia isolada do repositório, sem rede, que estava no plano como `scripts/isolado.sh`. Saiu por decisão do usuário e volta em versão própria (pendência 1.16). Sem ela, só ler e não usar rede são regras do papel, sem trava técnica: o subagente tem Bash solto e, conforme o harness, busca na web. A barreira é a lista `COMANDOS RODADOS`, escrita pelo próprio Resina e conferida pelo revisor (caso S5).
- Custo (P1): a varredura conta 2 agentes à parte (o Resina em opus e o revisor em sonnet). Em N3, o modo mudança troca a lente de segurança pelo Resina e soma o revisor: 1 agente a mais. Em N2 a lente não volta no diff, então ele soma 2 ao adversário: o Resina em opus e o revisor em sonnet. Medido pelo `medir.sh`: o ensaio, com o Resina em sonnet sobre 6 scripts da seiva, custou cerca de 357 mil tokens ponderados. É o único número medido; uma varredura em opus sobre um sistema inteiro custa mais, e quanto, só a primeira vai dizer.

Revisão: tarefa N2 enxuta. Plano do orquestrador, atacado por um adversário opus e uma lente de segurança e contrato em sonnet, de contexto limpo: 16 achados, 15 confirmados e 1 adiado (`--leva` não separa os dois modos, pendência 1.17). O ensaio do papel rodou só de leitura sobre 6 scripts da própria seiva. O relatório saiu com as 8 seções na ordem, e o `julgar-pre.sh` leu os 9 achados sem aviso. O único desvio foi uma lente inventada, que motivou a frase nova sobre a lente do achado. Os achados do ensaio sobre os scripts da seiva não foram revisados e estão na pendência 1.18. No código, o diff passou por um adversário sonnet de contexto limpo, de modelo diferente do orquestrador (opus), em uma rodada: das 16 referências do plano, 6 mitigadas, 9 sem objeto pela saída da prova isolada e 1 aberta de propósito (a pendência 1.17). Ele achou 1 defeito ALTO, 5 MÉDIOS e 3 suspeitas, todos confirmados: o gatilho do modo mudança tinha três leituras e um custo errado; o plano de correção podia citar o ID errado; o relatório podia ir para o commit; a rede aparecia como trava; a 1ª varredura passava pela guarda de orçamento sem custo; "N3 de segurança" não tinha definição; o `SKILL.md` crescia sem tirar texto; a auditoria podia instalar pacote; e a comparação de custo misturava escopos. O usuário decidiu o gatilho em N2 e o que é N3 de segurança. O orquestrador corrigiu como ajuste, sem 2ª rodada, porque em N2 só CRÍTICO reabre o portão do código; essa correção não teve revisor independente.

## 1.4.1 (2026-10-28)

A assinatura da skill, pedida em 2026-10-26.

- `SKILL.md`: `metadata.author: "JulianoSSR"` no frontmatter. Para o arquivo continuar com 164 linhas, as duas primeiras regras do Orquestrador enxuto viraram uma só, com o mesmo texto.
- Os 13 scripts de `scripts/` ganham `# seiva · JulianoSSR · MIT` na 2ª linha, logo depois do shebang. Os de `testes/scripts/` ficam sem, porque o pedido era só `scripts/`.
- `checar-skill.sh` passa a reprovar script de `scripts/` sem o cabeçalho na 2ª linha e frontmatter sem o `author`. Assim, um script novo não nasce sem assinatura sem que ninguém perceba. Dois casos novos em `testes/scripts/teste-checar-skill.sh`, e o `CONTRIBUTING.md` avisa quem for mandar script novo.
- Quem instalou a statusline (`~/.claude/statusline-seiva.sh`) vai ver `statusline desatualizada` na linha do orçamento até rodar a linha de atualização de `referencias/harness.md` (seção Orçamento vivo). O script mudou só no comentário da assinatura, mas o `orcamento.sh` compara a cópia instalada byte a byte. O estado e o código de saída não mudam.
- O arquivo de aprendizado passa a se chamar `julianossr.md`, com a 1ª linha `# julianossr.md · o que a seiva aprendeu neste projeto` (`SKILL.md`, etapa 9; `referencias/evolucao.md`; `CONTRIBUTING.md`; `testes/casos.md`). Projeto que já tem `aprendizado.md` continua funcionando: o orquestrador renomeia no fechamento da primeira tarefa feita com a 1.4.1 e, se achar os dois arquivos, pergunta antes de juntar (nota em `evolucao.md`, caso E4). As entradas antigas deste registro continuam citando `aprendizado.md`, porque é o nome que valia na época.
- Custo (P1): nenhum agente nem chamada a mais; o `checar-skill.sh` lê 13 linhas a mais.

Revisão: tarefa N1, construída pelo orquestrador. O diff foi revisado por um agente sonnet de contexto limpo (o orquestrador é opus), com o papel de adversário e a lente de contrato. Ele achou 2 MÉDIO, os dois corrigidos: a nota de compatibilidade mandava trocar "só a 1ª linha" do arquivo antigo, que podia ser a linha de uma tarefa; e a statusline instalada passaria a acusar versão desatualizada sem que o registro dissesse isso. Das 3 suspeitas, uma virou o aviso no `CONTRIBUTING.md`.

## 1.4.0 (2026-10-28)

Scripts que respondiam errado sem avisar, o `/usage` lido sozinho e o freio da janela calibrado pela leitura da própria janela. Saiu num commit só com o que seria a 1.3.1, que não chegou a ser publicada. Três dos defeitos escaparam da revisão da 1.2.3 (escapes E-1, E-2 e E-3 do `aprendizado.md`).

- `progresso.sh`: `pendentes` com a pasta de uma tarefa sai com código 2 e diz qual pasta espera; `marcar` e `conferir` com a pasta de trabalho também saem com 2, sem criar `progresso.md` nela. Pasta com `tarefas/` e um `progresso.md` solto continua sendo de trabalho. Caso real (E-1): em 2026-10-15, no ciclo-arboris, `pendentes` com a pasta da tarefa respondeu "nenhuma tarefa por terminar" com a tarefa parada na etapa 6.
- Trava de pasta em todos os scripts que recebem pasta (`medir.sh`, `julgar-pre.sh`, `ficha-tecnica.sh`, `diff-tarefa.sh`, `orcamento-local.sh --tarefa`, `progresso.sh` e, ao contrário, `nova-tarefa.sh`): a pasta do tipo vizinho (de trabalho, a `tarefas/` ou, no `nova-tarefa.sh`, a de uma tarefa) sai com código 2, a mensagem diz qual pasta espera e onde ela fica, e nada é criado. O caminho é resolvido antes (`tarefas/.` conta como `tarefas`). Caso real (E-3): a lente da tarefa 2026-10-26-pendencias-scripts viu `medir.sh --fechar` e `julgar-pre.sh` gravarem `sessoes`, `medicao.md` e `achados.md` na pasta de trabalho.
- `julgar-pre.sh`: relatório com achado fora do formato (`[L-n]`, `### L-1 (ALTO)`, `Arquivo:`, `Problema:`, `Defeito:` solto) ganha aviso na lista de não contados, com `relatório:linha` e sem texto do relatório, e a 1ª linha termina em `N não contado(s): ver a lista abaixo`. Suspeita `S-n` e relatório que declara zero achados não avisam. Caso real (E-2): as lentes do plano C da tarefa 2026-10-05 do ciclo-arboris usaram `[L-n]`, e o script devolveu 0 achados em silêncio. Medido em 122 relatórios reais: os 2 relatórios de lente fora do formato passam a avisar; nenhum relatório de revisor válido avisa.
- `medir.sh`:
  - `--sessao` conta a sessão inteira mesmo com marca, como a ajuda prometia. Sessão com uma marca só, ou com marcas no mesmo segundo, tem janela vazia: não conta nada e a saída diz, com os dois caminhos. Caso real: a sessão d17eed24 (14/10) saiu com orquestrador 0 sem aviso.
  - o nome da tarefa só conta inteiro: `x-tarefa` não leva mais os agentes da `x-tarefa-2` na mesma sessão (achado A-12 da revisão desta versão, reproduzido).
  - a linha do orquestrador no histórico ganha o hash do nome da tarefa na chave (`orq-<sessão>:<12 do sha256>`): duas tarefas na mesma sessão não se apagam, e o histórico continua sem o nome.
  - agente com aviso de fim no transcript principal entra no histórico mesmo mexido há menos de 2 minutos. Caso real: o revisor desta versão saiu "(rodando)" no `medicao.md` de 2026-10-27 e ficou fora do histórico.
- `orcamento-local.sh`:
  - o `/usage` que o usuário roda no terminal ou na aba Code vira leitura sozinho, pelo transcript (`usageReport`, desde o Claude Code 2.1.299, ou o texto em inglês), com a hora exata e o fim da janela; a leitura colada com o mesmo percentual até 15 minutos antes ou depois não duplica. Caso real: em 2026-10-26 quatro leituras foram coladas à mão numa noite, com o registro já no transcript. Conferido nesta máquina: as de 2026-10-20 (51%), 2026-10-26 23:30 (46%) e 2026-10-27 00:56 (82%) entraram, e as duas manuais iguais saíram.
  - com leitura de 10% ou mais na janela aberta, o limite é a mediana do que essas leituras dão, e a linha diz `leitura da janela`; sem ela, vale o menor dos 5 pontos, como antes. Caso real: em 2026-10-26 às 21:57 o menor dos pontos estimava 109% e o `/usage` dizia 82% (as leituras davam ≈ 3,5 mi; os limites batidos de 16 a 20/10, de 1,6 a 2,3 mi). Decisão do usuário em 2026-10-27.
  - leitura abaixo de 10% só ancora a execução (o `--calibrar` manual já recusava abaixo de 10%), e o `--leituras` não quebra com ela; o `--leituras` diz a fonte, e o `--descartar` recusa leitura do transcript, que voltaria na varredura seguinte.
  - sem statusline, o 7d sai da leitura do `/usage` feita na janela de 5 horas aberta.
  - registro do `/usage` em formato que o script não reconhece vira aviso na linha.
  - `--em` e `--descartar` aceitam a hora local do sistema (`20:26`, `20:26:15`, `8:21am`) e ISO com deslocamento (`-03:00`), além de epoch e ISO com `Z`; ISO sem fuso continua recusado. A confirmação mostra o fuso e a hora em UTC, e o `--leituras` mostra a hora local. Caso real: em 2026-10-21 a hora local do `/usage`, convertida à mão para UTC, saiu errada e o script recusou.
- Documentos: `SKILL.md` (só as linhas da versão e o nome da pasta em dois comandos; continua com 164 linhas), `retomada.md`, `revisao.md`, `harness.md` (leitura do `/usage`, regra da janela, medição, e o caminho oficial de uso do plano no Codex), `evolucao.md`, `moldes/progresso.md`. Casos novos em `testes/casos.md`: C16, C17, O16 a O20, R6, R7 e R8. Testes: progresso 31 → 118, julgar-pre 55 → 122, medir 56 → 173, orcamento-local 144 → 419, ficha-tecnica 45 → 57, e dois novos, diff-tarefa (16) e nova-tarefa (30). Os casos que cobrem os defeitos reprovam no script de antes.
- Custo (P1): nenhuma chamada nova; no máximo uma linha de aviso a mais por relatório ou por execução.

Limites:
- relatório em prosa pura, sem campo nem cabeçalho reconhecível, segue com "0 achados" sem aviso;
- o `julgar-pre.sh` pode avisar em dobro um bloco de severidade não reconhecida, avisar à toa uma hipótese numerada `R-n (ALTO)` ao lado de achado real, e avisar uma suspeita escrita como `[S-1] ALTO` com `Onde:` debaixo de `SUSPEITAS`; os três erram para o lado do aviso;
- `--sessao` em sessão longa conta trabalho de fora da tarefa (a menos que outra tarefa a marque, e aí sai `estimado`); janela vazia não conta nem a resposta do mesmo segundo da marca;
- a trava reconhece a pasta `tarefas/` pelo nome e por ter ao menos uma tarefa dentro: uma `tarefas/` vazia não é reconhecida, e uma pasta de trabalho de projeto novo (ainda sem `tarefas/`) passada no lugar da tarefa também não;
- a linha antiga `orq-<sessão>` do histórico não é migrada: medir de novo uma tarefa da 1.3.0 deixa o orquestrador dela duplicado no arquivo (a previsão do `--leva` não usa essas linhas); agente retomado depois do aviso de fim conta como encerrado até a medição seguinte;
- só há leitura automática quando o usuário roda `/usage`; a tela de uso do app colada como mensagem continua pedindo `--calibrar`; a leitura de uma janela aberta fora destes transcripts (claude.ai, outra máquina) sai com o gasto visto pela metade, o que erra para o lado do freio; com número par de leituras, a mediana é a de baixo; o 7d mostrado pode ter até 5 horas, sem a hora na linha;
- o limite muda com o tipo de trabalho (a saída não fecha com a conta oficial, 39aa8a8): leitura feita numa fase de leitura pode subestimar a de implementação até o próximo `/usage`;
- a hora repetida da volta do horário de verão pode errar em até 1 hora; o recibo usa o fuso com que o jq roda; epoch com mais de 11 dígitos passa a ser recusado; hora cheia sem minutos (`8pm`) não é aceita, porque nenhum formato real a traz;
- jq 1.6 e 1.7 não foram testados (só o 1.8.1). A comparação do nome da tarefa passou a usar code points para valer nos dois, mas nenhum caso reprova no 1.8.1 sem ela;
- a leitura do `/usage` não diz de que conta é: com duas contas Claude na mesma máquina, o `/usage` de uma vira leitura da outra, e o `--descartar` não a tira; não se sabe se, sem janela ativa, o `usageReport` omite o item `session` (aí viria um aviso de formato à toa); a dedupe de 15 minutos não confere se as duas leituras são da mesma janela;
- ficam sem teste: o aviso de fim de agente dentro de mensagem em lista de blocos, o arredondamento do fim da janela para o minuto, a semana já reiniciada no 7d e o caminho `shasum`/`cksum` do hash, quando falta o `sha256sum`.
- Revisão: duas tarefas. A da 1.3.1 (progresso, julgar-pre, medir e `--em`): plano de construtor sonnet atacado por adversário sonnet de contexto limpo e lente de contrato e operação opus, 11 achados corrigidos na rodada 2; código com um revisor opus (verificação e ataque juntos), C1 a C12 ok, 3 MÉDIO, dois corrigidos e o da atribuição por trecho levado para esta versão. A dos defeitos antigos (trava de pasta, medir, `/usage`): plano escrito pelo orquestrador e atacado por adversário opus de contexto limpo, 5 ALTO e 3 MÉDIO corrigidos no plano sem 2ª rodada; três implementadores sonnet; código com um revisor opus (verificação e ataque juntos), C1 a C7 ok, 1 ALTO (o nome da tarefa com acento antes no jq 1.6 e 1.7, que o `indices` conta em byte) e 1 BAIXO (texto do `--calibrar auto`), os dois corrigidos.

## 1.3.0 (2026-10-14)

Custo medido pelos transcripts, e um histórico que prevê o custo da próxima leva e melhora a cada tarefa medida.

- `medir.sh` (novo): mede uma tarefa pelos transcripts do Claude Code, com a régua do orçamento. Cada subagente é atribuído à tarefa pelo pacote, que cita a pasta. A parte do orquestrador é a sessão entre a 1ª e a última marca da tarefa. Quando a sessão serviu a outra tarefa, essa parte é dividida e sai `estimado`. Conta corridas (pacote e retomadas) e quedas (erros da API). Grava `<pasta>/medicao.md` e o histórico `custos.jsonl` no cache, em modo 600 e sem texto: nem descrição, nem nome de tarefa, nem caminho. Tarefa de antes desta versão é medida com `--sessao <id>`, e sem sessão o script lista as candidatas do projeto. Motivo, medido em duas tarefas reais do ciclo-arboris: o número da notificação de fim do subagente perde a leitura de cache e as corridas que caíram no limite. Um construtor informou 269 mil e gastou 1,10 mi. Na tarefa do ponto eletrônico, 2,74 mi (21% da sessão) foram de agentes que caíram no limite e não apareciam em número nenhum do registro.
- `orcamento-local.sh --leva "<papel>:<modelo> ..."`: prevê o custo da leva pela mediana das corridas limpas (sem queda e sem retomada) de cada papel e modelo no histórico, e diz se ela cabe no que resta da janela de 5 horas (`cabe`, `NÃO CABE` ou `a parte conhecida cabe`). Item com menos de 3 corridas limpas fica fora da soma, com o nome. O código de saída continua sendo o do `orcamento.sh`. Papel ou modelo fora do padrão é uso errado, para a previsão não falhar em silêncio por um nome digitado errado.
- Marcas de sessão em `<pasta>/sessoes`: o `nova-tarefa.sh` (com `CLAUDE_CODE_SESSION_ID`), o `orcamento-local.sh --tarefa` a cada leva e o `medir.sh --fechar` no fechamento.
- SKILL.md: a etapa 9 roda `medir.sh --fechar`; antes de cada leva vai `--leva`, e com `NÃO CABE` a leva é dividida; a descrição de cada agente começa pelo papel. `modelos.md`, `evolucao.md` (a linha do aprendizado usa os números do `medir.sh`), `retomada.md`, `harness.md` (seção "Medição da tarefa", com os limites) e o molde do registro (a coluna Tokens vira só conferência).
- Testes: `teste-medir.sh` (56 casos, novo) e 16 casos novos no `teste-orcamento-local.sh` (144). Casos de uso O14 (leva que não cabe) e O15 (fechamento com medição).

Limites, também em `harness.md`:
- cada instalação aprende só com o próprio uso. Não há troca de histórico entre usuários, porque isso exigiria mandar dado para fora da máquina;
- a previsão é a mediana do papel, não da tarefa: freio para não abrir leva que não cabe, não orçamento exato;
- a régua pesa todos os modelos igual. O histórico guarda entrada e leitura de cache separadas para que o peso por modelo possa ser medido depois;
- a retomada de um agente é reconhecida por não começar com tag, e o lembrete do harness começa com uma. Se o formato do Claude Code mudar, a contagem de corridas erra;
- no orquestrador, entra tudo o que a sessão fez entre as marcas, até pergunta do usuário fora da tarefa;
- feito sem revisor independente (a janela de 5 horas estava em 82% quando o escopo foi aprovado); revisão Sonnet pendente.

## 1.2.3 (2026-10-14)

Correções da 1ª revisão independente dos scripts da 1.2.0 à 1.2.2 (diff `96f8523^..e2a5bbb`, lentes contrato, operação e segurança): 15 itens, 2 ALTO e 7 MÉDIO confirmados, 4 BAIXO ou incertos, 2 falsos. Todos os confirmados e os adiados entraram.

- `julgar-pre.sh`: a severidade vale em qualquer caixa e com ou sem acento. Caso real (reproduzido): um `[A-2] Crítico` sumia sem aviso, e o Onde e o Defeito dele caíam por cima do achado anterior. O cabeçalho vale com qualquer prefixo antes do `[A-n]` (`1)`, `Achado`, negrito, crase). O que não fecha (cabeçalho sem severidade, bloco sem Onde nem Defeito, `Onde:` sem cabeçalho reconhecido) não conta, sai listado com `relatório:linha` e nunca cai por cima do achado anterior. Também lê `REFERÊNCIAS: A-n → ...` na linha do título, numera a partir só das linhas de achado que ele mesmo escreveu (um "A-9999" citado num Defeito não puxa mais a numeração), mascara os textos do revisor campo a campo (lente, Onde, Defeito, referência) e cria o `achados.md` com modo 600. A máscara por campo veio da 2ª rodada: mascarar o bloco inteiro deixava um `MINHA_KEY` no Defeito apagar a origem da linha, e um BEGIN de chave sem END no texto apagava todos os achados seguintes do `achados.md`.
- `orcamento-local.sh`: leitura do `/usage` errada tem volta. A linha de cada leitura nova diz a hora gravada e o comando para desfazer, e avisa quando o limite que ela dá passa do dobro ou fica abaixo da metade dos outros pontos. `--leituras` lista e `--descartar <hora|ultima>` apaga. Caso real: num ensaio do revisor, um 91% digitado como 19% deixava a janela seguinte em `ok` com a conta quase no limite, e nem o `--calibrar auto` apagava a leitura.
- `orcamento-local.sh`: calibração ilegível ou de forma desconhecida é guardada como `calibracao.json.invalido-<epoch>-<pid>` e refeita, com aviso em todas as saídas, inclusive `--leituras`, `--descartar` e erro do `--calibrar`. Antes era regravada por cima em silêncio, ou deixava o estado em `desligado` com a causa errada em toda execução. A leitura da 1.2.0 (campo `manual`) vira a 1ª leitura.
- `orcamento-local.sh`: duas execuções ao mesmo tempo esperam uma pela outra (`flock`); `.trava` que não se abre deixa seguir sem trava, com aviso, em vez de dizer que outra execução a segura. Antes, uma execução lenta apagava a leitura que outra tinha acabado de gravar (provado pelo revisor; o teste novo reprova a versão antiga).
- `orcamento-local.sh`: transcript desta sessão com resposta do modelo e nenhum registro de uso reconhecível dá `desligado` ("o formato do Claude Code pode ter mudado"), em vez de `ok` com 0%. Resposta de erro da API (529 e afins) não conta como resposta, para uma sessão que começou com erro não acusar formato.
- `orcamento-local.sh`: a janela de contexto de 1 milhão se prova pela própria sessão acima de 200 mil. O histórico do modelo só vale por 30 dias e sai marcado como `janela deduzida`. Medido em 2026-10-14: o transcript grava o mesmo nome de modelo nas janelas de 200 mil e de 1 milhão (nem `message.model` nem `requestedModel` trazem o `[1m]`). O `contexto_max` da 1.2.2 é migrado.
- `orcamento-local.sh`: com acento no caminho do projeto, a sessão deduzida procura a pasta com um hífen por caractere e, de reserva, um por byte.
- `ficha-tecnica.sh`: citação com caminho absoluto de fora, com `..` ou por link que sai do repositório não é lida, e aparece como pulada, "fora do repositório". A chave privada é trocada linha a linha, mantendo a numeração, antes de cortar o trecho. Além do corpo da chave em claro que o revisor apontou, o teste novo achou outro defeito: um trecho com o BEGIN e sem o END engolia todos os trechos seguintes do `trechos.md`.
- `progresso.sh`: `pendentes` deixa de listar tarefa com a etapa 9 `pulada`, como o `conferir` já fazia.
- Casos C14, C15, O12 e O13 em `testes/casos.md`; 51 casos novos em `teste-orcamento-local.sh`, 28 em `teste-julgar-pre.sh`, 10 em `teste-ficha-tecnica.sh` e 1 em `teste-progresso.sh`. Rodada contra os scripts da 1.2.2, a suíte nova reprova 51 casos. Os outros 39 cobrem o que a 1.2.2 já fazia certo e a 1ª versão desta correção quebrou: os 8 casos de prefixo antes do `[A-n]` passam na 1.2.2 e reprovavam a correção da 1ª rodada (regressão achada pela 2ª revisão, A-16).

Limitações que ficam: a janela deduzida ainda erra para quem alterna entre 200 mil e 1 milhão no mesmo modelo dentro de 30 dias (`SEIVA_JANELA_CONTEXTO` resolve); a regra do Claude Code para nome de pasta com caractere fora do ASCII e para caminho muito longo não foi medida; sem `flock` (macOS sem util-linux) a trava não existe, e a linha avisa; o aviso de formato só olha o transcript desta sessão e não pega a troca do campo `type`.

Revisão: duas rodadas de subagente de contexto limpo, em outro modelo (Sonnet; o construtor foi Opus). A 1ª revisou os scripts da 1.2.0 à 1.2.2 (250.709 tokens, 15 itens). A 2ª revisou a correção (202.887 tokens): os 13 achados confirmados ou adiados ficaram mitigados, e ela achou 3 defeitos novos, dois ALTO no `julgar-pre.sh` (um deles regressão da própria correção) e um MÉDIO no `orcamento-local.sh`, além de 2 suspeitas que também entraram. A correção desses 3 e das 2 suspeitas não teve revisor: pela regra do N2, só CRÍTICO abre 3ª rodada. Foi conferida pelos testes escritos antes do conserto (cada um reprovou a versão anterior) e pelos dois relatórios reais da revisão, que o `julgar-pre.sh` lê com 15 e 3 achados e 12 referências, sem aviso falso.

## 1.2.2 (2026-10-13)

- Leitura do `/usage` como âncora. Caso real: a 2ª leitura (90% às 11:21, contra 73% às 11:04) não fechou com a 1ª em nenhum peso não negativo para a escrita de cache, com a leitura de cache entre 0,01 e 0,1. O mais provável é gasto na janela que os transcripts não veem, como o chat do claude.ai. Com uma leitura dentro da janela aberta, o percentual parte do valor lido, e só o gasto depois dela é estimado, sobre o menor limite entre os pontos. Logo depois de calibrar, a linha deu 93%: os 90% lidos mais 3% estimados.
- O "Em aberto" da 1.2.1 fica sem medida: as duas leituras não permitem isolar o peso da escrita de cache.
- 3 casos novos e 5 ajustados em `teste-orcamento-local.sh`.

Revisão: nenhuma revisão independente; feita pelo orquestrador, com os testes automáticos.

## 1.2.1 (2026-10-13)

- Calibração por pontos. Caso real: na primeira conferência com o `/usage`, a regra da 1.2.0 (mediana dos 20 limites batidos mais recentes) dava cerca de 40% quando o oficial marcava 73%, e nenhum peso testado explicou a diferença. Agora cada leitura do `/usage` também vale como ponto (`--calibrar <pct> --em <hora do relatório>`, contando só o gasto da janela até aquela hora), e o limite é o menor dos 5 pontos mais recentes.
- Pausa longa também é parada: com contexto acima de 200 mil, a entrega avisa que voltar depois de 1 hora recria o cache inteiro. Caso real: na mesma sessão, a volta de uma pausa de 70 minutos gravou 373.540 tokens de cache numa resposta só.
- Caso R5 novo e O11 reescrito; 11 casos novos em `teste-orcamento-local.sh`.

Em aberto: com a leitura de 73% como base, aquela resposta levou a estimativa a mais de 100% sem a conta bater no limite: a escrita de cache pesa menos na conta oficial do que o peso 1 do script. Uma 2ª leitura do `/usage` mede quanto.

Revisão: nenhuma revisão independente; feita pelo orquestrador, com os testes automáticos.

## 1.2.0 (2026-10-13)

Objetivo: o mesmo processo (revisão independente, prova, segurança) com menos tokens, e funcionando no app desktop do Claude Code, onde a statusline não roda. Plano de origem: `plano-execucao-otimizacao-seiva.md`, do autor.

- **Orçamento vivo pelos transcripts** (`scripts/orcamento-local.sh`). Lê os transcripts que o terminal e o app desktop gravam em `~/.claude/projects/`, estima o uso da janela de 5 horas e mede o contexto da sessão. Grava no formato do `orcamento.json` e passa a decisão ao `orcamento.sh`, com os mesmos limiares. Caso real: a seiva roda quase sempre no app desktop, onde o orçamento vivo da 1.1 ficava desligado. Medido nesta máquina: a 1ª varredura de 30 dias leva cerca de 5 segundos, e as seguintes, menos de 1.
  - Calibração automática: o transcript guarda "You've hit your session limit · resets <hora>", e o total de cada janela que bateu no limite vale 100%. Calibração manual por `--calibrar <percentual do /usage>`.
  - O peso padrão da leitura de cache é 0,01, e não 0,1 como o plano propunha: nas 53 vezes que a conta do autor bateu no limite, 0,01 deixou o total das janelas com dispersão de 28%, e 0,1, com 42%. `PESO_CACHE_LEITURA` muda o peso.
  - A janela de contexto vem do histórico do modelo (1 milhão para o que já passou de 200 mil), porque as sessões do autor passam de 600 mil tokens de contexto.
  - `orcamento.sh` aceita os campos novos `fonte`, `cinco_horas.motivo` e `contexto.desta_sessao`; com `fonte: "jsonl"` não dá os avisos de statusline nem de app desktop. Contexto desta sessão em 70% ou mais vira `parar`. Arquivo da statusline lido à mão se comporta como antes.
- **Retomada barata** (`scripts/progresso.sh`, `moldes/progresso.md`, `moldes/contexto-tarefa.md`, `referencias/retomada.md`). Cada tarefa nasce com o checklist das etapas, com hash dos artefatos, e um contexto de até 1.500 tokens. A sessão nova lê só os dois; etapa feita não roda de novo; leva que caiu redispara só quem não entregou. No ensaio automático, a retomada de uma N2 caída no meio da leva do plano lê cerca de 700 tokens. A seção Estado do registro foi para o `progresso.md`, e a Retomada do registro virou uma linha por parada.
- **Revisores sem o arquivo inteiro** (`scripts/ficha-tecnica.sh`). Fichas por arquivo (importa, exporta, assinaturas, linhas-chave) e trechos de ±10 linhas em volta de cada citação do batedor, por expressão regular, sem modelo, com segredo mascarado. Medido em arquivos reais do Ciclo Arboris: um arquivo de rotas de 73 KB vira uma ficha de 6 KB, e um documento de 451 KB, uma de 2 KB. Só o implementador lê inteiros os arquivos que vai mudar.
- **Portões enxutos** (`scripts/julgar-pre.sh`). Achados numerados com ID estável na tarefa e agrupados por lugar antes do julgamento; na conversa fica uma linha por achado. Teto de 2 rodadas por portão em N2 e 3 em N3. Em N2, o portão do código é o adversário em uma rodada, com lente só para sinal novo no diff, achado do plano conferido pelo ID em uma linha e 2ª rodada só por CRÍTICO.
- **Triagem e modelos.** Dúvida entre dois níveis vira uma pergunta de sim ou não. Pedido de rigor sem superfície sensível vale N1 com dois revisores. Em N2, construtor e adversário vão para `padrao`.
- **Aprendizado.** O registro anota as correções do usuário (`C-n`), que viram proposta no fechamento. A linha de `aprendizado.md` compara o custo real com o orçado e soma a sessão do orquestrador aos subagentes.
- Casos novos: T8, T9, C11 a C13, M3, O9 a O11, R1 a R4, E2 e E3; O1 a O8 e C4 atualizados. Testes automáticos novos: `teste-orcamento-local.sh`, `teste-progresso.sh`, `teste-ficha-tecnica.sh` e `teste-julgar-pre.sh`.

Fora desta versão, de propósito:
- O `sqz` não substituiu o `enxugar.sh` (motivos em FONTES.md): ele devolve à conversa a saída inteira, só que encolhida, enquanto o enxugar guarda a saída e devolve até 51 linhas; a referência de 13 tokens aponta para conteúdo que o subagente de contexto limpo nunca viu; e ele não mascara segredo.
- O claude-recall não foi adotado: instala hook e injeta regra em toda sessão. A captura de correções ficou no registro da tarefa.
- Gateways e roteadores (OmniRoute, LiteLLM, RouteLLM e outros) e cache semântico ficaram para uma fase opcional de infraestrutura, não feita.

Custo: a cada leva, uma chamada do `orcamento-local.sh` (menos de 1 segundo, uma linha na conversa) e uma edição de 3 linhas no `contexto-tarefa.md`; por etapa, uma chamada do `progresso.sh`; por rodada, uma do `julgar-pre.sh`. Em N2, a troca de `forte` para `padrao` no construtor e no adversário reduz a independência do portão do plano para `mesmo-modelo-contexto-limpo`. A meta do plano, N2 com até 40% dos tokens de antes, ainda não foi medida: depende das tarefas reais anotadas com a 1.2.0.

Revisão: nenhuma revisão independente. A versão foi escrita e testada pelo orquestrador (Opus) sozinho, sem enxame e sem revisor de contexto limpo. Os scripts têm teste automático e o `orcamento-local.sh` rodou no app desktop; as regras de texto só têm os casos de `testes/casos.md`, que ainda não foram rodados numa sessão real.

## 1.1.1 (2026-10-01)

- O app desktop não chama a statusline, e isso agora está confirmado. Caso real: numa sessão nova do app, com a `statusLine` no `settings.json` e o script instalado funcionando quando rodado à mão, nenhum arquivo de orçamento foi gravado depois de várias mensagens. No app, o orçamento vivo fica desligado. A exceção é o dado que uma sessão do terminal gravou antes: ele vale como piso, mas não se atualiza.
- O `orcamento.sh` dá o motivo certo. Ele reconhece o app pela variável `CLAUDE_CODE_ENTRYPOINT=claude-desktop`, que não é documentada e foi medida nesta sessão. Sem arquivo, diz que o app não chama a statusline. Com um arquivo gravado antes pelo terminal, avisa que o dado não se atualiza no app. O estado e o código de saída não mudam. Fora do app, o motivo genérico também passa a citar o app.
- Sem dado confiável de orçamento (`desligado`, `sem-dado`, ou `ok` com o aviso do app), a seiva grava a Retomada antes de cada leva de N2 ou N3. `restrito` e `parar` com o aviso seguem o limiar, porque o percentual é piso. Na tarefa da 1.1.0 houve duas quedas por limite de uso no meio de uma leva, e foi a Retomada que salvou o trabalho nas duas. Custo: uma escrita curta no `registro.md` por leva, sem agente a mais. O molde do registro cita o gatilho novo.
- O caso O3 mudou, entrou o caso O8 e há 9 casos novos em `testes/scripts/teste-orcamento.sh`.

Adiado: com `--tarefa` no app, o leitor termina com "retomar não gravado: a pasta do orçamento não existe". Esse "retomar" é o arquivo da barra, mas pode ser lido como falha da Retomada do registro. Suspeita do revisor (confiança 6), não medida.

Revisão: tarefa N1, construída pelo orquestrador. O diff foi revisado por um agente sonnet de contexto limpo, com as lentes de contrato e operação. Ele rodou o leitor em 7 ambientes isolados e achou 1 MÉDIO e 2 BAIXO, todos corrigidos: a regra misturava o aviso do app com `restrito`; o texto público dizia "sempre desligado"; faltava o custo. Corrigida também uma suspeita: o texto não dizia que a cautela some se a variável do app mudar. Independência: outro modelo e contexto limpo em relação ao orquestrador. Os ajustes depois da revisão não passaram por nova rodada.

## 1.1.0 (2026-09-30)

- Orçamento vivo, só no Claude Code: a statusline (scripts/statusline-orcamento.sh, que o usuário instala por cópia) grava o uso das janelas de 5 horas e de 7 dias e o contexto da sessão, e scripts/orcamento.sh lê esse arquivo antes de cada leva de agentes. Com 70% da janela de 5 horas, só N0 e N1 seguem, com a Retomada gravada antes; com 85%, parada limpa e sessão nova. Caso real: ao retomar sessões gigantes com "Tentar novamente", o cache foi recriado em quebras de 800 a 940 mil tokens (session-report, 30 dias, uma máquina, medido em 2026-09-29). Sem a statusline, nada muda.
- scripts/enxugar.sh: a saída longa de um comando fica inteira em saidas/ da pasta da tarefa, com os segredos de padrão conhecido mascarados (chave privada, tokens com prefixo, atribuição a nome de segredo); na conversa voltam o resumo e o caminho. Segredo sem padrão conhecido, como um cabeçalho Authorization ou um cookie, passa: por isso o enxugar recusa pasta versionada e grava em modo 600.
- scripts/checar-skill.sh ignora a pasta de trabalho da seiva (.seiva/ e .claude/) e passa a conferir a sintaxe dos testes em testes/scripts/.
- Papel invasor: varredura de segurança do código com relatório de conserto, conferido por um revisor antes de virar conserto. Entrou no commit 1a762b2 sem subir a versão; fica registrado aqui.
- Dez casos de teste novos e testes automáticos dos scripts em testes/scripts/.

Adiado: o papel invasor ainda não tem caso de teste em testes/casos.md.

Revisão: tarefa N3. O plano foi atacado pelo adversário e pelas lentes de segurança, operação e contrato (opus, contexto limpo; o profundo não está disponível na conta). No código, um verificador opus (outro modelo que os implementadores sonnet) e três rodadas de ataque ao diff (adversário e lente de segurança, opus). Cada rodada achou um caminho para a chave privada escapar da máscara, e todos foram corrigidos com teste. Independência: outro modelo em relação aos implementadores; mesmo modelo, de contexto limpo, em relação aos consertos do orquestrador. Sem revisão por outro provedor (Gemini e Codex ausentes).

## 1.0.0 (2026-09-26)

Primeira versão.

- Doze leis, com o projeto em primeiro lugar: as regras do repositório valem mais que as da skill.
- Fluxo de dez etapas (terreno, triagem, reconhecer, propor, atacar o plano, decidir, construir, verificar, atacar o código, entregar e aprender), dimensionado em quatro níveis de risco, com critérios de N3 que se verificam.
- Perfil do projeto montado a partir das fontes de lei, com impressão digital por arquivo ou por seção para reler só o que mudou.
- Cinco categorias de modelo (`script`, `rapido`, `padrao`, `forte`, `profundo`), uma regra única de escalada, descida de categoria quando o modelo está indisponível e mapa por harness.
- Cinco papéis (batedor, construtor, adversário, implementador, verificador) e seis lentes (segurança, dados, design, desempenho, operação, contrato).
- Contratos de ida e volta, formato de achado com confiança mínima 7, suspeita grave medida antes de descartar, tabela de severidade e critério de parada em três rodadas.
- Suporte a Claude Code, Codex CLI, Gemini CLI, Cursor e OpenCode, com modo sequencial para harness sem subagentes e revisão por outro provedor.
- Evolução por escape, descoberto na triagem da tarefa seguinte, com aprovação de quem desenvolve.
- Quatro scripts: impressão das fontes, pasta da tarefa com foto inicial da árvore, diff da tarefa com arquivo novo e checagem da própria skill.
- Trinta casos de teste.

Antes de publicar, a versão passou pelo próprio processo: um adversário (Opus, contexto limpo) e um ensaio de mesa num bug real do Ciclo Arboris (Sonnet). Os dezoito achados confirmados foram corrigidos nesta versão. Entre eles: revisor sem saída quando o modelo mais caro está indisponível; diff que perdia arquivo novo e pegava mudança de outra sessão; perfil invalidado a cada commit; escape que nunca era detectado; e clone velho aceito por ser um repositório git válido.

## Propostas recusadas

Nenhuma ainda.
