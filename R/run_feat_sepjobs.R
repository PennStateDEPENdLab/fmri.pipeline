#' function to submit a set of jobs on a cluster to estimate many Feat level 1 models
#'
#' @param gpa a \code{glm_pipeline_arguments} object containing model specification
#' @param model_names an optional level 1 model name used to subset the runs to submit to feat.
#'   If not provided, all level 1 models in \code{gpa} will be submitted for feat estimation.
#' @param rerun a logical indicating whether to re-run an existing directory. Default: FALSE
#' @param wait_for a parent job that should complete before these jobs commence
#' @return a vector of job ids for all files that were submitted to the cluster
run_feat_sepjobs <- function(gpa, level=1L, model_names=NULL, rerun=FALSE, wait_for="") {
  # this version of the FSL LVL1 feat estimation creates multiple qsub scripts in a temporary directory
  # where each script has a number of feat calls that are forked, then the script waits for completion
  ## This circumvents the ICS limit on multiple nodes in R using a SNOW cluster.
  ## The primary calculation is how many files there are to run relative to processors and files per processor (chunking)

  checkmate::assert_class(gpa, "glm_pipeline_arguments")
  checkmate::assert_integerish(level, lower=1L, upper=3L, len=1L)
  checkmate::assert_character(model_names, null.ok=TRUE)
  checkmate::assert_logical(rerun)

  lg <- lgr::get_logger(paste0("glm_pipeline/l", level, "_estimation"))

  # TODO: support named subsetting in model_names, like list(l1_model="pe_only", l2_model=c("l2_1", "l2_2"))
  # level-specific copy-paste is a bit clunky here, but at least it's clear...
  if (level == 1) {
    if (!checkmate::test_class(gpa$l1_model_setup, "l1_setup")) {
      lg$error("In run_feat_sepjobs, did not find an l1_setup object in gpa$l1_model_setup.")
      lg$error("Make sure to run setup_l1_models before running run_feat_sepjobs")
      return(NULL)
    }

    if (!is.null(model_names[1L])) {
      feat_queue <- gpa$l1_model_setup$fsl %>% dplyr::filter(l1_model %in% !!model_names)
    } else {
      feat_queue <- gpa$l1_model_setup$fsl
    }

    fsf_files <- feat_queue$l1_feat_fsf
    dir_expect <- feat_queue$l1_feat_dir
    feat_time <- gpa$parallel$fsl$l1_feat_time
    feat_memgb <- gpa$parallel$fsl$l1_feat_memgb
  } else if (level == 2) {
    if (!checkmate::test_class(gpa$l2_model_setup, "l2_setup")) {
      lg$error("In run_feat_sepjobs, did not find an l2_setup object in gpa$l2_model_setup.")
      lg$error("Make sure to run setup_l2_models before running run_feat_sepjobs")
      return(NULL)
    }

    if (!is.null(model_names[1L])) {
      feat_queue <- gpa$l2_model_setup$fsl %>% dplyr::filter(l2_model %in% !!model_names)
    } else {
      feat_queue <- gpa$l2_model_setup$fsl
    }

    fsf_files <- feat_queue$l2_feat_fsf
    dir_expect <- feat_queue$l2_feat_dir
    feat_time <- gpa$parallel$fsl$l2_feat_time
    feat_memgb <- gpa$parallel$fsl$l2_feat_memgb
  } else if (level == 3) {
    if (!checkmate::test_class(gpa$l3_model_setup, "l3_setup")) {
      lg$error("In run_feat_sepjobs, did not find an l3_setup object in gpa$l3_model_setup.")
      lg$error("Make sure to run setup_l2_models before running run_feat_sepjobs")
      return(NULL)
    }

    if (!is.null(model_names[1L])) {
      feat_queue <- gpa$l3_model_setup$fsl %>% dplyr::filter(l3_model %in% !!model_names)
    } else {
      feat_queue <- gpa$l3_model_setup$fsl
    }

    fsf_files <- feat_queue$l3_feat_fsf
    dir_expect <- feat_queue$l3_feat_dir
    feat_time <- gpa$parallel$fsl$l3_feat_time
    feat_memgb <- gpa$parallel$fsl$l3_feat_memgb
  }

  # need this to be cached somewhere...
  feat_working_directory <- file.path(gpa$working_directory, paste0("feat_l", level))

  cpusperjob <- 8 #number of cpus per qsub
  runsperproc <- 2 #number of feat calls per processor

  # figure out which fsf files have already been run
  # dir_expect <- gsub("\\.fsf$", ".feat", fsf_files, perl=TRUE)

  to_run <- c()

  for (f in seq_along(fsf_files)) {
    if (dir.exists(dir_expect[f])) {
      if (rerun) {
        cmd <- paste0("rm -rf \"", dir_expect[f], "\"")
        lg$info("Removing old directory: %s", cmd)
        system(cmd)
        to_run <- c(to_run, fsf_files[f]) #add to queue
      } else {
        lg$info("Skipping existing directory: %s", dir_expect[f])
      }
    } else {
      to_run <- c(to_run, fsf_files[f])
    }
  }

  if (length(to_run) == 0L) {
    lg$warn("No Feat level %d .fsf files to execute.", level)
    return(NULL)
  }

  lg$info("About to run the following fsf files in parallel:")
  lg$info("  File: %s", to_run)

  if (gpa$scheduler == "slurm") {
    file_suffix <- ".sbatch"
    preamble <- c(
      "#!/bin/bash",
      "#SBATCH -N 1", #always single node for now
      paste0("#SBATCH -n ", cpusperjob),
      paste0("#SBATCH --time=", feat_time),
      paste0("#SBATCH --mem-per-cpu=", feat_memgb, "G"),
      sched_args_to_header(gpa), # analysis-level SBATCH directives
      "",
      "",
      gpa$parallel$fsl$compute_environment,
      "",
      "cd $SLURM_SUBMIT_DIR"
    )

  } else if (gpa$scheduler == "torque") {
    file_suffix <- ".pbs"
    preamble <- c(
      "#!/bin/bash",
      paste0("#PBS -l nodes=1:ppn=", cpusperjob),
      paste0("#PBS -l pmem=", feat_memgb, "gb"),
      ifelse(wait_for != "", paste0("#PBS -W depend=afterok:", wait_for), ""), # allow job dependency on upstream setup
      paste0("#PBS -l walltime=", feat_time),
      sched_args_to_header(gpa), # analysis-level PBS directives
      "",
      "",
      gpa$parallel$fsl$compute_environment,
      "",
      "cd $PBS_O_WORKDIR"
    )
  }

  if (!file.exists(feat_working_directory)) {
    lg$debug("Creating l%d working directory: %s", level, feat_working_directory)
    dir.create(feat_working_directory, recursive = TRUE)
  }

  njobs <- ceiling(length(to_run) / (cpusperjob*runsperproc))

  #use length.out on rep to ensure that the vectors align even if chunks are uneven wrt files to run
  df <- data.frame(fsf=to_run, job=rep(1:njobs, each=cpusperjob*runsperproc, length.out=length(to_run)), stringsAsFactors=FALSE)
  df <- df[order(df$job), ]

  submission_id <- basename(tempfile(pattern = "job"))
  joblist <- rep(NA_character_, njobs)
  for (j in seq_len(njobs)) {
    outfile <- paste0(feat_working_directory, "/featsep_l", level, "_", j, "_", submission_id, file_suffix)
    cat(preamble, file=outfile, sep="\n")
    thisrun <- with(df, fsf[job==j])
    cat(
      "function feat_runner() {",
      ifelse(level == 1L, "  local odir=\"${1/.fsf/.feat}\"", "  local odir=\"${1/.fsf/.gfeat}\""),
      "  [ -f \"${odir}/.feat_fail\" ] && rm -f \"${odir}/.feat_fail\"",
      "  start_time=$( date )",
      "  feat $1",
      "  exit_code=$?",
      "  end_time=$( date )",
      "  if [ $exit_code -eq 0 ]; then",
      "    status_file=\"${odir}/.feat_complete\"",
      "  else",
      "    status_file=\"${odir}/.feat_fail\"",
      "  fi",
      "  echo $start_time > \"${status_file}\"",
      "  echo $end_time >> \"${status_file}\"",
      "}",
      sep = "\n", file = outfile, append = TRUE
    )
    cat(paste("feat_runner", thisrun, "&"), file=outfile, sep="\n", append=TRUE)
    cat("wait\n\n", file=outfile, append=TRUE)
    cat(paste(
      "bash", system.file("bash/gen_feat_reg_dir", package = "fmri.pipeline"),      
      unique(dirname(thisrun))
    ), sep = "\n", file = outfile, append = TRUE)
    joblist[j] <- cluster_job_submit(outfile)
    #joblist[j] <- "dummy"
  }

  # write the list of separate feat qsub jobs that are now queued (so that LVL2 can wait on these)
  # should also return this to the caller as a function?
  writeLines(joblist, con = file.path(feat_working_directory, paste0("sep_l", level, "_jobs.txt")))

  return(joblist)
}
