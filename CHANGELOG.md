# Registro de mudanças

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
