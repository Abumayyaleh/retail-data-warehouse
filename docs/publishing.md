# Publish to GitHub

Create an empty GitHub repository named `retail-data-warehouse` under `Abumayyaleh`. Leave GitHub's README, license, and .gitignore initialization unchecked. Authenticate with your own GitHub account when Git asks.

Run these exact commands in PowerShell for this delivered folder:

```powershell
Set-Location 'C:\Users\mohdr\Documents\Codex\2026-09-15\organize-my-retail-data-warehouse-project\outputs\retail-data-warehouse'
git init -b main
git add README.md .gitignore sql data docs
git diff --cached --stat
git commit -m "Build PostgreSQL retail data warehouse portfolio"
git remote add origin https://github.com/Abumayyaleh/retail-data-warehouse.git
git push -u origin main
```

If Git requests an author identity, configure your actual name and email locally with `git config user.name "YOUR NAME"` and `git config user.email "YOUR EMAIL"`, then repeat the commit and subsequent steps. No identity is preconfigured by this project.

These commands assume a new local repository and an empty remote. If the remote already contains commits, fetch and reconcile its contents before pushing; do not force-push over existing work. Source CSVs are excluded by `.gitignore`. No license is selected on the author's behalf.
