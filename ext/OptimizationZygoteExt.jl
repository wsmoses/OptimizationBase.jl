module OptimizationZygoteExt

import OptimizationBase, OptimizationBase.ArrayInterface
import OptimizationBase.SciMLBase: OptimizationFunction
import OptimizationBase.LinearAlgebra: I
import DifferentiationInterface
import DifferentiationInterface: prepare_gradient, prepare_hessian, prepare_jacobian, gradient!, hessian!, jacobian!
using ADTypes, Zygote, Zygote.ChainRulesCore

function OptimizationBase.instantiate_function(f, x, adtype::ADTypes.AutoZygote, p = SciMLBase.NullParameters(), num_cons = 0)
    _f = (θ, args...) -> first(f.f(θ, p, args...))

    if f.grad === nothing
        extras_grad = prepare_gradient(_f, adtype, x)
        function grad(res, θ)
            gradient!(_f, res, adtype, θ, extras_grad)
        end
    else
        grad = (G, θ, args...) -> f.grad(G, θ, p, args...)
    end

    hess_sparsity = f.hess_prototype
    hess_colors = f.hess_colorvec
    if f.hess === nothing
        extras_hess = prepare_hessian(_f, DifferentiationInterface.SecondOrder(adtype), x) #placeholder logic, can be made much better
        function hess(res, θ, args...)
            hessian!(_f, res, adtype, θ, extras_hess)
        end
    else
        hess = (H, θ, args...) -> f.hess(H, θ, p, args...)
    end

    if f.hv === nothing
        hv = function (H, θ, v, args...)
            res = zeros(length(θ), length(θ))
            hess(res, θ, args...)
            H .= res * v
        end
    else
        hv = f.hv
    end

    if f.cons === nothing
        cons = nothing
    else
        cons = (res, θ) -> f.cons(res, θ, p)
        cons_oop = (x) -> (_res = Zygote.Buffer(x, num_cons); ChainRulesCore.@ignore_derivatives cons(_res, x); copy(_res))
    end

    cons_jac_prototype = f.cons_jac_prototype
    cons_jac_colorvec = f.cons_jac_colorvec
    if cons !== nothing && f.cons_j === nothing
        extras_jac = prepare_jacobian(cons_oop, adtype, x)
        cons_j = function (J, θ)
            jacobian!(cons_oop, J, adtype, θ, extras_jac)
        end
    else
        cons_j = (J, θ) -> f.cons_j(J, θ, p)
    end

    conshess_sparsity = f.cons_hess_prototype
    conshess_colors = f.cons_hess_colorvec
    if cons !== nothing && f.cons_h === nothing
        fncs = [(x) -> cons_oop(x)[i] for i in 1:num_cons]
        extras_cons_hess = prepare_hessian.(fncs, Ref(DifferentiationInterface.SecondOrder(adtype)), Ref(x))

        function cons_h(H, θ)
            for i in 1:num_cons
                hessian!(fncs[i], H[i], adtype, θ, extras_cons_hess[i])
            end
        end
    else
        cons_h = (res, θ) -> f.cons_h(res, θ, p)
    end

    if f.lag_h === nothing
        lag_h = nothing # Consider implementing this
    else
        lag_h = (res, θ, σ, μ) -> f.lag_h(res, θ, σ, μ, p)
    end
    return OptimizationFunction{true}(f.f, adtype; grad = grad, hess = hess, hv = hv,
        cons = cons, cons_j = cons_j, cons_h = cons_h,
        hess_prototype = hess_sparsity,
        hess_colorvec = hess_colors,
        cons_jac_prototype = cons_jac_prototype,
        cons_jac_colorvec = cons_jac_colorvec,
        cons_hess_prototype = conshess_sparsity,
        cons_hess_colorvec = conshess_colors,
        lag_h, f.lag_hess_prototype)
end

