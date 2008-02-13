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
end
