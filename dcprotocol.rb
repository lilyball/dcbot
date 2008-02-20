require 'stringio'
require 'cgi' # for entity-escaping
require './he3'
require './dcuser'

class DCProtocol < EventMachine::Connection
  include EventMachine::Protocols::LineText2
  
  def registerCallback(callback, &block)
    @callbacks[callback] << block
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
  
  def sanitize(data)
    data.gsub("|", "&#124;")
  end
  
  def unsanitize(data)
    CGI.unescapeHTML(data)
  end
  
  def send_command(cmd, *args)
    data = sanitize("$#{cmd}#{["", *args].join(" ")}") + "|"
    send_data(data)
  end
  
  def send_data(data)
    STDERR.puts "-> #{data}" if @debug
    super
  end
  
  def call_callback(callback, *args)
    @callbacks[callback].each do |proc|
      begin
        proc.call(self, *args)
      rescue Exception => e
        STDERR.puts "Exception: #{e.message}\n#{e.backtrace}"
      end
    end
  end
  
  def connection_completed
    call_callback :connected
  end
  
  def receive_line(line)
    STDERR.puts "<- #{line}" if @debug
    line.chomp!("|")
    line = unsanitize(line)
    cmd = line.slice!(/^\S+/)
    line.slice!(/^ /)
    
    if cmd =~ /^<.*>$/ then
      # this is a specially-formatted command
      # but lets handle it like other commands
      nick = cmd[1...-1]
      if self.respond_to? "cmd_<>" then
        self.send "cmd_<>", nick, line
      else
        call_callback :error, "Unknown command: <#{nick}> #{line}"
      end
    elsif cmd =~ /^\$\S+$/ then
      # this is a proper command
      cmd.slice!(0)
      # hardcode the $To: command since the colon is ugly
      # this protocol is pretty messy
      cmd = "To" if cmd == "To:"
      if self.respond_to? "cmd_#{cmd}" then
        self.send "cmd_#{cmd}", line
      else
        call_callback :error, "Unknown command: $#{cmd} #{line}"
      end
    else
      call_callback :error, "Garbage data: #{line}"
    end
  end
  
  def post_init
    @callbacks = Hash.new { |h,k| h[k] = [] }
    @debug = false
    set_delimiter "|"
  end
  
  def unbind
    call_callback :unbind
  end
end

class DCClientProtocol < DCProtocol
  # known keys for args are:
  #   password - server password
  #   debug - should this socket print debug data?
  #   description
  #   speed
  #   speed_class
  #   email
  #   version - version number for the tag
  #   slots - number of slots to declare as open
  def self.connect(host, port, nickname, args = {})
    EventMachine::connect(host, port, self) do |c|
      c.instance_eval do
        @nickname = nickname
        @config = args
        @debug = args[:debug]
        @config[:description] ||= ""
        @config[:speed] ||= "Bot"
        @config[:speed_class] ||= 1
        @config[:email] ||= ""
        @config[:version] ||= "0.1"
        @config[:slots] ||= 0
      end
      yield c if block_given?
    end
  end
  
  def sendPublicMessage(message)
    data = sanitize("<#{@nickname}> #{message}") + "|"
    send_data data
  end
  
  def sendPrivateMessage(recipient, message)
    send_command "To:", recipient, "From:", @nickname, "$<#{@nickname}>", message
  end
  
  def close
    @quit = true
    close_connection
  end
  
  attr_reader :nickname, :hubname, :quit, :users
  
  # protocol implementation
  
  def cmd_Lock(line)
    lock = line.split(" ")[0]
    key = lockToKey(lock)
    
    send_command("Key", "#{key}")
    send_command("ValidateNick", "#{@nickname}")
  end
  
  def cmd_ValidateDenide(line)
    call_callback :error, "Nickname in use or invalid"
    self.close
  end
  
  def cmd_GetPass(line)
    if @config.has_key? :password
      send_command "MyPass", @config[:password]
    else
      call_callback :error, "Password required but not given"
      self.close
    end
  end
  
  def cmd_BadPass(line)
    call_callback :error, "Bad password given"
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
      send_command "MyINFO", "$ALL #{@nickname} #{@config[:description]}<RubyBot V:#{@config[:version]},M:P,H:1/0/0,S:#{@config[:slots]}>$", \
                             "$#{@config[:speed]}#{@config[:speed_class].chr}$#{@config[:email]}$0$"
    else
      user = DCUser.new(self, nick)
      @users[nick] = user
      call_callback :user_connected, user
    end
  end
  
  def cmd_NickList(line)
    nicks = line.split("$$")
    @users = {}
    nicks.each do |nick|
      @users[nick] = DCUser.new(self, nick)
    end
    call_callback :nicklist, @users.values
  end
  
  def cmd_OpList(line)
    nicks = line.split("$$")
    nicks.each do |nick|
      if @users.has_key? nick then
        @users[nick].op = true
      end
    end
    call_callback :oplist, @users.values.select { |user| user.op }
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
      user = @users[nick]
      if user and user.nickname != @nickname then
        user.setInfo(interest, speed, speed_class, email, sharesize)
        call_callback :info, user
      end
    end
  end
  
  def cmd_ConnectToMe(line)
    # another peer is trying to connect to me
    if line =~ /^(\S+) (\S+):(\d+)$/ then
      mynick = $1
      ip = $2
      port = $3.to_i
      if mynick == @nickname then
        connect_to_peer(ip, port)
      else
        call_callback :error, "Strange ConnectToMe request: #{line}"
      end
    end
  end
  
  def cmd_RevConnectToMe(line)
    if line =~ /^(\S+) (\S+)$/ then
      # for the moment we're just going to be a passive client
      nick = $1
      mynick = $2
      if mynick == @nickname then
        user = @users[nick]
        if user then
          if not user.passive then
            # the passive switch keeps us from bouncing RevConnectToMe's back and forth
            user.passive = true
            call_callback :reverse_connection, user
            send_command "RevConnectToMe", mynick, nick
          else
            call_callback :reverse_connection_ignored, user
          end
        else
          call_callback :error, "RevConnectToMe request from unknown user: #{nick}"
        end
      else
        call_callback :error, "Strange RevConnectToMe request: #{line}"
      end
    end
  end
  
  define_method("cmd_<>") do |nick, line|
    call_callback :message, nick, line, false
  end
  
  def cmd_To(line)
    if line =~ /^(\S+) From: (\S+) \$<(\S+)> (.*)$/ then
      mynick = $1
      nick = $2
      displaynick = $3 # ignored for now
      message = $4
      call_callback :message, nick, message, true, (displaynick == "*")
    else
      call_callback :error, "Garbage $To: #{line}"
    end
  end
  
  def cmd_Quit(line)
    nick = line
    user = @users[nick]
    @users.delete nick
    if user.nil? then
      call_callback :error, "Unknown user Quit: #{nick}"
    else
      call_callback :user_quit, user
    end
  end
  
  def cmd_Search(line)
    # for the moment, completely ignore this
  end
  
  # utility methods
  
  def connect_to_peer(ip, port)
    @peers << EventMachine::connect(ip, port, DCPeerProtocol) do |c|
      parent = self
      debug = @debug || @config[:peer_debug]
      c.instance_eval do
        @parent = parent
        @host = ip
        @port = port
        @debug = debug
      end
      c.call_callback :initialized
    end
  end
  
  # event handling methods
  
  def post_init
    super
    @quit = false
    @peers = []
    @users = {}
    self.registerCallback :peer_unbind do |socket, peer|
      @peers.delete socket
    end
  end
  
  def unbind
    super
    @peers.each do |peer|
      peer.close_connection
    end
    @peers = []
  end
