using SmartAsserts: @smart_assert, @show_assertion, group_function_args
using Test

@testset "SmartAsserts.jl" begin

    @test group_function_args(:(f(x1; kw1=1, kw2, a.kw3, kw4=2)).args) ==
        (:f, Any[:x1], Pair[:kw1 => 1, :kw2 => :kw2, :kw3 => :(a.kw3), :kw4 => 2])

    @test begin
        @smart_assert 1 < 2
        @smart_assert 1 == 1 "This should pass"
        @smart_assert ≈(1, 1.2, atol=0.4) "This should pass"
        true
    end

    @test_throws AssertionError begin
        a = 5
        @smart_assert a < 1
    end

    @test_throws AssertionError begin
        a = 5
        @smart_assert a < 1 "This should fail. 2a = $(2 * a)"
    end

    @test_throws AssertionError begin
        @smart_assert ≈(1, 1.2, atol=0.1; rtol=0.1)
    end

    @test begin
        a = 5
        occursin("`a` evaluates to 5", @show_assertion(a < 1)[2])
    end

    @test begin
        occursin(
            "`reverse([1, 1, 2])` evaluates to [2, 1, 1]",
            @show_assertion(allunique(reverse([1, 1, 2])))[2],
        )
    end

    @test begin
        f_with_kw(a; b, c) = a == b + c
        c = 2
        reason = @show_assertion(f_with_kw(4, b=1; c))[2]
        occursin("`4` evaluates to 4", reason) &&
            occursin("`c` evaluates to 2", reason) &&
            occursin("`1` evaluates to 1", reason)
    end

    @test begin
        a = 1
        b = 3
        reason = @show_assertion(a <= b <= (b - 1))[2]
        occursin("`a` evaluates to 1", reason) &&
            occursin("`b` evaluates to 3", reason) &&
            occursin("`b - 1` evaluates to 2", reason)
    end
end
