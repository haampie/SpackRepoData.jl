module SpackData

import GitHub
using JLD2
using Dates
using PGFPlotsX

const repo_path = "spack/spack"

const safe_repo_name = replace(repo_path, '/' => '-')

function download_issues()
  myauth = GitHub.authenticate(ENV["GITHUB_AUTH"])    
  repo = GitHub.repo(repo_path)
  myparams = Dict("state" => "all", "per_page" => 100, "page" => 1);
  issues, _ = GitHub.issues(repo; params = myparams, auth = myauth)
  return issues
end

function save_issues(issues)
    f = jldopen("issues.jld", "w")
    write(f, "issues", issues)
    close(f)
end

function load_issues()
    f = jldopen("issues.jld", "r")
    issues = read(f, "issues")
    close(f)
    return issues
end

## package pr stuff

is_new_package(issue) = any(label -> label["name"] ∈ ("new-package",), issue.labels)
is_package(issue) = any(label -> label["name"] ∈ ("new-version", "update-package", "new-variant"), issue.labels)
is_core(issue) = any(label -> label["name"] ∈ ("core","architecture","binary-packages","build-environment","build-systems","new-command","commands","compilers","directives","environments","fetching","locking","modules","stage","tests","utilities","versions"), issue.labels)
is_merged_pr(issue) = issue.pull_request !== nothing && issue.pull_request.merged_at !== nothing && issue.state == "closed"
is_merged_package_pr(issue) = is_merged_pr(issue) && is_package(issue)
is_merged_new_package_pr(issue) = is_merged_pr(issue) && is_new_package(issue)
is_merged_internal_pr(issue) = is_merged_pr(issue) && is_core(issue)


function get_quantiles!(xs)
  length(xs) == 0 && return 0, 0, 0
  i_10 = ceil(Int, 0.1 * length(xs))
  i_50 = ceil(Int, 0.5 * length(xs))
  i_90 = ceil(Int, 0.9 * length(xs))
  p_10 = partialsort!(xs, i_10)
  p_50 = partialsort!(xs, i_50)
  p_90 = partialsort!(xs, i_90)
  return p_10, p_50, p_90
end

"""
Show robust statistics (10, 50, 90)'th percentile of closing stats
from a window of `window` days.
"""
function plot_close_quantiles(issues, window = 30)
  sort!(issues, by=issue -> issue.created_at)

  min_date = Date(issues[begin].created_at)
  total_days = (Date(now()) - min_date).value + 1

  # percentiles in window around every day.
  p10s, p50s, p90s = zeros(Int, total_days), zeros(Int, total_days), zeros(Int, total_days)

  milliseconds = Int[]
  days = Int[]

  current_pr = 1

  for day in 1:total_days
    # first remove data outside of this window
    while length(days) > 0 && days[begin] + window ≤ day
      popfirst!(days)
      popfirst!(milliseconds)
    end

    # then consume more days
    while current_pr ≤ length(issues) && (Date(issues[current_pr].created_at) - min_date).value + 1 == day
      push!(days, day)
      push!(milliseconds, (issues[current_pr].closed_at - issues[current_pr].created_at).value)
      current_pr += 1
    end

    println(length(days))

    p10s[day], p50s[day], p90s[day] = get_quantiles!(copy(milliseconds))
  end

  xs = range(min_date, length=total_days, step=Day(1))

  p10s_days = p10s ./ (1000 * 60 * 60 * 24)
  p50s_days = p50s ./ (1000 * 60 * 60 * 24)
  p90s_days = p90s ./ (1000 * 60 * 60 * 24)

  push!(PGFPlotsX.CUSTOM_PREAMBLE, raw"\usepgfplotslibrary{fillbetween}")

  @pgf time_to_close_plot = PGFPlotsX.Axis(
    {
      width = "20cm",
      height = "10cm",
      date_coordinates_in = "x",
      x_tick_label_style = "{rotate=45}",
      xticklabel = "{\\year}",
      # xmin = "$(min_date)",
      xmin = "2017-01-01",
      xmax = "$(Date(Dates.now()))",
      xtick = "{2017-01-01,2018-01-01,2019-01-01,2020-01-01,2021-01-01,2022-01-01}",
      xticklabel = "{\\year}",
      ymin = "0",
      ytick = "{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14}",
      ylabel = "Days",
      title = "Time from opened to closed [$(repo_path)]",
      xmajorgrids,
      ymajorgrids,
    },
    PGFPlotsX.Plot({ "name path=f", "draw=none" }, Table(; x = xs, y = p10s_days)),
    PGFPlotsX.Plot({ "name path=g", "draw=none" }, Table(; x = xs, y = p90s_days)),
    PGFPlotsX.Plot({ color = "blue", fill = "blue", opacity = 0.3}, raw"fill between [of=f and g]"),
    PGFPlotsX.Plot({ no_marks, color = "black", thick }, Table(; x = xs, y = p50s_days))
  )

  pgfsave("time-to-close-$(safe_repo_name).pdf", time_to_close_plot)

  return xs, p10s, p50s, p90s
