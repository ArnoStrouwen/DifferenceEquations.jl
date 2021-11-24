struct StateSpaceProblem{
    isinplace, 
    ftype, # TODO: Replace with LinearOperator 
    gtype, # TODO: Replace with LinearOperator 
    htype, # TODO: Replace with LinearOperator 
    wtype, 
    vtype, # TODO: Add support methods for vtype <: Distribution
    utype,
    ttype,
    otype,
    ptype
} <: AbstractStateSpaceProblem{isinplace}
    f::ftype # Evolution function
    g::gtype # Noise function
    h::htype # Observation function
    noise::wtype # Latent noise distribution
    obs_noise::vtype # Observation noise matrix
    u0::utype # Initial condition
    tspan::ttype # Timespan to use
    observables::otype # Observed data to use, if any
    params::ptype # Parameters, if any
end

function StateSpaceProblem(
    f::ftype, 
    g::gtype, 
    h::htype,
    u0::utype,
    tspan::ttype,
    params=nothing;
    obs_noise = StandardGaussian(size(h(u0, params, 0))), # TODO: Might be suboptimal way to get size of obs
    observables = nothing,
    noise = StandardGaussian(size(u0)),
) where {
    ftype, 
    gtype, 
    htype, 
    utype,
    ttype,
}
    if obs_noise isa Vector
        @assert length(obs_noise) == 1
        obs_noise = hcat(obs_noise) # Convert to matrix
    end

    return StateSpaceProblem{
        Val(false), 
        ftype, 
        gtype, 
        htype, 
        typeof(noise), 
        typeof(obs_noise),
        utype,
        ttype,
        typeof(observables),
        typeof(params)
    }(
        f, # Evolution function
        g, # Noise function
        h, # Observation function
        noise, # Latent noise matrix/function/distribution
        obs_noise, # Observation noise matrix/function/distribution
        u0, # Initial condition
        tspan, # Timespan to use
        observables, # Observed data to use, if any
        params
    )
end


CommonSolve.init(prob::StateSpaceProblem, args...; kwargs...) = prob

function CommonSolve.solve!(
    prob::StateSpaceProblem{isinplace, ftype, gtype, htype, wtype, vtype, utype, ttype, otype}, 
    args...; 
    kwargs...
) where {isinplace, ftype, gtype, htype, wtype, vtype, utype, ttype, otype<:Nothing}
    # Preallocate values
    T = prob.tspan[2]

    u = Vector{utype}(undef, T+1) # Latent states
    u[1] = prob.u0

    n1 = noise(prob.obs_noise, 1)
    n = Vector{typeof(n1)}(undef, T+1) # Latent noise
    n[1] = n1

    z1 = prob.h(u[1], prob.params, 1) + noise(prob.obs_noise, 1)
    z = Vector{typeof(z1)}(undef, T+1) # Observables generated
    z[1] = z1

    # Simulate it, homie
    for t in 2:T+1
        n[t] = noise(prob.noise, t)
        u[t] = prob.f(u[t-1], prob.params, t-1) .+ prob.g(u[t-1], prob.params, t-1) * n[t]
        z[t] = prob.h(u[t], prob.params, t) .+ noise(prob.obs_noise, t)
    end

    return StateSpaceSolution(z, u, n, nothing)
end

function CommonSolve.solve!(
    prob::StateSpaceProblem{isinplace, ftype, gtype, htype, wtype, vtype, utype, ttype, otype}, 
    args...; 
    kwargs...
) where {isinplace, ftype, gtype, htype, wtype, vtype, utype, ttype, otype}
    # Preallocate values
    T = prob.tspan[2]

    u = Vector{utype}(undef, T+1) # Latent states
    u[1] = prob.u0
    
    n1 = noise(prob.obs_noise, 1)
    n = Vector{typeof(n1)}(undef, T+1) # Latent noise
    n[1] = n1

    z1 = prob.h(u[1], prob.params, 1) + noise(prob.obs_noise, 1)
    z = Vector{typeof(z1)}(undef, T+1) # Observables generated
    z[1] = z1

    @info "" n1 n

    # Simulate it, homie
    loglik = 0.0
    for t in 2:T+1
        n[t] = noise(prob.noise, t)
        u[t] = prob.f(u[t-1], prob.params, t-1) .+ prob.g(u[t-1], prob.params, t-1) * n[t]
        z[t] = prob.h(u[t], prob.params, t) .+ noise(prob.obs_noise, 1)
        err = z[t] - prob.observables[t]
        loglik += loglikelihood(err, prob.obs_noise, t)
    end

    return StateSpaceSolution(z, u, n, loglik)
end