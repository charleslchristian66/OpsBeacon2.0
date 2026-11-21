# Live portable build verification

Verified on Windows PowerShell 5.1 on 2026-11-17. This is a local testing build; verification does not certify production deployment.

## Completed checks

- 27 PowerShell/API checks passed: application scripts parse, request bounds and scope validation, SQL instance input validation, rejected cross-origin/headerless mutations, report round trip, real event occurrence identity, bundled dependencies and unchanged hashes for all 379 original project files.
- 14 deterministic browser checks passed: separate General Purpose and SQL memory assessment, sustained warning/critical durations, brief grant spikes, missing data, short observations, live provenance, readable HTML, escaping and incomplete coverage. Fixtures are confined to the verification page; the live collection UI imports no scenario generator.
- 4 event collector checks passed against the actual Windows System log. A known record was found in its UTC search window, no out-of-window records were returned, event-ID searches preserved record identity and original timezone/source were retained. This includes a regression check for the Windows PowerShell 5.1 Get-WinEvent local-time filter behavior.
- 3 live network checks passed: loopback DNS/ICMP/TCP/HTTP, exactly one successful one-hop trace under a deliberately forced test threshold, and an exhausted inspection budget returning missing coverage without sending probes. The configured production latency threshold remains 170 ms.
- Actual laptop CPU, memory, system-volume capacity and transfer-weighted latency collected. Early cold-provider timeouts remained null and explicit errors; the collector's CIM timeout was increased to accommodate provider startup, and subsequent complete samples succeeded.
- Full browser assessment with all capabilities selected returned real general measurements, 100 event records with explicit truncation, HTTP 200 on the portal and clear unavailable SQL/cluster coverage.
- Manual event-ID search returned separate occurrences. Two different occurrences each produced a 79-event timeline, containing their respective anchors. Both investigations were retained in one saved assessment.
- Standalone HTML download captured and inspected: proper HTML MIME type, live provenance, both investigations, no visible JSON payload. Saved report round trip succeeded. Print media hid assessment/investigation forms and controls while preserving the report. An OS print-to-PDF dialog was not exercised.
- A packaged archive was extracted into a different writable directory and launched on port 8097 with its bundled Pode dependency. Live configuration and HTTP 200 were verified without package installation. The relocated test process was stopped after checking its command path. The final package contains subsequent UI/verification updates; launch and dependency code are unchanged.
- Archive inspection confirmed that reports, jobs, event data, runtime logs and verification result files were excluded. The main working folder retains local test reports.
- Editor diagnostics reported no errors in the PROD folder.

## Environment limits

This laptop has no discovered SQL database-engine instance or FailoverClusters module. Their actual unavailable-role paths were verified; successful SQL DMV queries, a real cluster, cluster-member remoting, file-share/cloud witnesses and multi-node workloads need testing on appropriate servers. SQL/cluster read-only collection is enabled, not simulated.

An explicitly requested WinRM connection to the laptop failed because the endpoint was unavailable. The job reported failure, no actual source and no portal fallback. A successful authenticated remote-server collection was not available to test. No remoting/firewall/security configuration was changed.

Long 5/15-minute observations, external HTTPS endpoints, real high-latency/lossy routes and failure conditions on production infrastructure were not exercised. SQL pressure decision behavior was checked with deterministic evidence, not induced workload. General storage measurements cover the system volume; cluster-member events and SQL workloads require separate assessments. Remote second-hop delegation can restrict member collection.

## Repeat

While the portal is running:

```powershell
.\tests\Run-Checks.ps1
.\tests\Event-Checks.ps1
.\tests\Network-Checks.ps1 -Port 8080
```

Open `/assets/live-verification.html` for the deterministic browser report checks. Run `Build-Portable.ps1` to rebuild the archive without local runtime data.

## Profile and event-summary update — 2026-11-17

The active portal uses port 8080. Restored server profiles (General Purpose Server, Database Server, Cluster Node), grouped System/Application Critical and Error counts, source-specific occurrence selection, separate event investigation reports, and VS Code Dark+ screen styling with white print output.

Validation completed:

