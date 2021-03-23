"""Main module."""
import os
from pathlib import Path, PureWindowsPath

def update_dir(path, target_os="Mac"):
    """Update the file path
    
    Change T drive path to the right mounting path under the OS system. E.g.:
    CCAD: /DCEG/Scimentis/DNM/data/BATCH2_b38
    Mac: /Volumes/ifs/DCEG/Scimentis/DNM/data/BATCH2_b38
    Windows: T:\DCEG\Scimentis\DNM\data\BATCH2_b38

    Args:
        path ([type]): [description]
        to (str, optional): [description]. Defaults to "Mac". The other optionis "Windows".

    """
    parts = list(Path(path).parts)

    rv = None

    if target_os == "Mac": 
        parts[0]='/Volumes/ifs/' + parts[0]
        rv = str(Path(*parts))
    elif target_os == "Windows":
        parts[0]='T:\\' + parts[0]
        rv= PureWindowsPath(Path(*parts))
    else:
        return(path) # no chagne;

    return str(rv)
    

def subprocess_cmd(command):
    '''
    Runs a terminal command with stdout piping enabled
    https://github.com/stevekm/IGV-snapshot-automator/blob/master/make_IGV_snapshots.py
    '''
    import subprocess as sp
    process = sp.Popen(command,stdout=sp.PIPE, shell=True)
    proc_stdout = process.communicate()[0].strip()
    print(proc_stdout)

def mkdir_p(path, return_path=False):
    '''
    recursively create a directory and all parent dirs in its path
    https://github.com/stevekm/IGV-snapshot-automator/blob/master/make_IGV_snapshots.py
    '''
    import errno

    try:
        os.makedirs(path)
    except OSError as exc:  # Python >2.5
        if exc.errno == errno.EEXIST and os.path.isdir(path):
            pass
        else:
            raise
    if return_path:
        return path


def slugify(value, allow_unicode=False):
    """
    Taken from https://github.com/django/django/blob/master/django/utils/text.py
    Convert to ASCII if 'allow_unicode' is False. Convert spaces or repeated
    dashes to single dashes. Remove characters that aren't alphanumerics,
    underscores, or hyphens. Convert to lowercase. Also strip leading and
    trailing whitespace, dashes, and underscores.
    """
    import unicodedata
    import re

    value = str(value)
    if allow_unicode:
        value = unicodedata.normalize('NFKC', value)
    else:
        value = unicodedata.normalize('NFKD', value).encode('ascii', 'ignore').decode('ascii')
    # value = re.sub(r'[^\w\s-]', '', value.lower()) # "2:1000:A:CT" => 21000act
    value = re.sub(r'[^\w\s-]', '_', value) # "2:1000:A:CT" ==> "2_1000_A_CT"
    return re.sub(r'[-\s]+', '-', value).strip('-_')


class IGV_Snapshot_Maker:
    """" IGV Snapshot Maker"""

    # refgenome="hg19"
    # ext=100 
    # output_dir = "IGV_Snapshots"

    def __init__(self, refgenome="hg19", ext=100, output_dir="IGV_Snapshots", igv_cmd="igv"):
        """Constructur

        Args:
            refgenome (str, optional): reference genome name. Defaults to "hg19".
            ext (int, optional): extension of window size (bp). Defaults to 100.
            output_dir (str, optional): output directory. Defaults to "IGV_Snapshots".
            igv_cmd (str, optional): the command to run IGV. Defaults to "/Users/zhuw10/opt/miniconda3/bin/igv".
        """
        self.refgenome = refgenome
        self.ext = ext
        self.output_dir = output_dir
        self.batch = ""
        self.igv_cmd = igv_cmd
        self.xvfb_cmd = 'xvfb-run --auto-servernum --server-args="-screen 0 3200x2400x24" %s -b ' % igv_cmd
        self.reset_batch()

    def reset_batch(self):
        self.batch="""\
new
genome %s
""" % (self.refgenome)
        

    def load_bams(self, bam_files, target_os=None):
        """Add bam files

        Append load bam file statements to the IGV batch script 

        Args:
            bam_files (list): list of bam file names

        """
        out = ["load " + update_dir(f, target_os=target_os) for f in bam_files]

        self.batch += "\n".join(out) + "\n"

    def create_batch_file(self, group_name, name): 
        dir_name = os.path.abspath(os.path.join(self.output_dir, self.fix_name(group_name)) )
        mkdir_p(dir_name)

        bat_name = os.path.join(dir_name, self.fix_name(name) + ".bat" )
        self.bat = open(bat_name, "w")
        self.bat.write(self.batch)
        self.bat.write("snapshotDirectory %s\n" % dir_name)
        return(str(bat_name))

    def close_batch_file(self, exit=True):
        if exit: 
            self.bat.write("exit\n")

        self.bat.close()

    def goto(self, name, chr, start, stop, snapshot=True):
        
        png_name = self.fix_name(name) + ".png"

        self.bat.write(self.get_goto(chr,start, stop) + "\n")
        self.bat.write("sort base\ncollapse\n")

        if snapshot:
            self.bat.write("snapshot %s\n" % (png_name))
            

    def set_xvfb_cmd(self, xvfb_cmd ):
        """Set up the xvfb command to run IGV

        By default: "xvfb-run --auto-servernum --server-args="-screen 0 3200x2400x24" igv -b "

        Args:
            xvfb_cmd (str): xvfb-run command
        """
        self.xvfb_cmd = xvfb_cmd

    def call_igv(self, bat_name):
        """Call IGV

        Call IGV using igv -v 
        Args:
            bat_name (str): Batch script file name

        """

        igv_command = self.xvfb_cmd + bat_name
        print("\nRunning the IGV command...")
        subprocess_cmd(igv_command)



    def get_goto(self, chr, start, stop): 
        """ goto chr1:35656750-35657150

        The target regions is cenetered on start+1 (1-based), [start+1-ext, start+1+ext]. stop is not used for the time being

        Args:
            chr (str): chromosome
            start (int): start position
            stop (int): stop position

        Returns:
            str: goto chr1:35656750-35657150

        """
        rv = "goto %s:%d-%d" % (chr, start+1-self.ext, stop+1+self.ext)
        return(rv)


    def fix_name(self, name):
        """Fix name for file or folder

        Use the function slugify to convert str to a valid name for folder/file
        Args:
            name (str): original name

        Returns: 
            str: the new name

        """
        return(slugify(name))