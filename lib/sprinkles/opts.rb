# typed: strict
# frozen_string_literal: true

require 'optparse'
require 'sorbet-runtime'

module Sprinkles; module Opts; end; end

module Sprinkles::Opts
  class GetOpt
    extend T::Sig
    extend T::Helpers
    abstract!

    sig { abstract.returns(String) }
    def self.program_name; end

    class Option < T::Struct
      extend T::Sig

      const :short, T.nilable(String)
      const :long, T.nilable(String)
      const :type, T.untyped
      const :placeholder, T.nilable(String)
      const :factory, T.nilable(T.proc.returns(T.untyped))
      const :description, T.nilable(String)

      sig { returns(T::Boolean) }
      def optional?
        return true unless factory.nil?
        return true if type.is_a?(T::Types::Union) && type.types.any? { |t| t == T::Utils.coerce(NilClass) }

        false
      end

      sig { returns(String) }
      def get_placeholder
        placeholder || 'VALUE'
      end
    end

    # for appeasing Sorbet, even though this isn't how we're using the
    # props methods. (we're also not allowing `prop` at all, only
    # `const`.)
    sig { params(rest: T.untyped).returns(T.untyped) }
    def self.decorator(*rest); end

    sig { returns(T::Hash[Symbol, Option]) }
    private_class_method def self.fields
      @fields = T.let(@fields, T.nilable(T::Hash[Symbol, Option]))
      @fields ||= {}
    end

    sig do
      params(
        name: Symbol,
        type: T.untyped,
        short: String,
        long: String,
        factory: T.nilable(T.proc.returns(T.untyped)),
        placeholder: String,
        description: String,
        without_accessors: TrueClass
      )
        .returns(T.untyped)
    end
    def self.const(
      name,
      type,
      short: '',
      long: '',
      factory: nil,
      placeholder: '',
      description: '',
      without_accessors: true
    )
      raise 'Do not start options with -' if short.start_with?('-')
      raise 'Do not start options with -' if long.start_with?('-')
      if (short == 'h') || (long == 'help')
        raise <<~RB
          The options `-h` and `--help` are reserved by Sprinkles::Opts::GetOpt
        RB
      end
      if !valid_type?(type)
        raise "#{type} is not a valid parameter type"
      end

      # we don't want to let the user pass in nil explicitly, so the
      # default values here are all '' instead, but we will treat ''
      # as if the argument was not provided
      short = nil if short.empty?
      long = nil if long.empty?
      raise <<~RB if short.nil? && long.nil?
        You must define at least one `short:` or `long:` option for #{name}
      RB

      placeholder = nil if placeholder.empty?
      fields[name] = Option.new(
        type: type,
        short: short,
        long: long,
        factory: factory,
        placeholder: placeholder,
        description: description
      )
    end

    sig { params(type: T.untyped).returns(T::Boolean) }
    def self.valid_type?(type)
      type = type.raw_type if type.is_a?(T::Types::Simple)
      # true if the type is one of the valid types
      return true if type == String || type == Symbol || type == Integer || type == Float || type == T::Boolean
      # true if it's a nilable valid type
      if type.is_a?(T::Types::Union)
        other_types = type.types.to_set - [T::Utils.coerce(NilClass)]
        return false if other_types.size > 1
        return valid_type?(other_types.first)
      end

      # otherwise we probably don't handle it
      false
    end

    sig { params(value: String, type: T.untyped).returns(T.untyped) }
    def self.convert_str(value, type)
      type = type.raw_type if type.is_a?(T::Types::Simple)
      if type.is_a?(T::Types::Union)
        # Right now, the assumption is that this is mostly used for
        # `T.nilable`, but with a bit of work we maybe could support
        # other kinds of unions
        possible_types = type.types.to_set - [T::Utils.coerce(NilClass)]
        raise 'TODO: generic union types' if possible_types.size > 1

        convert_str(value, possible_types.first)
      elsif type == String
        value
      elsif type == Symbol
        value.to_sym
      elsif type == Integer
        value.to_i
      elsif type == Float
        value.to_f
      else
        raise "Don't know how to convert a string to #{type}"
      end
    end

    sig { params(argv: T::Array[String]).returns(T.attached_class) }
    def self.parse(argv)
      values = {}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{program_name} [opts]"
        opts.on('-h', '--help', 'Prints this help') do
          puts opts
          exit
        end

        fields.each do |name, o|
          args = []
          if o.type == T::Boolean
            args << "-#{o.short}" if o.short
            args << "--[no-]#{o.long}" if o.long
          else
            args << "-#{o.short}#{o.get_placeholder}"
            args << "--#{o.long}=#{o.get_placeholder}"
          end
          args << o.description if o.description
          opts.on(*args) do |v|
            values[name] = v
          end
        end
      end.parse(argv)

      o = new
      fields.each do |name, opts|
        if opts.type == T::Boolean
          o.define_singleton_method(name) { !!values.fetch(name, false) }
        elsif values.include?(name)
          o.define_singleton_method(name) { Sprinkles::Opts::GetOpt.convert_str(values.fetch(name), opts.type) }
        elsif !opts.factory.nil?
          v = T.must(opts.factory).call
          o.define_singleton_method(name) { v }
        elsif opts.optional?
          o.define_singleton_method(name) { nil }
        else
          raise "Expected a value for #{name}"
        end
      end
      o
    end

    sig { returns(T.attached_class) }
    def self.parse!
      parse(ARGV)
    end
  end
end
