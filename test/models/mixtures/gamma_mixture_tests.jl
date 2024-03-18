@testitem "Model mixture" begin
    using Distributions
    using BenchmarkTools, LinearAlgebra, StableRNGs, Plots

    # `include(test/utiltests.jl)`
    include(joinpath(@__DIR__, "..", "..", "utiltests.jl"))

    @model function gamma_mixture_model(y, nmixtures, priors_as, priors_bs, prior_s)

        # set prior on global selection variable
        s ~ Dirichlet(probvec(prior_s))

        # allocate vectors of random variables
        local as
        local bs

        # set priors on variables of mixtures
        for i in 1:nmixtures
            as[i] ~ Gamma(shape = shape(priors_as[i]), rate = rate(priors_as[i]))
            bs[i] ~ Gamma(shape = shape(priors_bs[i]), rate = rate(priors_bs[i]))
        end

        # specify local selection variable and data generating process
        for i in eachindex(y)
            z[i] ~ Categorical(s)
            y[i] ~ GammaMixture(switch = z[i], a = as, b = bs)
        end
    end

    constraints = @constraints begin
        q(z, as, bs, s) = q(z)q(as)q(bs)q(s)

        q(as) = q(as[begin]) .. q(as[end])
        q(bs) = q(bs[begin]) .. q(bs[end])

        q(as)::PointMassFormConstraint(starting_point = (args...) -> [1.0])
    end

    # specify seed and number of data points
    rng = StableRNG(43)
    n_samples = 250

    # specify parameters of mixture model that generates the data
    # Note that mixture components have exactly the same means
    mixtures  = [Gamma(9.0, inv(27.0)), Gamma(90.0, inv(270.0))]
    nmixtures = length(mixtures)
    mixing    = rand(rng, nmixtures)
    mixing    = mixing ./ sum(mixing)
    mixture   = MixtureModel(mixtures, mixing)

    # generate data set
    dataset = rand(rng, mixture, n_samples)

    priors_as = [Gamma(1.0, 0.1), Gamma(1.0, 1.0)]
    priors_bs = [Gamma(10.0, 2.0), Gamma(1.0, 3.0)]
    prior_s = Dirichlet(1e3 * mixing)

    gmodel         = gamma_mixture_model(nmixtures = 2, priors_as = priors_as, priors_bs = priors_bs, prior_s = prior_s)
    gdata          = (y = dataset,)
    ginitmarginals = (s = prior_s, z = vague(Categorical, 2), bs = GammaShapeRate(1.0, 1.0))
    greturnvars    = (s = KeepLast(), z = KeepLast(), as = KeepEach(), bs = KeepEach())

    gresult = infer(
        model = gmodel,
        data = gdata,
        constraints = constraints,
        options = (limit_stack_depth = 100,),
        initmarginals = ginitmarginals,
        returnvars = greturnvars,
        free_energy = true,
        iterations = 50
        # free_energy_diagnostics = nothing
    )

    # extract inferred parameters
    _as, _bs = mean.(gresult.posteriors[:as][end]), mean.(gresult.posteriors[:bs][end])
    _dists   = map(g -> Gamma(g[1], inv(g[2])), zip(_as, _bs))
    _mixing  = mean(gresult.posteriors[:s])

    # create model from inferred parameters
    _mixture = MixtureModel(_dists, _mixing)

    # report on outcome of inference
    println("Dataset:", dataset[1:5])
    println("Generated means: $(mean(mixtures[1])) and $(mean(mixtures[2]))")
    println("Inferred means: $(mean(_dists[1])) and $(mean(_dists[2]))")
    println("========")
    println("Generated mixing: $(mixing)")
    println("Inferred mixing: $(_mixing)")
    println("Free energy:", gresult.free_energy)
end