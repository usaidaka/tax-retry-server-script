## Context

Saat ini, proses *retry manual tax* dilakukan oleh operator secara manual dengan menjalankan script PowerShell (`v2_tax_retry_production.ps1`), mengekspor data ke file CSV tertentu, dan merename suffix (`_MR1`, `_MR2`, dsb). Proses ini memakan waktu dan berisiko terjadinya *human error*, terutama jika jumlah file yang harus diproses cukup banyak atau operator lupa menyesuaikan parameter CSV secara benar.

## Goals / Non-Goals

**Goals:**
- Membuat Orchestrator Script dalam bahasa Bash (`retry.sh`) yang menyediakan *one-command automation* untuk operator.
- Mengonversi CSV ke format UNIX (dos2unix) secara otomatis untuk menghindari isu EOF / line ending.
- Secara otomatis mengatur folder routing (memindahkan CSV ke `02-csv-for-execute` dan log ke `04-log-retry-manual`).
- Menambahkan parameter dinamis ke script bisnis utama agar dapat menerima *custom path* file CSV dari Orchestrator.

**Non-Goals:**
- **TIDAK** mengubah, merombak, atau memindahkan *business logic* pemanggilan SOAP API yang saat ini sudah berjalan stabil di `v2_tax_retry_production.ps1`.
- **TIDAK** mengimplementasikan fitur SSH, SCP, FTP, maupun integrasi Docker / Java (ini adalah Future Milestone seperti yang tertera di `PRD.md`).

## Decisions

1. **PowerShell Script Extention & Parameterization**
   - *Decision:* Mengubah nama file dari `v2_tax_retry_production.sh` kembali menjadi `v2_tax_retry_production.ps1` dan menambahkan parameter `-CsvPath`.
   - *Rationale:* Mengingat script asli sepenuhnya bergantung pada `Import-Csv` dan `Invoke-WebRequest` dari ekosistem PowerShell, maka menjalankannya via `pwsh` atau `powershell` adalah langkah yang tepat. Hal ini menghindari *rewrite* ulang kode yang bisa memunculkan bug baru (menyalahi PRD). Parameter `-CsvPath` dibutuhkan agar Orchestrator dapat mengirim file spesifik ke script.

2. **Suffix Automation**
   - *Decision:* Jika user menginput `--suffix MR1` di script bash, script akan otomatis me-prepend `_` sehingga argumen yang terkirim ke PowerShell adalah `_MR1` sesuai SOP (kecuali user memang sudah memberikan `_`).
   - *Rationale:* Meminimalkan kesalahan ketik dari operator.

3. **Format Konversi (dos2unix)**
   - *Decision:* Menggunakan CLI tool seperti `dos2unix` atau `awk`/`tr` fallback untuk merubah CRLF ke LF.
   - *Rationale:* Script Shell akan gagal membaca konfigurasi atau input jika terdapat line terminator ala DOS (CRLF).

## Risks / Trade-offs

- **[Risk]** Target OS (Linux/Mac) tidak memiliki PowerShell Core (`pwsh`).
  - *Mitigation:* Memastikan instruksi `retry.sh` memberikan *error check* awal yang jelas bila `pwsh` atau `powershell` tidak ditemukan di dalam sistem PATH, dan memberitahu operator untuk menginstalnya.
- **[Risk]** Validasi CSV yang ketat (Missing columns).
  - *Mitigation:* `retry.sh` hanya mengecek keberadaan file dan ekstensi. Validasi mendalam (kolom wajib) tetap akan di-handle oleh *business logic* PowerShell (yang saat ini sudah berjalan baik dengan pemeriksaan `$requiredColumns`).
