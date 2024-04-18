module OptimizationFiniteDiffExt

import OptimizationBase, OptimizationBase.ArrayInterface
import OptimizationBase.SciMLBase: OptimizationFunction
import OptimizationBase.ADTypes: AutoFiniteDiff
using OptimizationBase.LinearAlgebra
isdefined(Base, :get_extension) ? (using FiniteDiff) : (using ..FiniteDiff)

const FD = FiniteDiff

function OptimizationBase.instantiate_function(f::OptimizationFunction{true}, x,
        adtype::AutoFiniteDiff, p,
        num_cons = 0)
    _f = (θ, args...) -> first(f.f(θ, p, args...))
    updatecache = (cache, x) -> (cache.xmm .= x; cache.xmp .= x; cache.xpm .= x; cache.xpp .= x; return cache)

    if f.grad === nothing
        gradcache = FD.GradientCache(x, x, adtype.fdtype)
        grad = (res, θ, args...) -> FD.finite_difference_gradient!(res, x -> _f(x, args...),
            θ, gradcache)
    else
        grad = (G, θ, args...) -> f.grad(G, θ, p, args...)
    end

    if f.hess === nothing
        hesscache = FD.HessianCache(x, adtype.fdhtype)
        hess = (res, θ, args...) -> FD.finite_difference_hessian!(res,
            x -> _f(x, args...), θ,
            updatecache(hesscache, θ))
    else
        hess = (H, θ, args...) -> f.hess(H, θ, p, args...)
    end

    if f.hv === nothing
        hv = function (H, θ, v, args...)
            T = eltype(θ)
            ϵ = sqrt(eps(real(T))) * max(one(real(T)), abs(norm(θ)))
            @. θ += ϵ * v
            cache2 = similar(θ)
            grad(cache2, θ, args...)
            @. θ -= 2ϵ * v
            cache3 = similar(θ)
            grad(cache3, θ, args...)
            @. θ += ϵ * v
            @. H = (cache2 - cache3) / (2ϵ)
        end
    else
        hv = f.hv
    end

    if f.cons === nothing
        cons = nothing
    else
        cons = (res, θ) -> f.cons(res, θ, p)
    end

    cons_jac_colorvec = f.cons_jac_colorvec === nothing ? (1:length(x)) :
                        f.cons_jac_colorvec

    if cons !== nothing && f.cons_j === nothing
        cons_j = function (J, θ)
            y0 = zeros(num_cons)
            jaccache = FD.JacobianCache(copy(x), copy(y0), copy(y0), adtype.fdjtype;
                colorvec = cons_jac_colorvec,
                sparsity = f.cons_jac_prototype)
            FD.finite_difference_jacobian!(J, cons, θ, jaccache)
        end
    else
        cons_j = (J, θ) -> f.cons_j(J, θ, p)
    end

    if cons !== nothing && f.cons_h === nothing
        hess_cons_cache = [FD.HessianCache(copy(x), adtype.fdhtype)
                           for i in 1:num_cons]
        cons_h = function (res, θ)
            for i in 1:num_cons#note: colorvecs not yet supported by FiniteDiff for Hessians
                FD.finite_difference_hessian!(res[i],
                    (x) -> (_res = zeros(eltype(θ), num_cons);
                    cons(_res, x);
                    _res[i]), θ,
                    updatecache(hess_cons_cache[i], θ))
            end
        end
    else
        cons_h = (res, θ) -> f.cons_h(res, θ, p)
    end

    if f.lag_h === nothing
        lag_hess_cache = FD.HessianCache(copy(x), adtype.fdhtype)
        c = zeros(num_cons)
        h = zeros(length(x), length(x))
        lag_h = let c = c, h = h
            lag = function (θ, σ, μ)
                f.cons(c, θ, p)
                l = μ'c
                if !iszero(σ)
                    l += σ * f.f(θ, p)
                end
                l
            end
            function (res, θ, σ, μ)
                FD.finite_difference_hessian!(res,
                    (x) -> lag(x, σ, μ),
                    θ,
                    updatecache(lag_hess_cache, θ))
            end
        end
    else
        lag_h = (res, θ, σ, μ) -> f.lag_h(res, θ, σ, μ, p)
    end
    return OptimizationFunction{true}(f, adtype; grad = grad, hess = hess, hv = hv,
        cons = cons, cons_j = cons_j, cons_h = cons_h,
        cons_jac_colorvec = cons_jac_colorvec,
        hess_prototype = f.hess_prototype,
        cons_jac_prototype = f.cons_jac_prototype,
        cons_hess_prototype = f.cons_hess_prototype,
        lag_h = lag_h,
        lag_hess_prototype = f.lag_hess_prototype,
        sys = f.sys,
        expr = f.expr,
        cons_expr = f.cons_expr)
