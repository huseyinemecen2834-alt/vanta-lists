#!/usr/bin/env bash
#
# Vanta listelerini üretir. Depo kökündeki üç dosyayı bu betik yazar:
#
#   ads.txt       = HaGeZi Multi Light + manual/ads.txt      - manual/allow.txt
#   trackers.txt  = manual/trackers.txt                      - manual/allow.txt
#   malware.txt   = URLhaus          + manual/malware.txt    - manual/allow.txt
#
# KURAL: Yalnızca "manual/" klasöründeki dosyalar elle düzenlenir. Kökteki üç
# dosya her çalıştırmada yeniden üretilir.
#
# Kullanım (Linux, macOS ya da Windows'ta Git Bash):
#   bash scripts/build.sh
#
# Güvenlik: her şey geçici bir klasörde üretilir. İndirme başarısız olursa ya
# da aşağıdaki denetimlerden biri tutmazsa betik sıfırdan farklı bir kodla
# çıkar ve kökteki dosyalara DOKUNMAZ.
#
# Sınama için ortam değişkenleri (normalde gerekmez):
#   HAGEZI_URLS, URLHAUS_URLS   boşlukla ayrılmış adresler; sırayla denenir
#                               (file:///... adresleri de olur)
#   DOWNLOAD_ATTEMPTS           her adres için deneme sayısı (varsayılan 3)
#   DOWNLOAD_RETRY_DELAY        denemeler arası saniye (varsayılan 10)

set -Eeuo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------
# Ayarlar
# ---------------------------------------------------------------------------

# HaGeZi Multi Light, "wildcard / only domains" biçimi: her satır bir alan adı,
# alt alan adları dahil sayılır (uygulama da kuralları böyle yorumlar).
HAGEZI_URLS="${HAGEZI_URLS:-https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/light-onlydomains.txt https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/light-onlydomains.txt}"
URLHAUS_URLS="${URLHAUS_URLS:-https://malware-filter.gitlab.io/malware-filter/urlhaus-filter-hosts-online.txt}"
DOWNLOAD_ATTEMPTS="${DOWNLOAD_ATTEMPTS:-3}"
DOWNLOAD_RETRY_DELAY="${DOWNLOAD_RETRY_DELAY:-10}"

# Denetim eşikleri
ADS_MIN=50000
ADS_MAX=150000
TRACKERS_MIN=1
MALWARE_MIN=50

# ads.txt bu adları mutlaka engellemelidir (bir kural adın kendisi ya da üst
# alan adı ise "kapsar").
MUST_BLOCK="googleads.g.doubleclick.net pagead2.googlesyndication.com ad.doubleclick.net www.googleadservices.com s0.2mdn.net"

OUTPUTS="ads trackers malware"
DATE_PREFIX='# Üretim tarihi:'

# ---------------------------------------------------------------------------
# Yardımcılar
# ---------------------------------------------------------------------------

WORK="$(mktemp -d)"
WARNINGS=0
PROBLEMS=()

cleanup() {
  rm -rf "$WORK"
  local name
  for name in $OUTPUTS; do
    rm -f "$ROOT/$name.txt.new"
  done
}
trap cleanup EXIT
trap 'echo "HATA: beklenmeyen hata (scripts/build.sh satır $LINENO)." >&2' ERR

say() { printf '%s\n' "$*"; }

# warn MESAJ [DOSYA SATIR]
warn() {
  WARNINGS=$((WARNINGS + 1))
  printf 'UYARI: %s\n' "$1" >&2
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    local msg="${1//%/%25}"
    if [ -n "${2:-}" ]; then
      printf '::warning file=%s,line=%s::%s\n' "$2" "${3:-1}" "$msg"
    else
      printf '::warning::%s\n' "$msg"
    fi
  fi
}

problem() {
  PROBLEMS+=("$1")
  printf 'DENETİM TUTMADI: %s\n' "$1" >&2
}

