# Documentation site

The public documentation site uses Hugo and the pinned Hugo Geekdoc release
defined in `Install-Theme.ps1`. Existing Markdown under `docs/` remains the
authoritative content for both GitHub and generated vending repositories.
Hugo module mounts expose that content under the `/docs/` site section.

Use Hugo Extended `0.167.0` or newer. The pinned Geekdoc release requires Hugo
`0.160.0` or newer.

## Preview locally

Install Hugo Extended on Windows if needed:

```powershell
winget install --id Hugo.Hugo.Extended --exact --source winget
```

Restart the terminal after installing Hugo, then run the version-checking
preview wrapper:

```powershell
pwsh ./website/Start-Preview.ps1
```

The wrapper installs the verified theme, rejects incompatible or non-extended
Hugo versions with an actionable message, and serves the site at
`http://localhost:1313/`. Additional Hugo server arguments can be appended to
the command.

The production site uses:

```text
https://haflidif.github.io/alz-sub-vending-accelerator/
```

## Validate a production build

```powershell
pwsh ./website/Install-Theme.ps1
hugo --source website --minify --gc
python ./website/scripts/check-site.py ./website/public `
  ./website/public `
  --base-path /alz-sub-vending-accelerator/
```

The checker validates internal links and fragments, document titles, language
metadata, and the main-content landmark.