end

function OptimizationBase.instantiate_function(f::OptimizationFunction{true},
        cache::OptimizationBase.ReInitCache,
        adtype::AutoFiniteDiff, num_cons = 0)
    _f = (θ, args...) -> first(f.f(θ, cache.p, args...))
    updatecache = (cache, x) -> (cache.xmm .= x; cache.xmp .= x; cache.xpm .= x; cache.xpp .= x; return cache)

    if f.grad === nothing
        gradcache = FD.GradientCache(cache.u0, cache.u0, adtype.fdtype)
        grad = (res, θ, args...) -> FD.finite_difference_gradient!(res, x -> _f(x, args...),
            θ, gradcache)
    else
        grad = (G, θ, args...) -> f.grad(G, θ, cache.p, args...)
    end

    if f.hess === nothing
        hesscache = FD.HessianCache(cache.u0, adtype.fdhtype)
        hess = (res, θ, args...) -> FD.finite_difference_hessian!(res, x -> _f(x, args...),
            θ,
            updatecache(hesscache, θ))
    else
        hess = (H, θ, args...) -> f.hess(H, θ, cache.p, args...)
    end

    if f.hv === nothing
        hv = function (H, θ, v, args...)
            T = eltype(θ)
            ϵ = sqrt(eps(real(T))) * max(one(real(T)), abs(norm(θ)))
            @. θ += ϵ * v
            cache2 = similar(θ)
            grad(cache2, θ, args...)
            @. θ -= 2ϵ * v
            cache3 = similar(θ)
            grad(cache3, θ, args...)
            @. θ += ϵ * v
            @. H = (cache2 - cache3) / (2ϵ)
        end
    else
        hv = f.hv
    end

    if f.cons === nothing
        cons = nothing
    else
        cons = (res, θ) -> f.cons(res, θ, cache.p)
    end

    cons_jac_colorvec = f.cons_jac_colorvec === nothing ? (1:length(cache.u0)) :
                        f.cons_jac_colorvec

    if cons !== nothing && f.cons_j === nothing
        cons_j = function (J, θ)
            y0 = zeros(num_cons)
            jaccache = FD.JacobianCache(copy(cache.u0), copy(y0), copy(y0),
                adtype.fdjtype;
                colorvec = cons_jac_colorvec,
                sparsity = f.cons_jac_prototype)
            FD.finite_difference_jacobian!(J, cons, θ, jaccache)
        end
    else
        cons_j = (J, θ) -> f.cons_j(J, θ, cache.p)
    end

    if cons !== nothing && f.cons_h === nothing
        hess_cons_cache = [FD.HessianCache(copy(cache.u0), adtype.fdhtype)
                           for i in 1:num_cons]
        cons_h = function (res, θ)
            for i in 1:num_cons#note: colorvecs not yet supported by FiniteDiff for Hessians
                FD.finite_difference_hessian!(res[i],
                    (x) -> (_res = zeros(eltype(θ), num_cons);
                    cons(_res,
                        x);
                    _res[i]),
                    θ, updatecache(hess_cons_cache[i], θ))
            end
        end
    else
        cons_h = (res, θ) -> f.cons_h(res, θ, cache.p)
    end
    if f.lag_h === nothing
        lag_hess_cache = FD.HessianCache(copy(cache.u0), adtype.fdhtype)
        c = zeros(num_cons)
        h = zeros(length(cache.u0), length(cache.u0))
        lag_h = let c = c, h = h
            lag = function (θ, σ, μ)
                f.cons(c, θ, cache.p)
                l = μ'c
                if !iszero(σ)
                    l += σ * f.f(θ, cache.p)
                end
                l
            end
            function (res, θ, σ, μ)
                FD.finite_difference_hessian!(h,
                    (x) -> lag(x, σ, μ),
                    θ,
                    updatecache(lag_hess_cache, θ))
                k = 1
                for i in 1:length(cache.u0), j in i:length(cache.u0)
                    res[k] = h[i, j]
                    k += 1
                end
            end
        end
    else
        lag_h = (res, θ, σ, μ) -> f.lag_h(res, θ, σ, μ, cache.p)
    end
    return OptimizationFunction{true}(f, adtype; grad = grad, hess = hess, hv = hv,
        cons = cons, cons_j = cons_j, cons_h = cons_h,
        cons_jac_colorvec = cons_jac_colorvec,
        hess_prototype = f.hess_prototype,
        cons_jac_prototype = f.cons_jac_prototype,
        cons_hess_prototype = f.cons_hess_prototype,
        lag_h = lag_h,
        lag_hess_prototype = f.lag_hess_prototype,
        sys = f.sys,
        expr = f.expr,
        cons_expr = f.cons_expr)
