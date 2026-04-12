# Google Play Store – Setup & Submission Guide

## 1. Keystore Generation (one-time, do this first)

A release keystore is required to sign the AAB you upload to Google Play.
**Keep the `.jks` file and its passwords safe — losing the keystore means you
cannot update the app on Play Store.**

### Generate the keystore (run once, on any machine with Java/JDK installed)

```bash
keytool -genkey -v \
  -keystore inhauski-release.jks \
  -alias inhauski \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storetype PKCS12
```

You will be prompted for:
- **Keystore password** – choose a strong password, save it
- **Key alias** – use `inhauski` (matches the `-alias` above)
- **Key password** – can be same as keystore password
- **Distinguished name** – name, org, city, country (any values work)

---

## 2. Add Keystore Secrets to GitHub Actions

In your GitHub repository go to:
**Settings → Secrets and variables → Actions → New repository secret**

Add these four secrets:

| Secret name        | Value                                              |
|--------------------|----------------------------------------------------|
| `KEYSTORE_BASE64`  | Base64-encoded contents of `inhauski-release.jks`  |
| `KEYSTORE_PASSWORD`| The keystore/store password you chose              |
| `KEY_ALIAS`        | `inhauski`                                         |
| `KEY_PASSWORD`     | The key password you chose                         |

### How to base64-encode the keystore

**macOS / Linux:**
```bash
base64 -i inhauski-release.jks | pbcopy   # copies to clipboard (macOS)
base64 -i inhauski-release.jks            # Linux — copy the output
```

**Windows (PowerShell):**
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("inhauski-release.jks")) | clip
```

Once the secrets are added, every push to `master` will build **both** the
debug APK and the signed release AAB. The AAB is uploaded as a GitHub Actions
artifact named `app-release-aab`.

---

## 3. Enable Google Play App Signing (recommended)

When uploading the **first** AAB to Play Console:
1. Go to **Setup → App signing**
2. Choose **"Use Google Play App Signing"** (recommended)
3. Upload your signing certificate

This means Google holds the final signing key and can re-sign if you ever
lose your upload key. Your `inhauski-release.jks` becomes the *upload key*,
not the final distribution key.

---

## 4. Application ID

The app's package name / application ID is:

```
com.inhauski.app
```

This is set during CI by the post-create fixup step. Once published to Play
Store, this ID **cannot be changed**.

---

## 5. Version Bumping

The version is set in `pubspec.yaml`:

```yaml
version: 1.0.0+1
#         ↑     ↑
#    versionName  versionCode (must increase with every Play upload)
```

- `versionCode` (`+N`) must be a higher integer for every new upload to Play Store.
- `versionName` (`1.0.0`) is the human-readable version shown to users.

---

## 6. Privacy Policy URL

The privacy policy is served via GitHub Pages from the `docs/` folder.

**URL:** `https://minemeraj.github.io/inhauski-mobile/privacy-policy.html`

To enable GitHub Pages:
1. Go to your repository → **Settings → Pages**
2. Source: **Deploy from a branch**
3. Branch: `master`, Folder: `/docs`
4. Save

The privacy policy URL above will be live within a few minutes.
Use this URL in the Play Console **App content → Privacy policy** field.

---

## 7. Play Console Checklist

### App information
- **App name:** InHausKI
- **Short description (80 chars max):**
  `Offline AI chat assistant — no cloud, no tracking, fully private.`
- **Category:** Productivity
- **Contact email:** (your email)
- **Privacy policy URL:** `https://minemeraj.github.io/inhauski-mobile/privacy-policy.html`

### Store listing — Full description (English, 4000 chars max)

```
InHausKI is a fully offline AI chat assistant that runs entirely on your device.
No internet connection is required after the initial model download. No data
ever leaves your phone.

KEY FEATURES

• 100% Offline — All AI inference runs locally using llama.cpp. Your
  conversations are never sent to any server.

• Privacy First — No accounts, no analytics, no ads, no tracking of any kind.
  Your data stays on your device, period.

• Document Chat (RAG) — Import your own text files and Markdown documents.
  The AI can answer questions about your documents using on-device vector search.

• Resumable Download — The AI model (~2.9 GB) is downloaded once on first
  launch with full pause/resume support. After that, everything works offline.

• GPU Accelerated — Supports OpenCL GPU acceleration on compatible Android
  devices for faster responses.

• Multilingual — Fully available in English and German (Deutsch).

TECHNICAL DETAILS

• AI Model: Gemma 4 2B Instruct (Q4_K_M quantization, ~2.9 GB download)
• Embedding Model: multilingual-e5-small (~90 MB, optional, for document search)
• Storage: All data stored locally in app-private storage
• Minimum Android: 5.0 (API 21)

FIRST LAUNCH

On first launch, the app will guide you through a one-time setup wizard:
1. Choose your language
2. Select AI model and GPU mode
3. Download the AI model (~2.9 GB — Wi-Fi recommended)
4. Optionally download the embedding model (~90 MB) for document search

After setup, the app works completely offline.

PRIVACY

InHausKI collects zero personal data. See the full privacy policy at:
https://minemeraj.github.io/inhauski-mobile/privacy-policy.html
```

