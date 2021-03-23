"""Console script for igv_snapshot_maker."""
import os
import sys
import logging
import argparse
import warnings
import yaml
import pathlib

from igv_snapshot_maker2 import IGV_Snapshot_Maker

'''
Ref: https://github.com/stevekm/IGV-snapshot-automator/blob/master/make_IGV_snapshots.py

Input: 
    YAML FILE: a list of dictonary:
        name, items [{name, start, stop, bam_files}]
Output: 
    Group Name
        snapshot_name.png
        snapshot_name.bat
'''

'''
cli2.py is a revision of cli.py, due to the change in the yaml format:
+ The major change is to move the bam_files from the items level to an upper level. 
+ There is minor change like "items" to "snapshots". 
+ The according change in the output is to have one master batch script and the individual script for each snapshot.
  + The customized path folder will be provided from the command-line. 
  + igv_snapshot_maker2.py is used.
   
'''

VERSION="0.1.0-dev"

USAGE = """\
IGV_snapshot_maker.py v%s: Genenerate IGV snapshots
""" % VERSION

THIS_DIR = os.path.dirname(os.path.realpath(__file__))
default_output_dir = os.path.join(THIS_DIR, "IGV_Snapshots")

def parse_args():
    """
    Pull the command line parameters
    """
    
    parser = argparse.ArgumentParser(prog="IGV_snapshot_maker", description=USAGE,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)

    parser.add_argument("-o", "--output", default=default_output_dir, type=str, required=False, metavar = 'output directory', help="Output directory for snapshots")
                        
    parser.add_argument("-e", "--extend", default=100, type=int, required=False, metavar = 'Extend +/- N bp', help="Extend N (N=100 by default) base pairs in two directions in IGV window")

    parser.add_argument("-g", default = 'hg19', type = str, dest = 'genome', metavar = 'genome', help="Name of the reference genome, Defaults to hg19")

    parser.add_argument("-f", default = 'Mac', type = str, dest = 'filesystem', metavar = 'filesystem', help="The target operating system (Mac or Windows) to run IGV, Defaults to Mac.")

    parser.add_argument("--igv", default = 'igv', type = str, dest = 'igv_cmd',  help="The command to run IGV (at CCAD)")

    parser.add_argument("-m", "--mem", default = "4000", type = str, dest = 'igv_mem', required=False, metavar = 'IGV memory (MB)', help="Amount of memory to allocate to IGV, in Megabytes (MB)")

    parser.add_argument("-i", "--input", type = str,  required=True, metavar = 'Input file', help="Input file in YAML format")

    args = parser.parse_args()
    return(args)
    
  

def setup_logging(debug=False, filename="my_log.txt", log_format=None):
    """
    Default logger
    """
    logLevel = logging.DEBUG if debug else logging.INFO
    if log_format is None:
        log_format = "%(asctime)s [%(levelname)s] %(message)s"
    logging.basicConfig(filename=filename, level=logLevel, format=log_format, filemode='w',)
    logging.info("Running %s", " ".join(sys.argv))

    def sendWarningsToLog(message, category, filename, lineno):
        """
        Put warnings into logger
        """
        logging.warning('%s:%s: %s:%s', filename, lineno, category.__name__, message)

    # pylint: disable=unused-variable
    old_showwarning = warnings.showwarning
    warnings.showwarning = sendWarningsToLog

def main():
    """Console script for igv_snapshot_maker."""
    args = parse_args() 
    setup_logging(debug=True)
    
    logging.info("Read %s", args.input)

    
    with open(args.input, 'r') as stream:
        try:
            dat = yaml.safe_load(stream)
        except yaml.YAMLError as exc:
            print(exc)

    # print("Extension (bp): %d" % args.extend + "\n")

    maker = IGV_Snapshot_Maker(ext = args.extend, refgenome=args.genome , output_dir=args.output, igv_cmd=args.igv_cmd)
    maker2 = IGV_Snapshot_Maker(ext = args.extend, refgenome=args.genome , output_dir=args.output, igv_cmd=args.igv_cmd)

    for i in dat:
        
        group_name = i['name']
        items = i['snapshots']
        maker.reset_batch() # reset the genome file

        maker.load_bams(sp['bam_files'])
        master_bat_fn = maker.create_batch_file(group_name, group_name)

        

        for sp in items: 
            maker2.reset_batch()
            maker2.load_bams(sp['bam_files'], target_os=args.filesystem)
            

            fn = maker2.create_batch_file(i['name'], sp['name'] )

            maker.goto(sp['name'], sp['chr'], sp['start'], sp['stop'], snapshot=True)
            maker2.goto(sp['name'], sp['chr'], sp['start'], sp['stop'], snapshot=False)

            print("Generating the script file %s\n" % fn)
            maker2.close_batch_file(exit=False)

        # run the master script
        maker.close_batch_file(exit=True) 
        maker.call_igv(master_bat_fn)

    return(0)


if __name__ == "__main__":
    sys.exit(main())  # pragma: no cover
