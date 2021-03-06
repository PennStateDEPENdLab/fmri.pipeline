% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/read_df_sqlite.R
\name{read_df_sqlite}
\alias{read_df_sqlite}
\title{helper function to lookup a keyed data.frame from the sqlite storage database}
\usage{
read_df_sqlite(
  gpa = NULL,
  id = NULL,
  session = NULL,
  run_number = NULL,
  table = NULL,
  drop_keys = TRUE
)
}
\arguments{
\item{id}{the id of the subject to whom these data belong}

\item{run_number}{the run_number of these data}

\item{table}{A character string of the table name to be modified}

\item{sesssion}{the session of these data}

\item{data}{A \code{data.frame} containing the data to be inserted into the sqlite db}

\item{delete_extant}{Whether to delete any existing records for this id + session + run_number combination}

\item{append}{Whether to append records to the table (passed through to dbWriteTable)}

\item{overwrite}{Whether to overwrite the existing table (passed through to dbWriteTable)}
}
\value{
a TRUE/FALSE indicating whether the record was successfully inserted
}
\description{
helper function to lookup a keyed data.frame from the sqlite storage database
}
