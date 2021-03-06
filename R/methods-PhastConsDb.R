## constructor
PhastConsDb <- function(provider, provider_version, download_url,
                        download_date, reference_genome,
                        data_pkgname, data_dirpath) {
  data_serialized_objnames <- "phastCons"
  data_cache <- new.env(hash=TRUE, parent=emptyenv())

  ## for backwards compatibility with first version of the PhastConsDb annotation package
  if (file.exists(file.path(data_dirpath, "phastCons100way.rda")))
    load(file.path(data_dirpath, "phastCons100way.rda"), envir=data_cache)
  else
    assign(data_pkgname, RleList(compress=FALSE), envir=data_cache)

  new("PhastConsDb", provider=provider,
                     provider_version=provider_version,
                     download_url=download_url,
                     download_date=download_date,
                     reference_genome=reference_genome,
                     data_pkgname=data_pkgname,
                     data_dirpath=data_dirpath,
                     data_serialized_objnames=data_serialized_objnames,
                     .data_cache=data_cache)
}

## accessors
setMethod("provider", "PhastConsDb", function(x) x@provider)

setMethod("providerVersion", "PhastConsDb", function(x) x@provider_version)

setMethod("referenceGenome", "PhastConsDb", function(x) x@reference_genome)

setMethod("organism", "PhastConsDb", function(object) organism(referenceGenome(object)))

setMethod("seqinfo", "PhastConsDb", function(x) seqinfo(referenceGenome(x)))

setMethod("seqnames", "PhastConsDb", function(x) seqnames(referenceGenome(x)))

setMethod("seqlengths", "PhastConsDb", function(x) seqlengths(referenceGenome(x)))

setMethod("seqlevelsStyle", "PhastConsDb", function(x) seqlevelsStyle(referenceGenome(x)))

## this has been improved using RleViews as discussed in
## https://stat.ethz.ch/pipermail/bioconductor/2013-December/056409.html
rleGetValues <- function(rlelst, gr, summaryFun="mean", coercionFun="as.numeric") {
  numericmean <- TRUE
  if (summaryFun != "mean" || coercionFun != "as.numeric")
    numericmean <- FALSE

  summaryFun <- match.fun(summaryFun)
  coercionFun <- match.fun(coercionFun)
  seqlevels(gr) <- names(rlelst)
  ord <- order(seqnames(gr))
  ans <- numeric(length(gr))
  startbyseq <- split(start(gr), seqnames(gr), drop=TRUE)
  ans[ord] <- unlist(lapply(rlelst[startbyseq], coercionFun), use.names=FALSE)
  whregions <- which(width(gr) > 1)
  if (length(whregions) > 0) { ## regions comprising more than one position need to be summarized
    tmpans <- NA_real_
    if (numericmean) {
      rngbyseq <- split(gr[whregions], seqnames(gr)[whregions])
      tmpans <- lapply(names(rngbyseq), function(sname) {
                                          coercedrle <- rlelst[[sname]]
                                          ## this coercion can take up to one second for chromosome 1
                                          ## should consider storing coerced version if memory consumption is not an issue
                                          runValue(coercedrle) <- as.numeric(runValue(coercedrle))
                                          viewMeans(Views(coercedrle,
                                                          start=start(rngbyseq[[sname]]),
                                                          end=end(rngbyseq[[sname]])))
                                        })
      tmpans <- unsplit(tmpans, as.factor(seqnames(gr)[whregions]))
    } else { ## this allows for other summary and coercion functions but it runs about 10-fold slower
      startbyseq <- split(start(gr)[whregions], seqnames(gr)[whregions], drop=TRUE)
      widthbyseq <- split(width(gr)[whregions], seqnames(gr)[whregions], drop=TRUE)
      tmpans <- unlist(mapply(function(r, p, w)
                                        sapply(seq_along(p),
                                               function(i, r, p, w) summaryFun(coercionFun(r[p[i]:(p[i]+w[i]-1)])),
                                               r, p, w),
                                     rlelst[names(startbyseq)], startbyseq, widthbyseq, SIMPLIFY=FALSE),
                              use.names=FALSE)
    }
    ans[ord[whregions]] <- tmpans
  }
  ans
}

setMethod("scores", c("PhastConsDb", "GRanges"),
          function(object, gpos, summaryFun="mean", coercionFun="as.numeric", caching=TRUE) {
            if (seqlevelsStyle(gpos) != seqlevelsStyle(object))
              seqlevelsStyle(gpos) <- seqlevelsStyle(object)

            snames <- unique(as.character(runValue(seqnames(gpos))))
            if (any(!snames %in% seqnames(object)))
              stop("Sequence names %s in GRanges object not present in PhastConsDb object.",
                   paste(snames[!snames %in% seqnames(object)], collapse=", "))

            pcrlelist <- get(object@data_pkgname, envir=object@.data_cache)
            missingMask <- !snames %in% names(pcrlelist)
            for (sname in snames[missingMask]) {
              if (file.exists(file.path(object@data_dirpath, paste0(sname, ".phastCons100way.RData")))) {
                warning("You are using a PhastConsDb annotation package version < 3.1.0, consider upgrading to the lastest version >= 3.1.0.")
                load(file.path(object@data_dirpath, paste0(sname, ".phastCons100way.RData")), envir=object@.data_cache)
                objname <- paste("phastCons100way_", sname)
                if (exists(objname, envir=object@.data_cache)) {
                  pcrlelist[[sname]] <- get(objname, envir=object@.data_cache)
                  rm(list=objname, envir=object@.data_cache)
                } else {
                  warning(sprintf("No phastCons scores for chromosome %s.", sname))
                  pcrlelist[[sname]] <- Rle(raw())
                }
              } else if (file.exists(file.path(object@data_dirpath, sprintf("%s.%s.rds", object@data_pkgname, sname))))
                pcrlelist[[sname]] <- readRDS(file.path(object@data_dirpath, sprintf("%s.%s.rds", object@data_pkgname, sname)))
              else {
                warning(sprintf("No phastCons scores for chromosome %s.", sname))
                pcrlelist[[sname]] <- Rle(raw())
              }
            }

            if (any(missingMask) && caching)
              assign(object@data_pkgname, pcrlelist, envir=object@.data_cache)

            sco <- rleGetValues(pcrlelist, gpos, summaryFun=summaryFun, coercionFun=coercionFun) / 10
            rm(pcrlelist)

            sco
          })

## show method
setMethod("show", "PhastConsDb",
          function(object) {
            cat(class(object), " object for ", organism(object), " (",
                provider(object), ")\n", sep="")
          })