end

function OptimizationBase.instantiate_function(f::OptimizationFunction{false}, x,
        adtype::AutoFiniteDiff, p,
        num_cons = 0)
    _f = (θ, args...) -> first(f.f(θ, p, args...))
    updatecache = (cache, x) -> (cache.xmm .= x; cache.xmp .= x; cache.xpm .= x; cache.xpp .= x; return cache)

    if f.grad === nothing
        gradcache = FD.GradientCache(x, x, adtype.fdtype)
        grad = (θ, args...) -> FD.finite_difference_gradient(x -> _f(x, args...),
            θ, gradcache)
    else
        grad = (θ, args...) -> f.grad(G, θ, p, args...)
    end

    if f.hess === nothing
        hesscache = FD.HessianCache(x, adtype.fdhtype)
        hess = (θ, args...) -> FD.finite_difference_hessian(x -> _f(x, args...), θ,
            updatecache(hesscache, θ))
    else
        hess = (θ, args...) -> f.hess(θ, p, args...)
    end

    if f.hv === nothing
        hv = function (θ, v, args...)
            T = eltype(θ)
            ϵ = sqrt(eps(real(T))) * max(one(real(T)), abs(norm(θ)))
            @. θ += ϵ * v
            cache2 = similar(θ)
            grad(cache2, θ, args...)
            @. θ -= 2ϵ * v
            cache3 = similar(θ)
            grad(cache3, θ, args...)
            @. θ += ϵ * v
            return @. (cache2 - cache3) / (2ϵ)
        end
    else
        hv = f.hv
    end

    if f.cons === nothing
        cons = nothing
    else
        cons = (θ) -> f.cons(θ, p)
    end

    cons_jac_colorvec = f.cons_jac_colorvec === nothing ? (1:length(x)) :
                        f.cons_jac_colorvec

    if cons !== nothing && f.cons_j === nothing
        cons_j = function (θ)
            y0 = zeros(eltype(θ), num_cons)
            jaccache = FD.JacobianCache(copy(x), copy(y0), copy(y0), adtype.fdjtype;
                colorvec = cons_jac_colorvec,
                sparsity = f.cons_jac_prototype)
            if num_cons > 1
                return FD.finite_difference_jacobian(cons, θ, jaccache)
            else
                return FD.finite_difference_jacobian(cons, θ, jaccache)[1, :]
            end
        end
    else
        cons_j = (θ) -> f.cons_j(θ, p)
    end

    if cons !== nothing && f.cons_h === nothing
        hess_cons_cache = [FD.HessianCache(copy(x), adtype.fdhtype)
                           for i in 1:num_cons]
        cons_h = function (θ)
            return map(1:num_cons) do i
                FD.finite_difference_hessian(x -> cons(x)[i], θ,
                    updatecache(hess_cons_cache[i], θ))
            end
        end
    else
        cons_h = (θ) -> f.cons_h(θ, p)
    end

    if f.lag_h === nothing
        lag_hess_cache = FD.HessianCache(copy(x), adtype.fdhtype)
        c = zeros(num_cons)
        h = zeros(length(x), length(x))
        lag_h = let c = c, h = h
            lag = function (θ, σ, μ)
                f.cons(c, θ, p)
                l = μ'c
                if !iszero(σ)
                    l += σ * f.f(θ, p)
                end
                l
            end
            function (θ, σ, μ)
                FD.finite_difference_hessian((x) -> lag(x, σ, μ),
                    θ,
                    updatecache(lag_hess_cache, θ))
            end
        end
    else
        lag_h = (θ, σ, μ) -> f.lag_h(θ, σ, μ, p)
    end
    return OptimizationFunction{false}(f, adtype; grad = grad, hess = hess, hv = hv,
        cons = cons, cons_j = cons_j, cons_h = cons_h,
        cons_jac_colorvec = cons_jac_colorvec,
        hess_prototype = f.hess_prototype,
        cons_jac_prototype = f.cons_jac_prototype,
        cons_hess_prototype = f.cons_hess_prototype,
        lag_h = lag_h,
        lag_hess_prototype = f.lag_hess_prototype,
        sys = f.sys,
        expr = f.expr,
        cons_expr = f.cons_expr)
