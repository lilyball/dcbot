RunLoopSource = Struct.new :fd, :events, :proc

class RunLoop
  class << RunLoop
    @@mainloop = nil
    
    def defaultRunLoop
      @@mainloop ||= RunLoop.new
    end
    
    alias_method :default, :defaultRunLoop
  end
  
  def initialize
    @sources = []
    @running = false
  end
  
  def add(src, types, &block)
    @sources << RunLoopSource.new(src, types, block)
  end
  
  def remove(src, types = nil)
    if types.nil? then
      @sources.delete_if { |rls| rls.fd == src }
    else
      @sources.select { |rls| rls.fd == src }.each do |rls|
        types.each do |type|
          rls.events.delete type
        end
      end
      @sources.delete_if { |rls| rls.events.empty? }
    end
  end
  
  def run
    @running = true
    while @running
      readers = @sources.select { |rls| rls.events.include? :read }.map { |rls| rls.fd }
      writers = @sources.select { |rls| rls.events.include? :write }.map { |rls| rls.fd }
      errorers = @sources.map { |rls| rls.fd }
      read, write, error = IO.select(readers, writers, errorers)
      [[read, :read], [write, :write], [error, :error]].each do |ary, event|
        ary.each do |fd|
          @sources.select { |rls| rls.fd == fd }.each { |rls| rls.proc.call(fd, event) }
        end
      end
    end
  end
  
  def stop
    @running = false
  end
end
