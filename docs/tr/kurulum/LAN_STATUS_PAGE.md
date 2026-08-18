# Status Page'i Wi-Fi Ağına Açma

Gerçek uygulama sırasında çalıştırılan terminal komutları, çıktıları, alınan
kararlar ve bütün dosyaların ayrıntılı açıklaması için
[LAN Status Page Uygulama Günlüğü](LAN_STATUS_PAGE_UYGULAMA_GUNLUGU.md)
belgesine bakın.

Bu yapılandırma yalnızca aşağıdaki Status Page'i yerel Wi-Fi ağına açar:

```text
/status-page/d379ced1-bc31-4acc-8252-8f1fb571e5b6
```

OneUptime dashboard, admin, identity, telemetry ve genel `/api` yolları bu
listener üzerinden yayınlanmaz. Mevcut `https://oneuptime.furkan.test` erişimi
aynen devam eder.

## 1. İzole proxy'yi kurma

```bash
kubectl --context oneuptime apply -k k8s/lan-status
kubectl --context oneuptime -n oneuptime \
  rollout status deployment/oneuptime-lan-status --timeout=180s
```

## 2. Wi-Fi adresinde port-forward başlatma

Ayrı bir terminal açın ve terminali açık bırakın:

```bash
./scripts/port-forward-status-page-lan.sh
```

Betiğin varsayılanları:

- Wi-Fi arayüzü: `en0`
- LAN portu: `80`
- LAN adresi: `ipconfig getifaddr en0` çıktısı
- Yerel DNS adı: `furkanstatus.test`

Port 80 ayrıcalıklı olduğu için macOS parolası istenir. Betik `0.0.0.0`
yerine yalnızca güncel Wi-Fi IP adresinde dinler. Başka bir arayüz veya port
için:

```bash
WIFI_INTERFACE=en1 LOCAL_HTTP_PORT=8080 \
  ./scripts/port-forward-status-page-lan.sh
```

## 3. `furkanstatus.test` için router DNS kaydı

`.test` alanı Bonjour/mDNS tarafından yayınlanmaz. Ağdaki bütün cihazların
`http://furkanstatus.test` adresini kullanabilmesi için router'ın yerel DNS
kaydını oluşturması gerekir. Nginx `server_name` ayarı tek başına DNS kaydı
oluşturmaz.

Router'ın yerel DNS/DHCP bölümünde aşağıdaki host (A) kaydını oluşturun:

```text
furkanstatus.test -> <Mac'in Wi-Fi IPv4 adresi>
```

Bu ağda router ve DNS sunucusu `192.168.5.1` olarak doğrulandı. Router yönetim
arayüzünde **Local DNS**, **DNS Host Override**, **Static DNS** veya benzer adlı
bölüm kullanılmalıdır. Yalnızca DHCP hostname alanı varsa router kaydı
`furkanstatus.lan` olarak oluşturabilir; `.test` için tam alan adı (FQDN) host
override desteği gerekir.

Bu kurulum sırasında doğrulanan adres `192.168.6.119` idi. DHCP adresi
değişebileceği için router üzerinde bu Mac için DHCP reservation tanımlamak
gerekir.

DNS önbelleği yenilendikten sonra ağdaki cihazlar şu adresi açabilir:

```text
http://furkanstatus.test
```

Kısa adres hedef Status Page'e yönlenir. DNS henüz hazır değilken doğrudan IP
ile test edilebilir:

```text
http://192.168.6.119/status-page/d379ced1-bc31-4acc-8252-8f1fb571e5b6
```

## Güvenlik sınırı

İzin verilen yüzey:

- Hedef Status Page ve onun alt yolları
- Status Page'in ortak statik dosyaları
- OneUptime'ın ayrı public `status-page-api` yolu

Diğer tüm yollar `404` döndürür. Özellikle `/dashboard`, `/admin`, `/identity`,
`/api`, `/telemetry` ve `/` altındaki diğer uygulama yolları upstream'e
iletilmez.

LAN listener HTTP kullanır. Böylece ağdaki her cihaza proje CA sertifikasını
yüklemek gerekmez. Hassas veya güvenilmeyen bir ağda HTTPS istenirse sertifikaya
`furkanstatus.test` SAN'ı eklenmeli ve yerel CA her istemciye güvenilir olarak
kurulmalıdır.
