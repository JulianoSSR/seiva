# Harness: como disparar subagentes em cada ferramenta

O núcleo da seiva não depende de harness. Este arquivo diz como cada ferramenta faz as três coisas de que ela precisa: disparar um subagente com modelo escolhido, rodar vários em paralelo e manter o revisor sem ferramenta de edição.

Regras para todos:

- **Só o orquestrador dispara subagentes.** Subagente não chama subagente. É assim que funciona em todos os harnesses (o Gemini CLI nem permite o contrário), e o custo fica previsível.
- **Nada é instalado no repositório do projeto.** Quando o harness exige arquivo de agente para escolher o modelo (Codex, Gemini, Cursor, OpenCode), a seiva cria quatro agentes genéricos, um por categoria, **no diretório do usuário**, e pergunta antes de criar. Eles não carregam regra nenhuma: o papel vai no pacote.

## Claude Code

- **Disparo:** ferramenta de subagente (`Agent`) com `model` = `haiku`, `sonnet`, `opus` ou `fable`. O parâmetro da chamada vale mais que o frontmatter do agente. Nenhum arquivo precisa ser criado.
- **Paralelo:** várias chamadas na mesma mensagem. Para não travar a conversa, use `run_in_background`; o resultado chega por notificação, então não fique consultando.
- **Sem ferramenta de edição:**
  - batedor: `subagent_type: "Explore"`;
  - adversário, lentes e verificador: `subagent_type: "Plan"`. Esse tipo não tem as ferramentas de edição, mas tem shell, que o verificador precisa para rodar comandos.
  - Se um desses tipos devolver fora do formato do contrato, use `general-purpose`, com a proibição no pacote, e anote no registro.
  - O tipo tira a ferramenta de edição, não o shell. O PROIBIDO do pacote continua valendo.
- **Agentes do projeto:** um agente em `.claude/agents/` que cubra uma superfície S do perfil é chamado pelo nome no `subagent_type`, com o pacote da seiva no prompt. Confira antes se o arquivo ainda existe: pasta ignorada pelo git não chega a um clone novo.
- **Worktree:** `isolation: "worktree"` cria a cópia a partir do repositório **em que a sessão abriu**. Se a sessão abriu num clone que não é o vivo, a cópia sai velha. Só use depois de confirmar o repositório na etapa 0. Com outra sessão editando o mesmo repositório em N2 ou N3, sugira a worktree ao usuário.
- **O que o subagente não tem:** a conversa, a memória da sessão, o `CLAUDE.md` de outro repositório. Tudo vai no pacote.
- **Tokens:** a notificação de fim de cada subagente traz os tokens usados. Anote no registro.

## Orçamento vivo (só no Claude Code)

No Claude Code, a statusline recebe a cada mensagem o uso das janelas de 5 horas e de 7 dias e o tamanho do contexto da sessão. O `scripts/statusline-orcamento.sh` guarda esses números, e o `scripts/orcamento.sh` os lê antes de cada leva de agentes. Sem a statusline nada disto existe, e a seiva trabalha como sempre.

- **O que é gravado, e onde:** em `${XDG_CACHE_HOME:-$HOME/.cache}/seiva/`, sempre em modo 600. O `orcamento.json` traz `versao`, `harness`, `script` (o caminho do script que gravou), `gravado_em`, `sessao`, `cinco_horas` e `sete_dias` (`usado`, `reinicia` e `visto_em`) e `contexto` (`usado` e `sessao`). O `retomar` guarda o caminho do `registro.md` da tarefa em curso: o `orcamento.sh --tarefa <pasta>` o grava, e a barra o usa para dizer qual tarefa retomar. A statusline é do usuário. A seiva fornece o script, e nenhum script dela escreve no `settings.json`.
- **Instalação:** só com o usuário. O orquestrador pergunta antes, preenche `SKILL` com o caminho absoluto da skill que está carregada (o harness mostra a pasta base dela; nunca suponha `~/.claude/skills/seiva`, porque a skill pode vir de um clone ou de um plugin) e entrega o bloco abaixo. A instalação é por cópia: atualizar a skill não muda o script que roda a cada mensagem. O bloco para sem mudar nada se o `settings.json` já tem uma `statusLine`. Depois de rodar, o usuário abre uma sessão nova e manda uma mensagem.

