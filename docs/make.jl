using DAQespmcp
using Documenter

DocMeta.setdocmeta!(DAQespmcp, :DocTestSetup, :(using DAQespmcp); recursive=true)

makedocs(;
    modules=[DAQespmcp],
    authors="Paulo José Saiz Jabardo",
    repo="https://github.com/pjsjipt/DAQespmcp.jl/blob/{commit}{path}#{line}",
    sitename="DAQespmcp.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)
