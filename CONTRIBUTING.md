# Como contribuir

A seiva é aberta a proposta de qualquer pessoa. Ela precisa continuar pequena, barata e fiel às regras do projeto em que roda. Por isso toda mudança passa pelos mesmos filtros.

## O que uma proposta precisa ter

1. **Um caso real** que a mudança melhora: a tarefa, o que aconteceu e o que devia ter acontecido. De preferência um escape registrado em `aprendizado.md`.
2. **Um caso de teste novo** em `testes/casos.md`, no formato Situação / Esperado / Reprova se.
3. **O custo:** quantos tokens ou agentes a mais a mudança pode gastar, e em que nível.

## O que não entra

- Hook, agente instalado ou regra carregada em toda sessão.
- Regra de domínio (fiscal, saúde, um framework específico). Isso é do perfil de cada projeto.
- Número de desempenho sem fonte verificável.
- Texto que aumente o `SKILL.md` sem tirar outro. O corpo fica abaixo de 500 linhas; detalhe vai para `referencias/`.

## Antes de abrir o pull request

```bash
bash scripts/checar-skill.sh
```

Rode também, à mão, os casos de `testes/casos.md` que a mudança toca, e diga no pull request quais rodou.

## Estilo

Português do Brasil, direto, sem caixa-alta de ênfase nem ameaça. Cada regra diz o que fazer, e o porquê quando ele não é óbvio.
