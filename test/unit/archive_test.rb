require 'assert'

module Undestroy::Archive::Test
  class Base < Undestroy::Test::Base
    subject { Undestroy::Archive }
    desc 'Undestroy::Archive class'

    setup do
      @default_init = {
        :source => Undestroy::Test::Fixtures::ARFixture.construct(:id => 1, :name => "Foo"),
        :config => Undestroy::Config.new
      }
    end

    def archive_instance(args={})
      Undestroy::Archive.new(@default_init.merge(args))
    end
  end

  class BasicInstance < Base
    subject { archive_instance }
    desc 'basic instance'

    should have_accessors :source, :config, :transfer, :transfer_options
  end

  class InitMethod < Base
    desc 'initialize method'

    should "require :source and :config options in hash argument" do
      assert_raises(ArgumentError) { subject.new }
      assert_raises(ArgumentError) { subject.new :source => nil }
      assert_raises(ArgumentError) { subject.new :config => nil }
    end

    should "set the source to source attr" do
      obj = archive_instance :source => "foo"
      assert_equal "foo", obj.source
    end

    should "set the config to config attr" do
      obj = archive_instance :config => "foo"
      assert_equal "foo", obj.config
    end

    should "set optional :transfer to transfer attr" do
      obj = archive_instance :transfer => "foo"
      assert_equal "foo", obj.transfer
    end

    should "set optional :transfer_options to transfer_options attr" do
      obj = archive_instance :transfer_options => { :foo => 'bar' }
      assert_equal({ :foo => 'bar' }, obj.transfer_options)
    end
  end

  class TransferMethod < BasicInstance
    desc 'transfer method'

    setup do
      @archive = subject
      @archive.config.target_class = Undestroy::Test::Fixtures::ARFixture
    end

    should "return instance of config.internals[:transfer]" do
      assert_instance_of @archive.config.internals[:transfer], @archive.transfer
    end

    should "cache the created instance" do
      assert_equal @archive.transfer.object_id, @archive.transfer.object_id
    end

    should "set fields on instance to config.fields.merge(source.attributes) with evaled procs" do
      target = @archive.transfer.target
      assert_instance_of @archive.config.target_class, @archive.transfer.target
      assert_equal 1, target.attributes[:id]
      assert_equal "Foo", target.attributes[:name]
      assert_instance_of Time, target.attributes[:deleted_at]
    end

    should "eval lambdas with source instance as argument" do
      val = nil
      @archive.config.add_field(:test, :string) { |arg| val = arg; "FOO" }
      target = @archive.transfer.target
      assert_equal @archive.source, val
      assert_equal "FOO", target.attributes[:test]
    end

    should "merge transfer_options attr onto arguments" do
      fixture = Class.new do
        attr_accessor :args
        def initialize(args)
          @args = args
        end
        def [](key)
          @args[key]
        end
      end
      @archive.config.internals[:transfer] = fixture
      @archive.transfer_options = { :foo => 'bar', :fields => 123 }

      assert_equal 'bar', @archive.transfer[:foo]
      assert_equal 123, @archive.transfer[:fields]
      assert_equal @archive.config.target_class, @archive.transfer[:klass]
    end
  end

  class RunMethod < Base
    desc 'run method'

    should "exist" do
      assert_respond_to :run, archive_instance
    end

    should "call run on the transfer model" do
      foo = Class.new do
        @@called = false
        def initialize(options={})
        end

        def run
          @@called = true
        end

        def self.called
          @@called
        end
      end

      archive = archive_instance(:transfer => foo.new)

      assert !foo.called
      archive.run
      assert foo.called
    end
  end
end

