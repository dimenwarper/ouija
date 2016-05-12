## Bayesian non-linear factor analysis for incorporating 
## prior knowledge into single-cell trajectory learning
## kieranc@well.ox.ac.uk


#' Fit a Ouija object.
#' 
#' Fit a Bayesian non-linear factor analysis model given some single-cell
#' gene expression data.
#' 
#' This function takes either a \code{SCESet} object or an expression matrix
#' and returns a \code{ouija_fit} object including posterior traces for all
#' variables.
#' 
#' @param x Either an \code{SCESet} from \code{scater} or a
#' cell-by-gene (N by G) matrix of non-negative values representing gene expression.
#' log2(TPM + 1) is recommended.
#' @param strengths G mean activation strength parameters
#' @param times G mean activation time parameters
#' @param strength_sd Optional standard deviations for k parameters
#' @param time_sd Optional standard deviations for t0 parameters
#' @param response The type of factor analysis, either \code{nonlinear} (default) 
#' or \code{linear} 
#' @param warn_lp Ouija can perform a crude check of convergence in cases where may
#' models are being fit and manual inspection may be cumbersome. The log-likelihood after
#' the burn period is regressed off the iteration number, and if the gradient of the fit
#' falls above a threshold (set by \code{lp_gradient_threshold}) then the user is warned.
#' @param lp_gradient_threshold The threshold for convergence warning. If the slope of regressing
#' the log-probability of the model against the iteration number falls above this value then
#' the user is warned.
#' @param ... Additional arguments to \code{rstan::sampling}
#' 
#' @import rstan
#' 
#' @export
#' 
#' @return An object of type \code{ouija_fit}
ouija <- function(x, 
                  strengths = NULL, times = NULL,
                  strength_sd = NULL, time_sd = NULL,
                  response = c("nonlinear", "linear"),
                  warn_lp = TRUE,
                  lp_gradient_threshold = 1e-2,
                  ...) {
  # require(rstan) # for some reason this is required despite the @import rstan
  
  ## Find out what sort of model we're trying to fit
  response <- match.arg(response)
  if(response != "nonlinear") stop("Only nonlinear factor analysis currently supported")
  
  model_file <- "ouija.stan"

  Y <- NULL
  if(is(x, "SCESet")) {
    ## convert to expression matrix Y  
    Y <- t(exprs(x))
  } else {
    Y <- x
  }
  if(!is(Y, "matrix")) {
    stop("x must either be an SCESet or matrix of gene expression values")
  }
  
  ## Now sanitize the input
  G <- ncol(Y) # number of genes
  N <- nrow(Y) # number of cells
  
  # we can fill in some values if they're null
  if(is.null(strengths)) strengths = rep(0, G)
  if(is.null(strength_sd)) strength_sd <- rep(1, G)
  if(is.null(times)) times <- rep(0.5, G) ## change if constrained
  if(is.null(time_sd)) time_sd <- rep(1, G)

  stopifnot(length(strengths) == G)
  stopifnot(length(strength_sd) == G)
  if(response == "nonlinear") { # now we have t0 parameters
    stopifnot(length(times) == G)
    stopifnot(length(time_sd) == G)
  }

  ## stan setup
  data <- list(Y = t(Y), G = G, N = N,
               k_means = strengths, k_sd = strength_sd,
               t0_means = times, t0_sd = time_sd)
  
  stanfile <- system.file(model_file, package = "ouija")
  model <- stan_model(stanfile)
  
  ## manipulate stan defaults
  stanargs <- list(...)
  if(!('iter' %in% names(stanargs))) stanargs$iter <- 1e4
  if(!('warmup' %in% names(stanargs))) stanargs$warmup <- stanargs$iter / 2
  if(!('chains' %in% names(stanargs))) stanargs$chains <- 1
  if(!('thin' %in% names(stanargs))) {
    # always specify thin so that approximately 1000 samples are returned
    stanargs$thin <- ceiling((stanargs$iter - stanargs$warmup) / 1000)
  }
  stanargs$object <- model
  stanargs$data <- data
  
  ## call sampling
  fit <- do.call(sampling, stanargs)
  
  ## Do a really dumb automated check of convergence:
  if(warn_lp) {
    lp <- extract(fit, pars = "lp__")$lp__
    siter <- seq_along(lp)
    lplm <- lm(lp ~ siter)
    if(coef(lplm)[2] > lp_gradient_threshold) {
      warning(paste("Gradient of log-probability against iteration greater than threshold: "), coef(lmlp)[2])
      warning("Model may not be converged")
    }
  }
    
  oui <- structure(list(fit = fit, G = G, N = N, Y = Y,
                       iter = stanargs$iter, chains = stanargs$chains,
                       thin = stanargs$thin), 
                  class = "ouija_fit")
  return(oui)
}

