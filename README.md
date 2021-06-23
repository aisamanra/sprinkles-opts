# sprinkles-opts

The `sprinkles-opts` library is a convenient Sorbet-aware way of doing
argument parsing.

## Basic Usage

Create a class that is a subclass of `S::Opts::GetOpt`. Define fields and their types with `const`, analogously to [how you would with `T::Struct`](), but give those fields either `short:` or `long:` options, or possibly both, which correspond to the command-line flags. You'll also have to provide a value for `program_name` by overriding an abstract method:

```ruby
class MyOptions < S::Opts::GetOpt
  sig {override.returns(String)}
  def self.program_name; "my-program"; end

  const :input, String, short: 'i', long: 'input'
  const :num_iterations, Integer, short: 'n', placeholder: 'N'
  const :verbose, T::Boolean, short: 'v', long: 'verbose'
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

Every field needs at least a `short:` or a `long:` name, but it's not necessary to have both.

## Optional Arguments

There are two ways of making arguments optional:
- A field whose type is marked as `T.nilable` will implicitly be initialized as `nil` if it is not provided.
- A field can have a `factory:` which should be a lambda that will be called to initialize the field if the argument is not provided.

Fields that are not `T.nilable` and do not have a `factory:` must be provided when parsing arguments.

## Help text and descriptions

The option names `-h` and `--help` are reserved, and when they are provided the program will print a usage panel and exit:

```
Usage: my-program [opts]
    -h, --help                       Prints this help
    -i, --input=VALUE
    -n, --num-iterations=N
    -v, --[no-]verbose
```

Individual fields can customize their default placeholder text away from the default `VALUE` using the `placeholder:` argument, and can provide more extensive descriptions using the `description:` argument.

## Why sprinkles?

Well, for one, because it's a sorbet topping. For another, it corresponds to `S::`, another terse namespace can be analogous to Sorbet's `T::`, while never conflicting with anything that Sorbet might add in the future.
