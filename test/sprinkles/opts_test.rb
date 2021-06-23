# typed: true

require "test_helper"
require "sprinkles/opts"

module Sprinkles
  class GetOptTest < Minitest::Test
    class SimpleOpt < S::Opts::GetOpt
      sig {override.returns(String)}
      def self.program_name; "simple-opt"; end

      const :input, String, short: 'i', long: 'input', placeholder: "QUUX"
      const :verbose, T::Boolean, short: 'v', long: 'verbose'
    end

    def test_getopt_short
      opts = SimpleOpt.parse(["-i", "foo"])
      assert_equal("foo", opts.input)
    end

    def test_getopt_long
      opts = SimpleOpt.parse(["--input=foo"])
      assert_equal("foo", opts.input)
    end

    def test_getopt_flag_short
      opts = SimpleOpt.parse(["-v", "--input=foo"])
      assert_equal(true, opts.verbose)

      opts = SimpleOpt.parse(["--input=foo"])
      assert_equal(false, opts.verbose)
    end

    def test_getopt_flag_long
      opts = SimpleOpt.parse(["--verbose", "--input=foo"])
      assert_equal(true, opts.verbose)

      opts = SimpleOpt.parse(["--input=foo"])
      assert_equal(false, opts.verbose)
    end

    def test_getopt_usage
      out_buf = StringIO.new
      begin
        $stdout = out_buf
        SimpleOpt.parse(["--help"])
        $stdout = STDOUT
      rescue SystemExit
        help_text = out_buf.string
        assert(help_text.include?("Usage: simple-opt [opts]"))
        assert(help_text.include?("-i, --input=QUUX"))
        assert(help_text.include?("-v, --[no-]verbose"))
      end
    end


    class RichTypes < S::Opts::GetOpt
      sig {override.returns(String)}
      def self.program_name; "rich-types"; end

      const :my_symbol, Symbol, short: 's', long: 'symbol'
      const :my_integer, Integer, short: 'i', long: 'integer'
      const :my_float, Float, short: 'f', long: 'float'
    end

    def test_rich_types
      opts = RichTypes.parse(["-s", "foo", "-i", "52", "-f", "2.3"])
      assert_equal(:foo, opts.my_symbol)
      assert_equal(52, opts.my_integer)
      assert_equal(2.3, opts.my_float)
    end


    class Optional < S::Opts::GetOpt
      sig {override.returns(String)}
      def self.program_name; "rich-types"; end

      const :opt_string, T.nilable(String), short: 'a'
      const :def_string, String, short: 'b', factory: ->{'foo'}

      const :opt_symbol, T.nilable(Symbol), short: 'c'
      const :def_symbol, Symbol, short: 'd', factory: ->{:bar}

      const :opt_integer, T.nilable(Integer), short: 'e'
      const :def_integer, Integer, short: 'f', factory: ->{55}
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
      opts = Optional.parse(%w{-a one -b two -c three -d four -e 99 -f 100})

      assert_equal('one', opts.opt_string)
      assert_equal('two', opts.def_string)

      assert_equal(:three, opts.opt_symbol)
      assert_equal(:four, opts.def_symbol)

      assert_equal(99, opts.opt_integer)
      assert_equal(100, opts.def_integer)
    end
  end
end
