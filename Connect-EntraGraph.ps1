<#
.SYNOPSIS
    Connects to Microsoft Graph for the Joiner-Mover-Leaver (JML) automation pipeline.

.NOTES
    Uses delegated (interactive) auth, which is the simplest path for a lab/portfolio
    project. In a real production IAM pipeline this would instead use app-only auth
    (client credentials with a certificate) so it can run unattended on a schedule --
    mention that distinction in interviews, it shows you understand the difference
    between delegated and application permissions.
#>

param(
    [string]$ClientId = "a0835b34-9f7d-4c88-b8c7-8503085930f9",
    [string]$TenantId = "4890db21-cdde-44ed-be90-ae262b541636"
)

$RequiredScopes = @(
    "User.ReadWrite.All",
    "Group.ReadWrite.All",
    "Directory.ReadWrite.All"
)

Write-Host "Connecting to Microsoft Graph using app registration $ClientId..." -ForegroundColor Cyan
Connect-MgGraph -ClientId $ClientId -TenantId $TenantId -Scopes $RequiredScopes -NoWelcome

$context = Get-MgContext
if ($null -eq $context) {
    Write-Error "Failed to connect to Microsoft Graph."
    exit 1
}

Write-Host "Connected as $($context.Account) to tenant $($context.TenantId)" -ForegroundColor Green
Write-Host "Granted scopes: $($context.Scopes -join ', ')" -ForegroundColor Green
