## Investigating genomic factors that influence gene expression noise
library(ggplot2)
library(reshape2)
library(Rtsne)
library(biomaRt)
library(e1071)
library(limSolve)
library(statmod)
source("~/Dropbox/R_sessions/GGMike/palette_256.R")
source("~/Dropbox/R_sessions/GGMike/theme_mike.R")

panc.cell <- read.table("~/Dropbox/pancreas/GSE86473-norm.tsv.gz",
                        sep="\t", h=T, stringsAsFactors=F)

ensembl <- useEnsembl(biomart='ensembl', dataset='hsapiens_gene_ensembl')
gene_symbol <- getBM(attributes=c('ensembl_gene_id', 'external_gene_name'),
                     filters='external_gene_name', mart=ensembl,
                     values=panc.cell$hgnc_symbol)

panc.merge <- merge(panc.cell, gene_symbol, by.x='hgnc_symbol',
                    by.y='external_gene_name')
panc.cells <- panc.merge[, -1]
panc.cells <- panc.cells[!duplicated(panc.cells$ensembl_gene_id), ]
rownames(panc.cells) <- panc.cells$ensembl_gene_id
panc.cells <- panc.cells[grepl(rownames(panc.cells), pattern="ENS"), ]

panc.meta <- read.table("~/Dropbox/pancreas/GSE86473_marker_metadata.tsv",
                        h=T, stringsAsFactors=F, sep="\t")

panc.beta <- panc.cells[, colnames(panc.cells) %in% panc.meta$Sample[panc.meta$CellType == "beta"]]

panc.means <- rowMeans(panc.beta[, 1:(dim(panc.beta)[2]-1)])
panc.vars <- apply(panc.beta[, 1:(dim(panc.beta)[2]-1)],
                   1, var)
panc.median <- apply(panc.beta[, 1:(dim(panc.beta)[2]-1)],
                     1, median)
panc.mad <- apply(panc.beta[, 1:(dim(panc.beta)[2]-1)],
                  1, FUN=function(M) mad(M, constant=1))

# get the variance mean of the counts on the linear scale
panc.count_var <- apply(panc.beta[, 1:(dim(panc.beta)[2]-1)],
                        1, FUN=function(Q) var(2**Q))
panc.count_mean <- apply(panc.beta[, 1:(dim(panc.beta)[2]-1)],
                         1, FUN=function(Q) mean(2**Q))

# create gene expression groups based on average expression over cells
panc.exprs.groups <- as.factor(cut_number(panc.means, n=10))
beta.gene.summary <- as.data.frame(cbind(panc.means, panc.vars, panc.median, panc.mad,
                                         panc.exprs.groups, log2(panc.count_mean), log2(panc.count_var)))
colnames(beta.gene.summary) <- c("Mean", "Var", "Median", "MAD", "Group", "CountMean", "CountVar")
beta.gene.summary$CV2 <- beta.gene.summary$Var/(beta.gene.summary$Mean** 2)
beta.gene.summary$CV2[is.na(beta.gene.summary$CV2)] <- 0
beta.gene.summary$GENE <- rownames(beta.gene.summary)
beta.gene.summary <- beta.gene.summary[(!beta.gene.summary$CountMean < 0), ]

# calculate the residual CV^2
# select genes with mean value greater than min value for fitting
useForFit <- beta.gene.summary$Mean <= 0.05

# fit with a gamma-distributed GLM
fit <- glmgam.fit(cbind(a0 = 1, a1tilde=1/beta.gene.summary$Mean[!useForFit]), 
                  beta.gene.summary$CV2[!useForFit])

beta.gene.summary$Residual.CV2[!useForFit] <- abs(beta.gene.summary$CV2[!useForFit] - fitted.values(fit))
