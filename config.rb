module IniReader
  def self.read(filename)
    File.open(filename, "r") do |f|
      read_stream(f)
    end
  end
  
  def self.read_stream(io)
    config = []
    name = ""
    section = {}
    until (line = io.gets).nil?
      if line =~ /^\s*#/ then
        # do nothing
      elsif line =~ /^\[(.*)\]\s*$/ then
        config << [name, section]
        name = $1
        section = {}
      elsif line =~ /^\s*(.*?)\s*=\s*(.*?)\s*$/ then
        section[$1] = $2
      end
    end
    config << [name, section]
    if config.size > 0 and config[0][0] == "" and config[0][1].empty? then
      config.delete_at 0
    end
    config
  end
end
