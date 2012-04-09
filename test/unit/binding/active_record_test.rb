require 'assert'

module Undestroy::Binding::ActiveRecord::Test

  class Base < Undestroy::Test::Base
    desc 'Binding::ActiveRecord class'
    subject { Undestroy::Binding::ActiveRecord }

    setup do
      @model = Class.new(Undestroy::Test::ARMain)
      @model.table_name = 'foobar'
      @model.connection.create_table :foobar, :force => true
      @model.connection.create_table :archive_foobar, :force => true
    end

    teardown do
      @model.connection.execute 'drop table if exists foobar'
      @model.connection.execute 'drop table if exists archive_foobar'
      Undestroy::Config.instance_variable_set(:@config, nil)
      Undestroy::Test::Fixtures::Archive.reset
    end
  end

  class BasicInstance < Base
    desc 'basic instance'
    subject { Undestroy::Binding::ActiveRecord.new @model }

    should have_accessors :config, :model, :active

    should "have instance method :active? as alias for :active" do
      obj = subject
      obj.active = false
      assert_equal false, obj.active?
      obj.active = true
      assert_equal true, obj.active?
    end
  end

  class AddClassMethod < Base
    desc 'add class method'

    setup do
      @model.class_eval do
        undef_method :undestroy_model_binding if respond_to?(:undestroy_model_binding)
        remove_possible_method :undestroy_model_binding=
        class << self
          undef_method :undestroy
        end
      end
      @model._destroy_callbacks = []
    end

    should "add undestroy class method to klass initializing this binding" do
      subject.add @model
      assert_respond_to :undestroy, @model

      @model.undestroy :fields => {}

      assert_instance_of subject, @model.undestroy_model_binding
      assert_equal Hash.new, @model.undestroy_model_binding.config.fields
    end

    should "allow adding to other classes" do
      new_model = Class.new(@model)
      subject.add(new_model)
      assert_respond_to :undestroy, new_model
      assert_not_respond_to :undestroy, @model
    end

  end

  class UndestroyExtensionMethod < AddClassMethod
    desc 'added undestroy method'

    setup do
      subject.add @model
    end

    should "add class_attr called `undestroy_model_binding`" do
      assert_not_respond_to :undestroy_model_binding, @model
      assert_not_respond_to :undestroy_model_binding=, @model
      @model.undestroy
      assert_respond_to :undestroy_model_binding, @model
      assert_respond_to :undestroy_model_binding=, @model
    end

    should "add before_destroy callback when undestroy called" do
      archive_class = Undestroy::Test::Fixtures::Archive
      @model.undestroy :internals => { :archive => archive_class }

      callback = @model._destroy_callbacks.first
      assert callback, "No destroy callbacks defined"
      assert_equal :before, callback.kind
      assert_instance_of Proc, callback.raw_filter

      instance = @model.new
      instance.instance_eval(&callback.raw_filter)
      assert_equal [[:run]], archive_class.data[:calls]
    end

    should "only add callbacks once" do
      @model.undestroy
      @model.undestroy
      assert_equal 1, @model._destroy_callbacks.size
    end

    should "add archived class method" do
      assert_not_respond_to :archived, @model
      @model.undestroy
      assert_respond_to :archived, @model
    end

    should "add archived method that returns configured target_class after undestroy configured" do
      @model.undestroy
      assert_equal @model.undestroy_model_binding.config.target_class, @model.archived
    end

    should "add restore method" do
      assert_not_respond_to :restore, @model
      @model.undestroy
      assert_respond_to :restore, @model
    end

    should "add restore method that passes args to target_class find and then calls 'restore' on each record" do
      @model.undestroy
      fixture = Class.new do
        cattr_accessor :calls, :return_val
        self.calls = []
        self.return_val = nil

        def self.find(*args)
          self.calls << [:find, args]
          self.return_val
        end

        def restore
          self.calls << [:restore]
        end
      end

      @model.undestroy_model_binding.config.target_class = fixture

      fixture.return_val = fixture.new
      @model.restore(:foo, :bar => :baz)

      assert_equal [:find, [:foo, { :bar => :baz }]], fixture.calls[0]
      assert_equal [:restore], fixture.calls[1]

      fixture.calls = []

      fixture.return_val = [fixture.new, fixture.new]
      @model.restore

      assert_equal [:restore], fixture.calls[1]
      assert_equal [:restore], fixture.calls[2]
      assert_nil fixture.calls[3]
    end

    should "add destroy! instance method that calls destroy without archival" do
      @model.class_eval do
        cattr_accessor :calls
        self.calls = []

        def destroy
          calls << [:destroy, undestroy_model_binding.active]
        end
      end
      @model.undestroy
      assert_respond_to :destroy!, @model.new

      @model.new.destroy!

      assert_equal [:destroy, false], @model.calls[0]
    end
  end

  class LoadModelsClassMethod < Base
    desc 'load_models class method'
    include Undestroy::Test::Helpers::ModelLoading

    should "force all models to load recursively in supplied path" do
      path = Undestroy::Test.fixtures_path('load_test', 'models1')
      assert_loads_models(path) do
        subject.load_models(path)
      end
    end

  end

  class InitMethod < Base
    desc 'init method'

    should "require first argument and set it to model" do
      assert_raises(ArgumentError) { subject.new }
      binding = subject.new @model
      assert_equal @model, binding.model
    end

    should "validate model argument is AR::Base" do
      assert_raises(ArgumentError) { subject.new Class.new }
    end

    should "accept optional hash of config options" do
      assert_not_raises { subject.new @model, {} }
    end

    should "set config attr to new config object" do
      binding = subject.new @model
      assert_instance_of Undestroy::Config, binding.config
    end

    should "default :active attr to true" do
      assert subject.new(@model).active, "Should be active by default"
    end

    should "merge config options onto global config" do
      Undestroy::Config.configure do |config|
        config.fields = {}
      end
      assert_equal Hash.new, subject.new(@model).config.fields
      assert_not_equal subject.new(@model).config.object_id, Undestroy::Config.config.object_id
      assert_not_equal subject.new(@model).config.fields.object_id, Undestroy::Config.config.fields.object_id
      assert_equal({ :foo => :bar }, subject.new(@model, :fields => { :foo => :bar }).config.fields)
    end

    should "accept block and pass config object to it" do
      binding = subject.new @model, {} do |config|
        config.fields = {}
      end
      assert_equal Hash.new, binding.config.fields
    end

    should "set config.source_class to value of model" do
      binding = subject.new(@model)
      assert_equal @model, binding.config.source_class
    end

    should "default :table_name to '{config.prefix}{source.table_name}'" do
      @model.table_name = :foobar
      binding = subject.new(@model, :prefix => "prefix_archive_")
      assert_equal 'prefix_archive_foobar', binding.config.table_name
    end

    should "create a target_class if none provided" do
      binding = subject.new(@model)
      assert binding.config.target_class.ancestors.include?(ActiveRecord::Base)
    end

    should "use target_class if provided" do
      target = Class.new(Undestroy::Test::ARAlt)
      target.table_name = "target_class_test"
      binding = subject.new(@model, :target_class => target)

      assert_equal target, binding.config.target_class
      assert_equal 'target_class_test', binding.config.target_class.table_name
      assert_equal 'tmp/alt.db', binding.config.target_class.connection_config[:database]
    end

    should "validate target_class is AR::Base if provided" do
      target = Class.new
      assert_raises(ArgumentError) { subject.new(@model, :target_class => target) }
    end

    should "set target class's table_name to :table_name attr" do
      binding = subject.new(@model, :table_name => "foo_foo_archive")
      assert_equal "foo_foo_archive", binding.config.target_class.table_name
    end

    should "set target class's parent class to :abstract_class attr" do
      @model.table_name = :foobar
      binding = subject.new(@model, :abstract_class => Undestroy::Test::ARAlt)
      assert_equal 'tmp/alt.db', binding.config.target_class.connection_config[:database]
    end

    should "create class_attribute undestroy_model_binding with no instance writer" do
      binding = subject.new(@model)
      assert_respond_to :undestroy_model_binding, binding.config.target_class
      assert_respond_to :undestroy_model_binding=, binding.config.target_class
      assert_respond_to :undestroy_model_binding, binding.config.target_class.new
      assert_not_respond_to :undestroy_model_binding=, binding.config.target_class.new
    end

    should "set self to the undestroy_model_binding on the target_class" do
      binding = subject.new(@model)
      assert_equal binding, binding.config.target_class.undestroy_model_binding
    end

    should "include Restorable mixin" do
      binding = subject.new(@model)
      assert_includes Undestroy::Binding::ActiveRecord::Restorable, binding.config.target_class.ancestors
    end

  end

  class BeforeDestroy < Base
    desc 'before_destroy method'
    subject { @binding ||= Undestroy::Binding::ActiveRecord.new(@model) }

    should "exist and require one param" do
      assert_respond_to :before_destroy, subject
      assert_equal 1, subject.method(:before_destroy).arity
    end

    should "instantiate config[:archive] instance with config and model instance and call `run`" do
      test_class = Undestroy::Test::Fixtures::Archive
      ar_source = Undestroy::Test::Fixtures::ARFixture.new
      subject.config.internals[:archive] = test_class
      subject.before_destroy(ar_source)

      assert_equal subject.config, test_class.data[:args][:config]
      assert_equal ar_source, test_class.data[:args][:source]
      assert_equal [[:run]], test_class.data[:calls]
    end

    should "pass :target value in :transfer_options if archive record exists and nil otherwise" do
      archive_class = Undestroy::Test::Fixtures::Archive
      ar_source = Undestroy::Test::Fixtures::ARFixture.new
      ar_source[:id] = 1
      subject.config.internals[:archive] = archive_class
      subject.config.source_class = ar_source.class
      subject.config.target_class = ar_source.class
      subject.before_destroy(ar_source)

      assert_equal [:where, [{ :id => 1 }]], ar_source.calls[0]
      assert_equal [:first, []], ar_source.calls[1]
    end

    should "not run the archival if active is false" do
      archive_class = Undestroy::Test::Fixtures::Archive
      ar_source = Undestroy::Test::Fixtures::ARFixture.new
      subject.config.internals[:archive] = archive_class
      subject.active = false
      subject.before_destroy(ar_source)
      assert_equal 0, archive_class.data[:calls].size
    end
  end

  class PrefixTableNameMethod < Base
    desc 'prefix_table_name method'
    subject { @binding ||= Undestroy::Binding::ActiveRecord.new(@model) }

    should "return {config.prefix}{source.table_name}" do
      subject.config.prefix = "archive_prefix_"
      assert_equal "archive_prefix_foo", subject.prefix_table_name("foo")
    end
  end

  class DeactivatedMethod < Base
    desc 'deactivated method'
    subject { @binding ||= Undestroy::Binding::ActiveRecord.new(@model) }

    should "set activated to false and yield to block" do
      called = false
      block = proc {
        called = true
        assert !subject.active, "Binding should be deactivated"
      }
      subject.deactivated(&block)
      assert called, "Block should be called"
    end

    should "always set activated back to original value" do
      block = proc {}
      raise_block = proc { raise "FOO" }

      subject.deactivated(&block)
      assert subject.active, "Should be activated"

      assert_raises { subject.deactivated(&raise_block) }
      assert subject.active, "Should be activated"

      subject.active = false
      subject.deactivated(&block)
      assert !subject.active, "Should not be activated"
    end
  end

end

