# Como contribuir

**Propostas precisam de evidência e revisão independente.** A Seiva é aberta a proposta de qualquer pessoa. Ela precisa continuar pequena, barata e fiel às regras do projeto em que roda. Por isso toda mudança passa pelos mesmos filtros.

## O que uma proposta precisa ter

1. **Um caso real** que a mudança melhora: a tarefa, o que aconteceu e o que devia ter acontecido. De preferência um escape registrado em `julianossr.md`.
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

Ele também confere a assinatura: script novo em `scripts/` leva `# seiva · JulianoSSR · MIT` na 2ª linha, logo depois do shebang.

Rode também, à mão, os casos de `testes/casos.md` que a mudança toca, e diga no pull request quais rodou.

## Estilo

Português do Brasil, direto, sem caixa-alta de ênfase nem ameaça. Cada regra diz o que fazer, e o porquê quando ele não é óbvio.

## Fichas de aprendizado

O [canal de propostas](referencias/aprendizado.md) recebe dados validados, sem código ou conteúdo de projeto cliente. O cliente propõe o conceito; o mantenedor reproduz contra base confiável e prepara mudança separada. Não executar script de PR externo para validar a própria contribuição.

`testes/casos.md` é catálogo textual e não substitui testes executáveis. Rode `bash scripts/testar.sh`; registre separadamente testes automáticos, avaliações com modelos e revisão humana. Comunicação à pessoa segue [as regras didáticas](referencias/comunicacao.md).

## Bloco de entrega

O agente prepara o bloco; o usuário executa commit e push. Use arquivos explícitos, sem `git add .`/`-A`, comandos entre chaves com `&&`, estatística antes de gravar e pausa indicando o esperado. Commit não inclui assinatura/trailer de IA. Verifique que o status dos documentos acompanha a mudança; preserve itens já staged de outra sessão. O bloco solicitado nesta parceria termina em `git push`, sem o agente executá-lo.
