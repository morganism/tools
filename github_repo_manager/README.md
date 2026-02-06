# GitHub Repository Manager

A comprehensive Ruby CLI tool to manage, monitor, and sync your GitHub repositories. Keep your local repos in sync with remote, check branch status, and selectively update repositories with an interactive interface.

## Features

- 🔍 **Scan Local Repositories**: Automatically discover git repos in your workspace
- 🌐 **GitHub Integration**: Connect to GitHub API to view all your remote repositories
- 📊 **Status Reporting**: See at-a-glance status of local vs. remote sync state
- 🔄 **Selective Updates**: Choose which repositories to update with an interactive menu
- 🎨 **Beautiful CLI**: Color-coded output and intuitive table displays
- ⚙️ **Configurable**: Customize base paths, auto-fetch behavior, and more
- 🔐 **Secure**: GitHub token stored in local config file

## Installation

### Quick Start (Bundler Inline)

The tool uses Bundler inline by default, so you can run it without installing gems globally:

```bash
chmod +x github-repo-manager
./github-repo-manager
```

Gems will be automatically installed on first run.

### Traditional Installation

If you prefer traditional gem management:

```bash
bundle install
```

Then modify `github-repo-manager` to remove the `bundler/inline` section and add:

```ruby
require 'bundler/setup'
```

## Setup

### GitHub Personal Access Token

You'll need a GitHub personal access token with `repo` scope:

1. Go to https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Select scopes: `repo` (Full control of private repositories)
4. Generate and copy the token

The tool will prompt for the token on first run and save it to `~/.github-repo-manager.yml`.

Alternatively, set the `GITHUB_TOKEN` environment variable:

```bash
export GITHUB_TOKEN="your_token_here"
```

Or create a `.env` file:

```bash
echo "GITHUB_TOKEN=your_token_here" > .env
```

## Configuration

The tool creates a configuration file at `~/.github-repo-manager.yml`:

```yaml
---
local_repos_path: /home/user/code
github_token: ghp_xxxxxxxxxxxxx
default_branch: main
auto_fetch: true
```

### Configuration Options

- **local_repos_path**: Base directory to scan for git repositories
- **github_token**: Your GitHub personal access token
- **default_branch**: Default branch name (usually `main` or `master`)
- **auto_fetch**: Automatically fetch from remotes when scanning (recommended)

You can modify these settings through the interactive "Settings" menu.

## Usage

Run the tool:

```bash
./github-repo-manager
```

### Main Menu Options

1. **Scan local repositories**
   - Scans the configured path for git repositories
   - Shows sync status, current branch, and uncommitted changes
   - Automatically fetches from remotes if auto_fetch is enabled

2. **Check remote GitHub repositories**
   - Lists all repositories in your GitHub account
   - Shows default branch, visibility, and last push time

3. **Check both local and remote**
   - Combined view showing which repos exist locally, remotely, or both
   - Identifies repositories that need to be cloned or pushed

4. **Update selected repositories**
   - Shows repositories that are behind their remote
   - Interactive multi-select menu to choose which repos to update
   - Handles uncommitted changes with stash/skip/force options
   - Uses rebase strategy for diverged branches

5. **Settings**
   - Configure local repos path
   - Toggle auto-fetch behavior
   - Update GitHub token

6. **Exit**
   - Peace out! ✌️

### Status Indicators

#### Sync Status
- ✓ **Up to date**: Local matches remote
- ↓ **Behind**: Local is behind remote (pull needed)
- ↑ **Ahead**: Local is ahead of remote (push available)
- ⚠ **Diverged**: Local and remote have diverged
- ○ **No remote**: Repository has no remote configured
- ? **Unknown**: Unable to determine status

#### Changes
- **Modified**: Uncommitted changes in working directory
- **Staged**: Changes staged for commit

## Workflow Examples

### Daily Sync

```bash
# Quick check and update all repos
./github-repo-manager
# Choose: "Check both local and remote" → "Update selected repositories"
```

### Find Repos That Need Attention

```bash
# See which repos are behind
./github-repo-manager
# Choose: "Scan local repositories"
# Look for ↓ (behind) or ⚠ (diverged) indicators
```

### Audit Your GitHub Account

```bash
# See all remote repos including those not cloned locally
./github-repo-manager
# Choose: "Check both local and remote"
# Look for "Not cloned" in the sync column
```

## Advanced Features

### Handling Uncommitted Changes

When updating a repository with uncommitted changes, you'll be prompted:

1. **Stash changes and pull**: Saves changes, pulls updates, optionally re-applies changes
2. **Skip this repository**: Leaves repository unchanged
3. **Force pull**: Discards local changes (⚠️ destructive!)

### Diverged Branches

For diverged branches, the tool uses `git pull --rebase` to maintain a clean history. If conflicts occur, you'll need to resolve them manually.

### Debug Mode

Enable debug output:

```bash
DEBUG=1 ./github-repo-manager
```

## Requirements

- Ruby >= 3.0.0
- Git installed and in PATH
- Internet connection for GitHub API
- GitHub personal access token

## Dependencies

- **octokit**: GitHub API client
- **tty-prompt**: Interactive CLI prompts
- **tty-table**: Beautiful table rendering
- **tty-spinner**: Loading spinners
- **pastel**: Color output
- **dotenv**: Environment variable management

## File Structure

```
.
├── github-repo-manager          # Main executable
├── lib/
│   └── github_repo_manager.rb   # Core logic
├── Gemfile                       # Gem dependencies
├── README.md                     # This file
└── .env.example                  # Example environment file
```

## Troubleshooting

### "Invalid GitHub token"

- Regenerate your token at https://github.com/settings/tokens
- Ensure `repo` scope is enabled
- Update via Settings menu or edit `~/.github-repo-manager.yml`

### "Directory not found"

- Check that `local_repos_path` in config points to valid directory
- Update path via Settings menu

### Repositories Not Detected

- Ensure repositories have `.git` directory
- Run with `DEBUG=1` to see detailed scanning output
- Check that path doesn't have permission issues

### Fetch Failures

- Verify network connectivity
- Check that repository remotes are properly configured
- Try `git fetch` manually in the repository

## Contributing

This is a personal tool, but feel free to fork and modify for your needs.

## License

Do whatever you want with it. It's just code.

## Author

Built with ❤️ and Ruby for managing the chaos of multiple repositories.

---

*"The only way to deal with an unfree world is to become so absolutely free that your very existence is an act of rebellion."* - Albert Camus (probably talking about git repos)
