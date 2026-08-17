# OneUptime Minikube Profilini Durdurma ve Yeniden Başlatma

Bu belge, mevcut `oneuptime` Minikube profilini veri kaybetmeden durdurmak ve
daha sonra yeniden başlatmak için kullanılacak operasyon sırasını açıklar.

> Bu akış mevcut bir cluster içindir. Profil daha önce silindiyse bu belgeyle
> devam etmeyin; [README.md](README.md) içindeki sıfırdan kurulum adımlarını
> uygulayın.

## `stop` ve `delete` arasındaki fark

| Komut | Sonuç |
|---|---|
| `minikube stop -p oneuptime` | Node container'larını durdurur; Kubernetes nesnelerini, Helm release'ini, PVC'leri, kullanıcı hesabını, monitörleri ve Probe Key'leri korur. |
| `minikube delete -p oneuptime` | `oneuptime` profilini ve profile ait tüm cluster verilerini siler. Yeniden kurulum, yeni hesap ve yeni Probe Key gerekir. |
| `helm uninstall oneuptime -n oneuptime` | Yalnızca Helm release'ini kaldırır. Normal durdurma/başlatma işlemi için kullanılmaz. |

Günlük kullanımda yalnızca `stop` ve mevcut profili yeniden açmak için `start`
kullanılmalıdır.

## 1. Cluster'ı güvenli biçimde durdurma

### 1.1 Port-forward işlemini kapatın

`kubectl port-forward` çalışan terminalde `Ctrl+C` tuşlarına basın. Port-forward
cluster'ın bir parçası değildir ve Minikube yeniden başladığında ayrıca tekrar
başlatılmalıdır.

### 1.2 İsteğe bağlı son durum kontrolü

```bash
kubectl config use-context oneuptime
kubectl get nodes
kubectl get pods -n oneuptime -o wide
```

Bu kontrol zorunlu değildir; durdurma öncesindeki durumu kaydetmek ve daha sonra
karşılaştırmak için faydalıdır.

### 1.3 Yalnızca OneUptime profilini durdurun

```bash
minikube stop -p oneuptime
```

`--all` kullanmayın. Diğer Minikube profillerinin durdurulmasına gerek yoktur.

### 1.4 Durumu doğrulayın

```bash
minikube status -p oneuptime
minikube profile list
```

`oneuptime` profilinin listede kalması, profilin silinmediğini gösterir. Node,
kubelet ve API sunucusunun `Stopped` görünmesi beklenir.

## 2. Mevcut profili yeniden başlatma

### 2.1 Docker Desktop'ı başlatın

Bu proje Docker sürücüsünü kullandığı için önce Docker Desktop'ın tamamen
çalışır durumda olduğundan emin olun.

### 2.2 Mevcut profili açın

```bash
minikube start -p oneuptime
kubectl config use-context oneuptime
```

Mevcut profili açarken yeniden `--nodes`, `--memory` veya `--cpus` vermek
gerekmez; Minikube profilin kayıtlı ayarlarını kullanır.

> `Profile "oneuptime" not found` mesajı alınırsa profil durdurulmamış, silinmiş
> demektir. Bu durumda [README.md](README.md) içindeki iki node'lu sıfırdan
> kurulum akışını uygulayın.

## 3. Start işleminden sonra yapılması gerekenler

### 3.1 Node'ların hazır olmasını bekleyin

```bash
kubectl get nodes -w
```

İki node da `Ready` olduktan sonra `Ctrl+C` ile izlemeyi kapatın. Beklenen node
adları:

```text
oneuptime
oneuptime-m02
```

### 3.2 Node label'larını doğrulayın

```bash
kubectl get nodes -L app
```

Beklenen yerleşim:

| Node | `app` label'ı | Görev |
|---|---|---|
| `oneuptime` | `oneuptime-core` | OneUptime çekirdek servisleri ve Probe One |
| `oneuptime-m02` | `oneuptime-probe` | Probe Two ve manuel Nginx test hedefi |

`minikube stop` label'ları silmez. Buna rağmen label eksik görünürse tekrar
uygulayın:

```bash
kubectl label nodes oneuptime app=oneuptime-core --overwrite
kubectl label nodes oneuptime-m02 app=oneuptime-probe --overwrite
```

### 3.3 Helm release'ini doğrulayın

```bash
helm list -n oneuptime
```

`oneuptime` release'i listelenmelidir. Normal bir stop/start sonrasında tekrar
`helm install` veya `helm upgrade` çalıştırmayın; kurulu release ve values
ayarları korunur.

### 3.4 OneUptime podlarının toparlanmasını bekleyin

```bash
kubectl get pods -n oneuptime -w
```

PostgreSQL, ClickHouse ve Redis gibi durum tutan servisler önce açılır. App,
Nginx ve probe podlarının hazır olması birkaç dakika sürebilir. Eski migration
podlarından birinin `Error`, sonraki denemenin `Completed` olması mümkündür;
kalıcı servislerin `Running` ve `READY 1/1` olması esas kontroldür.

Son durumu node yerleşimiyle birlikte kontrol edin:

