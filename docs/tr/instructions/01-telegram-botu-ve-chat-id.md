# Aşama 1 — Telegram Botu ve Chat ID Hazırlama

## Amaç

Bu aşamanın sonunda aşağıdaki iki değer güvenli biçimde elde edilmiş olur:

- Telegram Bot API token'ı
- Bildirimlerin gönderileceği kişisel sohbetin Chat ID değeri

Bu değerler parola gibi korunmalı ve dokümana yazılmamalıdır. Telegram'ın resmî
dokümantasyonuna göre bot, kullanıcıyla kendiliğinden sohbet başlatamaz; kullanıcının
önce botla iletişim kurması gerekir. Ayrıntılar için [Telegram bot
tanıtımı](https://core.telegram.org/bots) ve [BotFather
eğitimi](https://core.telegram.org/bots/tutorial) kullanılabilir.

## 1.1 BotFather üzerinden bot oluşturma

1. Telegram uygulamasında doğrulanmış `@BotFather` hesabını açın.
2. `/newbot` komutunu gönderin.
3. Bot için görünen bir ad belirleyin.
4. BotFather'ın istediği benzersiz kullanıcı adını belirleyin. Kullanıcı adı
   genellikle `bot` ile biter.
5. BotFather'ın ürettiği token'ı güvenli bir parola yöneticisine kaydedin.
6. Token'ı Markdown dosyasına, ekran görüntüsüne, terminal geçmişine veya Git'e
   eklemeyin.

> **Ekran görüntüsü eklenecek:** BotFather'da `/newbot` komutunun gönderildiği ve
> botun başarıyla oluşturulduğu ekran. Token satırı tamamen kapatılmalıdır.
> Önerilen dosya: `images/01-botfather-bot-created.png`

## 1.2 Botla kişisel sohbeti başlatma

1. BotFather'ın verdiği bot bağlantısını açın.
2. **Start** düğmesine basın veya `/start` mesajı gönderin.
3. Chat ID sorgulanmadan önce bot sohbetinde en az bir mesaj bulunduğunu
   doğrulayın.

> **Ekran görüntüsü eklenecek:** Yeni botla açılan kişisel sohbet ve gönderilmiş
> `/start` mesajı. Kişisel kullanıcı adı gerekiyorsa bulanıklaştırılmalıdır.
> Önerilen dosya: `images/01-telegram-bot-start.png`

## 1.3 Chat ID değerini bulma

Token'ı komut satırına açıkça yazmak yerine geçici ve gizli bir kabuk değişkenine
alın:

```bash
read -s "TELEGRAM_BOT_TOKEN?Telegram bot token: " TELEGRAM_BOT_TOKEN
echo
curl -sS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates"
unset TELEGRAM_BOT_TOKEN
```

Dönen JSON içinde kişisel sohbet mesajına ait aşağıdaki alanı bulun:

```text
result[] → message → chat → id
```

Bu sayısal değer kişisel sohbetin Chat ID değeridir. `result` dizisi boşsa bota
yeniden bir mesaj gönderip komutu tekrar çalıştırın. `getUpdates` metodunun gelen
güncellemeleri döndürme davranışı [Telegram Bot API
dokümantasyonunda](https://core.telegram.org/bots/api#getupdates) açıklanır.

Beklenen yanıt yapısı aşağıdaki gibidir. Gerçek değerler yerine yer tutucular
kullanılmıştır:

```text
{
  "ok": true,
  "result": [
    {
      "message": {
        "chat": {
          "id": <TELEGRAM_CHAT_ID>,
          "type": "private"
        },
        "text": "/start"
      }
    }
  ]
}
```

> **Ekran görüntüsü eklenecek:** `getUpdates` yanıtının yapısı ve
> `message.chat.id` alanının konumu. Token içeren URL, gerçek Chat ID ve kişisel
> bilgiler tamamen kapatılmalıdır.
> Önerilen dosya: `images/01-getupdates-chat-id.png`

## 1.4 Telegram gönderimini test etme

Değerleri yeniden gizli geçici değişkenlere alın:

```bash
read -s "TELEGRAM_BOT_TOKEN?Telegram bot token: " TELEGRAM_BOT_TOKEN
echo
read -s "TELEGRAM_CHAT_ID?Telegram Chat ID: " TELEGRAM_CHAT_ID
echo

curl -sS --request POST \
  --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
  --data-urlencode "text=OneUptime Telegram bağlantı testi başarılı." \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID
```

Telegram sohbetine test mesajı ulaştığında bağlantı hazırdır.

Başarılı isteğin beklenen, hassas değerleri çıkarılmış yanıt yapısı:

```text
{
  "ok": true,
  "result": {
    "message_id": <MESSAGE_ID>,
    "chat": {
      "id": <TELEGRAM_CHAT_ID>,
      "type": "private"
    },
    "text": "OneUptime Telegram bağlantı testi başarılı."
  }
}
```

> **Ekran görüntüsü eklenecek:** Bot sohbetindeki bağlantı testi mesajı. Ekranda
> token veya Chat ID bulunmamalıdır.
> Önerilen dosya: `images/01-telegram-test-message.png`

## Kabul kontrolü

- [ ] Projeye özel bot oluşturuldu.
- [ ] Botla kişisel sohbet başlatıldı ve `/start` gönderildi.
- [ ] Kişisel Chat ID bulundu.
- [ ] Test mesajı Telegram'a ulaştı.
- [ ] Token ve Chat ID hiçbir dosyaya veya ekran görüntüsüne eklenmedi.

Bu kontroller tamamlandıktan sonra
[Aşama 2 — OneUptime Global Variables](02-oneuptime-global-variables.md)
uygulanır.
