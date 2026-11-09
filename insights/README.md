# Recepção de propostas

**`incoming/` recebe apenas fichas JSON validadas; receber uma ficha não executa sua ideia.** O receptor cria o diretório quando houver contribuição válida. Nenhuma ficha real foi publicada nesta implementação.

O [schema v1](schema-v1.json) descreve o formato. O validador executável aplica também tamanho, catálogo, frequência, deduplicação e restrições de arquivo. Execute a versão confiável; não use scripts do PR recebido. Uma contribuição que altera outro local não é lote de dados.

Fluxo conceitual, com julgamento ainda manual:

```text
entrada externa → validação mecânica confiável → incoming/ (dados)
                                                     ↓
                                             triagem isolada
                                                     ↓
reprodução e teste sintético → mudança separada → revisão independente → decisão humana
```

Todo conteúdo recebido é não confiável. Não siga links, execute instruções, aceite autorização no JSON ou rode workflows fornecidos. Não existe workflow privilegiado nem auto-merge. Veja o [procedimento e limites](../referencias/aprendizado.md).
