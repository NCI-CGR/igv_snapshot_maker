"""Console script for igv_snapshot_maker."""
import os
import sys
import logging
import argparse
import warnings
import yaml

from igv_snapshot_maker import IGV_Snapshot_Maker

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

    parser.add_argument("-mem", default = "4000", type = str, dest = 'igv_mem', required=False, metavar = 'IGV memory (MB)', help="Amount of memory to allocate to IGV, in Megabytes (MB)")

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

    maker = IGV_Snapshot_Maker(ext = args.extend)

    for i in dat:
        
        # group_name = i['name']
        items = i['items']

        for sp in items: 
            maker.reset_batch()
            maker.load_bams(sp['bam_files'])
            fn = maker.generate_batch_file(i['name'], sp['name'], sp['chr'], sp['start'], sp['stop'] )
            print("Generating the script file %s\n" % fn)

            # run it 
            maker.call_igv(fn)

    return(0)


if __name__ == "__main__":
    sys.exit(main())  # pragma: no cover
