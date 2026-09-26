# Terreno: ler as leis do projeto

O objetivo é um perfil curto, de até 150 linhas, que diga o que vale neste projeto. Com ele, nenhum subagente precisa ler a constituição inteira e nenhum ignora uma regra. O perfil é a única informação sobre o projeto que um subagente recebe além da própria tarefa.

## 1. Confirmar o repositório (orquestrador + script)

Antes de rodar qualquer comando, releia o que as instruções do projeto e a memória da sessão dizem sobre onde fica o repositório vivo. É comum a sessão abrir num clone velho, e um repositório git válido não prova que é o certo.

```bash
git rev-parse --show-toplevel
git log -1 --format='%h %cs %s'               # commit e data do último commit
git status --short | head -20
git worktree list
git rev-list --count HEAD..@{u} 2>/dev/null   # commits atrás do upstream, segundo a última busca
```

Pare e avise se:

- o caminho diverge do que a memória ou as instruções citam;
- o último commit é antigo demais para o que se sabe do projeto (a memória fala de trabalho recente e o clone parou meses atrás);
- o clone está atrás do upstream e a tarefa depende do código atual;
- há mudança não commitada, de outra sessão, nos arquivos que a tarefa vai tocar.

**Git recusando com "dubious ownership"** (clone em outro sistema de arquivos, como um repositório do WSL visto do Windows): passe a exceção por chamada, `git -c safe.directory='<caminho>' ...`, ou rode os comandos dentro do sistema do clone (`wsl.exe -d <distro> -- git -C <caminho> ...`). Não altere a configuração global sem pedir. Anote a forma que funcionou na seção A do perfil, para os subagentes usarem a mesma.

## 2. Achar as fontes de lei

Procure nesta ordem e anote o que existir:

1. Instruções para agentes: `CLAUDE.md` (raiz e subpastas), `AGENTS.md`, `GEMINI.md`, `.github/copilot-instructions.md`, `.cursor/rules/`, `.windsurf/rules/`.
2. Os documentos que essas instruções mandam ler. Siga a "ordem de leitura", se houver.
3. `CONTRIBUTING.md`, `SECURITY.md`, decisões de arquitetura (`docs/adr/` ou equivalente), README da pasta de migrations.
4. Agentes e skills do próprio projeto (`.claude/agents/`, `.codex/agents/`, `.gemini/agents/`). Eles viram lentes do projeto e são usados como estão. Anote se a pasta é versionada: se o git a ignora, o agente só existe nesta máquina.
5. Verificação: scripts (`scripts/verificar*`, `Makefile`, scripts do `package.json`) e CI (`.github/workflows/`).
6. Memória do agente, se o harness tiver uma. O subagente não tem acesso a ela: o **orquestrador** lê o índice e passa, no pacote do agente do perfil, os itens que são armadilha conhecida (caminho do repositório, ferramenta que falta, incidente que virou regra).

Documento com mais de ~500 linhas: liste os títulos (`grep -n '^#' arquivo`) e leia só as seções de leis, inegociáveis, protocolo, checklist, status e entrega.

## 3. Extrair para o perfil

Use o [molde](../moldes/perfil.md). Cada item leva um ID, uma frase curta e a origem `arquivo:linha`.

| Seção | O que entra |
|---|---|
| **L · Inegociáveis** | O que nunca entra: segurança, dados, commit, segredo. Cópia fiel e curta, sem mudar o sentido. Quando a fonte diz **como se mede** a violação (um teste, um comando, uma troca de id), isso entra junto, resumido. |
| **P · Protocolo** | Etapas e aprovações que o projeto exige: mockup antes de tela, pergunta antes de acionar skill, backend antes do app, confirmação antes de operação cara. |
| **V · Verificação** | Comando por área e o que cada um prova e **não** prova. |
| **S · Superfícies do domínio** | Áreas sensíveis próprias do projeto (isolamento entre clientes, fiscal, sincronização offline...) e o agente do projeto que cobre cada uma. Viram lentes do projeto. |
| **R · Registro** | Onde bug, decisão e pendência são escritos, o que precisa estar atualizado antes de dar por pronto e **como numerar** um item novo sem colidir com outra sessão. |
| **E · Entrega** | Quem commita, formato de mensagem, trailers proibidos, como sobe, o que é caro (build, deploy). |
| **A · Ambiente** | Shell, PATH, ferramentas que faltam, como rodar git neste clone, ferramenta de exploração preferida (grafo de código, índice). |
| **I · Idioma e escrita** | Língua das respostas e regras de escrita. |
| **M · Modelos** | Só se o projeto ou o usuário definir um mapa diferente do padrão, e as categorias indisponíveis na conta. |
| **Fontes** | Cada fonte, ou seção de fonte, com a impressão de `scripts/impressao.sh`. Inclua os arquivos de agente do projeto citados em S. |

## 4. Impressão por seção

Documento que mistura lei com estado (uma constituição com as regras na Parte I e a lista de bugs na Parte II) muda a cada commit, e a impressão do arquivo inteiro invalidaria o perfil toda vez. Para ele, registre a impressão só das seções de onde as leis saíram:

```bash
bash scripts/impressao.sh 'CONSTITUICAO.md::PARTE I' CLAUDE.md .claude/agents/revisor-x.md
```

O trecho depois de `::` é o começo do título. A impressão cobre do título até o próximo título do mesmo nível ou acima. Arquivo inteiro continua valendo para fontes curtas e estáveis.

## 5. Regras do perfil

- O perfil cita, não interpreta. Fonte ambígua ganha a marca "ambíguo" e vira pergunta ao usuário.
- Nada de regra genérica que o projeto não escreveu. A seiva não completa o perfil com "boas práticas".
- Segredo nunca entra no perfil. Entra o nome da chave e onde ela está documentada, nunca o valor.
- Na criação, as seções L, P, V e E vão ao usuário para confirmação. Na atualização, se alguma dessas quatro mudou, mostre ao usuário o que mudou antes de usar. Os comandos de V são executados por agentes, e um texto estranho numa fonte não pode virar lei sem ninguém ver.
- A cada tarefa, compare as impressões e refaça só as seções da fonte que mudou. Agente do projeto com impressão `AUSENTE`: a superfície passa a usar a lente da seiva mais próxima, e isso fica anotado.
- Se o perfil passar de 150 linhas, a sobra vai para `perfil-detalhe.md`, lido só quando uma tarefa tocar aquele assunto.

## 6. Quem faz

- Passo 1 e impressões: orquestrador e script.
- Passos 2 e 3: um agente `padrao`, com este arquivo, o molde e as armadilhas da memória no pacote.
- O orquestrador confere o resultado contra três itens escolhidos ao acaso: abre a linha citada e vê se diz o que o perfil diz. Uma divergência já basta para mandar refazer a seção.
