% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ouija.R
\name{plot.ouija_fit}
\alias{plot.ouija_fit}
\title{Plot a \code{ouija_fit}}
\usage{
\method{plot}{ouija_fit}(x, what = c("behaviour", "behavior", "diagnostic",
  "heatmap", "pp", "dropout"), ...)
}
\arguments{
\item{x}{An object of class \code{ouija_fit}}

\item{what}{One of
\itemize{
\item \code{heatmap} This produces a heatmap of gene expression as a function of pseudotime
across different pseudotime samples. Underlying call is to \code{\link{plot_ouija_fit_heatmap}}.
\item \code{behaviour} This plots gene expression as a function of the MAP pseudotime with a red
line denoting the mean sigmoid trend. Underlying call is to
\code{\link{plot_ouija_fit_behaviour}}
\item \code{diagnostic} This returns trace and autocorrelation plots of the log-posterior
probability. Underlying call is to \code{\link{plot_ouija_fit_diagnostics}}
\item \code{pp} This returns density plots of posterior distributions for either activation
strength parameters \code{k} or activation time parameters \code{t0}.
\item \code{dropout} Returns a plot showing the relationship between latent expression
value and dropout probability. 
Underlying call is to \code{\link{plot_ouija_fit_dropout_probability}}
}}

\item{...}{Additional arguments passed to the corresponding functions}
}
\value{
A \code{ggplot2} plot.
}
\description{
Plot a \code{ouija_fit} object. Returns a plot of either
\itemize{
\item{diagnostic} Trace and autocorrelation plots of the log-posterior
probability. Underlying call is to \code{\link{plot_ouija_fit_diagnostics}}
\item{behaviour}  Gene expression as a function of the MAP pseudotime with a red
line denoting the mean sigmoid trend
\item{heatmap} A heatmap of gene expression as a function of pseudotime
across different pseudotime samples.
\item{pp} Density plots comparing prior to posterior distributions for the
activation parameters.
\item{dropout} The relationship between latent expression
value and dropout probability. 
}
}

