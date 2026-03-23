#!/bin/bash
set -eo pipefail

echo "================================================="
echo "       KUSTOMIZE SERVICE MANAGER WIZARD          "
echo "================================================="
echo ""
echo "Menu Utama:"
echo "1. 🏗️  Buat Manifest Service Baru (Scaffold)"
echo "2. 🗑️  Hapus Manifest Service"
read -p "Masukkan pilihan Anda [1/2]: " ACTION

if [[ "$ACTION" != "1" && "$ACTION" != "2" ]]; then
  echo "Error: Pilihan tidak valid!"
  exit 1
fi

if [[ "$ACTION" == "1" ]]; then
  # ==========================================
  # CREATE SERVICE
  # ==========================================
  echo ""
  read -p "Masukkan Nama Service (contoh: payment-service) : " SVC_NAME
  if [[ -z "$SVC_NAME" ]]; then echo "Error: Nama tidak boleh kosong!"; exit 1; fi
  if [[ "$SVC_NAME" =~ \  ]]; then echo "Error: Nama service tidak boleh mengandung SPASI untuk menjaga kompatibilitas Kubernetes!"; exit 1; fi

  # Penamaan Docker Image kini DIBEKUKAN otomatis dan dienkapsulasi kuat
  IMAGE_NAME="hegieswe/$SVC_NAME"
  
  read -p "Container Port (default: 8080)         : " PORT
  PORT=${PORT:-8080}
  
  read -p "Jumlah Replicas Pod (default: 1)       : " REPLICAS
  REPLICAS=${REPLICAS:-1}
  
  read -p "Ekspos keluar via NodePort? [y/N]      : " IS_NODEPORT
  SVC_TYPE="ClusterIP"
  NODEPORT_YAML=""
  if [[ "$IS_NODEPORT" =~ ^[Yy]$ ]]; then
    SVC_TYPE="NodePort"
    read -p "   => Masukkan nomor NodePort (misal 32025): " NODE_PORT
    NODEPORT_YAML="      nodePort: $NODE_PORT"
  fi
  
  read -p "Aktifkan Liveness & Readiness Probe? [y/N]: " IS_PROBE
  PROBE_YAML=""
  if [[ "$IS_PROBE" =~ ^[Yy]$ ]]; then
    read -p "   => Endpoint pengecekan (default: /health): " HEALTH_ENDPOINT
    HEALTH_ENDPOINT=${HEALTH_ENDPOINT:-"/health"}
    IFS= read -r -d '' PROBE_YAML <<EOF || true
          livenessProbe:
            httpGet:
              path: $HEALTH_ENDPOINT
              port: __PORT__
            initialDelaySeconds: 15
            periodSeconds: 20
          readinessProbe:
            httpGet:
              path: $HEALTH_ENDPOINT
              port: __PORT__
            initialDelaySeconds: 10
            periodSeconds: 10