die() {
  printf '\nHATA: %s\n' "$1" >&2
  printf 'Hiçbir dosya değiştirilmedi; kökteki ads.txt, trackers.txt ve malware.txt eskisi gibi duruyor.\n' >&2
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::error::%s\n' "${1//%/%25}"
  fi
  exit 1
}

count() { wc -l < "$1" | tr -d ' '; }

# download HEDEF ADRES...
# Adresleri sırayla, her birini DOWNLOAD_ATTEMPTS kez dener.
download() {
  local dest="$1" url attempt
  shift
  for url in "$@"; do
    attempt=1
    while [ "$attempt" -le "$DOWNLOAD_ATTEMPTS" ]; do
      rm -f "$dest"
      if curl -fsSL --connect-timeout 20 --max-time 180 -o "$dest" "$url" && [ -s "$dest" ]; then
        say "  indirildi: $url"
        return 0
      fi
      say "  indirilemedi (deneme $attempt/$DOWNLOAD_ATTEMPTS): $url"
      attempt=$((attempt + 1))
      if [ "$attempt" -le "$DOWNLOAD_ATTEMPTS" ]; then
        sleep "$DOWNLOAD_RETRY_DELAY"
      fi
    done
  done
  return 1
}

# normalize GİRDİ ÇIKTI RET_DOSYASI
# Her girdi aynı kuraldan geçer: \r ve "#" açıklamaları atılır, boşlukla
# ayrılmış son parça alınır (hosts biçimindeki "0.0.0.0 ad" satırları için),
# küçük harfe çevrilir, sondaki nokta atılır, yalnızca sözdizimi geçerli ve
# en az bir nokta içeren alan adları kalır. Reddedilen satırlar
# "satır_no<TAB>metin" olarak RET_DOSYASI'na yazılır.
# awk kısmı mawk ile de çalışsın diye {n,m} gibi aralık ifadeleri kullanılmaz.
normalize() {
  : > "$3"
  awk -v rejects="$3" '
    function valid(d,    n, i, L) {
      if (length(d) > 253) return 0
      n = split(d, L, /\./)
      if (n < 2) return 0
      for (i = 1; i <= n; i++) {
        if (length(L[i]) < 1 || length(L[i]) > 63) return 0
        if (L[i] !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/) return 0
      }
      if (L[n] ~ /^[0-9]+$/) return 0
      return 1
    }
    NR == 1 { sub(/^\357\273\277/, "") }
    {
      gsub(/\r/, "")
      raw = $0
      sub(/#.*/, "")
      if (NF == 0) next
      d = tolower($NF)
      sub(/\.$/, "", d)
      if (valid(d)) print d
      else print NR "\t" raw > rejects
    }
  ' "$1" | sort -u > "$2"
}

# load_manual AD  ->  $WORK/manual-AD.txt
# El listesindeki bozuk satır çalışmayı durdurmaz; görünür bir uyarıyla atlanır.
load_manual() {
  local name="$1"
  local src="$ROOT/manual/$name.txt" rej="$WORK/manual-$name.rej"
  local line text
  if [ ! -f "$src" ]; then
    die "manual/$name.txt bulunamadı."
  fi
  normalize "$src" "$WORK/manual-$name.txt" "$rej"
  while IFS=$'\t' read -r line text; do
    warn "manual/$name.txt, satır $line atlandı (geçerli bir alan adı değil): $text" "manual/$name.txt" "$line"
  done < "$rej"
  say "  manual/$name.txt: $(count "$WORK/manual-$name.txt") ad"
}

# load_upstream AD ETİKET ADRESLER  ->  $WORK/AD.txt
load_upstream() {
  local name="$1" label="$2" urls="$3"
  local rejected
  say "$label indiriliyor..."
  # shellcheck disable=SC2086
  if ! download "$WORK/$name.raw" $urls; then
    die "$label indirilemedi."
  fi
  normalize "$WORK/$name.raw" "$WORK/$name.txt" "$WORK/$name.rej"
  rejected="$(count "$WORK/$name.rej")"
  say "  $label: $(count "$WORK/$name.txt") alan adı (alan adı olmayan $rejected satır atlandı)"
}

# apply_allow GİRDİ ÇIKTI ÇIKARILANLAR
# İzin listesindeki bir ada eşit olan ya da onun üst alan adı olan kurallar
# çıkarılır (kural alt alan adlarını da engellediği için ikisi de o adı
# engellerdi). ÇIKARILANLAR: "kural<TAB>buna yol açan izin adı".
apply_allow() {
  : > "$3"
  awk -v allow="$WORK/manual-allow.txt" -v removed="$3" '
    BEGIN {
      while ((getline a < allow) > 0) {
        n = split(a, L, /\./)
        s = ""
        for (i = n; i >= 1; i--) {
          s = (s == "" ? L[i] : L[i] "." s)
          if (!(s in why)) why[s] = a
        }
      }
      close(allow)
    }
    {
      if ($0 in why) print $0 "\t" why[$0] > removed
      else print
    }
  ' "$1" > "$2"
}

# covering_rule AD KURAL_DOSYASI
# AD'ı kapsayan (kendisi ya da üst alan adı olan) ilk kuralı yazar; yoksa 1 döner.
covering_rule() {
  local d="$1"
  while :; do
    if grep -qxF -- "$d" "$2"; then
      printf '%s\n' "$d"
      return 0
    fi
    case "$d" in
      *.*) d="${d#*.}" ;;
      *) return 1 ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# 1) Girdiler