- 31 PowerShell/API checks passed, including profile retention/validation and preservation of all 379 original project files.
- 19 live Windows event checks passed. Group counts matched fresh Get-WinEvent error queries by log, source and Event ID. Checks also cover source-filtered occurrences, UTC boundaries, cross-log timelines, result-limit disclosure and an empty period.
- 21 browser report checks passed, including source/log grouping, message escaping, chronological rendering, incomplete-window notices and complete JSON evidence exports.
- Live browser workflow: local General Purpose Server assessment -> 6 source/Event ID groups containing 84 errors -> .NET Runtime / Event 1022 group -> 2 occurrences -> selected record 31618 -> saved 301-event investigation. Both System and Application collected successfully; Error, Warning and Information severities present; no timeline truncation.
- Browser JSON download retained all 301 returned events and the selected anchor. Standalone HTML download included a readable timeline and print controls. Print media hid controls, retained all event content and used a white background; the print button handler was verified. The native OS PDF-save dialog was not automated.
- All three UI profiles selected the intended SQL/cluster check defaults, and the actual profile was preserved in the saved live report. No successful SQL engine/cluster/WinRM endpoint was available; their existing support limits above still apply.
- Editor diagnostics clean. Portable archive rebuilt after these changes; local reports/jobs/logs remain excluded.

The error scan is capped at 20,000 matching errors per log; event searches and investigation timelines at 5,000 returned events across selected logs. The report explicitly discloses partial counts, truncation, unavailable logs and future portions of a window. Older saved assessments retain their original evidence and display sample-based counts until rerun.
## Original threading and job-dispatch parity — 2026-11-17

A complete rollback snapshot was created before editing PROD under `../Rollbacks/PROD-20261117-144703/`: 285 files in `PROD-before-queue-change.zip`, plus a SHA-256 manifest and restore instructions. Every archived file matched its manifest hash.

Inspected the original `Pode-Troubleshooting-POC-Portable-20260818-Optimized/Start-Poc.ps1` and its THD working copy. Both declare 8 web worker threads and a 600-second HTTP timeout, write Queued status, immediately invoke native Start-Job, and poll file-based Running/Completed/Failed status. Neither implements a waiting FIFO, an eight-job collection cap, automatic retries, cancellation management or restart replay. The original connectivity module uses CreateRunspacePool(1, 6).

PROD now matches those thread counts and dispatch semantics. The two-job rejection gate and API's synthetic 35-minute Failed response were removed. Job files retain IDs, submission/start/completion timestamps, source/options/results and worker PIDs. Status writes use atomic replacement (including Windows PowerShell 5.1's required NullString backup-path handling); launch failures save Failed and return HTTP 503. Existing saved reports and assessment evidence are preserved.

The bundled Pode 2.13 needs Server.Request.Timeout in its configuration file to actually set the listener timeout. The original top-level Request layout was adapted accordingly; runtime API verification confirmed the effective 600 seconds. The browser's existing 35-minute wait remains to support PROD's 5/15-minute observations, rather than copying the original UI's three-minute wait.

Validation:

- 16 job lifecycle checks passed, including HTTP 202 Queued acknowledgements, three simultaneous live local assessments in distinct PowerShell processes, lifecycle timestamps, separate results, worker failure and dispatch failure.
- 8 network checks passed: original six-probe setting, all six loopback destinations returned real DNS/ICMP/TCP/HTTP evidence, per-destination trace bounds, a shared deadline for queued work, and measured concurrent runspace execution respecting the six-worker limit. Network workers preserve the inspected source; they do not run on the portal as a remoting fallback.
- 33 PowerShell/API regression checks passed, including all 379 original project file hashes.
- 21 browser report checks passed; the previously saved 301-event investigation still opens after the server restart.
- Per-destination network timeouts, trace budgets, selected capabilities and SQL/cluster/event collection semantics remain as previously documented. Successful remote WinRM, SQL and cluster environments remain untested here.

