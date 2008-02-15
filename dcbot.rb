#!/usr/bin/env ruby

require 'rubygems'
require './runloop'
require './dcppsocket'
require './plugin'
require 'pp'

HOSTNAME = '127.0.0.1'
PORT = 7315
NICKNAME = 'RequestBot'

SLEEP_TABLE = [1, 2, 5, 15, 30, 60, 120, 300, 600, 1200, 1800]

def main
  catch :quit do
    sleepIdx = 0
    while true
      # if runConnection exits instead of throwing :quit
      # then the connection was closed
      # if we can't reconnect, increase our sleep time before reconnect attempts
      if !runConnection then
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

def runConnection
  begin
    socket = DCPPSocket.new(HOSTNAME, PORT, NICKNAME)
  rescue StandardError
    return false
  end
  
  STDERR.puts "Connected"
  
  socket.registerMessageCallback do |sender, message, isprivate|
    puts "<#{sender}> #{message}" if isprivate
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
