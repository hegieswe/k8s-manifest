#!/usr/bin/env bash
# =============================================================================
# cd.sh — Dynamic CD Script: Deploy ke Kubernetes via Kustomize
#
# Otomatis mendeteksi semua service di k8s/base/
#
# Usage:
#   ./cd.sh -e development
#   ./cd.sh -e staging --tags "dev-ops-test-java:v1.2.0,dev-ops-test-python:v1.0.0"
#
# Options:
#   -e, --env         Environment target: development | staging | production  (wajib)
#   --tags            Custom tags (format: "svc1:tag1,svc2:tag2")
#   --dry-run         Preview manifest tanpa apply ke cluster
#   -h, --help        Tampilkan bantuan ini
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────
# Warna output
# ─────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
step()  { echo -e "\n${BOLD}▶ $*${RESET}"; }

# ─────────────────────────────────────────────
# Default nilai
# ─────────────────────────────────────────────
DOCKER_ORG="${DOCKER_ORG:-hegieswe}"
ENV=""
TAGS_STR=""
DRY_RUN=false
GIT_SHA=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "latest")

# ─────────────────────────────────────────────
# Parse argumen
# ─────────────────────────────────────────────
usage() {
  sed -n '/^# Usage:/,/^# ==/p' "$0" | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--env)         ENV="$2";         shift 2 ;;
    --tags)           TAGS_STR="$2";    shift 2 ;;
    --dry-run)        DRY_RUN=true;     shift   ;;
    -h|--help)        usage ;;
    *) err "Unknown option: $1" ;;
  esac
done

# ─────────────────────────────────────────────
# Discovery & Validasi
# ─────────────────────────────────────────────
[[ -z "$ENV" ]] && err "Environment wajib diisi. Gunakan: -e development | staging | production"

OVERLAY_DIR="overlays/${ENV}"
[[ -d "$OVERLAY_DIR" ]] || err "Overlay tidak ditemukan: $OVERLAY_DIR"

# Namespace sesuai overlay (disesuaikan dengan isi kustomization.yaml)
case "$ENV" in
  development) NAMESPACE="dev-project"  ;;
  staging)     NAMESPACE="staging-project"  ;;
  production)  NAMESPACE="prod-project" ;;
  *) err "Environment tidak valid: $ENV" ;;
esac

# Deteksi semua service dari folder base
SERVICES=($(ls -d base/*/ | xargs -n1 basename))
info "Ditemukan ${#SERVICES[@]} service: ${SERVICES[*]}"

# Tag extraction logic (Bash 3.2 compatible)
get_tag() {
  local svc_name="$1"
  local tags_str="$2"
  local default_tag="$3"
  
  # Cari svc:tag dalam string tags_str (misal "svc1:tag1,svc2:tag2")
  local found_tag=$(echo "$tags_str" | grep -oE "(^|,)${svc_name}:[^,]+" | cut -d: -f2 || true)
  
  if [[ -n "$found_tag" ]]; then
    echo "$found_tag"
  else
    echo "$default_tag"
  fi
}

# ─────────────────────────────────────────────
# Ringkasan
# ─────────────────────────────────────────────
echo -e "\n${BOLD}═══════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Dynamic CD — Deploy ke Kubernetes${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════${RESET}"
info "Environment  : ${BOLD}$ENV${RESET}"
info "Namespace    : ${BOLD}$NAMESPACE${RESET}"
info "Default Tag  : ${BOLD}$GIT_SHA${RESET}"
info "Overlay      : $OVERLAY_DIR"
info "Dry run      : $DRY_RUN"

# ─────────────────────────────────────────────
# Step 1: Namespace
# ─────────────────────────────────────────────
step "1/3 Namespace"
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  ok "Namespace '$NAMESPACE' sudah ada."
else
  if [[ "$DRY_RUN" == true ]]; then
    warn "Namespace '$NAMESPACE' belum ada (dry-run)."
  else
    kubectl create namespace "$NAMESPACE"
    ok "Namespace '$NAMESPACE' dibuat."
  fi
fi

# ─────────────────────────────────────────────
# Step 2: Update Image Tag
# ─────────────────────────────────────────────
step "2/3 Dynamic Image Patching"

KUST_FILE="${OVERLAY_DIR}/kustomization.yaml"
KUST_BACKUP="${KUST_FILE}.bak"
cp "$KUST_FILE" "$KUST_BACKUP"

# Hapus blok images lama (Linux & Mac compatible)
if grep -q "^images:" "$KUST_FILE"; then
  # Hapus dari 'images:' sampai akhir file
  sed -i.tmp '/^images:/,$d' "$KUST_FILE" && rm -f "${KUST_FILE}.tmp"
fi

echo -e "\nimages:" >> "$KUST_FILE"

for SVC in "${SERVICES[@]}"; do
  # Cari SHA dari folder service yang bersangkutan jika ada (Polyreppo support)
  SVC_DIR="./${SVC}"
  DEFAULT_SVC_TAG="$GIT_SHA"
  
  if [[ -d "$SVC_DIR/.git" ]]; then
    # Ambil SHA dari repo service tersebut
    DEFAULT_SVC_TAG=$(cd "$SVC_DIR" && git rev-parse --short=7 HEAD 2>/dev/null || echo "latest")
    info "Service ${SVC}: mendeteksi Git SHA ${DEFAULT_SVC_TAG} dari folder .git"
  fi
  
  TAG=$(get_tag "$SVC" "$TAGS_STR" "$DEFAULT_SVC_TAG")
  IMAGE_NAME="${DOCKER_ORG}/${SVC}"
  
  echo "  - name: ${IMAGE_NAME}" >> "$KUST_FILE"
  echo "    newTag: \"${TAG}\"" >> "$KUST_FILE"
  info "Patching ${SVC} → ${TAG}"
done

# ─────────────────────────────────────────────
# Step 3: Deploy
# ─────────────────────────────────────────────
step "3/3 Deploy"

if [[ "$DRY_RUN" == true ]]; then
  warn "DRY-RUN — manifest preview:"
  kubectl kustomize "$OVERLAY_DIR"
  mv "$KUST_BACKUP" "$KUST_FILE"
  exit 0
fi

DEPLOY_START=$(date +%s)
kubectl apply -k "$OVERLAY_DIR"
rm -f "$KUST_BACKUP"

# Tunggu rollout untuk semua service yang ada di overlay ini
# Gunakan konvensi: Deployment name = gtech-hello-<folder_name>
info "Menunggu rollout status..."
for SVC in "${SERVICES[@]}"; do
  # Deteksi jika deployment ada di manifest (optional check)
  DEPLOY_NAME="gtech-hello-${SVC}"
  if kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" &>/dev/null; then
    info "Checking rollout status: ${DEPLOY_NAME}"
    kubectl rollout status deployment/"$DEPLOY_NAME" -n "$NAMESPACE" --timeout=60s || warn "Rollout timeout untuk ${SVC}"
  fi
done

DEPLOY_DURATION=$(( $(date +%s) - DEPLOY_START ))
echo -e "\n${GREEN}${BOLD}✅ Deploy selesai dalam ${DEPLOY_DURATION}s${RESET}"
kubectl get pods -n "$NAMESPACE"
