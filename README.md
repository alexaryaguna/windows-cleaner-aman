# Windows Cleaner Aman

Windows Cleaner Aman adalah aplikasi pembersih sampah Windows yang dibuat agar mudah dipakai oleh orang awam. Aplikasi ini berjalan dengan satu klik, membersihkan file-file sementara yang aman untuk dibuang, lalu dapat mengulang pembersihan otomatis setiap 30 menit selama aplikasinya masih terbuka.

## Cocok untuk

- Windows 10 32-bit
- Windows 10 64-bit
- Windows 11 64-bit

## Fitur utama

- **One click cleaning**: cukup jalankan `Run Cleaner.cmd`, lalu klik **Bersihkan Sekarang**.
- **Loop otomatis 30 menit**: bila opsi auto-clean aktif, aplikasi akan membersihkan ulang setiap 30 menit selama jendela aplikasi tetap terbuka.
- **Aman untuk file pribadi**: aplikasi **tidak** menghapus `Documents`, `Downloads`, `Desktop`, atau file pribadi lain.
- **Laporan hasil pembersihan**: aplikasi menampilkan apa saja yang berhasil dibersihkan, apa yang dilewati, dan perkiraan ruang yang berhasil dikosongkan.
- **Mode Administrator opsional**: bila dijalankan dengan **Run as Administrator**, aplikasi juga mencoba membersihkan target sistem seperti `C:\Windows\Temp` dan sisa unduhan Windows Update.

## Yang dibersihkan

Secara default, aplikasi membersihkan target aman berikut:

- folder temporary milik pengguna
- cache thumbnail Windows
- cache ikon Windows
- crash dump lokal
- folder diagnostik lokal
- Recycle Bin
- `C:\Windows\Temp` *(jika dijalankan sebagai Administrator)*
- `C:\Windows\SoftwareDistribution\Download` *(jika dijalankan sebagai Administrator)*

## Cara pakai

1. Buka folder aplikasi.
2. Klik dua kali `Run Cleaner.cmd`.
3. Klik tombol **Bersihkan Sekarang**.
4. Jika ingin pembersihan berulang, biarkan centang auto-clean tetap aktif dan biarkan aplikasinya tetap terbuka.

## Jika ingin hasil lebih maksimal

- Jalankan `Run Cleaner.cmd` dengan **Run as Administrator** agar target sistem juga bisa dibersihkan.
- Tutup aplikasi yang sedang sibuk memakai file cache tertentu agar lebih banyak file bisa dihapus.

## Catatan penting

- Beberapa file mungkin sedang dipakai Windows atau aplikasi lain. File seperti itu akan **dilewati dengan aman**, bukan dipaksa hapus.
- Aplikasi ini dirancang untuk **pembersihan aman**, bukan pembersihan agresif yang berisiko menghapus data penting.

## Struktur file

- `Run Cleaner.cmd` → launcher satu klik
- `src\WindowsCleaner.ps1` → aplikasi utama dengan tampilan GUI
- `src\CleanerCore.ps1` → logika pembersihan
- `tests\Validate-Cleaner.ps1` → validasi parser dan self-test

## Cara uji

Jalankan perintah berikut di Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-Cleaner.ps1
```

Jika berhasil, Anda akan melihat pesan bahwa parser validation dan self-test selesai dengan sukses.
