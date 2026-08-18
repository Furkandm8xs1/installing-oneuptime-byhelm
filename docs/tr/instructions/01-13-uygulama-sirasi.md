# Aşama 1–14 — Baştan Sona Uygulama Sırası

Bu dosya, OneUptime cross-monitoring, Status Page, Telegram workflow, bağımsız
watchdog ve yerel TLS sertifika monitorü çalışmasının ilk hazırlıktan son kabul
testine kadar tam uygulama sırasını tek yerde toplar.

Ayrıntılı açıklamalar, komutlar, kabul kontrolleri ve ekran görüntüsü önerileri
her aşamanın bağlantılı dokümanında bulunur.

## Hazırlık ve secret yönetimi

1. [Telegram botu ve Chat ID hazırlama](01-telegram-botu-ve-chat-id.md)
   - BotFather üzerinden projeye özel bot oluşturulur.
   - Botla kişisel sohbet başlatılır ve `/start` gönderilir.
   - `getUpdates` ile Chat ID bulunur ve test mesajı gönderilir.

2. [OneUptime Global Variables oluşturma](02-oneuptime-global-variables.md)
   - `TELEGRAM_BOT_TOKEN` secret değişkeni oluşturulur.
   - `TELEGRAM_CHAT_ID` secret değişkeni oluşturulur.
   - Gerçek değerler Workflow Builder içine doğrudan yazılmaz.

3. [Kubernetes Telegram Secret oluşturma](03-kubernetes-telegram-secret.md)
   - `oneuptime-watchdog-telegram` Secret'ı oluşturulur.
   - İki secret anahtarının varlığı, değerler gösterilmeden doğrulanır.

## Status Page ve incident üretimi

4. [Public Status Page oluşturma](04-public-status-page.md)
   - `OneUptime Cross-Monitoring Status` sayfası oluşturulur.
   - Node 1 ve Node 2 monitorleri `Cross-Monitoring Services` grubuna eklenir.
   - Public, parolasız yerel erişim doğrulanır.

5. [Monitor kriterleri ve otomatik incident'lar](05-monitor-kriterleri-ve-incidentlar.md)
   - Offline ve Operational kriterleri doğru sırayla yapılandırılır.
   - Node 1 için Critical, Node 2 için Major incident tanımlanır.
   - Auto Resolve ve Status Page görünümü etkinleştirilir.

## OneUptime Telegram workflow'ları

6. [Workflow JSON dosyalarını içe aktarma](06-workflow-json-import.md)
   - Incident ve Recovery workflow JSON dosyaları import edilir.
   - Grafik bağlantıları ve Global Variable referansları kontrol edilir.

7. [Incident → Telegram workflow testi](07-incident-telegram-workflow.md)
   - `[Cross-Monitoring]` başlıklı test incident'ı oluşturulur.
   - `[INCIDENT]` Telegram mesajı ve Runs & Logs sonucu doğrulanır.

8. [Recovery → Telegram workflow testi](08-recovery-telegram-workflow.md)
   - Test incident'ı `Resolved` durumuna geçirilir.
   - `[RECOVERED]` Telegram mesajı ve workflow logu doğrulanır.

9. [Workflow'ları üretim için etkinleştirme](09-workflow-etkinlestirme.md)
   - Doğrulanmış Incident ve Recovery workflow'ları açık bırakılır.
   - Eski veya yinelenen taslak workflow'lar kapatılır.

## Bağımsız watchdog

10. [Node 2 bağımsız watchdog kurulumu](10-node1-watchdog-kurulumu.md)
    - `node1-watchdog.yaml` uygulanır.
    - Watchdog'un `oneuptime-m02` üzerinde çalıştığı doğrulanır.
    - Node 1 sağlık endpoint'ine HTTP `200` aldığı kontrol edilir.

## Kontrollü kesinti testleri

11. [Nginx kontrollü kesinti testi](11-nginx-kesinti-testi.md)
    - Node 2 Nginx podu geçici olarak silinir.
    - Major incident, Status Page ve `[INCIDENT]` mesajı doğrulanır.
    - Pod geri getirilerek gerçek auto-resolve ve `[RECOVERED]` test edilir.

12. [Node 1 Core watchdog testi](12-node1-core-kesinti-testi.md)
    - `oneuptime-app` geçici olarak `0` replica yapılır.
    - `[WATCHDOG] DOWN` mesajı doğrulanır.
    - App tekrar `1` replica yapılarak `[WATCHDOG] RECOVERED` doğrulanır.

## Son kabul

13. [Son kabul ve güvenlik kontrolleri](13-son-kabul-kontrolleri.md)
    - Podlar, node yerleşimleri, Service endpoint'leri ve Helm durumu kontrol edilir.
    - İki monitor ve Status Page'in Operational olduğu doğrulanır.
    - Workflow logları, Telegram mesajları ve secret güvenliği kontrol edilir.

## TLS sertifika izleme

14. [TLS Certificate Monitor](14-tls-certificate-monitor.md)
    - Mevcut proje içinde SSL Certificate Monitor oluşturulur.
    - Probe One, `hostAliases` üzerinden yerel TLS Service'e ulaşır.
    - 7 günlük Offline/Critical, 30 günlük Degraded ve sağlıklı Operational
      kriterleri doğru sırada tanımlanır.
    - Yerel CA güven sınırlaması ve `[Cross-Monitoring]` Telegram başlık öneki
      doğrulanır.

## Ekran görüntüsü yaklaşımı

Her ayrıntılı dosyada `Ekran görüntüsü önerisi` başlıklı notlar bulunur. Görseller
`docs/tr/instructions/images/` altında tutulmalı ve eklenmeden önce token, Chat ID,
secret içerikleri, kullanıcı adı ve oturum bilgileri sansürlenmelidir.

Özellikle aşağıdaki kanıt görselleri raporun ana akışını göstermek için yeterlidir:

- İki secret Global Variable'ın listesi
- İki kaynaklı Operational Status Page
- Node 1 ve Node 2 monitor kriterleri
- Incident ve Recovery Workflow Builder grafikleri
- İki workflow'un Enabled olduğu liste
- Nginx kesintisindeki Status Page ve Telegram mesaj çifti
- Watchdog DOWN ve RECOVERED mesaj çifti
- Son pod yerleşimi ve tamamen Operational Status Page
- TLS Certificate Monitor kriter sırası ve Operational ilk sonuç
