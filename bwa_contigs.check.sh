#!/usr/bin/env bash
# Usage: ./bwa_contigs_check.sh /path/to/contigs.fa /path/to/sample_fastq_dir /path/to/outdir
# Example: ./bwa_contigs_check.sh /nvme/refs/hiv_contigs.fa /mnt/ext/opioid-fastq/LG31_FCM /nvme/scratch/lg31_check
set -euo pipefail

REF="$1"
FASTQ_DIR="$2"
OUTDIR="$3"
THREADS="${4:-8}"

mkdir -p "$OUTDIR"

# Paths (adjust filenames if your naming differs)
GEX_R2="$FASTQ_DIR/GEX/$(ls $FASTQ_DIR/GEX | grep _R2_ | head -n1)"
ATAC_R1="$FASTQ_DIR/ATAC/$(ls $FASTQ_DIR/ATAC | grep _R1_ | head -n1)"
ATAC_R2="$FASTQ_DIR/ATAC/$(ls $FASTQ_DIR/ATAC | grep _R2_ | head -n1)"

echo "REF: $REF"
echo "GEX_R2: $GEX_R2"
echo "ATAC_R1: $ATAC_R1"
echo "ATAC_R2: $ATAC_R2"
echo "OUTDIR: $OUTDIR"

# Index REF if needed
if [ ! -f "${REF}.bwt" ]; then
  echo "Indexing reference with bwa..."
  bwa index "$REF"
fi

# GEX single-end (R2)
echo "Running bwa mem for GEX (R2) -> $OUTDIR/gex_to_contigs.bam"
bwa mem -t "$THREADS" "$REF" "$GEX_R2" \
  | samtools view -b -F 2304 -q 10 - \
  | samtools sort -o "$OUTDIR/gex_to_contigs.bam"
samtools index "$OUTDIR/gex_to_contigs.bam"
samtools idxstats "$OUTDIR/gex_to_contigs.bam" > "$OUTDIR/gex_idxstats.tsv"

# ATAC paired (R1 + R2)
echo "Running bwa mem for ATAC (R1+R2) -> $OUTDIR/atac_to_contigs.bam"
bwa mem -t "$THREADS" "$REF" "$ATAC_R1" "$ATAC_R2" \
  | samtools view -b -F 2304 -q 10 - \
  | samtools sort -o "$OUTDIR/atac_to_contigs.bam"
samtools index "$OUTDIR/atac_to_contigs.bam"
samtools idxstats "$OUTDIR/atac_to_contigs.bam" > "$OUTDIR/atac_idxstats.tsv"

echo "Results written to $OUTDIR. Inspect *_idxstats.tsv for mapped counts per contig."
