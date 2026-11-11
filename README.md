# Vitra Radio

[![Release main](https://github.com/rafaelbazzolini/vitra-radio/actions/workflows/release.yml/badge.svg)](https://github.com/rafaelbazzolini/vitra-radio/actions/workflows/release.yml)
[![Validate](https://github.com/rafaelbazzolini/vitra-radio/actions/workflows/ci.yml/badge.svg)](https://github.com/rafaelbazzolini/vitra-radio/actions/workflows/ci.yml)

**O seu dia tem trilha.** Um player de rádio pela internet com temas visuais, favoritas, histórico e programação de horários.

[Baixar versões](https://github.com/rafaelbazzolini/vitra-radio/releases/latest) · [Builds](https://github.com/rafaelbazzolini/vitra-radio/actions) · [Privacidade](docs/PRIVACY.md) · [Como contribuir](CONTRIBUTING.md)

> O repositório contém um app nativo de macOS e uma edição compartilhada em Flutter. A matriz abaixo distingue os recursos de cada edição. Builds só são anunciados como disponíveis quando a workflow da release termina. O build iOS sem assinatura não pode ser instalado em um iPhone.

## Telas

As imagens usam **emissoras fictícias**, somente para demonstração. Não representam rádios pré-carregadas nem dados pessoais.

![Vitra Padrão: início e favoritas](docs/images/home.png)
![Heritage: receptor com acabamento de rádio e medidores](docs/images/heritage.png)
![Signal 90: tema digital](docs/images/signal.png)
![Automação: programação semanal ou por data específica](docs/images/automation.png)

## Instalação

Escolha o arquivo da sua plataforma em [Releases](https://github.com/rafaelbazzolini/vitra-radio/releases).

| Sistema | Produto | Requisitos e observações |
|---|---|---|
| macOS Apple Silicon / Intel | App nativo universal, `.zip` e `.dmg` | macOS 13+. Liquid Glass depende do sistema. Sem notarização Developer ID por enquanto. |
| Windows 11 | ZIP x64 | Extraia todos os arquivos antes de executar; sem assinatura Authenticode. |
| Linux | TAR x64 | GTK 3 e libmpv; Ubuntu 24.04 é a referência de CI. |
| Android | APK assinado e AAB | APK instalável; distribuição por loja ainda não configurada. |
| iOS | Build de dispositivo sem assinatura | **Não instalável.** Requer Apple Developer para assinar e publicar em TestFlight/App Store. |

A release inclui `SHA256SUMS.txt`. Preserve a pasta inteira dos aplicativos de desktop.

## Começar a ouvir

1. Abra **Todas as rádios** e pesquise no catálogo Radio Browser, ou adicione a URL direta de um stream.
2. Use o coração para montar suas favoritas. **Início** alterna entre **Favoritas** e **Recentes**.
3. Escolha um tema para mudar a aparência.
4. Em **Automação**, defina rádio, dias ou uma data completa, início e término.

**A instalação começa vazia:** não há rádios, servidores, credenciais, favoritas ou programações pessoais embutidas. Nenhuma conta do Vitra é necessária. Dados da biblioteca ficam no dispositivo.

## Recursos por edição

| Recurso | Nativo macOS (`Sources/`) | Compartilhado Flutter (`cross_platform/`) |
|---|---|---|
| Catálogo Radio Browser e stream por URL | Sim | Sim |
| Favoritas e recentes locais | Sim | Sim |
| Temas | Layouts próprios: Vitra, Receiver, Studio, Heritage, Signal 90 | Paletas e estilos adaptados à tela |
| Programação semanal e data específica | Sim, com retomada ao acordar | Sim, enquanto o processo estiver ativo |
| Intervalos sobrepostos e prioridade por data | Sim | Sim |
| Mini player flutuante redimensionável / barra de menus | Sim | Ainda não |
| VU Digital, Moderno e Analógico | Medição real; espectro de oito bandas por canal | Ainda não |
| Equilíbrio automático de volume | Sim | Ainda não |
| Navidrome/Subsonic, Jellyfin e pastas locais | Sim; credenciais no Keychain | URL direta acessível por rede local/Tailscale |
| Avisos de atualização | Sim | Sim, notificações do sistema com permissão |

### Automação

O app usa horário e fuso locais. Um período que começa depois assume a reprodução e, quando termina, retoma o anterior se ele ainda estiver vigente. Para o mesmo início, a faixa mais curta vem primeiro. Uma regra com **data específica** tem prioridade sobre semanais e executa somente naquela data; ela não se repete mensalmente. Dois períodos idênticos para os mesmos dias ou data são rejeitados.

Fechar a janela do app nativo mantém o áudio e a barra de menus. **Encerrar**, **⌘Q**, logout, desligamento e reinício podem finalizar o aplicativo. A automação não liga o computador, não abre sozinha o app e não garante execução em aparelhos suspensos. Android e iOS podem suspender processos em segundo plano; não use esta versão como despertador garantido.

### VU e áudio nativo

O Digital separa oito bandas reais (63, 125, 250, 500 Hz, 1, 2, 4 e 8 kHz), com canais L/R independentes e colunas fixas. Moderno e Analógico mostram o nível geral do canal. Não há valores aleatórios. HLS com processamento de áudio exige macOS 27; streams compatíveis podem usar o tap por faixa em sistemas anteriores. A medição não altera o volume do sistema.

### Atualizações a partir de `main`

- `dev` recebe trabalho em andamento; pull requests passam pelas verificações.
- Cada push em `main` dispara builds e publica uma release versionada **somente quando todos os jobs exigidos passam**.
- Apps consultam a última release estável, comparam versões numericamente e mostram um aviso.
- A consulta ocorre ao iniciar e a cada hora enquanto o processo estiver ativo; a edição Flutter também consulta ao retornar ao primeiro plano.
- Notificações do sistema precisam ser habilitadas no app e permitidas pelo usuário. Há também indicação dentro do aplicativo.
- O usuário abre a página da release e instala a atualização. Não há execução de código remoto, alteração silenciosa do app ou substituição pela branch bruta.
- No iOS, novas versões instaláveis devem ser distribuídas por TestFlight/App Store com assinatura adequada. Não existe atualização arbitrária de executáveis pela branch.

Veja [releases e assinatura](docs/RELEASING.md) para configurar chaves e distribuição. Não prometemos avisos com o aplicativo totalmente encerrado: isso exigiria serviços de push/loja ou integração de background própria de cada sistema.

## Desenvolvimento

### macOS nativo

Xcode com SDK macOS 26 ou posterior; Swift 5.9+.

```sh
bash scripts/build.sh
open 'dist/Vitra Radio.app'
```

```sh
'dist/Vitra Radio.app/Contents/MacOS/VitraRadio' --self-test
'dist/Vitra Radio.app/Contents/MacOS/VitraRadio' --verify-audio-balance
'dist/Vitra Radio.app/Contents/MacOS/VitraRadio' --verify-mini
```

Os testes usam preferências separadas. Os testes de DSP processam PCM real pelo AVAssetReader, sem afirmar que ouviram som no alto-falante. As capturas `--render-previews` usam dados fictícios.

### Edição compartilhada

Flutter **3.44.2**, Dart **3.12.2**; dependências fixadas em `pubspec.lock`.

```sh
cd cross_platform
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

Builds: `flutter build windows`, `flutter build linux`, `flutter build apk`, `flutter build appbundle` e `flutter build ios --release --no-codesign`. Desktop exige o host correspondente. O APK de release exige `android/key.properties` com uma chave privada local; esse arquivo nunca é versionado. Consulte o guia de release antes de distribuir.

## Estrutura

```text
Sources/VitraRadio/       # App nativo SwiftUI/AppKit/AVFoundation
cross_platform/          # App Flutter para desktop e mobile
scripts/                 # Build, geração de ícone e verificação de conteúdo público
docs/                    # Privacidade, arquitetura, screenshots e distribuição
.github/workflows/       # CI de dev/PRs e release de main
packaging/               # Metadados públicos do app macOS
```

## Privacidade, limites e licenças

Não versionamos preferências, senhas, tokens, histórico ou bibliotecas pessoais. Credenciais do app nativo são guardadas no Keychain. O catálogo externo e os próprios streams recebem a conexão necessária à reprodução. Veja [Privacidade](docs/PRIVACY.md).

A disponibilidade e os direitos das transmissões pertencem às emissoras. Não hospedamos áudio nem fornecemos acesso a conteúdo restrito. Respeite licenças e regras dos streams que adicionar. O código do Vitra Radio usa [MIT](LICENSE); bibliotecas e codecs mantêm suas próprias licenças, detalhadas em [terceiros](docs/THIRD_PARTY.md).
