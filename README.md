# vanta-lists

Domain block lists for Vanta, an Android app that blocks ads and trackers in the apps a user selects by filtering their DNS lookups on the device. The lists are plain text with one domain per line, so any DNS blocker that accepts plain domain lists can use them as well.

Türkçe düzenleme kılavuzu aşağıdadır: [Türkçe: listeler nasıl düzenlenir](#türkçe-listeler-nasıl-düzenlenir).

## The lists

| File | What it blocks | Approximate size |
| --- | --- | --- |
| `ads.txt` | Ad networks. It is built on HaGeZi Multi Light, so it also covers many tracking and telemetry hosts. | about 92,000 domains |
| `trackers.txt` | In-app analytics, attribution and user-tracking services. | about 20 domains (a short hand-kept list) |
| `malware.txt` | Hosts that are currently distributing malware. | a few hundred domains |

The counts are approximate and change daily. The exact number is in the comment header of each file.

Raw addresses:

```
https://raw.githubusercontent.com/huseyinemecen2834-alt/vanta-lists/main/ads.txt
https://raw.githubusercontent.com/huseyinemecen2834-alt/vanta-lists/main/trackers.txt
https://raw.githubusercontent.com/huseyinemecen2834-alt/vanta-lists/main/malware.txt
```

These addresses do not change. The installed Vanta app downloads the lists from exactly these URLs.

## Format

- UTF-8 text with LF line endings.
- Lines that start with `#` are comments. Each file begins with a comment header (sources, licence, build date, rule count), written partly in Turkish.
- Every other line is one domain name: lower case, sorted, no duplicates, no IP address prefix, no wildcard characters.
- A line stands for the domain **and all of its subdomains**. `doubleclick.net` also covers `ad.doubleclick.net`. Vanta applies the lists this way. A blocker that treats each line as one exact host name will block less than Vanta does.

## Sources and licences

| File | Built from | Licence |
| --- | --- | --- |
| `ads.txt` | [HaGeZi DNS Blocklists](https://github.com/hagezi/dns-blocklists), Multi Light, "wildcard / only domains" edition, plus this repository's `manual/ads.txt` | GPL-3.0 |
| `malware.txt` | [URLhaus](https://urlhaus.abuse.ch/) by abuse.ch, taken from the "hosts, online" list of [malware-filter/urlhaus-filter](https://gitlab.com/malware-filter/urlhaus-filter), plus this repository's `manual/malware.txt` | URLhaus data: CC0. urlhaus-filter: CC0-1.0 and MIT |
| `trackers.txt` | This repository's `manual/trackers.txt` only | No outside source |

In all three files, every rule that would block a name listed in `manual/allow.txt` is removed.

`ads.txt` is a modified work based on HaGeZi DNS Blocklists and is distributed under the GNU General Public License v3.0. The licence text is in [`LICENSES/GPL-3.0.txt`](LICENSES/GPL-3.0.txt), and the header of `ads.txt` carries the same notice.

The hand-written lists in `manual/` are this repository's own work. No separate licence has been chosen for them yet; where they are merged into `ads.txt`, that file's GPL-3.0 terms apply.

Thanks to HaGeZi, abuse.ch and the malware-filter project. This repository is not affiliated with or endorsed by any of them.

## How the lists are built

`scripts/build.sh` downloads the two upstream lists, reduces every line to a plain domain, merges in the files from `manual/`, removes the rules that conflict with `manual/allow.txt`, and runs sanity checks: size limits, a few well-known ad hosts must still be blocked, and nothing on the allow list may still be blocked. Only when every check passes are the three files replaced. If a download or a check fails, nothing is changed.

The GitHub Actions workflow "Update lists" runs the script once a day, on manual dispatch, and whenever `manual/` or `scripts/` changes on `main`, and commits the result.

The three files in the repository root are generated. Editing them by hand has no lasting effect; changes belong in `manual/`.

---

## Türkçe: listeler nasıl düzenlenir

Bu bölüm deponun sahibi içindir.

### Üç kural

1. Yalnızca `manual/` klasöründeki dört dosyayı düzenle.
2. Kökteki `ads.txt`, `trackers.txt` ve `malware.txt` dosyalarını elle düzenleme. Bunları `scripts/build.sh` üretir; elle yaptığın değişiklik bir sonraki üretimde silinir.
3. Kökteki bu üç dosyanın adını değiştirme, yerini değiştirme, dosyayı silme. Telefonlardaki uygulama listeleri tam bu adreslerden indirir; adres değişirse kurulu uygulamalar listeyi bir daha güncelleyemez.

### Hangi dosya ne işe yarar

| Dosya | İçine ne yazılır |
| --- | --- |
| `manual/ads.txt` | HaGeZi listesine ek olarak engellenecek reklam alan adları |
| `manual/trackers.txt` | İzleyiciler. Kökteki `trackers.txt` yalnızca bu dosyadan üretilir |
| `manual/malware.txt` | URLhaus listesine ek olarak engellenecek zararlı alan adları |
| `manual/allow.txt` | Hiçbir listede engellenmemesi gereken adlar |

### Nasıl yazılır

- Her satıra bir alan adı: `ornek.com`. Başına `https://`, sonuna `/sayfa` ekleme.
- Bir kural alt alan adlarını da engeller: `ornek.com` yazınca `reklam.ornek.com` da engellenir.
- `#` ile başlayan satır açıklamadır.
- Alan adı olmayan satır atlanır ve iş akışında uyarı olarak görünür; diğer satırlar etkilenmez.

### `allow.txt` ne içindir

Bir uygulama listeler yüzünden bozulduysa (giriş yapılamıyor, ödeme açılmıyor, bildirim gelmiyor), bozulan adı `manual/allow.txt` dosyasına yaz. O adı ya da onun üst alan adını engelleyen kural üç listeden de çıkarılır. Örnek: `www.google.com` bu dosyadayken `google.com` kuralı hiçbir listeye giremez.

Bu dosya telefona inmez; yalnızca listelerin üretimini etkiler. Bir kullanıcının uygulamada kendi eklediği engeli kaldırmaz.

### Değişikliği gönderme

En kolay yol GitHub sitesidir: dosyayı aç, kalem simgesine bas, düzenle, **Commit changes** de.

Bilgisayardan yapacaksan:

1. Önce `git pull`. İş akışı bu depoya her gün kendi kaydını (commit) atar; çekmeden gönderirsen GitHub reddeder.
2. `manual/` altındaki dosyayı düzenle ve kaydet.
3. `git add manual`, sonra `git commit -m "kısa açıklama"`, sonra `git push`.

İki yolda da birkaç dakika içinde "Update lists" iş akışı kendiliğinden çalışır ve kökteki dosyaları yeniler. Telefondaki uygulama yeni listeyi, kopyası 24 saatten eskiyse bir sonraki açılışta ya da "Şimdi güncelle" düğmesiyle alır.

### İş akışını elle çalıştırma

GitHub'da bu depo > **Actions** > soldaki listeden **Update lists** > **Run workflow** > yeşil **Run workflow** düğmesi. İş akışı ayrıca her gün yaklaşık 06:17'de (Türkiye saati) kendiliğinden çalışır.

### İş akışı kırmızı olursa

Kökteki dosyalar değişmemiştir, eski listeler yayında kalır. Günlükte `HATA` ya da `DENETİM TUTMADI` ile başlayan satırı oku. En sık iki neden:

- Kaynak liste indirilemedi. Biraz sonra iş akışını elle yeniden çalıştır.
- `manual/allow.txt` dosyasına eklenen bir ad, engellenmesi zorunlu bir reklam adının kuralını listeden çıkardı. Son eklediğin satırı geri al.

### Bilgisayarda deneme (gerekli değil)

Git Bash'te `bash scripts/build.sh` aynı üretimi bilgisayarda yapar ve kökteki üç dosyayı değiştirir. Sonrasında `git pull` bu dosyalar yüzünden hata verirse, önce `git restore ads.txt trackers.txt malware.txt` ile yerel değişikliği geri al.
