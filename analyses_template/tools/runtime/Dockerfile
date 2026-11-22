ARG BASE_IMAGE=rocker/rstudio:4.5.1
FROM ${BASE_IMAGE}
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 nodejs libwebpmux3 \
    && rm -rf /var/lib/apt/lists/*
