
class Undestroy::Test::Fixtures::ARFixture
  cattr_accessor :calls, :primary_key
  attr_accessor :attributes
  attr_reader :saved

  self.calls = []
  self.primary_key = :id

  alias :saved? :saved

  def initialize(attributes={})
    @saved = false
    self.attributes = HashWithIndifferentAccess.new(attributes)
    self.attributes.delete(:id)
  end

  def [](key)
    @attributes[key]
  end

  def []=(key, val)
    @attributes[key] = val
  end

  # Method missing won't catch this one
  def id
    self[:id]
  end

  def attributes
    @attributes.stringify_keys
  end

  def save
    @saved = true
  end

  # Shortcut to build an instance for testing purposes.
  def self.construct(attributes={})
    self.new.tap do |fixture|
      attributes.each do |field, value|
        fixture[field] = value
      end
    end
  end

  def self.where(*attrs)
    self.calls << [:where, attrs]
    self
  end

  def self.first(*attrs)
    self.calls << [:first, attrs]
  end

end

