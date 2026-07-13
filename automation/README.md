# Tax Retry Automation

Script automasi (*Orchestrator*) untuk melakukan *retry* (pengiriman ulang) transaksi pajak gagal yang bersumber dari file CSV.

## Prasyarat (Prerequisites)
1. Sistem Operasi berbasis UNIX (Linux/macOS) untuk menjalankan Bash.
2. Harus terinstall **PowerShell Core (`pwsh`)** di dalam server/laptop yang digunakan.

## Struktur Direktori
- `01-script/`: Berisi inti logika PowerShell (`v2_tax_retry_production.ps1`).
- `02-csv-for-execute/`: Folder **Input**. Taruh file CSV Anda di sini.
- `03-csv-after-execute/`: Folder **Arsip CSV**. File CSV yang telah diproses otomatis dipindah ke sini.
- `04-log-retry-manual/`: Folder **Arsip Log**. Log hasil *retry* (Success/Failed) akan disimpan di sini.
- `config.sh`: Berisi variabel konfigurasi *path* direktori.
- `retry.sh`: Script *Orchestrator* utama yang akan Anda jalankan.

## Cara Penggunaan (How to Run)
1. Pastikan folder `02-csv-for-execute/` dalam keadaan bersih/kosong.
2. Masukkan **tepat 1 (satu) buah file `.csv`** ke dalam folder `02-csv-for-execute/`. 
   > *(Catatan: Script akan menolak memproses jika mendeteksi lebih dari 1 file CSV sebagai bentuk pengamanan).*
3. (Opsional) Jika baru pertama kali di-*clone* di server Linux, pastikan script bisa dieksekusi:
   ```bash
   chmod +x retry.sh config.sh
   ```
4. Jalankan script orchestrator melalui terminal dengan membubuhkan *Suffix*:
   ```bash
   ./retry.sh --suffix NAMA_SUFFIX
   ```
   *Contoh: `./retry.sh --suffix MR4`*

## Aturan Format CSV
- CSV wajib memiliki *header* kolom secara persis: 
  `TRANSACTION_DATE,RECEIPT_NUMBER,SHORTCODE,AMOUNT,BRAND,REASON_TYPE,TRANSACTION_TYPE`
- Format pada baris data untuk kolom `TRANSACTION_DATE` wajib terdiri dari **tepat 14 digit angka** (`YYYYMMDDHHmmss`). Jika ada karakter aneh atau tidak genap 14 digit, maka eksekusi akan digagalkan otomatis oleh sistem.
