setMethod("unrelatedIndividuals", signature(param="VariantFilteringParam"),
          function(param, svparam=ScanVcfParam(), BPPARAM=bpparam("SerialParam")) {

  ## store call for reproducing it later
  callobj <- match.call()
  callstr <- gsub(".local", "unrelatedIndividuals", deparse(callobj))

  ## fetch necessary parameters
  vcfFiles <- param$vcfFiles
  seqInfos <- param$seqInfos
  txdb <- param$txdb
  bsgenome <- param$bsgenome
  sampleNames <- param$sampleNames
  
  if (!exists(as.character(substitute(BPPARAM))))
    stop(sprintf("Parallel back-end function %s given in argument 'BPPARAM' does not exist in the current workspace. Either you did not write correctly the function name or you did not load the package 'BiocParallel'.", as.character(substitute(BPPARAM))))
  
  if (length(vcfFiles) > 1) {
    stop("More than one input VCF file is currently not supported. Please either merge the VCF files into a single one with vcftools, do the variant calling simultaneously on all samples, or proceed analyzing each file separately.")
  } else if (length(vcfFiles) < 1)
    stop("A minimum of 1 vcf file has to be provided")

  annotationCache <- new.env() ## cache annotations when using VariantAnnotation::locateVariants()
  annotated_variants <- VRanges()
  open(vcfFiles[[1]])
  n.var <- 0
  while(nrow(vcf <- readVcf(vcfFiles[[1]], genome=seqInfos[[1]], param=svparam))) {

    # insert an index for each variant in the VCF file
    info(header(vcf)) <- rbind(info(header(vcf)),
                               DataFrame(Number=1, Type="Integer",
                                         Description="Variant index in the VCF file.",
                                         row.names="VCFIDX"))
    info(vcf)$VCFIDX <- (n.var+1):(n.var+nrow(vcf))
    varIDs <- rownames(vcf)

    n.var <- n.var + nrow(vcf)

    ## coerce the VCF object to a VRanges object
    variants <- as(vcf, "VRanges")

    ## since the conversion of VCF to VRanges strips the VCF ID field, let's put it back
    variants$VARID <- varIDs[variants$VCFIDX]

    ## harmonize Seqinfo data between variants, annotations and reference genome
    variants <- .matchSeqinfo(variants, txdb, bsgenome)

    ## annotate variants
    if (length(annotated_variants) > 0)
      annotated_variants <- c(annotated_variants, annotationEngine(variants, param, annotationCache,
                                                                   BPPARAM=BPPARAM))
    else
      annotated_variants <- annotationEngine(variants, param, annotationCache,
                                             BPPARAM=BPPARAM)

    message(sprintf("%d variants processed", n.var))
  }
  close(vcfFiles[[1]])

  gSO <- annotateSO(annotated_variants, sog(param))
  locMask <- conMask <- varTypMask <- logical(0)

  if (length(annotated_variants) > 0) {

    locMask <- do.call("names<-", list(rep(TRUE, nlevels(annotated_variants$LOCATION)),
                                       levels(annotated_variants$LOCATION)))
    conMask <- do.call("names<-", list(rep(TRUE, nlevels(annotated_variants$CONSEQUENCE)),
                                       levels(annotated_variants$CONSEQUENCE)))
    varTypMask <- do.call("names<-", list(rep(TRUE, nlevels(annotated_variants$TYPE)),
                                        levels(annotated_variants$TYPE)))
  } else
    warning("The input VCF file has no variants.")

  MAFpopMask <- NA
  if ("MafDb" %in% sapply(param$otherAnnotations, class)) {
    ## assume AF columns are those containing AF[A-Z]+ and being of class 'numeric'
    cnAF <- colnames(mcols(annotated_variants))
    colsclasses <- sapply(mcols(annotated_variants), class)
    cnAF <- cnAF[intersect(grep("AF[A-Z]+", cnAF), grep("numeric", colsclasses))]
    MAFpopMask <- rep(TRUE, length(cnAF))
    names(MAFpopMask) <- cnAF
  }

  new("VariantFilteringResults", callObj=callobj, callStr=callstr, inputParameters=param,
      activeSamples=sampleNames, inheritanceModel="unrelated individuals", variants=annotated_variants,
      ## indselected=NA_character_, selectgene=NA_character_,
      bamViews=BamViews(), gSO=gSO, filters=filters(param), cutoffs=cutoffs(param),
      dbSNPflag=NA_character_, OMIMflag=NA_character_,
      locationMask=locMask, consequenceMask=conMask, variantTypeMask=varTypMask, aaChangeType="Any",
      MAFpopMask=MAFpopMask, naMAF=TRUE, maxMAF=1,
      minPhastCons=NA_real_, minPhylostratumIndex=NA_integer_,
      minScore5ss=NA_real_, minScore3ss=NA_real_, minCUFC=0)
})
