## 1. Environment and Script Setup

- [x] 1.1 Ubah ekstensi file `automation/01-script/v2_tax_retry_production.sh` kembali menjadi `.ps1`
- [x] 1.2 Modifikasi `v2_tax_retry_production.ps1` untuk menerima parameter `-CsvPath` dan menggunakannya pada baris `$CSV_PATH`
- [x] 1.3 Update `automation/config.sh` jika diperlukan, pastikan variabel struktur folder terdefinisi

## 2. Orchestrator Script Foundation

- [x] 2.1 Buat parsing parameter CLI pada `retry.sh` (menerima `--csv` dan `--suffix`)
- [x] 2.2 Buat logic validasi file input CSV (eksistensi file, tidak kosong, dan format ekstensi) pada `retry.sh`
- [x] 2.3 Buat logic otomatisasi penambahan _ pada awalan suffix jika belum ada

## 3. CSV Preparation

- [x] 3.1 Implementasikan konversi DOS ke UNIX format menggunakan `dos2unix` atau `awk`
- [x] 3.2 Implementasikan copy CSV yang telah dikonversi dan divalidasi ke dalam folder `02-csv-for-execute`

## 4. Execution and Routing

- [x] 4.1 Tambahkan perintah eksekusi utama (via `pwsh` atau `powershell`) untuk memanggil `v2_tax_retry_production.ps1` dengan argumen yang tepat dari dalam `retry.sh`
- [x] 4.2 Buat proses pemindahan file CSV dari `02-csv-for-execute` ke `03-csv-after-execute` pasca eksekusi
- [x] 4.3 Buat proses pemindahan file log (`retry_success*.log` dan `retry_failed*.log`) dari folder 01 ke `04-log-retry-manual`
- [x] 4.4 Uji coba jalannya script secara menyeluruh dari awal hingga akhir dengan sample CSV
