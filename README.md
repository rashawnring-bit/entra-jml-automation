# Entra ID Joiner-Mover-Leaver (JML) Automation

A PowerShell + Microsoft Graph API pipeline that automates the core Identity &
Access Management lifecycle process: provisioning access when someone joins,
adjusting it when they change roles, and revoking it the moment they leave.

## Why this project

JML is the workflow real IAM teams are hired to own and audit. This project
demonstrates the full lifecycle end-to-end against a live Entra ID tenant,
including the security controls that matter most in an audit: least-privilege
group cleanup on exit and immediate session revocation.

## What it does

| Event | Action taken |
|---|---|
| **Join** | Creates the user in Entra ID, sets a temporary password with forced change at next sign-in, adds them to the correct groups based on department |
| **Move** | Updates job title/department, reconciles group membership to match the new role |
| **Leave** | Disables the account, removes all group memberships, revokes active sign-in sessions (kills existing tokens immediately) |

Every action is written to an audit log (`JML-Log.csv`) with a timestamp,
result, and detail — the kind of evidence an access review would ask for.

## Setup

1. Register an app in Entra ID (**App registrations → New registration**)
2. Grant these Graph API permissions and admin-consent them:
   - `User.ReadWrite.All`
   - `Group.ReadWrite.All`
   - `Directory.ReadWrite.All`
3. Install the SDK: `Install-Module Microsoft.Graph -Scope CurrentUser`
4. Run `Connect-EntraGraph.ps1` to authenticate
5. Edit `sample-employees.csv` (or point `-CsvPath` at your own file) and run:
   ```powershell
   .\Invoke-JMLPipeline.ps1
   ```

## Roadmap / next additions

- [ ] Conditional Access policy requiring MFA for privileged groups
- [ ] Privileged Identity Management (PIM) for just-in-time admin elevation
      instead of standing access
- [ ] Scheduled access-review script flagging accounts with no sign-in
      activity in 90+ days
- [ ] Move from delegated auth to app-only (certificate) auth so this can
      run unattended on a schedule, like a real HR-feed integration would

## Notes on scope

This uses delegated (interactive) authentication for simplicity in a lab
environment. A production version would use application permissions with a
certificate so the pipeline can run unattended — noted here deliberately to
show the distinction is understood.