#' Extract the MAP pseudotime estimates from a \code{ouija_fit}
#' 
#' @param oui An object of class \code{ouija_fit}.
#' 
#' @importFrom MCMCglmm posterior.mode
#' @importFrom rstan extract
#' @importFrom coda mcmc
#' 
#' @export
#' 
#' @return MAP pseudotime vector of length N
map_pseudotime <- function(oui) UseMethod("map_pseudotime")

#' Extract the MAP pseudotime estimates from a \code{ouija_fit}
#'
#' @param oui An object of class \code{ouija_fit}.
#' 
#' @importFrom MCMCglmm posterior.mode
#' @importFrom rstan extract
#' @importFrom coda mcmc
#' 
#' @export
#' 
#' @return MAP pseudotime vector of length N
map_pseudotime.ouija_fit <- function(oui) {
  stopifnot(is(oui, "ouija_fit"))
  posterior.mode(mcmc(extract(oui$fit, "t")$t))
}

#' Reconstructed pseudotimes
#' @export
rexprs <- function(oui) UseMethod("rexprs")

#' @importFrom MCMCglmm posterior.mode
#' @importFrom rstan extract
#' @importFrom coda mcmc
#' @export
rexprs.ouija_fit <- function(oui) {
  stopifnot(is(oui, "ouija_fit"))
  Z <- apply(extract(oui$fit, "mu")$mu, 3, function(x) posterior.mode(mcmc(x)))
  Z <- t(Z)
  colnames(Z) <- colnames(oui$Y)
  return(Z)
}


#' Print a \code{ouija_fit}
#' 
#' @param x An object of class \code{ouija_fit}.
#' 
#' @export
print.ouija_fit <- function(x) {
  cat(paste("A Bayesian non-linear factor analysis fit with\n"),
          paste(x$N, "cells and", x$G, "marker genes\n"),
          paste("MCMC info:", x$iter, "iterations on", x$chains, "chains"))
}

#' Plot a \code{ouija_fit}
#' 
#' Plot a \code{ouija_fit} object. Returns either a trace fit, MAP fit or MCMC diagnostic fit.
#' See the individual function calls (described below) for more details.
#' 
#' @param x An object of class \code{ouija_fit}
#' @param what One of
#' \itemize{
#' \item \code{trace} This produces a heatmap of gene expression as a function of pseudotime
#' across different pseudotime samples. Underlying call is to \code{\link{plot_ouija_fit_trace}}.
#' \item \code{map} This plots gene expression as a function of the MAP pseudotime with a red
#' line denoting a LOESS fit (showing the overall trend). Underlying call is to
#' \code{\link{plot_ouija_fit_map}}
#' \item \code{diagnostic} This returns trace and autocorrelation plots of the log-posterior
#' probability. Underlying call is to \code{\link{plot_ouija_fit_diagnostics}}
#' \item \code{dropout} Returns a plot showing the relationship between latent expression
#' value and dropout probability. 
#' Underlying call is to \code{\link{plot_ouija_fit_dropout_probability}}
#' }
#' @param ... Additional arguments passed to the corresponding functions
#' 
#' @return A \code{ggplot2} plot.
#' 
#' @export
plot.ouija_fit <- function(x, what = c("trace", "map", "diagnostic", "dropout"), ...) {
  what <- match.arg(what)
  plt <- switch(what,
                trace = plot_ouija_fit_trace(x, ...),
                map = plot_ouija_fit_map(x, ...),
                diagnostic = plot_ouija_fit_diagnostics(x, ...),
                dropout = plot_ouija_fit_dropout_probability(x, ...))
  return(plt)
}

#' Plot MCMC diagnostics.
#' 
#' Plot MCMC diagnostics (traceplot and autocorrelation) of the log-posterior probability
#' for a \code{ouija_fit} object.
#' 
#' Further assessment of convergence can be done using \code{rstan} functions on the
#' underlying STAN object (accessed through \code{oui$fit}).
#' 
#' @param oui A \code{ouija_fit} object
#' @param nrow Number of rows. If 1, plots are side-by-side; if 2, plots are vertically aligned.
#' @export
#' @importFrom cowplot plot_grid
#' 
#' @return A \code{ggplot2} object
#' 
plot_ouija_fit_diagnostics <- function(oui, arrange = c("vertical", "horizontal")) {
  stopifnot(is(oui, "ouija_fit"))
  arrange <- match.arg(arrange)
  nrow <- switch(arrange,
                 vertical = 2,
                 horizontal = 1)
  plt <- cowplot::plot_grid(stan_trace(oui$fit, "lp__"), stan_ac(oui$fit, "lp__"), nrow = nrow)
  return(plt)
}

