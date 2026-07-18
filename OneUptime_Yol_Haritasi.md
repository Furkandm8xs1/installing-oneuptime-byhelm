# OneUptime Projesi İçin Güncellenmiş Yol Haritası

## Cross Monitoring + Distributed Tracing + Incident Management + Alert Routing

Bu doküman, şirket içerisindeki sunucuların, uygulamaların ve
servislerin merkezi olarak izlenmesini, hataların gerçek kaynağının
tespit edilmesini ve doğru ekiplere otomatik olarak yönlendirilmesini
amaçlayan proje yol haritasını içerir.

## Faz 0 --- Mevcut Sistemin Analizi (Discovery)

Amaç mevcut altyapıyı anlamaktır.

-   Monitoring altyapısı (Prometheus, Grafana vb.)
-   Log toplama yöntemi (Fluent Bit, Vector, Fluentd)
-   Log deposu (Loki, Elasticsearch, Splunk)
-   Bildirim kanalları
-   Incident süreci
-   Takımlar ve sorumluluklar

------------------------------------------------------------------------

## Faz 1 --- Infrastructure Monitoring

Tamamlanan çalışmalar:

-   Kubernetes üzerinde OneUptime kurulumu
-   Çoklu Probe yapısı
-   Cross Monitoring
-   Proxy Health Check

Amaç:

-   Sunucu ayakta mı?
-   Proxy çalışıyor mu?
-   Response süresi normal mi?

------------------------------------------------------------------------

## Faz 2 --- Ölçeklenebilir Cross Monitoring

İki node yerine N node desteklenir.

Önerilen yaklaşım:

-   Ring Monitoring
-   Hierarchical Monitoring
-   Bölgesel (Datacenter) Probe yapısı
-   Yedek probe doğrulaması

------------------------------------------------------------------------

## Faz 3 --- Merkezi Log Toplama + Distributed Tracing

Amaç:

-   Fluent Bit / Vector ile log toplama
-   OpenTelemetry ile Trace üretme
-   TraceID ile log ve trace ilişkilendirme
-   Jaeger / Tempo
-   Loki / Elasticsearch

Bu faz sonunda yalnızca "404 oluştu" değil, "404 Product Service
üzerindeki Pod-2'de oluştu." bilgisi elde edilir.

------------------------------------------------------------------------

## Faz 4 --- Incident Management

OneUptime üzerinde:

-   Organization
-   Project
-   Teams
-   Users
-   Roller
-   On-Call Schedule
-   Escalation Policy
-   Incident Lifecycle
-   Status Page

------------------------------------------------------------------------

## Faz 5 --- Alert Routing Engine

Kurallar örneği:

-   404 oranı arttı → Frontend
-   429 Too Many Requests → Backend + Security
-   OutOfMemory → Platform
-   Database Down → DBA + Platform
-   Timeout → İlgili servis

Alert Router servisi log ve trace analiz ederek Incident oluşturur.

------------------------------------------------------------------------

## Faz 6 --- Notification & Escalation

Bildirim kanalları:

-   Microsoft Teams
-   Telegram
-   Slack
-   WhatsApp Business
-   SMS
-   Telefon Araması (kritik olaylar)

Escalation örneği:

1.  On-call Engineer
2.  Team Lead
3.  Engineering Manager
4.  CTO

------------------------------------------------------------------------

## Faz 7 --- AI Destekli Root Cause Analysis

AI Agent;

-   Trace analizi
-   Log analizi
-   Benzer Incident analizi
-   Root Cause tahmini
-   Runbook önerileri

sunacaktır.

------------------------------------------------------------------------

# Nihai Mimari

Application

↓

OpenTelemetry

↓

Collector

↓

Logs + Metrics + Traces

↓

Alert Router

↓

OneUptime Incident

↓

Teams / Telegram / SMS / Phone

Bu yapı şirketin merkezi Observability ve Incident Management
platformunu oluşturur.
