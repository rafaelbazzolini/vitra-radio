# Privacidade

A distribuição pública inicia sem rádios, favoritas, histórico, automações, servidores, senhas ou contas pessoais.

## Dados locais

- macOS nativo: preferências e biblioteca em UserDefaults; credenciais de servidores no Keychain.
- Edição Flutter: biblioteca, favoritos, recentes, horários e preferências em SharedPreferences. Não é armazenamento criptografado; não coloque segredos em URLs de streams.
- O app não envia a biblioteca a um backend próprio. Não há conta Vitra, analytics ou publicidade próprios.

## Conexões externas

- Radio Browser recebe termos de pesquisa e parâmetros do catálogo.
- A emissora/servidor recebe a conexão de áudio, incluindo IP e dados normais de rede.
- GitHub recebe consultas de versões (`/releases/latest`) e downloads que o usuário solicitar.
- Tailscale é configurado pelo usuário no sistema; o Vitra apenas usa uma URL alcançável. O projeto não recebe credenciais de Tailscale.

## Notificações e atualizações

No macOS nativo, o aviso de atualização aparece dentro do app e não requer permissão de notificações do sistema. Ao clicar em Atualizar e reiniciar, o usuário autoriza baixar e validar o pacote da release oficial e substituir a instalação. A operação preserva preferências e credenciais. A edição compartilhada mantém notificações opcionais que dependem da permissão do sistema. O app verifica versões enquanto está aberto/ativo; não existe um serviço de push que acompanhe dispositivos encerrados.

## Remover dados

Desinstalar pode não apagar preferências e Keychain automaticamente, conforme o sistema. Remova dados nas configurações de armazenamento do app ou nas preferências/Keychain correspondentes. A exclusão local não afeta a emissora ou o diretório externo.

## Repositório

Builds, caches, keystores, `.env`, perfis de provisionamento e configurações locais estão no `.gitignore`. Os screenshots são gerados com emissoras fictícias em domínio reservado `example.invalid`. Não copie exports de preferências para issues ou commits.
