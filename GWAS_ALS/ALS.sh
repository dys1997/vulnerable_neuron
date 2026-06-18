############ ALS ###############
###### Step1
zcat /mnt/alamo01/users/dengys/Project/jupyter/GWAS_ALS/SALS_for_magma.chr_bp_aa.pval.gz \
  | awk 'NR>1 {split($1,a,":"); print $1"\t"a[1]"\t"a[2]}' \
  > /mnt/alamo01/users/dengys/Project/jupyter/GWAS_ALS/SALS_snp.loc
###### Step2
/mnt/alamo01/users/dengys/Project/jupyter/GWAS/magma \
  --annotate window=10,10 \
  --snp-loc  /mnt/alamo01/users/dengys/Project/jupyter/GWAS_ALS/SALS_snp.loc \
  --gene-loc /mnt/alamo01/users/dengys/Project/jupyter/GWAS/ENSGv85.coding.genes.txt \
  --out      /mnt/alamo01/users/dengys/Project/jupyter/GWAS_ALS/ALS_annot

####### Step3
zcat /mnt/alamo01/users/dengys/Project/jupyter/GWAS_ALS/SALS_for_magma.chr_bp_aa.pval.gz \
| awk 'NR>1 && $1 !~ /:NA:/{print $1"\t"$2"\t"$3}' \
> /mnt/alamo01/users/dengys/Project/jupyter/GWAS_ALS/SALS_for_magma.noheader.pval

/mnt/alamo01/users/dengys/Project/jupyter/GWAS/magma \
  --bfile      /mnt/alamo01/users/dengys/Project/jupyter/GWAS/g1000_eur \
  --pval       /mnt/alamo01/users/dengys/Project/jupyter/GWAS_ALS/SALS_for_magma.noheader.pval use=1,2 ncol=3 \
  --gene-annot /mnt/alamo01/users/dengys/Project/jupyter/GWAS_ALS/ALS_annot.genes.annot \
  --out        /mnt/alamo01/users/dengys/Project/jupyter/GWAS_ALS/ALS_gene

###### Step4
从 MAGMA 结果取 Top-1000 基因并做 .gs

/mnt/alamo01/users/dengys/Project/jupyter/vulnerable_neurons/vuln_deg_in_disease/SALS_disease_driver_analysis.Rmd





out_dir="/mnt/alamo01/users/dengys/Project/jupyter/GWAS_ALS/scDRS_out/ALS_PFC"
mkdir -p "$out_dir"

python /mnt/alamo01/users/dengys/Project/jupyter/GWAS/compute_score.py \
  --h5ad_file   /mnt/alamo01/users/dengys/Project/jupyter/prepare/data/SALS_PFC_control.floatX.h5ad \
  --h5ad_species human \
  --cov_file    /mnt/alamo01/users/dengys/Project/jupyter/GWAS_ALS/scDRS_out/SALS_PFC_control_cov_final.tsv \
  --gs_file     /mnt/alamo01/users/dengys/Project/jupyter/GWAS_ALS/ALS_top1000.symbol.gs \
  --gs_species  human \
  --flag_filter False \
  --flag_raw_count True \
  --n_ctrl 1000 \
  --flag_return_ctrl_raw_score False \
  --flag_return_ctrl_norm_score True \
  --out_folder "$out_dir" | tee "$out_dir/run.log"











# zcat /mnt/alamo01/users/dengys/Project/jupyter/disea_driver/PD_for_magma.chr_bp_aa.pval.gz \
#   | awk 'NR>1 {split($1,a,":"); print $1"\t"a[1]"\t"a[2]}' \
#   > /mnt/alamo01/users/dengys/Project/jupyter/disea_driver/PD_snp.loc