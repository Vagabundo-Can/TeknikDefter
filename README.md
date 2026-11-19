# Teknik Defter

Mühendislik ve motosiklet eğitimi için kalem odaklı not uygulaması — Android tablet, Android telefon ve Windows; tek Flutter kod tabanı, Google Drive senkronu.

Spesifikasyon: Claude Docs'taki "Not Uygulaması — Mimari ve Spesifikasyon" dokümanı.

## Klasörler

| Klasör | İçerik |
| --- | --- |
| `lib/models` | Veri modeli, JSON, eleman düzeyinde senkron birleştirme |
| `lib/ink` | 1 € filtresi, Chaikin yumuşatma, şekil tanıma, el yazısı hizalama, kalem çizimi (ISO 128 çizgi tipleri) |
| `lib/canvas` | Editör denetleyicisi (geri al/yinele, seçim, silgi), tuval (kalem/parmak/fare), eleman çizicileri (ölçü, GD&T, yüzey, kaynak, koni, şerit) |
| `lib/templates` | 15 şablon: mühendislik + motosiklet eğitim |
| `lib/sync` | Google girişi (Android: google_sign_in · Windows: loopback OAuth), Drive appDataFolder senkronu |
| `lib/recognition` | El yazısı → metin (Android: ML Kit Digital Ink `tr`; Windows: Faz 2 eklenti kanalı) |
| `lib/ui` | Ana ekran, yeni sayfa sihirbazı, editör, araç ayarları, senkron düğmesi |

## İlk kurulum

1. Bu klasörü GitHub'da özel bir depoya koy (ör. `Vagabundo-Can/TeknikDefter`). `android/` ve `windows/` klasörleri yoksa GitHub Actions `flutter create` ile üretir; yerelde de aynısını çalıştır:
   ```
   flutter create --platforms=android,windows --org com.vagabundo --project-name teknik_defter .
   del test\widget_test.dart
   ```
   Release manifestine `<uses-permission android:name="android.permission.INTERNET"/>` ekle (Flutter şablonu yalnız debug'a koyar; workflow bunu otomatik yapar).

2. **Google Cloud Console** (tek proje):
   - *APIs & Services → Library*: **Google Drive API**'yi etkinleştir.
   - *OAuth consent screen*: External, uygulama adı "Teknik Defter", kapsam `.../auth/drive.appdata`. Test aşamasında kendi Gmail adresini **Test users**'a ekle (yayınlamadan kullanılabilir).
   - *Credentials → Create OAuth client ID → Android*: paket adı `com.vagabundo.teknik_defter`, SHA-1 = imzalayan anahtarın SHA-1'i (aşağıda).
   - *Credentials → Create OAuth client ID → Desktop app*: çıkan Client ID ve Client secret Windows derlemesinde kullanılır.

3. **Sabit Android anahtarı** (her CI derlemesinde aynı SHA-1 için):
   ```
   keytool -genkeypair -v -keystore debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
   keytool -list -v -keystore debug.keystore -storepass android      # SHA1 satırını Android OAuth istemcisine gir
   certutil -encode debug.keystore ks.b64                            # (Windows) içeriği tek satır yap
   ```
   GitHub → Settings → Secrets → Actions:
   - `ANDROID_DEBUG_KEYSTORE_B64` = keystore'un base64'ü
   - `GOOGLE_DESKTOP_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_SECRET` = masaüstü istemci

4. `main`'e push → Actions: analiz + test + `app-release.apk` + `teknik-defter-windows.zip` artefaktları. `v0.1.0` etiketi → GitHub Release.

## Yerel derleme

```
flutter pub get
flutter test
flutter run -d <tablet>                       # Android
flutter run -d windows --dart-define=GOOGLE_DESKTOP_CLIENT_ID=... --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=...
```

## Kullanım notları

- Tablette varsayılan **Yalnızca kalem**: parmak kaydırır, iki parmak zoom, iki parmakla dokunma = geri al. S Pen yan tuşu basılıyken silgi.
- Kalem çizgisini bitirip **450 ms basılı tut** → çizgi/dikdörtgen/üçgen/daire olur.
- **Kement** ile seç → *Metne çevir* (ML Kit, ilk kullanımda Türkçe modeli iner), *Hizala*, *Şekle oturt*, renk, çoğalt, sil.
- **Ölçü**: nokta 1 → sürükle → nokta 2 → ölçü çizgisinin yerine dokun. Değer sayfa ölçeğinden hesaplanır (Sayfa menüsü → Ölçek). R/Ø araçları çizili daireye dokununca merkezini yakalar.
- **Koni**: "Dizi 3 m" seçiliyken sürükle → 3 m aralıklı slalom dizisi; koni sayısı başlık altında.
- Windows kısayolları: P, H, E, L, S, D, T, C · Ctrl+Z/Y · Ctrl+S senkron · Ctrl+0 sığdır · Ctrl+D çoğalt · Space+sürükle / orta tuş kaydır · Ctrl+tekerlek zoom.

## Faz 2 / 3

Windows el yazısı tanıma eklentisi (InkRecognizerContainer), cetvel/açıölçer, PDF dışa aktarma, ISO 286 tolerans tablosu, hesap bloğu, PDF içe aktarıp üstüne yazma, sayfa küçük resim önbelleği.
