# OneUptime Status Page, Incident Workflow ve Telegram Bildirim Planı

## Özet

İki cross-monitor tek bir public yerel Status Page’de gösterilecek. Monitor arızaları otomatik incident oluşturacak; OneUptime Workflow arıza ve iyileşme mesajlarını kişisel Telegram sohbetine gönderecek. Node 1 tamamen çöktüğünde OneUptime Workflow çalışamayacağı için Node 2’de bağımsız Telegram watchdog kurulacak. Telefon araması kapsam dışıdır.

Uygulama sırasında her aşama tek tek anlatılacak ve siz tamamladığınızı bildirmeden sonraki aşamaya geçilmeyecek.

## Uygulama adımları

### 1. Telegram hazırlığı

- BotFather üzerinden projeye özel yeni bot oluşturulacak.
- Botla kişisel sohbet başlatılıp `/start` gönderilecek.
- `getUpdates` üzerinden kişisel Chat ID bulunacak.
- Token ve Chat ID hiçbir Markdown dosyasına, ekran görüntüsüne, Git dosyasına veya sohbete yazılmayacak.
- OneUptime Global Variables altında oluşturulacak:
  - `TELEGRAM_BOT_TOKEN`: secret
  - `TELEGRAM_CHAT_ID`: secret
- Aynı değerler watchdog için `oneuptime-watchdog-telegram` adlı Kubernetes Secret’a güvenli, etkileşimli komutla kaydedilecek.

### 2. Public Status Page

- Sayfa adı: `OneUptime Cross-Monitoring Status`
- Erişim: public, parolasız; `https://oneuptime.furkan.test` ve TLS port-forward üzerinden yerel erişim
- Tek grup: `Cross-Monitoring Services`
- Kaynaklar:
  - `Node 1 – OneUptime Core` → `Node1-App-Health-Check`
  - `Node 2 – Nginx Target` → `Node2-Nginx-Health-Check`
- Her iki kaynak için güncel durum ve uptime geçmişi gösterilecek.
- Public incident görünümü etkinleştirilecek; custom domain kurulmayacak.

### 3. Monitor kriterleri ve otomatik incident’lar

Her iki monitor için Offline kriteri:

- `Is Online = False` veya `Response Status Code != 200`
- Monitor durumu `Offline` yapılacak.
- Otomatik incident oluşturma etkinleştirilecek.
- Incident iyileşmede otomatik çözülecek.
- Incident Status Page üzerinde gösterilecek.

Incident ayrımı:

- Node 1:
  - Başlık: `[Cross-Monitoring] Node 1 OneUptime Core erişilemiyor`
  - Severity: `Critical`
- Node 2:
  - Başlık: `[Cross-Monitoring] Node 2 Nginx Target erişilemiyor`
  - Severity: `Major`

Başarılı HTTP yanıtı mevcut `Operational/Online` kriterine dönecek.

### 4. OneUptime Workflow’ları

`Cross-Monitoring Incident → Telegram`:

1. Trigger: `Incident → On Create`
2. Conditions: Incident title `starts with [Cross-Monitoring]`
3. Yes çıkışı: Telegram bileşeni
4. Bot token ve Chat ID secret Global Variables üzerinden verilecek.
5. Mesaj `[INCIDENT]` etiketiyle Türkçe incident başlığı, açıklaması, severity ve zamanı içerecek.

`Cross-Monitoring Recovery → Telegram`:

1. Trigger: `Incident → On Update`
2. İlk Conditions: title `[Cross-Monitoring]` ile başlıyor.
3. İkinci Conditions: incident state `Resolved`.
4. Yes çıkışı: Telegram bileşeni.
5. Mesaj `[RECOVERED]` etiketiyle Türkçe iyileşme bildirimi gönderecek.