### Store listing — Full description (German)

```
InHausKI ist ein vollständig offline betriebener KI-Chat-Assistent, der
ausschließlich auf Ihrem Gerät läuft. Nach dem einmaligen Modell-Download
ist keine Internetverbindung mehr erforderlich. Keine Daten verlassen Ihr Gerät.

HAUPTFUNKTIONEN

• 100% Offline — Alle KI-Berechnungen laufen lokal über llama.cpp. Ihre
  Gespräche werden niemals an einen Server übertragen.

• Datenschutz an erster Stelle — Keine Konten, keine Analysen, keine Werbung,
  kein Tracking. Ihre Daten bleiben auf Ihrem Gerät.

• Dokumenten-Chat (RAG) — Importieren Sie eigene Text- und Markdown-Dateien.
  Die KI kann Fragen zu Ihren Dokumenten mit lokaler Vektorsuche beantworten.

• Fortsetzbarer Download — Das KI-Modell (~2,9 GB) wird einmalig beim ersten
  Start heruntergeladen, mit vollständiger Pause-/Fortsetzungsfunktion.

• GPU-Beschleunigung — Unterstützt OpenCL-GPU-Beschleunigung auf kompatiblen
  Android-Geräten für schnellere Antworten.

• Mehrsprachig — Vollständig auf Englisch und Deutsch verfügbar.

TECHNISCHE DETAILS

• KI-Modell: Gemma 4 2B Instruct (Q4_K_M Quantisierung, ~2,9 GB Download)
• Einbettungsmodell: multilingual-e5-small (~90 MB, optional, für Dokumentensuche)
• Speicherung: Alle Daten lokal im privaten App-Speicher
• Mindest-Android: 5.0 (API 21)

ERSTER START

Beim ersten Start führt ein Einrichtungsassistent durch die Einmaleinrichtung:
1. Sprache wählen
2. KI-Modell und GPU-Modus auswählen
3. KI-Modell herunterladen (~2,9 GB — WLAN empfohlen)
4. Optional: Einbettungsmodell herunterladen (~90 MB) für Dokumentensuche

Nach der Einrichtung funktioniert die App vollständig offline.

DATENSCHUTZ

InHausKI erfasst keinerlei personenbezogene Daten. DSGVO-konform.
Vollständige Datenschutzerklärung:
https://minemeraj.github.io/inhauski-mobile/privacy-policy.html
```

---

## 8. Data Safety Form (Play Console → App content → Data safety)

Answer every question as follows:

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data collected by your app encrypted in transit? | N/A (no data collected) |
| Do you provide a way for users to request that their data is deleted? | **Yes** — via "Reset setup" in app settings |

---

## 9. Content Rating (IARC Questionnaire)

In Play Console → **App content → Content ratings**, complete the IARC questionnaire:

- **Category:** Utility / Productivity
- Violence: **No**
- Sexual content: **No**
- Profanity: **No**
- Controlled substances: **No**
- User-generated content / Social features: **No** (all local, no sharing)

Expected rating: **Everyone** (PEGI 3 / ESRB Everyone)

> Note: If you prefer a conservative stance given the LLM can generate
> unrestricted text, select "Teen" instead. Both are defensible.

---

## 10. Required Graphics

| Asset | Size | Notes |
|---|---|---|
| App icon | 512 × 512 px PNG | No transparency, no rounded corners (Play adds them) |
| Feature graphic | 1024 × 500 px JPG/PNG | Shown at top of store listing |
| Phone screenshots | min 2, max 8 | Min 320px short side, max 3840px long side |

Screenshots must show real app functionality (setup wizard, chat, documents screen).

---

## 11. Closed Testing (New Accounts Only)

If your Google Play developer account was created **after November 13, 2023**,
you must complete a closed test before publishing to production:

1. In Play Console, go to **Testing → Closed testing → Create track (Alpha)**
2. Upload the release AAB
3. Add at least **12 testers** (Gmail addresses) under **Testers**
4. Share the opt-in URL with your testers
5. Wait **14 consecutive days** with ≥12 opted-in testers having the app installed
6. Then apply for **Production access** in Play Console
7. Google reviews and approves within ~7 days

Total time before you can go live: **~3–4 weeks** from when you start the closed test.
