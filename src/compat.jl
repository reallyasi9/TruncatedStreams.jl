# circshift!, taken straight from Julia source, modified to only use the signature we need
function circshift!(a::Vector{UInt8}, shift::Integer)
    n = length(a)
    n == 0 && return a
    shift = mod(shift, n)
    shift == 0 && return a
    l = lastindex(a)
    reverse!(a, firstindex(a), l-shift)
    reverse!(a, l-shift+1, lastindex(a))
    reverse!(a)
    return a
end