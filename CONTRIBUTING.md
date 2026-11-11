# Contribuir

Use `dev` como base de trabalho e envie PRs com descrição do comportamento e validação. Mudanças que vão para main geram builds de release; confirme a matriz de plataformas antes do merge.

- Não envie rádios, bibliotecas, credenciais ou automações pessoais.
- Use fixtures fictícias em testes e screenshots.
- Rode `bash scripts/build.sh` para o nativo e `flutter analyze && flutter test` em `cross_platform/`.
- Mudanças de DSP devem rodar `--verify-audio-balance`.
- Atualize a matriz de recursos quando houver diferença entre as duas edições.
- Não anuncie builds assinados ou instalações em dispositivos sem evidência de distribuição válida.

A licença das contribuições é MIT, salvo arquivos de terceiros explicitamente identificados.
