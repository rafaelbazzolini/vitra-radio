# Podcasts na edição nativa macOS

**Podcasts** aparece na barra lateral do tema padrão e no menu superior dos outros temas. A busca aceita nome ou assunto; o catálogo pode ser selecionado por país. Esse país é independente do filtro das rádios e começa com o primeiro país configurado no app.

## Descobrir e ouvir

- A descoberta usa a [iTunes Search API da Apple](https://performance-partners.apple.com/search-api), sem conta ou chave individual. Até 24 programas são apresentados por busca.
- Escolha um programa para consultar seu RSS, ver capa, descrição e episódios e iniciar a reprodução. A ordem é da publicação mais recente para a mais antiga, quando o feed informa datas.
- O coração guarda o programa em **Favoritos**, separados das rádios. **Continuar** recupera o último episódio e sua posição, inclusive após reabrir o app.
- **Adicionar RSS** aceita o endereço direto de um feed HTTP(S), incluindo feeds fora do diretório. Links de páginas de programas não substituem o RSS.
- O filtro de idioma consulta a declaração de idioma dos feeds, com até quatro consultas simultâneas. Sem declaração ou quando o feed não está acessível, o programa não aparece no filtro específico. Sem filtro, o catálogo não impõe idioma.

O player principal e o miniplayer compartilham o episódio ativo. Os botões anterior/próximo se tornam voltar/avançar 15 segundos durante um podcast. A tela Podcasts oferece posição e duração e uma barra para buscar um ponto do episódio. A busca pausada não inicia a reprodução. O sistema também recebe duração, posição e comandos de busca quando há um podcast ativo.

A posição é salva aproximadamente a cada cinco segundos e ao pausar, buscar uma posição, mudar a fonte ou encerrar normalmente. Ao terminar, o episódio é marcado como concluído e uma nova reprodução começa do início. Não há avanço automático para uma rádio. Uma automação de rádio continua podendo substituir o episódio, salvando sua posição antes da troca.

## Formatos e limites

O leitor aceita RSS 2.0 e Atom com enclosures de áudio HTTP(S), conforme a [especificação RSS](https://www.rssboard.org/rss-specification). Durações em segundos ou HH:MM:SS, datas RSS/ISO e URLs relativas são interpretadas. GUID é preferido para identificar episódios; sem GUID, usa-se o endereço do áudio. Redirecionamentos do feed mantêm a identidade da assinatura. Se o autor mudar o GUID ou o endereço de um episódio sem GUID, ele pode ser reconhecido como um episódio novo.

Até 500 episódios por feed e feeds de até 20 MB são aceitos. HTML das descrições é exibido como texto. Declarações de entidades XML são rejeitadas; recursos externos de XML não são carregados. A reprodução depende do formato suportado pelo AVFoundation e da disponibilidade do servidor do autor. Conteúdo exclusivo sem RSS acessível não é incluído. Esta versão não faz download para ouvir offline.

Favoritos, último episódio e até 500 registros recentes de progresso ficam em UserDefaults, no dispositivo. Não são incluídos no repositório ou na instalação. URLs de feeds privados podem conter tokens e ficam nas preferências locais; não compartilhe exports dessas preferências. Os autores recebem as conexões de RSS, capas e áudio; a Apple recebe a busca e o país de catálogo.

A interface oferece português e inglês. Essa implementação pertence ao app nativo macOS; a edição Flutter e o Android antigo não foram alterados.

## Verificação

O build executa testes locais de RSS/Atom, enclosures, deduplicação, GUID, redirecionamentos, texto seguro, persistência independente das rádios e conclusão de episódios. Com o binário de desenvolvimento:

- `--verify-podcast-playback`: reproduz um WAV temporário silencioso para verificar retomada, seek, pausa, controles de 15 segundos e término real.
- `--verify-podcast-network`: verifica uma busca pública e a leitura de um RSS real, sem reproduzir seu áudio.
- `--render-previews --podcasts-preview`: gera imagens com programas fictícios; adicione `--podcast-episodes-preview` para a tela de episódios e `--english-preview` para inglês.
