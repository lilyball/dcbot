#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'eventmachine'
require './config'
require './dcprotocol'
require './keyboard'
require './plugin'
require 'pp'

SLEEP_TABLE = [1, 2, 5, 15, 30, 60, 120, 300]

def main
  # parse args
  options = {}
  options[:config_file] = "dcbot.conf"
  OptionParser.new do |opts|
    opts.banner = "Usage: dcbot.rb [options]"
    
    opts.on("--config filename", "Use filename as the config file", "[default: dcbot.conf]") do |filename|
      options[:config_file] = filename
    end
    opts.on("--[no-]debug", "Sets the debug flag") { |flag| options[:debug] = flag }
  end.parse!
  
  config = IniReader.read(options[:config_file])
  
  global_config = config.find { |section| section[0] == "global" }
  if options.has_key? :debug then
    $debug = options[:debug]
  elsif global_config and global_config[1].has_key? "debug" then
    debug = global_config[1]["debug"].downcase
    if debug == "true" then
      $debug = true
    else
      $debug = false
    end
  end
  
  connections = config.select { |section| section[0] == "connection" }
  # FIXME: use all config sections
  connection = connections[0][1]
  host = connection["host"]
  port = connection["port"].to_i
  nickname = connection["nickname"]
  description = connection["description"]
  
  if connection.has_key? "prefix" then
    PluginBase.cmd_prefix = connection["prefix"]
  end
  
  EventMachine::run do
    EventMachine::open_keyboard KeyboardInput
    setupConnection(host, port, nickname, description, 0)
  end
  STDERR.puts "Shutting Down"
end

def setupConnection(host, port, nickname, description, sleep)
  $socket = DCClientProtocol.connect(host, port, nickname, :description => description, :debug => $debug) do |c|
    c.registerCallback :message do |socket, sender, message, isprivate|
      if isprivate or sender == "*Dtella" then
        puts "<#{sender}> #{message}"
      end
      if message[0,1] == PluginBase::CMD_PREFIX then
        cmd, args = message[1..-1].split(" ", 2)
        args = "" if args.nil?
        if cmd == "reload" and isprivate then
          # special sekrit reload command
          PluginBase.loadPlugins
          socket.sendPrivateMessage(sender, "Plugins have been reloaded")
        elsif cmd == "quit" and isprivate then
          # super-sekrit quit command
          socket.close
        elsif PluginBase.has_command?(cmd) then
          begin
            PluginBase.dispatch(socket, cmd, sender, isprivate, args)
          rescue StandardError => e
            socket.sendPrivateMessage(sender, "An error occurred executing your command: #{e.to_s}")
            STDERR.puts "ERROR: #{e.to_s}"
            PP.pp(e.backtrace, STDERR)
          end
        elsif isprivate then
          socket.sendPrivateMessage(sender, "Unknown command: #{PluginBase::CMD_PREFIX}#{cmd}")
        end
      end
    end
    c.registerCallback :unbind do |socket|
      if c.quit then
        # this is our only socket for the moment
        EventMachine.stop_event_loop
      else
        EventMachine::add_timer(SLEEP_TABLE[sleep]) do
          sleep += 1 unless sleep == SLEEP_TABLE.size - 1
          setupConnection(host, port, nickname, description, sleep)
        end
      end
    end
    c.registerCallback :connected do |socket|
      puts "Connected"
      socket.registerCallback :unbind do |socket|
        if c.quit then
          # this is our only socket for the moment
          EventMachine.stop_event_loop
        else
          setupConnection(host, port, nickname, description, 0)
        end
      end
    end
  end
end

main
