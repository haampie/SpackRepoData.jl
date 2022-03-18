# SpackRepoData.jl

Generate plots for activity in [spack/spack](https://github.com/spack/spack).

## Install

Open the package manager in the REPL via `]` and run

```julia
(v1.7) pkg> add https://github.com/haampie/SpackRepoData.jl.git
```
## Generate

```julia
julia> using SpackData: download_issues, is_merged_package_pr, plot_fraction_merged_within

julia> issues = download_issues() # takes a while, github's api is not very fast.

julia> prs = filter(is_merged_package_pr, issues)

julia> plot_fraction_merged_within(prs, max_days=[1, 2, 7, 30], window=365)
┌ Info: Saving as
└   filename = "percentage-closed-spack-spack.pdf"
```
