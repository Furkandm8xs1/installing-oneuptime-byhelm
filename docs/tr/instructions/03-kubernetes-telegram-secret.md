# Aşama 3 — Kubernetes Telegram Secret Oluşturma

## Amaç

Node 2 üzerinde çalışacak bağımsız watchdog'un Telegram bilgilerini Kubernetes
Secret üzerinden almasını sağlamak. OneUptime Global Variables yalnızca OneUptime
Workflow'ları içindir; watchdog ayrı bir Kubernetes süreci olduğu için aynı
değerlerin Kubernetes Secret içinde de bulunması gerekir.

## 3.1 Ön koşulları doğrulama

Doğru Minikube profili ve namespace üzerinde çalışıldığını kontrol edin:

```bash
kubectl config current-context
kubectl get namespace oneuptime
```

Beklenen context adı `oneuptime`, namespace adı ise `oneuptime` olmalıdır.

Beklenen terminal çıktısı:

```text
oneuptime
NAME        STATUS   AGE
oneuptime   Active   <age>
```

## 3.2 Secret'ı güvenli ve etkileşimli oluşturma

Gerçek değerleri doğrudan komuta yazmak kabuk geçmişinde bırakabilir. Bunun
yerine değerleri gizli ve geçici değişkenlerle okuyun:

```bash
read -s "TELEGRAM_BOT_TOKEN?Telegram bot token: " TELEGRAM_BOT_TOKEN
echo
read -s "TELEGRAM_CHAT_ID?Telegram Chat ID: " TELEGRAM_CHAT_ID
echo

kubectl create secret generic oneuptime-watchdog-telegram \
  --namespace=oneuptime \
  --from-literal=TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}" \
  --from-literal=TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}" \
  --dry-run=client \
  --output=yaml | kubectl apply -f -

unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID
```

`--dry-run=client --output=yaml | kubectl apply -f -` biçimi komutu hem ilk
kurulumda hem de secret güncellemesinde kullanılabilir hale getirir. Üretilen
YAML ekrana veya dosyaya kaydedilmemelidir.

İlk oluşturmadaki beklenen terminal çıktısı:

```text
secret/oneuptime-watchdog-telegram created
```

Secret daha önce mevcutsa beklenen çıktı:

```text
secret/oneuptime-watchdog-telegram configured
```

## 3.3 Secret metadata ve anahtarlarını doğrulama

İçeriği göstermeden Secret'ın varlığını kontrol edin:

```bash
kubectl get secret oneuptime-watchdog-telegram \
  --namespace=oneuptime
```

`DATA` sütununda `2` görülmelidir. Yalnızca anahtar adlarını listelemek için:

```text
NAME                            TYPE     DATA   AGE
oneuptime-watchdog-telegram     Opaque   2      <age>
```

```bash
kubectl get secret oneuptime-watchdog-telegram \
  --namespace=oneuptime \
  --output=go-template='{{range $key, $value := .data}}{{printf "%s\n" $key}}{{end}}'
```

Beklenen anahtarlar:

```text
TELEGRAM_BOT_TOKEN
TELEGRAM_CHAT_ID
```

## 3.4 Kaçınılması gereken işlemler

Aşağıdaki işlemler gerçek secret değerlerini görünür hale getirebileceği için
kullanılmamalıdır:

- Gerçek değerleri doğrudan `--from-literal=...` içine yazarak komutu geçmişe
  kaydetmek
- `kubectl get secret ... -o yaml` çıktısını paylaşmak
- Base64 kodlanmış değeri güvenli şifreleme sanmak
- Secret YAML'ını Git deposuna eklemek
- Secret içeriklerinin göründüğü ekran görüntüsü almak

## Kabul kontrolü

- [ ] Secret `oneuptime` namespace'inde oluşturuldu.
- [ ] Secret adı `oneuptime-watchdog-telegram`.
- [ ] `DATA` sütunu `2` gösteriyor.
- [ ] `TELEGRAM_BOT_TOKEN` ve `TELEGRAM_CHAT_ID` anahtarları mevcut.
- [ ] Gerçek değerler terminal çıktısında, dosyada veya Git'te bulunmuyor.

Bu aşamadan sonra Kubernetes Secret, watchdog Deployment tarafından
`secretKeyRef` ile kullanılmaya hazırdır.
