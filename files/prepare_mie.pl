#!/usr/bin/env perl 

use warnings; 
use strict;

use YAML::Tiny;
use Text::CSV; 
use Excel::Writer::XLSX;

# Parse the input file and write YAML output 
# MIE: Mendelian Inheritance Error
# Also save the result into Excel format with http links to local files.
# use igv_case_bed_2_yaml.pl as a reference

# perl src/prepare_mie.pl Files/Meredith_Case1/t0008c1.mie.pt.filt.mdnm.relaxed.txt Files/Meredith_Case1/trios_final_IDs.txt /DCEG/Scimentis/DNM/data/BATCH2_b38 my.yaml  test.xlsx 

@ARGV == 5 or die "$0 <INFILE> <Manifest file> <BAM_DIR> <YAML output file> <Excel Table>\n"; 

my $infn = shift;
my $manifest_fn = shift;
my $bam_dir = shift;
my $yaml_outfn = shift;
my $excel_outfn = shift;



###################################
# Manifest file
# Files/Meredith_Case1/trios_final_IDs.txt
###################################
# head  Files/Meredith_Case1/trios_final_IDs.txt 
# PI_Subject_ID   Sex     Sample_Name     LIMSSample_ID   Project
# t0005c1 M       TRI00527 2000   SC499433
# t0005fa M       TRI00528 2000   SC499434
# t0005mo F       TRI00529 2000   SC499431
# t0008c1 F       TRI00533 2000   SC499419
# t0008fa M       TRI00534 2000   SC499415
# t0008mo F       TRI00535 2000   SC499436
# t0010c1 F       TRI00536 2000   SC499416
# t0010fa M       TRI00537 2000   SC499417
# t0010mo F       TRI00538 2000   SC499437

    #  1  PI_Subject_ID   t0005c1
    #  2  Sex             M
    #  3  Sample_Name     TRI00527 2000
    #  4  LIMSSample_ID   SC499433
    #  5  Project    
###################################

my $tab = Text::CSV->new ({ sep_char => qq|\t|, eol => $/ });
open my $mani, "<", $manifest_fn or die "$manifest_fn: $!";



my @mani_hdr = $tab->header ($mani , { munge_column_names => "none" }); 
$tab->column_names (@mani_hdr);

# construct hash PI_Subject_ID => LIMSSample_ID
my %mani_hash = (); 
while (my $href = $tab->getline_hr ($mani)) {
    
    $mani_hash{$href->{PI_Subject_ID}} = $href->{LIMSSample_ID};
    # print join("\t", $href->{PI_Subject_ID},$mani_hash{$href->{LIMSSample_ID}})."\n";
}

###################################
# Input file (Tab delimed file displayed in the vertical way)
    #  1  CHROM       1
    #  2  POS         2799849
    #  3  AC          1
    #  4  FAMILY      t0016c1
    #  5  TP          120
    #  6  MOTHER_GT   T/T
    #  7  MOTHER_DP   67
    #  8  MOTHER_AD   67,0
    #  9  MOTHER_PL   0,201,2328
    # 10  FATHER_GT   T/T
    # 11  FATHER_DP   78
    # 12  FATHER_AD   78,0
    # 13  FATHER_PL   0,234,2674
    # 14  CHILD_GT    T/C
    # 15  CHILD_DP    106
    # 16  CHILD_AD    55,51
    # 17  CHILD_PL    1250,0,1562
    # 18  TYPE        SNP
######################################

### Create an Excel file
my $workbook  = Excel::Writer::XLSX->new($excel_outfn);
my $worksheet = $workbook->add_worksheet();

### Create a new object with a single hashref document
my $yaml = YAML::Tiny->new();

my $csv = Text::CSV->new ({ sep_char => qq|\t|, eol => $/ });
open my $io, "<", $infn or die "$infn: $!";

#lower case otherwise
my @hdr = $csv->header ($io, , { munge_column_names => "none" }); 

# print join(", ", @hdr)."\n";

$csv->column_names (@hdr);

my @new_hdr= (@hdr, "IGV_snapshot", "IGV_script");

# have rows returned as hashrefs
my @bam_files = ();

# The whole YAML output is an array with only one element. 

&write_line_excel($worksheet, 0, \@new_hdr);
my $row_id=1;

my $entry = {};
my $snapshots = [];

while (my $href = $csv->getline_hr ($io)) {
    

    # Create a UID_00001 for each row.
    # And create a hash of name, chr, start, stop for each row.
    # Rows are organized into an array, which is part of hash value,
    # with the key "snapshots"
    my $cid = $href->{FAMILY};
    my $fam = substr $cid, 0, 5;
    my $fid = $fam."fa";
    my $mid = $fam."mo";
    
    if(! @bam_files){
        # Push to the bam_files if it is emtpy
        @bam_files = map{$bam_dir.'/'.$mani_hash{$_}.".bam"} ($fid, $mid, $cid);

        $entry->{name} = $cid; 
        $entry->{bam_files} = \@bam_files;
    }

    my $snapshot_name = sprintf("%s_MIE_%05d", $cid, $row_id);
    my $sp_hash = {};
    $sp_hash->{name} = $snapshot_name;
    $sp_hash->{chr} = $href->{CHROM};
    $sp_hash->{start} = int($href->{POS}); # 1-based cooordinates
    $sp_hash->{stop} = int($href->{POS});
    push @$snapshots, $sp_hash;

    my @row_data = map {$href->{$_}} @hdr;
    # print join("\t", $cid, $mani_hash{$cid}, $mani_hash{$fid}, $mani_hash{$mid})."\n";

    # Besides, each row together with the UID (and the additional http links to the local scriptsa and pngs ) will also be saved as Excel file,
    &write_line_excel($worksheet, $row_id, \@row_data);

    # Add links to igv script
    $worksheet->write_url($row_id, $#row_data + 1, "./IGV_Snapshots/".$entry->{name}."/".$sp_hash->{name}.".png",  undef, $sp_hash->{name}.".png" );
    $worksheet->write_url($row_id, $#row_data + 2, "./IGV_Snapshots/".$entry->{name}."/".$sp_hash->{name}.".bat",  undef, $sp_hash->{name}.".bat" );
    $row_id++;
}

# Create the only entry for the whole yaml file
$entry->{snapshots} = $snapshots;

my $entries = [];
push @$entries, $entry;
push @$yaml, $entries; 
$yaml->write($yaml_outfn);

###########
sub write_line_excel{
    my $ws = shift;
    my $row = shift;
    my $data_ref = shift;

    for my $col (0  .. @{$data_ref} - 1) {
        my $cell_data = $data_ref->[$col];
        $worksheet->write( $row, $col, $cell_data);
    }
}