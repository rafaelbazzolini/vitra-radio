# Releases, branches e assinatura

## Branches

`main` é a origem das releases estáveis. `dev` é a integração de desenvolvimento. Abra um PR de dev para main, aguarde CI e revise. Commits em dev não disparam avisos de versão aos usuários.

A workflow `Release main` usa `0.1.<run_number>`, testa, compila e publica os arquivos em um tag imutável apontando ao commit do push. Apenas a etapa final tem permissão de escrita. As outras só leem o repositório. Uma falha impede a publicação daquela release; consulte Actions.

## Android

A chave de assinatura precisa ser a mesma para que versões futuras substituam as anteriores. Secrets:

- `ANDROID_KEYSTORE_BASE64`: keystore JKS codificado em base64, alias `vitra`.
- `ANDROID_KEYSTORE_PASSWORD`: senha usada tanto para o keystore quanto para o alias.

O CI recompõe a chave apenas no runner. Não use a chave de debug em releases públicas. Guarde uma cópia privada segura da chave; perder a chave impede atualizar APKs já instalados com ela. A geração inicial local usa arquivos dentro de `.build/`, ignorados pelo Git.

## macOS

O release contém um app universal arm64/x86_64 assinado ad hoc. Para distribuir com identidade verificada e notarização, forneça um certificado Developer ID, acesso à equipe Apple e credenciais próprias de notarização; ainda não estão configurados. Nenhuma configuração pessoal é empacotada no `.app`.

## iOS

O job sem assinatura comprova que compila e produz um `.app` de dispositivo. **Não é uma release instalável no iPhone.** Não renomeie o ZIP como IPA para simular uma distribuição.

Para a distribuição real:

1. Tenha uma equipe Apple Developer e registre o bundle ID do Runner.
2. Configure certificado e provisioning profile próprios, ou assinatura gerenciada no Xcode.
3. Execute `flutter build ipa --release --export-options-plist=...` com opções da equipe.
4. Envie para TestFlight/App Store e configure o link dessa distribuição no cliente.
5. Mantenha certificados, profiles e App Store Connect keys fora do Git, em secrets privados.

Sem esses dados, o pipeline publica somente o produto **UNSIGNED-NOT-INSTALLABLE**, e o projeto declara a limitação em vez de anunciar um instalador inexistente.

## Windows e Linux

Windows usa um ZIP portátil x64 completo; não há assinatura Authenticode ainda. Linux usa um TAR de bundle x64 e depende de GTK/libmpv do sistema. A workflow não afirma cobertura de ARM Linux/Windows.

## Atualização nos dispositivos

Os clientes só consultam releases estáveis do repositório oficial. Não usam tags de dev nem instalam executáveis por conta própria. Permissões de notificação são opcionais. A consulta não ocorre com o processo encerrado. Para iOS distribuído por loja, a atualização precisa seguir o mecanismo de TestFlight/App Store.
