# Botni serversiz onlayn qilish (Vercel + webhook)

Bot 24/7 ishlaydi, lekin hech qanday server ijaraga olinmaydi va hech narsa
"deploy qilib qo'yilmaydi" — kompyuteringiz o'chiq bo'lsa ham bot javob beradi.

## Qanday ishlaydi

**Eski usul (polling):** bot kompyuteringizda doim ishlab turadi va har soniyada
Telegram'dan "yangi xabar bormi?" deb so'raydi. Kompyuter o'chsa — bot o'ladi.

**Yangi usul (webhook):** Telegram xabar kelganda uni o'zi sizning
manzilingizga yuboradi. Funksiya uyg'onadi, javob beradi va o'chadi.

```
O'qituvchi  ──/dars──>  Telegram  ──POST──>  Vercel funksiyasi
                                                   │
                                            havola yasaydi
                                                   │
O'qituvchi  <──javob──  Telegram  <──────────────┘
```

Hech narsa doimiy ishlab turmaydi, shuning uchun bepul va o'chmaydi.

## Kerak bo'ladigan narsalar

| Nima | Qayerdan | Narxi |
|---|---|---|
| Bot tokeni | @BotFather → `/newbot` yoki `/token` | 0 $ |
| Vercel hisobi | <https://vercel.com> → GitHub bilan kirish | 0 $, karta so'ramaydi |

Boshqa hech qanday API, kalit yoki to'lov kerak emas. Jitsi uchun ham kalit
kerak emas — havola oddiy URL.

## O'rnatish

### 1. Vercel'ga ulash

1. <https://vercel.com/new> → GitHub bilan kiring
2. `Iqtidor_bot_aniqla` reposini tanlang → **Import**
3. Hech narsani o'zgartirmasdan **Deploy** bosing

Natijada `https://iqtidor-bot-aniqla.vercel.app` kabi manzil olasiz.

### 2. Muhit o'zgaruvchilari

Vercel → loyiha → **Settings → Environment Variables**:

| Nomi | Qiymati | Majburiymi |
|---|---|---|
| `BOT_TOKEN` | @BotFather bergan token | ha |
| `WEBHOOK_SECRET` | o'zingiz o'ylagan tasodifiy matn | ha (himoya uchun) |
| `ADMIN_ID` | sizning Telegram ID'ingiz | ha |
| `TEACHER_IDS` | boshqa o'qituvchilar ID'lari, vergul bilan | yo'q |
| `JITSI_BASE_URL` | o'z Jitsi serveringiz bo'lsa | yo'q |
| `ALLOW_EVERYONE` | `1` bo'lsa hamma xona ocha oladi | yo'q |

Telegram ID'ingizni bilish uchun @userinfobot ga yozing.

O'zgaruvchilarni qo'shgandan keyin **Deployments → ... → Redeploy** bosing,
aks holda ular kuchga kirmaydi.

### 3. Webhook'ni ulash

Kompyuteringizda bir marta:

```bash
export BOT_TOKEN=...          # yangi token
export WEBHOOK_SECRET=...     # Vercel'dagi bilan bir xil
python3 scripts/set_webhook.py https://iqtidor-bot-aniqla.vercel.app/api/telegram
```

Tekshirish:

```bash
python3 scripts/set_webhook.py --info
```

`"pending_update_count": 0` va xatosiz bo'lsa — tayyor. Botga `/dars` yozing.

## Buyruqlar

| Buyruq | Nima qiladi |
|---|---|
| `/start` | Tanishtiruv |
| `/dars` | Yangi tasodifiy xona havolasi |
| `/dars Fizika 9-A` | Nomli xona (`fizika-9-a-5wqaejai`) |
| `/help` | Yo'riqnoma |

Xona ochish faqat `ADMIN_ID` va `TEACHER_IDS` dagilarga ruxsat etilgan.
Hammaga ochish uchun `ALLOW_EVERYONE=1` qo'ying.

## Cheklovlar — halol aytganda

* **Testlar bo'limi bu yerga ko'chmagan.** Hozirgi test boti (`main.py`,
  `handlers/`, `database/`) foydalanuvchining javoblarini eslab turadi —
  serverless funksiya esa har safar noldan uyg'onadi, hech narsa eslamaydi.
  Uni ko'chirish uchun holatni bazada saqlash kerak bo'ladi (Vercel Postgres
  yoki Upstash Redis — ikkalasining ham bepul darajasi bor). Ayting, qilaman.
* **Sovuq start:** birinchi xabarga javob 1-2 soniya kechikishi mumkin.
* **Bepul limit:** kuniga 100 000 so'rov — maktab uchun mo'l-ko'l.
* Bir vaqtda faqat bitta usul ishlaydi: webhook yoqilsa, `main.py` dagi
  polling bot ishlamaydi. Qaytarish uchun:
  `python3 scripts/set_webhook.py --delete`

## Muammolar

**Bot javob bermayapti** — `--info` da `last_error_message` ni o'qing.
`403` bo'lsa `WEBHOOK_SECRET` Vercel'dagi bilan mos emas. `404` bo'lsa manzil
xato (`/api/telegram` qismini unutmang).

**"Kechirasiz, xona ochish faqat o'qituvchilar uchun"** — `ADMIN_ID` noto'g'ri
yoki Redeploy qilinmagan.

**Vercel loglari:** loyiha → Deployments → oxirgisi → **Runtime Logs**.
