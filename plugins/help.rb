class HelpPlugin < PluginBase
  def self.cmd_help(socket, sender, isprivate, args)
    socket.sendPrivateMessage(sender, "Available commands are:")
    PluginBase.commands.each do |cmd|
      message = "#{CMD_PREFIX}#{cmd}"
      if PluginBase.has_command_help?(cmd) then
        arghelp, cmdhelp = PluginBase.command_help(cmd).call()
        message << " #{arghelp}" unless arghelp.nil? or arghelp.empty?
        message << " - #{cmdhelp}"
        socket.sendPrivateMessage(sender, "  #{message}")
      end
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
end
