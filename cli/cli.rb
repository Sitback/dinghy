$LOAD_PATH << File.dirname(__FILE__)+"/thor/lib"
require 'thor'

$LOAD_PATH << File.dirname(__FILE__)

require 'dinghy.rb'
require 'dinghy/check_env'
require 'dinghy/docker'
require 'dinghy/fsevents_to_vm'
require 'dinghy/dnsdock'
require 'dinghy/preferences'
require 'dinghy/unfs'
require 'dinghy/machine'
require 'dinghy/machine/create_options'
require 'dinghy/ssh'
require 'dinghy/system'
require 'dinghy/version'

class DinghyCLI < Thor
  option :memory,
    type: :numeric,
    aliases: :m,
    desc: "virtual machine memory size (in MB) (default #{MEM_DEFAULT})"
  option :cpus,
    type: :numeric,
    aliases: :c,
    desc: "number of CPUs to allocate to the virtual machine (default #{CPU_DEFAULT})"
  option :disk,
    type: :numeric,
    aliases: :d,
    desc: "size of the virtual disk to create, in MB (default #{DISK_DEFAULT})"
  option :provider,
    aliases: :p,
    desc: "which docker-machine provider to use, 'virtualbox' or 'vmware'"
  desc "create", "create the docker-machine VM"
  def create
    if machine.created?
      $stderr.puts "The VM '#{machine.name}' already exists in docker-machine."
      $stderr.puts "Run `dinghy up` to bring up the VM, or `dinghy destroy` to delete it."
      exit(1)
    end

    create_options = (preferences[:create] || {}).merge(options)
    create_options['provider'] = machine.translate_provider(create_options['provider'])

    if create_options['provider'].nil?
      $stderr.puts("Invalid value for required option --provider. Valid values are: 'virtualbox', 'vmware'")
      exit(1)
    end

    puts "Creating the #{machine.name} VM..."
    machine.create(create_options)
    start_services
    preferences.update(create: create_options)
  end

  option :fsevents,
    type: :boolean,
    desc: "start the FS event forwarder"
  desc "up", "start the Docker VM and services"
  def up
    if machine.running?
      puts "#{machine.name} already running, restarting..."
      halt
    end

    if !machine.created?
      $stderr.puts "The VM '#{machine.name}' does not exist in docker-machine."
      $stderr.puts "Run `dinghy create` to create the VM, `dinghy help create` to see available options."
      exit(1)
    end

    puts "Starting the #{machine.name} VM..."
    start_services
  end

  desc "ssh [args...]", "ssh to the VM"
  def ssh(*args)
    ssh = Ssh.new(machine)
    if args.empty?
      ssh.exec
    else
      ssh.run(*args)
    end
  rescue Ssh::CommandFailed => e
    exit(e.exitstatus)
  end

  desc "ssh-config", "print ssh configuration for the VM"
  def ssh_config
    puts Ssh.new(machine).ssh_config
  end

  desc "status", "get VM and services status"
  def status
    puts "  VM: #{machine.status}"
    puts " NFS: #{Unfs.new(machine).status}"
    puts "FSEV: #{FseventsToVm.new(machine).status}"
    puts " DNS: #{Dnsdock.new(machine).status}"
  end

  desc "ip", "get the VM's IP address"
  def ip
    if machine.running?
      puts machine.vm_ip
    else
      $stderr.puts "The VM is not running, `dinghy up` to start"
      exit 1
    end
  end

  desc "nameserver", "get the DNS nameserver container's IP"
  def nameserver_ip
    if machine.running?
      puts Dnsdock::CONTAINER_IP
    else
      $stderr.puts "The VM is not running, `dinghy up` to start"
      exit 1
    end
  end

  desc "halt", "stop the VM and services"
  def halt
    FseventsToVm.new(machine).halt
    machine.halt
    Unfs.new(machine).halt
  end

  desc "restart", "restart the VM and services"
  def restart
    halt
    up
  end

  option :force,
    type: :boolean,
    aliases: :f,
    desc: "destroy without confirmation"
  desc "destroy", "stop and delete all traces of the VM"
  def destroy
    halt
    machine.destroy(force: options[:force])
  end

  desc "upgrade", "upgrade the boot2docker VM to the newest available"
  def upgrade
    machine.upgrade
    # restart to re-enable the dns container, etc
    restart
  end

  desc "shellinit", "returns env variables to set, should be run like $(dinghy shellinit)"
  def shellinit
    CheckEnv.new(machine).print
  end

  map "-v" => :version
  desc "version", "display dinghy version"
  def version
    puts "Dinghy #{DINGHY_VERSION}"
  end

  private

  def preferences
    @preferences ||= Preferences.load
  end

  def fsevents_disabled?
    preferences[:fsevents_disabled] == true
  end

  def machine
    @machine ||= Machine.new
  end

  def start_services
    unfs = Unfs.new(machine)
    machine.up
    unfs.up
    machine.mount(unfs)
    fsevents = options[:fsevents] || (options[:fsevents].nil? && !fsevents_disabled?)
    if fsevents
      FseventsToVm.new(machine).up
    end
    # this is hokey, but it can take a few seconds for docker daemon to be available
    # TODO: poll in a loop until the docker daemon responds
    sleep 5
    Dnsdock.new(machine).up
    CheckEnv.new(machine).run

    preferences.update(
      fsevents_disabled: !fsevents,
    )
  end
end
