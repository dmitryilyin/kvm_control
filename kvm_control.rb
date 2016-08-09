#!/usr/bin/env ruby

require 'optparse'
require 'yaml'
require 'open3'
require 'securerandom'

# Libvirt API interface functions
module LibVirt

  # Delete a domain by it's name
  # @param [String] domain_name
  def domain_delete(domain_name)
    commands = [
        'virsh',
        'undefine',
        domain_name,
    ]
    debug "Domain delete: #{commands.join ' '}"
    _output, success = run commands
    error "Failed to delete domain: #{domain_name}" unless success
    success
  end

  # Start a domain by it's name
  # @param [String] domain_name
  def domain_start(domain_name)
    commands = [
        'virsh',
        'start',
        domain_name,
    ]
    debug "Domain start: #{commands.join ' '}"
    _output, success = run commands
    warning "Failed to start domain: #{domain_name}" unless success
    success
  end

  # Set autostart for a domain by it's name
  # @param [String] domain_name
  def domain_autostart(domain_name)
    commands = [
        'virsh',
        'autostart',
        domain_name,
    ]
    debug "Domain autostart: #{commands.join ' '}"
    _output, success = run commands
    warning "Failed to autostart domain: #{domain_name}" unless success
    success
  end

  # Unset autostart for a domain by it's name
  # @param [String] domain_name
  def domain_no_autostart(domain_name)
    commands = [
        'virsh',
        '--disable',
        'autostart',
        domain_name,
    ]
    debug "Domain no autostart: #{commands.join ' '}"
    _output, success = run commands
    warning "Failed to stop autostart domain: #{domain_name}" unless success
    success
  end

  # Stop a domain by it's name
  # @param [String] domain_name
  def domain_stop(domain_name)
    commands = [
        'virsh',
        'destroy',
        domain_name,
    ]
    debug "Domain stop: #{commands.join ' '}"
    _output, success = run commands
    warning "Failed to stop domain: #{domain_name}" unless success
    success
  end

  # Get a list of all defined domains, states and ids (if running)
  # @return [Hash<String => Hash>]
  def domain_list
    command = %w(virsh list --all)
    domains = {}
    output, success = run command
    error 'Failed to get domain list! Is you libvirt service running?' unless success
    output.split("\n").each do |line|
      line_array = line.split
      id = line_array[0]
      name = line_array[1]
      state = line_array[2..-1]
      next unless id and name and state
      id = id.chomp.strip
      name = name.chomp.strip
      state = state.join(' ').chomp.strip
      next if id == 'Id'
      domain_hash = {}
      domain_hash['state'] = state
      domain_hash['id'] = id unless id == '-'
      domains[name] = domain_hash
    end
    domains
  end

  # Check if a domain is started for it's name
  # @param [String] domain_name
  # @return [true,false]
  def domain_started?(domain_name)
    domain_state(domain_name) == 'running'
  end

  # Get a state of a domain by it's name
  # @param [String] domain_name
  # @return [String]
  def domain_state(domain_name)
    domain_attributes = domain_list.fetch domain_name, {}
    domain_attributes.fetch 'state', 'missing'
  end

  # Check if a domain is defined by it's name
  # @param [String] domain_name
  # @return [true,false]
  def domain_defined?(domain_name)
    domain_list.key? domain_name
  end

  # Create a new libvirt volume if a pool
  # @param [String] volume_name
  # @param [String] virt_type
  # @param [String,Numeric] volume_size
  # @return [true,false] success?
  def volume_create(volume_name, virt_type, volume_size)
    commands = [
        'virsh',
        'vol-create-as',
        virt_type,
        volume_name,
        volume_size,
    ]

    debug "Volume create: #{commands.join ' '}"
    _output, success = run commands
    error "Failed to create volume: #{volume_name}" unless success
    success
  end

  # Get a path of a volume in a pool by it's name
  # Returns nil if there is no such volume
  # @param [String] volume_name
  # @param [String] pool_name
  # @return [String,nil]
  def volume_path(volume_name, pool_name)
    volume_list(pool_name).fetch(volume_name, nil)
  end

  # Delete a volume in a pool by its name
  # @param [String] volume_name
  # @param [String] pool_name
  # @return [true,false] success?
  def volume_delete(volume_name, pool_name)
    commands = [
        'virsh',
        'vol-delete',
        '--pool', pool_name,
        volume_name
    ]
    debug "Delete volume: #{commands.join ' '}"
    _output, success = run commands
    error "Failed to delete volume: #{volume_name}" unless success
    success
  end

  # List all volumes in a pool
  # @param [String] pool_name
  # @return [Hash<String => String>] Volume name and path
  def volume_list(pool_name)
    commands = [
        'virsh',
        'vol-list',
        '--pool', pool_name,
    ]
    output, success = run commands
    error "Failed to get volume list of pool: #{pool_name}!" unless success
    volumes = {}
    output.split("\n").each do |line|
      line_array = line.split
      name = line_array[0]
      path = line_array[1]
      next unless name and path
      name = name.chomp.strip
      path = path.chomp.strip
      next if name == 'Name'
      volumes[name] = path
    end
    volumes
  end

  # Check if a volume in a pool is defined
  # @param [String] volume_name
  # @param [String] pool_name
  # @return [true,false]
  def volume_defined?(volume_name, pool_name)
    volume_list(pool_name).key? volume_name
  end

  # Generate a new serial for a disk
  # @return [String]
  def generate_disk_serial
    ::SecureRandom.uuid
  end

  # Create a new domain using it's attributes structure
  # @param [String] domain_name
  # @param [Hash] domain_attributes
  # @return [true,false] success?
  def domain_create(domain_name, domain_attributes)
    name = domain_attributes.fetch 'name', domain_name
    fail 'There is no domain name!' unless name
    ram = domain_attributes.fetch 'ram', '1024'
    cpu = domain_attributes.fetch 'cpu', '2'
    volumes = domain_attributes.fetch 'volumes', {}
    networks = domain_attributes.fetch 'networks', {}

    commands = [
        'virt-install',
        '--name', name,
        '--ram', ram,
        '--vcpus', "#{cpu},cores=#{cpu}",
        '--os-type', 'linux',
        '--virt-type', options[:virt],
        '--pxe',
        '--boot', 'network,hd',
        '--noautoconsole',
        '--graphics', 'vnc,listen=0.0.0.0',
        '--autostart',
    ]

    volumes.each do |volume|
      volume['serial'] = generate_disk_serial unless volume['serial']
      volume['cache'] = 'none' unless volume['cache']
      volume['bus'] = 'virtio' unless volume['bus']

      unless volume['path']
        warning "Volume: #{volume.inspect} has no path defined! Skipping!"
        next
      end

      disk_string = volume.reject do |attribute_name, _attribute_value|
        %w(size name).include? attribute_name
      end.map do |attribute_name, attribute_value|
        "#{attribute_name}=#{attribute_value}"
      end.join ','

      commands += ['--disk', disk_string]
    end

    networks.each do |network|
      network['model'] = 'virtio' unless network['model']

      unless network['network']
        warning "Network: #{network.inspect} has no 'network' defined! Skipping!"
        next
      end

      network_string = network.map do |attribute_name, attribute_value|
        "#{attribute_name}=#{attribute_value}"
      end.join ','

      commands += ['--network', network_string]
    end

    debug "Domain create: #{commands.join ' '}"
    _output, success = run commands
    error "Failed to create the domain: #{name}" unless success
    success
  end
