# Aşama 14 — TLS Certificate Monitor

## Amaç

Yerel `oneuptime.furkan.test` TLS sertifikasının bitmesine kaç gün kaldığını
OneUptime üzerinden izlemek; 30 gün kala uyarı, 7 gün kala kritik durum ve
incident üretmek.

Kubernetes ve Probe One tarafında yapılan ağ değişikliğinin ayrıntıları için
[TLS Certificate Monitor İçin Probe One Ağ Yapılandırması](../kurulum/TLS_CERTIFICATE_MONITOR_PROBE_ONE.md)
belgesine bakın.

Hostname'in alias öncesinde neden `127.0.0.1:443` adresine gidip
`ECONNREFUSED` aldığı dahil bütün terminal kanıtları
[teknik sorun giderme günlüğünde](../trouble-shooting/TLS_CERTIFICATE_MONITOR_PROBE_ONE_UYGULAMA_GUNLUGU.md)
bulunur.

## 14.1 Neden mevcut proje içinde yeni monitor?

Bu sertifika aynı OneUptime kurulumuna aittir. Bu nedenle yeni proje yerine
mevcut proje içinde bağımsız bir monitor kullanılır. Böylece:

- Mevcut Probe One kullanılabilir.
- Incident ve Recovery workflow'ları tekrar kullanılabilir.
- Proje yetkileri ve bildirim yapısı bölünmez.
- Sertifika monitorü diğer servis monitorlerinden bağımsız durum üretir.

Yeni proje yalnızca farklı ekip, yetki, bildirim politikası veya tamamen farklı
bir ortam söz konusuysa gereklidir.

## 14.2 Ön koşullar

Panelde monitor oluşturmadan önce aşağıdaki kontroller başarılı olmalıdır:

```bash
kubectl -n oneuptime get deployment oneuptime-probe-one -o json | \
  jq '{ready:.status.readyReplicas,
       hostAliases:.spec.template.spec.hostAliases}'
```

Beklenen özet:

```text
ready: 1
oneuptime.furkan.test → 10.97.179.200
```

Service IP'sini ayrıca kontrol edin:

```bash
kubectl -n oneuptime get service oneuptime-local-tls \
  -o jsonpath='{.spec.clusterIP}{"\n"}'
```

Beklenen mevcut değer:

```text
10.97.179.200
```

Service IP farklıysa monitorü oluşturmadan önce
`probe-one-host-alias.yaml` güncellenmelidir.

## 14.3 Monitor oluşturma

OneUptime panelinde:

```text
Monitors → Create Monitor → SSL Certificate
```

Alanları aşağıdaki gibi doldurun:

| Alan | Değer |
|---|---|
| Monitor Name | `OneUptime Local TLS Certificate` |
| Monitor Type | `SSL Certificate` |
| URL / Destination | `https://oneuptime.furkan.test` |
| Probe | Yalnızca `Probe One` / varsayılan `Probe` |
| Check Interval | Mümkünse `6 hours`; yoksa en yakın saatlik seçenek |

Sertifika kontrolü TLS el sıkışmasında yapılır; Status Page'in uzun yolu bu
monitor için gerekli değildir. Hedef olarak şu adres kullanılmamalıdır:

```text
https://oneuptime.furkan.test/status-page/<id>
```

Doğru hedef hostname'in kök HTTPS adresidir:

```text
https://oneuptime.furkan.test
```

## 14.4 Kriter sırası neden önemlidir?

Monitor kriterleri yukarıdan aşağıya değerlendirilir ve ilk eşleşen kriter
sonucu üretir. Örneğin sertifikanın bitmesine 5 gün kaldığında hem `<7` hem de
`<30` doğrudur. `<30` kriteri önce gelirse monitor yalnızca `Degraded` olabilir.

Doğru sıra:

1. `< 7 gün` veya erişim hatası → `Offline`
2. `< 30 gün` → `Degraded`
3. `>= 30 gün` ve erişilebilir → `Operational`

Kriter kartlarını sol taraflarındaki sürükleme tutamacıyla bu sıraya getirin.

## 14.5 Kriter 1/3 — Offline ve Critical

İlk kriter kartında:

| Alan | Değer |
|---|---|
| Criteria Name | `OneUptime TLS sertifikası kritik veya erişilemiyor` |
| Criteria Description | `Sertifika 7 günden az kaldığında, sona erdiğinde veya TLS isteği zaman aşımına uğradığında Offline olur.` |
| Filter Condition | `Any` |

Filtreleri ekleyin:

```text
Expires In Days       Less Than   7
OR
Is Expired Certificate            True
OR
Is Request Timeout                True
```

Arayüz destekliyorsa aşağıdaki filtre de eklenebilir:

```text
Is Online                         False
```

### Bu kriterden silinmesi gerekenler

Şunları ilk Offline kartında tutmayın:

