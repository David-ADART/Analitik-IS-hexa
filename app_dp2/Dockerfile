FROM rocker/r-ver:4.4.2

RUN apt-get update && apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libssl-dev \
        libxml2-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/* \
    && install2.r --error --skipinstalled plumber dplyr jsonlite

WORKDIR /app
COPY motor.R api.R index.html ./
COPY css ./css
COPY js ./js

ENV PORT=8080
EXPOSE 8080

CMD ["Rscript", "-e", "plumber::plumb('api.R')$run(host='0.0.0.0', port=as.integer(Sys.getenv('PORT', '8080')))"]