# ---------------------------------------------------------------------------

for tool in curl awk sort grep cmp wc tr date mktemp; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    die "Gerekli araç bulunamadı: $tool"
  fi
done
if [ ! -s "$ROOT/LICENSES/GPL-3.0.txt" ]; then
  die "LICENSES/GPL-3.0.txt bulunamadı. ads.txt GPL-3.0 ile dağıtıldığı için lisans metni depoda durmalıdır."
fi

say "El listeleri okunuyor..."
load_manual ads
load_manual trackers
load_manual malware
load_manual allow
if [ ! -s "$WORK/manual-allow.txt" ]; then
  warn "manual/allow.txt içinde hiç ad yok; izin listesi uygulanmayacak." "manual/allow.txt" 1
fi

load_upstream hagezi "HaGeZi Multi Light" "$HAGEZI_URLS"
load_upstream urlhaus "URLhaus" "$URLHAUS_URLS"

# ---------------------------------------------------------------------------
# 2) Birleştir, izin listesini uygula
# ---------------------------------------------------------------------------

sort -u "$WORK/hagezi.txt" "$WORK/manual-ads.txt" > "$WORK/ads.merged"
sort -u "$WORK/manual-trackers.txt" > "$WORK/trackers.merged"
sort -u "$WORK/urlhaus.txt" "$WORK/manual-malware.txt" > "$WORK/malware.merged"

say "İzin listesi uygulanıyor (manual/allow.txt)..."
for name in $OUTPUTS; do
  apply_allow "$WORK/$name.merged" "$WORK/$name.body" "$WORK/$name.removed"
  removed="$(count "$WORK/$name.removed")"
  if [ "$removed" -eq 0 ]; then
    say "  $name.txt: çıkarılan kural yok"
  else
    say "  $name.txt: $removed kural çıkarıldı:"
    while IFS=$'\t' read -r rule entry; do
      say "    - $rule   (izin listesindeki ad: $entry)"
    done < "$WORK/$name.removed"
  fi
done

ADS_COUNT="$(count "$WORK/ads.body")"
TRACKERS_COUNT="$(count "$WORK/trackers.body")"
MALWARE_COUNT="$(count "$WORK/malware.body")"

# ---------------------------------------------------------------------------
# 3) Denetimler: biri bile tutmazsa hiçbir şey yazılmaz
# ---------------------------------------------------------------------------

