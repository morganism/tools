# Quick Start Guide

Get up and running in 3 minutes.

## 1. Get Your GitHub Token

Visit: https://github.com/settings/tokens/new

- Description: `GitHub Repo Manager`
- Expiration: Choose your preference
- Select scopes: ✅ `repo` (Full control of private repositories)
- Click "Generate token"
- **Copy the token** (you won't see it again!)

## 2. Install

```bash
./install.sh
```

## 3. Configure

Edit `.env` and add your token:

```bash
GITHUB_TOKEN=ghp_your_token_here
```

Or just let the tool prompt you on first run.

## 4. Run

```bash
./github-repo-manager
```

## First Run Workflow

1. **Select option 3**: "Check both local and remote"
   - This scans your local repos AND fetches from GitHub
   - You'll see which repos are synced, behind, ahead, etc.

2. **Select option 4**: "Update selected repositories"
   - Pick repos that are behind
   - Let it pull the latest changes

That's it! 🎉

## Common Tasks

### Update Everything Daily

```bash
./github-repo-manager
# Choose: 3 (check both) → 4 (update selected)
```

### Clone Missing Repos

```bash
# Find repos on GitHub that aren't cloned locally
./examples.rb clone ~/code
```

### Auto-Update Script

```bash
# Updates all repos that are behind, no interaction needed
./examples.rb update
```

### Get a Status Report

```bash
./examples.rb report
```

## Troubleshooting

**"Invalid GitHub token"**
- Regenerate at https://github.com/settings/tokens
- Make sure `repo` scope is checked
- Update in Settings menu (option 5)

**"Directory not found"**
- Edit `~/.github-repo-manager.yml`
- Set `local_repos_path` to where your repos live

**Gems won't install**
- Make sure you have Ruby >= 3.0: `ruby -v`
- Try: `bundle install` manually

## Pro Tips

1. **Auto-fetch enabled**: Automatically runs `git fetch` when scanning
2. **Stash changes**: Tool will offer to stash uncommitted changes during updates
3. **Settings menu**: Configure paths and behavior without editing files
4. **Debug mode**: Run with `DEBUG=1 ./github-repo-manager` to see details

## What It Does

- Scans your local repos for sync status
- Fetches from GitHub to see all your remote repos
- Shows which are behind, ahead, or diverged
- Lets you selectively pull updates
- Handles merge conflicts and uncommitted changes

---

Happy repo wrangling! 🚀