EOF
  fi
  
  echo ""
  echo "--- Spesifikasi Hardware Resources (CPU & RAM) ---"
  read -p "Ingin menentukan ukuran limit resource secara kustom? [y/N] (Meninggalkan kosong menggunakan default 128MB RAM): " IS_RESOURCES
  if [[ "$IS_RESOURCES" =~ ^[Yy]$ ]]; then
    read -p "   => Request CPU (default: 50m)     : " CPU_REQ
    read -p "   => Limit CPU (default: 200m)      : " CPU_LIM
    read -p "   => Request Memory (default: 64Mi) : " MEM_REQ
    read -p "   => Limit Memory (default: 128Mi)  : " MEM_LIM
  fi
  
  CPU_REQ=${CPU_REQ:-"50m"}
  CPU_LIM=${CPU_LIM:-"200m"}
  MEM_REQ=${MEM_REQ:-"64Mi"}
  MEM_LIM=${MEM_LIM:-"128Mi"}
  
  echo ""
  echo "🚀 Membangun struktur Kustomize untuk '$SVC_NAME' ..."
  
  TARGET_DIR="base/$SVC_NAME"
  if [[ -d "$TARGET_DIR" ]]; then
    echo "Error: Service '$SVC_NAME' sudah ada di direktori base/!"
    exit 1
  fi
  
  mkdir -p "$TARGET_DIR"
  cp -r .template/* "$TARGET_DIR/"
  
  # Injeksi ProbeYAML jika diaktifkan pengguna
  export PROBE_YAML
  if [[ -n "$PROBE_YAML" ]]; then
    perl -pi -e 's/__PROBES__/$ENV{PROBE_YAML}/g' "$TARGET_DIR/deployment.yaml"
  else
    perl -pi -e 's/__PROBES__\n?//g' "$TARGET_DIR/deployment.yaml"
  fi
  
  # Injector Variabel ke dalam folder deployment yang dituju
  for file in "$TARGET_DIR"/*.yaml; do
    perl -pi -e "s|__SERVICE_NAME__|$SVC_NAME|g" "$file"
    perl -pi -e "s|__IMAGE_NAME__|$IMAGE_NAME|g" "$file"
    perl -pi -e "s|__PORT__|$PORT|g" "$file"
    perl -pi -e "s|__REPLICAS__|$REPLICAS|g" "$file"
    perl -pi -e "s|__SVC_TYPE__|$SVC_TYPE|g" "$file"
    perl -pi -e "s|__CPU_REQ__|$CPU_REQ|g" "$file"
    perl -pi -e "s|__CPU_LIM__|$CPU_LIM|g" "$file"
    perl -pi -e "s|__MEM_REQ__|$MEM_REQ|g" "$file"
    perl -pi -e "s|__MEM_LIM__|$MEM_LIM|g" "$file"
    
    if [[ -n "$NODEPORT_YAML" ]]; then
      perl -pi -e "s|__NODEPORT__|$NODEPORT_YAML|g" "$file"
    else
      perl -pi -e "s|__NODEPORT__\n?||g" "$file"
    fi
  done
  
  echo "✅ Berhasil melahirkan service $SVC_NAME di direktori -> $TARGET_DIR/"
  
  # Merangkainya dan menyambungkannya menjadi overlay komplit
  OVERLAY_KUST="overlays/development/kustomization.yaml"
  if [[ -f "$OVERLAY_KUST" ]]; then
    if ! grep -q "\- ../../base/$SVC_NAME" "$OVERLAY_KUST"; then
      echo "🔗 Menyambungkan rute resources ke berkas $OVERLAY_KUST ..."
      perl -pi -e "s/(resources:)/\$1\n  - ..\/..\/base\/$SVC_NAME/" "$OVERLAY_KUST"
    fi
  fi
  
  echo "🎉 SELESAI! Service $SVC_NAME sukses DITAMBAHKAN ke manifest repository!"
  echo ""
  echo "👉 LANGKAH SELANJUTNYA:"
  echo "- Uji coba peluncuran secara lokal di Kubernetes Anda:"
  echo -e "\033[1mkubectl apply -k overlays/development\033[0m"
  echo "- Atau biarkan ArgoCD yang mengambil alih dengan melakukan Push ke Git:"
  echo -e "\033[1mgit add . && git commit -m \"feat: Menambahkan service $SVC_NAME\" && git push\033[0m"
  echo "────────────────────────────────────────────────="

elif [[ "$ACTION" == "2" ]]; then
  # ==========================================
  # DELETE SERVICE
  # ==========================================
  echo ""
  echo "⚠️ MENGHAPUS SERVICE..."
  echo "Daftar service yang sedang terpasang di manifest Base:"
  
  # Mengisi daftar (array) dengan nama folder di dalam direktori base/
  SERVICES=()
  for d in base/*/; do
    if [[ -d "$d" ]]; then
      SERVICES+=("$(basename "$d")")
    fi
  done
  
  if [[ ${#SERVICES[@]} -eq 0 ]]; then
    echo "ℹ️ Tidak ada service yang ditemukan."
    exit 0
  fi
  
  # Mencetak menu opsi
  for i in "${!SERVICES[@]}"; do
    echo "  $((i+1)). ${SERVICES[$i]}"
  done
  
  # Meminta angka ID dari pengguna
  echo ""
  read -p "Masukkan NOMOR service yang ingin DIHANCURKAN (1-${#SERVICES[@]}): " DEL_ID
  
  # Validasi agar input-nya sesuai indeks array kita
  if ! [[ "$DEL_ID" =~ ^[0-9]+$ ]] || [ "$DEL_ID" -lt 1 ] || [ "$DEL_ID" -gt "${#SERVICES[@]}" ]; then
    echo "Error: Pilihan nomor '$DEL_ID' tidak valid!"
    exit 1
  fi
  
  # Mengambil balik nama service dari indeks yang diketik (index terminal minus 1)
  SVC_NAME="${SERVICES[$((DEL_ID-1))]}"
  
  echo ""
  echo "🧨 Menyiapkan peledakan untuk '$SVC_NAME'..."
  
  TARGET_DIR="base/$SVC_NAME"
  if [[ -d "$TARGET_DIR" ]]; then
    rm -rf "$TARGET_DIR"
    echo "✅ Berhasil mendetonasi dan membongkar folder -> $TARGET_DIR"
  else
    echo "ℹ️ Direktori $TARGET_DIR tidak ditemukan."
  fi
  
  # Cabut jalur koneksinya dari semua overlay (development, staging, production)
  for OVERLAY_KUST in overlays/*/kustomization.yaml; do
    if [[ -f "$OVERLAY_KUST" ]]; then
      if grep -q -e "- ../../base/$SVC_NAME" -e "- \.\.\/\.\.\/base\/$SVC_NAME" "$OVERLAY_KUST"; then
        # Regex penghapus referensi resource base khusus untuk baris itu
        perl -pi -e "s/[ \t]*\- \.\.\/\.\.\/base\/$SVC_NAME\n?//g" "$OVERLAY_KUST"
        echo "✅ Rute referensi dari $OVERLAY_KUST bersih terhapus."
      fi
      
      # Surgical Cleanup dengan "yq" jika terinstal
      if command -v yq >/dev/null 2>&1; then
        echo "🧹 Memindai dengan pisau bedah 'yq': Pembersihan Sisa Manifes $OVERLAY_KUST..."
        # Hapus elemen array yang mengarah ke service ini
        yq -i "del(.images[]? | select(.name == \"hegieswe/$SVC_NAME\"))" "$OVERLAY_KUST" 2>/dev/null || true
        yq -i "del(.patches[]? | select(.target.name == \"$SVC_NAME\"))" "$OVERLAY_KUST" 2>/dev/null || true
        
        # Bersihkan Key utamanya jika array sudah kosong
        yq -i 'if .images == [] then del(.images) else . end' "$OVERLAY_KUST" 2>/dev/null || true
        yq -i 'if .patches == [] then del(.patches) else . end' "$OVERLAY_KUST" 2>/dev/null || true
        echo "✅ Seluruh riwayat konfigurasi 'patches' & 'images' di $OVERLAY_KUST berhasil dilenyapkan!"
      fi
    fi
  done
  
  echo "🗑️ SELESAI! Seluruh riwayat untuk service '$SVC_NAME' sudah DIHAPUS dari muka repository k8s-manifest dan seluruh environments!"
  echo ""
  echo "👉 REKOMENDASI PENGHAPUSAN POD:"
  echo "Untuk memastikan Pod milik service ini juga ikut musnah di server Kubernetes Anda:"
  echo "- Jika memakai ArgoCD GitOps, cukup Commit & Push saja (ArgoCD akan membuangnya otomatis):"
  echo -e "\033[1mgit add . && git commit -m \"del: Menghapus service $SVC_NAME\" && git push\033[0m"
  echo "- TAPI Jika Anda ingin menghapusnya secara lokal secara manual dari K3d:"
  echo -e "\033[1mkubectl delete deployment $SVC_NAME -n <nama-namespace>\033[0m"
  echo "────────────────────────────────────────────────="
fi
