const SimpleBitsType = Union{Type{Int16},Type{UInt16},Type{Int32},Type{UInt32},Type{Int64},Type{UInt64},Type{Int128},Type{UInt128},Type{Float16},Type{Float32},Type{Float64},Type{Complex{Int16}},Type{Complex{UInt16}},Type{Complex{Int32}},Type{Complex{UInt32}},Type{Complex{Int64}},Type{Complex{UInt64}},Type{Complex{Int128}},Type{Complex{UInt128}},Type{Complex{Float16}},Type{Complex{Float32}},Type{Complex{Float64}}}

"""
TruncatedIO <: IO

Wraps an IO stream object and lies about how much is left to read from the stream.

Objects inheriting from this abstract type pass along all IO methods to the wrapped stream
except for `bytesavailable(io)` and `eof(io)`. Inherited types need to implement:
- `unwrap(::AbstractTruncatedSource)::IO`: return the wrapped IO stream.
- `Base.bytesavailable(::AbstractTruncatedSource)::Int`: report the number of bytes available to
read from the stream until EOF or a buffer refill.
- `Base.eof(::AbstractTruncatedSource)::Bool`: report whether the stream cannot produce any more
bytes.

Optional methods to implement that might be useful are:
- `Base.reseteof(::AbstractTruncatedSource)::Nothing`: reset EOF status.
- `Base.unsafe_read(::AbstractTruncatedSource, p::Ptr{UInt8}, n::UInt)::Nothing`: copy `n` bytes from the stream into memory pointed to by `p`.
- `Base.seek(::TruncatedIO, n::Integer)` and `Base.seekend(::TruncatedIO)`: seek stream to position `n` or end of stream.
- `Base.reset(::TruncatedIO)`: reset a marked stream to the saved position.
"""
abstract type TruncatedIO <: IO end

"""
unwrap(s<:TruncatedIO) -> IO

Return the wrapped source.
"""
function unwrap end

# unary functions
for func in (:lock, :unlock, :isopen, :close, :closewrite, :flush, :position, :mark, :unmark, :reset, :ismarked, :isreadable, :iswritable, :seekend)
    @eval Base.$func(s::TruncatedIO) = Base.$func(unwrap(s))
end

# n-ary functions
Base.seek(s::TruncatedIO, n::Integer) = seek(unwrap(s), n)
Base.skip(s::TruncatedIO, n::Integer) = skip(unwrap(s), n)
Base.unsafe_read(s::TruncatedIO, p::Ptr{UInt8}, n::UInt) = unsafe_read(unwrap(s), p, n)
Base.unsafe_write(s::TruncatedIO, p::Ptr{UInt8}, n::UInt) = unsafe_write(unwrap(s), p, n)

function Base.read(s::TruncatedIO, ::Type{UInt8})
    r = Ref{UInt8}()
    unsafe_read(s, r, 1)
    return r[]
end

"""
FixedLengthIO(io, length) <: TruncatedIO

A truncated source that reads `io` up to `length` bytes.
"""
mutable struct FixedLengthIO{S <: IO} <: TruncatedIO
    wrapped::S
    length::Int
    remaining::Int

    FixedLengthIO(io::S, length::Integer) where {S} = new{S}(io, length, length)
end

unwrap(s::FixedLengthIO) = s.wrapped

Base.bytesavailable(s::FixedLengthIO) = min(s.remaining, bytesavailable(unwrap(s)))

Base.eof(s::FixedLengthIO) = eof(unwrap(s)) || s.remaining <= 0

function Base.unsafe_read(s::FixedLengthIO, p::Ptr{UInt8}, n::UInt)
    # note that the convention from IOBuffer is to read as much as possible first,
    # then throw EOF if the requested read was beyond the number of bytes available.
    available = bytesavailable(s)
    to_read = min(available, n)
    unsafe_read(unwrap(s), p, to_read)
    s.remaining -= to_read
    if to_read < n
        throw(EOFError())
    end
    return nothing
end

