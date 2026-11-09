---
name: seiva
description: |
  Organiza desenvolvimento pelo risco com plano, implementação, revisão independente e prova.
  Busca menor consumo total de tokens mantendo qualidade e as regras do projeto. Use em tarefa
  média ou maior, área sensível, bug recorrente ou pedido de "seiva", "enxame", "planeja e revisa".
  Tarefa trivial segue direto; ferramentas e adaptadores só entram quando necessários.
license: MIT
compatibility: Núcleo independente do aplicativo. Scripts exigem git, bash e dependências verificadas; estado e monitor usam Python 3. Capacidades de agentes, modelos e medição são detectadas por ambiente.
metadata:
  version: "1.5.0"
  author: "JulianoSSR"
---

# Seiva

**A Seiva organiza o trabalho conforme o projeto, o risco e a prova disponível.** O orquestrador lê suas regras, classifica o risco, usa só os papéis necessários e fecha com evidência. Não instala hooks, agentes globais nem configuração carregada em toda sessão.

## Regras do núcleo

1. **O projeto manda**, respeitadas as instruções da plataforma. Leia as regras atuais, preserve edições concorrentes e cumpra as aprovações já exigidas; autorização existente continua valendo.
2. **Otimize o trabalho completo.** Conte orquestrador, agentes, cache, tentativas interrompidas, revisão e retomada. Menor preço por token não implica menos tokens nem menor custo final.
3. **Comando para o mecânico.** Contar, extrair, calcular hash, montar diff e rodar verificação não exigem julgamento de modelo.
4. **Capacidade antes de preço.** Categoria vem da tarefa. Indisponibilidade ou saldo baixo não autorizam rebaixar trabalho sensível.
5. **Quem constrói não aprova.** Outra instância revisa com contexto limpo; informe o nível real de independência e a limitação do ambiente.
6. **Prova antes de concluir.** Resultado precisa de tentativa atual, artefato válido, hash e evidência. Um relatório existente não prova conclusão.
7. **Contexto suficiente, sem repetição gratuita.** Comece por índices, fichas, diff e trechos; amplie para dependentes ou arquivo inteiro quando necessário, com justificativa breve. O batedor é mapa inicial, não limite da revisão.
8. **Um dono por arquivo.** Paralelo só para escrita em arquivos distintos e sem dependência. Arquivo compartilhado fica com o orquestrador.
9. **Teto interrompe, não aprova.** N1 até 1 rodada, N2 até 2, N3 até 3 por portão. Grave confirmado fecha com correção verificada ou aceite explícito permitido pelas regras. No teto, pendência continua pendência.
10. **Premissa se mede.** Sem comando ou evidência, marque suposição e seu impacto.
11. **Limitação aparece.** Dado ausente não é zero; autoconferência não é revisão independente; notificação não é contabilidade.
12. **Evolução precisa de evidência.** Escape e correção do usuário viram proposta, sem mudar regras automaticamente.

## Fluxo

| Etapa | Resultado | N0 | N1 | N2 | N3 |
|---|---|---|---|---|---|
| 0 Terreno | perfil e capacidades | usa regras | ✓ | ✓ | ✓ |
| 1 Triagem | nível, escopo e orçamento | direto | ✓ | ✓ | ✓ |
| 2 Reconhecer | mapa e premissas | — | se preciso | ✓ | ✓ |
| 3 Propor | plano | — | até 5 linhas | ✓ | ✓ |
| 4 Atacar plano | achados | — | — | adversário + lentes | reforçado |
| 5 Decidir | julgamento e autorização | — | — | ✓ | ✓ |
| 6 Construir | mudança e relatório | orquestrador | ✓ | ✓ | ✓ |
| 7 Verificar | prova dos critérios | comandos | ✓ | ✓ | outro modelo |
| 8 Atacar código | revisão do diff | — | revisor | adversário + sinais novos | lentes + adversário |
| 9 Entregar e aprender | status e medição | ✓ | ✓ | ✓ | ✓ |

### 0 · Terreno

