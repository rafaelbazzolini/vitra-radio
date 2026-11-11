# Arquitetura

## Duas edições, um projeto

O app nativo preserva a integração AppKit, painel flutuante, ciclo de vida do macOS, áudio com AVFoundation e processamento em tempo real. A edição Flutter cria a base responsiva de Windows/Linux/Android/iOS e uma variante de desktop macOS para desenvolvimento; ela usa `media_kit` para tocar streams. Não são implementações com paridade total: o README lista diferenças.

## Estado e dados

`RadioPlayer`/`RadioStore` controlam playback, favoritas, recentes e biblioteca persistida. As distribuições não carregam dados do desenvolvedor. Fixtures sintéticas só são usadas nos testes ou modo explícito de screenshots.

## Agenda

As regras guardam datas civis e minutos locais, sem converter a data escolhida para UTC. O motor reconstrói a ocorrência vigente em vez de depender de ter presenciado o minuto inicial. Datas específicas vencem regras semanais. Dentro da mesma prioridade, o início mais recente vence; para o mesmo início, vence o término mais próximo. Términos anteriores ao início atravessam a meia-noite.

A agenda usa timer enquanto o processo está ativo. No macOS nativo há observação de wake. No Flutter a volta ao primeiro plano reavalia a regra. Mobile suspenso não tem execução garantida; não existe alarm service ou wake lock nesta edição.

## DSP nativo

Um MTAudioProcessingTap calcula RMS estéreo e alimenta medidores através de snapshots atômicos. O espectro passa o áudio por oito filtros passa-faixa, independentes por canal, com ataque/queda suavizados. O callback não faz I/O, chamadas de UI ou alocações por amostra. O equilíbrio usa RMS integrado, limite de ganho, gate de silêncio e limitador de pico.

## Distribuição

CI valida código em dev/PRs. Release recebe apenas main, atribui versão e compila no host adequado. Publicação só roda após os builds necessários. Clientes consultam releases estáveis, comparam a versão e abrem a página oficial. Nenhum código da branch é executado no dispositivo sem um novo build/instalação.