function Base.seek(s::FixedLengthIO, n::Integer)
    pos = clamp(n, 0, s.length)
    s.remaining = s.length - pos
    return seek(unwrap(s), n)
end

Base.seekend(s::FixedLengthIO) = seek(s, s.length)

function Base.skip(s::FixedLengthIO, n::Integer)
    # negative numbers will add bytes back to bytesremaining
    bytes = clamp(Int(n), s.remaining - s.length, s.remaining)
    return seek(s, position(s) + bytes)
end

function Base.reset(s::FixedLengthIO)
    pos = reset(unwrap(s))
    seek(s, pos) # seeks the underlying stream as well, but that should be a noop
    return pos
end

"""
SentinelIO(io, sentinel) <: TruncatedIO

A truncated source that reads `io` until `sentinel` is found.

Can be reset with the `reseteof()` method if the sentinel read is discovered upon further
inspection to be bogus.

The wrapped stream `io` must implement `mark` and `reset`.
"""
mutable struct SentinelIO{S <: IO} <: TruncatedIO
    wrapped::S
    sentinel::Vector{UInt8}

    remaining::Int # cached number of bytes known to be good to read

    function SentinelIO(io::S, sentinel::AbstractVector{UInt8}) where {S <: IO}
        new{S}(io, sentinel, 0)
    end
end

unwrap(s::SentinelIO) = s.wrapped

function Base.bytesavailable(s::SentinelIO)
    if s.remaining > 0
        # used cached value
        return s.remaining
    end

    s.remaining = _max_bytes_available(unwrap(s), s.sentinel, typemax(UInt) - length(s.sentinel))
    return s.remaining
end

function Base.eof(s::SentinelIO)
    if eof(unwrap(s))
        s.remaining = 0
        return true
    end
    # trust the number of bytes remaining
    # (if, for example, the sentinel was fake, then remaining bytes will tell us we can read past it)
    if s.remaining > 0
        return false
    end
    r = _max_bytes_available(unwrap(s), s.sentinel, 1)
    if r == 1
        s.remaining = max(s.remaining, 1)
        return false
    else
        s.remaining = 0
        return true
    end
end

function Base.reseteof(s::SentinelIO)
    Base.reseteof(unwrap(s))
    s.remaining = max(s.remaining, length(s.sentinel))
    return nothing
end

function _max_bytes_available(io, sentinel, n)
    previous_mark = -1
    if ismarked(io)
        pos = position(io)
        previous_mark = reset(io)
        seek(io, pos)
    end
    pos = mark(io)
    try
        check = read(io, n + length(sentinel) - 1)
        f = findfirst(sentinel, check)
        if isnothing(f)
            return n
        else
            return first(f) - 1
        end
    finally
        reset(io)
        if previous_mark >= 0
            seek(io, previous_mark)
            mark(io)
            seek(io, pos)
        end
    end
    throw(ErrorException("unreachable tail"))
end

function Base.unsafe_read(s::SentinelIO, p::Ptr{UInt8}, n::UInt)
    if n > s.remaining
        s.remaining = _max_bytes_available(unwrap(s), s.sentinel, n)
    end
    to_read = min(n, s.remaining)
    unsafe_read(unwrap(s), p, to_read)
    s.remaining -= to_read
    if to_read < n
        throw(EOFError())
    end
    return nothing
end

function Base.seek(s::SentinelIO, n::Integer)
    # seeking backwards is always fine.
    # seeking forwards is easier done as reading and dumping data.
    pos = max(n, 0)
    p = position(s)
    bytes = pos - p
    if bytes < 0
        s.remaining -= bytes
        return seek(unwrap(s), pos)
    end
    # drop remainder on the floor
    read(s, bytes)
    return s
end

Base.seekend(s::SentinelIO) = read(s) # read until the end

Base.skip(s::SentinelIO, n::Integer) = seek(s, position(s) + n)

function Base.reset(s::SentinelIO)
    pos = reset(unwrap(s))
    seek(s, pos) # seeks the underlying stream as well, but that should be a noop
    return pos
end