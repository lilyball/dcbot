module KeyboardInput
  include EventMachine::Protocols::LineText2
  
  def receive_line(line)
    line.chomp!
    $socket.sendPublicMessage(line)
  end
end