Confirme caminho, HEAD, árvore e diffs antes de editar. Leia instruções, memória e documentos canônicos atuais. O [perfil](moldes/perfil.md) cita origem das regras; impressão das fontes permite atualizar só o que mudou. Mostre alterações de L, P, V e E quando o protocolo exigir. Não configure git global para contornar ownership.

Execução fica em pasta privada ignorada pelo git: `.claude/seiva/` se já ignorada, ou `.seiva/` com exclusão local autorizada. Sem exclusão, use diretório privado externo e registre o caminho. Documentação e exemplos sanitizados são versionáveis. Preserve `julianossr.md` e `aprendizado.md` existentes; não publique seu conteúdo.

Detecte capacidades de agentes, contexto limpo, modelos, ferramentas, isolamento e medição. Carregue apenas o adaptador necessário: [harness](referencias/harness.md). Não crie agentes globais para compensar recurso ausente.

Em retomada, siga [retomada](referencias/retomada.md): localizar tarefa, ler contexto e conferir estado antes de qualquer redisparo.

### 1 · Triagem

Use `scripts/nova-tarefa.sh <pasta-de-trabalho> <slug>` para guardar base e foto inicial da árvore. Classifique por [triagem](referencias/triagem.md): nível, superfícies concretas, lentes e sinal de cada uma, categoria e orçamento. Bug já classificado parte da gravidade registrada; divergência precisa de motivo.

Procure escape em tarefas anteriores pelos arquivos entregues, lendo só registros pertinentes. Resuma ao usuário nível, motivo, lentes, orçamento e pontos de decisão. Não repita pedido de autorização já concedida.

Antes da leva, confira orçamento pela fonte suportada, grave próxima ação e pacote. Sem saldo confiável, não invente uma previsão que cabe. Nível sensível permanece sensível mesmo quando não cabe.

### 2 · Reconhecer

O [batedor](papeis/batedor.md) localiza código, dependentes e alternativas existentes; mede premissas. Em bug, descreve o padrão e procura variantes, informando cobertura e limites reais.

Relatório cita caminhos e linhas; `scripts/ficha-tecnica.sh <tarefa> --de relatorios/batedor-1.md` gera fichas e trechos iniciais. Qualquer revisor pode conferir a fonte e descobrir caminhos fora desse mapa. Ampliação de leitura não requer nova autorização se estiver dentro do escopo autorizado.

### 3 · Propor

O [construtor](papeis/construtor.md) usa [molde do plano](moldes/plano.md), pedido, regras pertinentes e mapa. N2 usa categoria `padrao`; N3, `forte`. Perguntas das lentes viram riscos com mitigação verificável. N3 inclui volta. Comportamento novo sem verificação precisa de tarefa de teste ou decisão explícita permitida pelas regras.

### 4 · Atacar o plano

[Adversário](papeis/adversario.md) e [lentes acionadas](papeis/lentes/) revisam em contexto limpo. N2 usa `padrao`; N3 usa adversário `profundo` e lentes `forte`. O pacote leva caminhos, IDs das regras, critérios e [contrato de achado](referencias/contratos.md), sem despejar conversa.

### 5 · Decidir

`scripts/julgar-pre.sh <tarefa> plano <relatórios>` numera e agrupa; não julga. O orquestrador confere prova, dá veredito e agrupa por causa: intenção ao usuário; plano ao construtor; ajuste ao implementador; adiamento ao registro canônico permitido.

Suspeita grave é medida antes de descarte. Cada achado mantém ID, status e evidência; “não houve achado novo” não fecha os anteriores. Em N2/N3, cumpra autorização do plano antes de código, considerando a autorização que já existe na conversa.

### 6 · Construir

O [implementador](papeis/implementador.md) recebe tarefa, arquivos exclusivos e critério de pronto. Premissa desmentida volta com evidência. Mudança dependente é sequencial; em N3 não há edição paralela. Testes seguem regras e comandos do projeto.

### 7 · Verificar