```bash
(
  umask 077 &&
  SKILL='<caminho absoluto da skill carregada, preenchido pelo orquestrador>' &&
  CFG="$HOME/.claude/settings.json" &&
  test -f "$SKILL/scripts/statusline-orcamento.sh" &&
  { test -f "$CFG" || printf '{}\n' > "$CFG"; } &&
  jq -e 'type == "object" and (has("statusLine") | not)' "$CFG" >/dev/null &&
  cp -p "$CFG" "$CFG.bak-$(date +%Y%m%d-%H%M%S)" &&
  install -m 0755 "$SKILL/scripts/statusline-orcamento.sh" "$HOME/.claude/statusline-seiva.sh" &&
  jq '.statusLine = {"type": "command", "command": "bash ~/.claude/statusline-seiva.sh", "padding": 0}' "$CFG" > "$CFG.novo" &&
  jq -e '.statusLine.command == "bash ~/.claude/statusline-seiva.sh"' "$CFG.novo" >/dev/null &&
  mv "$CFG.novo" "$CFG" &&
  echo "OK às $(date +%s): abra uma sessão nova, mande uma mensagem e rode: bash $SKILL/scripts/orcamento.sh"
) || echo "PAROU AQUI: o settings.json só muda na linha do mv. Se já existe statusLine, o bloco para de propósito."
```

- **Atualização:** depois de atualizar a skill, ou quando o `orcamento.sh` avisar `statusline desatualizada`, o usuário copia o script de novo:

```bash
install -m 0755 '<caminho absoluto da skill carregada>/scripts/statusline-orcamento.sh' ~/.claude/statusline-seiva.sh
```

- **Volta:** o bloco abaixo tira a `statusLine` do `settings.json`, e só depois apaga a cópia e os arquivos do cache. Se a `statusLine` não for a da seiva, ele para. O `.bak-<data>` que a instalação deixou é o último recurso: desfaz também o que mudou no `settings.json` depois dele.

```bash
(
  umask 077 &&
  CFG="$HOME/.claude/settings.json" &&
  C="${XDG_CACHE_HOME:-$HOME/.cache}/seiva" &&
  jq -e '.statusLine.command == "bash ~/.claude/statusline-seiva.sh"' "$CFG" >/dev/null &&
  jq 'del(.statusLine)' "$CFG" > "$CFG.novo" &&
  jq -e 'has("statusLine") | not' "$CFG.novo" >/dev/null &&
  mv "$CFG.novo" "$CFG" &&
  rm -f "$HOME/.claude/statusline-seiva.sh" "$C/orcamento.json" "$C/retomar" &&
  { rmdir "$C" 2>/dev/null || true; } &&
  echo "OK: statusline removida do settings e depois do disco; vale na próxima sessão"
) || echo "PAROU AQUI: se a statusLine não é a da seiva, o bloco para de propósito. O .bak-<data> é o último recurso: ele desfaz também o que mudou no settings depois dele."
```

- **Limiares (janela de 5 horas):** antes de cada leva, o orquestrador roda `bash <skill>/scripts/orcamento.sh --tarefa <pasta-da-tarefa>` e lê a palavra depois de `ORCAMENTO`.
  - `ok`: segue.
  - `restrito` (70% ou mais, código 10): N2 e N3 não começam nem abrem leva nova. O usuário pode mandar seguir, e isso vira `D-n` no registro, com o custo se errado. N0 e N1 seguem, com a Retomada gravada antes de cada leva. O nível não desce por causa do orçamento: uma tarefa N3 continua N3 e espera o reinício ou a decisão do usuário.
  - `parar` (85% ou mais, código 20): parada limpa em qualquer nível, só na fronteira entre levas. O agente em curso termina.
  - `sem-dado`: a janela reiniciou depois da última gravação, e o percentual gravado é da janela anterior. Trate como `desligado` até a statusline gravar de novo.
  - `desligado`: sem statusline, sem `jq` ou sem arquivo legível. Diga uma vez por tarefa que o orçamento vivo está desligado e siga como sempre.
