#!/usr/bin/env perl 

use warnings; 
use strict;

use YAML::Tiny;
use Excel::Writer::XLSX;
use feature qw( switch );
no if $] >= 5.018, warnings => qw( experimental::smartmatch );

#####################################################################################
# The perl script takes two input files: 
# + conf/pRCC_input_bam.txt
# + output/compare_and_annotate/ (the output folder of MoCCA-SV)
#   + output/compare_and_annotate/intrachromosomal_SVs_*
#   + output/compare_and_annotate/interchromosomal_SVs_*

# The script is going to parse the file conf/pRCC_input_bam.txt, to have the related samples from the same subject. Then the meerkat information will be retrieve from the files under the MoCCA-SV output folder.

# By default, we may use all the available bam files. If necessary, we may restrict the bam files at the step of the snapshot generation.
#####################################################################################

#  perl src/parse_mocca_meerkat.pl  /Volumes/DCEG_pRCC_SV/conf/pRCC_input_bam.txt /Volumes/DCEG_pRCC_SV/mocca_sv_working/output/compare_and_annotate /data/DCEG_pRCC_SV/EAGLE_Kidney_BAM pRCC_SV.yaml pRCC_SV.xlsx

@ARGV == 5 or die "$0 <TN input file> <MoCCA output directory> <BAM_DIR> <YAML output file> <Excel Table>\n";

my $infn = shift; 
my $mocca_dir = shift;
my $bam_dir = shift;
my $yaml_outfn = shift;
my $excel_outfn = shift;

#####################################
# Declare some global variables
#####################################
my $NEXT_ROW=1;
my $MAX_WINDOW=300000; # the maxium alignment visible window is 300kb in IGV.

### Create an Excel file
my $workbook  = Excel::Writer::XLSX->new($excel_outfn);
my $worksheet = $workbook->add_worksheet();
# Add the header line
my @hdr = qw(SV_ID chrom  start   end     chrom2  start2  end2    svaba   delly   manta   gridss  meerkat caller_count Original_caller_output IGV_script Combined_snapshot);

my $cc =0;
my %hdr_col = map{$_ => $cc++ } @hdr;

# use Data::Dumper;
# print Dumper %hdr_col; die;

&write_line_excel($worksheet, 0, \@hdr);

### Create a new object with a single hashref document
my $yaml = YAML::Tiny->new();


open FIN, $infn or die $!;

# head  /Volumes/DCEG_pRCC_SV/conf/pRCC_input_bam.txt
# cdRCC_1697_10_T01 GPK0144_0401.bam GPK0144_0421.bam
# cdRCC_1697_10_T02 GPK0144_0402.bam GPK0144_0421.bam
# cdRCC_1697_10_T04 GPK0144_0404.bam GPK0144_0421.bam
# cdRCC_1697_10_T05 GPK0144_0405.bam GPK0144_0421.bam
# cdRCC_1697_10_T06 GPK0144_0406.bam GPK0144_0421.bam
# cdRCC_1697_10_T07 GPK0144_0407.bam GPK0144_0421.bam
# cdRCC_1697_10_T08 GPK0144_0408.bam GPK0144_0421.bam

my $entries = []; # each entry is for one T01 sample
my $subj_hash = {}; 

# Parse the whole file first to have all bam files ready for every subject.



while(<FIN>){
    chomp;
    my ($sam_id, $t, $n ) =  split / /; 
    
    my ($subj_id, $tissue_id) = ($sam_id =~ /^(.+)_([^_]+)$/);

    # print join("\t", $subj_id, $tissue_id, $t, $n)."\n";

    if(!defined $subj_hash->{$subj_id}){
        $subj_hash->{$subj_id} = {};
    }
    
    $subj_hash->{$subj_id}->{normal}=$n;
    $subj_hash->{$subj_id}->{$tissue_id} = $t;
}
close FIN;


### Then iterate over each subject T01 sample to load the MoCCA-SV outputs
my $skip_cond = " \$meerkat ne '0' || (( \$svaba ne '0') + (\$delly ne '0') + (\$manta ne '0') + (\$gridss ne '0')) < 3 ";

for my $subj_id (keys %$subj_hash){
    # for my $k (keys %{$subj_hash->{$subj_id}}){
    #     print join("\t", $subj_id, $k, $subj_hash->{$subj_id}->{$k} )."\n";
    # }
    
    my $sam_id = $subj_id."_T01";

    
    # parse the files under MoCCA-SV  output folders
    my $intra_fn = sprintf("%s/intrachromosomal_SVs_%s", $mocca_dir, $sam_id);
    my $inter_fn = sprintf("%s/interchromosomal_SVs_%s", $mocca_dir, $sam_id);
    # print $intra_fn."\n";
    # &parse_mocca(1, $intra_fn);
    my $snapshots = &parse_mocca($sam_id, 0, $inter_fn, $worksheet,$skip_cond);
    my $rv = &parse_mocca($sam_id, 1, $intra_fn, $worksheet, $skip_cond);
    push @$snapshots, @$rv;

    if(scalar(@$snapshots)){
        # there are some SVs predicted for the sample
        # so we need create the entry and push it to entries
        # note that each entry has 3 attributes: 
        # + name
        # + bam_files
        # + snapshots

        my $entry = {};

        my @ordered_tissues = sort  { rank($a) <=> rank($b) } keys %{$subj_hash->{$subj_id}};
        my @bam_files = map{$bam_dir.'/'. $subj_hash->{$subj_id}->{$_}} @ordered_tissues;

        # print join("\t", @ordered_tissues)."\n";
        # print join("\t", @bam_files)."\n";
        # die;
        $entry->{name} = $sam_id;
        $entry->{bam_files} = \@bam_files;
        $entry->{snapshots} = $snapshots;
        push @$entries, $entry;
    }
    
   
} # end of for

