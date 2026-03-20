# Kubernetes Kustomize Manifests - hello-golang

Repositori ini berisi konfigurasi Kubernetes menggunakan **Kustomize** untuk layanan `hello-golang`. Proyek ini dirancang untuk mendukung deployment ke berbagai lingkungan (*environments*) dengan konfigurasi yang terstandarisasi namun fleksibel.

## Struktur Direktori

Struktur proyek ini mengikuti praktik terbaik Kustomize:

```bash
.
├── base/
│   └── golang-gitops-project/
│       ├── deployment.yaml      # Definisi Deployment dasar
│       ├── kustomization.yaml   # Konfigurasi kustomize untuk base
│       └── service.yaml         # Definisi Service (NodePort)
└── overlays/
    ├── development/             # Konfigurasi khusus lingkungan Development
    │   └── kustomization.yaml
    ├── staging/                 # Konfigurasi khusus lingkungan Staging
    │   └── kustomization.yaml
    └── production/              # Konfigurasi khusus lingkungan Production
        └── kustomization.yaml
```

- **base/**: Berisi sumber daya dasar (*base resources*) yang dibagikan antar lingkungan.
- **overlays/**: Berisi patch dan kustomisasi spesifik untuk masing-masing lingkungan seperti jumlah replika, nama namespace, dan alokasi *resource* (CPU/Memory).

## Prasyarat

Sebelum memulai, pastikan Anda telah menginstal alat-alat berikut:
- **kubectl**: Versi v1.21 ke atas sangat disarankan.
- **kustomize**: Terintegrasi langsung di dalam `kubectl` (gunakan perintah `kubectl kustomize`).

## Detail Lingkungan (Overlays)

Setiap lingkungan memiliki karakteristik yang berbeda:

| Fitur | Development | Staging | Production |
| :--- | :--- | :--- | :--- |
| **Namespace** | `dev-project` | `staging-project` | `production-project` |
| **Replica** | 1 | 2 | 3 |
| **Env Var** | `ENV=development` | `ENV=staging` | `ENV=production` |
| **CPU (Req/Lim)** | 50m / 200m | 100m / 250m | 100m / 250m |
| **Memory (Req/Lim)**| 64Mi / 128Mi | 128Mi / 256Mi | 128Mi / 256Mi |

## Cara Penggunaan

### 1. Melihat Hasil Manifest (Dry-run)

Sebelum menerapkan ke klaster, Anda dapat melihat manifest YAML yang dihasilkan oleh Kustomize:

```bash
# Untuk lingkungan Development
kubectl kustomize overlays/development

# Untuk lingkungan Staging
kubectl kustomize overlays/staging

# Untuk lingkungan Production
kubectl kustomize overlays/production
```

### 2. Menerapkan ke Klaster (Apply)

Gunakan perintah `-k` (kustomize) untuk menerapkan konfigurasi ke Kubernetes Cluster:

```bash
# Deploy ke Development
kubectl apply -k overlays/development

# Deploy ke Staging
kubectl apply -k overlays/staging

# Deploy ke Production
kubectl apply -k overlays/production
```

### 3. Menghapus Deployment

Jika ingin menghapus seluruh *resource* yang dibuat:

```bash
kubectl delete -k overlays/<nama-lingkungan>
```

## Spesifikasi Layanan (Service)

Layanan ini menggunakan type `NodePort` untuk aksesibilitas:
- **Internal Port**: 8080
- **NodePort**: 32020
- **Health Check Port**: 8080 (Endpoint: `/health`)

---

> [!NOTE]
> Pastikan namespace yang didefinisikan di setiap `kustomization.yaml` sudah tersedia atau biarkan ArgoCD/Kubectl membuatnya jika dikonfigurasi demikian.
