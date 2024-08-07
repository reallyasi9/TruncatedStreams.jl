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

function Base.read(s::FixedLengthIO, T::SimpleBitsType)
    available = bytesavailable(s)
    nb = sizeof(T)
    if available < nb
        throw(EOFError())
    end
    x = read(unwrap(s), T)
    return x
end

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
    failure_function::Vector{Int}
    eof::Bool
    skip::Bool

    function SentinelIO(io::S, sentinel::AbstractVector{UInt8}) where {S <: IO}
        # Implements Knuth-Morris-Pratt failure function computation
        # https://en.wikipedia.org/wiki/Knuth%E2%80%93Morris%E2%80%93Pratt_algorithm
        s = Vector{UInt8}(sentinel)
        t = ones(Int, length(s) + 1)
        pos = firstindex(s) + 1
        cnd = firstindex(t)

        t[cnd] = 0
        @inbounds while pos <= lastindex(s)
            if s[pos] == s[cnd]
                t[pos] = t[cnd]
            else
                t[pos] = cnd
                while cnd > 0 && s[pos] != s[cnd]
                    cnd = t[cnd]
                end
            end
            pos += 1
            cnd += 1
        end
        t[pos] = cnd

        new{S}(io, s, t, false, false)
    end
end

unwrap(s::SentinelIO) = s.wrapped

function Base.bytesavailable(s::SentinelIO)
    if eof(s)
        # already exhausted the stream
        return 0
    end

    n = bytesavailable(unwrap(s))
    if n < length(s.sentinel)
        # only read up until we cannot determine sentinel status: don't refill buffers
        return 0
    end

    # Implements Knuth-Morris-Pratt with extra logic to deal with the tail of the buffer
    # https://en.wikipedia.org/wiki/Knuth%E2%80%93Morris%E2%80%93Pratt_algorithm

    mark(s)
    b_idx = 0
    s_idx = firstindex(s.sentinel)

    try
        while true
            if n + s_idx - 1 <= length(s.sentinel)
                # ran out of bytes to match against the sentinel
                # can read up to the last known non-sentinel byte
                return b_idx - s_idx + 1
            end

            r = read(s, UInt8)
            n -= 1

            if s.sentinel[s_idx] == r
                # if this was a continuation from a previous EOF that was reset,
                # pretend this was not a match and reset the skip flag
                if s.skip && s_idx == firstindex(s.sentinel)
                    s.skip = false
                    s.eof = false
                    continue
                end
                s_idx += 1
                b_idx += 1
                if s_idx == lastindex(s.sentinel) + 1
                    # sentinel found
                    # can read up until the byte before the sentinel
                    return b_idx - s_idx + 1
                end
            else
                # reset to closest matching byte found so far
                s_idx = s.failure_function[s_idx]
                if s_idx <= 0
                    # start over
                    b_idx += 1
                    s_idx += 1
                end
            end
        end
    finally
        reset(s)
    end

    throw(ErrorException("unreachable tail"))
end

function Base.eof(s::SentinelIO)
    if s.eof
        return true
    end
    if eof(unwrap(s))
        return s.eof = true
    elseif s.skip
        return s.eof = false
    end
    # finding EOF is much simpler than counting bytes available
    n = bytesavailable(unwrap(s))
    if n < length(s.sentinel)
        # not enough bytes to find sentinel
        return s.eof = false
    end
    mark(s)
    s_idx = firstindex(s.sentinel)
    try
        while true
            r = read(s, UInt8)
            if s.sentinel[s_idx] != r
                return s.eof = false
            else 
                s_idx += 1
                if s_idx == lastindex(s.sentinel) + 1
                    return s.eof = true
                end
            end
        end
    finally
        reset(s)
    end
    return s.eof = false
end

function Base.reseteof(s::SentinelIO)
    Base.reseteof(unwrap(s))
    s.skip = true
    s.eof = false
    return nothing
end
