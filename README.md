# Windows Cleaner Aman

Windows Cleaner Aman adalah aplikasi pembersih sampah Windows yang dibuat agar mudah dipakai oleh orang awam. Aplikasi ini berjalan dengan satu klik, memaksa mode Administrator saat dibuka normal, membersihkan file-file sementara yang aman untuk dibuang, lalu tetap berjalan di tray sambil mengulang pembersihan otomatis setiap 30 menit.

## Cocok untuk

- Windows 10 32-bit
- Windows 10 64-bit
- Windows 11 64-bit

## Fitur utama

- **One click cleaning tanpa terminal terbuka**: cukup jalankan `Run Cleaner.vbs` atau `Run Cleaner.cmd`. Terminal CMD tidak akan tetap tampil saat aplikasi berjalan.
- **Paksa Administrator saat dibuka normal**: aplikasi meminta hak Administrator agar target sistem Windows juga bisa dibersihkan.
- **Loop otomatis 30 menit**: selama aplikasi masih berjalan, pembersihan otomatis tetap aktif setiap 30 menit.
- **Minimize dan close ke tray**: saat di-minimize atau jendelanya ditutup, aplikasi tidak mati. Aplikasi berpindah ke tray dan tetap berjalan.
- **Aman untuk file pribadi**: aplikasi **tidak** menghapus `Documents`, `Downloads`, `Desktop`, atau file pribadi lain.
- **Laporan hasil pembersihan**: aplikasi menampilkan apa saja yang berhasil dibersihkan, apa yang dilewati, dan perkiraan ruang yang berhasil dikosongkan.

## Yang dibersihkan

Secara default, aplikasi membersihkan target aman berikut:

- folder temporary milik pengguna
- cache thumbnail Windows
- cache ikon Windows
- crash dump lokal
- folder diagnostik lokal
- Recycle Bin
- `C:\Windows\Temp`
- `C:\Windows\Prefetch` *(hanya file `*.pf`, bukan semua isi folder secara membabi buta)*
- `C:\Windows\SoftwareDistribution\Download`
- `C:\Windows\SoftwareDistribution\DeliveryOptimization\Cache`
- `C:\Windows\Minidump`
- `C:\ProgramData\Microsoft\Windows\WER\ReportQueue`

## Cara pakai

1. Buka folder aplikasi.
2. Klik dua kali `Run Cleaner.vbs`.
3. Izinkan permintaan Administrator jika Windows memintanya.
4. Klik tombol **Bersihkan Sekarang**.
5. Jika ingin aplikasi terus berjaga, cukup minimize atau tutup jendelanya. Aplikasi akan pindah ke tray dan tetap berjalan.

## Cara membuka lagi dari tray

- Cari ikon **Windows Cleaner Aman** di area tray Windows.
- Klik dua kali ikon tray untuk membuka jendela lagi.
- Anda juga bisa klik kanan tray icon untuk membuka aplikasi, menjalankan pembersihan, atau keluar sepenuhnya.

## Catatan penting

- Beberapa file mungkin sedang dipakai Windows atau aplikasi lain. File seperti itu akan **dilewati dengan aman**, bukan dipaksa hapus.
- Folder sistem dibersihkan memakai **allowlist target aman**, bukan penghapusan liar ke seluruh `C:\Windows`.
- Aplikasi ini dirancang untuk **pembersihan aman**, bukan pembersihan agresif yang berisiko menghapus data penting.

## Struktur file

- `Run Cleaner.vbs` → launcher utama tersembunyi
- `Run Cleaner.cmd` → wrapper launcher kompatibilitas
- `src\WindowsCleaner.ps1` → aplikasi utama dengan GUI, tray, dan auto-elevation
- `src\CleanerCore.ps1` → logika pembersihan dan allowlist target
- `tests\Validate-Cleaner.ps1` → validasi parser, launcher, tray behavior, dan self-test

## Cara uji

Jalankan perintah berikut di Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-Cleaner.ps1
```

Jika berhasil, Anda akan melihat bahwa parser validation, hidden launcher test, tray smoke test, dan self-test selesai dengan sukses.
