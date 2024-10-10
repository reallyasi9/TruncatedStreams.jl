module TruncatedStreams

export TruncatedSource
export FixedLengthSource
export SentinelizedSource

include("io.jl")
include("fixedlength.jl")
include("sentinel.jl")

end
