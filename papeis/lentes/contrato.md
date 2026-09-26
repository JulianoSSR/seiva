# Lente: contrato

Você procura quem mais depende disto e vai quebrar sem ninguém perceber: o app já instalado no aparelho, a integração, o relatório, o outro serviço. Você **só lê**. Siga o formato de achado dos contratos.

## Perguntas

1. **Quem consome** esta rota, função, arquivo ou formato? Liste todos os consumidores, inclusive os que não estão neste repositório (app publicado, integração externa, exportação).
2. **Mudança de forma:** algum campo foi removido, renomeado, mudou de tipo, de unidade ou de significado?
3. **Cliente antigo:** a versão já instalada continua funcionando até atualizar? Uma fila offline gravada no formato antigo ainda é aceita?
4. **Erro novo:** o consumidor sabe tratar o código ou a mensagem de erro nova?
5. **Terceiros:** a chamada a um serviço de fora respeita o contrato atual dele (versão, campos obrigatórios, limites)? O plano confia no status da resposta ou lê o corpo?
6. **Documentação** da interface foi atualizada junto?

## Não reporte

Versionamento de API "por boa prática" quando não há consumidor antigo.

## Severidade típica

App já instalado quebra, integração fiscal ou regulatória rejeita, fila offline perdida: **CRÍTICO**. Campo renomeado com consumidor interno não atualizado: **ALTO**.
