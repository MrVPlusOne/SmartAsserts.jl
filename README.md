# SmartAsserts

[![Run tests](https://github.com/MrVPlusOne/SmartAsserts.jl/actions/workflows/test.yml/badge.svg)](https://github.com/MrVPlusOne/SmartAsserts.jl/actions/workflows/test.yml)


A `@smart_assert` macro that automatically prints out argument values upon assertion failure, used to replace the standard `@assert`. Unlike `@assert`, these smart assertions can also be easily turned off at compile-time.

## Example Usages

A (failed) binary inequality assertion:
```julia
julia> let a = 5
           @smart_assert a < 1
       end
ERROR: AssertionError: Condition `a < 1` failed due to:
        `a` evaluates to 5
        `1` evaluates to 1
Stacktrace:
 [1] top-level scope
   @ REPL[156]:2
```

Functions with keyword arguments are also supported:
```julia
julia> let a = 1.0, rtol=0.1
           @smart_assert isapprox(a, sin(a), atol=0.05; rtol)
       end
ERROR: AssertionError: Condition `isapprox(a, sin(a), atol = 0.05; rtol)` failed due to:
        `a` evaluates to 1.0
        `sin(a)` evaluates to 0.8414709848078965
        `0.05` evaluates to 0.05
        `rtol` evaluates to 0.1
Stacktrace:
 [1] top-level scope
   @ REPL[177]:2
```

Like `@assert`, you can also provide an additional message as the second argument:
```julia
julia> let a = 5
           @smart_assert a < 1 "This should fail. 2a = $(2 * a)"
       end
ERROR: AssertionError: This should fail. 2a = 10
Caused by Condition `a < 1` failed due to:
        `a` evaluates to 5
        `1` evaluates to 1
Stacktrace:
 [1] top-level scope
   @ REPL[167]:2
```

## How it works
Under the hood, an expression like `@smart_assert f(<ex1>, <ex2>)` is expanded by the macro into something like the following (with newly introduced variables renamed by macro hygiene)
```julia
quote
    arg1 = <ex1>
    arg2 = <ex2>
    if !(f(arg1, arg2))
        eval_string = Main.join(["\t`$(ex)` evaluates to $(val)" for (ex, val) in Main.zip((<ex1>, <ex2>), (arg1, arg2))], "\n")
        reason_text = "Condition `f(<ex1>, <ex2>)` failed due to:\n" * eval_string
        Main.throw(Main.AssertionError(reason))
    end
end
```

Note that a new local variable (`arg1` and `arg2`) is introduced for each expression to ensure that all expressions are only evaluated once. Thus, when the assertion fails, the original values that caused the assertion condition to fail will be printed out, avoiding re-evaluation.

## Supported Syntax
Currently, additional information will be printed out for the following types of expressions:
- function calls: e.g., `a <= b`, `bool_f(a,k1=...; k2...)`

- type asserts: e.g., `Type1 <: Type2`

- comparison expressions: e.g., `a == b <= c + d <= e`

For other cases, only the original condition expression will be printed but not their argument information.

## Turning off the assertions (at compile-time)
All `@smart_assert`s inside a module `M` can be statically turned off by adding the constant definition `const ENABLE_ASSERTIONS = false` at the beginning of `M`'s body.

For example, no error will be thrown in the following example because when `@smart_assert 1 + 1 == 3` is executed, `ENABLE_ASSERTIONS = false` is already defined inside `M`.
```julia
module M
    using SmartAsserts
    # this turns off all subsequent @smart_assert calls
    const ENABLE_ASSERTIONS = false 
    
    @smart_assert 1 + 1 == 3
end
```

Note that if `ENABLE_ASSERTIONS` is not a compile-time constant, the assertions will still be turned off, but there will be a small overhead since each assertion will have a run-time `if` check in its generated code.
