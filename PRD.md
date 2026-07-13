# PRD
## Retry Manual Tax Automation

Version: 0.1

---

# Overview

Project ini bertujuan membuat automation shell script untuk proses Manual Retry Tax.

Saat ini perusahaan sudah memiliki business script utama yang bekerja dengan baik.

Nama script:

v2_tax_retry_production.sh

Script tersebut sudah digunakan di production dan TIDAK menjadi fokus project ini.

Project ini hanya bertugas membangun automation wrapper agar proses manual menjadi otomatis.

Automation akan dikembangkan bertahap.

Saat ini target hanya berjalan di LOCAL environment.

Deployment ke server akan menjadi milestone berikutnya.

---

# Current Environment

Development Machine

- macOS
- Apple Silicon M2
- VSCode
- Terminal (bash / zsh)

Target Runtime

Linux Shell (.sh)

---

# Existing Files

AI wajib membaca seluruh folder project terlebih dahulu sebelum membuat code.

Folder documentation berisi:

- step.md
- sop-in-indonesian.md
- retry_success_*.log
- jalankan-ini-ketika-dapat-error-digital-signed.md

Script existing:

- v2_tax_retry_production.sh

Sample CSV

- T_TAX_REQUEST_xxxxx.csv

Jangan mengubah isi file existing tanpa alasan yang jelas.

---

# Business Rule

Business logic sudah berada di:

v2_tax_retry_production.sh

Script tersebut menangani:

- membaca CSV
- validasi data
- SOAP API
- success log
- failed log

Automation TIDAK boleh memindahkan business logic ke file lain.

Automation hanya bertindak sebagai ORCHESTRATOR.

---

# Objective

Membuat automation agar operator cukup menjalankan satu command.

Contoh:

./retry.sh \
    --csv sample.csv \
    --suffix MR1

Automation akan mengerjakan workflow secara otomatis.

---

# Workflow

Current Phase

1. Validate parameter
2. Validate CSV
3. Convert CSV menjadi UNIX format
4. Copy CSV ke execution folder
5. Execute existing script
6. Organize output
7. Logging

Future Phase

1. Upload CSV ke server
2. Execute via SSH
3. Download log
4. Archive

Future phase tidak perlu dibuat sekarang.

---

# Project Structure

automation/

    retry.sh

    config.sh

    lib/

    01-script/

    02-csv-for-execute/

    03-csv-after-execute/

    04-log-retry-manual/

---

# Coding Rules

Gunakan Bash.

Gunakan POSIX jika memungkinkan.

Pisahkan logic menjadi file kecil.

Jangan membuat retry.sh berisi ratusan line.

Gunakan function.

Gunakan exit code yang benar.

Gunakan logging.

Gunakan komentar seperlunya.

---

# Configuration

Semua konfigurasi berada pada:

config.sh

Contoh:

CSV_FOLDER

SCRIPT_FOLDER

LOG_FOLDER

ARCHIVE_FOLDER

SERVER_HOST

SERVER_USER

REMOTE_PATH

Walaupun server belum digunakan, struktur konfigurasi harus dipersiapkan.

---

# Milestone

## Milestone 1

Target:

Project structure selesai.

Output:

retry.sh

config.sh

folder structure

Belum ada implementasi.

---

## Milestone 2

Target:

retry.sh dapat dijalankan.

Contoh:

./retry.sh --help

./retry.sh --csv sample.csv --suffix MR1

Output:

Parameter berhasil dibaca.

Belum execute script.

---

## Milestone 3

Target:

CSV Validation

Validasi:

- file ada
- extension csv
- tidak kosong

---

## Milestone 4

Target:

Convert UNIX Format

Jika file DOS

↓

convert

Jika sudah UNIX

↓

skip

---

## Milestone 5

Target:

Copy CSV

copy ke

02-csv-for-execute

---

## Milestone 6

Target:

Execute

Menjalankan

v2_tax_retry_production.sh

secara LOCAL.

Belum SSH.

---

## Milestone 7

Target

Organize

CSV

↓

03-csv-after-execute

Log

↓

04-log-retry-manual

---

# Constraints

Jangan implementasikan:

- SSH
- SCP
- Upload
- Download
- Java
- Docker

Semua itu adalah Future Milestone.

---

# AI Behaviour

Sebelum menulis code:

1.

Baca seluruh project.

2.

Pelajari seluruh dokumentasi.

3.

Jelaskan pemahaman requirement.

4.

Jelaskan design.

5.

Buat checklist milestone.

6.

Minta approval.

Baru mulai coding.

---

# Coding Philosophy

AI harus bekerja seperti Senior Software Engineer.

Jangan langsung membuat seluruh project.

Setiap milestone:

- Implement
- Jelaskan
- Tunggu approval

Baru lanjut milestone berikutnya.

---

# Success Criteria

Operator cukup menjalankan:

./retry.sh

atau

./retry.sh --csv xxx.csv --suffix MR1

Automation berjalan tanpa operator melakukan proses manual satu per satu.

---

END PRD