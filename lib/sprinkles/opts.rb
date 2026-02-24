# typed: strict
# frozen_string_literal: true

require "optparse"
require "set"
require "sorbet-runtime"

# :nodoc:
module Sprinkles
  # :nodoc:
  module Opts
    # @abstract A class that inherits from `GetOpt` represents a value
    #   derived from command-like arguments, where how to extract each
    #   field is determined by the extra parameters given on the field
    #   definition. Subclass this and use one or more calls to `#const`
    #   to define fields.
    class GetOpt
      # A `ValiationError` represents a user error in defining a
      # `GetOpt` field.
      class ValidationError < Exception
        extend T::Sig

        sig { params(message: String, name: Symbol).void }
        # @param [String] message the exception message
        # @param [Symbol] name the field being defined when this error was raised
        def initialize(message, name)
          @name = name
          super("In definition of #{name}: #{message}")
        end

        sig { returns(Symbol) }
        # @return [Symbol] the name of the field being defined when this error was
        #   raised.
        attr_reader :name
      end

      # An `InternalError` represents an internal invariant having
      # been violated. This should generally not be seen.
      class InternalError < Exception
      end

      extend T::Sig
      extend T::Helpers
      abstract!

      sig { overridable.returns(String) }
      # The name of the program, as written in the help output. This
      # defaults to `$PROGRAM_NAME` but can be overridden if desired.
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
        def get_placeholder(default = "VALUE")
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
      private_class_method def self.decorator(*rest)
      end

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
      # The `const(name, type, ...)` method will define an accessor
      # method called `name` which contains a value of type `type`,
      # and will be initialized when parsing the a command-like
      # argument list.
      #
      # The logic of how to parse a given field is as follows:
      #
      # - If `short:` or `long:` are provided, then the field's value will be
      #   derived from a flag.
      # - If neither `short:` nor `long:` are provided, then the field's value
      #   will be derived from positional parameters.
      # - If a field is not provided, either because the field was defined by
      #   flags which were not provided or because the field was positional and
      #   not enough positional arguments were passed, then what happens is
      #   determined by the following logic:
      #     - If a `factory:` argument is provided, then it will initialize the
      #       field with the result of calling the `factory:` proc.
      #     - If the field has a `T.nilable` type, then it will default to `nil`.
      #     - If the field has a `T::Array` or `T::Set` type, then it will default
      #       to an empty array or set.
      #     - Otherwise, it will raise an error.
      #
      # There are a few other special considerations for specific types:
      #
      # - If a field has the type `T::Boolean` and a `long:` option, then it will
      #   also get a corresponding flag that starts with `--no-` which sets the
      #   field to `false`.
      # - If a field has the type `T::Array` or `T::Set` and defines a long or short
      #   option, then that option can be provided multiple times and each invocation
      #   will add to that array or set.
      # - If a field has the type `T::Array` or `T::Set` and does not define any
      #   options, then it must also be the last positional parameter, and all remaining
      #   arguments will be added to that final array or set.
      #
      # @param [Symbol] name the name of the field to define
      # @param [Type] type the type of the field
      # @param [String] short the short option corresponding to this field
      #   (without a leading hyphen.) This must be exactly one character long.
      # @param [String] long the long option corresponding to this field
      #   (without leading hyphens.)
      # @param [Proc] factory a zero-argument proc used to initialize the
      #   value of this field if it is not otherwise provided
      # @param [String] placeholder the placeholder text to use in the
      #   `--help` output for the argument of this field
      # @param [String] description the description of this field as it
      #   will appear in the `--help` output
      def self.const(
        name,
        type,
        short: "",
        long: "",
        factory: nil,
        placeholder: "",
        description: "",
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
        if opt.short&.start_with?("-")
          raise ValidationError.new("Do not start options with -", opt.name)
        end

        if opt.long&.start_with?("-")
          raise ValidationError.new("Do not start options with -", opt.name)
        end

        if (opt.short == "h") || (opt.long == "help")
          raise(
            ValidationError.new(
              "The options `-h` and `--help` are reserved by Sprinkles::Opts::GetOpt",
              opt.name
            )
          )
        end

        if !valid_type?(opt.type)
          raise ValidationError.new("`#{opt.type}` is not a valid parameter type", opt.name)
        end

        # the invariant we want to keep is that all mandatory positional
        # fields come first while all optional positional fields come
        # after: this makes matching up positional fields a _lot_ easier
        # and less surprising
        if opt.positional? && opt.optional?
          @seen_optional_positional = T.let(true, T.nilable(TrueClass))
        end

        if opt.positional? && @seen_repeated_positional
          raise(
            ValidationError.new(
              "The positional parameter `#{opt.name}` comes after the " \
                "repeated parameter `#{@seen_repeated_positional.name}`",
              opt.name
            )
          )
        end

        if opt.positional? && opt.repeated?
          if @seen_optional_positional
            raise(
              ValidationError.new(
                "The repeated parameter `#{opt.name}` comes after an " \
                  "optional parameter.",
                opt.name
              )
            )
          end

          @seen_repeated_positional = T.let(opt, T.nilable(Option))
        end

        if opt.positional? && !opt.optional? && @seen_optional_positional
          # this means we're looking at a _mandatory_ positional field
          # coming after an _optional_ positional field. To make things
          # easy, we simply reject this case.
          prev = fields.select { |f| f.positional? && f.optional? }
          prev = prev.map { |f| "`#{f.name}`" }.to_a.join(", ")

          raise(
            ValidationError.new(
              "`#{opt.name}` is a mandatory positional field " \
                "but it comes after the optional field(s) #{prev}",
              opt.name
            )
          )
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
      private_class_method def self.convert_str(value, type)
        type = type.raw_type if type.is_a?(T::Types::Simple)
        if type.is_a?(T::Types::Union)
          # Right now, the assumption is that this is mostly used for
          # `T.nilable`, but with a bit of work we maybe could support
          # other kinds of unions
          possible_types = type.types.to_set - [T::Utils.coerce(NilClass)]
          raise InternalError.new("TODO: generic union types") if possible_types.size > 1

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
          raise InternalError.new("Don't know how to convert a string to #{type}")
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
                v = convert_str(val, field.type)
              else
                v = values.fetch(field.name).map do |val|
                  convert_str(val, field.type.type)
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

        o.define_singleton_method(:_serialize) { serialized }
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
          rest = T.must(fields.find { |f| f.positional? && f.repeated? })
          pos_values[rest.name] = argv.drop(total_positional)
        end

        pos_fields.zip(argv).each do |field, arg|
          next if arg.nil?
          pos_values[field.name] = [arg]
        end

        pos_values
      end

      sig { params(msg: String).void }
      private_class_method def self.usage!(msg = "")
        if @opts.nil?
          raise(
            InternalError.new(
              "Internal error: tried to call `usage!` before building option parser!"
            )
          )
        end

        puts(msg) if !msg.empty?
        puts(@opts)
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
      # Parse the provided argument array according to the logic
      # encoded in the field declarations in this class.
      #
      # @param [T::Array[String]] argv the array of strings to parse
      def self.parse(argv = ARGV)
        # we're going to destructively modify this
        argv = argv.clone

        values = T::Hash[Symbol, T::Array[String]].new
        OptionParser
          .new do |opts|
            @opts = T.let(opts, T.nilable(OptionParser))
            opts.banner = "Usage: #{program_name} #{cmdline}"
            opts.on("-h", "--help", "Print this help") do
              usage!
            end

            fields.each do |field|
              next if field.positional?
              T.unsafe(opts).on(*field.optparse_args) do |v|
                if field.repeated?
                  (values[field.name] ||= []) << v
                else
                  values[field.name] = [v]
                end
              end
            end
          end
          .parse!(argv)

        values.merge!(match_positional_fields(argv))

        build_config(values)
      end

      private_constant :Option
    end
  end
end
