# Yerel HTTPS ve TLS Sertifikası

Bu belge iki amacı birlikte taşır:

1. Bu projeye HTTPS eklenirken gerçekte hangi adımların uygulandığını ve hangi
   sonuçların alındığını gösterir.
2. Minikube yeniden başlatıldığında HTTPS erişiminin nasıl tekrar açılacağını
   anlatır.

Belgedeki uzun ve tekrarlı terminal çıktıları okunabilirlik için kısaltılmıştır.
Hiçbir Probe Key, parola veya özel anahtar içeriği belgeye yazılmamıştır.

DNS'ten uygulamaya kadar paketlerin geçtiği katmanlar, port dönüşümleri,
Kubernetes Service/Endpoint ilişkileri ve Mermaid akış şemaları ayrı olarak
[Yerel DNS, TLS Proxy ve Uygulama Trafik Akışı](LOCAL_DNS_TLS_TRAFFIC.md)
belgesinde açıklanmıştır.

## İçindekiler

1. [Son durum](#1-son-durum)
2. [Neden mevcut 443 portu kullanılmadı?](#2-neden-oneuptimeın-mevcut-443-portu-kullanılmadı)
3. [Uygulama sırasında yapılan işlemler](#3-uygulama-sırasında-yapılan-işlemler)
4. [Yapılan doğrulamalar ve gerçek sonuçlar](#4-yapılan-doğrulamalar-ve-gerçek-sonuçlar)
5. [Eklenen ve değiştirilen dosyalar](#5-eklenen-ve-değiştirilen-dosyalar)
6. [Bundan sonra günlük kullanım](#6-bundan-sonra-günlük-kullanım)
7. [Elle doğrulama komutları](#7-elle-doğrulama-komutları)
8. [Sorun giderme](#8-sorun-giderme)
9. [Güvenlik notları](#9-güvenlik-notları)
10. [Resmî kaynaklar](#10-resmî-kaynaklar)

## 1. Son durum

OneUptime panelinin yeni yerel adresi:

```text
https://oneuptime.furkan.test
```

İstek şu yolu izler:

```text
Mac tarayıcısı
  │
  │ oneuptime.furkan.test yazılırsa önce HTTP/80
  │ 308 redirect ile HTTPS/443
  ▼
kubectl port-forward
  │
  │ oneuptime-local-tls Service, port 443
  ▼
oneuptime-local-tls podu
  │
  │ TLS burada sonlandırılır
  │ HTTP, cluster içi port 80
  ▼
oneuptime-nginx Service
  │
  ▼
OneUptime uygulaması
```

Son durumda:

- Tarayıcı ile proxy arasındaki trafik şifrelidir.
- TLS 1.2 ve TLS 1.3 desteklenir.
- Sertifika `oneuptime.furkan.test`, `localhost`, `127.0.0.1` ve `::1` için
  geçerlidir.
- Yerel CA macOS kullanıcı anahtar zincirinde güvenilir durumdadır.
- OneUptime'ın kendi URL ayarı da `https://oneuptime.furkan.test` olarak
  güncellenmiştir.
- Cluster içindeki `oneuptime-local-tls → oneuptime-nginx` bağlantısı HTTP'dir.
  Bu trafik Minikube cluster ağı içinde kalır.

## 2. Neden OneUptime'ın mevcut 443 portu kullanılmadı?

OneUptime chart'ında aşağıdaki yerleşik ayarlar bulundu:

```yaml
host: localhost
httpProtocol: http

ssl:
  provision: false

nginx:
  ports:
    http: 80
    https: 443
```

`ssl.provision: true`, Let's Encrypt üzerinden otomatik sertifika almak içindir.
Bu yöntem için gerçek bir DNS adı ile internetten erişilebilen 80 ve 443
portları gerekir. Let's Encrypt `localhost` adına sertifika üretmez.

Chart'ın Service nesnesinde 443 portunun bulunması da tek başına yeterli
değildir. O portta kullanılacak bir sertifika yoksa TLS el sıkışması
tamamlanamaz. Bu durum aşağıdaki testte doğrulandı.

Bu nedenle OneUptime'ın önüne, sertifikası Kubernetes Secret'tan gelen ayrı bir
TLS reverse proxy konuldu.

## 3. Uygulama sırasında yapılan işlemler

### 3.1 Mevcut proje ayarları incelendi

Önce proje içinde HTTP, HTTPS, TLS, host ve port-forward ayarları arandı:

```bash
rg -n -i \
  "ingress|tls|https|3002|port-forward|minikube tunnel|host|domain|cert" \
  values.yaml all.yaml default-values.yaml oneuptime/values.yaml \
  oneuptime/templates SETTING_UP.md docs
```

Önemli bulgular:

```text
values.yaml:5:host: "localhost:8080"
values.yaml:6:httpProtocol: http
SETTING_UP.md:237:kubectl port-forward svc/oneuptime-nginx 8080:80
oneuptime/values.yaml:ssl.provision: false
oneuptime/values.yaml:nginx.ports.http: 80
oneuptime/values.yaml:nginx.ports.https: 443
```

Yerel araçlar da kontrol edildi:

```bash
command -v kubectl
command -v helm
command -v minikube
command -v mkcert
command -v openssl
```

Çıktı:

```text
/opt/homebrew/bin/kubectl
/opt/homebrew/bin/helm
/opt/homebrew/bin/minikube
mkcert için çıktı yok; kurulu değil
/usr/bin/openssl
```

`mkcert` kurulu olmadığı için yeni bir paket indirmek yerine macOS'ta zaten
bulunan OpenSSL ile projeye özel yerel CA üretildi.

Chart'ın Ingress template'i de incelendi:

```bash
sed -n '1,260p' oneuptime/templates/ingress.yaml
sed -n '1,340p' oneuptime/templates/nginx.yaml
```

Ingress template'inin çıktısı şunu gösterdi:

```text
Kubernetes Ingress support has been removed.
This template intentionally renders nothing.
```

Yani bu chart ayrıca bir Kubernetes Ingress kaynağı oluşturmuyor;
`oneuptime-nginx` kendi gateway'i olarak çalışıyor.

### 3.2 Çalışan cluster kontrol edildi

Kullanılan Kubernetes context:

```bash
kubectl config current-context
```

Çıktı:

```text
oneuptime
```

Mevcut OneUptime Service, Deployment ve Helm release kontrol edildi:

```bash
kubectl --context oneuptime -n oneuptime \
  get svc oneuptime-nginx -o wide

kubectl --context oneuptime -n oneuptime \
  get deploy oneuptime-nginx -o wide

helm --kube-context oneuptime -n oneuptime list
```

İlgili çıktı:

```text
NAME              TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)
oneuptime-nginx   LoadBalancer   10.109.199.202   <pending>     80:31683/TCP,443:31367/TCP

NAME              READY   AVAILABLE   IMAGE
oneuptime-nginx   1/1     1           docker.io/oneuptime/nginx:release

NAME        STATUS     CHART              APP VERSION
oneuptime   deployed   oneuptime-12.0.6   12.0.6
```

Burada Service üzerinde 443 portunun tanımlı olduğu görüldü. Bir sonraki adımda
bu portun gerçekten kullanılabilir TLS sunup sunmadığı test edildi.

### 3.3 Mevcut 443 portu test edildi ve hata doğrulandı

Önce OneUptime'ın mevcut 443 portu geçici olarak bilgisayardaki 18443 portuna
iletildi:

```bash
kubectl --context oneuptime -n oneuptime \
  port-forward svc/oneuptime-nginx 18443:443
```

Çıktı:

```text
Forwarding from 127.0.0.1:18443 -> 7850
Forwarding from [::1]:18443 -> 7850
```

Ardından TLS isteği gönderildi:

```bash
curl -vkI --max-time 10 https://localhost:18443/
```

Sonuç:

```text
Connected to localhost (::1) port 18443
TLS handshake, Client hello
LibreSSL: tlsv1 alert internal error
curl: (35) LibreSSL SSL_connect error
```

Bu sonuç şunu kanıtladı:

- TCP bağlantısı kurulabiliyordu.
- İstemci TLS görüşmesini başlatabiliyordu.
- Sunucu tarafı geçerli bir sertifika ile görüşmeyi tamamlayamıyordu.
- Yalnızca `httpProtocol: https` yapmak yeterli olmayacaktı.

Testten sonra geçici 18443 port-forward süreci `Ctrl+C` ile kapatıldı.

### 3.4 Uygulanacak mimari belirlendi

Yerel geliştirme için aşağıdaki yapı seçildi:

```text
localhost sertifikası
  → Kubernetes TLS Secret
  → ayrı Nginx TLS proxy
  → mevcut oneuptime-nginx:80
```

Bu yaklaşımın nedenleri:

- Public DNS veya Let's Encrypt gerektirmez.
- Mevcut OneUptime chart dosyalarını çatallamayı gerektirmez.
- Sertifika ve private key Git'e girmez.
- OneUptime sürümü değişse bile ön proxy bağımsız kalır.
- Sertifika tarayıcı tarafından güvenilir yapılabilir.

### 3.5 OneUptime'ın ana URL ayarı HTTPS olarak değiştirildi

[values.yaml](../../../values.yaml) ve [all.yaml](../../../all.yaml) içinde şu
değişiklik yapıldı:

Önce:

```yaml
host: "localhost:8080"
httpProtocol: http
```

Sonra:

```yaml
host: "localhost:8443"
httpProtocol: https
```

Bu değişiklik önemlidir. Tarayıcı `https://localhost:8443` üzerinden açılırken
uygulama kendisini hâlâ `http://localhost:8080` olarak tanırsa API istekleri,
yönlendirmeler ve kayıt ekranı yanlış adrese gidebilir.

### 3.6 Sertifika dosyalarının Git'e girmesi engellendi

[.gitignore](../../../.gitignore) dosyasına şu kural eklendi:

```gitignore
k8s/local-tls/certs/
```

Bu dizinde aşağıdaki dosyalar üretilir:

```text
local-ca.key       Yerel CA private key; kesinlikle paylaşılmamalı
local-ca.crt       Tarayıcıya güvenilir olarak eklenen CA sertifikası
localhost.key      HTTPS sunucusunun private key'i
localhost.csr      Sertifika imzalama isteği
localhost.crt      Nginx'in sunduğu localhost sertifikası
localhost.ext      SAN ve key-usage uzantıları
local-ca.srl       CA seri numarası
```

### 3.7 Yerel CA üretildi

Bu işlemler [setup-local-https.sh](../../../scripts/setup-local-https.sh)
betiği tarafından yapıldı. Betiğin çalıştırdığı CA üretme komutu:

```bash
openssl req -x509 -newkey rsa:3072 -sha256 -nodes \
  -days 3650 \
  -keyout k8s/local-tls/certs/local-ca.key \
  -out k8s/local-tls/certs/local-ca.crt \
  -subj "/CN=OneUptime Local Development CA" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash"
```

Parametrelerin anlamı:

- `rsa:3072`: CA için 3072 bit RSA anahtarı üretir.
- `-x509`: CSR yerine doğrudan self-signed CA sertifikası üretir.
- `-sha256`: İmzada SHA-256 kullanır.
- `-nodes`: Private key'i parola ile şifrelemez. Kubernetes podunun açılışta
  parola soramayacağı için gereklidir.
- `-days 3650`: CA'yı 10 yıl geçerli yapar.
- `CA:TRUE`: Bu sertifikanın başka sertifikaları imzalayabilen bir CA olduğunu
  belirtir.
- `pathlen:0`: Bu CA'nın altında başka bir ara CA üretilememesini sağlar.

İlgili betik çıktısı:

```text
Yerel sertifika otoritesi olusturuluyor...
Generating a 3072 bit RSA private key
writing new private key to '.../k8s/local-tls/certs/local-ca.key'
```

### 3.8 `localhost` sunucu sertifikası üretildi

Önce sunucu private key'i ve CSR üretildi:

```bash
openssl req -new -newkey rsa:2048 -sha256 -nodes \
  -keyout k8s/local-tls/certs/localhost.key \
  -out k8s/local-tls/certs/localhost.csr \
  -subj "/CN=localhost"
```

Sertifika uzantıları şu şekilde oluşturuldu:

```text
authorityKeyIdentifier=keyid,issuer
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1,IP:::1
```

Buradaki en önemli satır `subjectAltName` satırıdır. Güncel tarayıcılar yalnızca
`CN=localhost` değerine bakmaz; `localhost` adının SAN alanında bulunmasını
ister.

CSR, yerel CA ile imzalandı:

```bash
openssl x509 -req \
  -in k8s/local-tls/certs/localhost.csr \
  -CA k8s/local-tls/certs/local-ca.crt \
  -CAkey k8s/local-tls/certs/local-ca.key \
  -CAcreateserial \
  -out k8s/local-tls/certs/localhost.crt \
  -days 825 \
  -sha256 \
  -extfile k8s/local-tls/certs/localhost.ext
```

Çıktı:

```text
localhost sunucu sertifikasi olusturuluyor...
Generating a 2048 bit RSA private key
Signature ok
subject=/CN=localhost
Getting CA Private Key
```

Private key izinleri ayrıca sınırlandı:

```bash
chmod 600 k8s/local-tls/certs/local-ca.key \
  k8s/local-tls/certs/localhost.key
```

İlk `localhost:8443` aşamasında üretilen sertifikanın bilgileri:

```text
subject=/CN=localhost
issuer=/CN=OneUptime Local Development CA
notBefore=Aug 17 14:13:49 2026 GMT
notAfter=Nov 19 14:13:49 2028 GMT
```

### 3.9 TLS proxy için Kubernetes kaynakları oluşturuldu

Üç ana yapılandırma dosyası eklendi:

- [kustomization.yaml](../../../k8s/local-tls/kustomization.yaml)
- [nginx.conf](../../../k8s/local-tls/nginx.conf)
- [proxy.yaml](../../../k8s/local-tls/proxy.yaml)

#### Kustomization ne yapıyor?

`kustomization.yaml`:

- `localhost.crt` ve `localhost.key` dosyalarından
  `oneuptime-local-tls` adlı Kubernetes TLS Secret üretir.
- `nginx.conf` dosyasından `oneuptime-local-tls-nginx` ConfigMap üretir.
- Deployment ve Service manifestlerini uygular.
- Secret ve ConfigMap adlarını kararlı tutar. Sertifika yenilendiğinde eski
  private key içeren hash'li Secret'ların cluster'da kalmasını önler.

#### Nginx ne yapıyor?

`nginx.conf` içindeki önemli bölüm:

```nginx
server {
  listen 8443 ssl;
  listen [::]:8443 ssl;
  server_name localhost;

  ssl_certificate /etc/nginx/tls/tls.crt;
  ssl_certificate_key /etc/nginx/tls/tls.key;
  ssl_protocols TLSv1.2 TLSv1.3;

  location / {
    proxy_pass http://oneuptime-nginx.oneuptime.svc.cluster.local:80;
    proxy_set_header Host $http_host;
    proxy_set_header X-Forwarded-Proto https;
  }
}
```

Bunun anlamı:

- Nginx podu 8443 portunda TLS dinler.
- Sertifika ve anahtarı Kubernetes Secret'tan okur.
- Yalnızca TLS 1.2 ve TLS 1.3 kabul eder.
- Çözülen isteği cluster içinde mevcut `oneuptime-nginx:80` servisine yollar.
- WebSocket bağlantıları ve uzun süren istekler için gerekli proxy başlıkları
  ve timeout değerleri de yapılandırılmıştır.

#### Deployment ne yapıyor?

Deployment:

- Tek replica çalıştırır.
- `app=oneuptime-core` etiketi sayesinde Node 1'e yerleşir.
- Sabit `nginx:1.31.3` imajını kullanır.
- TLS Secret ve Nginx ConfigMap'i read-only bağlar.
- Readiness ve liveness kontrollerini 8443 TCP portunda yapar.
- Root olmayan UID/GID `101` ile çalışır.
- Linux capability'lerini düşürür ve privilege escalation'ı kapatır.
- Küçük CPU ve bellek limitleri kullanır.

#### Service ne yapıyor?

Service, cluster içinde 443 portunu podun 8443 portuna yönlendirir:

```text
oneuptime-local-tls Service :443
  → oneuptime-local-tls pod :8443
```

Service `ClusterIP` tipindedir; doğrudan internete açılmaz.

### 3.10 Sertifika ve TLS proxy cluster'a uygulandı

İlk uygulama şu komutla yapıldı:

```bash
./scripts/setup-local-https.sh
```

Betiğin ilk uygulamada Kubernetes tarafında çalıştırdığı ana komutlar:

```bash
kubectl --context oneuptime apply -k k8s/local-tls

kubectl --context oneuptime -n oneuptime \
  rollout status deployment/oneuptime-local-tls --timeout=180s
```

İlk oluşturma çıktısı:

```text
TLS proxy Kubernetes'e uygulaniyor...
configmap/oneuptime-local-tls-nginx-... created
secret/oneuptime-local-tls-... created
service/oneuptime-local-tls created
deployment.apps/oneuptime-local-tls created
deployment "oneuptime-local-tls" successfully rolled out
```

İlk tasarımda Kustomize, ConfigMap ve Secret adlarına içerik hash'i ekliyordu.
Sertifika yenilemelerinde eski Secret'ın cluster'da kalmaması için bu tasarım
daha sonra kararlı adlara çevrildi:

```text
configmap/oneuptime-local-tls-nginx created
secret/oneuptime-local-tls created
service/oneuptime-local-tls unchanged
deployment.apps/oneuptime-local-tls configured
deployment "oneuptime-local-tls" successfully rolled out
```

Bu çalışma sırasında oluşturulan iki eski hash'li geçici kaynak daha sonra
isimleri açıkça belirtilerek silindi:

```bash
kubectl --context oneuptime -n oneuptime \
  delete configmap oneuptime-local-tls-nginx-88cbm5mt6b

kubectl --context oneuptime -n oneuptime \
  delete secret oneuptime-local-tls-ftg5ccckb7
```

Çıktı:

```text
configmap "oneuptime-local-tls-nginx-88cbm5mt6b" deleted
secret "oneuptime-local-tls-ftg5ccckb7" deleted
```

Son durumda yalnızca kararlı adlı Secret ve ConfigMap bulunmaktadır.

Kararlı ad kullanıldığında Secret içeriği aynı ad altında güncellenir. Nginx'in
yeni sertifikayı hemen belleğine alması için güncel kurulum betiğine kontrollü
restart adımı da eklendi:

```bash
kubectl --context oneuptime -n oneuptime \
  rollout restart deployment/oneuptime-local-tls
```

### 3.11 Nginx imajı sabit sürüme kilitlendi

İlk manifest yerel Minikube önbelleğinde zaten bulunan `nginx:latest` imajını
kullanıyordu. Çalışan proxy yanıtında şu sürüm görüldü:

```text
Server: nginx/1.31.3
```

İleride `latest` etiketi değişip beklenmeyen bir rollout oluşmaması için manifest
şu sürüme sabitlendi:

```yaml
image: nginx:1.31.3
```

Değişiklik yeniden uygulandı:

```bash
kubectl --context oneuptime apply -k k8s/local-tls

kubectl --context oneuptime -n oneuptime \
  rollout status deployment/oneuptime-local-tls --timeout=180s
```

Çıktı:

```text
deployment.apps/oneuptime-local-tls configured
deployment "oneuptime-local-tls" successfully rolled out
nginx:1.31.3
```

### 3.12 OneUptime Helm release HTTPS adresiyle güncellendi

TLS proxy'yi kurmak tek başına yeterli değildir. OneUptime'ın ürettiği API ve
yönlendirme URL'lerinin de HTTPS adresini kullanması gerekir.

Mevcut Probe Key ve diğer çalışan release ayarlarını korumak için
`--reuse-values` kullanıldı:

```bash
helm upgrade oneuptime ./oneuptime \
  --kube-context oneuptime \
  --namespace oneuptime \
  --reuse-values \
  --set-string host=localhost:8443 \
  --set-string httpProtocol=https \
  --wait \
  --timeout 15m
```

Önemli çıktı:

```text
Release "oneuptime" has been upgraded. Happy Helming!
NAME: oneuptime
NAMESPACE: oneuptime
STATUS: deployed
REVISION: 4
DESCRIPTION: Upgrade complete
```

Helm değerleri ayrıca kontrol edildi:

```bash
helm --kube-context oneuptime -n oneuptime \
  get values oneuptime -o json | \
  jq '{host, httpProtocol}'
```

Çıktı:

```json
{
  "host": "localhost:8443",
  "httpProtocol": "https"
}
```

### 3.13 Yerel CA macOS güven deposuna eklendi

Sertifika CA dosyasıyla doğrulanabilir olsa da tarayıcının uyarı göstermemesi
için CA'nın macOS trust store'a eklenmesi gerekir.

Kullanıcı anahtar zincirinin yolu önce okundu:

```bash
security default-keychain -d user
```

Çıktı:

```text
"/Users/macbook/Library/Keychains/login.keychain-db"
```

İlk denemede `security add-trusted-cert` komutuna `-d` seçeneği verilmişti.
Komut başarılı oldu, fakat macOS `security` yardımında `-d` seçeneğinin admin
trust store anlamına geldiği görüldü:

```bash
man security | col -b | rg -A22 -B3 'add-trusted-cert'
```

İlgili yardım çıktısı:

```text
-d    Add to admin cert store; default is user.
```

Amaç yalnızca mevcut macOS kullanıcısı için güven eklemek olduğu için ilk kayıt
kaldırıldı ve kullanıcı kapsamında yeniden eklendi:

```bash
security remove-trusted-cert -d \
  /Users/macbook/Desktop/oneuptime/k8s/local-tls/certs/local-ca.crt

security add-trusted-cert \
  -r trustRoot \
  -k /Users/macbook/Library/Keychains/login.keychain-db \
  /Users/macbook/Desktop/oneuptime/k8s/local-tls/certs/local-ca.crt
```

Her iki komut da exit code `0` ile tamamlandı. macOS bu işlem sırasında kullanıcı
parolası veya Touch ID isteyebilir.

Son [setup-local-https.sh](../../../scripts/setup-local-https.sh) betiğinde
doğrudan doğru kullanıcı-scope komutu bulunur; admin-scope komutu artık yoktur.

### 3.14 HTTPS port-forward başlatıldı

Tekrar kullanılabilir olması için ayrı bir betik eklendi:

[port-forward-https.sh](../../../scripts/port-forward-https.sh)

Betiğin çalıştırdığı komut:

```bash
kubectl --context oneuptime \
  --namespace oneuptime \
  port-forward service/oneuptime-local-tls 8443:443
```

Çalıştırma:

```bash
./scripts/port-forward-https.sh
```

Çıktı:

```text
Forwarding from 127.0.0.1:8443 -> 8443
Forwarding from [::1]:8443 -> 8443
```

Burada soldaki `8443` Mac üzerindeki port, sağdaki `8443` ise Service'in
`targetPort` ile çözdüğü pod portudur. Kubernetes Service dışarıya 443 sunar;
port-forward komutundaki `8443:443` eşlemesi Service'in 443 portunu seçer.

Deployment rollout sırasında bağlı olunan eski pod silindiği için port-forward
süreci iki kez kapandı. Her rollout sonrasında aynı betik yeniden çalıştırıldı.
Bu normal Kubernetes davranışıdır.

### 3.15 Özel DNS adı eklendi ve URL'den port kaldırıldı

İlk HTTPS kurulumu `https://localhost:8443` ile doğrulandıktan sonra son kullanıcı
adresi şu şekilde değiştirildi:

```text
https://oneuptime.furkan.test
```

`.test`, IANA tarafından test amacıyla ayrılmış özel kullanım alanıdır.
`oneuptime.com` ise OneUptime'ın gerçek public alan adı olduğu için yerel
`/etc/hosts` kaydıyla ezilmedi.

Mac'in bu adı loopback adresine çözmesi için aşağıdaki kayıt eklendi:

```text
127.0.0.1 oneuptime.furkan.test
```

DNS çözümlemesi kontrol edildi:

```bash
dscacheutil -q host -a name oneuptime.furkan.test
```

Çıktı:

```text
name: oneuptime.furkan.test
ip_address: 127.0.0.1
```

Kurulum betiği bu kaydı idempotent olarak kontrol eder. Kayıt yoksa çalıştırdığı
komutun eşdeğeri şudur:

```bash
printf '127.0.0.1\toneuptime.furkan.test\n' | \
  sudo tee -a /etc/hosts >/dev/null

sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

Sertifika üretimi de güncellendi. Yeni sertifikanın SAN listesi:

```text
DNS:oneuptime.furkan.test
DNS:localhost
IP:127.0.0.1
IP:::1
```

OneUptime'ın canonical host değeri port olmadan değiştirildi:

```yaml
host: "oneuptime.furkan.test"
httpProtocol: https
```

HTTPS'nin varsayılan portu 443 olduğu için tarayıcı URL'de port göstermez.
macOS üzerinde 443 ayrıcalıklı bir porttur. Normal kullanıcıyla yapılan ilk
bağlanma testi şu hatayı verdi:

```text
Unable to listen on port 443
bind: permission denied
error: unable to listen on any of the requested ports
```

Bu nedenle güncel port-forward betiği 80 ve 443 kullanılırken `sudo` çağırır ve açık
kullanıcı kubeconfig dosyasını root olarak çalışan `kubectl` komutuna verir:

```bash
sudo /opt/homebrew/bin/kubectl \
  --kubeconfig /Users/macbook/.kube/config \
  --context oneuptime \
  --namespace oneuptime \
  port-forward service/oneuptime-local-tls 80:80 443:443
```

TLS proxy'nin 8080 numaralı container portunda çalışan ikinci server bloğu,
HTTP isteklerini kalıcı yönlendirmeyle HTTPS'e taşır:

```nginx
server {
  listen 8080;
  server_name oneuptime.furkan.test;
  return 308 https://oneuptime.furkan.test$request_uri;
}
```

Bu terminal açık kaldığı sürece aşağıdaki adres portsuz çalışır:

```text
https://oneuptime.furkan.test
```

Yeni sertifika ve Helm rollout'u uygulandıktan sonra alınan güncel sertifika
çıktısı:

```text
subject=/CN=oneuptime.furkan.test
issuer=/CN=OneUptime Local Development CA
notBefore=Aug 17 14:57:40 2026 GMT
notAfter=Nov 19 14:57:40 2028 GMT
```

Helm güncellemesi bu ikinci aşamada revision 5 olarak tamamlandı:

```text
Release "oneuptime" has been upgraded. Happy Helming!
STATUS: deployed
REVISION: 5
```

### 3.16 DNS ve portsuz alan adı aşamasında karşılaşılan problemler

Bu aşamada yalnızca başarılı sonuca değil, başarısız denemelere de bakıldı.
Karşılaşılan sorunların özeti:

| Deneme | Gerçek belirti/çıktı | Neden | Düzeltme |
|---|---|---|---|
| `/etc/hosts` kaydını ilk AppleScript komutuyla ekleme | `syntax error: A real number can’t go after this "\\". (-2740)` | AppleScript içine gömülen shell komutunda kaçış karakterleri hatalıydı | `/etc/hosts` dosyasının değişmediği doğrulandı; idempotent geçici shell helper ile kayıt eklendi ve helper silindi |
| Yönetici yetkisi gerektiren adım | Terminal çıktı üretmeden macOS onayını bekledi | `/etc/hosts` ve düşük TCP portları yönetici yetkisi gerektirir | Açılan macOS yetki penceresi onaylandı; betik yetki isteneceğini açıkça yazacak hale getirildi |
| `443:443` port-forward'ını normal kullanıcıyla başlatma | `bind: permission denied` ve `unable to listen on any of the requested ports` | macOS'ta 1024'ten küçük portlar ayrıcalıklıdır | `sudo kubectl`, normal kullanıcının açık `--kubeconfig` yolu ile çalıştırıldı |
| İki portlu yeni port-forward'ı başlatma | `80` açıldı fakat HTTPS connection reset/refused verdi | Önceki root port-forward süreci `443` portunu tutuyordu | `ps` ve `netstat` ile bu çalışma sırasında açılmış eski PID `62030` bulundu, yalnızca o süreç kapatıldı ve `80/443` birlikte yeniden başlatıldı |
| Query string içeren HTTP redirect testi | `zsh:1: no matches found: http://oneuptime.furkan.test/test-path?check=1` | zsh, tırnaksız `?` karakterini glob kabul etti | URL tek tırnak içine alındı |
| TLS proxy rollout'u | `lost connection to pod` | Port-forward'ın bağlı olduğu eski pod rollout sırasında silindi | Rollout bittikten sonra port-forward yeniden başlatıldı |
| Başka bir cihazdan aynı adı kullanma beklentisi | Alan adı diğer cihazda çözümlenmez | `/etc/hosts` ortak DNS değil, yalnızca bu Mac'e ait yerel kayıttır | Tek makine kapsamı korundu; diğer cihazlar için ayrı DNS/hosts, LAN listener ve CA güveni gerektiği dokümante edildi |
| Alan adı seçimi | `.furkan` ve `oneuptime.com` seçenekleri güvenli değildi | `.furkan` ayrılmış bir test son eki değildir; `oneuptime.com` gerçek public alandır | IANA özel kullanım alanı altındaki `oneuptime.furkan.test` seçildi |

`/etc/hosts` kaydı DNS sunucusu değildir. macOS'un yerel ad çözümleme
kaynaklarından biridir ve dış DNS'e kayıt göndermez. Uçtan uca yolun ve her
hata katmanının ayrıntısı
[LOCAL_DNS_TLS_TRAFFIC.md](LOCAL_DNS_TLS_TRAFFIC.md) dosyasındadır.

## 4. Yapılan doğrulamalar ve gerçek sonuçlar

### 4.1 Çıplak alan adının HTTPS'e yönlendirilmesi

Tarayıcı davranışını temsil etmek için önce HTTP adresine gidildi ve redirect
takip edildi:

```bash
curl -sS -L -o /dev/null \
  -w 'Bare HTTP redirect final -> %{url_effective} HTTP %{http_code}\n' \
  http://oneuptime.furkan.test/
```

Çıktı:

```text
Bare HTTP redirect final -> https://oneuptime.furkan.test/ HTTP 200
```

Redirect yanıtı tek başına da kontrol edildi:

```text
HTTP/1.1 308 Permanent Redirect
Location: https://oneuptime.furkan.test/test-path?check=1
```

### 4.2 Tarayıcı güveni dahil HTTPS ana sayfa kontrolü

`--cacert` vermeden istek gönderildi. Bu, yalnızca sertifikanın çalışmasını
değil, macOS güven ayarının da devrede olduğunu kontrol eder:

```bash
curl -sS -o /dev/null \
  -w 'HTTPS home -> HTTP %{http_code}\n' \
  --max-time 20 \
  https://oneuptime.furkan.test/
```

Çıktı:

```text
HTTPS home -> HTTP 200
```

İlk ayrıntılı yanıtta görülen başlıklar:

```text
HTTP/1.1 200 OK
Server: nginx/1.31.3
Content-Type: text/html; charset=utf-8
Content-Length: 17444
```

### 4.3 OneUptime canlılık endpoint'i kontrolü

```bash
curl -sS -o /dev/null \
  -w 'HTTPS live -> HTTP %{http_code}\n' \
  --max-time 20 \
  https://oneuptime.furkan.test/status/live
```

Çıktı:

```text
HTTPS live -> HTTP 200
```

### 4.4 Sertifika zinciri kontrolü

```bash
openssl verify \
  -CAfile k8s/local-tls/certs/local-ca.crt \
  k8s/local-tls/certs/localhost.crt
```

Çıktı:

```text
k8s/local-tls/certs/localhost.crt: OK
```

Bu, `localhost.crt` sertifikasının projede üretilen `local-ca.crt` tarafından
geçerli biçimde imzalandığını gösterir.

### 4.5 Sertifika hostname/SAN kontrolü

macOS ile gelen LibreSSL'de `openssl x509 -ext` seçeneği bulunmadığı için
uyumlu olan `-text` komutu kullanıldı:

```bash
openssl x509 \
  -in k8s/local-tls/certs/localhost.crt \
  -noout -subject -issuer -dates -text | \
  grep -A1 'Subject Alternative Name'
```

Çıktı:

```text
X509v3 Subject Alternative Name:
    DNS:oneuptime.furkan.test, DNS:localhost,
    IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1
```

Son IPv6 değeri `::1` adresinin açık yazımıdır.

### 4.6 TLS 1.2 kontrolü

```bash
openssl s_client \
  -connect oneuptime.furkan.test:443 \
  -servername oneuptime.furkan.test \
  -CAfile k8s/local-tls/certs/local-ca.crt \
  -tls1_2 </dev/null 2>&1 | \
  grep -E 'Protocol|Verify return code'
```

Çıktı:

```text
Protocol  : TLSv1.2
Verify return code: 0 (ok)
```

### 4.7 TLS 1.3 kontrolü

Önce `curl` ile TLS 1.3'ü zorlamak denendi:

```bash
curl --cacert k8s/local-tls/certs/local-ca.crt \
  --tlsv1.3 --tls-max 1.3 \
  https://oneuptime.furkan.test/
```

Mac üzerindeki `curl`, TLS için SecureTransport ile derlendiğinden bu seçenek
desteklenmedi:

```text
curl: (4) A requested feature, protocol or option was not found built-in
```

Bu bir sunucu/TLS hatası değildi; yerel `curl` binary'sinin özellik farkıydı.
Bu nedenle TLS 1.3 görüşmesi OpenSSL istemcisiyle test edildi:

```bash
openssl s_client \
  -connect oneuptime.furkan.test:443 \
  -servername oneuptime.furkan.test \
  -CAfile k8s/local-tls/certs/local-ca.crt \
  -tls1_3 </dev/null 2>&1 | \
  grep -E 'Protocol|Verify return code'
```

Çıktı:

```text
Protocol  : TLSv1.3
Verify return code: 0 (ok)
```

`Verify return code: 0 (ok)`, sertifika zincirinin o TLS görüşmesinde başarıyla
doğrulandığı anlamına gelir.

### 4.8 TLS proxy Kubernetes kaynakları kontrolü

```bash
kubectl --context oneuptime -n oneuptime get \
  deployment,service,configmap,secret \
  -l app.kubernetes.io/name=oneuptime-local-tls \
  -o name
```

Çıktı:

```text
deployment.apps/oneuptime-local-tls
service/oneuptime-local-tls
configmap/oneuptime-local-tls-nginx
secret/oneuptime-local-tls
```

Deployment ayrıntısı:

```bash
kubectl --context oneuptime -n oneuptime \
  get deployment oneuptime-local-tls \
  -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image,NODE_SELECTOR:.spec.template.spec.nodeSelector.app'
```

Çıktı:

```text
NAME                  READY   IMAGE          NODE_SELECTOR
oneuptime-local-tls   1       nginx:1.31.3   oneuptime-core
```

Service ayrıntısı:

```text
NAME                  TYPE        CLUSTER-IP      PORT(S)
oneuptime-local-tls   ClusterIP   10.97.179.200   80/TCP,443/TCP
```

Proxy loglarında official Nginx entrypoint'in `/etc/nginx/conf.d/default.conf`
dosyasını değiştiremediğine dair aşağıdaki uyarı görüldü:

```text
can not modify /etc/nginx/conf.d/default.conf (read-only file system?)
Configuration complete; ready for start up
```

Bu uyarı beklenir: container root olmayan kullanıcıyla çalışır ve bizim
`nginx.conf` dosyamız read-only mount edilir. Hemen arkasından
`Configuration complete; ready for start up` yazdığı, readiness başarılı olduğu
ve HTTPS `200` döndüğü için çalışma hatası değildir.

### 4.9 OneUptime pod sağlığı kontrolü

İlgili podlar kontrol edildi:

```text
oneuptime-app-...          true   Running
oneuptime-local-tls-...    true   Running
oneuptime-nginx-...        true   Running
oneuptime-probe-one-...    true   Running
oneuptime-probe-two-...    true   Running
```

Hem ana uygulama hem iki probe hem de yeni TLS proxy sağlıklı durumdadır.

### 4.10 Helm release son durumu

```bash
helm --kube-context oneuptime -n oneuptime \
  status oneuptime -o json | \
  jq '{status:.info.status,revision:.version}'
```

Çıktı:

```json
{
  "status": "deployed",
  "revision": 5
}
```

### 4.11 Dosya ve betik biçim kontrolleri

Shell betiklerinin sözdizimi kontrol edildi:

```bash
bash -n scripts/setup-local-https.sh scripts/port-forward-https.sh
```

Git diff içinde hatalı boşluk veya conflict marker kontrolü yapıldı:

```bash
git diff --check
```

Her iki komut da çıktı üretmeden exit code `0` ile tamamlandı. Bu, shell
sözdiziminde ve Git whitespace kontrolünde hata bulunmadığını gösterir.

## 5. Eklenen ve değiştirilen dosyalar

### Yeni dosyalar

| Dosya | Görevi |
|---|---|
| `k8s/local-tls/kustomization.yaml` | ConfigMap ve TLS Secret üretir, manifestleri birleştirir |
| `k8s/local-tls/nginx.conf` | TLS 1.2/1.3 ve reverse proxy ayarları |
| `k8s/local-tls/proxy.yaml` | Nginx Deployment ve ClusterIP Service |
| `scripts/setup-local-https.sh` | CA/sertifika üretimi, trust, K8s apply ve Helm upgrade |
| `scripts/port-forward-https.sh` | Yerel 80 ve 443 portlarını redirect/TLS Service'e iletir |
| `docs/tr/kurulum/LOCAL_HTTPS.md` | Bu uygulama günlüğü ve işletim rehberi |
| `docs/tr/kurulum/LOCAL_DNS_TLS_TRAFFIC.md` | DNS/hosts'tan OneUptime uygulamasına kadar uçtan uca trafik yolu ve akış şemaları |

### Değiştirilen ana ayarlar

| Dosya | Değişiklik |
|---|---|
| `values.yaml` | `host: oneuptime.furkan.test`, `httpProtocol: https` |
| `all.yaml` | Aynı HTTPS host/protokol ayarı |
| `.gitignore` | Üretilen sertifika/private key dizini hariç tutuldu |
| `SETTING_UP.md` | Kurulum akışı HTTPS olacak şekilde güncellendi |
| `docs/tr/kurulum/MINIKUBE_START_STOP.md` | Yeniden başlatma ve port-forward adımları HTTPS yapıldı |
| `docs/tr/kurulum/SELFHOSTED_KURULUM.md` | Yerel erişim adresi ve TLS kurulum adımı güncellendi |
| `docs/tr/instructions/04-public-status-page.md` | Status Page erişimi HTTPS yapıldı |

## 6. Bundan sonra günlük kullanım

### Cluster zaten çalışıyorsa

Ayrı bir terminal açın:

```bash
cd /Users/macbook/Desktop/oneuptime
./scripts/port-forward-https.sh
```

443 ayrıcalıklı port olduğu için betik macOS kullanıcı parolasını `sudo`
üzerinden isteyebilir. Parola terminale yazılırken karakter görünmemesi normaldir.
Port-forward terminalini açık bırakın; kapatmak için aynı terminalde `Ctrl+C`
kullanın.

Terminali açık bırakın ve tarayıcıda şuraya gidin:

```text
https://oneuptime.furkan.test
```

### Minikube durdurulup yeniden başlatıldıysa

```bash
minikube start -p oneuptime
cd /Users/macbook/Desktop/oneuptime
./scripts/port-forward-https.sh
```

TLS Deployment, Service, ConfigMap ve Secret Minikube profili içinde korunur;
normal `minikube stop/start` işleminde sertifikayı yeniden üretmek gerekmez.

### Minikube profili tamamen silindiyse

OneUptime kurulumundan ve podlar sağlıklı olduktan sonra:

```bash
cd /Users/macbook/Desktop/oneuptime
./scripts/setup-local-https.sh --trust
```

Betiğin yaptığı işler idempotent olacak şekilde tasarlanmıştır:

- Geçerli sertifika dosyası yeni DNS adını içeriyorsa yeniden üretmez.
- Kubernetes kaynaklarını create/update eder.
- TLS proxy'yi yeni sertifikayı yüklemesi için yeniden başlatır.
- Helm release'in mevcut değerlerini koruyup host/protokolü HTTPS yapar.

## 7. Elle doğrulama komutları

HTTPS yanıtı:

```bash
curl -I https://oneuptime.furkan.test
```

CA dosyasını açıkça vererek doğrulama:

```bash
curl --cacert k8s/local-tls/certs/local-ca.crt \
  -I https://oneuptime.furkan.test
```

Sertifika bilgileri:

```bash
openssl x509 \
  -in k8s/local-tls/certs/localhost.crt \
  -noout -subject -issuer -dates -fingerprint -sha256
```

Kubernetes kaynakları:

```bash
kubectl --context oneuptime -n oneuptime get \
  deployment,service,configmap,secret \
  -l app.kubernetes.io/name=oneuptime-local-tls
```

TLS proxy logları:

```bash
kubectl --context oneuptime -n oneuptime \
  logs deployment/oneuptime-local-tls --tail=100
```

## 8. Sorun giderme

### `connection refused` alınıyorsa

Önce port-forward terminalini kontrol edin. Çalışmıyorsa:

```bash
./scripts/port-forward-https.sh
```

Ardından pod ve Service'i kontrol edin:

```bash
kubectl --context oneuptime -n oneuptime \
  get pod,service -l app.kubernetes.io/name=oneuptime-local-tls
```

### Port-forward `lost connection to pod` diyerek kapanıyorsa

Bu genellikle Deployment rollout sırasında bağlı olunan podun silindiği anlamına
gelir. Rollout bittikten sonra port-forward betiğini yeniden çalıştırın:

```bash
kubectl --context oneuptime -n oneuptime \
  rollout status deployment/oneuptime-local-tls

./scripts/port-forward-https.sh
```

### Tarayıcı sertifika uyarısı gösteriyorsa

1. Adresin tam olarak `https://oneuptime.furkan.test` olduğunu doğrulayın.
2. Betiği bir kez `--trust` ile çalıştırın:

   ```bash
   ./scripts/setup-local-https.sh --trust
   ```

3. Tarayıcıyı tamamen kapatıp yeniden açın.
4. Sertifika yenilendiyse macOS **Keychain Access** içinde eski
   `OneUptime Local Development CA` kaydını kaldırıp `--trust` adımını yeniden
   çalıştırın.

### TLS çalışıyor fakat OneUptime `Network Error` gösteriyorsa

Helm değerlerini kontrol edin:

```bash
helm --kube-context oneuptime -n oneuptime \
  get values oneuptime -o json | \
  jq '{host, httpProtocol}'
```

Beklenen değer:

```json
{
  "host": "oneuptime.furkan.test",
  "httpProtocol": "https"
}
```

Farklıysa düzeltin:

```bash
helm upgrade oneuptime ./oneuptime \
  --kube-context oneuptime \
  -n oneuptime \
  --reuse-values \
  --set-string host=oneuptime.furkan.test \
  --set-string httpProtocol=https \
  --wait \
  --timeout 15m
```

### Port 443 kullanımda ise

Portu hangi process'in kullandığını kontrol edin:

```bash
lsof -nP -iTCP:443 -sTCP:LISTEN
```

Eski bir `kubectl port-forward` çalışıyorsa onu kullanabilir veya ilgili
terminalde `Ctrl+C` ile kapatabilirsiniz.

Farklı bir yerel port kullanmak isterseniz OneUptime'ın `host` değeri de aynı
portla güncellenmelidir. Örneğin 9443:

```bash
helm upgrade oneuptime ./oneuptime \
  --kube-context oneuptime \
  -n oneuptime \
  --reuse-values \
  --set-string host=oneuptime.furkan.test:9443 \
  --set-string httpProtocol=https

LOCAL_HTTPS_PORT=9443 ./scripts/port-forward-https.sh
```

Sertifika porttan bağımsızdır; hostname `oneuptime.furkan.test` kaldığı sürece yeniden
üretilmesi gerekmez.

## 9. Güvenlik notları

- `local-ca.key` ele geçirilirse bu CA adına yeni sertifikalar üretilebilir.
  Dosyayı paylaşmayın.
- `localhost.key` yalnızca bu yerel HTTPS sunucusu içindir; yine de Git'e veya
  mesajlaşma kanallarına koymayın.
- TLS Secret'ın içeriğini terminale yazdırmak için
  `kubectl get secret ... -o yaml` kullanmayın; base64 private key ekrana çıkar.
- Bu yapılandırma yerel geliştirme içindir. Üretimde gerçek DNS, kurumsal/public
  CA, güvenli secret yönetimi, LoadBalancer/Ingress ve sertifika yenileme
  politikası kullanılmalıdır.
- Yerel HTTPS eklenmesi, cluster içindeki bütün servisler arası trafiğin otomatik
  olarak TLS olduğu anlamına gelmez. Bu çözüm tarayıcıdan OneUptime girişine
  kadar olan bağlantıyı korur.

## 10. Resmî kaynaklar

- [OneUptime örnek TLS yapılandırması](https://github.com/OneUptime/oneuptime/blob/master/config.example.env)
- [OneUptime self-hosted mimarisi](https://oneuptime.com/docs/en/self-hosted/architecture)
- [Kubernetes Secret](https://kubernetes.io/docs/concepts/configuration/secret/)
- [kubectl port-forward](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/)
