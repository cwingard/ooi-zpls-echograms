#!/bin/bash
#
# Setup a batch processing job for the recovered data from an uncabled AZFP
# bioacoustic sonar sensor.
#
# C. Wingard 2021-11-10
#
# NOTE: CONDA_SH below is host-specific and MUST be set correctly for the
# machine this script runs on -- especially if invoked from cron, which does
# not source .bashrc/.profile and so cannot rely on $CONDA_EXE or anything
# else from an interactive shell's environment.
CONDA_SH="/home/ooiuser/miniconda3/etc/profile.d/conda.sh"   # e.g. /opt/ooidata/miniconda3/etc/profile.d/conda.sh

set -euo pipefail

# Parse the command line inputs, setting the data directories and processing dates
if [ $# -ne 6 ]; then
    echo "$0: required inputs are the site name, the path to the raw and processed data"
    echo "directories, the path to the XML file with instrument specific calibration"
    echo "coefficients, and the starting and ending dates (format is YYYY-MM-DD) of the"
    echo "deployment to batch process."
    echo ""
    echo "    example: $0 ce07shsm /home/ooiuser/data/raw/CE07SHSM/R00010/instrmts/dcl37/ZPLSC_sn55099/DATA \\ "
    echo "        /home/ooiuser/data/raw/CE07SHSM/R00010/instrmts/dcl37/ZPLSC_sn55099/processed \\ "
    echo "        /home/ooiuser/data/raw/CE07SHSM/R00010/instrmts/dcl37/ZPLSC_sn55099/DATA/201910/19101018.XML \\ "
    echo "        \"2019-10-10\" \"2020-07-16\""
    exit 1
fi
SITE=${1^^}
DATA_DIR=$2
PROC_DIR=$3
XML_FILE=$4
START_DATE=`date -u +%Y%m%d -d $5`
END_DATE=`date -u +%Y%m%d -d $6`

# activate the echogram environment
. "$CONDA_SH" || { echo "$0: failed to source $CONDA_SH" >&2; exit 1; }
conda activate echogram || { echo "$0: failed to activate 'echogram' env" >&2; exit 1; }

# Set up concurrent parallel processing using 4 cores (equates to 4 weeks)
N=4
FAILED=0
PIDS=()

# process the data, using 2012-01-01 as the base year for all plots
for d in $(seq $(date -u +%s -d "2012-01-01") +604800 $(date -u +%s -d $END_DATE)); do
    start_date=`date -u +%Y%m%d -d @$d`
    stop_date=`date -u +%Y%m%d -d "$start_date+7days"`
    if [[ $stop_date -gt $START_DATE ]]; then 
        (zpls-echogram -s $SITE -d $DATA_DIR -o $PROC_DIR -dr $start_date $stop_date -zm AZFP -xf $XML_FILE) &
        PIDS+=($!)
    fi
    if (( ${#PIDS[@]} >= N )); then
        # there are already $N jobs outstanding, wait for the oldest to finish
        wait "${PIDS[0]}" || { echo "$0: job (PID ${PIDS[0]}) failed" >&2; FAILED=1; }
        PIDS=("${PIDS[@]:1}")
    fi
done
# no more jobs to run, but wait for the remaining ones to finish
if (( ${#PIDS[@]} > 0 )); then
    for pid in "${PIDS[@]}"; do
        wait "$pid" || { echo "$0: job (PID $pid) failed" >&2; FAILED=1; }
    done
fi

if (( FAILED != 0 )); then
    echo "$0: one or more processing jobs failed, see messages above" >&2
    exit 1
fi
