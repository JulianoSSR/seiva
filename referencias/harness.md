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
