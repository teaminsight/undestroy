require 'active_record'

class Undestroy::Binding::ActiveRecord

  attr_accessor :config, :model, :active
  alias :active? :active

  def initialize(model, options={})
    ensure_is_ar! model

    self.model = model
    self.config = Undestroy::Config.config.merge(options)
    yield self.config if block_given?
    self.active = true

    set_defaults
  end

  def before_destroy(instance)
    config.internals[:archive].new(
      :config => config,
      :transfer_options => { :target => target(instance) },
      :source => instance
    ).run if active?
  end

  def prefix_table_name(name)
    self.config.prefix.to_s + name.to_s
  end

  def deactivated
    previously = self.active
    self.active = false
    yield
  ensure
    self.active = previously
  end

  protected

  def target(source)
    source_pk = config.source_class.primary_key
    target_pk = config.target_class.primary_key
    config.target_class.where(target_pk => source[source_pk]).first
  end

  def set_defaults
    self.config.source_class = self.model
    self.config.table_name ||= prefix_table_name(self.model.table_name) if self.model.respond_to?(:table_name)
    self.config.target_class ||= create_target_class
    ensure_is_ar! self.config.target_class
  end

  # Builds a dynamic AR class representing the archival table
  def create_target_class
    Class.new(self.config.abstract_class || ActiveRecord::Base).tap do |target_class|
      target_class.table_name = self.config.table_name
      target_class.class_attribute :undestroy_model_binding, :instance_writer => false
      target_class.undestroy_model_binding = self
      target_class.send :include, Restorable
    end
  end

  def ensure_is_ar!(klass)
    raise ArgumentError, "#{klass.inspect} must be an ActiveRecord model" unless is_ar?(klass)
  end

  def is_ar?(klass)
    klass.is_a?(Class) && klass.ancestors.include?(ActiveRecord::Base)
  end

  # Add binding to the given class if it doesn't already have it
  def self.add(klass=ActiveRecord::Base)
    klass.class_eval do

      def self.undestroy(options={})
        class_eval do
          class_attribute :undestroy_model_binding, :instance_writer => false

          before_destroy { undestroy_model_binding.before_destroy(self) }

          def self.archived
            undestroy_model_binding.config.target_class
          end

          def self.restore(*args)
            [*archived.find(*args)].each(&:restore)
          end

          def destroy!
            undestroy_model_binding.deactivated do
              destroy
            end
          end

        end unless respond_to?(:undestroy_model_binding)

        self.undestroy_model_binding = Undestroy::Binding::ActiveRecord.new(self, options)
      end


    end unless klass.respond_to?(:undestroy)
  end

  def self.load_models(path)
    Dir[File.join(path, '**', '*.rb')].each do |file|
      require_dependency file
    end
  end

end

require 'undestroy/binding/active_record/migration_statement'
require 'undestroy/binding/active_record/restorable'

