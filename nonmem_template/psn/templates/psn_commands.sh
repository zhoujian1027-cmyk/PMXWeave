#!/usr/bin/env bash

MODEL=run_base.mod          # the converted, PsN-ready control stream
SCM=run_base.scm            # generated from templates/scm_config.scm

scm -config_file="$SCM" -seed=12345 -missing_data_token=-99

bootstrap "$MODEL" -samples=2000 -seed=12345 -threads=8 -dir=boot_run1
