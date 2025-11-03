FROM rocker/r-ver:4.3.3

ENV RENV_VERSION=1.0.7 \
    RENV_PATHS_CACHE=/renv/cache

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libcurl4-openssl-dev \
      libssl-dev \
      libicu-dev && \
    rm -rf /var/lib/apt/lists/*

RUN R -e "install.packages('renv', repos = 'https://cloud.r-project.org')"

WORKDIR /workspace
COPY . .

RUN R -e "renv::consent(provided = TRUE); renv::restore(lockfile = 'renv.lock', prompt = FALSE)"

CMD ["R", "-q"]
