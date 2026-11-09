# Integrações sob demanda

O núcleo é o protocolo: ler regras, classificar risco, dividir arquivos, revisar e verificar. Ele não depende de Claude Code, Codex, Gemini CLI, Cursor ou OpenCode.

Cada integração informa **o que foi detectado**, fonte, data e limitações. Ter um aplicativo instalado não prova que a sessão permite escolher modelo, abrir agente, usar contexto limpo, executar comandos ou medir custo.

## Antes de usar uma integração

Confirme no ambiente atual:

| Capacidade | Evidência necessária |
|---|---|
| Subagentes | ferramenta ou comando realmente disponível e autorizado |
| Modelo por agente | parâmetro suportado e modelos acessíveis nesta conta |
| Contexto limpo | sem herdar conversa; instruções fixas ainda são declaradas |
| Paralelismo | limite de agentes e exclusividade dos arquivos |
| Somente leitura | restrição técnica real; se for só instrução, diga isso |
| Isolamento | diretório, credenciais, rede e efeitos que estão isolados |
| Contabilidade | fonte, campos, atribuição, intervalo e cobertura |
| Limite de uso | dado oficial ou estimativa rotulada, com validade |

Documentação oficial orienta a integração; a evidência local confirma se ela pode operar nesta sessão. Sem detecção, o estado é `desconhecido` ou `indisponivel`, nunca “suportado” por suposição.

## Configuração e modo sequencial

Adaptador carrega só quando a tarefa precisa. Não criar agentes no diretório global do usuário, não alterar configurações persistentes e não instalar hooks ou regras para toda sessão. Use ferramentas já disponíveis ou configuração temporária limitada à tarefa, quando autorizada. Referências e exemplos de adaptadores não são executados pelo simples carregamento da skill.

Sem subagentes, o orquestrador pode executar a parte mecânica e preparar um pacote para outra sessão ou revisor. Uma releitura no mesmo contexto é autoconferência. Se a tarefa exige revisão independente e ela não existe, o portão fica pendente até receber essa revisão; o modo sequencial não dispensa qualidade nem rebaixa N3.

## Uso por ferramenta

- **Claude Code:** conferir a ferramenta de agentes e seus parâmetros atuais. Não presumir aliases de modelo, tipos Explore/Plan ou isolamento. Os scripts `orcamento-local.sh` e `medir.sh` são específicos de transcripts compatíveis do Claude Code; não medem Codex, Gemini, Cursor ou OpenCode.
- **Codex:** conferir ferramentas de colaboração, herança de contexto, modelos e restrições expostas na sessão. Um ambiente com perfis predefinidos pode não permitir modelo arbitrário por agente.
- **Gemini CLI, Cursor e OpenCode:** conferir comandos e formato de agentes na documentação oficial atual e no ambiente. Sem suporte temporário já disponível, usar o modo sequencial; não instalar agentes globais para contornar a falta.
- **Outros:** aplicar o mesmo contrato de capacidades e declarar os campos sem fonte. Não copiar o formato de transcript de uma ferramenta para outra.

## Tokens, custo e intervalo

Uma medição registra origem, instante, identificadores pseudônimos de tarefa e tentativa, intervalo e unidade. Entrada, saída, leitura e escrita de cache permanecem separadas. Valor bruto, ponderação local e dinheiro não são somados como se fossem a mesma unidade.

Notificação de fim serve para acompanhamento; não é a fonte canônica do custo total. Relatórios de uso podem omitir cache, corridas interrompidas ou partes do orquestrador.

O intervalo da tarefa não é a sessão inteira: uma tarefa atravessa sessões; uma sessão alterna tarefas. Só atribua consumo por identificação ou intervalo demonstrável. Com uma marca só, sobreposição ou fonte incompleta, marque atribuição parcial/estimada. Medir a sessão inteira exige confirmar que ela foi exclusiva da tarefa. Não apresente dado ausente como zero.

## Integração legada de orçamento do Claude Code

```bash
bash <skill>/scripts/orcamento-local.sh --tarefa <pasta> --leva "<papel>:<modelo> ..."
bash <skill>/scripts/medir.sh --tarefa <pasta> --fechar
```

Os comandos só valem após confirmar dependências e formato suportado. A leitura de transcripts é local, sem publicar prompts ou conversas. Sem fonte reconhecida, informe a lacuna uma vez e mantenha checkpoint antes da leva.

`restrito` e `NÃO CABE` interrompem a abertura de trabalho que não cabe. `parar` pede parada limpa na fronteira da leva. Limite de custo não aprova achado, não reduz nível nem dispensa revisão. A retomada segue [retomada](retomada.md).

A estimativa por transcripts e a janela de uso são heurísticas da integração, não tokens oficiais nem saldo financeiro. Statusline e comandos de uso são opcionais; não instalar configuração global como parte desta skill.

## Monitor local e seleção de levas

O monitor é acionado só para a tarefa. Não roda como daemon, não instala hook e não altera configuração global. Confira as opções disponíveis com `--help`.