Alan referansları elle yazılmayacak; Workflow değer seçicisi kullanılacak. Önce Manual Run ve Logs kontrolü yapılacak, sonra iki workflow etkinleştirilecek. Bu yapı resmi [Workflow](https://oneuptime.com/docs/en/workflows/index) ve [Workflow Components](https://oneuptime.com/docs/en/workflows/components) modelini kullanır.

### 5. Node 2 bağımsız watchdog

`node1-watchdog.yaml` oluşturulacak:

- Tek replica Deployment
- `nodeSelector: app=oneuptime-probe`
- Node: `oneuptime-m02`
- Kontrol aralığı: 30 saniye
- Alarm: 3 ardışık hata, yaklaşık 90 saniye
- İyileşme: 2 ardışık başarılı kontrol
- Hedef: Kubernetes’in enjekte ettiği `ONEUPTIME_APP_SERVICE_HOST` ClusterIP’sinde `:3002/status/live`
- Telegram mesajları:
  - `[WATCHDOG] DOWN`
  - `[WATCHDOG] RECOVERED`
- Telegram değerleri Kubernetes Secret’tan alınacak.
- Watchdog, Node 1’deki CoreDNS’e bağımlı olmayacak; Telegram için bağımsız dış DNS kullanacak.
- Tek süreç içinde durum tutulacak ve aynı arıza için her 30 saniyede tekrar mesaj atılmayacak.

OneUptime incident mesajı ve watchdog mesajı aynı arıza sonrasında birlikte/gecikmeli gelebilir; seçilen yedeklilik politikası gereği bu kabul edilecek.

### 6. Dokümantasyon

Yeni `ONEUPTIME_STATUS_INCIDENT_WORKFLOW.md` dosyası hazırlanacak. İçeriği:

- BotFather adımları
- Status Page kurulumu
- Incident kriterleri
- İki Workflow’un blok bağlantıları
- Global Variable ve Secret güvenliği
- Node 1 çöküşünde Workflow’un neden tek başına yeterli olmadığı
- Watchdog mimarisi
- Mermaid bildirim akış şeması
- Kontrollü kesinti ve iyileşme testleri
- Workflow Logs, Status Page ve Telegram kabul kontrolleri

Gerçek token ve Chat ID dokümana eklenmeyecek.

## Test planı

- Telegram botuna güvenli test mesajı gönderilecek.
- Status Page’de iki kaynak `Operational` görünmeli.
- Workflow Manual Run sonucu `Success` olmalı ve Telegram mesajı gelmeli.
- Nginx testi:
  - `nginx-target` geçici olarak silinecek.
  - Major incident, Status Page kesintisi ve `[INCIDENT]` mesajı doğrulanacak.
  - Pod yeniden oluşturulacak.
  - Incident auto-resolve ve `[RECOVERED]` mesajı doğrulanacak.
- Core testi:
  - `oneuptime-app` geçici olarak `0` replica yapılacak.
  - Yaklaşık 90 saniye içinde watchdog `[WATCHDOG] DOWN` göndermeli.
  - Replica tekrar `1` yapılacak ve rollout tamamlanmalı.
  - İki başarılı kontrolden sonra `[WATCHDOG] RECOVERED` gelmeli.
  - Core geri geldiğinde oluşabilecek gecikmiş OneUptime incident mesajı kabul edilecek.
- Test sonunda tüm podlar hazır, iki monitor Online ve Status Page Operational olmalı.
- Workflow Runs & Logs kayıtlarında iki workflow’un başarılı çalıştığı doğrulanmalı.

## Varsayımlar

- İçerikler ve Telegram mesajları Türkçe olacak; mevcut teknik monitor adları korunacak.
- Telefon/SMS/SMTP kurulmayacak.
- Telegram kişisel sohbet kullanılacak.
- Status Page yalnızca port-forward erişimi nedeniyle yerel olarak public olacaktır.
- Self-hosted OneUptime `12.0.6` kullanılmaya devam edilecek.
- Gerçek control-plane node container’ı durdurulmayacak; güvenli test için App replica `0/1` yöntemi kullanılacak.
