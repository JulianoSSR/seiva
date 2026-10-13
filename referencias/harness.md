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
- **Tokens:** a notificação de fim de cada subagente traz os tokens usados. Anote no registro, na tabela de agentes; a soma vai para o total da tarefa, junto com o gasto da sessão do orquestrador que o `orcamento-local.sh` mostra (`sessão ≈`).

## Orçamento vivo

O `scripts/orcamento-local.sh` lê os transcripts que o Claude Code grava em `~/.claude/projects/`, e o terminal e o app desktop gravam do mesmo jeito. Antes de cada leva ele diz se a seiva pode abrir outra. Não precisa de statusline, de hook nem de terminal, e nada é instalado. A decisão continua com o `scripts/orcamento.sh`, que o próprio `orcamento-local.sh` chama: os limiares são os mesmos de antes.

- **Como se usa:** antes de cada leva, `bash <skill>/scripts/orcamento-local.sh --tarefa <pasta-da-tarefa>`, e leia a palavra depois de `ORCAMENTO`. A linha termina com a fonte (`estimado pelos transcripts`, ou `fonte statusline`), o contexto da sessão contra a janela do modelo e o gasto da sessão com subagentes (`sessão ≈`), que vai para o registro no fechamento. A 1ª vez varre os transcripts dos últimos 30 dias (cerca de 5 segundos em 620 transcripts); depois, só o que mudou.
- **O que mede:**
  - cada resposta pesa entrada + saída + escrita de cache + `PESO_CACHE_LEITURA` × leitura de cache, contada uma vez: o transcript repete a mesma resposta numa linha por bloco de conteúdo. O peso padrão é 0,01. Em 53 vezes que a conta do autor bateu no limite, ele deixou o total de cada janela com dispersão de 28%; com 0,1 a dispersão foi de 42%, e sem leitura nenhuma, de 31% (medido em 2026-10-13, uma conta, quase toda em Opus);
  - a janela de 5 horas começa na 1ª resposta depois do fim da anterior, arredondada para baixo em 10 minutos. Assim bateram 53 das 56 janelas com aviso de limite nos transcripts do autor; as outras 3 foram abertas por uso que não aparece neles. Quando a conta bate no limite, o transcript guarda "You've hit your session limit · resets <hora> (<fuso>)", e essa janela passa a ser a exata;
  - o percentual é o total da janela dividido pelo limite calibrado. O aviso de limite com hora de reinício no futuro vale 100% e `parar`;
  - o contexto é o tamanho da última resposta da sessão (entrada + leitura e escrita de cache) sobre a janela do modelo: 1 milhão para o modelo que já passou de 200 mil em algum transcript, 200 mil para os outros, ou o valor de `SEIVA_JANELA_CONTEXTO`. A sessão é a de `CLAUDE_CODE_SESSION_ID`; sem ela, o transcript mais recente da pasta do projeto, com o aviso `sessão deduzida`.
- **Calibração:** por pontos. Cada vez que a conta bateu no limite, o total daquela janela até o aviso vale 100% (só entra a janela que os transcripts viram abrir: a aberta pelo claude.ai ou por outra máquina sairia baixa demais). Cada leitura do `/usage` vale o percentual lido: quando o usuário colar o relatório, o orquestrador roda `orcamento-local.sh --calibrar <percentual> --em <hora do relatório>`, e só conta o que a janela tinha gastado até aquela hora. O limite é o **menor** dos 5 pontos mais recentes, e a linha diz quantos pontos de cada tipo entraram e a dispersão deles. Leitura feita dentro da janela aberta é **âncora**: o percentual parte do valor lido, e só o gasto depois dela é estimado, sobre esse limite. Sem ponto nenhum, o estado é `desligado`, com o motivo e o comando na linha.
- **A única conferência com o número oficial** (2026-10-13, uma conta) mostrou o tamanho do erro. A hora do reinício bateu (14:19:59 no `/usage`, 14:20 na estimativa). O percentual não: a mediana dos 20 limites anteriores dava cerca de 40% quando o `/usage` marcava 73%. Nenhum peso testado (leitura de cache a 0,01 ou 0,1, prêmio acima de 200 mil de contexto) explicou a diferença, e por isso a regra passou da mediana para o menor dos pontos recentes. Na mesma sessão, com essa leitura como base, uma única resposta que reescreveu 373 mil tokens de cache levou a estimativa de 73% para mais de 100% sem a conta bater no limite: a escrita de cache pesa menos na conta oficial do que o peso 1 do script. A 2ª leitura, 17 minutos depois (90%), não fechou com a 1ª em peso nenhum: a janela tinha gasto que os transcripts não veem. Daí a âncora, que deixa a estimativa só para o gasto depois da última leitura.
- **Estados:**
  - `ok`: segue.
  - `restrito` (70% ou mais, código 10): N2 e N3 não começam nem abrem leva nova. O usuário pode mandar seguir, e isso vira `D-n` no registro, com o custo se errado. N0 e N1 seguem, com a Próxima ação gravada antes de cada leva. O nível não desce por causa do orçamento: uma tarefa N3 continua N3 e espera o reinício ou a decisão do usuário.
  - `parar` (código 20): 85% ou mais, limite batido, ou contexto desta sessão em 70% ou mais. Parada limpa em qualquer nível, só na fronteira entre levas ([retomada](retomada.md)). A linha diz se o motivo é o contexto (a sessão nova pode começar já) ou a janela (a sessão nova espera a hora do reinício).
  - `sem-dado`: a janela reiniciou depois da última gravação; só acontece com o arquivo da statusline. Trate como `desligado`.
  - `desligado`: sem `jq`, sem transcripts ou sem calibração. Diga uma vez por tarefa o motivo que a linha traz e siga. Em N2 e N3, grave a Próxima ação antes de cada leva: sem o dado, nada avisa que a janela está acabando.
