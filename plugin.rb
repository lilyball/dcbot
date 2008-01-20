require 'activerecord'

class PluginBase
  @@plugins = []
  @@pluginWrapper = nil
  CMD_PREFIX = "!"
  
  def self.inherited(subclass)
    @@plugins << subclass
  end
  
  def self.commands
    @@plugins.map { |plugin| plugin.methods.grep(/^cmd_[a-zA-Z]+$/).map { |cmd| cmd.sub(/^cmd_/, "") } }.flatten
  end
  
  def self.has_command?(cmd)
    self.commands.include? cmd
  end
  
  def self.has_command_help?(cmd)
    @@plugins.any? { |plugin| plugin.methods.include? "cmd_#{cmd}_help"}
  end
  
  def self.command_help(cmd)
    @@plugins.each do |plugin|
      meth = plugin.methods.grep("cmd_#{cmd}_help").first
      return plugin.method(meth) unless meth.nil?
    end
  end
  
  def self.dispatch(socket, cmd, sender, isprivate, args)
    @@plugins.each do |plugin|
      if plugin.methods.include? "cmd_#{cmd}" then
        begin
          begin
            plugin.method("cmd_#{cmd}").call(socket, sender, isprivate, args)
          rescue Mysql::Error => e
            STDERR.puts "Mysql exception raised executing command:\n#{e.to_s}"
            # try one more time
            socket.sendPrivateMessage("An error occurred executing your command. Retrying...")
            self.initdb
            plugin.method("cmd_#{cmd}").call(socket, sender, isprivate, args)
          end
        rescue StandardError => e
          STDERR.puts "An exception was raised executing cmd_#{cmd}:\n#{e.to_s}"
          socket.sendPrivateMessage("An error occurred: #{e.to_s}")
        end
      end
    end
  end
  
  def self.loadPlugins
    @@plugins = []
    @@pluginWrapper = Module.new
    Dir["plugins/*"].each do |file|
      begin
        @@pluginWrapper.class_eval File.read(file), file
      rescue StandardError, ScriptError => e
        STDERR.puts "Error loading plugin `#{file}': #{e.to_s}"
      end
    end
  end
  
  def self.initdb
    ActiveRecord::Base.establish_connection(
      :adapter => "mysql",
      :host => "localhost",
      :username => "dcbot",
      :database => "40thieves")
  end
end

PluginBase.initdb
PluginBase.loadPlugins
