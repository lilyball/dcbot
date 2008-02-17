class HelpPlugin < PluginBase
  def self.cmd_help(socket, sender, isprivate, args)
    args.strip!
    if args.blank? or not PluginBase.has_command?(args) then
      if not args.blank? then
        socket.sendPrivateMessage(sender, "Unknown command '#{args}'.")
      end
      socket.sendPrivateMessage(sender, "Available commands are:")
      PluginBase.commands.each do |cmd|
        if PluginBase.has_command_help?(cmd) then
          socket.sendPrivateMessage(sender, "  #{self.command_help(cmd)}")
        end
      end
    else
      self.send_usage(socket, sender, args)
    end
  end
  
  def self.cmd_help_help
    [nil, "Displays this help"]
  end
  
  def self.cmd_about(socket, sender, isprivate, args)
    about = <<EOF
I am a Direct Connect bot written in Ruby.
I was written by Kevin Ballard <kevin@sb.org>.
My code is available at http://repo.or.cz/w/dcbot.git
EOF
    about.split("\n").each do |line|
      socket.sendPrivateMessage(sender, line)
    end
  end
  
  def self.cmd_about_help
    [nil, "Displays information about this bot"]
  end
  
  def self.command_help(cmd)
    message = "#{CMD_PREFIX}#{cmd}"
    if PluginBase.has_command_help?(cmd) then
      arghelp, cmdhelp = PluginBase.command_help(cmd).call()
      message << " #{arghelp}" unless arghelp.nil? or arghelp.empty?
      message << " - #{cmdhelp}"
    end
    message
  end
  
  def self.send_usage(socket, user, cmd)
    socket.sendPrivateMessage(user, "Usage: #{self.command_help(cmd)}")
  end
end
