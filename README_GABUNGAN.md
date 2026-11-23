# Flutter Food Store - gabungan proyek asli + versi fitur Dewi

Folder ini mempertahankan struktur dan file platform dari proyek asli kamu.
Halaman aplikasi utama di `lib/main.dart` diganti dengan versi Food Store yang memiliki
login/register, beranda, kategori, produk, pencarian, keranjang, pesanan, dan profil.

## Menjalankan
1. Buka folder `flutter_foodstore` di VS Code.
2. Jalankan `flutter pub get`.
3. Jalankan `flutter run`.

## Alamat API
Di `lib/main.dart`, cari `ApiConfig`.
- Android Emulator: `http://10.0.2.2:8000/api/`
- Flutter Web/Desktop: ubah menjadi `http://localhost:8000/api/`
- HP fisik: gunakan IP LAN komputer yang menjalankan Laravel, misalnya `http://192.168.x.x:8000/api/`

Pastikan server Laravel aktif dan endpoint API sesuai dengan proyek Laravel kamu.
File lama selain `lib/main.dart` tetap disimpan; beberapa file lama mungkin tidak lagi dipakai oleh halaman utama.
