using FeatherScope
using Documenter

DocMeta.setdocmeta!(FeatherScope, :DocTestSetup, :(using FeatherScope); recursive=true)

makedocs(;
    modules=[FeatherScope],
    authors="Galen Lynch <galen@galenlynch.com>",
    sitename="FeatherScope.jl",
    format=Documenter.HTML(;
        canonical="https://galenlynch.github.io/FeatherScope.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/galenlynch/FeatherScope.jl",
    devbranch="main",
)