say "Denetimler..."
if [ "$ADS_COUNT" -lt "$ADS_MIN" ] || [ "$ADS_COUNT" -gt "$ADS_MAX" ]; then
  problem "ads.txt $ADS_COUNT kural içeriyor; $ADS_MIN ile $ADS_MAX arasında olmalı (kaynak liste bozulmuş ya da değişmiş olabilir)."
else
  say "  ads.txt kural sayısı: $ADS_COUNT (sınır $ADS_MIN-$ADS_MAX)"
fi
if [ "$TRACKERS_COUNT" -lt "$TRACKERS_MIN" ]; then
  problem "trackers.txt boş çıkıyor; uygulama boş listeyi kabul etmez (manual/trackers.txt içinde geçerli ad kalmamış)."
else
  say "  trackers.txt kural sayısı: $TRACKERS_COUNT (en az $TRACKERS_MIN)"
fi
if [ "$MALWARE_COUNT" -lt "$MALWARE_MIN" ]; then
  problem "malware.txt $MALWARE_COUNT kural içeriyor; en az $MALWARE_MIN olmalı (URLhaus indirmesi eksik olabilir)."
else
  say "  malware.txt kural sayısı: $MALWARE_COUNT (en az $MALWARE_MIN)"
fi

for host in $MUST_BLOCK; do
  if rule="$(covering_rule "$host" "$WORK/ads.body")"; then
    say "  $host engelleniyor (kural: $rule)"
  else
    problem "ads.txt, $host adını engellemiyor. manual/ads.txt ya da manual/allow.txt içindeki son değişikliğe bak."
  fi
done

# İzin listesindeki hiçbir ad, üretilen listelerde engellenmiş kalmamalı.
while IFS= read -r entry; do
  for name in $OUTPUTS; do
    if rule="$(covering_rule "$entry" "$WORK/$name.body")"; then
      problem "$name.txt, izin listesindeki $entry adını hâlâ engelliyor (kural: $rule)."
    fi
  done
done < "$WORK/manual-allow.txt"

if [ "${#PROBLEMS[@]}" -gt 0 ]; then
  die "${#PROBLEMS[@]} denetim tutmadı: ${PROBLEMS[*]}"
fi

# ---------------------------------------------------------------------------
# 4) Çıktı dosyaları (geçici klasörde)
# ---------------------------------------------------------------------------

BUILD_DATE="$(date -u '+%Y-%m-%d %H:%M UTC')"
mkdir -p "$WORK/out"

{
  cat <<EOF
# Vanta - Reklamlar
#
# BU DOSYA OTOMATİK ÜRETİLİR, ELLE DÜZENLEME: değişikliğin bir sonraki üretimde silinir.
# KURAL: Yalnızca "manual/" klasöründeki dosyaları düzenle.
#   Alan adı eklemek için       : manual/ads.txt
#   Bir adın engelini kaldırmak : manual/allow.txt
# GENERATED FILE - DO NOT EDIT. Edit manual/ads.txt or manual/allow.txt instead.
# Üreten: scripts/build.sh
#
# Kaynaklar:
#   1) HaGeZi DNS Blocklists - Multi Light
#      https://github.com/hagezi/dns-blocklists
#      Lisans: GNU General Public License v3.0 (GPL-3.0)
#   2) manual/ads.txt (bu deponun el listesi)
#
# Bu dosya, HaGeZi DNS Blocklists temel alınarak DEĞİŞTİRİLMİŞ bir çalışmadır:
# el listesi eklendi, manual/allow.txt içindeki adları engelleyen kurallar
# çıkarıldı, satırlar yeniden sıralandı. GPL-3.0 ile dağıtılır.
# Lisans metni: LICENSES/GPL-3.0.txt
#
# This file is a modified work based on HaGeZi DNS Blocklists
# (https://github.com/hagezi/dns-blocklists), modified on the build date below.
# It is licensed under the GNU General Public License v3.0; see LICENSES/GPL-3.0.txt.
#
$DATE_PREFIX $BUILD_DATE
# Kural sayısı: $ADS_COUNT
#
EOF
  cat "$WORK/ads.body"
} > "$WORK/out/ads.txt"

