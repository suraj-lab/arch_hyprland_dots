# Set up the pi coding agent on Windows from this repo's pi/ directory.
# Run from anywhere:  powershell -ExecutionPolicy Bypass -File scripts\setup-pi-windows.ps1
# Safe to re-run. Never touches auth.json (log in with `pi` once per machine).
$ErrorActionPreference = 'Stop'

$repo  = Split-Path $PSScriptRoot -Parent
$src   = Join-Path $repo 'pi'
$dst   = Join-Path $HOME '.pi\agent'
$tutor = Join-Path $HOME 'Projects\ai-tutor'

foreach ($t in 'git', 'node', 'npm') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
        throw "$t not found. Install Node.js 22.19+ and Git for Windows (pi uses its Git Bash) first."
    }
}
if (-not (Get-Command pi -ErrorAction SilentlyContinue)) {
    npm install -g @earendil-works/pi-coding-agent
}

# robocopy exit codes below 8 mean success.
function Copy-Tree($from, $to, [string[]]$extra) {
    robocopy $from $to /E /NFL /NDL /NJH /NJS @extra | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE): $from" }
}

# Skipped: Linux-only persona/skills/monitor, and the quiz/teach symlinks (copied from ai-tutor below).
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Tree $src $dst @('/XD', 'arch', 'hyprland', 'quickshell', 'qmk', 'quiz', 'teach', 'node_modules',
                      '/XF', 'AGENTS.md', 'mcp-monitor.sh', 'quiz', 'teach')

# quiz/teach are symlinks into the ai-tutor repo on Linux; clone it and copy the real files.
if (Test-Path $tutor) { git -C $tutor pull --ff-only } else { git clone https://github.com/suraj-lab/ai-tutor.git $tutor }
foreach ($s in 'quiz', 'teach') { Copy-Tree "$tutor\skills\$s" "$dst\skills\$s" @('/MIR') }

# Extensions ship without node_modules.
Get-ChildItem "$dst\extensions" -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path "$($_.FullName)\package.json" } |
    ForEach-Object { npm install --prefix $_.FullName --omit=dev }

# Install the packages listed in settings.json (idempotent).
(Get-Content "$dst\settings.json" -Raw | ConvertFrom-Json).packages | ForEach-Object { pi install $_ }

Write-Host "Done. Run 'pi' once and log in to your provider (auth is per-machine)."
