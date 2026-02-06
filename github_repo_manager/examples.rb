#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Using GitHubRepoManager programmatically
# This shows how to extend or automate the tool

require_relative 'lib/github_repo_manager'

# Example 1: Auto-update all repositories that are behind
def auto_update_all_behind
  manager = GitHubRepoManager.new
  
  # Access private methods using send for automation
  manager.send(:scan_local_repos)
  local_repos = manager.instance_variable_get(:@local_repos)
  
  behind_repos = local_repos.select { |r| r[:sync_status] == 'behind' }
  
  puts "Found #{behind_repos.size} repositories behind remote"
  
  behind_repos.each do |repo|
    puts "\nUpdating #{repo[:name]}..."
    manager.send(:update_repo, repo)
  end
  
  puts "\n✓ All repositories updated!"
end

# Example 2: Generate a report of repository status
def generate_status_report
  manager = GitHubRepoManager.new
  manager.send(:scan_local_repos)
  manager.send(:fetch_remote_repos)
  
  local_repos = manager.instance_variable_get(:@local_repos)
  remote_repos = manager.instance_variable_get(:@remote_repos)
  
  report = {
    timestamp: Time.now,
    local_count: local_repos.size,
    remote_count: remote_repos.size,
    behind: local_repos.count { |r| r[:sync_status] == 'behind' },
    ahead: local_repos.count { |r| r[:sync_status] == 'ahead' },
    diverged: local_repos.count { |r| r[:sync_status] == 'diverged' },
    up_to_date: local_repos.count { |r| r[:sync_status] == 'up-to-date' },
    with_changes: local_repos.count { |r| r[:has_changes] || r[:has_staged] }
  }
  
  puts "\n=== Repository Status Report ==="
  puts "Generated: #{report[:timestamp]}"
  puts "\nCounts:"
  puts "  Local repos: #{report[:local_count]}"
  puts "  Remote repos: #{report[:remote_count]}"
  puts "\nSync Status:"
  puts "  Up to date: #{report[:up_to_date]}"
  puts "  Behind: #{report[:behind]}"
  puts "  Ahead: #{report[:ahead]}"
  puts "  Diverged: #{report[:diverged]}"
  puts "\nLocal Changes:"
  puts "  Repos with uncommitted changes: #{report[:with_changes]}"
  
  report
end

# Example 3: Find repositories not pushed in X days
def find_stale_repos(days = 30)
  manager = GitHubRepoManager.new
  manager.send(:fetch_remote_repos)
  
  remote_repos = manager.instance_variable_get(:@remote_repos)
  cutoff = Time.now - (days * 86400)
  
  stale = remote_repos.select { |r| r[:pushed_at] < cutoff }
  
  puts "\n=== Repositories not updated in #{days} days ==="
  stale.each do |repo|
    days_ago = ((Time.now - repo[:pushed_at]) / 86400).to_i
    puts "  #{repo[:name]} - #{days_ago} days ago"
  end
  
  stale
end

# Example 4: Bulk clone missing repositories
def clone_missing_repos(target_dir = File.expand_path('~/code'))
  manager = GitHubRepoManager.new
  manager.send(:scan_local_repos)
  manager.send(:fetch_remote_repos)
  
  local_repos = manager.instance_variable_get(:@local_repos)
  remote_repos = manager.instance_variable_get(:@remote_repos)
  
  local_names = local_repos.map { |r| r[:remote_name] || r[:name] }
  missing = remote_repos.reject { |r| local_names.include?(r[:name]) }
  
  puts "\n=== Missing Repositories ==="
  puts "Found #{missing.size} repositories not cloned locally"
  
  missing.each do |repo|
    next if repo[:archived] # Skip archived repos
    
    repo_path = File.join(target_dir, repo[:name])
    puts "\nCloning #{repo[:name]}..."
    
    if system("git clone #{repo[:clone_url]} #{repo_path}")
      puts "  ✓ Cloned successfully"
    else
      puts "  ✗ Clone failed"
    end
  end
end

# Example 5: Export repository data to JSON
def export_to_json(output_file = 'repo-status.json')
  require 'json'
  
  manager = GitHubRepoManager.new
  manager.send(:scan_local_repos)
  manager.send(:fetch_remote_repos)
  
  data = {
    exported_at: Time.now,
    local_repos: manager.instance_variable_get(:@local_repos),
    remote_repos: manager.instance_variable_get(:@remote_repos)
  }
  
  File.write(output_file, JSON.pretty_generate(data))
  puts "\n✓ Exported to #{output_file}"
end

# Run examples if called directly
if __FILE__ == $PROGRAM_NAME
  puts "GitHub Repository Manager - Examples"
  puts "====================================="
  
  choice = ARGV[0]
  
  case choice
  when 'update'
    auto_update_all_behind
  when 'report'
    generate_status_report
  when 'stale'
    days = ARGV[1]&.to_i || 30
    find_stale_repos(days)
  when 'clone'
    target = ARGV[1] || File.expand_path('~/code')
    clone_missing_repos(target)
  when 'export'
    output = ARGV[1] || 'repo-status.json'
    export_to_json(output)
  else
    puts "\nUsage:"
    puts "  ruby examples.rb update           # Auto-update all behind repos"
    puts "  ruby examples.rb report           # Generate status report"
    puts "  ruby examples.rb stale [days]     # Find repos not updated in X days"
    puts "  ruby examples.rb clone [dir]      # Clone missing repos to directory"
    puts "  ruby examples.rb export [file]    # Export data to JSON"
  end
end
