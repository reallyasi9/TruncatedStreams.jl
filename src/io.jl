"""
    TruncatedSource <: IO

Wrap an IO object to read only as much as should be read and not a byte more.

Objects inheriting from this abstract type pass along all read-oriented IO methods to the wrapped
stream except for `bytesavailable(io)` and `eof(io)`. Inherited types _must_ implement:
- `TruncatedStreams.unwrap(::TruncatedSource)::IO`: return the wrapped IO stream.
- `Base.eof(::TruncatedSource)::Bool`: report whether the stream cannot produce any more bytes.

In order to implement truncation, some number of these methods will likely need to be implemented:
- `Base.unsafe_read(::TruncatedSource, p::Ptr{UInt8}, n::UInt)::Nothing`: copy `n` bytes from the
    stream into memory pointed to by `p`.
- `Base.read(::TruncatedSource, T::Type)::T`: read and return an object of type `T` from the stream.
- `Base.bytesavailable(::TruncatedSource)::Int`: report the number of bytes available to read from
    the stream until EOF or a buffer refill is necessary.
- `Base.seek(::TruncatedSource, p::Integer)` and `Base.seekend(::TruncatedSource)`: seek stream to
    position `p` or end of stream.
- `Base.reset(::TruncatedSource)`: reset a marked stream to the saved position.
- `Base.reseteof(::TruncatedSource)::Nothing`: reset EOF status.
- `Base.peek(::TruncatedSource[, T::Type])::T`: read and return the next object of type `T` from the
    stream, but leave the bytes available in the stream for the next read.

The following methods _must_ be implemented by the wrapped IO type for all the functionality of the
    `TruncatedSource` to work at all:
- `Base.eof(::IO)::Bool`
- `Base.read(::IO, ::Type{UInt8})::UInt8`

The wrapped stream also must implement `Base.seek` and `Base.skip` for seeking and skipping of the
truncated stream to work properly. Additionally, `Base.position` needs to be implemented for some
implementations of `Base.seek` to work properly.
"""
abstract type TruncatedSource <: IO end


"""
    unwrap(s<:TruncatedSource{T}) -> T where {T <: IO}

Return the wrapped source.
"""
function unwrap end

# unary functions
for func in (
    :lock,
    :unlock,
    :isopen,
    :close,
    :position,
    :mark,
    :unmark,
    :reset,
    :ismarked,
    :isreadable,
)
    @eval Base.$func(s::TruncatedSource) = Base.$func(unwrap(s))
end

# always report unwritable
Base.iswritable(::TruncatedSource) = false

# required to override byte-level reading of objects by delegating to unsafe_read
function Base.read(s::TruncatedSource, ::Type{UInt8})
    r = Ref{UInt8}()
    unsafe_read(s, r, 1)
    return r[]
end

# allows bytesavailable to signal how much can be read from the stream at a time
Base.readavailable(s::TruncatedSource) = read(s, bytesavailable(s))
