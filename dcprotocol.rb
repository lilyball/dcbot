class DCProtocol < EventMachine::Connection
  include EventMachine::Protocols::LineText2
  
  RUBYBOT_VERSION = 0.1
  
  # known keys for args are:
  #   password
  #   description
  #   speed
  #   speed_class
  #   email
  def self.connect(host, port, nickname, args = {})
    EventMachine::connect(host, port, self) do |c|
      c.instance_eval do
        @nickname = nickname
        @config = args
        @config[:description] ||= ""
        @config[:speed] ||= "Bot"
        @config[:speed_class] ||= 1
        @config[:email] = ""
      end
      yield c if block_given?
    end
  end
  
  def sendPublicMessage(message, isaction = false)
    if isaction then
      nick = "*"
      message = "#{@nickname} #{message}"
    else
      nick = @nickname
    end
    send_data "<#{nick}> #{message}!"
  end
  
  def sendPrivateMessage(recipient, message, isaction = false)
    if isaction then
      nick = "*"
      message = "#{@nickname} #{message}"
    else
      nick = @nickname
    end
    send_command "To:", recipient, "From:", @nickname, "$<#{nick}>", message
  end
  
  def close
    @quit = true
    send_command("Quit")
    close_connection_after_writing
  end
  
  def registerCallback(callback, &block)
    @callbacks[callback] = block
  end
  
  attr_reader :nickname, :hubname, :quit
  
  # protocol implementation
  
  def cmd_Lock(line)
    lock = line.split(" ")[0]
    key = lockToKey(lock)
    
    send_command("Key", "#{key}")
    send_command("ValidateNick", "#{@nickname}")
  end
  
  def cmd_ValidateDenide(line)
    STDERR.puts "Nickname in use or invalid"
    self.close
  end
  
  def cmd_GetPass(line)
    if @config.has_key? :password
      send_command "MyPass", @config[:password]
    else
      STDERR.puts "Password required but not given"
      self.close
    end
  end
  
  def cmd_BadPass(line)
    STDERR.puts "Bad password given"
    self.close
  end
  
  def cmd_LogedIn(line)
    call_callback :logged_in
  end
  
  def cmd_HubName(line)
    @hubname = line
    call_callback :hubname, @hubname
  end
  
  def cmd_Hello(line)
    nick = line
    if nick == @nickname then
      # this is us, we should respond
      send_command "Version", "1,0091"
      send_command "GetNickList"
      send_command "MyINFO", "$ALL #{@nickname} #{@config[:description]}<RubyBot V:#{RUBYBOT_VERSION}>$", \
                             "$#{@config[:speed]}#{@config[:speed_class].chr}$#{@config[:email]}$0$"
    else
      call_callback :user_connected, nick
    end
  end
  
  def cmd_NickList(line)
    call_callback :nicklist, line.split("$$")
  end
  
  def cmd_OpList(line)
    call_callback :oplist, line.split("$$")
  end
  
  def cmd_MyINFO(line)
    if line =~ /^\$ALL (\S+) ([^$]*)\$ +\$([^$]*)\$([^$]*)\$([^$]*)\$$/ then
      nick = $1
      interest = $2
      speed = $3
      email = $4
      sharesize = $5
      if speed.length > 0 and speed[-1] < 0x20 then
        # assume last byte a control character means it's the speed class
        speed_class = speed.slice!(-1)
      else
        speed_class = 0
      end
      call_callback :info, nick, interest, speed, speed_class, email, sharesize unless nick == @nickname
    end
  end
  
  def cmd_ConnectToMe(line)
    # another peer is trying to connect to me
    if line =~ /^(\S+) (\S+):(\d+)$/ then
      nick = $1
      ip = $2
      port = $3
      connect_to_peer(nick, ip, port)
    end
  end
  
  def cmd_RevConnectToMe(line)
    if line =~ /^(\S+) (\S+)$/ then
      # for the moment we're just going to be a passive client
      STDERR.puts "$RevConnectToMe: #{line}"
      send_command "RevConnectToMe", $2, $1
    end
  end
  
  def cmd_To(line)
    if line =~ /^(\S+) From: (\S+) \$<(\S+)> (.*)$/ then
      mynick = $1
      nick = $2
      displaynick = $3 # ignored for now
      message = $4
      call_callback :message, nick, true, (displaynick == "*")
    else
      STDERR.puts "Garbage To: #{line}"
    end
  end
  
  def cmd_Quit(line)
    nick = line
    call_callback :user_quit, nick
  end
  
  def cmd_Search(line)
    # for the moment, completely ignore this
  end
  
  # utility methods
  
  def send_command(cmd, *args)
    send_data("$#{cmd}#{["", *args].join(" ")}|")
  end
  
  def call_callback(callback, *args)
    @callbacks[callback].call(self, *args) if @callbacks.has_key? callback
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
  
  # event handling methods
  
  def initialize(*args)
    @quit = false
    super
  end
  
  def post_init
    @data = ""
    @callbacks = {}
    set_delimiter "|"
  end
  
  def connection_completed
    call_callback :connected
  end
  
  def receive_line(line)
    line.chomp!("|")
    cmd = line.slice!(/^\S+/)
    line.slice!(/^ /)
    
    if line[0] == ?< then
      # this must be a public message
      nick = line.slice!(/^<\S*?>/)
      if nick.nil? then
        # huh, bad message
        STDERR.puts "Garbage data: #{line}"
      else
        line.slice!(/^ /)
        call_callback :message, nick[1...-1], line, false, false
      end
    elsif line[0] =~ /^\$\S+/ then
      # this is a proper command
      line.slice!(0)
      cmd = line.slice!(/\S+/)
      line.slice!(/^ /)
      # hardcode the $To: command since the colon is ugly
      # this protocol is pretty messy
      cmd = "To" if cmd == "To:"
      if self.respond_to? "cmd_#{cmd}" then
        self.send "cmd_#{cmd}", line
      else
        STDERR.puts "Unknown command: $#{cmd} #{line}"
      end
    else
      STDERR.puts "Garbage data: #{line}"
    end
  end
  
  def unbind
    call_callback :unbind
  end
end