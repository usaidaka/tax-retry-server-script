====================================================================
SOP - v2_tax_retry_production.ps1
====================================================================

TUJUAN:
Melakukan manual retry terhadap transaksi yang gagal, baik
pada percobaan original MAUPUN pada automatic retry (_R02), atau
gagal lagi setelah manual retry round sebelumnya (_MR1, _MR2, ...).
Setiap percobaan ditandai dengan suffix baru agar API menganggapnya
sebagai transaksi baru.

*** SCRIPT INI MENGARAH KE PRODUCTION (10.49.120.220 / MDW08) ***

====================================================================
LANGKAH-LANGKAH
====================================================================

1. Ambil RECEIPT_NUMBER yang benar menggunakan SQL query yang sudah
   disepakati (original + retry sama-sama FAILED, error code sesuai,
   dan belum ada _MR% yang SUCCESS).

2. Export ke CSV. Pastikan:
   - RECEIPT_NUMBER adalah angka polos (bare number), tanpa suffix
     apa pun.
   - Kolom dan urutannya sesuai persis:
     TRANSACTION_DATE, RECEIPT_NUMBER, SHORTCODE, AMOUNT, BRAND,
     REASON_TYPE, TRANSACTION_TYPE
   - AMOUNT adalah nilai RAW/original (script akan mengalikan
     dengan 100 secara otomatis - JANGAN dikalikan lebih dulu di
     dalam CSV).

3. Update $CSV_PATH di dalam script agar sesuai dengan nama file
   CSV yang baru saja di-export.

4. Jalankan di PowerShell:

       .\v2_tax_retry_production.ps1 -ManualRetrySuffix "_MR1"

   Gunakan nomor round BERIKUTNYA setiap kali dijalankan:
       Manual retry ke-1  -> "_MR1"
       Manual retry ke-2  -> "_MR2"
       Manual retry ke-3  -> "_MR3"

5. Periksa kedua file log setelah selesai:
       retry_success_<timestamp>.log
       retry_failed_<timestamp>.log
   Buka retry_success dan baca field Response - HTTP 200 saja BUKAN
   jaminan sukses di API ini. Pastikan isi response benar-benar
   menunjukkan hasil sukses.

6. Jika masih gagal, ulangi dari Langkah 1 menggunakan query yang
   sesuai untuk suffix yang baru saja gagal (_MR1, _MR2, ...).

====================================================================
!! PERINGATAN - PERIKSA INI SEBELUM MENJALANKAN !!
====================================================================

[ ] INI ADALAH PRODUCTION. Pastikan ini benar-benar transaksi dan
    receipt number yang ingin disubmit - tidak ada undo setelah
    diterima oleh API.

[ ] PASTIKAN RECEIPT_NUMBER MASIH POLOS (BARE). Jika CSV yang
    di-export sudah mengandung suffix di RECEIPT_NUMBER (misalnya
    ..._R02 atau ..._MR1), script akan menambahkan suffix lagi di
    atasnya dan menghasilkan receipt number yang salah/bertumpuk
    (contoh: ..._R02_MR2). Periksa ulang SQL query jika ini terjadi
    - query seharusnya mengambil RECEIPT_NUMBER original yang polos,
    bukan RECEIPT_NUMBER dari attempt retry-nya.

[ ] PASTIKAN NAMA FILE CSV SUDAH BENAR. $CSV_PATH harus di-update
    agar sesuai dengan file yang benar-benar di-export untuk run
    ini - komentar di dalam script hanya pengingat, bukan
    pengecekan otomatis.

[ ] FIELD YANG BOLEH KOSONG. BRAND dan TRANSACTION_TYPE boleh
    kosong. Semua kolom lain (TRANSACTION_DATE, RECEIPT_NUMBER,
    SHORTCODE, AMOUNT, REASON_TYPE) wajib memiliki nilai, jika
    tidak baris tersebut akan otomatis di-skip (cek retry_failed
    log untuk entry SKIPPED).

====================================================================
REFERENSI CEPAT
====================================================================
Endpoint      : http://10.49.120.220:7001/TaxFacade/ws/tax  (PRODUCTION)
Script        : v2_tax_retry_production.ps1
Parameter     : -ManualRetrySuffix "_MR1" / "_MR2" / "_MR3" ...
Success log   : retry_success_<timestamp>.log
Failed log    : retry_failed_<timestamp>.log
====================================================================