#' Plot heatmaps of gene expression changes
#' 
#' Produces a heatmap of gene expression as a function of pseudotime
#' across different pseudotime samples.
#' 
#' @param oui An object of class \code{ouija_fit}
#' @param samples Number of posterior pseudotime samples to use (number of rows of heatmap)
#' @param genes A vector that subsets the gene expression matrix. Defaults to the first \code{g}
#' genes, where \code{g} is either 4 or the number of genes in the model if less than 4.
#' @param output If \code{grid} then \code{cowplot::plot_grid} is called and a grid plot
#' of all genes is returned. If \code{plotlist} then a list of \code{ggplot2} objects is returned 
#' for the user to customise further
#' @param show_legend Logical. If \code{TRUE} then the legend (ie gene expression magnitude) is
#' displayed for each heatmap.
#' @param ... Additional arguments passed to \code{cowplot::plot_grid}
#' 
#' @importFrom rstan extract
#' @importFrom cowplot plot_grid
#' @importFrom viridis scale_fill_viridis
#' @importFrom reshape2 melt
#' 
#' 
#' @param samples Number of posterior pseudotime samples to use
#' @export
#' 
#' @return A \code{ggplot2} object.
plot_ouija_fit_trace <- function(oui, samples = 50, genes = seq_len(min(oui$G, 6)),
                                 output = c("grid", "plotlist"), 
                                 show_legend = FALSE, ...) {
  stopifnot(is(oui, "ouija_fit"))
  output <- match.arg(output)
  
  ttrace <- extract(oui$fit, "t")$t
  to_sample <- sample(seq_len(min(nrow(ttrace), samples)))
  ttrace <- ttrace[to_sample, ]
  cell_orders <- apply(ttrace, 1, order)
  # apply over genes
  plts <- lapply(genes, function(g) {
    yg <- oui$Y[,g]
    Xg <- apply(cell_orders, 2, function(or) yg[or])
    Xg <- data.frame(Xg)
    names(Xg) <- 1:ncol(Xg)
    Xg$x <- 1:nrow(Xg)
    Xm <- melt(Xg, id.vars = "x", variable.name = "y", value.name = "Expression")
    
    plt <- ggplot(Xm, aes(x = x, y = y, fill = Expression)) + geom_tile() +
      xlab("Cell") + ylab(expression("Pseudotime\n sample")) + 
      scale_fill_viridis() + 
      theme_bw() + 
      theme(axis.ticks = element_blank(),
            axis.line = element_blank(),
            panel.grid = element_blank(),
            panel.border = element_blank(),
            axis.text = element_blank())
    if(!show_legend) plt <- plt + theme(legend.position = "none")
    return( plt )
  })

  if(output == "grid") {
    return(plot_grid(plotlist = plts, scale = 0.9, ...))
  } else {
    return( plts )
  }
}

#' Generic function to return sigmoid whenever needed
tsigmoid <- function(mu0, k, t0, t) {
  return( 2 * mu0 / (1 + exp(-k*(t - t0))))
}

#' Plot gene expression as a function of MAP pseudotime
#' 
#' Plot gene expression as a function of the MAP pseudotime with a red
#' line denoting a LOESS fit (showing the overall trend). Genes are plotted with
#' one per grid square (using a call to \code{facet_wrap(~ gene)}).
#' 
#' @param oui An object of class \code{ouija_fit}
#' @param genes A vector that subsets the gene expression matrix. Defaults to the first \code{g}
#' genes, where \code{g} is either 4 or the number of genes in the model if less than 4.
#' 
#' @importFrom reshape2 melt
#' @importFrom rstan extract
#' @importFrom MCMCglmm posterior.mode
#' @importFrom coda mcmc
#' @importFrom dplyr inner_join
#' @import ggplot2
#' 
#' @export
#' 
#' @return An object of class \code{ggplot2}
plot_ouija_fit_map <- function(oui, genes = seq_len(min(oui$G, 6)),
                               expression_units = "log2(TPM+1)") {
  stopifnot(is(oui, "ouija_fit"))
  tmap <- map_pseudotime(oui)
  Y <- oui$Y
  

  ## want to plot sigmoid function so need MAP estimates
  extr <- extract(oui$fit, pars = c("mu0", "k", "t0"))
  mu0_map <- posterior.mode(mcmc(extr$mu0))
  k_map <- posterior.mode(mcmc(extr$k))
  t0_map <- posterior.mode(mcmc(extr$t0))
  sig_map <- data.frame(mapply(tsigmoid, mu0_map, k_map, t0_map, MoreArgs = list(t = tmap)))
  names(sig_map) <- colnames(Y)

  
  ## Create data frame for gene expression values
  Y <- Y[,genes]
  dy <- data.frame(Y, pseudotime = tmap)
  dm <- melt(dy, id.vars = "pseudotime", 
             variable.name = "gene", 
             value.name = "expression")
  
  S <- sig_map[,genes]
  ds <- data.frame(S, pseudotime = tmap)
  dm2 <- melt(ds, id.vars = "pseudotime",
              variable.name = "gene",
              value.name = "predicted_expression")
  
  dm_joined <- inner_join(dm, dm2, by = c("pseudotime", "gene"))
  
  plt <- ggplot(dm_joined, aes(x = pseudotime, y = expression, colour = "Measured")) + 
    geom_point() +
    facet_wrap(~ gene, scales = "free_y") +
    xlab("MAP pseudotime") + ylab(paste("Expression", expression_units)) + theme_bw()
  plt <- plt + 
    geom_line(aes(x = pseudotime, y = predicted_expression, color = 'Predicted'), 
              size = 2, alpha = 0.7) +
    scale_colour_manual(values = c("Predicted" = "red", "Measured" = "black"), name = element_blank()) +
    theme(legend.position = "bottom")
  return( plt )
}

