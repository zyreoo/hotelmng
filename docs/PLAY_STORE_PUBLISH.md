# Publishing Stayora (hotelmng) to Google Play Store

## 1. Google Play Developer account

- Go to [Google Play Console](https://play.google.com/console).
- Sign in with a Google account and **register as a developer** (one-time **$25** fee).
- Accept the Developer Distribution Agreement.

---

## 2. Prepare your app for release

### 2.1 Unique application ID (package name)

Your app must use a **unique package name** that you own. Replace `com.example.hotelmng` with something like:

- `com.stayora.app`
- `com.yourcompany.stayora`
- `com.yourdomain.hotelmng`

**Important:** Once you publish the first version, you **cannot change** the application ID. Choose carefully.

Update it in:
- `android/app/build.gradle.kts` → `applicationId`
- `android/app/build.gradle.kts` → `namespace` (same value)
- MainActivity package: `android/app/src/main/kotlin/.../` folder and `package` in `MainActivity.kt`

### 2.2 App signing (required for Play Store)

1. **Create a keystore** (one-time, keep it safe and backed up):

   ```bash
   keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

   You’ll be asked for a password and details (name, org, etc.). **Do not lose this file or password** — you need them for all future updates.

2. **Create `android/key.properties`** (do **not** commit to git):

   ```properties
   storePassword=YOUR_KEYSTORE_PASSWORD
   keyPassword=YOUR_KEY_PASSWORD
   keyAlias=upload
   storeFile=../upload-keystore.jks
   ```

   Use `storeFile` as path to your keystore: **relative to the `android` folder** (e.g. `../upload-keystore.jks` if the keystore is in the project root) or an absolute path (e.g. `/Users/yourname/upload-keystore.jks`).

3. **Configure release signing** in `android/app/build.gradle.kts` (see project file; `key.properties` is loaded and used for `release` buildType).

### 2.3 App name and icon

- **Name:** Set in `android/app/src/main/AndroidManifest.xml` → `android:label` (e.g. `"Stayora"`).
- **Icon:** Replace `android/app/src/main/res/mipmap-*/ic_launcher.png` with your app icon (multiple densities). Use [Adaptive Icon](https://developer.android.com/develop/ui/views/launch/icon_design_adaptive) for best results.

### 2.4 Version

- In `pubspec.yaml`: `version: 1.0.0+1` (versionName `1.0.0`, versionCode `1`).
- For each Play Store upload, increase at least `versionCode` (e.g. `1.0.0+2`, then `1.0.1+3`, etc.).

---

## 3. Build the release app bundle (AAB)

From the project root:

```bash
flutter clean
flutter pub get
flutter build appbundle
```

Output: `build/app/outputs/bundle/release/app-release.aab`.

---

## 4. Create the app in Play Console

1. In [Play Console](https://play.google.com/console), click **Create app**.
2. Fill in:
   - App name (e.g. **Stayora**)
   - Default language
   - App or game → **App**
   - Free or paid → **Free** (or Paid if you charge)
3. Accept declarations (e.g. export laws, policies).

---

## 5. Complete the store listing

In Play Console → your app → **Main store listing**:

- **Short description** (max 80 characters)
- **Full description** (max 4000 characters)
- **App icon:** 512×512 px PNG
- **Feature graphic:** 1024×500 px (optional but recommended)
- **Screenshots:** At least 2 phone screenshots (e.g. 1080×1920 or 9:16). Add more for 7" and 10" tablets if you support them.
- **Category** (e.g. Business or Productivity)
- **Contact details** (email, privacy policy URL if you collect data)

---

## 6. Set up content rating and target audience

- **Content rating:** Complete the questionnaire (e.g. “Everyone” or “Teen” depending on content).
- **Target audience:** Select age groups.
- **News app / COVID-19 / data safety:** Answer as required; add a **Privacy policy** URL if you collect user/data (Firebase often requires this).

---

## 7. Upload the AAB and release

1. Go to **Release** → **Production** (or **Testing** first).
2. **Create new release**.
3. **Upload** `app-release.aab` from `build/app/outputs/bundle/release/`.
4. Add **Release name** (e.g. `1.0.0 (1)`) and **Release notes**.
5. **Review and roll out** (or send for review).

After review (often 1–3 days), the app will be available on the Play Store.

---

## Quick checklist

- [ ] Developer account ($25) and app created in Play Console
- [ ] `applicationId` and namespace updated (no `com.example`)
- [ ] Keystore created and `key.properties` configured
- [ ] Release build uses signing config (no debug signing in release)
- [ ] App name and icon set in Android
- [ ] Store listing, screenshots, and feature graphic ready
- [ ] Content rating and privacy policy (if needed) done
- [ ] `flutter build appbundle` succeeds
- [ ] AAB uploaded and release submitted

---

## Optional: Test before production

- Use **Internal testing** or **Closed testing** in Play Console.
- Upload the same AAB and add testers by email to install from the Play Store link.