end

function OptimizationBase.instantiate_function(f::OptimizationFunction{false},
        cache::OptimizationBase.ReInitCache,
        adtype::AutoFiniteDiff, num_cons = 0)
    _f = (θ, args...) -> first(f.f(θ, cache.p, args...))
    updatecache = (cache, x) -> (cache.xmm .= x; cache.xmp .= x; cache.xpm .= x; cache.xpp .= x; return cache)
    p = cache.p

    if f.grad === nothing
        gradcache = FD.GradientCache(x, x, adtype.fdtype)
        grad = (θ, args...) -> FD.finite_difference_gradient(x -> _f(x, args...),
            θ, gradcache)
    else
        grad = (θ, args...) -> f.grad(G, θ, p, args...)
    end

    if f.hess === nothing
        hesscache = FD.HessianCache(x, adtype.fdhtype)
        hess = (θ, args...) -> FD.finite_difference_hessian!(x -> _f(x, args...), θ,
            updatecache(hesscache, θ))
    else
        hess = (θ, args...) -> f.hess(θ, p, args...)
    end

    if f.hv === nothing
        hv = function (θ, v, args...)
            T = eltype(θ)
            ϵ = sqrt(eps(real(T))) * max(one(real(T)), abs(norm(θ)))
            @. θ += ϵ * v
            cache2 = similar(θ)
            grad(cache2, θ, args...)
            @. θ -= 2ϵ * v
            cache3 = similar(θ)
            grad(cache3, θ, args...)
            @. θ += ϵ * v
            return @. (cache2 - cache3) / (2ϵ)
        end
    else
        hv = f.hv
    end

    if f.cons === nothing
        cons = nothing
    else
        cons = (θ) -> f.cons(θ, p)
    end

    cons_jac_colorvec = f.cons_jac_colorvec === nothing ? (1:length(x)) :
                        f.cons_jac_colorvec

    if cons !== nothing && f.cons_j === nothing
        cons_j = function (θ)
            y0 = zeros(num_cons)
            jaccache = FD.JacobianCache(copy(x), copy(y0), copy(y0), adtype.fdjtype;
                colorvec = cons_jac_colorvec,
                sparsity = f.cons_jac_prototype)
            if num_cons > 1
                return FD.finite_difference_jacobian(cons, θ, jaccache)
            else
                return FD.finite_difference_jacobian(cons, θ, jaccache)[1, :]
            end
        end
    else
        cons_j = (θ) -> f.cons_j(θ, p)
    end

    if cons !== nothing && f.cons_h === nothing
        hess_cons_cache = [FD.HessianCache(copy(x), adtype.fdhtype)
                           for i in 1:num_cons]
        cons_h = function (θ)
            return map(1:num_cons) do i
                FD.finite_difference_hessian(x -> cons(x)[i], θ,
                    updatecache(hess_cons_cache[i], θ))
            end
        end
    else
        cons_h = (θ) -> f.cons_h(θ, p)
    end

    if f.lag_h === nothing
        lag_hess_cache = FD.HessianCache(copy(x), adtype.fdhtype)
        c = zeros(num_cons)
        h = zeros(length(x), length(x))
        lag_h = let c = c, h = h
            lag = function (θ, σ, μ)
                f.cons(c, θ, p)
                l = μ'c
                if !iszero(σ)
                    l += σ * f.f(θ, p)
                end
                l
            end
            function (θ, σ, μ)
                FD.finite_difference_hessian((x) -> lag(x, σ, μ),
                    θ,
                    updatecache(lag_hess_cache, θ))
            end
        end
    else
        lag_h = (θ, σ, μ) -> f.lag_h(θ, σ, μ, p)
    end
    return OptimizationFunction{false}(f, adtype; grad = grad, hess = hess, hv = hv,
        cons = cons, cons_j = cons_j, cons_h = cons_h,
        cons_jac_colorvec = cons_jac_colorvec,
        hess_prototype = f.hess_prototype,
        cons_jac_prototype = f.cons_jac_prototype,
        cons_hess_prototype = f.cons_hess_prototype,
        lag_h = lag_h,
        lag_hess_prototype = f.lag_hess_prototype,
        sys = f.sys,
        expr = f.expr,
        cons_expr = f.cons_expr)
end

end
