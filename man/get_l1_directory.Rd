% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/glm_helper_functions.R
\name{get_l1_directory}
\alias{get_l1_directory}
\title{small helper function to return the location of an l1 directory based on
  id, session, and run number}
\usage{
get_l1_directory(
  id = NULL,
  session = NULL,
  run_number = NULL,
  model_name = NULL,
  gpa,
  glm_software = "fsl",
  create_if_missing = FALSE
)
}
\arguments{
\item{id}{The id of a participant}

\item{session}{The session number to lookup}

\item{run_number}{The run number to lookup}

\item{gpa}{A \code{glm_pipeline_arguments} object}

\item{glm_software}{which software is being used for the analysis (since directories may vary)}

\item{create_if_missing}{whether to create the directory if it does not exist}
}
\description{
small helper function to return the location of an l1 directory based on
  id, session, and run number
}
