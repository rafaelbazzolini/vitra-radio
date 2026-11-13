## Vitra Radio — canal main

Esta versão é gerada do commit de `main` indicado na release, após as verificações e builds.

### Novidades da versão 0.1.11

- Filtros Treino, Trabalho e Meditação no catálogo, com sugestões internacionais e categorias personalizadas salvas no dispositivo.
- Início reúne favoritas e recentes de rádios e podcasts; episódios recentes retomam do ponto salvo.
- Android com navegação, países, idioma, podcasts, bibliotecas locais e servidores alinhados à versão Mac.

### Novidades no macOS

- País sugerido na primeira abertura e seleção de vários países, com resultados misturados e paginação por país.
- Correção do redesenho do VU no miniplayer e botão Apoiar, com destino de doação configurável pelo mantenedor.

- Verificação de atualizações ao abrir e uma vez a cada 24 horas, com opções independentes em Ajustes → Atualizações. A busca manual continua disponível.
- Aviso dentro do app e botão Atualizar e reiniciar: baixa, valida e substitui a instalação sem abrir DMG, preservando as preferências.

- Ajustes reúne Idioma e região, Temas, Automação, Miniplayer e Atualizações em abas.
- Minhas Músicas fica ao lado de Podcasts em todos os temas, mesmo sem biblioteca configurada. Adicionar oferece duas abas: Pasta deste dispositivo e Servidor de música (Navidrome/Subsonic, Jellyfin ou pasta compartilhada na rede).
- O miniplayer pode exibir VU Digital ou Analógico atrás do nome da rádio, usando níveis reais do áudio e transparência para manter a leitura.
- Aparência, largura, altura e posição sobre outras janelas podem ser configuradas em Ajustes → Miniplayer.

### Android

- Opções independentes em Ajustes para verificar ao abrir e automaticamente a cada 24 horas, persistidas entre sessões.
- Aviso dentro do app e acesso direto ao APK oficial quando ele está disponível na release. A instalação continua sujeita à confirmação do Android.
- Notificações do sistema são opcionais; não há promessa de verificações com o processo encerrado.
- Navegação alinhada ao Mac: Início, Todas as rádios, Podcasts, Minhas Músicas e Ajustes.
- Idioma pt-BR/en e seleção de vários países na primeira abertura e nos Ajustes.
- Busca do catálogo com paginação, preservação de acentos e alternativa de servidor em caso de indisponibilidade.
- Podcasts com busca, RSS, favoritos, episódios e retomada.
- Minhas Músicas com pastas locais pelo seletor Android, Navidrome/Subsonic e Jellyfin; credenciais protegidas pelo sistema.
- Player inferior adaptado a retrato, paisagem e nomes longos. Recursos de janela flutuante, barra de menus, VU e normalização nativos do Mac ainda não estão disponíveis nesta edição.

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
