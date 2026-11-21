# Ops Beacon 2.0 — live portable test build

Run `Start-OpsBeacon.cmd` and open **http://127.0.0.1:8080/**. Allow about 30–60 seconds for the web server to start. The original preview on port 8095 is separate.

Alternatively, from this folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-OpsBeacon.ps1
# If the default port is busy:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-OpsBeacon.ps1 -Port 8097
```

The launcher binds to loopback and never stops another process. Keep its console open; use Ctrl+C to stop it. Closing only the browser does not stop a background collection. Stopping the launcher can stop its PowerShell jobs. Collecting does not modify the inspected machine's configuration; it writes local assessment/job files and sends the selected network probes.

## Stopping Ops Beacon

Double-click `Stop-OpsBeacon.cmd`, or run this from the deployment folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Stop-OpsBeacon.ps1
# Preview what would stop without stopping it:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Stop-OpsBeacon.ps1 -WhatIf
# For a server started on another port:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Stop-OpsBeacon.ps1 -Port 8097
```

The default port comes from `config.json` (8080). The script verifies that the listener belongs to this deployment's dedicated PowerShell launcher, stops it and its PowerShell assessment workers, then confirms the port is released. Saved reports are preserved. An interrupted running assessment is marked Failed when its worker can be identified. Already-stopped sessions are harmless; an unrelated application using the port is refused.

Use the same Windows account and elevation as the launcher; if Ops Beacon was started as administrator, run the stop script as administrator too. Start with `Start-OpsBeacon.cmd` or the documented `powershell.exe -File` command. If the launcher was invoked inside an existing shared PowerShell console with `& .\Start-OpsBeacon.ps1`, use Ctrl+C in that console instead. Closing the browser alone does not release the port.

## Portable use

Copy this folder, or extract `OpsBeacon-Live-Portable.zip`, to a writable folder on a supported Windows computer. Start with **Windows PowerShell 5.1** (`powershell.exe`), .NET Framework 4.7.2 or newer and Windows CIM/event-log support. PowerShell 7 and Linux collectors are not supported by this build. Pode 2.13.4 and its license/dependency notices are bundled under `vendor/`; no package installation or internet download is needed. WinRM and optional server roles must already be configured on inspected servers.

The archive excludes this laptop's reports, event data, jobs and runtime logs. Generate a fresh archive with `Build-Portable.ps1`. The working folder retains assessment data under `reports/` and `jobs/`; treat exported reports and copied working folders as operational data.


## Assessments

Select a server profile to choose recommended checks, then adjust the optional capabilities for the inspected server:

| Capability | Actual collection and limits |
| --- | --- |
| Pending reboot (all profiles) | Read-only checks on the inspected target for Component Based Servicing `RebootPending`, Windows Update `RebootRequired`, and nonempty `PendingFileRenameOperations` / `PendingFileRenameOperations2`. A detected indicator is Warning; all checked indicators must be readable and absent for Healthy. Access failures are Unknown / Not Assessed with explicit collection gaps. File rename entries may be stale; other products can use additional reboot signals. No restart is performed. |
| General Purpose | CPU counter deltas, physical-memory samples and capacity for all mounted volumes (drive letters and folder mount points). Each volume shows total, used and free space, free percentage and its own threshold assessment. Transfer-weighted storage latency still covers the system drive; idle storage has no measured latency. |
| Connectivity | DNS, four ICMP probes, TCP and HTTP/HTTPS HEAD requests from the inspected computer. One bounded ICMP TTL trace is triggered by unanswered probes or average latency above the configured threshold. Certificate validation stays enabled; HTTP error responses are distinct from transport failures. |
| Windows events | System and Application Critical/Error summary over the last 24 hours, scanning at most 20,000 errors per log. Occurrence searches and timelines return up to 5,000 events across selected logs; FailoverClustering Operational is optional. Missing logs and truncated results are explicit. Manual searches query the source again, with optional event ID and a period up to 7 days. |
| Event investigations | Choose an individual occurrence to collect a fresh timeline two hours before/after it, including other IDs and severities. Identity includes server, log, provider and record ID. Follow-up in the future is incomplete. Scope is the inspected computer. |
| SQL Server | Local engine discovery or a selected named instance on the inspected computer. Read-only SQL DMVs for total/target memory, pending grants and uptime, using integrated authentication and validated encrypted SQL connections. Requires a valid SQL certificate and DMV permissions (`VIEW SERVER STATE`, or appropriate SQL 2022 performance-state permission). No SQL logins/passwords are accepted or persisted. Multiple instances must be assessed separately. |
| Windows Failover Cluster | Read-only topology, quorum, witness, groups, resources and per-member General Purpose samples (up to 16 members). File-share witness paths are shown only for file-share witnesses. Requires FailoverClusters tools and rights. SQL workloads and events on other members require separate assessments. No validation, failover, restart, storage tests or configuration changes. |

