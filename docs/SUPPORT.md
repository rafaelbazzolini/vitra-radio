# Apoio voluntário ao Vitra Radio

O botão **Apoiar** abre uma tela de contribuição voluntária. Não há pagamento obrigatório nem coleta de dados financeiros dentro do app.

## Configurar o destino

1. Crie ou escolha uma página de recebimento própria.
2. Confirme o destinatário e o funcionamento do link.
3. Defina a URL HTTPS pública em [`packaging/support.json`](../packaging/support.json):

```json
{
  "donationURL": "https://seu-dominio.example/apoie"
}
```

4. Gere uma nova versão. O arquivo é incluído nos recursos assinados do app nativo.

O valor inicial é `null`: não aponta para contas presumidas e não oferece cobrança enquanto o mantenedor não confirmar o destino. Não inclua senhas, tokens ou chaves privadas nesse arquivo. Não há um campo para usuários finais trocarem o destinatário das doações do projeto.

## Opções de recebimento

- **Ko-fi:** página simples de contribuições, com recebimento pelo PayPal ou Stripe; depende da configuração da conta do mantenedor. Consulte [formas de recebimento](https://help.ko-fi.com/hc/en-us/articles/115003980093-How-do-I-get-paid) e [taxas atuais](https://help.ko-fi.com/hc/en-us/articles/360002506494-Does-Ko-fi-take-a-fee).
- **Pix:** pode ser disponibilizado em uma página HTTPS própria com QR Code/copia e cola, usando uma chave pública que o mantenedor escolha divulgar. O app não deve publicar uma chave ou nome de recebedor sem confirmação.
- **GitHub Sponsors:** opção para apoiar código aberto; requer habilitar o perfil e configurar o recebimento. Veja a [documentação oficial](https://docs.github.com/en/sponsors/getting-started-with-github-sponsors/about-github-sponsors).

O app não faz pagamentos em nome do usuário. A pessoa escolhe o valor e confirma diretamente no provedor.