end

# Configuration and settings related functions
module Configuration

  # The structure describing the domains to manage
  # @return [Hash]
  def domain_settings
    error "There is no YAML file: #{options[:yaml]}" unless File.exists? options[:yaml]
    begin
      data = YAML.load_file options[:yaml]
    rescue => exception
      error "Could not read YAML file: #{options[:yaml]}: #{exception}"
    end
    error "Data format of YAML file: #{options[:yaml]} is incorrect!" unless data.is_a? Array
    data
  end

  # Console options structure
  # @return [Hash]
  def options
    return @options if @options
    @options = {}

    OptionParser.new do |opts|
      opts.banner = 'kvm_control [options] (domain)'

      opts.on('-D', '--delete', 'Delete the created domains and volumes') do
        @options[:delete] = true
      end

      opts.on('-R', '--recreate', 'Delete and create the domains and volumes') do
        @options[:recreate] = true
      end

      opts.on('-s', '--stop', 'Stop all created domains') do
        @options[:stop] = true
      end

      opts.on('-r', '--start', 'Start all created domains') do
        @options[:start] = true
      end

      opts.on('-l', '--list', 'List the domains and volumes') do
        @options[:list] = true
        @options[:all] = true
      end

      opts.on('-c', '--config', 'Show the requested configuration of the domains and volumes') do
        @options[:config] = true
      end

      opts.on('-a', '--all', 'Process all domains') do
        @options[:all] = true
      end

      opts.on('-d', '--debug', 'Show debug messages') do
        @options[:debug] = true
      end

      opts.on('-C', '--console', 'Run the debug console') do
        @options[:debug] = true
        @options[:console] = true
      end

      opts.on('-y', '--yaml FILE', 'Settings YAML file') do |value|
        @options[:yaml] = value
      end

      opts.on('-q', '--qemu', 'Use QEMU instead of KVM') do
        @options[:virt] = 'qemu'
      end

      opts.on('-p', '--pool POOL', 'The name of the libvirt storage pool') do |value|
        @options[:pool] = value
      end

    end.parse!

    @options
  end

  def munge_options
    return unless options.is_a? Hash
    options[:yaml] = '/etc/kvm_hosts.yaml' unless options[:yaml]
    options[:pool] = 'default' unless options[:pool]
    options[:virt] = 'kvm' unless options[:virt]
    options[:hosts] = ARGV.compact.uniq
    
    unless options[:all] or (options[:hosts] and options[:hosts].any?)
      error "You have to provided any hosts names to work with.
             Please, give obne or more host name or use '-a' to work on all defined hosts!
             Defined hosts: #{domain_names.join ', '}"
    end
    debug "Options: #{options.inspect}"
  end

