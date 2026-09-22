# Jitsi Meet — bepul video konferensiya serveri

Telefon hotspot yoki oddiy uy internetida noutbukdagi Jitsi boshqa davlatlardan
ochilmaydi: operator bergan IP (masalan `92.63.204.38`) o'nlab abonent bilan
bo'lishiladi va port forwarding qilib bo'lmaydi. Yechim — tashqaridan
ko'rinadigan server.

Bu papkada ikkita tayyor yo'l bor.

---

## Qaysi variantni tanlash

| | Narxi | Server kerakmi | HTTPS | Cheklov |
|---|---|---|---|---|
| **A. `meet.jit.si`** (ommaviy Jitsi) | 0 $ | Yo'q | Tayyor | Xona 8x8 serverida; brend o'zingizniki emas |
| **B. Oracle Cloud Always Free** | 0 $ | Ha (4 CPU / 24 GB) | Let's Encrypt | Karta bilan ro'yxatdan o'tish; A1 quvvati ba'zan tugaydi |
| ~~C. GitHub~~ | — | — | — | **Ishlamaydi** — pastga qarang |

### Nega GitHub'ni server qilib bo'lmaydi

Savol tabiiy, lekin texnik jihatdan iloji yo'q:

* **GitHub Pages** faqat *statik* fayl tarqatadi (HTML/CSS/JS). Jitsi'ga esa
  doimiy ishlab turadigan jarayonlar kerak: Prosody (XMPP), Jicofo, JVB
  (videobridge). Pages'da hech qanday server jarayoni ishlamaydi.
* **Videobridge UDP 10000 portini** talab qiladi. GitHub faqat 443/HTTPS
  beradi — ovoz va video umuman o'tmaydi.
* **GitHub Actions** — bu CI, server emas: bitta job maksimum 6 soat yashaydi,
  barqaror public IP yo'q, kiruvchi ulanishlarni qabul qilmaydi. Uni doimiy
  xizmat sifatida ishlatish GitHub shartlarida ham taqiqlangan.
* **Codespaces** port forwarding beradi, lekin faqat TCP/HTTPS, bir necha
  daqiqadan keyin uxlaydi va bepul soatlar cheklangan.

GitHub bu yerda faqat **kodni saqlash** uchun kerak (shu papkadagi skriptlar).
Jitsi esa alohida serverda turishi shart.

---

## Variant A — serversiz (eng tez, 5 daqiqa)

Bot `meet.jit.si` da tasodifiy xona ochib, havolani yuboradi. Hech narsa
o'rnatilmaydi, hech kim to'lamaydi.

```bash
python3 deploy/jitsi/jitsi_link.py
# Xona: dars-OWwvoKcw
# Havola: https://meet.jit.si/dars-OWwvoKcw#config.startWithAudioMuted=true...
```

Botga ulash (aiogram 3):

```python
from deploy.jitsi.jitsi_link import meeting_link

@admin_router.message(Command("dars"))
async def start_lesson(message: Message):
    link, room = meeting_link(prefix="dars")
    await message.answer(
        f"Dars xonasi tayyor:\n{link}\n\nHavolani o'quvchilarga yuboring."
    )
```

Xona nomi tasodifiy (`dars-OWwvoKcw`), shuning uchun begonalar taxmin qilib
kira olmaydi. Keyinchalik o'z serveringiz paydo bo'lsa, faqat bitta o'zgaruvchi
almashadi:

```bash
export JITSI_BASE_URL=https://meet.example.com
```

---

## Variant B — Oracle Cloud Always Free

4 ta ARM yadro va 24 GB RAM — Jitsi uchun mo'l-ko'l. Har oyda 0 $.

### 0-qadam: hisob ochish (buni faqat siz qila olasiz)

1. <https://www.oracle.com/cloud/free/> → **Start for free**
2. Mamlakat, email, telefon tasdiqlash.
3. Bank kartasi — **tekshirish uchun**, pul yechilmaydi (odatda ~1 $ ushlab
   turiladi va qaytariladi). Upgrade tugmasini bosmasangiz hech qachon
   to'lov bo'lmaydi.
4. Home region'ni yaqinroq tanlang: `eu-frankfurt-1` yoki `me-dubai-1`.
   **Home region keyin o'zgarmaydi.**

### 1-qadam: domen (ixtiyoriy, lekin tavsiya qilinadi)

HTTPS sertifikati uchun domen kerak. Bepul variant — DuckDNS:

1. <https://www.duckdns.org> → GitHub bilan kirish
2. `maktab-iqtidor` kabi nom yarating → `maktab-iqtidor.duckdns.org`
3. Server IP'si ma'lum bo'lgach, o'sha IP'ni DuckDNS'ga yozasiz.

