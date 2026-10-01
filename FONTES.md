# Fontes

Levantamento feito em 2026-09-26, só leitura: nada foi instalado nem executado a partir destes projetos. Nenhum trecho foi copiado; as ideias foram reescritas em português, no formato desta skill.

## Projetos de orquestração

| Projeto | Licença | Versão lida | O que inspirou |
|---|---|---|---|
| [affaan-m/ECC](https://github.com/affaan-m/ECC) | MIT | 2.2.2, commit `e482e57` (2026-09-24) | Tamanho da tarefa decide a cerimônia; portão de relatório que exige linha exata e cenário; conselho de vozes com contexto mínimo contra ancoragem; rótulo honesto de independência entre provedores; auditoria de orçamento de contexto |
| [obra/superpowers](https://github.com/obra/superpowers) | MIT | commit de 2026-09-25 | Registro de decisões com custo se errado; revisor novo a cada tarefa; "voltas custam mais que preço"; nenhuma alegação de pronto sem evidência nova |
| [github/spec-kit](https://github.com/github/spec-kit) | MIT | commit de 2026-09-25 | Constituição como política permanente; marcação explícita do que precisa de esclarecimento |
| [bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) | MIT | commit de 2026-09-25 | Lentes paralelas sem contexto e julgamento central; rotas intenção, plano, ajuste e adiar; seção de intenção congelada; matriz de casos; pergunta da lacuna de verificação |
| [open-gsd/gsd-core](https://github.com/open-gsd/gsd-core) (antes gsd-build/get-shit-done) | MIT | commit de 2026-09-27 | Revisor de plano antes da execução com teto de rodadas; ameaças plantadas no plano e auditadas no código; subagente com contexto novo |
| [humanlayer/humanlayer](https://github.com/humanlayer/humanlayer) | Apache 2.0 | commit de 2026-06-18 | Batedores que documentam sem criticar; revisão humana no plano, onde ela rende mais; verificação automática separada da manual |
| [wshobson/agents](https://github.com/wshobson/agents) | MIT | commit de 2026-09-26 | Distribuição de modelos por nível; um dono por arquivo; formato fixo de achado |
| [code-yeongyu/oh-my-opencode](https://github.com/code-yeongyu/oh-my-opencode) | mista (ver o LICENSE.md do projeto) | commit de 2026-09-27 | Roteamento por categoria de intenção, não por nome de modelo; prompt mais explícito para modelo pequeno; só o orquestrador escreve |
| [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) | MIT | commit de 2026-09-21 | Regras de honestidade: não inventar métrica nem supor canal de mensagem que não existe |
| [SuperClaude-Org/SuperClaude_Framework](https://github.com/SuperClaude-Org/SuperClaude_Framework) | MIT | commit de 2026-09-15 | Carregamento progressivo por complexidade |
| [ruvnet/claude-flow](https://github.com/ruvnet/claude-flow) | MIT | 3.45.0 | Roteamento pelo modelo mais barato que passa numa barra de qualidade (ideia; os números do projeto não foram verificados de forma independente) |
| [anthropics/claude-code-security-review](https://github.com/anthropics/claude-code-security-review) | ver o repositório | lido em 2026-09-26 | Confiança numérica com limiar; lista de exclusões contra falso positivo; achado com cenário de exploração |

## Levantamento de 2026-09-29 (versão 1.1)

| Projeto | Licença | Versão lida | O que inspirou |
|---|---|---|---|
| [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/session-report), plugin session-report | Apache 2.0 | sem versão no manifesto; marketplace lido em 2026-09-29 | As medições de uso que deram o caso real do orçamento vivo (quebras de cache ao retomar sessão gigante). A skill não depende dele e nada foi copiado |
| [headroomlabs-ai/headroom](https://github.com/headroomlabs-ai/headroom) | Apache-2.0 | README do `main` lido em 2026-09-29; release mais recente naquele dia: v0.39.1 (2026-09-26) | A compressão reversível: o original fica guardado na máquina e o que volta ao modelo é o resumo, com o caminho para buscar o resto. Nada foi copiado, e a seiva não depende dele (é proxy de rede em Python; o enxugar é um script local) |

O RTK e o Context Mode foram estudados no mesmo levantamento, mas não inspiraram a 1.1.0 e ficam de fora. As fontes do podador, do observador e da revisão externa entram com a entrega delas.

## Estudos e textos

- Anthropic, *How we built our multi-agent research system*, 2025-06-13: multiagente gasta cerca de 15 vezes os tokens de um chat; tarefas acopladas, como boa parte das de código, paralelizam mal.
- Zheng et al., *Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena*, NeurIPS 2023: vieses de posição, de verbosidade e de preferência pelo próprio estilo.
- Panickssery, Bowman e Feng, *LLM Evaluators Recognize and Favor Their Own Generations*, NeurIPS 2024: autopreferência.
- Sharma et al., *Towards Understanding Sycophancy in Language Models*, ICLR 2024: tendência a concordar.
- Verga et al., *Replacing Judges with Juries* (PoLL), 2024: painel de modelos diversos contra juiz único.
- *Multi-Agent Debate for LLM Judges with Adaptive Stability Detection*, arXiv 2510.12697: ganho de rodadas que cai depois da segunda ou terceira.
- Gary Klein, *Performing a Project Premortem*, Harvard Business Review, 2007-09.
- STRIDE (Microsoft), OWASP API Security Top 10 2023 e OWASP ASVS 5.0: usados só pelos títulos das categorias, como perguntas.
- Especificação Agent Skills (agentskills.io) e documentação oficial de subagentes do Claude Code, Codex CLI, Gemini CLI, Cursor e OpenCode, lidas em 2026-09.
- Documentação oficial da statusline do Claude Code (campos `rate_limits` e `context_window`, atualização com debounce), lida em 2026-09-29.

## O que ficou de fora, e por quê

- **Hooks sempre ativos e memória contínua injetada em toda sessão** (ECC, continuous-learning): custo fixo de contexto e código de terceiro rodando a cada ferramenta. A evolução aqui é por arquivo, lido só no fechamento da tarefa.
- **Catálogos com dezenas de agentes instalados:** cada descrição instalada ocupa contexto em toda sessão. Aqui os papéis são moldes lidos sob demanda.
- **Personas com nome e tom teatral:** não melhoram o resultado e gastam token.
- **Prosa em caixa-alta e ameaça ("VOCÊ DEVE")**: estrutura e critério fazem o trabalho que a pressão retórica não faz.
- **Números de custo e acerto divulgados pelos próprios projetos sem verificação independente.**