- **Estouro no meio da leva:** a janela pode acabar com um agente rodando. O que salva o trabalho é a Próxima ação gravada antes da leva, com os relatórios esperados, e o pacote de cada agente em arquivo ([retomada](retomada.md)).
- **Limites:**
  - o percentual é estimado. A contabilidade da assinatura não é pública, e o número é freio, não medidor oficial. Os pontos de uma mesma conta variam de 25 a 33% entre si, e a conferência acima errou para os dois lados conforme o tipo de gasto: leia o número como faixa, e cole o `/usage` quando ele importar;
  - uso fora do Claude Code desta máquina (o chat do claude.ai, outra máquina) não aparece nos transcripts, mas gasta a mesma janela. A calibração automática absorve parte disso; o resto é erro para baixo;
  - a mistura de modelos não tem peso: uma janela gasta em Haiku pesa como se fosse em Opus. A calibração foi medida numa conta quase só de Opus;
  - a calibração automática depende do texto em inglês do aviso de limite ("You've hit your session limit · resets ..."). Se o Claude Code mudar esse texto, ela deixa de achar pontos novos e segue com os que já guardou;
  - `CLAUDE_CODE_SESSION_ID` não é documentada (medida no app desktop em 2026-10-13). Sem ela, a sessão é deduzida, e com duas sessões abertas no mesmo projeto o contexto medido pode ser o da outra;
  - a janela de contexto vem do histórico do modelo; modelo novo começa em 200 mil até aparecer acima disso, o que só adianta a parada;
  - o Claude Code apaga transcripts com mais de 30 dias (padrão do `cleanupPeriodDays`). Os pontos de calibração já guardados ficam em `calibracao.json`;
  - a janela de 7 dias não é estimada, e perto do teto semanal quem decide é o usuário (`/usage`);
  - em outro harness não há esses transcripts: o estado é `desligado`.
- **O que é gravado, e onde:** em `${XDG_CACHE_HOME:-$HOME/.cache}/seiva/`, sempre em modo 600: `orcamento-local.json` (o estado, no formato do `orcamento.json` com `fonte`, `cinco_horas.motivo`, `contexto.desta_sessao` e `estimativa`) e `calibracao.json` (os pontos, a calibração manual e o maior contexto visto por modelo). Do transcript só saem números, horários, nomes de modelo e o texto do aviso de limite: nenhum texto de conversa.

### Statusline (opcional, só no terminal)

No `claude` de terminal, a statusline recebe a cada mensagem o percentual oficial das janelas de 5 horas e de 7 dias. Com ela instalada e gravando há menos de 10 minutos, o `orcamento-local.sh` usa o número oficial no lugar da estimativa (`fonte statusline`); o contexto continua vindo do transcript da sessão. No app desktop ela não roda: a aba Code não chama a statusline (confirmado em 2026-10-01), e o `orcamento-local.sh` a ignora quando `CLAUDE_CODE_ENTRYPOINT=claude-desktop`. Sem ela, nada muda nos freios.

- **O que é gravado:** `orcamento.json` (`versao`, `harness`, `script`, `gravado_em`, `sessao`, `cinco_horas` e `sete_dias` com `usado`, `reinicia` e `visto_em`, e `contexto`) e `retomar`, o caminho do `registro.md` da tarefa em curso, que o `--tarefa` grava e a barra usa para dizer qual tarefa retomar. A partir de 70%, a barra termina com `estourou? sessão nova + retome <tarefa>`.
- **Instalação:** só com o usuário. O orquestrador pergunta antes, preenche `SKILL` com o caminho absoluto da skill que está carregada (o harness mostra a pasta base dela; nunca suponha `~/.claude/skills/seiva`, porque a skill pode vir de um clone ou de um plugin) e entrega o bloco abaixo. A instalação é por cópia: atualizar a skill não muda o script que roda a cada mensagem. O bloco para sem mudar nada se o `settings.json` já tem uma `statusLine`. Depois de rodar, o usuário abre uma sessão nova do `claude` no terminal e manda uma mensagem.

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

- **Atualização:** depois de atualizar a skill, ou quando a linha avisar `statusline desatualizada`, o usuário copia o script de novo:

```bash
install -m 0755 '<caminho absoluto da skill carregada>/scripts/statusline-orcamento.sh' ~/.claude/statusline-seiva.sh
```

- **Volta:** o bloco abaixo tira a `statusLine` do `settings.json`, e só depois apaga a cópia e os arquivos dela no cache (o `orcamento-local.json` e a `calibracao.json` ficam). Se a `statusLine` não for a da seiva, ele para. O `.bak-<data>` que a instalação deixou é o último recurso: desfaz também o que mudou no `settings.json` depois dele.

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

- **Limites da statusline:** só chega `rate_limits` para assinante Pro ou Max, e só depois da 1ª resposta da sessão (documentação oficial, lida em 2026-09-29); duas sessões gravando ao mesmo tempo podem perder uma atualização; a barra pode estar uma mensagem atrás, então a idade do dado aparece na linha (`dado de <n> min`); rodado à mão, o `orcamento.sh` sobre o arquivo da statusline mantém os avisos de antes (`statusline desatualizada`, `app desktop`).

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
