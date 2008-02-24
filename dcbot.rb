#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'eventmachine'
require 'pp'
dir = File.dirname(__FILE__)
require "#{dir}/config"
require "#{dir}/dcprotocol"
require "#{dir}/keyboard"
require "#{dir}/plugin"

SLEEP_TABLE = [1, 2, 5, 15, 30, 60, 120, 300]

RUBYBOT_VERSION = "0.1"

DCProtocol.registerClientVersion("RubyBot", RUBYBOT_VERSION)

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
    opts.on("--[no-]peer-debug", "Sets the debug flag for peer connections") { |flag| options[:peer_debug] = flag }
  end.parse!
  
  config = IniReader.read(options[:config_file])
  
  global_config = config.find { |section| section[0] == "global" }
  debug = false
  if options.has_key? :debug then
    debug = options[:debug]
  elsif global_config and global_config[1].has_key? "debug" then
    debug = global_config[1]["debug"].downcase
    if debug == "true" then
      debug = true
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
    sockopts = { :description => description,
                 :debug => debug,
                 :peer_debug => options[:peer_debug] }
    setupConnection(host, port, nickname, sockopts, 0)
  end
  puts "Goodbye"
end

def setupConnection(host, port, nickname, sockopts, sleep)
  $socket = DCClientProtocol.connect(host, port, nickname, sockopts) do |c|
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
    c.registerCallback :error do |socket, message|
      STDERR.puts "! #{message}"
    end
    c.registerCallback :peer_error do |socket, peer, message|
      STDERR.puts "! Peer #{peer.host}:#{peer.port}: #{message}"
    end
    c.registerCallback :unbind do |socket|
      if c.quit then
        # this is our only socket for the moment
        EventMachine.stop_event_loop
      else
        EventMachine::add_timer(SLEEP_TABLE[sleep]) do
          sleep += 1 unless sleep == SLEEP_TABLE.size - 1
          setupConnection(host, port, nickname, sockopts, sleep)
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
          setupConnection(host, port, nickname, sockopts, 0)
        end
      end
    end
    c.registerCallback :reverse_connection do |socket, user|
      puts "* Bouncing RevConnectToMe back to user: #{user.nickname}"
    end
    c.registerCallback :reverse_connection_ignored do |socket, user|
      puts "* Ignoring RevConnectToMe from user: #{user.nickname}"
    end
    c.registerCallback :peer_initialized do |socket, peer|
      puts "* Connecting to peer: #{peer.host}:#{peer.port}"
    end
    c.registerCallback :peer_unbind do |socket, peer|
      peer_id = "#{peer.host}:#{peer.port}"
      peer_id << " (#{peer.remote_nick})" if peer.remote_nick
      puts "* Connection to peer #{peer_id} closed"
    end
    c.registerCallback :peer_get do |socket,peer,filename|
      peer_id = "#{peer.host}:#{peer.port}"
      peer_id << " (#{peer.remote_nick})" if peer.remote_nick
      puts "* Peer #{peer_id} requested: #{filename}"
    end
  end
end

Signal.trap 'INT' do
  Signal.trap 'INT', 'DEFAULT'
  STDERR.puts "\nShutting down..."
  # TODO: cancel all client2client connections that are in a cancel-able state
  EventMachine.stop_event_loop
end

main