Repeat with `tests/Job-Checks.ps1` and `tests/Network-Checks.ps1 -Port 8080` while the default portal is running. Start the server with `-WorkerThreads` and `-RequestTimeoutSeconds` to override the original defaults. Closing the browser leaves workers running; stopping the launcher can stop its native PowerShell jobs. There is no automatic replay on restart.
Final live pipeline smoke check: assessment e5b9a0b1-4a41-474c-a391-93abe6909194 completed through native job dispatch and the parallel connectivity wrapper with the real local source and both destinations retained. Both destinations returned DNS, four successful ICMP replies and connected TCP evidence. HTTP to 127.0.0.1:8080 returned 200; HTTP to localhost:8080 reached its configured timeout and was correctly reported as a Warning with its error, rather than fabricated success.

## Historical provider drill-down fix - 2026-11-17

System / googledrivefs31931 / Event 2 / Record 34108 at 2026-11-17T03:46:12.0265066Z reproduced a summary drill-down failure. The stored record exists but Get-WinEvent -ListProvider cannot resolve its publisher. FilterHashtable.ProviderName performs publisher registration lookup, so it fails even though an unfiltered log scan can see the record. The summary-group UI also omitted the failed log coverage from its status.

Provider-specific queries now filter stored record XML with FilterXPath, preserving the original time/ID/severity filters and result cap without requiring installed publisher metadata. Names containing both quote delimiters use a streaming exact-name filter before the result cap. A missing formatted description now shows explicitly labelled stored event data. Failed summary queries surface the actual log error in the investigation pane.

Validation: 23 live event checks passed, covering every current summary source (including this historical Google Drive source), UTC boundaries, timelines, truncation, unavailable descriptions, empty results and quoted source names. Editor diagnostics are clear. A fresh browser assessment selected the Google Drive group, displayed its one matching record and stored text "The driver version of the disk does not match.", then created a 111-event +/-2-hour investigation retaining the anchor. Assessment ae1fd0bc-6335-4a7d-b371-818ea9063ece; investigation 79d23993-1156-47c9-b23e-95ce73030744.

Before edits, the previous portable code archive was copied to ../Rollbacks/PROD-provider-lookup-20261117-152820/, with a SHA-256 manifest and restore instructions. This rollback excludes runtime data; existing assessment evidence remains in PROD. Rebuilt portable code excludes reports/jobs/logs/results as before.

## Target-local report times - 2026-11-17

A verified copy of the previous portable code was saved before edits under ../Rollbacks/PROD-target-time-20261117-161625/, with a SHA-256 manifest and restore instructions. Existing assessment/job data was preserved.

UTC remains the canonical storage/query/order/calculation time. Readable reports now use the inspected target's time zone for assessment metadata, summary periods and most-recent times, occurrence lists, investigation links, window boundaries, collection times and timelines. Every displayed local time includes its UTC offset. HTML exports and print/PDF use the same rendered local timestamps. Raw timestamp evidence remains available separately.

The local/remote target worker captures TimeZoneInfo.Local on the inspected server, its Windows identifier and exact UTC offset periods. Periods cover the previous/current/following calendar years, with extra coverage for explicitly queried historical windows outside those years. Six-hour scans and millisecond boundary searches capture standard/daylight transitions from the target's actual Windows rules, including disabled-DST settings; the browser needs no Windows-to-IANA mapping or external service. Offset evidence is preserved in Collection.TargetTimeZone and event query/investigation targetTimeZone metadata. UTC event timestamps and +/-2 elapsed-hour window calculations are unchanged. Display offsets distinguish the repeated hour when clocks move back.

Older saved reports are not rewritten. Their events use the original local timestamp/offset already collected. Timestamps without applicable target-zone evidence explicitly fall back to UTC; rerun an older assessment for complete target-local headings/window boundaries. UTC values outside recorded offset coverage also fall back explicitly rather than borrowing a current or browser-local offset.

