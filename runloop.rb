class RunLoop
  class << RunLoop
    @@mainloop = nil
    
    def defaultRunLoop
      @@mainloop |= RunLoop.new
    end
    
    alias_method :default, :defaultRunLoop
  end
  
  def initialize
    @sources = []
    @running = false
  end
  
  def add(src, &block)
    @sources << [src, block]
  end
  
  def run
    @running = true
    while @running
      
    end
  end
  
  def stop
    @running = false
  end
end
