## Why

Saat ini proses "retry manual tax" mengharuskan operator untuk menjalankan PowerShell script secara manual, menyalin file CSV, mengatur suffix (_MR1, dll) satu per satu, dan memindahkan log secara manual. Hal ini rentan human error dan memakan waktu. Automasi berbasis Bash ini akan membantu proses orchestrasi ini menjadi lebih cepat dan efisien.

## What Changes

- Membuat sebuah Orchestrator script (`retry.sh`) berbasis Bash yang akan menstandarkan input dari operator.
- Modifikasi kecil pada script `v2_tax_retry_production.ps1` agar menerima dinamis parameter CSV path (yang sebelumnya hardcoded).
- Mengonversi format file CSV ke UNIX format (dos2unix) untuk mencegah error saat proses baca.
- Automasi alur backup file CSV (ke folder `02` dan `03`) dan Log (ke folder `04`).

## Capabilities

### New Capabilities
- `orchestrate-tax-retry`: Bash automation logic (termasuk validasi file CSV, konversi format UNIX, arg parsing, execution command pembungkus, dan folder routing CSV/Logs).
- `dynamic-csv-support`: Penyesuaian `v2_tax_retry_production.ps1` (mengubahnya dari extension .sh menjadi .ps1 dan penambahan CLI parameter `$CsvPath`).

### Modified Capabilities
- Tidak ada spesifikasi bisnis utama yang berubah. Semua business logic tetap berada pada `v2_tax_retry_production.ps1`.

## Impact

- **Affected Code:** `automation/01-script/v2_tax_retry_production.sh` akan dirubah ekstensi filenya menjadi `.ps1` dan akan dimodifikasi argumennya. File `retry.sh` dan `config.sh` baru akan diimplementasi.
- **Dependencies:** Script `retry.sh` akan membutuhkan `pwsh` atau `powershell` (jika berjalan di OS target Linux/Mac). Utilities tambahan: `dos2unix` atau `awk` untuk format UNIX CSV.
