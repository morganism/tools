# frozen_string_literal: true

require 'octokit'
require 'tty-prompt'
require 'tty-table'
require 'tty-spinner'
require 'pastel'
require 'dotenv/load'
require 'fileutils'
require 'yaml'

class GitHubRepoManager
  CONFIG_FILE = File.expand_path('~/.github-repo-manager.yml')
  
  def initialize
    @pastel = Pastel.new
    @prompt = TTY::Prompt.new
    load_config
    setup_github_client
    @local_repos = []
    @remote_repos = []
  end

  def run
    show_banner
    
    loop do
      choice = @prompt.select('What would you like to do?', cycle: true) do |menu|
        menu.choice 'Scan local repositories', 1
        menu.choice 'Check remote GitHub repositories', 2
        menu.choice 'Check both local and remote', 3
        menu.choice 'Update selected repositories', 4
        menu.choice 'Settings', 5
        menu.choice 'Exit', 6
      end

      case choice
      when 1
        scan_local_repos
        display_local_status
      when 2
        fetch_remote_repos
        display_remote_status
      when 3
        scan_local_repos
        fetch_remote_repos
        display_combined_status
      when 4
        update_repositories
      when 5
        configure_settings
      when 6
        puts @pastel.cyan("\nPeace out! ✌️")
        break
      end
    end
  end

  private

  def show_banner
    banner = <<~BANNER
      #{@pastel.bright_cyan.bold('╔═══════════════════════════════════════╗')}
      #{@pastel.bright_cyan.bold('║')}  #{@pastel.bright_magenta.bold('GitHub Repository Manager')}      #{@pastel.bright_cyan.bold('║')}
      #{@pastel.bright_cyan.bold('║')}  #{@pastel.dim('Keep your repos in sync')}           #{@pastel.bright_cyan.bold('║')}
      #{@pastel.bright_cyan.bold('╚═══════════════════════════════════════╝')}
    BANNER
    puts banner
  end

  def load_config
    if File.exist?(CONFIG_FILE)
      @config = YAML.load_file(CONFIG_FILE)
    else
      @config = {
        'local_repos_path' => File.expand_path('~/code'),
        'github_token' => ENV['GITHUB_TOKEN'],
        'default_branch' => 'main',
        'auto_fetch' => true
      }
      save_config
    end
  end

  def save_config
    File.write(CONFIG_FILE, @config.to_yaml)
  end

  def setup_github_client
    token = @config['github_token'] || ENV['GITHUB_TOKEN']
    
    unless token
      puts @pastel.yellow("\n⚠️  No GitHub token found!")
      token = @prompt.mask('Enter your GitHub personal access token:')
      @config['github_token'] = token
      save_config
    end

    @client = Octokit::Client.new(access_token: token)
    @client.auto_paginate = true
    
    # Test the connection
    begin
      @user = @client.user
      puts @pastel.green("\n✓ Connected to GitHub as #{@pastel.bold(@user.login)}")
    rescue Octokit::Unauthorized
      puts @pastel.red("\n✗ Invalid GitHub token!")
      exit 1
    end
  end

  def scan_local_repos
    puts @pastel.cyan("\n🔍 Scanning local repositories...")
    base_path = @config['local_repos_path']
    
    unless Dir.exist?(base_path)
      puts @pastel.yellow("  Directory not found: #{base_path}")
      return
    end

    spinner = TTY::Spinner.new("[:spinner] Scanning...", format: :dots)
    spinner.auto_spin
    
    @local_repos = []
    
    Dir.glob("#{base_path}/*/.git").each do |git_dir|
      repo_path = File.dirname(git_dir)
      next unless File.directory?(repo_path)
      
      repo_info = analyze_local_repo(repo_path)
      @local_repos << repo_info if repo_info
    end
    
    spinner.success("(Found #{@local_repos.size} repositories)")
  end

  def analyze_local_repo(path)
    Dir.chdir(path) do
      return nil unless system('git rev-parse --git-dir > /dev/null 2>&1')
      
      repo_name = File.basename(path)
      current_branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
      
      # Get remote info
      remote_url = `git config --get remote.origin.url 2>/dev/null`.strip
      remote_name = extract_repo_name(remote_url)
      
      # Check if we have a remote
      has_remote = !remote_url.empty?
      
      # Fetch if auto_fetch is enabled
      if has_remote && @config['auto_fetch']
        system('git fetch --quiet 2>/dev/null')
      end
      
      # Get branch status
      branches = `git branch -a`.split("\n").map(&:strip).reject(&:empty?)
      
      # Check if current branch is up to date with remote
      status = {
        path: path,
        name: repo_name,
        remote_name: remote_name,
        current_branch: current_branch,
        branches: branches,
        has_remote: has_remote,
        remote_url: remote_url
      }
      
      if has_remote && current_branch != 'HEAD'
        # Check if local is behind remote
        local_commit = `git rev-parse #{current_branch} 2>/dev/null`.strip
        remote_commit = `git rev-parse origin/#{current_branch} 2>/dev/null`.strip
        
        if local_commit.empty? || remote_commit.empty?
          status[:sync_status] = 'unknown'
        elsif local_commit == remote_commit
          status[:sync_status] = 'up-to-date'
        else
          ahead = `git rev-list --count origin/#{current_branch}..#{current_branch} 2>/dev/null`.strip.to_i
          behind = `git rev-list --count #{current_branch}..origin/#{current_branch} 2>/dev/null`.strip.to_i
          
          status[:commits_ahead] = ahead
          status[:commits_behind] = behind
          
          if ahead > 0 && behind > 0
            status[:sync_status] = 'diverged'
          elsif behind > 0
            status[:sync_status] = 'behind'
          elsif ahead > 0
            status[:sync_status] = 'ahead'
          else
            status[:sync_status] = 'up-to-date'
          end
        end
      else
        status[:sync_status] = 'no-remote'
      end
      
      # Check for uncommitted changes
      status[:has_changes] = !system('git diff --quiet 2>/dev/null')
      status[:has_staged] = !system('git diff --cached --quiet 2>/dev/null')
      
      status
    end
  rescue => e
    puts @pastel.red("  Error analyzing #{path}: #{e.message}") if ENV['DEBUG']
    nil
  end

  def extract_repo_name(url)
    return nil if url.empty?
    # Extract repo name from git URL
    url.split('/').last.gsub(/\.git$/, '')
  end

  def fetch_remote_repos
    puts @pastel.cyan("\n🌐 Fetching GitHub repositories...")
    spinner = TTY::Spinner.new("[:spinner] Loading...", format: :dots)
    spinner.auto_spin
    
    begin
      repos = @client.repositories
      @remote_repos = repos.map do |repo|
        {
          name: repo.name,
          full_name: repo.full_name,
          default_branch: repo.default_branch,
          private: repo.private,
          fork: repo.fork,
          archived: repo.archived,
          pushed_at: repo.pushed_at,
          url: repo.html_url,
          clone_url: repo.clone_url
        }
      end
      spinner.success("(Found #{@remote_repos.size} repositories)")
    rescue => e
      spinner.error("(Failed: #{e.message})")
    end
  end

  def display_local_status
    return if @local_repos.empty?
    
    puts @pastel.cyan("\n📂 Local Repository Status:")
    
    headers = ['Name', 'Branch', 'Status', 'Changes']
    rows = @local_repos.map do |repo|
      status_color = case repo[:sync_status]
                     when 'up-to-date' then :green
                     when 'behind' then :yellow
                     when 'ahead' then :blue
                     when 'diverged' then :magenta
                     else :dim
                     end
      
      status_text = case repo[:sync_status]
                    when 'up-to-date' then '✓ Up to date'
                    when 'behind' then "↓ Behind #{repo[:commits_behind]}"
                    when 'ahead' then "↑ Ahead #{repo[:commits_ahead]}"
                    when 'diverged' then "⚠ Diverged (↑#{repo[:commits_ahead]} ↓#{repo[:commits_behind]})"
                    when 'no-remote' then '○ No remote'
                    else '? Unknown'
                    end
      
      changes = []
      changes << 'Modified' if repo[:has_changes]
      changes << 'Staged' if repo[:has_staged]
      changes_text = changes.empty? ? '-' : changes.join(', ')
      
      [
        repo[:name],
        repo[:current_branch],
        @pastel.decorate(status_text, status_color),
        changes_text
      ]
    end
    
    table = TTY::Table.new(headers, rows)
    puts table.render(:unicode, padding: [0, 1])
  end

  def display_remote_status
    return if @remote_repos.empty?
    
    puts @pastel.cyan("\n🌐 Remote GitHub Repositories:")
    
    headers = ['Name', 'Default Branch', 'Type', 'Last Push']
    rows = @remote_repos.map do |repo|
      type_tags = []
      type_tags << 'Private' if repo[:private]
      type_tags << 'Fork' if repo[:fork]
      type_tags << 'Archived' if repo[:archived]
      type_text = type_tags.empty? ? 'Public' : type_tags.join(', ')
      
      [
        repo[:name],
        repo[:default_branch],
        type_text,
        format_time_ago(repo[:pushed_at])
      ]
    end
    
    table = TTY::Table.new(headers, rows)
    puts table.render(:unicode, padding: [0, 1])
  end

  def display_combined_status
    return if @local_repos.empty? && @remote_repos.empty?
    
    puts @pastel.cyan("\n📊 Combined Repository Status:")
    
    # Create a hash of local repos by name
    local_by_name = @local_repos.each_with_object({}) do |repo, hash|
      name = repo[:remote_name] || repo[:name]
      hash[name] = repo
    end
    
    # Create a hash of remote repos by name
    remote_by_name = @remote_repos.each_with_object({}) { |repo, hash| hash[repo[:name]] = repo }
    
    # Combine all repo names
    all_names = (local_by_name.keys + remote_by_name.keys).uniq.sort
    
    headers = ['Name', 'Local Status', 'Remote', 'Sync']
    rows = all_names.map do |name|
      local = local_by_name[name]
      remote = remote_by_name[name]
      
      local_status = if local
                       case local[:sync_status]
                       when 'up-to-date' then @pastel.green('✓')
                       when 'behind' then @pastel.yellow('↓')
                       when 'ahead' then @pastel.blue('↑')
                       when 'diverged' then @pastel.magenta('⚠')
                       else @pastel.dim('○')
                       end
                     else
                       @pastel.dim('-')
                     end
      
      remote_status = remote ? @pastel.green('✓') : @pastel.dim('-')
      
      sync_status = if local && remote
                      if local[:sync_status] == 'up-to-date'
                        @pastel.green('In sync')
                      elsif local[:sync_status] == 'behind'
                        @pastel.yellow('Pull needed')
                      elsif local[:sync_status] == 'ahead'
                        @pastel.blue('Push available')
                      elsif local[:sync_status] == 'diverged'
                        @pastel.magenta('Diverged')
                      else
                        @pastel.dim('Unknown')
                      end
                    elsif local && !remote
                      @pastel.cyan('Local only')
                    elsif !local && remote
                      @pastel.yellow('Not cloned')
                    else
                      '-'
                    end
      
      [name, local_status, remote_status, sync_status]
    end
    
    table = TTY::Table.new(headers, rows)
    puts table.render(:unicode, padding: [0, 1])
  end

  def update_repositories
    if @local_repos.empty?
      puts @pastel.yellow("\n⚠️  No local repositories found. Scan first!")
      return
    end
    
    # Filter repos that can be updated
    updatable = @local_repos.select do |repo|
      repo[:sync_status] == 'behind' || repo[:sync_status] == 'diverged'
    end
    
    if updatable.empty?
      puts @pastel.green("\n✓ All repositories are up to date!")
      return
    end
    
    puts @pastel.cyan("\n🔄 Updatable Repositories:")
    
    choices = updatable.map do |repo|
      status_info = case repo[:sync_status]
                    when 'behind' then "↓ #{repo[:commits_behind]} commits behind"
                    when 'diverged' then "⚠ Diverged (↑#{repo[:commits_ahead]} ↓#{repo[:commits_behind]})"
                    else repo[:sync_status]
                    end
      
      { name: "#{repo[:name]} - #{status_info}", value: repo }
    end
    
    selected = @prompt.multi_select(
      'Select repositories to update:',
      choices,
      per_page: 15,
      echo: false
    )
    
    return if selected.empty?
    
    puts "\n"
    selected.each do |repo|
      update_repo(repo)
    end
    
    puts @pastel.green("\n✓ Update process complete!")
  end

  def update_repo(repo)
    puts @pastel.cyan("Updating #{repo[:name]}...")
    
    Dir.chdir(repo[:path]) do
      # Check for uncommitted changes
      if repo[:has_changes] || repo[:has_staged]
        puts @pastel.yellow("  ⚠️  Repository has uncommitted changes!")
        
        action = @prompt.select('What would you like to do?') do |menu|
          menu.choice 'Stash changes and pull', :stash
          menu.choice 'Skip this repository', :skip
          menu.choice 'Force pull (discard changes)', :force
        end
        
        case action
        when :skip
          puts @pastel.dim("  Skipped")
          return
        when :stash
          puts @pastel.dim("  Stashing changes...")
          system('git stash')
        when :force
          puts @pastel.yellow("  ⚠️  Discarding local changes...")
          system('git reset --hard HEAD')
        end
      end
      
      # Perform the update
      puts @pastel.dim("  Pulling latest changes...")
      
      if repo[:sync_status] == 'diverged'
        puts @pastel.yellow("  ⚠️  Branch has diverged. Using rebase strategy...")
        success = system("git pull --rebase origin #{repo[:current_branch]}")
      else
        success = system("git pull origin #{repo[:current_branch]}")
      end
      
      if success
        puts @pastel.green("  ✓ Updated successfully")
        
        # Pop stash if we stashed
        if repo[:has_changes] || repo[:has_staged]
          if @prompt.yes?('  Apply stashed changes?')
            system('git stash pop')
          end
        end
      else
        puts @pastel.red("  ✗ Update failed!")
      end
    end
  end

  def configure_settings
    puts @pastel.cyan("\n⚙️  Settings:")
    
    choice = @prompt.select('What would you like to configure?') do |menu|
      menu.choice "Local repos path (current: #{@config['local_repos_path']})", :path
      menu.choice "Auto-fetch (current: #{@config['auto_fetch']})", :fetch
      menu.choice 'Reset GitHub token', :token
      menu.choice 'Back', :back
    end
    
    case choice
    when :path
      new_path = @prompt.ask('Enter path to scan for repositories:', default: @config['local_repos_path'])
      @config['local_repos_path'] = File.expand_path(new_path)
      save_config
      puts @pastel.green("✓ Path updated")
      
    when :fetch
      @config['auto_fetch'] = @prompt.yes?('Enable auto-fetch?')
      save_config
      puts @pastel.green("✓ Auto-fetch #{@config['auto_fetch'] ? 'enabled' : 'disabled'}")
      
    when :token
      new_token = @prompt.mask('Enter new GitHub token:')
      @config['github_token'] = new_token
      save_config
      setup_github_client
      puts @pastel.green("✓ Token updated")
    end
  end

  def format_time_ago(time)
    return 'Never' unless time
    
    diff = Time.now - time
    
    case diff
    when 0..59
      "#{diff.to_i}s ago"
    when 60..3599
      "#{(diff / 60).to_i}m ago"
    when 3600..86399
      "#{(diff / 3600).to_i}h ago"
    when 86400..2591999
      "#{(diff / 86400).to_i}d ago"
    else
      time.strftime('%Y-%m-%d')
    end
  end
end
