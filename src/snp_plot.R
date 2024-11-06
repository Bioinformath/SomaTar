
library(ggplot2)
library(tidyr)
library(dplyr)

args <- commandArgs(trailingOnly = TRUE)

data <- read.csv(args[1], sep = "\t", header = TRUE)

data$Position <- as.factor(data$Position)

#read_depth_threshold <- as.numeric(args[2])

sample_name <- tools::file_path_sans_ext(basename(args[1]))

data <- data %>%
filter(ReadDepth >= 50)


chromosomes <- unique(data$Chromosome)

output_dir <- file.path(dirname(args[1]), sample_name)
if (!dir.exists(output_dir)) {
  dir.create(output_dir)
}

for (chr in chromosomes){
 plot <- data %>%
  filter(Chromosome == chr) %>%
  pivot_longer(cols = c(VAF, RAF), names_to = "Type", values_to = "Value") %>%
  ggplot(aes(x = Position, y = Value, color = Type)) +
  annotate("rect", xmin = -Inf, xmax = Inf, ymin = 0.4, ymax = 0.6, alpha = 0.3, fill = "grey") +
  annotate("rect", xmin = -Inf, xmax = Inf, ymin = 1.0, ymax = Inf, alpha = 0.3, fill = "grey") +
  annotate("rect", xmin = -Inf, xmax = Inf, ymin = -Inf, ymax = 0.0, alpha =0.3, fill =" grey")+
  geom_point(size = 2) +
  scale_color_manual(values = c("RAF" = "purple", "VAF" = "blue")) +
  geom_hline(yintercept = 0.5, color = "red") +
  geom_hline(yintercept = seq(0.2, 1, by = 0.2), linetype = "dotted", color = "black") +
  ggtitle('Allele Frequency at SNP Position') +
  scale_y_continuous(name= "Allele_Frequency", breaks = seq(0, 1, by = 0.2), limits = c(0,1)) +
  theme_bw() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),plot.title = element_text(hjust = 0.5)) +
  annotate("text", x = Inf, y = -Inf, label = "Filtered out SNPs with read depth <50", hjust = 1.1, vjust = -1.1, size = 3, color = "black")
  ggsave(filename = file.path(output_dir, paste0("plot_", chr, ".png")), plot = plot, width = 20, height = 6, dpi = 300)
}