end

# major assumption in this implementation is that we are simply uploading
# if we want to be able to initiate downloads, this needs some tweaking
# we're also a passive client, so we're always connecting to the other client
class DCPeerProtocol < DCProtocol
  XML_FILE_LISTING = <<EOF
<?xml version="1.0" encoding="utf-8"?>
<FileListing Version="1" Generator="RubyBot">
<Directory Name="Send a /pm with !help for help">
</Directory>
</FileListing>
EOF
  DCLST_FILE_LISTING = <<EOF
Send a /pm with !help for help
EOF
  DCLST_FILE_LISTING_HE3 = he3_encode(DCLST_FILE_LISTING)
  
  attr_reader :remote_user, :host, :port
  
  def post_init
    super
  end
  
  # callbacks triggered from the peer always begin with peer_
  def call_callback(name, *args)
    @parent.call_callback "peer_#{name.to_s}".to_sym, self, *args
  end
  
  def connection_completed
    super
    send_command "MyNick", @parent.nickname
    send_command "Lock", "FOO", "Pk=BAR"
  end
  
  def cmd_MyNick(line)
    nick = line
    @remote_user = @parent.users[nick]
    if @remote_user.nil? then
      # why are we being connected to by someone not on the hub?
      @remote_user = DCUser.new(@parent, nick)
    end
  end
  
  def cmd_Lock(line)
    lock = line.split(" ")[0]
    key = lockToKey(lock)
    send_command "Direction", "Upload", rand(0x7FFF)
    send_command "Key", key
  end
  
  def cmd_Key(line)
    # who cares if they got the key right? just ignore it
  end
  
  def cmd_Direction(line)
    direction, rnd = line.split(" ")
    if direction != "Download" then
      # why did they send me a ConnectToMe if they don't want to download?
      call_callback :error, "Unexpected peer direction: #{direction}"
      # close_connection
    end
  end
  
  def cmd_GetListLen(line)
    send_command "ListLen", DCLST_FILE_LISTING_HE3.length
  end
  
  def cmd_Get(line)
    if line =~ /^([^$]+)\$(\d+)$/ then
      @filename = $1
      offset = $2.to_i - 1 # it's 1-based
      call_callback :get, @filename
      if @filename == "MyList.DcLst" then
        @fileio = StringIO.new(DCLST_FILE_LISTING_HE3)
        @fileio.pos = offset
        send_command "FileLength", @fileio.size - @fileio.pos
      else
        send_command "Error", "File Not Available"
        close_connection_after_writing
      end
    else
      send_command "Error", "Unknown $Get format"
      close_connection_after_writing
    end
  end
  
  def cmd_Send(line)
    if @fileio.nil? then
      # we haven't been asked for the file yet
      send_command "Error", "Unexpected $Send"
      close_connection_after_writing
    else
      data = @fileio.read(40906)
      send_data data
    end
  end
  
  def cmd_Canceled(line)
    close_connection
  end
  
  def cmd_Error(line)
    call_callback :error, "Peer Error: #{line}"
  end
end
