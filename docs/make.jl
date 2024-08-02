using TruncatedStreams
using Documenter

DocMeta.setdocmeta!(TruncatedStreams, :DocTestSetup, :(using TruncatedStreams); recursive=true)

makedocs(;
    modules=[TruncatedStreams],
    authors="Phil Killewald <reallyasi9@users.noreply.github.com> and contributors",
    sitename="TruncatedStreams.jl",
    format=Documenter.HTML(;
        canonical="https://reallyasi9.github.io/TruncatedStreams.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/reallyasi9/TruncatedStreams.jl",
    devbranch="main",
)