- **Parada limpa:** grave a Retomada no `registro.md` (o que rodava, o próximo passo e "retomar em sessão nova") e diga ao usuário a hora do reinício, que a linha do `orcamento.sh` traz, e o caminho absoluto do `registro.md`: `abra uma sessão nova depois das HH:MM e diga: retome <caminho>`. Nunca sugira "Tentar novamente" na sessão gigante: retomar sessão grande recria o cache inteiro, e as maiores quebras medidas foram de 800 a 940 mil tokens (session-report, 30 dias, uma máquina, em 2026-09-29). Na sessão nova, o orquestrador lê a Retomada do registro e segue do passo gravado.
- **Estouro no meio da leva:** a janela pode acabar com um agente rodando. O que salva o trabalho é a Retomada gravada antes da leva. A barra ajuda: a partir de 70% ela termina com `estourou? sessão nova + retome <tarefa>`, com o nome da pasta que o `--tarefa` gravou.
- **Como ler o dado:** o percentual gravado vale como piso até a janela reiniciar, porque o uso só cresce dentro dela. Depois da hora do reinício, o estado é `sem-dado`. A idade aparece na linha (`dado de <n> min`) e conta desde a última vez que a barra recebeu dado da janela. O leitor avisa `statusline desatualizada` quando a cópia instalada difere da do repositório, e `versão da statusline não conferida` quando não consegue comparar.
- **Limites:**
  - só chega `rate_limits` para assinante Pro ou Max, e só depois da 1ª resposta da sessão (documentação oficial da statusline do Claude Code, lida em 2026-09-29);
  - o contexto é o da última sessão que gravou, não o de todas;
  - na aba Code do app desktop não foi confirmado que a statusline rode; sem o arquivo, o leitor diz `desligado`, e com um arquivo gravado antes por uma sessão do terminal ele usa esse dado como piso, com a idade na linha;
  - a decisão olha só a janela de 5 horas: a de 7 dias aparece na linha, mas não trava nada, e perto do teto semanal quem decide é o usuário (`/usage`);
  - o `retomar` vale por 6 horas depois da última leva; mais velho, a barra volta ao texto genérico;
  - em outro harness o leitor diz `desligado`: a statusline é do Claude Code;
  - duas sessões gravando ao mesmo tempo podem perder uma atualização, que a mensagem seguinte corrige;
  - a barra pode estar uma mensagem atrás (a atualização espera 300 ms e é cancelada se outra chega), então a idade do dado fica visível.

## Codex CLI

Confira na documentação do Codex antes do primeiro uso, porque os detalhes mudam rápido.

- **Agentes:** arquivos TOML em `~/.codex/agents/`, com `name`, `description` e `developer_instructions`. O modelo definido no arquivo do agente tem precedência sobre o padrão. Crie `seiva-rapido`, `seiva-padrao`, `seiva-forte` e `seiva-profundo`, com instruções mínimas. Use a pasta do usuário, nunca a `.codex/agents/` do projeto.
- **Paralelo:** o Codex roda agentes em paralelo e junta os resultados. O limite fica em `[agents]` do `config.toml`.
- **Skill:** a pasta `seiva/` vai para o diretório de skills do Codex. As regras do projeto estão no `AGENTS.md`, que o Terreno lê.

Esboço de agente (conferir os nomes de campo e de modelo):

```toml
name = "seiva-forte"
description = "Executa um pacote da seiva na categoria forte."
model = "gpt-6-astra"
model_reasoning_effort = "medium"
developer_instructions = "Siga o PAPEL e o pacote recebidos. Não edite fora do ESCOPO. Responda no formato de SAÍDA."
```

## Gemini CLI

- **Agentes:** `~/.gemini/agents/*.md`, um por categoria, com `model` explícito. O `/model` da sessão não muda o modelo dos subagentes.
- **Subagente não chama subagente** (proibido pela ferramenta).
- **Paralelo:** não confirmado na documentação. Rode em sequência.

## Cursor

- **Agentes:** `~/.cursor/agents/`, um por categoria. O Cursor também lê `.claude/agents/` e `.codex/agents/`.
- **Modelo:** campo `model`, com esforço entre colchetes (`modelo[effort=high]`). Use `readonly` nos revisores.
- **Skills:** lê `SKILL.md` desde a versão 2.4.

## OpenCode

- **Agentes:** `~/.config/opencode/agents/*.md`, com `mode: subagent` e `model: provedor/modelo` sempre explícito. Sem `model`, o subagente herda o modelo de quem o chamou e a categoria se perde.

## GitHub Copilot, Windsurf e harness sem subagente com modelo próprio

Use o **modo sequencial**:

1. Cada papel roda em sequência, no mesmo contexto.
2. Antes de trocar de papel, grave o artefato da etapa em arquivo.
3. Declare a troca ("agora como adversário") e trabalhe só com o papel e o artefato, sem voltar ao raciocínio anterior.
4. A independência dessas revisões é `mesmo-contexto`. Diga isso na entrega.
5. Em N3, recomende uma revisão de fora, como na seção seguinte.

## Revisão por outro provedor

É a independência mais forte que existe e funciona em qualquer harness. Em N3, se o usuário tiver uma segunda ferramenta (Codex, Gemini), o orquestrador prepara `revisao-externa.md` com o plano ou o diff, o papel do adversário e o formato de achado.

Antes de gravar o arquivo:

- tire valor de segredo, dado pessoal e dado de cliente. Plano e diff não devem ter nenhum deles; se tiverem, isso já é um achado;
- diga ao usuário que o conteúdo vai para outro provedor. Quem manda é ele.

O usuário abre a outra ferramenta, cola o arquivo e traz a resposta. O achado que volta é julgado como qualquer outro, com independência `outro-provedor`.
