module TruncatedStreams

export TruncatedSource
export FixedLengthSource
export SentinelizedSource

@static if VERSION < v"1.7"
    include("compat.jl")
end
include("io.jl")
include("fixedlength.jl")
include("sentinel.jl")

end
