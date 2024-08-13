#!/usr/bin/env ruby

require 'fileutils'
require 'fcntl'
require 'io/console'
require 'open3'
require 'pathname'
require 'socket'

# Define constants globally
LOG_ERROR = 1
LOG_WARN = 2
LOG_INFO = 3
LOG_DEBUG = 4

LOG_CONSTANTS = { "LOG_ERROR" => LOG_ERROR, "LOG_WARN" => LOG_WARN, "LOG_INFO" => LOG_INFO, "LOG_DEBUG" => LOG_DEBUG }

def should_print(config, loglevel)
  verbosity = config.get('VERBOSITY')
  verbosity = LOG_CONSTANTS[verbosity] if verbosity.is_a?(String) && LOG_CONSTANTS.key?(verbosity)
  verbosity = verbosity.to_i if verbosity.is_a?(String)
  loglevel <= verbosity
end

class SshIdentPrint
  def initialize(config)
    @config = config
  end

  def write(*args, loglevel: LOG_INFO, **kwargs)
    return if @config.get('SSH_BATCH_MODE')

    if should_print(@config, loglevel)
      puts(*args)
    end
  end

  alias call write
end

class Config
  DEFAULTS = {
    'FILE_USER_CONFIG' => "#{Dir.home}/.ssh-ident",
    'DIR_IDENTITIES' => "#{Dir.home}/.ssh/identities",
    'DIR_AGENTS' => "#{Dir.home}/.ssh/agents",
    'PATTERN_KEYS' => '/(id_.*|identity.*|ssh[0-9]-.*)',
    'PATTERN_CONFIG' => '/config$',
    'SSH_OPTIONS' => {},
    'SSH_DEFAULT_OPTIONS' => '-oUseRoaming=no',
    'BINARY_SSH' => nil,
    'BINARY_DIR' => nil,
    'DEFAULT_IDENTITY' => ENV['USER'],
    'MATCH_PATH' => [],
    'MATCH_ARGV' => [],
    'SSH_ADD_OPTIONS' => {},
    'SSH_ADD_DEFAULT_OPTIONS' => '-t 7200',
    'SSH_BATCH_MODE' => false,
    'VERBOSITY' => LOG_INFO
  }

  def initialize
    @values = {}
  end

  def load
    path = get('FILE_USER_CONFIG', required: false)
    return self unless path && File.exist?(path)

    begin
      @values = eval(File.read(path))
    rescue Errno::ENOENT
      return self
    end
    self
  end

  def self.expand(value)
    return unless value.is_a?(String)

    File.expand_path(value.gsub('$HOME', Dir.home))
  end

  def get(parameter, required: true)
    value = ENV[parameter] || @values[parameter] || DEFAULTS[parameter]
    if required && !value
      raise "Parameter '#{parameter}' needs to be defined in config file or defaults"
    end

    self.class.expand(value)
  end

  def set(parameter, value)
    @values[parameter] = value
  end
end

def find_identity_in_list(elements, identities)
  elements.each do |element|
    identities.each do |regex, identity|
      return identity if Regexp.new(regex).match?(element)
    end
  end
  nil
end

def find_identity(argv, config)
  paths = [Dir.pwd, File.expand_path(Dir.pwd), File.realpath(Dir.pwd)]
  find_identity_in_list(argv, config.get('MATCH_ARGV')) ||
    find_identity_in_list(paths, config.get('MATCH_PATH')) ||
    config.get('DEFAULT_IDENTITY')
end

def find_keys(identity, config)
  directories = [File.join(config.get('DIR_IDENTITIES'), identity)]
  directories << "#{Dir.home}/.ssh" if identity == ENV['USER']

  pattern = Regexp.new(config.get('PATTERN_KEYS'))
  found = {}

  directories.each do |directory|
    next unless File.directory?(directory)

    Dir.each_child(directory) do |key|
      key_path = File.join(directory, key)
      next unless File.file?(key_path)
      next unless pattern.match?(key_path)

      kinds = { 'private' => 'priv', 'public' => 'pub', '.pub' => 'pub', '' => 'priv' }
      kinds.each do |match, kind|
        if key_path.include?(match)
          found[key_path.gsub(match, '')] ||= {}
          found[key_path.gsub(match, '')][kind] = key_path
        end
      end
    end
  end

  if found.empty?
    warn "Warning: no keys found for identity #{identity} in:"
    warn directories
  end

  found
