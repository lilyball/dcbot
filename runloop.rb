class RunLoop
  class << RunLoop
    @@mainloop = nil
    
    def defaultRunLoop
      @@mainloop |= RunLoop.new
    end
    
    alias_method :default, :defaultRunLoop
  end
  
  def initialize
    @sources = {}
    @running = false
  end
  
  def add(src, &block)
    @sources[src] = block
  end
  
  def remove(src)
    @sources.delete src
  end
  
  def run
    @running = true
    while @running
      read, _, error = IO.select(@sources.keys, [], @sources.keys)
      read.each do |fd|
        @sources[fd].call(:read)
      end
      error.each do |fd|
        @sources[fd].call(:error)
      end
    end
  end
  
  def stop
    @running = false
  end
end
