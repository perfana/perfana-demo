# Running Perfana as a Windows service (NSSM) — survives user logoff

The [§11 scheduled-task boot](INSTALL.md#11-start-automatically-on-boot) starts the stack when the
**distro-owning admin logs in**, but WSL2's utility VM is bound to that account's logon session: when
the admin **logs off**, Windows ends the session and WSL tears the VM — and every container — down
with it. `vmIdleTimeout` does not cover logoff.

This guide runs the stack under a **dedicated service account that no human ever logs into
interactively**, wrapped as a Windows service with **NSSM**. Because that account is never logged
off, its WSL VM is never torn down — your admins can RDP in and out as themselves all day and Perfana
keeps running.

**Use this instead of [§11](INSTALL.md#11-start-automatically-on-boot), not alongside it** — running
both races two boots against each other. If you set up the §11 `Perfana` scheduled task, unregister
it first: `Unregister-ScheduledTask -TaskName "Perfana" -Confirm:$false`.

The plan, in three moves:

1. **A dedicated service account** (`perfana-svc`) — the only thing that owns the running WSL distro.
2. **Re-register the existing distro under it** — export it as-is and import it as `perfana-svc`. No
   reinstall: Docker, systemd config, and the `data-root` setting all come across in the export, and
   the heavy state (database, images, volumes) never moves — it lives on the dedicated VHDX share,
   which is attached at the Windows layer independent of who owns the distro.
3. **An NSSM service** that attaches the VHDX, starts the stack, and blocks — keeping the service
   account's logon session (and thus the WSL VM) alive for good.

Assumes you completed [INSTALL.md](INSTALL.md) through at least [§9](INSTALL.md#9-deploy-perfana) as
the current admin (`perfana-admin`), with the distro named `Ubuntu-24.04`. Replace `SERVERNAME`,
account names, and the VHDX/tar paths to match your host. Domain accounts are `DOMAIN\perfana-svc`
instead of `.\perfana-svc`.

---

## 1. Create the dedicated service account

**PowerShell as Administrator.** A local account is fine (use a domain account if your org requires
it). It needs local admin so the service can run `wsl --mount`.

```powershell
$pw = Read-Host -AsSecureString "Password for perfana-svc"
New-LocalUser -Name "perfana-svc" -Password $pw `
  -FullName "Perfana WSL service" `
  -Description "Owns the Perfana WSL distro; never used interactively" `
  -PasswordNeverExpires -AccountNeverExpires
Add-LocalGroupMember -Group "Administrators" -Member "perfana-svc"
```

> "Log on as a service" is granted automatically when you set the service's account in
> [step 5](#5-create-the-nssm-service). For hardening you can additionally **deny interactive logon**
> to this account in Local Security Policy (`secpol.msc` → *Deny log on locally*) once setup is done —
> but do it **after** the one-time import in [step 3](#3-re-register-the-distro-under-the-service-account),
> which needs a logon.

---

## 2. Export the existing distro

As the current owner (`perfana-admin`), stop WSL and export the distro to a tar. This is a plain
snapshot of the distro's filesystem — Docker, `/etc`, your Linux user, everything.

```powershell
wsl --shutdown
wsl --export Ubuntu-24.04 D:\perfana-distro.tar
```

> The dedicated data share (the VHDX from [§6 Option A](INSTALL.md#option-a--dedicated-ext4-vhdx-recommended))
> is **not** part of this tar — it's a separate bare-mounted disk holding your Docker volumes, images,
> and the repo. It stays put and is reused as-is.

---

## 3. Re-register the distro under the service account

`wsl --import` registers the distro to **whoever runs it**, so it must run as `perfana-svc`. The
simplest way is a one-time interactive login.

**Log in as `perfana-svc`** (RDP or the console — this is the only time you ever will), open
PowerShell, and import:

```powershell
New-Item -ItemType Directory -Force -Path C:\WSL\Ubuntu-perfana | Out-Null
wsl --import Ubuntu-perfana C:\WSL\Ubuntu-perfana D:\perfana-distro.tar --version 2
wsl -l -v          # confirm "Ubuntu-perfana" is listed and VERSION 2
```

`wsl --import` defaults the distro's login to **root**. Set the default back to your Linux user so
the `docker` group applies to interactive use (replace `perfana` with your UNIX username from
[§4](INSTALL.md#4-install-wsl2-on-windows-server-2025)):

```powershell
wsl -d Ubuntu-perfana -u root -- bash -lc 'printf "[user]\ndefault=perfana\n" >> /etc/wsl.conf'
```

Then **log `perfana-svc` off and never log it in interactively again.** (The NSSM service always runs
its WSL commands as `-u root`, so the default-user setting only matters if a human ever opens a shell.)

> **Account denied interactive logon by policy?** Do the import from a one-shot scheduled task
> running as `perfana-svc` instead:
> ```powershell
> $imp = New-ScheduledTaskAction -Execute "wsl.exe" `
>   -Argument "--import Ubuntu-perfana C:\WSL\Ubuntu-perfana D:\perfana-distro.tar --version 2"
> Register-ScheduledTask -TaskName "perfana-import" -Action $imp `
>   -User "SERVERNAME\perfana-svc" -Password "<password>" -RunLevel Highest
> Start-ScheduledTask -TaskName "perfana-import"
> Start-Sleep 30
> (Get-ScheduledTask -TaskName "perfana-import" | Get-ScheduledTaskInfo).LastTaskResult   # 0 = success
> Unregister-ScheduledTask -TaskName "perfana-import" -Confirm:$false
> ```

---

## 4. Create the boot wrapper scripts

The NSSM service runs one process that must **block** — so long as it runs, `perfana-svc`'s logon
session (and its WSL VM) stays alive. Two small files do that.

**Inside the distro**, create the runner that starts the stack then blocks. As `perfana-svc` is off,
run this from your normal admin shell against the new distro:

```powershell
wsl -d Ubuntu-perfana -u root -- bash -lc 'cat > /srv/perfana/app/nssm-run.sh' <<'EOF'
#!/usr/bin/env bash
set -e
mount -a 2>/dev/null || true                       # mount the dedicated VHDX by label (Option A)
cd /srv/perfana/app
sudo -u "$(stat -c '%U' /srv/perfana/app)" ./start.sh
exec sleep infinity                                # block so the wrapping service stays "running"
EOF
wsl -d Ubuntu-perfana -u root -- chmod +x /srv/perfana/app/nssm-run.sh
```

**On the Windows host**, create the wrapper the service actually launches. Save as
**`G:\perfana\nssm-boot.ps1`** (adjust the VHDX path; on [§6 Option B](INSTALL.md#option-b--directory-on-the-distro-disk-simpler)
the `wsl --mount` line simply no-ops — leave it):

```powershell
$ErrorActionPreference = 'SilentlyContinue'
# Attach the dedicated VHDX (Option 6A). Harmless if already attached, or on Option 6B.
wsl --mount --vhd "G:\perfana\perfana-data.vhdx" --bare
# Start the stack and BLOCK — this call does not return, which keeps the service alive.
wsl -d Ubuntu-perfana -u root -e /srv/perfana/app/nssm-run.sh
```

---

## 5. Create the NSSM service

Download NSSM from <https://nssm.cc/download> (or copy it onto the server if air-gapped) and place
`nssm.exe` at e.g. `C:\nssm\nssm.exe`. **PowerShell as Administrator:**

```powershell
$nssm = "C:\nssm\nssm.exe"
& $nssm install Perfana powershell.exe "-NoProfile -ExecutionPolicy Bypass -File G:\perfana\nssm-boot.ps1"
& $nssm set Perfana ObjectName ".\perfana-svc" "<password>"   # sets the account + grants "Log on as a service"
& $nssm set Perfana Start SERVICE_AUTO_START                  # start at boot, before any login
& $nssm set Perfana DisplayName "Perfana (WSL)"
& $nssm set Perfana Description "Boots and keeps the Perfana WSL2 stack alive; survives user logoff."
& $nssm set Perfana AppStdout C:\WSL\perfana-service.log
& $nssm set Perfana AppStderr C:\WSL\perfana-service.log
```

Because the service runs as a member of Administrators, it gets a full (elevated) token, so
`wsl --mount` in the wrapper works without an interactive UAC prompt.

Start it:

```powershell
& $nssm start Perfana
Get-Service Perfana            # STATUS should be Running
```

Watch the first boot in `C:\WSL\perfana-service.log` and the containers with
`wsl -d Ubuntu-perfana -u root -e docker compose -f /srv/perfana/app/docker-compose.yml ps`.

> First run only: if you have not yet run [`bootstrap.sh`](INSTALL.md#94-run-first-run-bootstrap-once),
> do it now — `wsl -d Ubuntu-perfana -u root -e bash -lc 'cd /srv/perfana/app && ./bootstrap.sh'`.

---

## 6. Verify it survives logoff

This is the whole point — test it:

```powershell
# 1. Confirm the stack answers.
Invoke-WebRequest http://localhost:3001/api/health -UseBasicParsing   # 200 OK
```

2. **Sign out** of your Windows session completely (not just close the terminal).
3. Sign back in (or check from another host on the LAN).

```powershell
# 4. Still healthy — the VM was never torn down.
Invoke-WebRequest http://localhost:3001/api/health -UseBasicParsing   # 200 OK
Get-Service Perfana                                                   # still Running
```

Then do the real test — a **full host reboot** — and confirm the service starts the stack with no
login at all.

---

## 7. Operating notes

- **Stopping the service does not stop the containers.** `nssm stop Perfana` only kills the keepalive
  wrapper; Docker keeps the containers running (restart policy). To actually stop the stack:
  `wsl -d Ubuntu-perfana -u root -e bash -lc 'cd /srv/perfana/app && ./stop.sh'`. To stop everything,
  stop the stack first, then `wsl --shutdown`.
- **Upgrades** ([§13](INSTALL.md#13-upgrades)) are unchanged — run `./update.sh` inside the distro;
  no need to touch the service.
- **Password changes** on `perfana-svc`: re-run `nssm set Perfana ObjectName ".\perfana-svc" "<new>"`.
  Use a non-expiring password (set above) so the service doesn't silently fail to start later.
- **Belt-and-suspenders:** you can also add `vmIdleTimeout=-1` under `[wsl2]` in
  [`.wslconfig`](INSTALL.md#5-allocate-resources-to-wsl2-wslconfig). Not required — the blocking
  service already keeps the VM up — but it prevents idle teardown if the service is ever stopped.
- **Retire the old distro** once you're satisfied the service works. As `perfana-admin`:
  `wsl --unregister Ubuntu-24.04`. Safe — its data was exported and the live data is on the VHDX
  share, not in that distro. Delete `D:\perfana-distro.tar` too.
```