end

def find_ssh_config(identity, config)
  directory = File.join(config.get('DIR_IDENTITIES'), identity)
  pattern = Regexp.new(config.get('PATTERN_CONFIG'))

  return unless File.directory?(directory)

  Dir.each_child(directory) do |sshconfig|
    sshconfig_path = File.join(directory, sshconfig)
    return sshconfig_path if File.file?(sshconfig_path) && pattern.match?(sshconfig_path)
  end
  nil
end

def get_session_tty
  begin
    fd = File.open('/dev/tty', 'r')
    fd.ioctl(Termios::TIOCGPGRP)
  rescue Errno::EIO
    return nil
  end
  fd
end

class AgentManager
  def initialize(identity, sshconfig, config)
    @identity = identity
    @config = config
    @ssh_config = sshconfig
    @agents_path = File.absolute_path(config.get('DIR_AGENTS'))
    @agent_file = self.class.get_agent_file(@agents_path, @identity)
  end

  def load_unloaded_keys(keys)
    toload = find_unloaded_keys(keys)
    if toload.any?
      puts "Loading keys:\n    #{toload.join("\n    ")}"
      load_key_files(toload)
    else
      puts "All keys already loaded"
    end
  end

  def find_unloaded_keys(keys)
    loaded = get_loaded_keys
    toload = []
    keys.each do |key, config|
      next unless config['pub'] && config['priv']

      fingerprint = self.class.get_public_key_fingerprint(config['pub'])
      toload << config['priv'] unless loaded.include?(fingerprint)
    end
    toload
  end

  def load_key_files(keys)
    options = @config.get('SSH_ADD_OPTIONS')[@identity] || @config.get('SSH_ADD_DEFAULT_OPTIONS')
    console = get_session_tty
    self.class.run_shell_command_in_agent(@agent_file, "ssh-add #{options} #{keys.join(' ')}", stdin: console, stdout: console)
  end

  def get_loaded_keys
    retval, stdout = self.class.run_shell_command_in_agent(@agent_file, 'ssh-add -l')
    return [] if retval != 0

    stdout.lines.map do |line|
      line.split(' ')[1]
    end.compact
  end

  def self.get_public_key_fingerprint(key)
    retval, stdout = run_shell_command("ssh-keygen -l -f #{key} | tr -s ' '")
    return nil if retval != 0

    stdout.split(' ')[1]
  end

  def self.get_agent_file(path, identity)
    FileUtils.mkdir_p(path, mode: 0o700)
    agentfile = File.join(path, "agent-#{identity}-#{Socket.gethostname}")
    if File.readable?(agentfile) && is_agent_file_valid(agentfile)
      puts "Agent for identity #{identity} ready"
      return agentfile
    end

    puts "Preparing new agent for identity #{identity}"
    system("/usr/bin/env -i /bin/sh -c 'ssh-agent > #{agentfile}'")
    agentfile
  end

  def self.is_agent_file_valid(agentfile)
    retval, = run_shell_command_in_agent(agentfile, 'ssh-add -l >/dev/null 2>/dev/null')
    retval & 0xff in [0, 1]
  end

  def self.run_shell_command(command)
    stdout, stderr, status = Open3.capture3(command)
    [status.exitstatus, stdout]
  end

  def self.run_shell_command_in_agent(agentfile, command, stdin: nil, stdout: nil)
    full_command = "/bin/sh -c '. #{agentfile} >/dev/null 2>/dev/null; #{command}'"
    stdout, stderr, status = Open3.capture3(full_command, stdin_data: stdin, binmode: true, stdout: stdout)
    [status.exitstatus, stdout]
  end

  def self.escape_shell_arguments(argv)
    argv.map { |arg| "'#{arg.gsub("'", "'\"'\"'")}'" }.join(' ')
  end

  def get_shell_args
    should_print(@config, LOG_DEBUG) ? '-xc' : '-c'
  end

  def run_ssh(argv)
    additional_flags = @config.get('SSH_OPTIONS')[@identity] || @config.get('SSH_DEFAULT_OPTIONS')
    additional_flags += " -F #{@ssh_config}" if @ssh_config

    command = ["/bin/sh", get_shell_args, ". #{@agent_file} >/dev/null 2>/dev/null; exec #{@config.get('BINARY_SSH')} #{additional_flags} #{self.class.escape_shell_arguments(argv)}"]
    exec("/bin/sh", *command)
  end
