
class Undestroy::Transfer
  attr_accessor :target

  def initialize(args={})
    raise ArgumentError, ":klass option required" unless args[:klass]
    args[:fields] ||= {}

    self.target = args[:target] || args[:klass].new

    # Set instance values directly to avoid AR's filtering of protected fields
    args[:fields].each do |field, value|
      self.target[field] = value
    end
  end

  def run
    self.target.save
  end

end