end

using Colors


"""
Show what % of prs was merged within `max_days` days in the last `window` days.
"""
function plot_fraction_merged_within(issues; max_days = [1, 2, 7, 30], window = 30)
  sort!(issues, by=issue -> issue.created_at)

  min_date = Date(issues[begin].created_at)
  total_days = (Date(now()) - min_date).value + 1

  # percentiles in window around every day.
  fractions = [zeros(Float64, total_days) for _ in max_days]
  new_prs = zeros(Int, total_days)
  milliseconds = Int[]
  days = Int[]
  current_pr = 1

  for day in 1:total_days
    # first remove data outside of this window
    while length(days) > 0 && days[begin] + window ≤ day
      popfirst!(days)
      popfirst!(milliseconds)
    end

    # then consume more days
    while current_pr ≤ length(issues) && (Date(issues[current_pr].created_at) - min_date).value + 1 == day
      push!(days, day)
      push!(milliseconds, (issues[current_pr].closed_at - issues[current_pr].created_at).value)
      current_pr += 1
    end

    for (idx, max_day) in enumerate(max_days)
      fractions[idx][day] = 100 * count(x -> x < 1000 * 3600 * 24 * max_day, milliseconds) / length(milliseconds)
    end
    new_prs[day] = length(days)
  end

  xs = range(min_date, length=total_days, step=Day(1))
  colors = distinguishable_colors(length(max_days), [RGB(1,1,1), RGB(0,0,0)], dropseed=true)

  @pgf time_to_close_plot = TikzPicture(
    PGFPlotsX.Axis(
      {
        "axis y line*" = "right",
        width = "20cm",
        height = "10cm",
        date_coordinates_in = "x",
        xmin = "2017-01-01",
        xmax = "$(Date(Dates.now()))",
        ymin = 0,
        "xmajorticks" = "false",
        "xminorticks" = "false",
        ylabel = "\\# package prs",
      },
      PGFPlotsX.Plot({ no_marks, thick }, Table(; x = xs, y = new_prs)),
    ),
    PGFPlotsX.Axis(
      {
        "axis y line*" = "left",
        "legend pos" = "south east",
        width = "20cm",
        height = "10cm",
        date_coordinates_in = "x",
        x_tick_label_style = "{rotate=45}",
        xmin = "2017-01-01",
        xmax = "$(Date(Dates.now()))",
        xtick = "{2017-01-01,2018-01-01,2019-01-01,2020-01-01,2021-01-01,2022-01-01}",
        xticklabel = "{\\year}",
        ymin=0,
        ymax=100,
        ylabel = "\\% merged",
        ytick = "{0,10,20,30,40,50,60,70,80,90,100}",
        title = "Percentage of package PRs merged within $window days [$(repo_path)]",
        xmajorgrids,
        ymajorgrids,
      },
      [PGFPlotsX.Plot({ no_marks, thick, color = colors[i] }, Table(; x = xs, y = fraction)) for (i, fraction) in enumerate(fractions)]...,
      Legend(["$d days" for d in max_days])
    )
  )

  filename = "percentage-closed-$(safe_repo_name).pdf"

  @info "Saving as" filename
  pgfsave("percentage-closed-$(safe_repo_name).pdf", time_to_close_plot)

  return xs, fractions, new_prs
end

end # module
