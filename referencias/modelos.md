# Categorias de modelo

A categoria descreve capacidade necessária, não uma marca ou um preço fixo. O mapa do ambiente é detectado no início da tarefa e guardado no perfil com fonte, data e limitações.

| Categoria | Uso |
|---|---|
| `script` | contagem, hash, diff, teste, extração e validação determinística |
| `rapido` | localização, extração curta e premissa mensurável |
| `padrao` | implementação delimitada, teste, plano e revisão N2 |
| `forte` | plano e lentes N3, implementação delicada |
| `profundo` | adversário N3, arquitetura e defeito persistente |

## O que otimizar

O alvo é o menor consumo **total** que mantenha os critérios de qualidade. Inclua orquestrador, todos os agentes, tentativas interrompidas, repetição, contexto retransmitido, cache e retomadas. Compare volume bruto de tokens, preço e unidades ponderadas separadamente: modelo de menor preço pode gastar mais tokens para concluir.

1. Use script quando não houver julgamento.
2. Escolha a menor categoria que dê conta com evidência. Não use um modelo pequeno se ele precisar de sucessivas correções ou de um pacote enorme.
3. Meça ao fim da tarefa com a fonte disponível. Notificação de término não cobre necessariamente cache nem tentativas anteriores.
4. Não declare economia sem base comparável. A avaliação em [AVALIACOES](../docs/AVALIACOES.md) controla tarefa, qualidade e fonte.

## Independência

Quem implementa não aprova. Ordem de diversidade: `outro-provedor`, `outro-modelo`, `mesmo-modelo-contexto-limpo`, `mesmo-contexto`. A última é autoconferência e não substitui o portão independente exigido.

N2 admite outra instância no mesmo modelo, de contexto limpo. N3 requer a diversidade prevista no perfil e na triagem. Se o ambiente não consegue fornecê-la, declare a lacuna antes de prosseguir; não a esconda atrás de um nome de papel.

## Categoria por papel e modelo real

A triagem fixa a categoria de **cada papel** (batedor, construtor, adversário, lentes, implementador, verificador, revisor, conserto) e o pacote a registra. O disparo passa o `model` explícito; agente que herda o modelo da sessão não cumpre a categoria. Se o adaptador não deixa escolher o modelo, a tarefa registra a lacuna (`attempt-start` sem `--modelo` avisa) e **não declara independência**. Cada relatório e cada tentativa guardam o modelo real usado (`attempt-complete --modelo-real`), porque o pedido e a execução podem divergir. Revisão e conserto em categoria menor que a exigida valem como autoconferência, não como portão.

## Repetição e indisponibilidade

- Rodada 2: nova instância, mesma categoria, pacote com o erro e a evidência anterior.
- Rodada 3, se o portão permitir: categoria acima. Ao esgotar a categoria ou o teto, interrompa e registre a pendência.
- Falta de acesso, saldo ou suporte é indisponibilidade, não prova de que a categoria inferior serve.
- **Nunca rebaixe automaticamente tarefa ou revisão sensível.** Preserve o nível e os requisitos; espere, troque por capacidade equivalente comprovada ou leve as opções ao responsável.
- Em tarefa não sensível, uma alternativa menor exige justificativa registrada, critérios de verificação preservados e autorização quando as regras do projeto a exigirem.
- Não grave uma indisponibilidade momentânea como rebaixamento permanente. Registre quando foi observada e confira novamente quando houver sinal de mudança.

Nomes de modelos, esforço e parâmetros pertencem ao adaptador. Não copie mapas antigos de outra conta como se estivessem disponíveis aqui.