### Output the YAML data to file
push @$yaml, $entries; 
$yaml->write($yaml_outfn);
# end of main

######################################################
# Parse the MoCCA SV output files
# add new entries to the perl data structure for the final YAML output
# and also output the corresponding output as Excel table
# and return $snapshots (refence to the array)
######################################################
sub parse_mocca{

    my $sam_id = shift;
    my $is_intra = shift;
    my $fn = shift;
    my $ws = shift; # Excel wooksheet
    my $skip_cond = shift || "\$meerkat ne 'orig'"; 

    my $snapshots = [];

    my @indice = ();
    if($is_intra){
        @indice = (0..8, 27);
    }else{
        @indice = (0..2, 6..12);
    }
    open MOCCA, $fn or die $!; 

    <MOCCA>; # skip the headline
    my $row_id = 0;
    while(<MOCCA>){
        chomp;
        $row_id ++; # keep the track of the row_id in the original MoCCA SV output

        my @items = split(/\t/);
        my ($chrom2, $start2, $end2);
        my $len = undef;
        my ($chrom, $start, $end, $svaba, $delly, $manta, $gridss, $meerkat, $caller_count, $orig) = @items[@indice];    
        next if (!defined $orig) || eval $skip_cond ;
        
        ### I need set up extra filter to remove redundant SVs
        # Preference: gridss > svaba > manta > delly
        my $sv_all = join("_", $gridss, $svaba, $manta, $delly);
        next if $sv_all =~ /[1-9].*orig/;
        
        print join("\t", @items)."\n";

        my $ext = 500;
        my $ext2 = 800; # for indel

        my $sv_id = sprintf("%s_%s_SV%05d", $sam_id, ($is_intra)?"INTRA":"INTER", $row_id);

        # get or redefine start2 and end2
        if ($is_intra){
            $len = $end - $start + 1; # assume mocca-sve uses 1-based coordindates
            
            $ext2 = int($len /6.0) if $len/6.0 > $ext2;

            $start2=$end2=$end;
            $end = $start;
            $chrom2=$chrom;
            
        }else{
            ($chrom2, $start2, $end2) = @items[3..5];
        }

        push @$snapshots, &new_snapshot($sv_id."_BP1", $chrom, $start, $end,$ext);
        push @$snapshots, &new_snapshot($sv_id."_BP2", $chrom2, $start2, $end2,$ext);

        
        # print join("\t", $chrom, $chrom2, $start2, $end2, $meerkat, $caller_count, $orig)."\n";

        &write_line_excel($ws, $NEXT_ROW, [$sv_id, $chrom, $start, $end, $chrom2, $start2, $end2, $svaba, $delly, $manta, $gridss, $meerkat, $caller_count, $orig]); 

        # IGV_script BP1_snapshot BP2_snapshot Overview_snapshot

        # write_item_with_local_link($ws, $NEXT_ROW, $hdr_col{IGV_script}, './IGV_Snapshots/'.$sam_id, $sv_id."_overview.bat");

        # add ROIs bat to all SVs from the same subj by default
        write_item_with_local_link($ws, $NEXT_ROW, $hdr_col{IGV_script}, './IGV_Snapshots/'.$sam_id, $sam_id."_ROIs.bat");

        ### Add link to the combined snapshot
        write_item_with_local_link($ws, $NEXT_ROW, $hdr_col{Combined_snapshot}, './IGV_Snapshots/'.$sam_id, $sv_id."_combined.png");

        # write_item_with_local_link($ws, $NEXT_ROW, $hdr_col{BP1_snapshot}, './IGV_Snapshots/'.$sam_id, $sv_id."_BP1.png");

        # write_item_with_local_link($ws, $NEXT_ROW, $hdr_col{BP2_snapshot}, './IGV_Snapshots/'.$sam_id, $sv_id."_BP2.png");

        if(defined $len && $len + 2*$ext2 <= $MAX_WINDOW){
            push @$snapshots, &new_snapshot($sv_id."_overview", $chrom, $start, $end2, $ext2);
            
            # write_item_with_local_link($ws, $NEXT_ROW, $hdr_col{Overview_snapshot}, './IGV_Snapshots/'.$sam_id, $sv_id."_overview.png");
        }
        # add snapshot for each SV

        $NEXT_ROW++;
        
    }
    close MOCCA;

    return $snapshots;
}

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

sub write_item_with_local_link{
    my $ws = shift;
    my $row = shift;
    my $col = shift;
    my $dir = shift;
    my $fn = shift; # "./IGV_Snapshots/".$entry->{name}

    $ws->write_url($row, $col, $dir."/".$fn, undef, $fn);
    
}

# rank the tissues in such way: normal, T01, and others

sub rank {
    my ($word) = @_;
    return do {
        given ($word) {
            0 when /normal/;
            1 when /T01/;
            default { 1000 };
        }
    };
}


sub new_snapshot{
    my $name = shift;
    my $chr = shift;
    my $start = shift;
    my $stop = shift;
    my $ext = shift // 200;

    my $h= {};
    $h->{name} = $name;
    $h->{chr} = $chr;
    $h->{start} = int($start);
    $h->{stop} = int($stop);
    $h->{ext} = int($ext);
    return $h;
}