Unavailable roles, denied access, idle counters and missing samples stay **Not Assessed**. They never become fabricated zeroes or healthy results. CPU/memory health uses sample averages and provisional thresholds. A short snapshot cannot establish sustained health. For sustained SQL pressure, select the 5-minute-10-second or 15-minute observation; complete paired SQL/OS samples and separate warning/critical durations are required. High SQL memory use alone is not pressure. No synthetic fixtures are shipped in the live application.
![alt text](<Assemt Summary at a glance 1-1.png>)![alt text](<Assemt Summary at a glance 3-1.png>)
## Remote Windows servers

Select **Remote Windows server (WinRM)** and enter the server name. Collection runs in a PowerShell session on that server with the Windows identity displayed by the portal. A failed remote connection fails the collection; there is no fallback to the portal machine. The app does not configure WinRM, TrustedHosts, credential delegation, firewall rules or permissions. Domain/Kerberos connectivity is recommended; remoting by IP or across domains may fail under existing security policy. Additional hops from a remote cluster node may be denied by Windows delegation policy and remain coverage gaps.

Connectivity destinations must be entered as `host, port, protocol`, for example `intranet.example.com, 443, https`. The initial loopback destination checks the portal when collecting locally. Replace it for remote assessments: loopback on a remote server means that server, not this portal. Maximum 20 destinations; up to six parallel probes share one inspection deadline; connectivity inspection has a 60-second budget, traces at most 11 hops/15 seconds, individual probes 1 second. An in-flight operation may finish slightly after its budget. ICMP filtering alone does not establish an outage.

Job handling matches the original Ops Beacon: **8 web worker threads**, a **600-second HTTP request timeout**, and one native PowerShell **Start-Job** per accepted collection. Submissions return HTTP 202 and `Queued`, then the worker records `Running` and `Completed` or `Failed`. Requests, timestamps and results remain under `jobs/` for status polling; a launch failure records `Failed` and returns HTTP 503. Jobs start immediately; there is no waiting FIFO, automatic retry or restart replay, and the previous two-job rejection limit has been removed. Eight web threads do not impose an eight-collection limit. Connectivity matches the original's **six parallel probe runspaces**; other collector sequencing remains unchanged.

Optional launcher settings use the same names/defaults as the original: `-WorkerThreads 8 -RequestTimeoutSeconds 600`. The bundled Pode 2.13 configuration uses `Server.Request.Timeout` in `server.psd1`; a nondefault timeout creates a runtime-only configuration under `jobs/`. `/api/config` includes the effective runtime settings. The browser continues polling for up to 35 minutes so PROD's 5/15-minute observation profiles remain usable; this client wait limit does not terminate a worker or change its saved job state. Browser timers can be throttled in hidden tabs; a completed job remains available until the page polls again.

## Reports and testing

New live assessments include **Pending reboot** in Server measurements and a detailed indicator table in the readable report, downloaded HTML and print/PDF output. The technical JSON preserves the check time in UTC, reasons, registry locations and any access errors under `Measurements.pendingReboot`. Display times follow the inspected target's time zone. Older saved assessments have no reboot evidence; run a new assessment to collect it. This check is always included with general collection, independently of the SQL, cluster, Windows events and connectivity selections.

