require 'socket'

def debug(msg)
  #STDERR.puts "DEBUG #{msg}"
end

class DCPPSocket
  attr_reader :socket
  attr :serverPort
  
  SERVER_PORT = 1412
  
  def initialize(server, port, nickname, serverPort = SERVER_PORT)
    @nickname = nickname
    @messages = []
    @serverPort = serverPort
    @clients = []
    @messageCallback = Proc.new do |sender, message, isprivate|
      STDERR.puts "ERROR: No message callback registered"
    end
    
    setupCommands
    
    connect(server, port)
  end
  
  def connect(server, port)
    @hubsocket = TCPSocket.new(server, port)
    @server = TCPServer.new('localhost', @serverPort)
  end
  
  def startRunLoop()
    catch :done do
      while true
        begin
          readsockets, _, _ = IO.select([@hubsocket, @server, *@clients])
          readsockets.each do |socket|
            if socket == @hubsocket then
              parseCommand()
            elsif socket == @server then
              clientsocket << @server.accept
              # print the client and return for now
              STDERR.puts "Client: #{clientsocket.peeraddr.inspect}"
              clientsocket.close
              # @clients << clientsocket
            else
              # socket is a client
              
            end
          end
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
    @hubsocket.close
  end
  
  def processMessage(sender, message, isprivate)
    @messageCallback.call(sender, message, isprivate)
  end
  
  # parses a given command
  # errors out if expected is given and doesn't match the command
  def parseCommand(expected = nil)
    cmdstring = @hubsocket.gets("|")
    if cmdstring.nil?
      @hubsocket.close
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
    @hubsocket.write(message)
  end
  
  def sendMessage(nick, message)
    str = "<#{nick}> #{message}|"
    debug("-> #{str.inspect}")
    @hubsocket.write(str)
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
    cmd("ConnectToMe") do |*args|
      STDERR.puts("ConnectToMe: #{args.inspect}")
    end # also ignore this - we aren't a fileserver
    cmd("RevConnectToMe") do |nick,remote|
      STDERR.puts("RevConnectToMe: #{nick} #{remote}")
      send("RevConnectToMe", remote, nick)
    end # pretend to be passive
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