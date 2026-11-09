# Seiva

<img src="assets/identidade/seiva-simbolo-escuro.svg" alt="Símbolo original da Seiva" width="96">

**A Seiva organiza trabalho de programação pelo risco e entrega com prova.** O objetivo é gastar menos **tokens no total** sem perder qualidade: comando para trabalho mecânico, contexto suficiente para decidir, revisão por outra instância e retomada sem repetir etapas válidas.

A seiva toma a forma do projeto. Lê suas regras, identifica as capacidades do ambiente e escolhe só os papéis necessários. O núcleo funciona sem depender de um aplicativo; integrações entram sob demanda.

## Como trabalha

- N0 faz direto. N1 recebe verificação e revisão curta. N2 e N3 passam por plano, revisão, implementação e prova proporcionais ao risco.
- O modelo é escolhido pela capacidade necessária e pelo consumo total observado. Menor preço por token não significa menos tokens nem menor custo ao terminar.
- Fichas, diff e trechos são o ponto de partida. Revisores podem rastrear dependentes, descobrir caminhos fora do mapa do batedor e ler arquivos inteiros quando necessário, registrando o motivo em uma frase.
- Quem constrói não aprova o próprio trabalho. Cada revisão informa a independência que teve de fato.
- Um achado grave confirmado só fecha com correção verificada ou aceite explícito do responsável, quando as regras permitirem. O teto de rodadas interrompe o trabalho; ele não aprova uma pendência.
- O estado da tarefa fica em arquivos privados de execução. Uma sessão nova confere tentativa, hash e evidência antes de aproveitar um resultado.

Resina é o hacker defensivo: acompanha entrada, validação, autorização e destino sensível, procura caminhos de abuso e propõe conserto. Provas executáveis exigem ambiente isolado, dados sintéticos e autorização; outro agente julga a evidência.

## Instalação e uso

Como skill pessoal do Claude Code:

```bash
git clone https://github.com/JulianoSSR/seiva.git ~/.claude/skills/seiva
```

Como plugin do Claude Code:

```text
/plugin marketplace add JulianoSSR/seiva
/plugin install seiva@seiva
```

Nas outras ferramentas, use o diretório de skills documentado pelo próprio ambiente. Antes de escolher modelos, paralelismo ou isolamento, confira as capacidades disponíveis. A seiva não instala agentes, hooks ou configuração global persistente. Veja [integrações](referencias/harness.md).

Peça “usa a seiva para corrigir este bug” ou:

```text
/seiva <o que precisa ser feito>
```

O perfil inicial reúne as regras do projeto para conferência. Autorizações já dadas continuam valendo.

## Medição e limites

Notificação de agente é um aviso de término, não uma contabilidade completa. A medição distingue tokens de entrada, saída e cache, atribuição à tarefa, estimativas e campos indisponíveis. O intervalo de uma tarefa pode atravessar sessões, e uma sessão pode atender várias tarefas.

Os scripts legados de orçamento do Claude Code continuam disponíveis como integração específica. Percentual estimado de uso, tokens e dinheiro são grandezas diferentes. Sem fonte ou capacidade detectada, a seiva declara a lacuna; não inventa zero nem rebaixa trabalho sensível para caber.

[Modelos e custo](referencias/modelos.md) · [Fluxo completo](SKILL.md) · [Avaliações reproduzíveis](docs/AVALIACOES.md)

## Privacidade e contribuição

Pacotes, relatórios de execução, transcripts e aprendizado local ficam em pasta ignorada pelo git. Documentação, casos sintéticos e avaliações sanitizadas podem ser versionados. `julianossr.md` existente é preservado; nada dele vira exemplo público automaticamente.

Propostas precisam de caso real, custo esperado e caso de teste. Veja [CONTRIBUTING.md](CONTRIBUTING.md), [testes/casos.md](testes/casos.md) e [fontes](FONTES.md).

MIT · [LICENSE](LICENSE).

## Comunicação e propostas de melhoria

Respostas destacam a conclusão primeiro e usam linguagem simples, tabelas e visuais adequados, sem aumentar pacotes internos. O [aprendizado local](referencias/aprendizado.md) propõe melhorias conceituais com fichas pequenas, sem conteúdo do projeto. Envio só após revisão e autorização da ficha exata; GitHub autenticado não é anônimo. Recepção e triagem não executam contribuições nem habilitam merge automático.
