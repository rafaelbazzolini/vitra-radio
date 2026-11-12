# Idiomas da interface nativa

O app macOS oferece Português (Brasil), identificador `pt-BR`, e English, identificador `en`. Na primeira abertura, o idioma é sugerido a partir das preferências locais do sistema. O usuário confirma ou altera essa escolha junto dos países. Depois, **Ajustes → Idioma e região** permite trocar imediatamente, sem reiniciar a reprodução.

A preferência `interfaceLanguage` fica somente em UserDefaults. Países, nomes de rádios, favoritos, perfis de servidor e programações mantêm seus identificadores e dados. Mudar idioma não altera o filtro de países nem reabre o onboarding já concluído. Português não brasileiro é reconhecido; sistemas sem idioma suportado usam português como fallback.

## Manutenção

- [AppLocalization.swift](../Sources/VitraRadio/AppLocalization.swift) contém os idiomas, persistência e tradução nas fronteiras da interface. Os textos em português são a fonte e o fallback.
- [en.json](../packaging/Languages/en.json) contém as traduções inglesas embarcadas. Não há tradução remota ou dependência de rede.
- Use `L10n.tr("Texto")` para texto da interface. Para interpolação, use `L10n.tr("Ouvir \(station.name)")`; o catálogo usa a chave `Ouvir %@`. Preserve a quantidade e a ordem dos placeholders. Os valores interpolados não passam por tradução.
- Valores de enums usados em persistência não devem ser traduzidos; traduza somente seu rótulo na apresentação. Nomes próprios e conteúdo informado pelo usuário permanecem originais.
- Views com rótulos observam `AppLocalization.shared`; controles de data e país recebem a localidade selecionada. Menus AppKit são reconstruídos na troca de idioma, mantendo suas ações e atalhos.
- [build.sh](../scripts/build.sh) copia o catálogo para `Contents/Resources/Languages` antes de assinar. `--self-test` verifica a presença do recurso, interpolações, persistência e independência entre idioma e biblioteca.

Para verificar a troca ao vivo na interface nativa, execute o binário de desenvolvimento com `--verify-language`. O teste usa preferências isoladas, verifica menus e controles nos dois idiomas e compara imagens da janela, sem alterar o aplicativo instalado. `--render-previews --english-preview --onboarding-preview` gera exemplos da primeira abertura em inglês com rádios fictícias. Adicione `--settings-preview --countries-preview` para visualizar Idioma e região.

Esta implementação pertence à edição nativa macOS. A edição Flutter ainda não oferece o seletor.
