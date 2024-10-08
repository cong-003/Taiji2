library(Seurat)
library(pheatmap)
library(tibble)
library(dplyr)
library(purrr)
library(gridExtra)
library(gtable)
library(grid)
library(viridis)
library(RColorBrewer)
library(fgsea)
library(reshape2)
library(ggplot2)
library(tidyr)
library(this.path)

setwd(this.path::here())


ModuleScores = function(sobj, query_guides, ctrl_guides, custom_gene_sets, gene_set_order, gRNA_order) {
  sobj = sobj[, (sobj@meta.data$guide_ID %in% query_guides) | (sobj@meta.data$perturbed_gene == 'gScramble')] 
  
  sobj = AddModuleScore(object = sobj, 
                        features = custom_gene_sets,
                        name = "ModuleScore")
  
  df_scores = sobj@meta.data %>% 
    dplyr::select(starts_with("ModuleScore"), perturbed_gene)
  
  df_long = pivot_longer(df_scores, cols = starts_with("ModuleScore"), names_to = "GeneSet", values_to = "Score")
  
  average_scores = df_long %>%
    group_by(GeneSet, perturbed_gene) %>%
    summarize(AvgScore = mean(Score, na.rm = TRUE)) %>%
    ungroup()
  
  mtx = pivot_wider(average_scores, names_from = perturbed_gene, values_from = AvgScore)
  mtx = as.matrix(mtx[,-1]) # Assuming the first column is GeneSet names
  
  rownames(mtx) = average_scores$GeneSet[!duplicated(average_scores$GeneSet)]
  rownames(mtx) = c(unlist(lapply(rownames(mtx), function (x) gsub("ModuleScore", "", x))))
  
  idx = sapply(rownames(mtx), function(x) as.integer(x), USE.NAMES = FALSE)
  rownames(mtx) = names(custom_gene_sets)[idx]
  
  mtx = mtx[gene_set_order, ]
  mtx = (mtx - mtx[, ctrl_guides])
  mtx = mtx[, !colnames(mtx) %in% ctrl_guides]
  
  mask = gRNA_order %in% colnames(mtx)
  signature_groups = c('TEx_Prog_Biased','TEx_Prog_Biased','TEx_Prog_Biased','TEx_Eff_Biased','TEx_Eff_Biased','TEx_Eff_Biased','TEx_Eff_Biased', 'TEx_Eff_Biased','TEx_Eff_Biased','TEx_Eff_Biased','TEx_Eff_Biased','TEx_Eff_Biased','TEx_Eff_Biased','TEx_Eff_Biased','TEx_Eff_Biased','TEx_Eff_Biased', 'TEx_Eff_Biased', 'TEx_Eff_Biased')
  gRNA_order = gRNA_order[mask]
  signature_groups = signature_groups[mask]
  mtx = mtx[, gRNA_order]

  mtx = t(mtx)
  val_max = max(abs(mtx))
  val_min = -val_max
  
  ann_colors = list(signature_group = c(TEx_Prog_Biased = "#e0afe0", TEx_Eff_Biased = "#91a3cc"))
  
  gene_annots = data.frame(signature_group = as.factor(signature_groups))
  gene_annots$signature_group = factor(gene_annots$signature_group, levels=unique(gene_annots$signature_group))
  rownames(gene_annots) = gRNA_order
  
  heatmap = pheatmap(mtx, margins = c(5,5,0,5), cellheight = 10, cellwidth = 14,
                     cluster_cols = FALSE, show_colnames = TRUE, cluster_rows = FALSE, gaps_row = c(3),
                     border_color = NA, treeheight_row = 0, treeheight_col = 0, fontsize_col = 8, angle_col = '315',
                     silent = TRUE, breaks = seq(val_min, val_max, length.out = 101), gaps_col = c(1, 4),
                     annotation_row = gene_annots, annotation_colors = ann_colors, annotation_names_row = FALSE,
                     color = colorRampPalette(rev(brewer.pal(11, "RdBu")))(100))

  return(list(heatmap=heatmap, mtx=mtx))
}


save_pheatmap_pdf = function(x, filename, width=NULL, height=NULL) {
  stopifnot(!missing(x))
  stopifnot(!missing(filename))
  if (is.null(width) | is.null(height)) {
    pdf(filename)
  } else {
    pdf(filename, width=width, height=height)
  }
  
  print(x)
  dev.off()
}

### MAIN ###

sobj = readRDS('Cl13_23TP04_20231010.rds') # 7538 cells x 32285 genes (2000 var.); gScramble-2, gScramble-4
query_guides = read.csv('query-guides.Cl13.csv', header=FALSE)$V1
gRNA_order = c("gNfatc1", "gStat3", "gPrdm1", "gJdp2", "gIkzf3", "gHic1", "gZbtb49", "gNr4a2", "gNfil3", "gZfp324", "gIrf8", "gPrdm4", "gZscan20", "gFoxd2", "gEtv5", "gGfi1", "gArid3a", "gHinfp")

# sobj = readRDS('TP16_Arm_clean_simpler4clustersn_20231020.rds') # 7538 cells x 32285 genes (2000 var.); gScramble-4
# query_guides = read.csv('query-guides.Arm.csv', header=FALSE)$V1
#gRNA_order = c("gFosb", "gPrdm1", "gHic1", "gGfi1", "gNfil3", "gNr4a2", "gIkzf3", "gStat3", "gTfdp1", "gIrf8", "gZfp324", "gZscan20", "gNfatc1", "gZfp410", "gJdp2", "gArid3a", "gEtv5")

signatures = read.csv('Signature1.subset.csv', header=FALSE)
gene_set_order = c('TExTerm', 'TExEff', 'TE', 'Ca', 'TExProg', 'Naive')
ctrl_guides = c('gScramble')

rownames(signatures) = signatures$V1
signatures = signatures[-1]
custom_gene_sets = list()

for (r in rownames(signatures)) {
  tmp = as.character(signatures[r,])
  tmp = tmp[tmp != ""]
  custom_gene_sets[[r]] = tmp
}

res = ModuleScores(sobj, query_guides, ctrl_guides, custom_gene_sets, gene_set_order, gRNA_order)
fig = res$heatmap
mtx = res$mtx

write.csv(mtx, 'Fig2I.Cl13.ModScores.RdBu.offset.none.csv', row.names = TRUE)
save_pheatmap_pdf(fig, 'Fig2I.Cl13.ModScores.RdBu.offset.none.pdf')