{
  cat <<EOF
# Vanta - İzleyiciler
#
# BU DOSYA OTOMATİK ÜRETİLİR, ELLE DÜZENLEME: değişikliğin bir sonraki üretimde silinir.
# KURAL: Yalnızca "manual/" klasöründeki dosyaları düzenle.
#   Alan adı eklemek için       : manual/trackers.txt
#   Bir adın engelini kaldırmak : manual/allow.txt
# GENERATED FILE - DO NOT EDIT. Edit manual/trackers.txt or manual/allow.txt instead.
# Üreten: scripts/build.sh
#
# Kaynak: manual/trackers.txt (bu deponun el listesi; dış kaynak ve dış lisans yok)
#
$DATE_PREFIX $BUILD_DATE
# Kural sayısı: $TRACKERS_COUNT
#
EOF
  cat "$WORK/trackers.body"
} > "$WORK/out/trackers.txt"

{
  cat <<EOF
# Vanta - Zararlı siteler
#
# BU DOSYA OTOMATİK ÜRETİLİR, ELLE DÜZENLEME: değişikliğin bir sonraki üretimde silinir.
# KURAL: Yalnızca "manual/" klasöründeki dosyaları düzenle.
#   Alan adı eklemek için       : manual/malware.txt
#   Bir adın engelini kaldırmak : manual/allow.txt
# GENERATED FILE - DO NOT EDIT. Edit manual/malware.txt or manual/allow.txt instead.
# Üreten: scripts/build.sh
#
# Kaynaklar:
#   1) URLhaus (abuse.ch), malware-filter/urlhaus-filter "hosts online" listesi
#      https://gitlab.com/malware-filter/urlhaus-filter
#      Lisans: URLhaus verisi CC0; urlhaus-filter CC0-1.0 ve MIT
#      (https://gitlab.com/malware-filter/urlhaus-filter#license)
#   2) manual/malware.txt (bu deponun el listesi)
#
$DATE_PREFIX $BUILD_DATE
# Kural sayısı: $MALWARE_COUNT
#
EOF
  cat "$WORK/malware.body"
} > "$WORK/out/malware.txt"

# ---------------------------------------------------------------------------
# 5) Yayımla: yalnızca değişen dosyalar, hepsi hazır olduktan sonra
# ---------------------------------------------------------------------------

# Üretim tarihi satırı dışında aynı kalan dosyaya dokunulmaz; böylece tarih
# "içeriğin en son değiştiği üretim"i gösterir ve her gün boş yere kayıt
# (commit) oluşmaz.
same_content() {
  [ -f "$1" ] && cmp -s <(grep -vF -- "$DATE_PREFIX" "$1") <(grep -vF -- "$DATE_PREFIX" "$2")
}

CHANGED=""
for name in $OUTPUTS; do
  if same_content "$ROOT/$name.txt" "$WORK/out/$name.txt"; then
    say "  $name.txt: içerik aynı, dokunulmadı"
  else
    cp "$WORK/out/$name.txt" "$ROOT/$name.txt.new"
    CHANGED="$CHANGED $name"
  fi
done
for name in $CHANGED; do
  mv -f "$ROOT/$name.txt.new" "$ROOT/$name.txt"
  say "  $name.txt: yazıldı"
done

say ""
say "Tamam. ads.txt: $ADS_COUNT kural, trackers.txt: $TRACKERS_COUNT kural, malware.txt: $MALWARE_COUNT kural. Uyarı sayısı: $WARNINGS."

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Vanta listeleri"
    echo ""
    echo "| Dosya | Kural sayısı |"
    echo "| --- | --- |"
    echo "| ads.txt | $ADS_COUNT |"
    echo "| trackers.txt | $TRACKERS_COUNT |"
    echo "| malware.txt | $MALWARE_COUNT |"
    echo ""
    echo "Değişen dosyalar:${CHANGED:- yok}. Uyarı sayısı: $WARNINGS."
  } >> "$GITHUB_STEP_SUMMARY"
fi
