# typed: true
# frozen_string_literal: true

require 'test_helper'
require 'sprinkles/opts'

module Sprinkles
  class GetOptTest < Minitest::Test
    extend T::Sig

    sig {params(blk: T.proc.void).returns(String)}
    def capture_usage(&blk)
      out_buf = StringIO.new
      begin
        $stdout = out_buf
        yield
      rescue SystemExit
        $stdout = STDOUT
      end
      help_text = out_buf.string
      return help_text
    end

    class SimpleOpt < Sprinkles::Opts::GetOpt
      sig { override.returns(String) }
      def self.program_name
        'simple-opt'
      end

      const :input, String, short: 'i', long: 'input', placeholder: 'QUUX'
      const :verbose, T::Boolean, short: 'v', long: 'verbose'
    end

    def test_getopt_short
      opts = SimpleOpt.parse(['-i', 'foo'])
      assert_equal('foo', opts.input)
    end

    def test_getopt_long
      opts = SimpleOpt.parse(['--input=foo'])
      assert_equal('foo', opts.input)
    end

    def test_getopt_flag_short
      opts = SimpleOpt.parse(['-v', '--input=foo'])
      assert_equal(true, opts.verbose)

      opts = SimpleOpt.parse(['--input=foo'])
      assert_equal(false, opts.verbose)
    end

    def test_getopt_flag_long
      opts = SimpleOpt.parse(['--verbose', '--input=foo'])
      assert_equal(true, opts.verbose)

      opts = SimpleOpt.parse(['--input=foo'])
      assert_equal(false, opts.verbose)
    end

    def test_getopt_usage
      help_text = capture_usage { SimpleOpt.parse(['--help']) }

      assert(help_text.include?('Usage: simple-opt [opts]'))
      assert(help_text.include?('-i, --input=QUUX'))
      assert(help_text.include?('-v, --[no-]verbose'))
    end

    class Positional < Sprinkles::Opts::GetOpt
      sig { override.returns(String) }
      def self.program_name
        'positional'
      end

      const :first, String
      const :second, Integer
      const :third, T.nilable(Symbol)
    end

    def test_positional_params
      opts = Positional.parse(%w[one 2 three])
      assert_equal('one', opts.first)
      assert_equal(2, opts.second)
      assert_equal(:three, opts.third)

      opts = Positional.parse(%w[one 2])
      assert_equal('one', opts.first)
      assert_equal(2, opts.second)
      assert_nil(opts.third)
    end

    def test_positional_errors
      msg = capture_usage { Positional.parse(%w[one]) }
      assert(msg.include?('Not enough arguments'))

      msg = capture_usage { Positional.parse(%w[one 2 three four]) }
      assert(msg.include?('Too many arguments'))
    end


    class RichTypes < Sprinkles::Opts::GetOpt
      sig { override.returns(String) }
      def self.program_name
        'rich-types'
      end

      const :my_symbol, Symbol, short: 's', long: 'symbol'
      const :my_integer, Integer, short: 'i', long: 'integer'
      const :my_float, Float, short: 'f', long: 'float'
    end

    def test_rich_types
      opts = RichTypes.parse(['-s', 'foo', '-i', '52', '-f', '2.3'])
      assert_equal(:foo, opts.my_symbol)
      assert_equal(52, opts.my_integer)
      assert_equal(2.3, opts.my_float)
    end

    class Optional < Sprinkles::Opts::GetOpt
      sig { override.returns(String) }
      def self.program_name
        'rich-types'
      end

      const :opt_string, T.nilable(String), short: 'a'
      const :def_string, String, short: 'b', factory: -> { 'foo' }

      const :opt_symbol, T.nilable(Symbol), short: 'c'
      const :def_symbol, Symbol, short: 'd', factory: -> { :bar }

      const :opt_integer, T.nilable(Integer), short: 'e'
      const :def_integer, Integer, short: 'f', factory: -> { 55 }
    end

    def test_nilable_with_nil
      opts = Optional.parse([])

      assert_nil(nil, opts.opt_string)
      assert_equal('foo', opts.def_string)

      assert_nil(opts.opt_symbol)
      assert_equal(:bar, opts.def_symbol)

      assert_nil(opts.opt_integer)
      assert_equal(55, opts.def_integer)
    end

    def test_nilable_with_values
      opts = Optional.parse(%w[-a one -b two -c three -d four -e 99 -f 100])

      assert_equal('one', opts.opt_string)
      assert_equal('two', opts.def_string)

      assert_equal(:three, opts.opt_symbol)
      assert_equal(:four, opts.def_symbol)

      assert_equal(99, opts.opt_integer)
      assert_equal(100, opts.def_integer)
    end

    class MyEnum < T::Enum
      enums do
        One = new('one')
        Two = new('two')
      end
    end

    class OptsWithEnum < Sprinkles::Opts::GetOpt
      sig { override.returns(String) }
      def self.program_name; "opts-with-enum"; end

      const :value, MyEnum, long: "value"
    end

    def test_usage_string_for_enums
      help_text = capture_usage { OptsWithEnum.parse(['--help']) }
      assert(help_text.include?('--value=[one|two]'))
    end

    def test_enum_values
      opts = OptsWithEnum.parse(%w[--value=one])
      assert_equal(MyEnum::One, opts.value)

      opts = OptsWithEnum.parse(%w[--value=two])
      assert_equal(MyEnum::Two, opts.value)

      msg = assert_raises(KeyError) do
        opts = OptsWithEnum.parse(%w[--value=seventeen])
      end
      msg = T.cast(msg, KeyError)
      assert(msg.message.include?('key not found: "seventeen"'))
    end

    def test_disallow_leading_short_hyphens
      msg = assert_raises(RuntimeError) do
        Class.new(Sprinkles::Opts::GetOpt) do
          T.unsafe(self).const(:foo, String, short: '-f')
        end
      end
      msg = T.cast(msg, RuntimeError)
      assert(msg.message.include?('Do not start options with -'))
    end

    def test_disallow_leading_long_hyphens
      msg = assert_raises(RuntimeError) do
        Class.new(Sprinkles::Opts::GetOpt) do
          T.unsafe(self).const(:foo, String, long: '--foo')
        end
      end
      msg = T.cast(msg, RuntimeError)
      assert(msg.message.include?('Do not start options with -'))
    end

    def test_disallow_help
      msg = assert_raises(RuntimeError) do
        Class.new(Sprinkles::Opts::GetOpt) do
          T.unsafe(self).const(:foo, String, short: 'h')
        end
      end
      msg = T.cast(msg, RuntimeError)
      assert(msg.message.include?('The options `-h` and `--help` are reserved'))
    end

    def test_disallow_bad_types
      msg = assert_raises(RuntimeError) do
        Class.new(Sprinkles::Opts::GetOpt) do
          T.unsafe(self).const(:foo, Proc, long: 'foo')
        end
      end
      msg = T.cast(msg, RuntimeError)
      assert_equal('`Proc` is not a valid parameter type', msg.message)
    end
  end
end
