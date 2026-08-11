# Aşama 9 — Workflow'ları Üretim İçin Etkinleştirme

## Amaç

Test edilmiş iki workflow'u doğru adlarla açık bırakmak ve aynı olaya çift mesaj
gönderebilecek eski taslakları kapatmak.

## 9.1 Workflow adlarını düzenleme

Import sonrasında adlardaki `(JSON)` ifadesi kaldırılabilir. Son adlar:

```text
Cross-Monitoring Incident → Telegram
Cross-Monitoring Recovery → Telegram
```

## 9.2 Yalnızca doğrulanmış workflow'ları açık bırakma

Workflows listesinde beklenen durum:

| Workflow | Durum |
|---|---|
| `Cross-Monitoring Incident → Telegram` | Açık / Enabled |
| `Cross-Monitoring Recovery → Telegram` | Açık / Enabled |

Daha önce Builder'da elle hazırlanmış eski veya eksik workflow varsa
`Disabled/Kapalı` bırakın ya da artık gerekmediğinden emin olduktan sonra ayrıca
temizleyin. Aynı trigger'a bağlı iki aktif kopya, Telegram'a yinelenen mesajlar
gönderebilir.

> **Ekran görüntüsü önerisi:** Workflows listesinde doğru adlarla yalnızca iki
> workflow'un `Açık` görünmesi. Buraya `09-workflows-enabled.png` resmini
> koyabilirsin. Bu, Aşama 9 için ana kanıt görselidir.

## 9.3 Son log kontrolü

Runs & Logs altında aşağıdaki iki başarılı çalışmayı doğrulayın:

- Incident oluşturma testi → `Success`
- Incident çözülme testi → `Success`

Log ayrıntılarında secret Global Variable değerleri açık biçimde
görünmemelidir.

## 9.4 Mimari sınır

Bu iki workflow OneUptime Core çalışırken bildirim gönderir. Node 1'deki
`oneuptime-app` tamamen kapandığında:

- Probe sonuçları Core'a iletilemeyebilir.
- Incident oluşturma veya güncelleme gerçekleşmeyebilir.
- Workflow motoru çalışamayabilir.
- Telegram component'i çağrılamayabilir.

Bu nedenle Core'un kendisini izlemek için Node 2 üzerinde OneUptime'dan bağımsız
bir watchdog gerekir.

## Kabul kontrolü

- [ ] İki workflow doğru adlarla açık.
- [ ] Eski/taslak workflow'lar kapalı.
- [ ] Incident test run sonucu başarılı.
- [ ] Recovery test run sonucu başarılı.
- [ ] Telegram'a yinelenen mesaj gelmiyor.
- [ ] Workflow içinde hardcoded credential yok.

Sonraki adım:
[Aşama 10 — Node 1 watchdog kurulumu](10-node1-watchdog-kurulumu.md).
