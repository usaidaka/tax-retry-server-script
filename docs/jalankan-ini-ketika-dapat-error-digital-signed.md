1. Jika terkena error berikut:
C:\Users\Phincon\Downloads\Retry\v2_tax_retry_production.ps1 is not digitally signed. You cannot run this script on the current system. 
For more information about running scripts and setting execution policy, see about_Execution_Policies at 
https:/go.microsoft.com/fwlink/?LinkID=135170.
At line:1 char:1
+ .\v2_tax_retry_production.ps1 -ManualRetrySuffix "_MR1"
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : SecurityError: (:) [], PSSecurityException
    + FullyQualifiedErrorId : UnauthorizedAccess

2. Jalankan Command Berikut:
Unblock-File -Path .\v2_tax_retry_production.ps1