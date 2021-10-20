# sprinkles-opts

The `sprinkles-opts` library is a convenient Sorbet-aware way of doing
argument parsing.

## Basic usage

Create a class that is a subclass of `Spinkles::Opts::GetOpt`. Define fields and their types with `const`, analogously to [how you would with `T::Struct`](), but those fields can have `short:` and `long:` options that map to the flags used to provide them. You'll also have to provide a value for `program_name` by overriding an abstract method:

```ruby
class MyOptions < Sprinkles::Opts::GetOpt
  sig {override.returns(String)}
  def self.program_name; "my-program"; end

  const :input, String, short: 'i', long: 'input'
  const :num_iterations, Integer, short: 'n', placeholder: 'N'
  const :verbose, T::Boolean, short: 'v', long: 'verbose', factory: -> {false}
end
```

You can then call `MyOptions.parse(ARGV)` in order to get a value of type `MyOptions` with the defined fields initialized.

```ruby
opts = MyOptions.parse(%w{-i foo -n 8 --verbose})
assert_equal('foo', opts.input)
assert_equal(8, opts.num_iterations)
assert_equal(true, opts.verbose)
```

The field type will affect the behavior of the option parser. Fields whose type is `T::Boolean` are implicitly treated as flags that do not take more arguments, and a `T::Boolean` field with a long argument name like `--foo` will also automatically get a corresponding `--no-foo` which sets the flag to false. Values with other built-in types like `Symbol` or `Integer` will be converted to the appropriate type.

Fields without a `short:` or `long:` parameter will be understood to be positional arguments. Ordering is important here: positional arguments will be filled in the order that they appear in the definition.

```ruby
class PosOptions < Sprinkles::Opts::GetOpt
  sig {override.returns(String)}
  def self.program_name; "positional-options"; end

  const :source, String
  const :destination, String
end

opts = PosOptions.parse(%w{this that})
assert_equal('this', opts.source)
assert_equal(that, opts.destination)
```

Parsing will fail and exit the program with a usage statement if either too many or too few positional parameters are provided.

```ruby
opts = PosOptions.parse(%w{this})
# this will exit and print the following:
# Not enough arguments!
# Usage: positional-options SOURCE DESTINATION
#     -h, --help                       Prints this help
```

## Optional arguments

There are two ways of making arguments optional:
- A field whose type is marked as `T.nilable` will implicitly be initialized as `nil` if it is not provided.
- A field can have a `factory:` which should be a lambda that will be called to initialize the field if the argument is not provided.

Fields that are not `T.nilable` and do not have a `factory:` must be provided when parsing arguments.

For _positional_ arguments, there's currently an extra restriction: all mandatory positional arguments _must come first_, and will throw a definition-time error if they appear later. This means that positional parameters are matched in-order as they appear, and once we're out of positional parameters the remaining optional parameters will be initialized to `nil` (for `T.nilable` fields) or their provided defaults (if they have a `factory:` parameter.)

```ruby
class PosOptions < Sprinkles::Opts::GetOpt
  sig {override.returns(String)}
  def self.program_name; "positional-options"; end

  const :a, String
  const :b, T.nilable(String)
  const :c, T.nilable(String)
end

PosOptions.parse(%w{1 2 3})  # a is 1, b is 2, c is 3
PosOptions.parse(%w{1 2})    # a is 1, b is 2, c is nil
PosOptions.parse(%w{1})      # a is 1, b is nil, c is nil
```

It is still an error to pass too few positional parameters (i.e. fewer than there are mandatory positional parameters) or too many (i.e. more than there are total positional parameters, mandatory and optional).

## Repeated arguments

Fields whose types are either `T::Array[...]` or `T::Set[...]` are implicitly treated as repeated fields.

When a positional field has type `T::Array[...]` or `T::Set[...]`, then it is subject to two major restrictions:
- It must be the last positional field specified, which also implies that it must be the _only_ repeated positional field.
- None of the other fields can be optional.

The second restriction is because of the ambiguity as to where extra fields go when choosing how to fill in optional fields, but may eventually be lifted in the future.

When a positional field is `T::Array[...]` or `T::Set[...]`, then any trailing arguments will be added to the array contained in that field. For example:

```ruby
class PosArray < Sprinkles::Opts::GetOpt
  const :a, Integer
  const :b, T::Array[String]
end

PosArray.parse(%w{1})      # a is 1, b is []
PosArray.parse(%w{1 2})    # a is 1, b is ['2']
PosArray.parse(%w{1 2 3})  # a is 1, b is ['2', '3']
```

When a non-positional field is `T::Array[...]` or `T::Set[...]`, then it can be specified multiple times (in any order) to add to that collection. For example:

```ruby
class OptArray < Sprinkles::Opts::GetOpt
  const :a, T::Array[Integer]
end

PosArray.parse(%w{})             # a is []
PosArray.parse(%w{-a 5})         # a is [5]
PosArray.parse(%w{-a 22 -a 33})  # a is [22, 33]
```

## Help text and descriptions

The option names `-h` and `--help` are reserved, and when they are provided the program will print a usage panel and exit:

```
Usage: my-program --input=VALUE -nN
    -h, --help                       Print this help
    -i, --input=VALUE
    -nN
    -v, --[no-]verbose
```

Individual fields can customize their default placeholder text away from the default `VALUE` using the `placeholder:` argument, and can provide more extensive descriptions using the `description:` argument.


## Why sprinkles?

Well, because it's a Sorbet topping. I have other unfinished ideas for how to leverage Sorbet to write certain abstractions, and my thought was that it might be nice to put them in a common namespace.
