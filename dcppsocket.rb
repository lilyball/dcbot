require 'socket'

def debug(msg)
  #STDERR.puts "DEBUG #{msg}"
end

class DCPPSocket
  attr_reader :socket
  
  def initialize(server, port, nickname)
    @nickname = nickname
    @messages = []
    @messageCallback = Proc.new do |sender, message, isprivate|
      STDERR.puts "ERROR: No message callback registered"
    end
    
    setupCommands
    
    connect(server, port)
  end
  
  def connect(server, port)
    @socket = TCPSocket.new(server, port)
  end
  
  def startRunLoop()
    catch :done do
      while true
        begin
          parseCommand()
        rescue StandardError => e
          STDERR.puts "ERROR: #{e.to_s}"
        end
      end
    end
  end
  
  def registerMessageCallback(&block)
    @messageCallback = block
  end
  
  def sendPublicMessage(message)
    sendMessage(@nickname, message)
  end
  
  def sendPrivateMessage(recipient, message)
    send("To:", recipient, "From:", @nickname, "$<#{@nickname}>", message)
  end
  
  def close
    @socket.close
  end
  
  def processMessage(sender, message, isprivate)
    @messageCallback.call(sender, message, isprivate)
  end
  
  # parses a given command
  # errors out if expected is given and doesn't match the command
  def parseCommand(expected = nil)
    cmdstring = @socket.gets("|")
    if cmdstring.nil?
      @socket.close
      throw :done
    end
    debug("<- #{cmdstring.inspect}")
    cmdstring = cmdstring.chomp("|")
    cmd, *args = cmdstring.split(" ")
    
    if cmd[0,1] == "<" and cmd[-1,1] == ">" then
      # it's a public message
      processMessage(cmd[1...-1], args.join(" "), false)
    else
      raise "Unexpected command data: #{cmdstring}" unless cmd[0,1] == "$"
      cmd = cmd[1..-1]
      raise "Unexpected command: #{cmdstring}" if expected != cmd unless expected.nil?
      
      raise "Unknown command: #{cmdstring}" unless @commands.has_key? cmd
      
      @commands[cmd].call(*args)
    end
  end
  
  def send(cmd, *args)
    message = "$#{cmd}#{args.empty? ? "" : " "}#{args.join(" ")}|"
    debug("-> #{message.inspect}")
    @socket.write(message)
  end
  
  def sendMessage(nick, message)
    str = "<#{nick}> #{message}|"
    debug("-> #{str.inspect}")
    @socket.write(str)
  end
  
  def lockToKey(lock)
    key = String.new(lock)
    1.upto(key.size - 1) do |i|
      key[i] = lock[i] ^ lock[i-1]
    end
    key[0] = lock[0] ^ lock[-1] ^ lock[-2] ^ 5
    
    # nibble-swap
    0.upto(key.size - 1) do |i|
      key[i] = ((key[i]<<4) & 240) | ((key[i]>>4) & 15)
    end
    
    0.upto(key.size - 1) do |i|
      if [0,5,36,96,124,126].include?(key[i]) then
        key[i,1] = ("/%%DCN%03d%%/" % key[i])
      end
    end
    
    key
  end
  
  # Commands
  def cmd(name, &block)
    @commands[name] = block
  end
  
  def setupCommands
    @commands = Hash.new
    cmd("Lock") do |lock,pk|
      send("Key", lockToKey(lock))
      send("ValidateNick", @nickname)
    end
    cmd("HubName") { |*name| @hubname = name.join(" ") }
    cmd("Hello") do |nick|
      if @nickname == nick
        send("Version", "1,0091")
        send("GetNickList")
        send("MyINFO", "$ALL #{@nickname} Ruby Request Bot<RubyBot V:0.1>$", "$Bot\001$$0$")
      end
    end
    cmd("MyINFO") { |*args| } # do nothing for MyINFO
    cmd("ConnectToMe") { |*args| } # also ignore this - we aren't a fileserver
    cmd("RevConnectToMe") { |nick,remote| send("RevConnectToMe", remote, nick) } # pretend to be passive
    cmd("To:") do |me, from, sender, *message|
      raise "Unexpected To: data" if from != "From:" or message[0][0,1] != "$"
      processMessage(sender, message[1..-1].join(" "), true)
    end
    cmd("NickList") { |*args| } # ignore
    cmd("OpList") { |*args| } # ignore
    cmd("Quit") { |*args| } # ignore
    cmd("Search") { |*args| } # ignore
  end
end