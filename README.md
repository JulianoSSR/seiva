# Seiva

Skill para agentes de programação que organiza o trabalho complexo num enxame de subagentes, cada um com o modelo mais barato que dá conta da sua parte. Um agente propõe o plano, outros o atacam antes da primeira linha de código, e a entrega só sai com prova.

O nome vem da analogia: a seiva sobe pela árvore e toma a forma dela. A skill não traz regra de domínio nem estrutura pronta. Ela lê as regras do projeto em que está (`CLAUDE.md`, `AGENTS.md`, constituição, `CONTRIBUTING`) e se molda a elas.

## O que ela faz

- **Mede o risco antes de gastar.** Classifica a tarefa em quatro níveis. Correção trivial ela manda fazer direto. Permissão, dinheiro, migração, isolamento entre clientes e produção recebem o processo completo.
- **Escolhe o modelo por tarefa.** Busca e leitura vão para o modelo rápido; implementação bem descrita, para o médio; plano e revisão de alto risco, para o mais forte. O que é mecânico vira comando, sem modelo.
- **Ataca o plano antes do código.** Um adversário faz o pre-mortem ("isto já quebrou; por quê?"), e as lentes (segurança, dados, design, desempenho, operação, contrato) respondem às perguntas da área delas. Achado só conta com prova.
- **Julga os achados e para na hora certa.** O orquestrador confere cada achado, agrupa por causa e decide a rota: pergunta ao usuário, revisão do plano, ajuste ou registro. No máximo três rodadas por portão.
- **Verifica com outro agente.** Quem implementa não é quem prova. O verificador roda os comandos do projeto e confere cada critério de aceite e cada risco do plano.
- **Aprende com o que escapa.** Defeito encontrado depois da entrega vira proposta de pergunta nova numa lente. Nada muda sem aprovação.
- **Vigia a janela de uso (Claude Code).** Com a statusline opcional, confere o uso da janela de 5 horas antes de cada leva de agentes: perto do limite, segura as tarefas grandes e para limpo, com o ponto de retomada gravado, em vez de estourar no meio.

## O que ela não faz

- Não instala hook, agente nem regra carregada em toda sessão, e nada no repositório do projeto. O custo fixo é só a descrição da skill. A exceção é fora do Claude Code: Codex, Gemini, Cursor e OpenCode só escolhem modelo por subagente através de arquivo de agente, então a seiva cria quatro agentes genéricos (um por categoria) no diretório do usuário, depois de perguntar.
- Não substitui as regras do projeto. Quando as duas divergem, vale a do projeto.
- Não commita nem sobe nada se o projeto não permitir.
- Não diz que a revisão foi independente quando não foi.
- A statusline do orçamento vivo é opcional, e quem instala é você. A seiva só fornece o script e o bloco de instalação.

## Instalação

**Claude Code, como skill pessoal:**

```bash
git clone https://github.com/JulianoSSR/seiva.git ~/.claude/skills/seiva
```

Para atualizar, rode `git pull` dentro da pasta. A skill aparece na sessão seguinte.

**Claude Code, como plugin:**

```text
/plugin marketplace add JulianoSSR/seiva
/plugin install seiva@seiva
```

**Codex CLI, Cursor e outros:** copie a pasta `seiva/` para o diretório de skills da ferramenta. Para ter um modelo por categoria no Codex, veja [referencias/harness.md](referencias/harness.md).

## Como usar

Peça em linguagem comum ("usa a seiva para corrigir o BUG-088", "planeja e revisa esta migração") ou chame pelo nome:

```text
/seiva <o que precisa ser feito>
```

Na primeira vez num projeto, a seiva monta um perfil com as regras que encontrou e pede a sua confirmação. Depois ela só relê o que mudou.

## Custo

Um enxame gasta muito mais tokens que uma conversa: a Anthropic mediu cerca de 15 vezes. Por isso a seiva começa pela triagem. Tarefa trivial não dispara agente; tarefa leve usa de 1 a 3; só as de risco alto recebem o processo inteiro. O orçamento de agentes de cada tarefa aparece antes de começar, e os tokens gastos ficam anotados quando o harness informa.

Se a conta não tiver acesso ao modelo mais caro, a seiva desce para o de baixo, segue e diz isso na entrega.

## Como contribuir

Toda proposta precisa de um caso real que ela melhora e de um caso de teste novo em [testes/casos.md](testes/casos.md). O passo a passo está no [CONTRIBUTING.md](CONTRIBUTING.md).

## Origem

A primeira versão saiu de um levantamento feito em 2026-09-26 em onze projetos públicos de orquestração de agentes, entre eles o ECC, o Superpowers, o Spec-Kit, o BMAD e o GSD, e em estudos sobre viés de modelos usados como revisores. O texto foi escrito do zero, em português. O que veio de onde está no [FONTES.md](FONTES.md).

## Licença

MIT. Veja [LICENSE](LICENSE).