#' Plot heatmaps showing comparisons of measured data and imputed
#' 
#' @param oui An object of class \code{ouija_fit}.
#' @param return_plotlist If TRUE then the list of \code{ggplot}s is returned
#' instead of being plotted with \code{cowplot::plot_grid}
#' 
#' 
#' @export
#' @import ggplot2
#' 
#' @return Either a list of plots of class \code{ggplot} or a single 
#' \code{ggplot} showing them
plot_ouija_fit_comparison <- function(oui, return_plotlist = FALSE) {
  stopifnot(is(oui, "ouija_fit"))
  X <- oui$Y
  Z <- rexprs(oui)
  tmap <- map_pseudotime(oui)
  
  make_tile_plot <- function(X, tmap) {
    Xp <- apply(X, 2, function(x) (x - min(x)) / (max(x) - min(x)))
    
    dfx <- data.frame(Xp, pseudotime = rank(tmap)) %>%
      melt(id.vars = "pseudotime", variable.name = "gene", value.name = "expression")
    ggplot(dfx, aes(x = pseudotime, y = gene, fill = expression)) + 
      geom_tile() + scale_fill_viridis(name = expression("Relative\nexpression")) + 
      theme_bw() + 
      theme(axis.line = element_blank(),
            panel.grid = element_blank(),
            panel.border = element_blank(),
            axis.title.y = element_blank()) +
      xlab("Pseudotime order")
  }
  plts <- lapply(list(X, Z), make_tile_plot, tmap)
  if(return_plotlist) return(plts)
  cowplot::plot_grid(plotlist = plts, nrow = 2, 
                     labels = c("Measured", "Reconstructed"))
}


#' Plot dropout probability
#' 
#' Plot the probability of a dropout as a function of latent expression value. In ouija
#' this is implemented via logit regression, so the probability of dropout is related
#' to latent expression \eqn{\mu_{ig}} via
#' \deqn{\frac{1}{1 + \exp(-(\beta_0 + \beta_1 \mu_{ig}))}}
#' The red curve shows the MAP estimate of the relationship, while the grey lines show 
#' posterior samples of the relationship.
#' 
#' @param oui An object of class \code{ouija_fit}
#' @param posterior_samples Number of posterior samples to add to the plot. If 0, only
#' the MAP estimate is plotted.
#' 
#' @importFrom rstan extract
#' @importFrom MCMCglmm posterior.mode
#' @importFrom coda mcmc
#' @export
#' 
#' @return An object of type \code{ggplot}
plot_ouija_fit_dropout_probability <- function(oui, posterior_samples = 40) {
  stopifnot(is(oui, "ouija_fit"))
  x_range <- range(as.vector(oui$Y))
  dsig <- function(x, beta0, beta1) 1 / (1 + exp(-(beta0 + beta1 * x)))
  ext <- extract(oui$fit, "beta")
  beta_map <- posterior.mode(mcmc(ext$beta))
  
  plt <- ggplot(data.frame(Mean_expression = x_range), aes(x = Mean_expression)) 


  if(posterior_samples > 0) {
    total_samples <- dim(ext$beta)[1]
    to_sample <- sample(total_samples, posterior_samples)
    for(i in seq_len(posterior_samples)) {
      beta <- ext$beta[to_sample[i], ]
      plt <- plt + stat_function(fun = dsig, 
                                 args = list(beta0 = beta[1], beta1 = beta[2]),
                                 alpha = 0.3)
    }
  }
  plt <- plt + stat_function(fun = dsig, 
                args = list(beta0 = beta_map[1], beta1 = beta_map[2]),
                colour = "red") +
    ylab("Dropout probability") + xlab("Latent expression")
  return( plt )
}

#' Synthetic gene expression matrix
#' 
#' A matrix containing some synthetic gene expression data for 
#' 100 cells and 6 genes
#' 
"synth_gex"

#' Synthetic gene pseudotimes
#' 
#' A vector with the 'true' pseudotimes for the synthetic 
#' gene expression data in \code{synth_gex}
"true_pst"