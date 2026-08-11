# Numaralı Ekran Görüntüsü İndeksi

Bu dizin, `docs/instructions/` altındaki talimatlarda kullanılan numaralı ekran
görüntülerini içerir. Görsel numaraları, dokümantasyondaki şekil numaralarıyla
aynıdır.

## Güvenlik kontrolü

Bir görseli bu dizine eklemeden önce:

- Bot token'ını tamamen kapatın; birkaç karakterini açık bırakmayın.
- Chat ID değerini kapatın.
- OneUptime `Content` alanındaki secret değerini kapatın.
- Kubernetes Secret'ın Base64 kodlanmış değerlerini kapatın.
- Gerekli olmayan kullanıcı adı, e-posta, oturum veya proje kimliklerini kapatın.
- Tarayıcı adres çubuğunda token içeren bir URL varsa adres çubuğunu kapatın.

Base64 kodlama şifreleme değildir. Base64 bir Secret değeri de gerçek secret gibi
gizlenmelidir.

## Kullanılan görseller

| Görsel | Kullanıldığı aşama | Gösterilen kanıt |
|---|---|---|
| `5.png` | Aşama 2 | Secret olarak oluşturulan iki OneUptime Global Variable |
| `7.png` | Aşama 4 | İki kaynağın sağlıklı public Status Page görünümü |
| `8.png` | Aşama 4 | Status Page grubu ve iki monitor-kaynak eşleştirmesi |
| `9.png` | Aşama 4 | Public Status Page kabul görünümü |
| `10.png` | Aşama 5 | Node 1 monitor Offline kriteri, Critical incident ve Auto Resolve |
| `11.png` | Aşama 5 | Node 2 monitor Offline kriteri, Major incident ve Auto Resolve |
| `13.png` | Aşama 6 | Incident Workflow Builder grafiği |
| `14.png` | Aşama 6 | Recovery Workflow Builder grafiği |
| `15.jpeg` | Aşama 8 | Manuel test incident'ının Resolved durumu |
| `16.png` | Aşama 7 | Telegram Incident tarih düzeltmesi ve Recovery test mesajı |
| `17.jpeg` | Aşama 8 | Incident ve Recovery Workflow Runs & Logs kayıtları |
| `21.jpeg` | Aşama 13 | Kontrollü testlerdeki son Workflow run kayıtları |
| `24.png` | Aşama 11 | Node 2 Offline durumu ve aktif Major incident |
| `25.png` | Aşama 11 | Gerçek Nginx kesintisinin Incident/Recovered mesaj çifti |
| `27.png` | Aşama 12 | Watchdog DOWN/RECOVERED mesaj çifti |
| `30.png` | Aşama 13 | Testler sonrasında tamamen Operational Status Page |

## Terminal çıktıları

Terminal ekranları bu dizinde resim olarak tutulmaz. Komutların sonuçları ilgili
aşama dosyalarında beklenen çıktı olarak kod bloklarında gösterilir. Kuruluma göre
değişen değerler şu biçimde temsil edilir:

```text
oneuptime-app-<pod-hash>    1/1    Running    <pod-ip>    oneuptime
```

Bu yöntem, gerçek bir çalıştırmanın birebir çıktısını iddia etmeden okuyucuya
başarılı sonucun yapısını gösterir.

Yeni bir arayüz görseli eklenecekse ilgili Markdown dosyasına şu biçimde
bağlanmalıdır:

```markdown
![Açıklayıcı alternatif metin](images/numara.png)
```