function OptimizationBase.instantiate_function(f, cache::OptimizationBase.ReInitCache, adtype::ADTypes.AutoZygote, num_cons = 0)
    x = cache.u0
    p = cache.p
    _f = (θ, args...) -> first(f.f(θ, p, args...))

    if f.grad === nothing
        extras_grad = prepare_gradient(_f, adtype, x)
        function grad(res, θ)
            gradient!(_f, res, adtype, θ, extras_grad)
        end
    else
        grad = (G, θ, args...) -> f.grad(G, θ, p, args...)
    end

    hess_sparsity = f.hess_prototype
    hess_colors = f.hess_colorvec
    if f.hess === nothing
        extras_hess = prepare_hessian(_f, DifferentiationInterface.SecondOrder(adtype), x) #placeholder logic, can be made much better
        function hess(res, θ, args...)
            hessian!(_f, res, DifferentiationInterface.SecondOrder(adtype), θ, extras_hess)
        end
    else
        hess = (H, θ, args...) -> f.hess(H, θ, p, args...)
    end

    if f.hv === nothing
        hv = function (H, θ, v, args...)
            # _θ = ForwardDiff.Dual.(θ, v)
            # res = similar(_θ)
            # grad(res, _θ, args...)
            # H .= getindex.(ForwardDiff.partials.(res), 1)
            res = zeros(length(θ), length(θ))
            hess(res, θ, args...)
            H .= res * v
        end
    else
        hv = f.hv
    end

    if f.cons === nothing
        cons = nothing
    else
        cons = (res, θ) -> f.cons(res, θ, p)
        cons_oop = (x) -> (_res = Zygote.Buffer(x, num_cons); cons(_res, x); copy(_res))
    end

    cons_jac_prototype = f.cons_jac_prototype
    cons_jac_colorvec = f.cons_jac_colorvec
    if cons !== nothing && f.cons_j === nothing
        extras_jac = prepare_jacobian(cons_oop, adtype, x)
        cons_j = function (J, θ)
            jacobian!(cons_oop, J, adtype, θ, extras_jac)
        end
    else
        cons_j = (J, θ) -> f.cons_j(J, θ, p)
    end

    conshess_sparsity = f.cons_hess_prototype
    conshess_colors = f.cons_hess_colorvec
    if cons !== nothing && f.cons_h === nothing
        fncs = [(x) -> cons_oop(x)[i] for i in 1:num_cons]
        extras_cons_hess = prepare_hessian.(fncs, Ref(DifferentiationInterface.SecondOrder(adtype)), Ref(x))

        function cons_h(H, θ)
            for i in 1:num_cons
                hessian!(fncs[i], H[i], adtype, θ, extras_cons_hess[i])
            end
        end
    else
        cons_h = (res, θ) -> f.cons_h(res, θ, p)
    end

    if f.lag_h === nothing
        lag_h = nothing # Consider implementing this
    else
        lag_h = (res, θ, σ, μ) -> f.lag_h(res, θ, σ, μ, p)
    end
    return OptimizationFunction{true}(f.f, adtype; grad = grad, hess = hess, hv = hv,
        cons = cons, cons_j = cons_j, cons_h = cons_h,
        hess_prototype = hess_sparsity,
        hess_colorvec = hess_colors,
        cons_jac_prototype = cons_jac_prototype,
        cons_jac_colorvec = cons_jac_colorvec,
        cons_hess_prototype = conshess_sparsity,
        cons_hess_colorvec = conshess_colors,
        lag_h, f.lag_hess_prototype)
end