Validation:
- 11 PowerShell time-zone checks passed: Eastern and Australian DST boundaries on both sides, India half-hour offset, UTC, the actual local zone, historical coverage and fixed/no-DST behavior, compared against .NET TimeZoneInfo.
- 15 browser time-display checks passed: previous-date conversion, summer/winter offsets, spring gap, repeated fall hour, half-hour remote-style zone independent of the browser, legacy evidence, explicit fallback, assessment/investigation/standalone HTML display and unchanged UTC JSON exports/order.
- 23 live event checks and 34 PowerShell/API regression checks passed; all 379 original project file hashes remain unchanged. The existing 21 browser report checks also passed. Editor diagnostics are clear.
- Fresh live assessment ef7576cf-5e8d-4fdc-bec0-0b4ff5280f4f displayed Google Drive Event 2 / Record 34108 as Nov 16, 2026, 10:46:12 PM (UTC-05:00). Investigation 554e7a29-3b30-4830-9a33-efbd87ffcbe6 retained all 111 events and the UTC anchor 2026-11-17T03:46:12.0265066Z. Its local window displays 8:46:12 PM through 12:46:12 AM; JSON retains 01:46:12.026Z through 05:46:12.026Z. Downloadable HTML shows the same local times and print controls are enabled.
- A separate live assessment with events disabled completed and still captured the real local target's zone/source. Successful remote-server infrastructure remains unavailable here; remote deployment uses the same embedded target worker. No machine/browser time-zone setting was changed.

Repeat: tests/TimeZone-Checks.ps1 and tests/Event-Checks.ps1. Browser modules /assets/time-verification.js (runTimeChecks) and /assets/live-verification.js (runChecks) expose deterministic display checks. The OS PDF-save dialog was not automated. Portable archive rebuilt without reports/jobs/runtime logs/test results.

## Separate shutdown script - 2026-11-17

Before changes, the portable archive was copied and SHA-256 verified under ../Rollbacks/PROD-stop-script-20261117-214553/, with a manifest and restore instructions. Assessment evidence was preserved.

Stop-OpsBeacon.ps1 defaults to config.json port 8080; Stop-OpsBeacon.cmd provides a double-click entry point. The script verifies every listener belongs to this deployment's dedicated powershell.exe -File launcher before any stop, rechecks process creation times, stops its PowerShell descendants and confirms the listener is gone. It supports WhatIf and Confirm. A launcher identity record under jobs/ supports relative -File startup; stale records cannot authorize reused PIDs. An unrelated port owner is refused. Interrupted Running jobs associated with captured workers become Failed; saved reports are preserved. Use the same account/elevation as startup. An in-process launcher in a shared console must be stopped there with Ctrl+C.

Validation: all 16 shutdown checks passed on Windows PowerShell 5.1. A separate real Pode server on an allocated test port ran a native assessment worker. WhatIf preserved both; actual stop released its port and removed the worker, recording interruption with the original job ID. Repeat stop was harmless. An unrelated live PowerShell TCP listener was refused and preserved. Exact launcher identity, alternate deployment refusal, relative registration, stale PID registration, descendant filtering and unchanged existing report hashes were checked. All 36 PowerShell/API regression checks passed, including all 379 original project file hashes; editor diagnostics are clear. The real port 8080 session received WhatIf only and remains running. Repeat with tests/Stop-Checks.ps1 and tests/Run-Checks.ps1.

## All mounted drive capacities - 2026-11-18

Rollback created before edits: ../Rollbacks/PROD-all-volumes-20261118-081445/, containing a SHA-256 verified copy of the previous portable ZIP, manifest and restore instructions. Existing reports/jobs were preserved.

The shared target collector now queries Win32_Volume with Win32_MountPoint associations to collect drive-letter and folder-mounted volume capacity once per volume, retaining all mount aliases. Unmounted recovery/system partitions are excluded. Win32_LogicalDisk adds mapped network drives visible to the inspected identity/session. Each row retains raw total/used/free bytes, unrounded free percentage, label, filesystem and mount paths. Unknown/inaccessible/no-media capacity remains unavailable; discovery failures are explicit partial coverage. Legacy system-drive fields remain for older consumers. System-drive latency sampling is unchanged. The collector is embedded in the same local/WinRM/cluster-member worker paths.

Reports show a mounted-drive table with total/used/free GiB, free percentage and individual threshold status. Capacity findings contribute independently to health, so another full volume cannot be hidden by healthy C: capacity. The readable report, standalone HTML and print/PDF content share this table; raw JSON retains all volume evidence. Saved older reports retain their original evidence and continue rendering. Refresh the application and run a new assessment to collect all volumes.

