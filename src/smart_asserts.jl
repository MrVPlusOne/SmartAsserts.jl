const _ENABLED = Ref(true)

"""
Calling `SmartAsserts.set_enabled(false)` will make all future `@smart_assert` 
be compiled into no-ops. Hence, simply call this at the beginning of your module 
to disable all `@smart_asserts` in your project. 
(You might also want to call `SmartAsserts.set_enabled(true)` at the end of your 
module to not accidentally turn off others' `@smart_asserts`).
"""
function set_enabled(value::Bool)
    _ENABLED[] = value
end

"""
Evaluate a boolean expression, and if it is false, also try to show additional information
to explain why it's false.

Returns `(value::Bool, reason::Union{Nothing, String})`
"""
macro show_assertion(ex)
    _show_assertion(ex)
end

function _show_assertion(ex)
    ex_type = if Meta.isexpr(ex, :(<:))
        args = ex.args
        :type_assert
    elseif ex.head == :call
        op, pos_args, kw_args = group_function_args(ex.args)
        args = tuple(pos_args..., getindex.(kw_args, 2)...)
        kw_names = getindex.(kw_args, 1)
        :func_call
    elseif ex.head == :comparison
        args = Tuple(e for (i, e) in enumerate(ex.args) if isodd(i))
        ops = Tuple(e for (i, e) in enumerate(ex.args) if iseven(i))
        :comparison
    else
        :other
    end

    ex_q = QuoteNode(ex)
    if ex_type == :other
        :($(esc(ex)), "Condition `$($ex_q)` failed.")
    else
        args_q = Expr(:tuple, QuoteNode.(args)...)
        arg_names = [gensym("arg$i") for i in 1:length(args)]

        cond_ex = if ex_type == :type_assert
            Expr(:(<:), arg_names...)
        elseif ex_type == :func_call
            n_pos_args = length(pos_args)
            Expr(
                :call,
                esc(op),
                Expr(
                    :parameters,
                    (
                        Expr(:kw, k, v) for
                        (k, v) in zip(kw_names, arg_names[(n_pos_args + 1):end])
                    )...,
                ),
                arg_names[1:n_pos_args]...,
            )
        elseif ex_type == :comparison
            comp_args = (
                isodd(i) ? arg_names[1 + i ÷ 2] : ops[i ÷ 2] for i in eachindex(ex.args)
            )
            Expr(:comparison, comp_args...)
        else
            error("This should not be reached.")
        end

        assigns = Expr(
            :block, (Expr(:(=), n, esc(e)) for (n, e) in zip(arg_names, args))...
        )
        args_tuple = Expr(:tuple, arg_names...)

        quote
            $assigns
            if !$(cond_ex)
                eval_string = join(
                    [
                        "\t`$ex` evaluates to $val" for
                        (ex, val) in zip($args_q, $args_tuple)
                        if string(ex) != string(val)
                    ],
                    "\n",
                )
                reason_text = "Condition `$($ex_q)` failed due to:\n" * eval_string
                (false, reason_text)
            else
                (true, nothing)
            end
        end
    end
end

"""
Group the args part of a function call Expr into 3 parts: the operator, 
the positional args, and the keyword args. 
"""
function group_function_args(args)
    op = args[1]
    has_kw_params = length(args) > 1 && args[2] isa Expr && args[2].head == :parameters

    pos_args = []
    kw_args = Pair{Symbol}[]
    rest_args = has_kw_params ? args[3:end] : args[2:end]
    for a in rest_args
        if a isa Expr && a.head == :kw
            push!(kw_args, (a.args[1] => a.args[2]))
        else
            push!(pos_args, a)
        end
    end
    if has_kw_params
        for a in args[2].args
            pair = if a isa Symbol
                a => a
            else
                @assert a isa Expr
                if a.head == :kw
                    a.args[1] => a.args[2]
                elseif a.head == :.
                    @assert a.args[2] isa QuoteNode
                    a.args[2].value => a
                else
                    error("Unsupported expression in keyword parameters: $a")
                end
            end
            push!(kw_args, pair)
        end
    end
    op, pos_args, kw_args
end

"""
Like @assert, but try to also print out additional information about the arguments.
Note that each argument is only evaluated once, so there is no extra overhead compared 
to a normal assert.

Currently, additional information will be returned for the following types of expressions:

- function calls: e.g., `a <= b`, `bool_f(a,k1=...; k2...)`

- type asserts: e.g., `Type1 <: Type2`

- comparison expressions: e.g., `a == b <= c + d <= e`

See also [`SmartAsserts.set_enabled`](@ref) on how to disable `@smart_assert`s 
at compile-time.

## Examples
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
 ...
```
"""
macro smart_assert(ex, msg=nothing)
    if !_ENABLED[]
        return :(nothing)
    end

    has_msg = msg !== nothing
    r_ex = _show_assertion(ex)

    quote
        (result, reason) = $r_ex
        error_msg = $has_msg ? "$($(esc(msg)))\nCaused by $reason" : reason
        if !result
            throw(AssertionError(error_msg))
        end
    end |> Base.remove_linenums!
end