function OptimizationBase.instantiate_function(f::OptimizationFunction{false}, x,
        adtype::AutoZygote, p,
        num_cons = 0)
    _f = (θ, args...) -> f(θ, p, args...)[1]
    if f.grad === nothing
        grad = function (θ, args...)
            val = Zygote.gradient(x -> _f(x, args...), θ)[1]
            if val === nothing
                return zero(eltype(θ))
            else
                return val
            end
        end
    else
        grad = (θ, args...) -> f.grad(θ, p, args...)
    end

    if f.hess === nothing
        hess = function (θ, args...)
            return ForwardDiff.jacobian(θ) do θ
                return Zygote.gradient(x -> _f(x, args...), θ)[1]
            end
        end
    else
        hess = (θ, args...) -> f.hess(θ, p, args...)
    end

    if f.hv === nothing
        hv = function (H, θ, v, args...)
            _θ = ForwardDiff.Dual.(θ, v)
            res = grad(_θ, args...)
            return getindex.(ForwardDiff.partials.(res), 1)
        end
    else
        hv = f.hv
    end

    if f.cons === nothing
        cons = nothing
    else
        cons = (θ) -> f.cons(θ, p)
        cons_oop = cons
    end

    if cons !== nothing && f.cons_j === nothing
        cons_j = function (θ)
            if num_cons > 1
                return first(Zygote.jacobian(cons_oop, θ))
            else
                return first(Zygote.jacobian(cons_oop, θ))[1, :]
            end
        end
    else
        cons_j = (θ) -> f.cons_j(θ, p)
    end

    if cons !== nothing && f.cons_h === nothing
        fncs = [(x) -> cons_oop(x)[i] for i in 1:num_cons]
        cons_h = function (θ)
            return map(1:num_cons) do i
                Zygote.hessian(fncs[i], θ)
            end
        end
    else
        cons_h = (θ) -> f.cons_h(θ, p)
    end

    if f.lag_h === nothing
        lag_h = nothing # Consider implementing this
    else
        lag_h = (θ, σ, μ) -> f.lag_h(θ, σ, μ, p)
    end

    return OptimizationFunction{false}(f.f, adtype; grad = grad, hess = hess, hv = hv,
        cons = cons, cons_j = cons_j, cons_h = cons_h,
        hess_prototype = f.hess_prototype,
        cons_jac_prototype = f.cons_jac_prototype,
        cons_hess_prototype = f.cons_hess_prototype,
        lag_h, f.lag_hess_prototype)
end

function OptimizationBase.instantiate_function(f::OptimizationFunction{false},
        cache::OptimizationBase.ReInitCache,
        adtype::AutoZygote, num_cons = 0)
    _f = (θ, args...) -> f(θ, cache.p, args...)[1]
    p = cache.p

    if f.grad === nothing
        grad = function (θ, args...)
            val = Zygote.gradient(x -> _f(x, args...), θ)[1]
            if val === nothing
                return zero(eltype(θ))
            else
                return val
            end
        end
    else
        grad = (θ, args...) -> f.grad(θ, p, args...)
    end

    if f.hess === nothing
        hess = function (θ, args...)
            return ForwardDiff.jacobian(θ) do θ
                Zygote.gradient(x -> _f(x, args...), θ)[1]
            end
        end
    else
        hess = (θ, args...) -> f.hess(θ, p, args...)
    end

    if f.hv === nothing
        hv = function (H, θ, v, args...)
            _θ = ForwardDiff.Dual.(θ, v)
            res = grad(_θ, args...)
            return getindex.(ForwardDiff.partials.(res), 1)
        end
    else
        hv = f.hv
    end

    if f.cons === nothing
        cons = nothing
    else
        cons = (θ) -> f.cons(θ, p)
        cons_oop = cons
    end

    if cons !== nothing && f.cons_j === nothing
        cons_j = function (θ)
            if num_cons > 1
                return first(Zygote.jacobian(cons_oop, θ))
            else
                return first(Zygote.jacobian(cons_oop, θ))[1, :]
            end
        end
    else
        cons_j = (θ) -> f.cons_j(θ, p)
    end

    if cons !== nothing && f.cons_h === nothing
        fncs = [(x) -> cons_oop(x)[i] for i in 1:num_cons]
        cons_h = function (θ)
            return map(1:num_cons) do i
                Zygote.hessian(fncs[i], θ)
            end
        end
    else
        cons_h = (θ) -> f.cons_h(θ, p)
    end

    if f.lag_h === nothing
        lag_h = nothing # Consider implementing this
    else
        lag_h = (θ, σ, μ) -> f.lag_h(θ, σ, μ, p)
    end

    return OptimizationFunction{false}(f.f, adtype; grad = grad, hess = hess, hv = hv,
        cons = cons, cons_j = cons_j, cons_h = cons_h,
        hess_prototype = f.hess_prototype,
        cons_jac_prototype = f.cons_jac_prototype,
        cons_hess_prototype = f.cons_hess_prototype,
        lag_h, f.lag_hess_prototype)
end

end
