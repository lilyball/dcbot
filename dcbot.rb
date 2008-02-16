#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require './runloop'
require './config'
require './dcppsocket'
require './plugin'
require 'pp'

SLEEP_TABLE = [1, 2, 5, 15, 30, 60, 120, 300, 600, 1200, 1800]

def main
  # parse args
  config_file = "dcbot.conf"
  OptionParser.new do |opts|
    opts.banner = "Usage: dcbot.rb [options]"
    
    opts.on("--config filename", "Use filename as the config file", "[default: dcbot.conf]") do |filename|
      config_file = filename
    end
  end.parse!
  
  config = IniReader.read(config_file)
  
  connections = config.select { |section| section[0] == "connection" }
  # FIXME: use all config sections
  connection = connections[0][1]
  host = connection["host"]
  port = connection["port"]
  nickname = connection["nickname"]
  
  if connection.has_key? "prefix" then
    PluginBase.cmd_prefix = connection["prefix"]
  end
  
  catch :quit do
    sleepIdx = 0
    while true
      # if runConnection exits instead of throwing :quit
      # then the connection was closed
      # if we can't reconnect, increase our sleep time before reconnect attempts
      if !runConnection(host, port, nickname) then
        STDERR.puts "Connection refused"
        sleepTime = SLEEP_TABLE[sleepIdx]
        STDERR.puts "Sleeping for #{sleepTime} seconds"
        sleep sleepTime
        sleepIdx += 1 unless sleepIdx == SLEEP_TABLE.size - 1
      else
        sleepIdx = 0
        STDERR.puts "Connection closed"
      end
    end
  end
  STDERR.puts "Shutting Down"
end

def runConnection(host, port, nickname)
  begin
    STDERR.puts "Connecting to #{host}:#{port} as #{nickname}"
    socket = DCPPSocket.new(host, port, nickname)
  rescue StandardError
    return false
  end
  
  STDERR.puts "Connected"
  
  socket.registerMessageCallback do |sender, message, isprivate|
    puts "<#{sender}> #{message}" if isprivate or sender == "*Dtella"
    if message[0,1] == PluginBase::CMD_PREFIX then
      cmd, args = message[1..-1].split(" ", 2)
      args = "" if args.nil?
      if cmd == "reload" and isprivate then
        # special sekrit reload command
        PluginBase.loadPlugins
        socket.sendPrivateMessage(sender, "Plugins have been reloaded")
      elsif cmd == "quit" and isprivate then
        # super-sekrit quit command
        throw :quit
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
  
  socket.startRunLoop
  return true
end

main