```text
Is Not A Valid Certificate = True
Expires In Days < 30
```

`Expires In Days < 30`, ayrı Degraded kriterine aittir.

Yerel sertifika, `OneUptime Local Development CA` tarafından imzalanmıştır ve bu
CA şu anda Probe One container güven deposunda değildir. Bu nedenle
`Is Not A Valid Certificate=True` filtresi kullanılırsa sertifikanın bitmesine
824 gün kalsa bile kriter hemen eşleşebilir.

### Offline actions

```text
When filters match, change monitor status: Açık
Change monitor status to: Offline

When filters match, create an alert: Kapalı
When filters match, declare an incident: Açık
```

Incident alanları:

| Alan | Değer |
|---|---|
| Incident Title | `[Cross-Monitoring] OneUptime TLS sertifikası kritik durumda` |
| Severity | `Critical Incident` |
| Auto Resolve Incident | `Yes` |
| Show Incident on Status Page | Dahili uyarı isteniyorsa `No`; ayrıca göstermek isteniyorsa `Yes` |

Incident Description:

```text
oneuptime.furkan.test TLS sertifikasının süresinin dolmasına 7 günden az kaldı,
sertifika sona erdi veya TLS adresine erişilemiyor.
```

Başlıktaki `[Cross-Monitoring]` öneki önemlidir. Mevcut Incident ve Recovery
Telegram workflow'ları yalnızca başlığı bu önekle başlayan incident'ları işler.
Önek kaldırılırsa incident oluşur ancak mevcut workflow Telegram mesajı
göndermez.

## 14.6 Kriter 2/3 — Degraded ve 30 günlük uyarı

İkinci kriter kartı:

| Alan | Değer |
|---|---|
| Criteria Name | `OneUptime TLS sertifikasının süresi 30 günden az` |
| Criteria Description | `Sertifikanın bitmesine 30 günden az kaldığında yenileme uyarısı üretir.` |
| Filter Condition | `All` |

Tek filtre:

```text
Expires In Days       Less Than   30
```

İlk `<7` Offline kriteri bunun üzerinde olduğu için 7 günden az kaldığında önce
kritik kriter çalışır.

Actions:

```text
When filters match, change monitor status: Açık
Change monitor status to: Degraded

When filters match, declare an incident: Açık
```

Incident alanları:

| Alan | Değer |
|---|---|
| Incident Title | `[Cross-Monitoring] OneUptime TLS sertifikası 30 gün içinde sona erecek` |
| Severity | `Minor Incident` |
| Auto Resolve Incident | `Yes` |

Incident Description:

```text
oneuptime.furkan.test TLS sertifikasının süresinin dolmasına 30 günden az kaldı.
Sertifika yenileme işlemi planlanmalıdır.
```

30 günlük durumda incident yerine yalnızca panel durumu isteniyorsa `Declare an
incident` kapatılabilir. Ancak mevcut Telegram workflow'uyla 30 günlük ön uyarı
almak isteniyorsa açık bırakılmalıdır.

## 14.7 Kriter 3/3 — Operational

Üçüncü ve son kriter:

| Alan | Değer |
|---|---|
| Criteria Name | `OneUptime TLS sertifikası sağlıklı` |
| Criteria Description | `Sertifika erişilebilir ve bitmesine en az 30 gün var.` |
| Filter Condition | `All` |

Filtreler:

```text
Expires In Days       Greater Than or Equal   30
AND
Is Online                                     True
```

Arayüzde `Greater Than or Equal` seçeneği yoksa eşdeğer olarak şunu kullanın:

```text
Expires In Days       Greater Than   29
```

Actions:

```text
When filters match, change monitor status: Açık
Change monitor status to: Operational

When filters match, create an alert: Kapalı
When filters match, declare an incident: Kapalı
```

Offline ve Degraded kriterlerindeki `Auto Resolve=Yes`, monitor tekrar bu
Operational kritere geldiğinde ilgili incident'ın otomatik çözülmesini sağlar.

## 14.8 Ekran görüntülerindeki yanlış birleşimin düzeltilmesi

İlk kurulum denemesinde Offline kriterinde şu üç filtre aynı `Any` grubu altında
bulunuyordu:

```text
Is Not A Valid Certificate = True
OR Expires In Days < 30
OR Expires In Days < 7
```

Bu yapı doğru değildir:

- Yerel CA güvenilmediği için ilk filtre hemen Offline üretebilir.
- `<30`, 29 gün kaldığında monitorü doğrudan Offline yapar.
- `<7`, zaten `<30` tarafından kapsandığı için aynı kartta etkisiz kalır.

Düzeltme:

1. Offline kartından `Is Not A Valid Certificate=True` filtresini silin.
2. Offline kartından `<30` filtresini silin.
3. Offline kartında `<7`, expired ve timeout filtrelerini bırakın.
4. `<30` filtresini ikinci Degraded kartına koyun.
5. Sağlıklı kriterini üçüncü karta koyun.
6. Kart sırasının Offline → Degraded → Operational olduğunu doğrulayın.