end

# Main KVM control logic class
class KvmControl
  attr_writer :options
  include Configuration
  include LibVirt

  # The filtered list of domains
  # It should contain only the domains from the command line
  # or all domains if the "-a" is set.
  def domains
    domain_settings.select do |domain|
      options[:all] or options[:hosts].include? domain['name']
    end
  end

  # Get an array of defined domain names
  # @return [Array<Staring>]
  def domain_names
    domain_settings.map do |domain|
      domain['name']
    end.compact.uniq
  end

  # Run the debug console
  def console
    require 'pry'
    binding.pry
    exit(0)
  end

  # Show the configuration
  def show_config
    info YAML.dump domains
    exit(0)
  end

  # The 'list' action
  # Lists all domains and their statuses
  def action_list
    domain_statuses = domain_list
    max_length = domain_names.max_by { |d| d.length }.length

    domain_names.each do |domain_name|
      domain_attributes = domain_statuses.fetch(domain_name, {})
      domain_state = domain_attributes.fetch 'state', 'missing'
      info "#{domain_name.ljust max_length} - #{domain_state}"
    end
    exit(0)
  end

  # The 'delete' action
  # Stops domains and deletes volumes and domains
  def action_delete
    domains_stop
    domains_delete
    volumes_delete
  end

  # The 'create action'
  # Creates volumes and domains,
  # starts domains and marks them for autostart
  def action_create
    volumes_create
    domains_create
    domains_start
    domains_autostart
  end

  # The 'recreate' action
  # Calls 'delete' and 'create' actions
  def action_recreate
    action_delete
    action_create
  end

  # The 'stop' action
  # Stop all domains in the working set
  def action_stop
    domains_stop
  end

  # The 'start' action
  # Start all domains in the working set
  def action_start
    domains_start
  end

  # Create all domains in the working set
  def domains_create
    debug 'Call: domains_create'
    domains.each do |domain|
      domain_name = domain.fetch 'name'
      next unless domain_name
      if domain_defined? domain_name
        warning "Domain: #{domain_name} is already defined! Skipping!"
        next
      end
      resolve_volume_paths domain['volumes']
      domain_create domain_name, domain
    end
  end

  # Resolve the path of a libvirt volumes by their names
  # If volume has a path already defined it will be skipped
  # @param [Array] volumes
  def resolve_volume_paths(volumes)
    return unless volumes.is_a? Array
    volumes.each do |volume|
      next if volume['path']
      volume['path'] = volume_path volume['name'], options[:pool]
    end
  end

  # Create volumes for the domains in the working set
  def volumes_create
    domains.each do |domain|
      volumes = domain.fetch 'volumes', {}
      volumes.each do |volume|
        volume_size = volume.fetch 'size'
        volume_name = volume.fetch 'name'
        next unless volume_name and volume_size
        if volume_defined? volume_name, options[:pool]
          warning "Volume: #{volume_name} of the pool: #{options[:pool]} is already created! Skipping!"
          next
        end
        if volume['path']
          info "Volume: #{volume_name} has a path already defined. Assuming it's already created!"
          next
        end
        volume_create volume_name, options[:pool], volume_size
      end
    end
  end

  # Delete all volumes of domains in the working set
  def volumes_delete
    debug 'Call: volumes_delete'
    domains.each do |domain|
      volumes = domain.fetch 'volumes', {}
      volumes.each do |volume|
        volume_name = volume.fetch 'name'
        next unless volume_name
        unless volume_defined? volume_name, options[:pool]
          info "Volume: #{volume_name} of the pool: #{options[:pool]} is not defined! Skipping!"
          next
        end
        volume_delete volume_name, options[:pool]
      end
    end
  end

  # Delete all domains in the working set
  def domains_delete
    debug 'Call: domains_delete'
    domains.each do |domain|
      domain_name = domain.fetch 'name'
      next unless domain_name
      unless domain_defined? domain_name
        warning "Domain: #{domain_name} is not defined! Skipping!"
        next
      end
      domain_delete domain_name
    end
  end

  # Start all domains in the working set
  def domains_start
    debug 'Call: domains_start'
    domains.each do |domain|
      domain_name = domain.fetch 'name'
      next unless domain_name
      unless domain_defined? domain_name
        warning "Domain: #{domain_name} is not defined! Skipping!"
        next
      end
      if domain_started? domain_name
        warning "Domain: #{domain_name} is already started! Skipping!"
        next
      end
      domain_start domain_name
    end
  end

  # Unset autostart mark from all domain in the working set
  def domains_no_autostart
    debug 'Call: domains_no_autostart'
    domains.each do |domain|
      domain_name = domain.fetch 'name'
      next unless domain_name
      unless domain_defined? domain_name
        warning "Domain: #{domain_name} is not defined! Skipping!"
        next
      end
      domain_no_autostart domain_name
    end
  end

  # Mark all domains in the working set for autostart
  def domains_autostart
    debug 'Call: domains_autostart'
    domains.each do |domain|
      domain_name = domain.fetch 'name'
      next unless domain_name
      unless domain_defined? domain_name
        warning "Domain: #{domain_name} is not defined! Skipping!"
        next
      end
      domain_autostart domain_name
    end
  end

  # Stop all domains in the working set
  def domains_stop
    debug 'Call: domains_stop'
    domains.each do |domain|
      domain_name = domain.fetch 'name'
      next unless domain_name
      unless domain_defined? domain_name
        warning "Domain: #{domain_name} is not defined! Skipping!"
        next
      end
      unless domain_started? domain_name
        warning "Domain: #{domain_name} is not started! Skipping!"
        next
      end
      domain_stop domain_name
    end
  end

  # Run the command
  # @param [Array] commands
  # @return [Array] Array of stdout and success boolean value
  def run(*commands)
    commands.flatten!
    commands.map!(&:to_s)
    out, status = Open3.capture2 *commands
    [out, status.exitstatus == 0]
  end

  def debug(message)
    $stdout.puts message if options[:debug]
  end

  def warning(message)
    $stdout.puts "WARNING: #{message}"
  end

  def info(message)
    $stdout.puts message
  end

  def error(message)
    $stderr.puts "ERROR: #{message}"
    exit(0)
  end

  # The main function
  def main
    munge_options

    if options[:console]
      console
      exit(0)
    end

    if options[:config]
      show_config
      exit(0)
    end

    if options[:list]
      action_list
    end

    if options[:delete]
      action_delete
      exit(0)
    end

    if options[:recreate]
      action_recreate
      exit(0)
    end

    if options[:stop]
      action_stop
      exit(0)
    end

    if options[:start]
      action_start
      exit(0)
    end

    action_create
  end
end

if $0 == __FILE__
  kvm_control = KvmControl.new
  kvm_control.main
end