`tests/Reboot-Checks.ps1` verifies pending, clear and unreadable outcomes without changing registry values, and captures a real registry snapshot. `tests/Reboot-Report-Checks.mjs` then verifies that snapshot, profile coverage, friendly HTML, print export, JSON preservation and older-report handling using a Node-compatible runtime.

New assessments include a **Mounted drive capacities** table in the readable report, standalone HTML and print/PDF output. Multiple mount paths for one volume share one row. Capacity uses GiB (1,073,741,824 bytes); raw byte counts remain in JSON. Unmounted recovery/system partitions are excluded. Mapped network drives are included only when visible to the inspected Windows execution identity/session; another user's interactive mappings may not be visible through WinRM. Missing capacity and discovery failures remain explicit coverage gaps. Older saved reports retain their original system-drive-only evidence; run a new assessment to collect all mounted volumes. The same collector runs on local targets, remote targets and assessed cluster members.

End users see a readable report with measured values, findings, next steps, event context and collection limits. Download a standalone HTML copy or use Print / Save as PDF. Technical JSON is optional. Reports are saved locally and saved-report links work while this portal is running. Search results and multiple investigations are preserved in JSON; investigations also appear in the readable report.

Report dates use the inspected target's Windows time zone, with a UTC offset beside each time to distinguish repeated daylight-saving hours. Assessment headings, error summaries, occurrence lists, investigation windows and timelines use the same presentation in the browser, downloaded HTML and printed/PDF reports. The viewing computer's time zone does not change the report. UTC remains canonical in JSON, searches, chronological ordering and the two-hour-before/after calculations.

New collections retain the target's time-zone identifier and actual UTC offset periods, including its daylight-saving setting. Periods cover the previous/current/following calendar years; older explicitly queried windows receive additional coverage. Metadata is collected on the target through the same local/remote collector, including assessments with events disabled. Older saved events use their recorded local timestamp and offset. A timestamp without applicable recorded time-zone evidence is explicitly shown in UTC rather than guessing; rerun an older assessment for complete target-local headings and window boundaries. Saved reports are not rewritten when viewed.

Run `tests/Run-Checks.ps1` while the portal is running for PowerShell parsing, validation, API protection, live local evidence and preservation of the original project files. Open `/assets/live-verification.html` for deterministic assessment/report checks. See `VERIFICATION.md` for the checks completed on this laptop and their limits.

This is a portable local testing application. The loopback portal has same-origin mutation checks and no network-facing authentication setup. Keep the loopback binding when testing.

## Server profiles and event reports

Select **General Purpose Server**, **Database Server**, or **Cluster Node**. Every profile includes CPU, memory, storage, Windows events and connectivity. Database Server also selects SQL; Cluster Node also selects failover-cluster checks. Check both optional roles for a clustered database server. The selected profile is preserved in the saved assessment; actual checked capabilities determine collection.

The **System and Application error summary** scans the last 24 hours for Critical and Error entries, grouped by log, source (provider) and Event ID. Counts are based on a separate error-only scan, rather than a small sample of recent informational entries. Each log's access status is shown. A scan is limited to 20,000 errors per log; if reached, counts are explicitly partial. Older saved assessments show counts from their preserved sample until a new assessment is run.

Select a group to retrieve its error occurrences, then select **Investigate ±2 hours** on a specific timestamp/record. The timeline collects both System and Application logs, across all sources, severities and Event IDs, from two hours before to two hours after that occurrence. The optional clustering-log checkbox includes that log too. Each query returns at most 5,000 events across the selected logs; limits and unavailable logs are disclosed. A future portion of the window remains incomplete until those events exist. Full messages are preserved up to the existing 12,000-character limit per message.

Open the created investigation report to read the chronological timeline, download its indented JSON evidence, download a standalone readable HTML report, or **Print / Save as PDF**. JSON keeps the selected anchor, actual source, UTC boundaries, log coverage and returned events. Reports use VS Code Dark+ colors on screen and a white background on paper. Saved report links require this portal and the local reports folder; downloaded HTML works independently.