## 14.9 Beklenen ilk sonuç

Sertifikanın doğrulanan bilgileri:

```text
Common Name: oneuptime.furkan.test
Issuer: OneUptime Local Development CA
Valid From: 17 Ağustos 2026 14:57:40 UTC
Valid To: 19 Kasım 2028 14:57:40 UTC
Kurulum anında kalan süre: yaklaşık 824 gün
```

Kriterler kaydedildikten ve ilk kontrol tamamlandıktan sonra beklenen durum:

```text
Monitor: OneUptime Local TLS Certificate
Probe: Probe One
Resolved IP: 10.97.179.200
Status: Operational
```

Kalan süre yaklaşık 824 gün olduğu için `<30` ve `<7` kriterleri
eşleşmemelidir.

## 14.10 Panelde doğrulama

Monitor detayında şu bölümleri kontrol edin:

- **Monitor Events / Logs:** Probe One'ın kontrol yaptığı görülmeli.
- **Certificate Details:** CN ve bitiş tarihi görünmeli.
- **Probes:** Yalnızca Probe One seçili olmalı.
- **Criteria:** Sıra Offline, Degraded, Operational olmalı.
- **Current Status:** `Operational` olmalı.

İlk kontrol sonucu hemen görünmüyorsa seçilen check interval'i bekleyin veya
arayüzde mevcutsa manuel `Run/Test Monitor` işlemini kullanın.

## 14.11 Sorun giderme

### Monitor hostname'i çözemiyorsa

```bash
kubectl -n oneuptime exec deployment/oneuptime-probe-one -- \
  node -e \
  'require("dns").lookup("oneuptime.furkan.test",(e,a)=>{if(e)throw e;console.log(a)})'
```

Beklenen IP:

```text
10.97.179.200
```

Farklıysa Service IP ve `probe-one-host-alias.yaml` değerini karşılaştırın.

### Monitor hemen Offline oluyorsa

Önce Offline kriterinde şu filtrenin bulunmadığını doğrulayın:

```text
Is Not A Valid Certificate = True
```

Yerel CA henüz Probe One tarafından güvenilir kabul edilmediği için en olası
neden budur.

### Monitor 29 gün kala Offline oluyorsa

`Expires In Days < 30` filtresi yanlışlıkla Offline kartındadır. Filtreyi
Degraded kartına taşıyın.

### Telegram mesajı gelmiyorsa

Incident title'ın tam olarak şu önekle başladığını doğrulayın:

```text
[Cross-Monitoring]
```

Ardından `Cross-Monitoring Incident → Telegram` workflow'unun Enabled olduğunu
ve Runs & Logs bölümünü kontrol edin.

### Monitor port-forward kapalıyken çalışmıyorsa

Bu beklenen tasarım değildir. Probe One'ın hedefi Mac'teki `127.0.0.1` veya
port-forward değil, `hostAliases` üzerinden `oneuptime-local-tls` ClusterIP
olmalıdır. Probe içindeki çözümlemeyi tekrar kontrol edin.

## 14.12 Kabul kontrol listesi

- [ ] Monitor mevcut proje içinde oluşturuldu.
- [ ] Monitor türü `SSL Certificate`.
- [ ] Hedef `https://oneuptime.furkan.test`.
- [ ] Yalnızca Probe One seçili.
- [ ] Offline kriteri birinci ve `<7` filtresini içeriyor.
- [ ] Offline kriterinde `Is Not A Valid Certificate=True` bulunmuyor.
- [ ] Degraded kriteri ikinci ve `<30` filtresini içeriyor.
- [ ] Operational kriteri üçüncü ve `>=30 AND Is Online=True` kullanıyor.
- [ ] Offline incident severity `Critical Incident`.
- [ ] Degraded incident severity `Minor Incident`.
- [ ] Incident başlıkları `[Cross-Monitoring]` ile başlıyor.
- [ ] Auto Resolve etkin.
- [ ] İlk kontrol sonucu `Operational`.
- [ ] Bitiş tarihi `19 Kasım 2028 14:57:40 UTC` olarak okunuyor.

## 14.13 İlgili belgeler

- [Probe One ağ yapılandırması](../kurulum/TLS_CERTIFICATE_MONITOR_PROBE_ONE.md)
- [Yerel HTTPS kurulumu](../kurulum/LOCAL_HTTPS.md)
- [Monitor kriterleri ve otomatik incident'lar](05-monitor-kriterleri-ve-incidentlar.md)
- [Incident → Telegram workflow](07-incident-telegram-workflow.md)
- [Recovery → Telegram workflow](08-recovery-telegram-workflow.md)
- [OneUptime SSL Certificate Monitor](https://oneuptime.com/docs/en/monitor/ssl-certificate-monitor)