Domensiz ham ishlaydi, lekin brauzer "sertifikat ishonchsiz" deb ogohlantiradi
va o'quvchilar har safar "Advanced → Proceed" bosishi kerak bo'ladi.

### 2-qadam: server yaratish

#### B1. Qo'lda (Console orqali)

1. Oracle Console → **Compute → Instances → Create instance**
2. **Image:** Canonical Ubuntu 22.04
3. **Shape:** `VM.Standard.A1.Flex` → 4 OCPU, 24 GB
4. SSH public key'ingizni qo'shing → **Create**
5. Instance tayyor bo'lgach, **Networking → VCN → Security Lists →
   Default Security List → Add Ingress Rules:**

   | Source | Protokol | Port |
   |---|---|---|
   | `0.0.0.0/0` | TCP | 80 |
   | `0.0.0.0/0` | TCP | 443 |
   | `0.0.0.0/0` | UDP | 10000 |

6. DuckDNS'da (yoki domeningiz DNS'ida) **A yozuvi**ni server IP'siga yo'naltiring.
7. Skriptni serverga yuborib, ishga tushiring:

```bash
scp deploy/jitsi/setup.sh ubuntu@<SERVER_IP>:~
ssh ubuntu@<SERVER_IP>
sudo ./setup.sh --domain maktab-iqtidor.duckdns.org --email siz@example.com
```

10-15 daqiqada `https://maktab-iqtidor.duckdns.org` ochiladi.

#### B2. Terraform bilan (hammasi avtomatik)

Serverni ham, tarmoqni ham, Jitsi'ni ham bitta buyruq yaratadi.

```bash
cd deploy/jitsi/terraform
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars ni to'ldiring (OCID'lar: Console → Profile → API Keys)
terraform init
terraform apply
```

Chiqishda IP va havola ko'rinadi:

```
public_ip  = "140.238.x.x"
dns_record = "A  maktab-iqtidor.duckdns.org  ->  140.238.x.x"
jitsi_url  = "https://maktab-iqtidor.duckdns.org"
```

DNS yozuvini qo'ying va 10 daqiqa kuting. O'rnatishni kuzatish:

```bash
ssh ubuntu@140.238.x.x 'sudo tail -f /var/log/jitsi-setup.log'
```

---

## Faqat o'qituvchi xona ocha olsin

`--auth` bilan o'rnatilsa (yoki Terraform'da `enable_auth = true`), xonani
faqat parol bilan kirgan foydalanuvchi ocha oladi; o'quvchilar mehmon
sifatida qo'shiladi:

```bash
cd /opt/jitsi/docker-jitsi-meet
sudo docker compose exec prosody /usr/bin/prosodyctl \
  --config /config/prosody.cfg.lua register ustoz meet.jitsi KUCHLI_PAROL
```

---

## Boshqaruv

`setup.sh` serverga `jitsi` buyrug'ini o'rnatadi:

```bash
jitsi status     # konteynerlar holati
jitsi logs       # loglar
jitsi restart    # qayta ishga tushirish
jitsi update     # yangi versiyaga o'tish
jitsi stop
```

Konfiguratsiya: `/opt/jitsi/docker-jitsi-meet/.env`
Sozlama fayllari: `/opt/jitsi/cfg/`

---

## Muammolar

**`Out of host capacity`** — A1 quvvati o'sha Availability Domain'da tugagan.
Bu Always Free'da tez-tez uchraydi. Terraform'da
`availability_domain_number = 2` (yoki 3) qilib ko'ring, yoki bir necha soatdan
keyin qayta urinib ko'ring.

**Sahifa ochiladi, lekin ovoz/video yo'q** — deyarli har doim UDP 10000 yopiq.
Ikkala joyda ham ochilishi shart:
1. Oracle Security List (yuqoridagi jadval),
2. serverning o'z iptables'i — `setup.sh` buni avtomatik qiladi. Tekshirish:
   `sudo iptables -L INPUT -n --line-numbers | grep 10000`

**Sertifikat olinmadi** — `A` yozuvi hali tarqalmagan yoki 80-port yopiq.
Tekshirish: `dig +short sizning.domeningiz` server IP'sini qaytarishi kerak.
Keyin: `cd /opt/jitsi/docker-jitsi-meet && sudo docker compose logs web`

**Sekin / uziladi** — bir xonada 20+ ishtirokchi bo'lsa A1 ning 4 yadrosi
yetmasligi mumkin. Videoni o'chirib, faqat ovozda o'tkazish yordam beradi.
