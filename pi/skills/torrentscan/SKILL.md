---
name: torrentscan
description: Scan torrent downloads for suspicious content — file types, malware strings, structure anomalies
---

# Torrent Scan Skill

Run `torrentscan` to inspect torrents. The tool handles everything — file types, strings sweeps, extension checks, hash generation.

## Workflow

**Pre-download (.torrent files):**
```bash
torrentscan ~/Downloads/*.torrent
```
Shows full file listing from metadata. Red flags: `.scr`, `.bat`, `.cmd`, `.vbs`, `.ps1` in media releases, or double extensions like `.mkv.exe`.

**Post-download (completed directories):**
```bash
torrentscan ~/Downloads/SomeRelease/
```
Or scan qBittorrent's completed location:
```bash
torrentscan /mnt/second/torrents/*/
```

**Both at once:**
```bash
torrentscan ~/Downloads/*.torrent ~/Downloads/*/ /mnt/second/torrents/*/
```

## Interpretation guide

When reporting results to the user:
- **Media-only (.mkv/.mp4/.flac) with no executables** → low risk, no further action
- **Single Setup.exe + archives (.bin/.doi)** → typical scene game repack, note the SHA256 for VirusTotal
- **Executable in a media release** → flag immediately, that's a malware pattern
- **Strings sweep flagged** → list the exact patterns found, don't generalize
- **Suspicious extensions (.scr/.bat/.vbs/.ps1)** → flag immediately

If the user wants deeper analysis of an executable beyond what torrentscan shows, run additional `strings` patterns or offer to hash it for VirusTotal.