O [verificador](papeis/verificador.md) é outra instância; em N3, outro modelo conforme capacidade e protocolo. Confere critérios, riscos e se uma regressão seria detectada. Distingue passou, falhou e não exercitado. Falha volta com evidência dentro do teto; esgotamento interrompe.

### 8 · Atacar o código

`scripts/diff-tarefa.sh <tarefa> <arquivos entregues>` monta o diff a partir da base registrada, incluindo novos arquivos. Diferença não atribuível a esta tarefa precisa de decisão, nunca é assumida como própria.

Recalcule lentes pelo diff. N1 tem revisor; N2, adversário e lente de sinal novo; N3, lentes e adversário. Confirme os achados do plano pelo ID. Correção grave recebe verificação direcionada, ainda que não abra nova exploração geral. [Revisão](referencias/revisao.md) define fechamento.

**Resina**, o [hacker defensivo](papeis/invasor.md), rastreia entrada → validação → autorização → destino sensível e dependentes. Entra por gatilhos da triagem, sem duplicar a lente de segurança no mesmo escopo. Inspeção estática é o padrão. Prova executável só em ambiente isolado, com dados sintéticos, sem credenciais reais ou produção, e autorização do escopo. Outro agente julga a prova antes do conserto.

### 9 · Entregar e aprender

Atualize os registros canônicos e respeite o protocolo de entrega, commit e publicação do projeto. Informe mudança, prova, pendências, limitações, decisões e independência. Achado grave aceito precisa de responsável, escopo, motivo e autorização válida; inegociável não admite aceite.

Meça pela fonte disponível com intervalo da tarefa, incluindo tentativas. Com `medir.sh`, confirme suporte e atribuição antes de usar números. Registre aprendizado local em `julianossr.md`, sem expor dados privados. Conteúdo público deriva apenas de avaliação sanitizada.

## Comunicação e aprendizado local

Respostas à pessoa, relatórios e documentação explicativa seguem [comunicação](referencias/comunicacao.md): conclusão em negrito no primeiro parágrafo, linguagem simples, tabelas e visuais conforme o conteúdo. Use recursos nativos/scripts; nenhum agente extra só para formatar. Pacotes internos continuam compactos.

No fechamento, bloqueio ou intervenção, as [seis capacidades](referencias/autoaperfeicoamento.md) aproveitam prova e reflexão privadas antes de propor ficha pelo [aprendizado](referencias/aprendizado.md), sem copiar conteúdo do cliente, instalar observador ou aplicar regra automaticamente. Mostre ficha, título, corpo, canal e visibilidade exatos antes de pedir autorização específica. Recusa/silêncio não envia. O cliente propõe o conceito; a correção da Seiva cabe ao mantenedor em fluxo separado.

## Estado e parada

`estado.json` é a fonte canônica de execução; Markdown é projeção e contexto curto. Tentativa, dono, base, hashes e evidência sustentam a conclusão. Marcar etapa feita exige artefatos e --attempt válido; etapa mecânica usa --evidence explícita. Estado legado sem comprovação exige revalidação. Migração de tarefa legada preserva arquivos e não converte relatório antigo em aprovação atual. Veja [retomada](referencias/retomada.md).

Antes da leva, grave pacote, tentativa e próxima ação. Depois, valide relatório e artefatos contra a tentativa esperada, incluindo marcador final produzido pelo agente com os IDs corretos; o orquestrador não completa relatório velho para aceitá-lo. No limite de custo, contexto, rodadas ou capacidade, pare de abrir levas, guarde pendências e deixe caminho de retomada. Não reduza nível para continuar.

## Referências sob demanda

- [Terreno](referencias/terreno.md), [triagem](referencias/triagem.md), [modelos](referencias/modelos.md).
- [Contratos](referencias/contratos.md), [revisão](referencias/revisao.md), [harness](referencias/harness.md).
- [Retomada](referencias/retomada.md), [evolução](referencias/evolucao.md), [avaliações](docs/AVALIACOES.md).
- `papeis/` e `moldes/`: só o papel e o molde necessários à etapa.