```bash
kubectl get pods -n oneuptime -o wide
```

Beklenen temel yerleşim:

- OneUptime çekirdek podları ve `oneuptime-probe-one` → `oneuptime`
- `oneuptime-probe-two` → `oneuptime-m02` (Probe Two daha önce kurulmuşsa)
- `nginx-target` → `oneuptime-m02` (manuel test podu daha önce oluşturulmuşsa)

### 3.5 Manuel Nginx hedefini kontrol edin

OneUptime Helm ile yönetilir; `nginx-target` ve `nginx-target-svc` ise test için
manuel olarak `kubectl` ile oluşturulmuştur. `minikube stop` bu nesneleri silmez,
bu yüzden start sonrasında tekrar ayağa kalkmaları gerekir:

```bash
kubectl get pod -n oneuptime nginx-target -o wide
kubectl get svc -n oneuptime nginx-target-svc
```

Pod veya servis yoksa ve çapraz izleme testine ihtiyaç varsa yeniden oluşturun:

```bash
kubectl run nginx-target --image=nginx --overrides='{"spec":{"nodeSelector":{"app":"oneuptime-probe"}}}' -n oneuptime
kubectl expose pod nginx-target --port=80 --target-port=80 --name=nginx-target-svc -n oneuptime
```

### 3.6 HTTPS servisini doğrulayın

```bash
kubectl get svc -n oneuptime oneuptime-local-tls
```

Servis `ClusterIP` tipindedir; dashboard erişimi için port-forward kullanılır.

### 3.7 Port-forward'ı yeniden başlatın

Ayrı bir terminal sekmesinde çalıştırın ve terminali açık bırakın:

```bash
./scripts/port-forward-https.sh
```

Beklenen çıktı:

```text
Forwarding from 127.0.0.1:80 -> 8080
Forwarding from [::1]:80 -> 8080
Forwarding from 127.0.0.1:443 -> 8443
Forwarding from [::1]:443 -> 8443
```

Arayüzü açın:

```text
https://oneuptime.furkan.test
```

İsteğe bağlı TLS ve HTTP kontrolü:

```bash
curl --cacert k8s/local-tls/certs/local-ca.crt \
  -I https://oneuptime.furkan.test
```

`HTTP/1.1 200` veya yönlendirme belirten geçerli bir HTTP yanıtı alınmalıdır.

### 3.8 Probe ve monitör durumlarını kontrol edin

Dashboard'da **Project → Products → Monitor → Probes** sayfasını açın.
Podlar tamamen hazır olduktan sonra daha önce kurulan probe'ların tekrar
`Connected`/`Online` olması gerekir.

`minikube stop` PostgreSQL verisini ve Probe Key'leri koruduğu için yeni bir
Probe Two kaydı veya yeni key oluşturmayın. Yeni key yalnızca profil
`minikube delete -p oneuptime` ile silinip sıfırdan kurulduğunda gerekir.

Mevcut çapraz izleme monitörleri de korunur. Şunları doğrulayın:

- `Node2-Nginx-Health-Check`: Probe One → `nginx-target-svc`
- `Node1-App-Health-Check`: Probe Two → OneUptime App health endpoint'i

İlk birkaç kontrol sırasında probe veya monitor kısa süreli `Disconnected`
görünebilir. Podlar hazır olduktan ve yeni değerlendirme çalıştıktan sonra durum
kendiliğinden düzelmelidir.

## 4. Sorun giderme

### Pod uzun süre hazır olmuyorsa

```bash
kubectl get pods -n oneuptime -o wide
kubectl get events -n oneuptime --sort-by=.lastTimestamp
kubectl describe pod -n oneuptime POD_ADI
kubectl logs -n oneuptime POD_ADI --tail=100
```

`ContainerCreating` sırasında büyük imajların hazırlanması zaman alabilir.
`ImagePullBackOff` görülürse olay mesajındaki nedeni inceleyin; geçici ağ zaman
aşımında kubelet otomatik olarak yeniden dener. Yalnızca bu durum nedeniyle
cluster'ı silmeyin veya Helm release'ini yeniden kurmayın.

### `oneuptime.furkan.test` açılmıyorsa

1. `oneuptime-local-tls` ve `oneuptime-nginx` podlarının `1/1 Running`
   olduğunu doğrulayın.
2. Port-forward terminalinin hâlâ açık olduğunu kontrol edin.
3. Port-forward kapandıysa 3.7 bölümündeki komutu yeniden çalıştırın.
4. Port `443` kullanımda ise eski port-forward sürecini kapatın veya hâlihazırda
   çalışan terminal oturumunu kullanın.

## Hızlı komut özeti

Durdurma:

```bash
minikube stop -p oneuptime
```

Yeniden başlatma ve kontrol:

```bash
minikube start -p oneuptime
kubectl config use-context oneuptime
kubectl get nodes -L app
helm list -n oneuptime
kubectl get pods -n oneuptime -o wide
kubectl get svc -n oneuptime oneuptime-local-tls
./scripts/port-forward-https.sh
```
