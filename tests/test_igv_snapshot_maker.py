#!/usr/bin/env python

"""Tests for `igv_snapshot_maker` package."""

import pytest
import os
from pathlib import Path

from igv_snapshot_maker.igv_snapshot_maker import IGV_Snapshot_Maker

default_batch="""\
new
genome hg19
""" 

default_batch_load="""\
new
genome hg19
load a
load b
load c
""" 



@pytest.fixture
def my_maker():
    return IGV_Snapshot_Maker()

def test_maker(my_maker):
    assert my_maker.refgenome == "hg19"  
    assert my_maker.xvfb_cmd == 'xvfb-run --auto-servernum --server-args="-screen 0 3200x2400x24" igv -b '  


def test_header(my_maker):
    assert my_maker.batch == default_batch 

def test_load_bam(my_maker):
    my_maker.load_bams(['a', 'b','c'])
    assert  my_maker.batch == default_batch_load  

def test_fix_name(my_maker):
    assert my_maker.fix_name("2:1000:A:CT") == "2_1000_A_CT"

def test_goto(my_maker):
    assert my_maker.get_goto('3', 1000, 2000) == "goto 3:901-1101"

def test_generate_batch_file(my_maker):
    my_maker.load_bams(['a', 'b','c'])
    batch_fn = my_maker.generate_batch_file("GENE", '2:1000:A:CT', 2, 999, 1000)

    snap_dir = Path("./IGV_Snapshots/GENE").absolute()

    assert snap_dir.is_dir()
    assert str(batch_fn) == str(snap_dir/'2_1000_A_CT.bat')
    assert (snap_dir/'2_1000_A_CT.bat').is_file()
     