Validation: 14 Windows PowerShell collection checks passed, including live C: and G: capacities/byte accounting, folder mounts with aliases, hidden partitions, full volumes, missing media, visible network mapping and discovery failures. 34 JavaScript report checks passed (13 new capacity checks plus all 21 existing report checks), covering individual health, escaping, HTML/PDF content, JSON, partial/empty coverage, old reports and cluster findings. Browser report modules were executed with the installed VS Code Node runtime; no Node dependency is added to the application. The native OS PDF-save dialog was not automated. All 37 PowerShell/API regression checks passed, including preservation of all 379 original project file hashes. Editor diagnostics are clear.

Fresh real API/native-job assessment 8062c00a-0d2b-4851-b92f-5d058bd11ff6 completed on DEMO-LAPTOP and returned C: and G: with Collected coverage. C: total 126804291584 bytes; G: total 107374182400 bytes. Its actual collected values also passed readable/standalone report rendering checks. Folder mounts, unavailable media and mapped drives used deterministic fixtures; no disk/mount configuration was changed. Successful remote WinRM/cluster infrastructure remains unavailable here. The test portal is running on port 8080.

Repeat: tests/Volume-Checks.ps1 and tests/Run-Checks.ps1. tests/Volume-Report-Checks.mjs runs in a modern Node runtime after Volume-Checks.ps1 and while the portal is on port 8080. The portable ZIP was rebuilt with Start-OpsBeacon.ps1, Start-OpsBeacon.cmd, Stop-OpsBeacon.ps1 and Stop-OpsBeacon.cmd; archive source hashes and exclusions were checked.

## Assessment form and error-summary layout - 2026-11-18

Rollback: ../Rollbacks/PROD-layout-20261118-223304/, with a verified copy of the previous portable ZIP and restore instructions.

The Server type field now occupies the next cell in the existing responsive assessment grid, matching the left-column controls above it. Removed its independent 550px width. The event summary's first Log column and its coverage table's second Log column now reserve at least 110px and keep log names on one line. The scoped report rules apply on screen and in standalone/printed reports. Existing start/stop launchers are preserved.

Validation: headless Edge measured both layouts at actual viewport widths 1256px and 576px. All seven checks passed at each width: shared grid placement, matching dropdown left edge/width, both Application cells present, adequate/no-wrap Log widths, one text line per log name and form containment. All 34 existing report checks passed using the saved live volume evidence and the bundled configuration (no live API needed). Editor diagnostics are clear. Portable archive rebuilt and source hashes/start-stop scripts verified.
# Pending reboot detection - 2026-11-18

- Rollback: `../Rollbacks/PROD-pending-reboot-20261118-230052/OpsBeacon-Live-Portable.zip`; pre-change SHA256 `E47CDFF34397496B1DD13EC7324813532B715A8E00B198AF96E7BC5394F720D6`.
- Added read-only Windows servicing, Windows Update and both pending-file-rename registry indicators to general collection. Uses the target's native registry view; collection code travels with the existing authenticated remote worker. Helper is nested so serialized cluster-member collection also includes it.
- Detected indicators produce Warning. Missing or empty indicators are clear only when all checks are readable; any unreadable indicator preserves Unknown / Not Assessed unless other evidence already establishes a pending reboot. Collection errors remain explicit.
- All profiles include the main target's reboot finding, with indicator details in live, saved, downloaded and print/PDF reports. UTC evidence and target-time display are retained. Historical reports are not backfilled.
- Validation: 12 PowerShell checks, 16 reboot report checks and all 34 existing volume/report regression checks passed. No target registry values were changed.
- Live server integration: submitted one three-second local assessment through the real queued API. Completed with four reboot indicators and full coverage. The laptop reported pending file rename operations; Windows Update and CBS reboot flags were absent. This is indicator evidence, not proof that an immediate restart is required.
- Remote WinRM and cluster infrastructure were not available for a live remote run; those execution paths use the same serialized collector.

