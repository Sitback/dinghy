class Ssh
  attr_reader :machine

  class CommandFailed < RuntimeError
    attr_reader :exitstatus
    def initialize(message, exitstatus)
      super(message)
      @exitstatus = exitstatus
    end
  end

  def initialize(machine)
    @machine = machine
  end

  def write_ssh_config!
    File.open(ssh_config_path, 'wb') { |f| f.write(ssh_config) }
  end

  def run(*command)
    system("ssh", "-F", ssh_config_path.to_s, "dinghy", "--", *command)
    if command_failed?
      raise CommandFailed.new("Error executing command: #{command}", $?.exitstatus)
    end
  end

  def exec
    Kernel.exec("ssh", "-F", ssh_config_path.to_s, "dinghy")
  end

  def ssh_config
    # Constructing the IdentityFile path ourselves is a recipe for future
    # sadness, but I haven't found a way to get it out of docker-machine.
    <<-SSH
Host dinghy
  HostName #{machine.vm_ip}
  User docker
  Port 22
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile #{machine.store_path}/id_rsa
  IdentitiesOnly yes
  LogLevel ERROR
    SSH
  end

  protected

  def ssh_config_path
    # this is hard-coded inside the fsevents_to_vm plist, as well
    HOME_DINGHY+"ssh-config"
  end

  def command_failed?
    !$?.success?
  end
end