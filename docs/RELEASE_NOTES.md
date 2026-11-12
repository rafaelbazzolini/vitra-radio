## Vitra Radio — canal main

Esta versão é gerada do commit de `main` indicado na release, após as verificações e builds.

### Novidades no macOS

- País sugerido na primeira abertura e seleção de vários países, com resultados misturados e paginação por país.
- Correção do redesenho do VU no miniplayer e botão Apoiar, com destino de doação configurável pelo mantenedor.

- Aviso dentro do app e botão Atualizar e reiniciar: baixa, valida e substitui a instalação sem abrir DMG, preservando as preferências.

- Ajustes reúne Servidor, Temas, Automação e Miniplayer em abas.
- Minhas músicas aparece na navegação após uma conexão bem-sucedida com o servidor.
- O miniplayer pode exibir VU Digital ou Analógico atrás do nome da rádio, usando níveis reais do áudio e transparência para manter a leitura.
- Aparência, largura, altura e posição sobre outras janelas podem ser configuradas em Ajustes → Miniplayer.

### Downloads

- **macOS Apple Silicon e Intel:** ZIP e DMG universais do app nativo. Assinatura ad hoc; ainda sem notarização Developer ID.
- **Windows 11 x64:** extraia o ZIP inteiro e execute `vitra_radio.exe`. Inclui DLLs necessárias; sem assinatura Authenticode.
- **Linux x64:** extraia o TAR e execute `vitra_radio`. Requer GTK 3 e libmpv (`sudo apt install libgtk-3-0 libmpv2` em Ubuntu 24.04).
- **Android:** APK assinado com uma chave de release persistente. AAB para publicação futura no Google Play.
- **iOS:** o ZIP `UNSIGNED-NOT-INSTALLABLE` é um produto de compilação para desenvolvedores. **Não é um IPA instalável.** Distribuição real requer assinatura Apple e TestFlight/App Store.

A edição compartilhada tem catálogo, streams por URL, favoritas, recentes, temas, programação e avisos de atualização. Os recursos avançados de mini player, VU de oito bandas e servidores Navidrome/Jellyfin completos estão no app nativo de macOS. Consulte a matriz de recursos no README.

Instalação nova não inclui rádios pessoais, histórico, favoritas, servidores ou automações do desenvolvedor.
Os avisos de versão funcionam ao abrir o app e enquanto o processo está ativo. No macOS nativo, aparecem dentro do app: o usuário pode atualizar e reiniciar pela própria janela, sem reinstalação manual. A edição compartilhada mantém os avisos do sistema com permissão e o download manual. iOS usa a distribuição permitida pela Apple.

Confira os hashes dos arquivos em `SHA256SUMS.txt`. A instalação continua dependendo das políticas de segurança de cada sistema.