```bash
python3 scripts/monitor.py capacidades --app codex --saida <capacidades.json>
python3 scripts/monitor.py coletar --app codex --tarefa <tarefa> --fonte <uso.jsonl> --inicio <ISO-com-fuso> --fim <ISO-com-fuso>
python3 scripts/monitor.py vigiar --app codex --tarefa <tarefa> --fonte <uso.jsonl> --intervalo 15 --duracao 300
python3 scripts/monitor.py selecionar --tarefa <tarefa> --capacidades <capacidades.json> --tarefas <tarefas.json> --reserva <id>
python3 scripts/monitor.py liberar --tarefa <tarefa> --reserva <id>
```

`--app` aceita `codex`, `claude`, `gemini`, `opencode`, `cursor` e `generic`. Identificar o app não comprova uma capacidade. A detecção consulta o que estiver implementado e acessível; catálogo vivo de modelos do Codex exige seu serviço disponível. `--rpc-bin` permite indicar o executável para essa consulta. Ausência, formato desconhecido ou falha ficam explícitos.

`coletar` aceita várias `--fonte`; `--inicio` e `--fim` delimitam o intervalo da tarefa. `vigiar` repete coleta por duração limitada e precisa ser iniciado: coleta pontual não é acompanhamento ativo. O monitor usa metadados de uso, sem publicar texto de conversa. Dado oficial e dado estimado mantêm origem, instante e unidade distintos.

A entrada de seleção descreve cada tarefa: `id`, `kind`, `risk` (0–3), `complexity`, `context_tokens`, `required_tools`, `depends_on`, `priority`, `authorized` e candidatos. Cada candidato informa modelo, qualidade avaliada para aquele trabalho, ferramentas, limite de contexto, tokens previstos, custo previsto, tokens de revisão, retrabalho e fechamento (closing_tokens), e esforço. A tarefa independent exige capacidade de contexto limpo; completed libera dependências. Capacidade expirada exige nova detecção. Qualidade é julgamento explícito com evidência; um catálogo de modelos não a prova.

A seleção verifica o maior risco requerido, dependências, autorização, contexto, ferramentas, qualidade e saldo antes do preço. Soma consumo previsto com revisão e retrabalho. Histórico pode entrar por --historico <json>: cada amostra informa modelo, kind, risk, total_tokens e accepted. A previsão divide tokens totais, inclusive falhas, pelo número de sucessos comparáveis. Sem amostra suficiente usa previsão conservadora com margem; não chama essa hipótese de medida.

A entrada contém tasks (lista), completed (IDs concluídos) e budget. Saldo exige budget {tokens, unit: "tokens", observed_at, source}, com fonte e instante de até 300 segundos. --saldo-tokens substitui somente o valor: não dispensa unidade, fonte e horário válidos. Não converter percentual de janela em tokens nem deduzir saldo de preço. Sem saldo confiável, a seleção declara orçamento desconhecido e não abre a leva.

A reserva usa arquivo privado compartilhado pelo repositório git comum, com trava atômica e prazo de validade: evita que duas sessões prometam o mesmo saldo. Ela não é configuração global nem agente persistente. Libere a reserva ao terminar ou abortar; reserva expirada não é prova de execução concluída.

## Cobertura conferida em 2026-11-08

| Integração | Evidência disponível | Limite |
|---|---|---|
| Codex | executável local, consulta real de catálogo e quota, parser com registro local | não é comparação de tarefa completa; registro recente não atribui sessão inteira |
| Claude Code | scripts legados preservados; parser novo com fixtures | parser novo não validado em tarefa real completa |
| Gemini CLI | fixtures do formato documentado | simulado, sem execução real da integração |
| OpenCode | fixtures do formato documentado | simulado, sem execução real da integração |
| Cursor | formato de saída consultado | tokens indisponíveis no formato público suportado; não inferir zero |
| Generic | contrato explícito de uso em fixture | fonte precisa trazer campos e semântica reconhecidos |

As fontes de formato são [Codex App Server](https://learn.chatgpt.com/docs/app-server), [Gemini CLI headless](https://geminicli.com/docs/cli/headless/), [Cursor CLI output format](https://cursor.com/docs/cli/reference/output-format), [mensagens de sessão do OpenCode](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/session/message.ts) e [streaming da Claude API](https://platform.claude.com/docs/en/build-with-claude/streaming). A API de streaming não documenta por si só todo transcript local do Claude Code: a integração declara o que consegue reconhecer.

Quota, créditos e tokens são campos separados. Cota com horário antigo mantém a marca de validade; saldo financeiro não vira tokens por regra implícita. Pesos e heurísticas do orçamento legado do Claude não são aplicados a outros aplicativos. Evidências pessoais de consulta ficam na execução privada, sem publicar quotas.

O monitor Python exige pasta da tarefa ignorada dentro do repositório. O armazenamento externo descrito no núcleo não é aceito por esse monitor nesta versão. Os scripts de estado e monitor usam `fcntl` e exigem Linux/macOS; no Windows, execute pelo WSL. O executável Windows do Codex pode ser consultado por caminho explícito a partir do WSL.
