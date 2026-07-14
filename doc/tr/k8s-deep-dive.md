# Kubernetes Core Objects: Derinlemesine Mimari ve Çalışma Mantığı

Kubernetes (K8s) temelde devasa bir **Durum Makinesidir (State Machine)**. Sen API sunucusuna bir YAML (Manifesto) gönderdiğinde, ona sistemin *İstenen Durumunu (Desired State)* söylersin. K8s Controller'ları, sistemin *Mevcut Durumunu (Actual State)* sürekli olarak İstenen Duruma eşitlemek için sonsuz bir döngüde (Control Loop) çalışır.

Aşağıda bu mimarinin yapı taşları olan objelerin yüzeysel tanımlarını değil, arka plandaki mühendislik gerçekliklerini bulacaksın.



---

## 1. Altyapı ve Temel Bileşenler (Infrastructure)

### Node (Düğüm)
Kubernetes'in doğrudan kendi yarattığı bir obje değildir; dış dünyadaki fiziksel bir sunucunun (veya sanal makinenin) K8s API'sindeki temsilidir. 
* **Arka Plan Mantığı:** Bir sunucunun Node olabilmesi için üzerinde `kubelet` (K8s'in o sunucudaki ajanı) ve `kube-proxy` (ağ kurallarını yazan ajan) çalışması gerekir. Kubelet, Master Node'dan gelen emirleri alır ve sunucunun RAM/CPU kapasitesine (`cgroups`) göre konteynerleri başlatması için Container Runtime'a (örn: containerd) talimat verir.

### Pod
Kubernetes'in en küçük, atomik yapı taşıdır. Bir veya birden fazla konteyneri barındırır.
* **Arka Plan Mantığı:** K8s asla doğrudan bir Docker/containerd konteyneri yönetmez, Pod yönetir. Bir Pod yaratıldığında, arka planda önce **"Pause Container" (sandbox)** adında görünmez bir konteyner başlatılır. Bu pause container, Pod'un IP adresini ve Linux Network/IPC namespace'lerini (isim alanlarını) rezerve eder. Pod içindeki diğer gerçek uygulama konteynerleri, bu pause container'ın ağına bağlanır. Bu sayede aynı Pod içindeki konteynerler birbirleriyle `localhost` üzerinden haberleşebilir ve aynı depolama alanlarını (volumes) paylaşabilir.

---

## 2. İş Yükü Yöneticileri (Workload Controllers)

Pod'lar geçicidir (ephemeral). Çökerlerse kendiliklerinden geri gelmezler. Pod'ları hayatta tutan ve yöneten objeler bunlardır.

### ReplicaSet
Belirli bir etikete (label) sahip Pod'lardan her zaman tam olarak `N` adet çalışmasını garanti eden denetleyicidir.
* **Arka Plan Mantığı:** Sürekli Kube-API'yi dinler. `app=backend` etiketli 3 Pod olması gerekirken 2 tane bulursa, anında 1 tane daha Pod yaratma isteği (`Create Pod`) gönderir. Genellikle doğrudan kullanılmaz, Deployment tarafından yönetilir.

### Deployment
Durumsuz (Stateless) uygulamaların yaşam döngüsünü yönetir.
* **Arka Plan Mantığı:** Versiyon kontrolü yapar. Sen yeni bir imaj tag'i ile Deployment'ı güncellediğinde, mevcut `ReplicaSet`'in kopyalarını yavaşça azaltırken (örn: `RollingUpdate`), yeni bir `ReplicaSet` oluşturup onun kopyalarını artırır. Eğer K8s'e `Recreate` stratejisi verirsen, önce eski ReplicaSet'i tamamen öldürür, kaynakları boşa çıkarır, sonra yenisini ayağa kaldırır. 

### StatefulSet
Durum tutan (Stateful), yani veritabanları (PostgreSQL, ClickHouse vb.) gibi uygulamalar için kullanılır.
* **Arka Plan Mantığı:** Deployment'taki podların isimleri rastgele hash'lerden oluşurken (`app-7b89...`), StatefulSet podlarına kalıcı (sticky) bir kimlik verir (`db-0`, `db-1`). Pod silinip başka bir node'da ayağa kalksa bile ismi ve ağ kimliği değişmez. Ayrıca podları aynı anda değil, sırayla (0, sonra 1, sonra 2) ayağa kaldırır ve kapatırken tersten kapatır. Her pod'a özel kalıcı disk (PVC) bağlamak için kurgulanmıştır.

### DaemonSet
Bir Pod'un, cluster'daki **her** (veya belirli etiketlere sahip her) Node üzerinde tam olarak 1 adet çalışmasını garanti eder.
* **Arka Plan Mantığı:** K8s Scheduler (zamanlayıcı) mekanizmasını bypass edebilir (veya nodeSelector ile hedeflenir). Log toplayıcılar (Fluentd), ağ eklentileri (Calico) veya donanım izleme ajanları (Node Exporter, OneUptime Probes) için kullanılır. Kümeye yeni bir Node eklendiğinde, DaemonSet anında o Node'a da kendi Pod'undan bir tane kopyalar.

### Job ve CronJob
Sürekli çalışması gerekmeyen, bir görevi yapıp bitirmesi beklenen (Run-to-completion) objelerdir.
* **Arka Plan Mantığı:** Deployment podu çökerse veya işi biterse yeniden başlatılır. Job podu işini başarıyla bitirip `Exit 0` kodu döndürdüğünde K8s podu "Completed" durumuna çeker ve yeniden başlatmaz. Veritabanı migrasyonları (migration jobs) veya yedekleme scriptleri için kullanılır.

---

## 3. Ağ ve Trafik Yönetimi (Networking)

Pod'ların IP adresleri geçicidir (çöküp tekrar kalkan pod yeni IP alır). Bu değişkenliği soyutlayan objelere ihtiyaç vardır.



### Service (ClusterIP, NodePort, LoadBalancer)
Pod'ların önüne konulan, kalıcı bir IP'si (VIP - Virtual IP) olan ağ soyutlamasıdır.
* **Arka Plan Mantığı:** Bir Service objesi aslında bir process (çalışan bir kod) değildir. K8s'te Service yarattığında, her Node üzerinde çalışan `kube-proxy` aracı gider, o Node'un işletim sistemindeki **`iptables` (veya `IPVS`) kurallarını günceller.** Sen uygulamanın Service IP'sine istek attığında, sunucunun çekirdeği (kernel) paketi alır, `iptables` kurallarına bakar ve paketi rastgele (round-robin) olarak arkadaki Pod'lardan birinin gerçek IP'sine yönlendirir (NAT işlemi). 
* **Türleri:**
    * `ClusterIP`: Sadece cluster içinden erişilir.
    * `NodePort`: Tüm Node'ların fiziksel IP'sinden belirli bir port (30000-32767) açar.
    * `LoadBalancer`: Bulut sağlayıcısına (AWS, GCP) talimat verip dışarıda fiziksel bir Load Balancer makinesi oluşturur.

### Ingress
Service'ler genellikle Layer 4'te (TCP/UDP) çalışır. Ingress ise Layer 7'de (HTTP/HTTPS) trafik yönlendiren bir obje ve kurallar bütünüdür.
* **Arka Plan Mantığı:** Sadece Ingress objesi yaratmak hiçbir işe yaramaz; kümede bir **Ingress Controller** (Nginx, Traefik vb.) çalışıyor olması gerekir. Sen bir Ingress kuralı (örn: `api.sirket.com` adresini `backend-service`'e yönlendir) yazdığında, Ingress Controller bu YAML'ı okur ve arka planda dinamik olarak kendi `nginx.conf` dosyasını güncelleyip reload (Nginx -s reload) komutu çalıştırır.

---

## 4. Konfigürasyon ve Veri Kalıcılığı (Storage & Config)

Konteyner imajlarının içine şifre veya ortam değişkeni (ENV) gömmek (hardcoding) anti-pattern'dir. 

### ConfigMap ve Secret
Uygulamanın ayarlarını koddan bağımsız hale getirmek için kullanılır.
* **Arka Plan Mantığı:** ConfigMap düz metin tutar, Secret ise veriyi Base64 ile encode eder (**Şifrelemez! Sadece formatlar**). Kubelet, bir Pod'u ayağa kaldırırken bu objelerdeki verileri alır ve konteynerin içine ya ortam değişkeni (ENV) olarak enjekte eder ya da konteynerin dosya sistemine bir `tmpfs` (RAM tabanlı sanal disk) mount ederek dosya gibi okumasını sağlar.

### PersistentVolume (PV) ve PersistentVolumeClaim (PVC)
Konteynerler öldüğünde içindeki veriler (ephemeral storage) silinir. Veriyi kalıcı hale getirmek için soyutlama objeleridir.
* **Arka Plan Mantığı:** * **PV:** Storage Yöneticisinin (Admin) kümeye eklediği fiziksel disktir (AWS EBS, NFS, lokal SSD).
    * **PVC:** Yazılım geliştiricisinin K8s API'sinden "Bana 10GB disk lazım" diyerek oluşturduğu "Talep" fişidir. 
    * K8s, uygun PV ile PVC'yi birbirine bağlar (Bound). Pod ayağa kalkarken Kubelet o fiziksel diski Node'a bağlar (attach), ardından konteynerin içindeki ilgili klasöre (örn: `/var/lib/postgresql/data`) mount eder.