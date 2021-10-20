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

    sig { overridable.returns(String) }
    def self.program_name
      $PROGRAM_NAME
    end

    class Option < T::Struct
      extend T::Sig

      const :name, Symbol
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

      sig { returns(T::Boolean) }
      def positional?
        short.nil? && long.nil?
      end

      sig { returns(T::Boolean) }
      def repeated?
        type.is_a?(T::Types::TypedArray) || type.is_a?(T::Types::TypedSet)
      end

      sig { params(default: String).returns(String) }
      def get_placeholder(default='VALUE')
        if type.is_a?(Class) && type < T::Enum
          # if the type is an enum, we can enumerate the possible
          # values in a rich way
          possible_values = type.values.map(&:serialize).join("|")
          return "<#{possible_values}>"
        end

        placeholder || default
      end

      sig { returns(T::Array[String]) }
      def optparse_args
        args = []
        if type == T::Boolean
          args << "-#{short}" if short
          args << "--[no-]#{long}" if long
        else
          args << "-#{short}#{get_placeholder}" if short
          args << "--#{long}=#{get_placeholder}" if long
        end
        args << description if description
        args
      end
    end

    # for appeasing Sorbet, even though this isn't how we're using the
    # props methods. (we're also not allowing `prop` at all, only
    # `const`.)
    sig { params(rest: T.untyped).returns(T.untyped) }
    def self.decorator(*rest); end

    sig { returns(T::Array[Option]) }
    private_class_method def self.fields
      @fields = T.let(@fields, T.nilable(T::Array[Option]))
      @fields ||= []
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
      # we don't want to let the user pass in nil explicitly, so the
      # default values here are all '' instead, but we will treat ''
      # as if the argument was not provided
      short = nil if short.empty?
      long = nil if long.empty?

      placeholder = nil if placeholder.empty?

      opt = Option.new(
        name: name,
        type: type,
        short: short,
        long: long,
        factory: factory,
        placeholder: placeholder,
        description: description
      )
      validate!(opt)
      fields << opt
      self.define_method(name) { instance_variable_get("@#{name}") }
    end

    sig { params(opt: Option).void }
    private_class_method def self.validate!(opt)
      raise 'Do not start options with -' if opt.short&.start_with?('-')
      raise 'Do not start options with -' if opt.long&.start_with?('-')
      if (opt.short == 'h') || (opt.long == 'help')
        raise <<~RB
          The options `-h` and `--help` are reserved by Sprinkles::Opts::GetOpt
        RB
      end
      if !valid_type?(opt.type)
        raise "`#{opt.type}` is not a valid parameter type"
      end

      # the invariant we want to keep is that all mandatory positional
      # fields come first while all optional positional fields come
      # after: this makes matching up positional fields a _lot_ easier
      # and less surprising
      if opt.positional? && opt.optional?
        @seen_optional_positional = T.let(true, T.nilable(TrueClass))
      end

      if opt.positional? && @seen_repeated_positional
        raise "The positional parameter `#{opt.name}` comes after the "\
              "repeated parameter `#{@seen_repeated_positional.name}`"
      end

      if opt.positional? && opt.repeated?
        if @seen_optional_positional
          raise "The repeated parameter `#{opt.name}` comes after an "\
                "optional parameter."
        end

        @seen_repeated_positional = T.let(opt, T.nilable(Option))
      end

      if opt.positional? && !opt.optional? && @seen_optional_positional
        # this means we're looking at a _mandatory_ positional field
        # coming after an _optional_ positional field. To make things
        # easy, we simply reject this case.
        prev = fields.select {|f| f.positional? && f.optional?}
        prev = prev.map {|f| "`#{f.name}`"}.to_a.join(", ")
        raise "`#{opt.name}` is a mandatory positional field "\
              "but it comes after the optional field(s) #{prev}"
      end
    end

    sig { params(type: T.untyped).returns(T::Boolean) }
    private_class_method def self.valid_type?(type)
      type = type.raw_type if type.is_a?(T::Types::Simple)
      # true if the type is one of the valid types
      return true if type == String || type == Symbol || type == Integer || type == Float || type == T::Boolean
      # allow enumeration types
      return true if type.is_a?(Class) && type < T::Enum
      # true if it's a nilable valid type
      if type.is_a?(T::Types::Union)
        other_types = type.types.to_set - [T::Utils.coerce(NilClass)]
        return false if other_types.size > 1
        return valid_type?(other_types.first)
      elsif type.is_a?(T::Types::TypedArray) || type.is_a?(T::Types::TypedSet)
        return valid_type?(type.type)
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
      elsif type.is_a?(Class) && type < T::Enum
        type.deserialize(value)
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

    sig { params(values: T::Hash[Symbol, T::Array[String]]).returns(T.attached_class) }
    private_class_method def self.build_config(values)
      o = new
      serialized = {}
      fields.each do |field|
        if field.type == T::Boolean
          default = false
          default = field.factory&.call if !field.factory.nil?
          v = !!values.fetch(field.name, [default]).fetch(0)
        elsif values.include?(field.name)
          begin
            if !field.repeated?
              val = values.fetch(field.name).fetch(0)
              v = Sprinkles::Opts::GetOpt.convert_str(val, field.type)
            else
              v = values.fetch(field.name).map do |val|
                Sprinkles::Opts::GetOpt.convert_str(val, field.type.type)
              end
              # we allow both arrays and sets but we use arrays
              # internally, so convert to a set just in case
              v = v.to_set if field.type.is_a?(T::Types::TypedSet)
            end
          rescue KeyError => exn
            usage!("Invalid value `#{val}` for field `#{field.name}`:\n  #{exn.message}")
          end
        elsif !field.factory.nil?
          v = T.must(field.factory).call
        elsif field.optional?
          v = nil
        elsif field.repeated?
          if field.type.is_a?(T::Types::TypedArray)
            v = []
          else
            v = Set.new
          end
        else
          usage!("Expected a value for `#{field.name}`")
        end
        o.instance_variable_set("@#{field.name}", v)
        serialized[field.name] = v
      end
      o.define_singleton_method(:_serialize) {serialized}
      o
    end

    sig { params(argv: T::Array[String]).returns(T::Hash[Symbol, T::Array[String]]) }
    private_class_method def self.match_positional_fields(argv)
      pos_fields = fields.select(&:positional?).reject(&:repeated?)
      total_positional = pos_fields.size
      min_positional = total_positional - pos_fields.count(&:optional?)

      pos_values = T::Hash[Symbol, T::Array[String]].new

      usage!("Not enough arguments!") if argv.size < min_positional
      if argv.size > total_positional
        # we only want to warn about too many args if there isn't a
        # repeated arg to grab them
        usage!("Too many arguments!") if !fields.select(&:positional?).any?(&:repeated?)

        # we verify on construction that there's at most one
        # positional repeated field, and we don't intermingle repeated
        # and optional fields
        rest = T.must(fields.find {|f| f.positional? && f.repeated?})
        pos_values[rest.name] = argv.drop(total_positional)
      end

      pos_fields.zip(argv).each do |field, arg|
        next if arg.nil?
        pos_values[field.name] = [arg]
      end

      pos_values
    end

    sig { params(msg: String).void }
    private_class_method def self.usage!(msg='')
      raise <<~RB if @opts.nil?
        Internal error: tried to call `usage!` before building option parser!
      RB

      puts msg if !msg.empty?
      puts @opts
      exit
    end

    sig { returns(String) }
    private_class_method def self.cmdline
      cmd_line = T::Array[String].new
      field_count = 0
      # first, all the positional fields
      fields.each do |field|
        next if !field.positional?
        field_count += 1
        field_name = field.get_placeholder(field.name.to_s.upcase)
        if field.optional?
          cmd_line << "[#{field_name}]"
        elsif field.repeated?
          cmd_line << "[#{field_name} ...]"
        else
          cmd_line << field_name
        end
      end
      # next, the non-positional but mandatory flags
      # (leaving the optional flags for the other help)
      fields.each do |field|
        next if field.positional? || field.optional? || field.repeated?
        field_count += 1
        if field.long
          cmd_line << "--#{field.long}=#{field.get_placeholder}"
        else
          cmd_line << "-#{field.short}#{field.get_placeholder}"
        end
      end

      # then the repeated fields, which the special `...` to denote
      # their repetition
      fields.each do |field|
        next if !field.repeated?
        field_count += 1
        if field.long
          cmd_line << "[--#{field.long}=#{field.get_placeholder} ...]"
        else
          cmd_line << "[-#{field.short}#{field.get_placeholder} ...]"
        end
      end

      # we'll only add the final [OPTS...] if there are other things
      # we haven't listed yet
      cmd_line << "[OPTS...]" if fields.size > field_count
      cmd_line.join(" ")
    end

    sig { params(argv: T::Array[String]).returns(T.attached_class) }
    def self.parse(argv=ARGV)
      # we're going to destructively modify this
      argv = argv.clone

      values = T::Hash[Symbol, T::Array[String]].new
      parser = OptionParser.new do |opts|
        @opts = T.let(opts, T.nilable(OptionParser))
        opts.banner = "Usage: #{program_name} #{cmdline}"
        opts.on('-h', '--help', 'Print this help') do
          usage!
        end

        fields.each do |field|
          next if field.positional?
          opts.on(*field.optparse_args) do |v|
            if field.repeated?
              (values[field.name] ||= []) << v
            else
              values[field.name] = [v]
            end
          end
        end
      end.parse!(argv)

      values.merge!(match_positional_fields(argv))

      build_config(values)
    end
  end
end
