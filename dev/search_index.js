var documenterSearchIndex = {"docs":
[{"location":"","page":"Home","title":"Home","text":"CurrentModule = TruncatedStreams","category":"page"},{"location":"#TruncatedStreams","page":"Home","title":"TruncatedStreams","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Documentation for TruncatedStreams.","category":"page"},{"location":"","page":"Home","title":"Home","text":"","category":"page"},{"location":"","page":"Home","title":"Home","text":"Modules = [TruncatedStreams]","category":"page"},{"location":"#TruncatedStreams.FixedLengthIO","page":"Home","title":"TruncatedStreams.FixedLengthIO","text":"FixedLengthIO(io, length) <: TruncatedIO\n\nA truncated source that reads io up to length bytes.\n\n\n\n\n\n","category":"type"},{"location":"#TruncatedStreams.SentinelIO","page":"Home","title":"TruncatedStreams.SentinelIO","text":"SentinelIO(io, sentinel) <: TruncatedIO\n\nA truncated source that reads io until sentinel is found.\n\nCan be reset with the reseteof() method if the sentinel read is discovered upon further inspection to be bogus.\n\nThe wrapped stream io must implement mark and reset.\n\n\n\n\n\n","category":"type"},{"location":"#TruncatedStreams.TruncatedIO","page":"Home","title":"TruncatedStreams.TruncatedIO","text":"TruncatedIO <: IO\n\nWraps an IO stream object and lies about how much is left to read from the stream.\n\nObjects inheriting from this abstract type pass along all IO methods to the wrapped stream except for bytesavailable(io) and eof(io). Inherited types need to implement:\n\nunwrap(::AbstractTruncatedSource)::IO: return the wrapped IO stream.\nBase.bytesavailable(::AbstractTruncatedSource)::Int: report the number of bytes available to\n\nread from the stream until EOF or a buffer refill.\n\nBase.eof(::AbstractTruncatedSource)::Bool: report whether the stream cannot produce any more\n\nbytes.\n\nOptional methods to implement that might be useful are:\n\nBase.reseteof(::AbstractTruncatedSource)::Nothing: reset EOF status.\nBase.unsafe_read(::AbstractTruncatedSource, p::Ptr{UInt8}, n::UInt)::Nothing: copy n bytes from the stream into memory pointed to by p.\nBase.seek(::TruncatedIO, n::Integer) and Base.seekend(::TruncatedIO): seek stream to position n or end of stream.\nBase.reset(::TruncatedIO): reset a marked stream to the saved position.\n\n\n\n\n\n","category":"type"},{"location":"#TruncatedStreams.unwrap","page":"Home","title":"TruncatedStreams.unwrap","text":"unwrap(s<:TruncatedIO) -> IO\n\nReturn the wrapped source.\n\n\n\n\n\n","category":"function"}]
}
