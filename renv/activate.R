local({
  project <- getwd()
  libpath <- Sys.getenv("RENV_PATHS_LIBRARY", unset = file.path(project, "renv/library"))
  if (!requireNamespace("renv", quietly = TRUE)) {
    repos <- Sys.getenv("RENV_REPOS_OVERRIDE", unset = "https://cloud.r-project.org")
    install.packages("renv", repos = repos)
  }
  renv::load(project = project)
})
