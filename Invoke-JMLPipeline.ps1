<#
.SYNOPSIS
    Joiner-Mover-Leaver (JML) automation pipeline for Microsoft Entra ID.

.DESCRIPTION
    Reads a CSV that simulates an HR feed and provisions, updates, or deprovisions
    users in Entra ID based on the "Action" column:
        Join  - creates the user and adds them to the specified groups
        Move  - updates job title/department and reconciles group membership
        Leave - disables the account, strips group membership, and revokes
                active sign-in sessions

    Every action is logged to JML-Log.csv with a timestamp so the run is auditable --
    this is the "access review" evidence a real IAM team would need.

.PARAMETER CsvPath
    Path to the HR feed CSV. Defaults to sample-employees.csv in the same folder.

.NOTES
    Run Connect-EntraGraph.ps1 first in the same PowerShell session.
#>

param(
    [string]$CsvPath = "$PSScriptRoot\sample-employees.csv",
    [string]$LogPath = "$PSScriptRoot\JML-Log.csv"
)

if (-not (Get-MgContext)) {
    Write-Error "Not connected to Microsoft Graph. Run Connect-EntraGraph.ps1 first."
    exit 1
}

# Default password policy for new joiners - force change at first sign-in
function New-TempPassword {
    $chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%'
    -join ((1..14) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

function Write-JMLLog {
    param($UserPrincipalName, $Action, $Result, $Details)
    $entry = [PSCustomObject]@{
        Timestamp = (Get-Date).ToString("s")
        User      = $UserPrincipalName
        Action    = $Action
        Result    = $Result
        Details   = $Details
    }
    $entry | Export-Csv -Path $LogPath -Append -NoTypeInformation
    Write-Host "[$Action] $UserPrincipalName -> $Result ($Details)"
}

function Get-OrCreateGroup {
    param([string]$GroupName)
    $group = Get-MgGroup -Filter "displayName eq '$GroupName'" -ErrorAction SilentlyContinue
    if (-not $group) {
        $group = New-MgGroup -DisplayName $GroupName -MailEnabled:$false `
            -MailNickname ($GroupName -replace '\s', '') -SecurityEnabled:$true
        Write-Host "Created missing group: $GroupName" -ForegroundColor Yellow
    }
    return $group
}

function Invoke-Join {
    param($Row)
    try {
        $password = New-TempPassword
        $userParams = @{
            AccountEnabled    = $true
            DisplayName       = "$($Row.FirstName) $($Row.LastName)"
            GivenName         = $Row.FirstName
            Surname           = $Row.LastName
            UserPrincipalName = $Row.UserPrincipalName
            MailNickname      = $Row.UserPrincipalName.Split('@')[0]
            JobTitle          = $Row.JobTitle
            Department        = $Row.Department
            PasswordProfile   = @{
                Password                      = $password
                ForceChangePasswordNextSignIn = $true
            }
        }
        $newUser = New-MgUser -BodyParameter $userParams

        foreach ($groupName in ($Row.Groups -split ';' | Where-Object { $_ })) {
            $group = Get-OrCreateGroup -GroupName $groupName.Trim()
            New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $newUser.Id
        }

        Write-JMLLog -UserPrincipalName $Row.UserPrincipalName -Action "Join" `
            -Result "Success" -Details "Groups: $($Row.Groups); Temp password issued"
    }
    catch {
        Write-JMLLog -UserPrincipalName $Row.UserPrincipalName -Action "Join" `
            -Result "Failed" -Details $_.Exception.Message
    }
}

function Invoke-Move {
    param($Row)
    try {
        $user = Get-MgUser -Filter "userPrincipalName eq '$($Row.UserPrincipalName)'"
        if (-not $user) { throw "User not found" }

        Update-MgUser -UserId $user.Id -JobTitle $Row.JobTitle -Department $Row.Department

        # Reconcile group membership: add to any listed groups the user isn't already in
        $currentGroups = Get-MgUserMemberOf -UserId $user.Id | ForEach-Object { $_.AdditionalProperties.displayName }
        $targetGroups = $Row.Groups -split ';' | Where-Object { $_ } | ForEach-Object { $_.Trim() }

        foreach ($groupName in $targetGroups) {
            if ($groupName -notin $currentGroups) {
                $group = Get-OrCreateGroup -GroupName $groupName
                New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id
            }
        }

        Write-JMLLog -UserPrincipalName $Row.UserPrincipalName -Action "Move" `
            -Result "Success" -Details "New title: $($Row.JobTitle); Dept: $($Row.Department)"
    }
    catch {
        Write-JMLLog -UserPrincipalName $Row.UserPrincipalName -Action "Move" `
            -Result "Failed" -Details $_.Exception.Message
    }
}

function Invoke-Leave {
    param($Row)
    try {
        $user = Get-MgUser -Filter "userPrincipalName eq '$($Row.UserPrincipalName)'"
        if (-not $user) { throw "User not found" }

        # 1. Disable the account
        Update-MgUser -UserId $user.Id -AccountEnabled:$false

        # 2. Strip all group memberships (least privilege on exit)
        $memberships = Get-MgUserMemberOf -UserId $user.Id
        foreach ($m in $memberships) {
            try { Remove-MgGroupMemberByRef -GroupId $m.Id -DirectoryObjectId $user.Id } catch {}
        }

        # 3. Revoke active sessions / refresh tokens so existing logins are killed immediately
        Revoke-MgUserSignInSession -UserId $user.Id | Out-Null

        Write-JMLLog -UserPrincipalName $Row.UserPrincipalName -Action "Leave" `
            -Result "Success" -Details "Account disabled, groups stripped, sessions revoked"
    }
    catch {
        Write-JMLLog -UserPrincipalName $Row.UserPrincipalName -Action "Leave" `
            -Result "Failed" -Details $_.Exception.Message
    }
}

# --- Main pipeline ---
if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV not found at $CsvPath"
    exit 1
}

$rows = Import-Csv -Path $CsvPath
Write-Host "`nProcessing $($rows.Count) JML events from $CsvPath`n" -ForegroundColor Cyan

foreach ($row in $rows) {
    switch ($row.Action) {
        "Join"  { Invoke-Join  -Row $row }
        "Move"  { Invoke-Move  -Row $row }
        "Leave" { Invoke-Leave -Row $row }
        default { Write-Warning "Unknown action '$($row.Action)' for $($row.UserPrincipalName)" }
    }
}

Write-Host "`nDone. Full audit log written to $LogPath" -ForegroundColor Green
