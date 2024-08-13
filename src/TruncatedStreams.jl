module TruncatedStreams

export TruncatedIO
export FixedLengthIO
export SentinelIO

@static if VERSION < v"1.7"
    include("compat.jl")
end
include("io.jl")
include("fixedlengthio.jl")
include("sentinelio.jl")

end
