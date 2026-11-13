# Música online e playlists

Em **Minhas Músicas**, as abas **Sua biblioteca**, **Descobrir músicas** e **Minhas playlists** mantêm as pastas e os servidores existentes e acrescentam catálogos online.

## Buscar e ouvir

- Escolha **Internet Archive** ou **Jamendo**, um campo de pesquisa e, opcionalmente, uma categoria musical. Os filtros de texto e categoria são combinados.
- Internet Archive pesquisa registros de música e álbuns das coleções de música ao vivo, netlabels, música e discos históricos. Abra um resultado para ver suas faixas. Títulos, artistas e compositores dependem dos metadados publicados; o título pesquisado pode ser de uma faixa ou de um álbum. Um compositor pode não estar indexado, mesmo quando a gravação existe.
- Jamendo oferece busca por texto livre, título, artista e categorias. A API não possui um campo específico para compositor, por isso essa opção não é exibida nessa fonte.
- Use **Ouvir** para reproduzir no player existente. As URLs de streaming são consultadas novamente ao iniciar cada faixa. Uma faixa removida ou restrita gera um aviso; o app não contorna restrições nem substitui a música silenciosamente.
- **Ver na fonte** e **Licença** permitem conferir a origem e as informações publicadas. O app não afirma que todo item do Archive está em domínio público.

Não há botões de download, exportação de áudio ou funcionamento offline. São persistidos apenas identificadores e metadados necessários às playlists; buffers normais de reprodução são gerenciados pelo player e pelo sistema.

## Playlists

Crie playlists, adicione músicas das duas fontes pelo menu da faixa, renomeie e exclua listas, reordene listas e faixas com **Mover para cima/baixo**, e remova músicas individualmente. **Ouvir playlist** inicia a fila na ordem definida; o avanço automático para no fim. Os controles anterior/próxima também funcionam nessa fila.

As playlists ficam no dispositivo, sem conta, sincronização ou publicação nos serviços. Adicionar uma faixa não altera rádios favoritas, podcasts ou bibliotecas de pastas/servidores. Limites: 100 playlists, 500 faixas por playlist e 120 caracteres por nome. A mesma faixa não é adicionada duas vezes na mesma lista.

## Configurar Jamendo

É necessário registrar um aplicativo no [portal Jamendo](https://devportal.jamendo.com/) e obter um Client ID apropriado. Nenhum identificador de demonstração é incluído no app. Sem esse identificador, o Internet Archive e as playlists continuam disponíveis; a interface informa o requisito para usar Jamendo.

O mantenedor pode fornecer o identificador durante o build:

- macOS: variável `VITRA_JAMENDO_CLIENT_ID` ao executar `scripts/build.sh`; o valor é incluído no Info.plist do app gerado.
- Flutter: `--dart-define=JAMENDO_CLIENT_ID=...` no build.

Para testes de uma instalação, **Descobrir músicas → Jamendo → Conexão Jamendo** permite informar o Client ID localmente. Uma configuração local salva prevalece sobre a configuração do build. Não é solicitada senha do usuário nem client secret. As playlists são próprias do Vitra, não dependem de OAuth de escrita no Jamendo.

## Verificações

- `--self-test` no macOS cobre parsing, filtragem de arquivos privados/restritos, persistência e organização de playlists.
- `--verify-online-music` consulta o Internet Archive, abre um item, resolve um stream e recebe um trecho em memória, sem salvar arquivos de música nem alterar preferências reais.
- Os testes Flutter cobrem filtros, paginação, escape de consulta, URLs, listas mistas, duplicatas, persistência, fila, respostas atrasadas, troca de fonte e layout em telas pequenas com fonte ampliada.

## Documentação dos serviços

- [Jamendo: pesquisa de faixas](https://developer.jamendo.com/v3.0/tracks)
- [Jamendo: autenticação de aplicativo](https://developer.jamendo.com/v3.0/authentication)
- [Internet Archive: pesquisa avançada](https://archive.org/advancedsearch.php)
- [Internet Archive: metadados e arquivos](https://archive.org/developers/md-read.html)
