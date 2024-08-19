"""
    TruncatedIO <: IO

Wraps a streaming IO object that reads only as much as should be read and not a byte more.

Objects inheriting from this abstract type pass along all IO methods to the wrapped stream
except for `bytesavailable(io)` and `eof(io)`. Inherited types _must_ implement:
- `TruncatedStreams.unwrap(::TruncatedIO)::IO`: return the wrapped IO stream.
- `Base.eof(::TruncatedIO)::Bool`: report whether the stream cannot produce any more bytes.

In order to implement truncation, some number of these methods will likely need to be
implemented:
- `Base.unsafe_read(::TruncatedIO, p::Ptr{UInt8}, n::UInt)::Nothing`: copy `n` bytes from the stream into memory pointed to by `p`.
- `Base.read(::TruncatedIO, T::Type)::T`: read and return an object of type `T` from the stream.
- `Base.bytesavailable(::TruncatedIO)::Int`: report the number of bytes available to read from the stream until EOF or a buffer refill.
- `Base.seek(::TruncatedIO, p::Integer)` and `Base.seekend(::TruncatedIO)`: seek stream to position `p` or end of stream.
- `Base.reset(::TruncatedIO)`: reset a marked stream to the saved position.
- `Base.reseteof(::TruncatedIO)::Nothing`: reset EOF status.

Note that writing to the stream does not affect truncation.

The following methods must be implemented by the wrapped IO type for all the functionality
of the truncated streams to work at all:
- `Base.eof(::IO)::Bool`
- `Base.read(::IO, ::Type{UInt8})::UInt8`

The wrapped stream also must implement `Base.seek` and `Base.skip` for seeking and skipping
of the truncated stream to work properly. Additionally, `Base.position` needs to be
implemented for some instances of `Base.seek` to work properly.
"""
abstract type TruncatedIO <: IO end

"""
    unwrap(s<:TruncatedIO) -> IO

Return the wrapped source.
"""
function unwrap end

# unary functions
for func in (
    :lock,
    :unlock,
    :isopen,
    :close,
    :flush,
    :position,
    :mark,
    :unmark,
    :reset,
    :ismarked,
    :isreadable,
    :iswritable,
    :seekend,
)
    @eval Base.$func(s::TruncatedIO) = Base.$func(unwrap(s))
end

# newer functions for half-duplex close
@static if VERSION >= v"1.8"
    for func in (:closewrite,)
        @eval Base.$func(s::TruncatedIO) = Base.$func(unwrap(s))
    end
end

# n-ary functions
Base.seek(s::TruncatedIO, n::Integer) = seek(unwrap(s), n)
Base.skip(s::TruncatedIO, n::Integer) = skip(unwrap(s), n)

# required to override byte-level reading of objects by delegating to unsafe_read
function Base.read(s::TruncatedIO, ::Type{UInt8})
    r = Ref{UInt8}()
    unsafe_read(s, r, 1)
    return r[]
end

# allows bytesavailable to signal how much can be read from the stream at a time
Base.readavailable(s::TruncatedIO) = read(s, bytesavailable(s))

# required to allow passthrough of byte-level writing
Base.write(s::TruncatedIO, x::UInt8) = return write(unwrap(s), x)