end

def autodetect_binary(argv, config)
  return if config.get('BINARY_SSH', required: false) # Skip if BINARY_SSH is already set

  runtime_name = argv[0]
  if config.get('BINARY_DIR', required: false)
    binary_name = File.basename(runtime_name)
    binary_path = File.join(config.get('BINARY_DIR'), binary_name)
    binary_path = File.join(config.get('BINARY_DIR'), 'ssh') unless File.file?(binary_path) && File.executable?(binary_path)
    config.set('BINARY_SSH', binary_path)
    puts "Will run '#{config.get('BINARY_SSH')}' as ssh binary - detected based on BINARY_DIR"
    return
  end

  ssh_ident_path = ''
  if File.dirname(runtime_name).empty?
    puts "argv[0] ('#{runtime_name}') is a relative path. This may result in a loop with 'ssh-ident' trying to run itself."
  else
    ssh_ident_path = File.absolute_path(File.dirname(runtime_name))
  end

  search_path = ENV['PATH'].split(File::PATH_SEPARATOR).map { |p| File.expand_path(p) }.reject { |p| p == ssh_ident_path }
  binary_path = search_path.find { |p| File.executable?(File.join(p, File.basename(runtime_name))) } || search_path.find { |p| File.executable?(File.join(p, 'ssh')) }

  if binary_path
    config.set('BINARY_SSH', binary_path)
    puts "Will run '#{config.get('BINARY_SSH')}' as ssh binary - detected from argv[0] and $PATH"
  else
    puts "ssh-ident was invoked in place of the binary '#{runtime_name}'. Neither this binary nor 'ssh' could be found in $PATH."
    exit 255
  end
end

def parse_command_line(argv, config)
  binary = File.basename(config.get('BINARY_SSH'))
  if %w[ssh scp].include?(binary)
    argv.each_with_index do |arg, index|
      argv[index + 1] = argv[index + 1].prepend(arg) if arg == '-o'
      if arg =~ /-oBatchMode[= ](yes|true)/i
        config.set('SSH_BATCH_MODE', true)
        break
      elsif arg =~ /-oBatchMode[= ](no|false)/i
        config.set('SSH_BATCH_MODE', false)
        break
      end
    end
  end
end

def main(argv)
  begin
    $stdout.reopen('/dev/tty', 'w')
    $stderr.reopen('/dev/tty', 'w')
  rescue Errno::EIO
    nil
  end

  config = Config.new.load
  ssh_ident_print = SshIdentPrint.new(config)

  autodetect_binary(argv, config)

  binary_path = File.realpath(ENV['PATH'].split(File::PATH_SEPARATOR).find { |p| File.executable?(File.join(p, File.basename(argv[0]))) })
  ssh_ident_path = File.realpath(File.expand_path(argv[0]))

  if binary_path == ssh_ident_path
    ssh_ident_print.call("ssh-ident found '#{config.get('BINARY_SSH')}' as the next command to run. Based on argv[0] ('#{argv[0]}'), it seems like this will create a loop.")
    exit 255
  end

  parse_command_line(argv, config)
  identity = find_identity(argv, config)
  keys = find_keys(identity, config)
  sshconfig = find_ssh_config(identity, config)
  agent = AgentManager.new(identity, sshconfig, config)

  agent.load_unloaded_keys(keys) unless config.get('SSH_BATCH_MODE')

  agent.run_ssh(argv[1..-1])
end

if __FILE__ == $0
  begin
    exit main(ARGV)
  rescue Interrupt
    warn "Goodbye"
  end
end

