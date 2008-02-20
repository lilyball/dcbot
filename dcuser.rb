class DCUser
  attr_reader :hub, :nickname
  attr_reader :description, :tag, :speed, :speed_class, :email, :sharesize
  attr_accessor :passive, :op
  
  def initialize(hub, nickname)
    @hub = hub
    @nickname = nickname
    @passive = false
    @op = false
  end
  
  def sendMessage(message)
    @hub.sendPrivateMessage(@nickname, message)
  end
  
  def setInfo(description, tag, speed, speed_class, email, sharesize)
    @description = description
    @tag = tag
    @speed = speed
    @speed_class = speed_class
    @email = email
    @sharesize = sharesize
  end
end
