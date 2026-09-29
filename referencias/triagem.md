# Triagem: nível, lentes e orçamento

## Níveis

| Nível | Quando | Etapas | Agentes (típico) |
|---|---|---|---|
| **N0 · Direto** | Pergunta, texto, ajuste de uma linha óbvio, renomear algo local. Nenhuma superfície sensível. | O orquestrador faz. Se tocou código, roda a verificação do projeto. | 0 |
| **N1 · Leve** | 1 a 3 arquivos, fácil de desfazer, comportamento claro, nenhuma superfície sensível. | 2 (se preciso), 6, 7 e 8 com um revisor. Plano de até 5 linhas no registro. | 1 a 3 |
| **N2 · Padrão** | Feature ou bug de vários arquivos, regra de negócio nova ou alterada, ou código que **usa** um mecanismo sensível que já existe sem mudar como ele funciona (uma rota nova que chama a checagem de permissão de sempre, uma consulta nova com o filtro de cliente de sempre). | Todas. | 5 a 10 |
| **N3 · Crítico** | Pelo menos um critério da lista abaixo. | Todas, com os reforços. | 8 a 12 |

**Critérios de N3.** Cada um se verifica olhando o pedido, o relatório do batedor ou o diff:

1. muda **como** se decide quem acessa o quê: autenticação, sessão, permissão, isolamento entre clientes;
2. cria ou altera migration, ou mexe em dado em massa (importação, exclusão, correção retroativa);
3. altera cálculo de dinheiro, imposto, peso ou quantidade que vai para documento ou para fora;
4. altera o que sai do sistema: e-mail, nota fiscal, integração regulatória, arquivo exportado;
5. apaga dado, ou mexe em segredo, infraestrutura, deploy ou produção;
6. viola, ou chega perto de violar, um inegociável do perfil (seção L);
7. é bug que já voltou, ou um escape (ver a etapa 1 no SKILL.md).

**Reforços do N3:** adversário `profundo`, acima do construtor e em outro modelo; lentes em `forte`; adversário também sobre o diff; verificador em modelo diferente do implementador; plano com volta (rollback) obrigatória; nada de edição em paralelo; revisão por outro provedor quando o usuário tiver um disponível ([harness](harness.md)).

Regras:

- Na dúvida entre dois níveis, fica o maior.
- **Item que o projeto já registrou com gravidade** (um bug com severidade medida, um risco classificado) é o ponto de partida. Subir ou descer exige uma linha de motivo no registro. Como o registro pode estar velho, a medição do batedor pode mudar o nível.
- O nível sobe sozinho quando uma etapa encontra superfície sensível. Descer exige dizer ao usuário por quê.
- Pedido explícito de rigor ("revisa tudo", "não pode dar erro") vale como N2 no mínimo.
- Pedido de pressa não rebaixa um N3: diga o risco e pergunte.

## Sinais que acionam cada lente

Leia o pedido, o relatório do batedor, o plano e, na etapa 8, o diff. **Anote no registro o sinal que acionou cada lente**: a evolução da skill depende dessa anotação.

| Lente | Sinais |
|---|---|
| [segurança](../papeis/lentes/seguranca.md) | autenticação, sessão, token, papel ou permissão, rota nova, entrada do usuário, upload, SQL montado, shell, segredo ou variável de ambiente, CORS e cabeçalhos, dependência nova, conteúdo externo lido por IA |
| [dados](../papeis/lentes/dados.md) | migration, schema, escrita em tabela, transação, importação ou exclusão em massa, isolamento entre clientes, cálculo de valor, peso ou quantidade, sincronização offline, repetição de envio, data e fuso |
| [design](../papeis/lentes/design.md) | tela, componente, texto de interface, fluxo, estados de vazio, erro e carregando, acessibilidade, relatório visual |
| [desempenho](../papeis/lentes/desempenho.md) | laço sobre coleção, consulta de listagem ou relatório, tamanho de resposta, paginação, job, lista longa no app, imagem ou arquivo grande |
| [operação](../papeis/lentes/operacao.md) | deploy, configuração, cron, servidor web, CI, aplicação de migration, backup, log e alerta, volta, ordem de subida |
| [contrato](../papeis/lentes/contrato.md) | mudança de API ou de formato que outro cliente consome (app já instalado, integração, outro serviço, exportação), campo removido ou renomeado, versão |
| lentes do projeto | superfícies S do perfil. Se o projeto tem agente para ela e o arquivo do agente ainda existe, use o agente do projeto; se sumiu, use a lente da seiva mais próxima e anote. |

**Invasor:** varredura de segurança do sistema inteiro, a pedido do usuário ou em tarefa de segurança N3 ([papel](../papeis/invasor.md)). O relatório dele passa por um revisor de segurança antes de virar conserto.

**Adversário:** revisa o plano em N2 e N3 e o diff em N3. Em qualquer nível, se nenhuma lente acionar no diff, o adversário faz a revisão do diff.

**Teto:** até 4 revisores por portão. Se acionarem mais, junte lentes afins no mesmo agente (desempenho com operação, contrato com dados) ou parta a tarefa.

## Partir a tarefa

Um N3 grande vira etapas menores, cada uma com entrega própria. Sinais: plano com mais de 8 tarefas, mais de 15 arquivos ou duas superfícies N3 independentes.

## Anotação no registro

```
Nível: N2 — regra de negócio nova em 4 arquivos; usa o filtro de cliente existente sem mudá-lo
Superfícies: dados (escrita em tabela), contrato (app instalado lê o campo)
Lentes: plano → adversário, dados (sinal: escrita em tabela), contrato (sinal: campo lido pelo app) · diff → recalcular
Categorias: batedor rapido · construtor forte · adversário forte · lentes padrao · implementador padrao · verificador padrao
Orçamento: 8 agentes · paradas com o usuário: plano, entrega
```
