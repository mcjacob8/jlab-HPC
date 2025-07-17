#!/bin/bash

# ------------------------------------------------------------------------- #
# This script submits a single job for real data analysis. It should be     #
# called by sbs-replay-main.sh.                                             #
# ---------                                                                 #
# P. Datta <pdbforce@jlab.org> CREATED 11-09-2022                           #
# Sean Jeffas <sj9ry@virginia.edu> Updated 07-25-2023                       #
# ---------                                                                 #
# ** Do not tamper with this sticker! Log any updates to the script above.  #
# ------------------------------------------------------------------------- #

runnum=$1
prefix=$2
nevents=$3
maxsegments=$4
segments_per_job=$5
use_sbs_gems=$6
run_on_rivanna=$7
outdirpath=$8
workflowname=$9
scriptdir=${10}
analyzerenv=${11}
sbsofflineenv=${12}
sbsreplayenv=${13}
datapath=${14}
ANAVER=${15}     # Analyzer version
useJLABENV=${16} # Use 12gev_env instead of modulefiles?
JLABENV=${17}    # /site/12gev_phys/softenv.sh version

#Set environments from inputs above
export SCRIPT_DIR=$scriptdir
export ANALYZER=$analyzerenv
export SBSOFFLINE=$sbsofflineenv
export SBS_REPLAY=$sbsreplayenv
export DATA_PATH=$datapath
#export DATA_DIR=/cache/$DATA_PATH
export DATA_DIR=$DATA_PATH

firstsegment=0
lastsegment=0
nsegments=0

# look for first segment of first stream on cache disk:
firstsegname=$prefix'_'$runnum'.evio.0.0'
mssfirst='mss:/mss/'$DATA_PATH/$firstsegname
#cachefirst='/cache/mss/'$DATA_PATH/$firstsegname
cachefirst=$DATA_PATH/$firstsegname

script=$SCRIPT_DIR'/run-sbs-replay.sh'

# no matter what we require the first stream, first segment for each job (must exist)
# so we initialize input string to the first segment of first stream:
inputstring=' -input '$cachefirst' '$mssfirst' '

for ((i=0; i<=$maxsegments; i++))
do

    segment_i_added=0 # this will be set to 1 if at least segment i stream 0 is found:
    
    if(( $nsegments == 0 )); then # we haven't added any segments to this job yet:
	# initialize firstsegment and inputstring:
	firstsegment=$i
	inputstring=' -input '$cachefirst' '$mssfirst' '
    fi

    # look for streams zero through 2 for segment i: $i is segment number $j is stream number
    for((j=0; j<=2; j++))
    do 
	eviofilename=$prefix'_'$runnum'.evio.'$j'.'$i
	mssfilename='mss:/mss/'$DATA_PATH/$eviofilename
	#cachefile='/cache/mss/'$DATA_PATH/$eviofilename
	cachefile=$DATA_PATH/$eviofilename

	testfilename=$DATA_PATH/$eviofilename
	#testfilename='/mss/'$DATA_PATH/$eviofilename
        echo $cachefile	
	if [ -f "$testfilename" ]; 
	then
	    if(( $j == 0 )); then
		(( nsegments++ ))
		segment_i_added=1
	    fi
	    if(( !($j == 0 && $i == 0) )); then # unless this is the first segment of stream 0, add the file to the job:
		inputstring+=' -input '$cachefile' '$mssfilename' '
	    fi
	fi
    done # end loop on streams 0-2
    echo ">>> Reached checkpoint: [1]"
    echo $segment_i_added
    # After adding any files found from this segment number to the job,
    # check if this is the last segment or if adding this segment caused us to reach the target number of segments per job:
    if(( $segment_i_added == 1 )); then # if we at least found stream 0 for this segment, proceed: 
	# increment the number of segments:
	# NO! This was already done above! ((nsegments++))

        echo ">>> Reached checkpoint: [1.5]"
	if (( $i == $maxsegments || $nsegments == $segments_per_job )); 
	    then # this is either the last segment or we reached the required number of segments per job. 
	    # Go ahead and launch the job and then reset segment counter:
	    lastsegment=$i 
	    jobname=$prefix'_replay_'$runnum'_segments'$firstsegment'_'$lastsegment
	    
	    echo 'Submitting job '$jobname' with '$nsegments' segments, runnum='$runnum
	    #		echo 'Input string = '$inputstring
	    
	    scriptrun=$script' '$runnum' '$nevents' 0 '$prefix' '$firstsegment' '$nsegments' '$use_sbs_gems' '$DATA_PATH' '$outdirpath' '$run_on_rivanna' '$ANALYZER' '$SBSOFFLINE' '$SBS_REPLAY' '$ANAVER' '$useJLABENV' '$JLABENV
	    addjobcmd='add-job -workflow '$workflowname' -partition production -name '$jobname' -cores 1 -disk 25GB -ram 3000MB '$inputstring' '$scriptrun
	    
	    #if [[ $run_on_ifarm -ne 1 ]]; then
	    #    swif2 $addjobcmd
		##echo $addjobcmd
	    #else
		#$scriptrun
	    #fi

            echo ">>> Reached checkpoint: [2]"
		if [[ $run_on_rivanna -ne 1 ]]; then
        # Create a temporary SLURM submission script for this job
    		slurmscript=$(mktemp /tmp/slurmjob_${jobname}.XXXXXX.sh)

    		cat > "$slurmscript" <<EOF
#!/bin/bash
#SBATCH --job-name=$jobname
#SBATCH --output=$outdirpath/logs/${jobname}.out
#SBATCH --error=$outdirpath/logs/${jobname}.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=3000
#SBATCH --time=24:00:00
#SBATCH --partition=standard

module purge
# Load required modules (modify these based on what's available)
module use /share/apps/modulefiles
module load gcc
module load physics/root
module load cmake

# Source analyzer setup if available
if [[ -f /standard/sbs/Analyzer/bin/setup.sh ]]; then
    source /standard/sbs/Analyzer/bin/setup.sh
fi

$scriptrun
EOF
		    sbatch "$slurmscript"
		    #jobid=$(sbatch "$slurmscript" | awk '{print $4}')
		    #echo "Submitted job '$jobname' with Job ID: $jobid"
		else
    		        echo "Running job interactively with command:"
                        echo "$scriptrun"
                        $scriptrun
		fi
       	    nsegments=0
	fi

    else # current segment NOT added; if any segments have been added to the job, go ahead and submit the job if applicable
	
        echo ">>> Reached checkpoint: [new]"
	if (( $nsegments > 0 ))
	then
	    ((lastsegment=$i-1))
	    jobname=$prefix'_replay_'$runnum'_segments'$firstsegment'_'$lastsegment
	    
	    echo 'Submitting job '$jobname' with '$nsegments' segments, runnum = '$runnum
#	    echo 'Input string = "'$inputstring'"'

	    scriptrun=$script' '$runnum' '$nevents' 0 '$prefix' '$firstsegment' '$nsegments' '$use_sbs_gems' '$DATA_PATH' '$outdirpath' '$run_on_rivanna' '$ANALYZER' '$SBSOFFLINE' '$SBS_REPLAY' '$ANAVER' '$useJLABENV' '$JLABENV
	    addjobcmd='add-job -workflow '$workflowname' -partition production -name '$jobname' -cores 1 -disk 25GB -ram 3000MB '$inputstring' '$scriptrun

	    #if [[ $run_on_ifarm -ne 1 ]]; then
	    #    swif2 $addjobcmd
		##echo $addjobcmd
	    #else
		#$scriptrun
	    #fi

		if [[ $run_on_rivanna -ne 1 ]]; then
    		# Create a temporary SLURM submission script for this job
    		slurmscript=$(mktemp /tmp/slurmjob_${jobname}.XXXXXX.sh)

    		cat > "$slurmscript" <<EOF
#!/bin/bash
#SBATCH --job-name=$jobname
#SBATCH --output=$outdirpath/logs/${jobname}.out
#SBATCH --error=$outdirpath/logs/${jobname}.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=3000
#SBATCH --time=24:00:00
#SBATCH --partition=standard

module purge
# Load required modules (modify these based on what's available)
module use /share/apps/modulefiles
module load gcc
module load physics/root
module load cmake

# Source analyzer setup if available
if [[ -f /standard/sbs/Analyzer/bin/setup.sh ]]; then
    source /standard/sbs/Analyzer/bin/setup.sh
fi

$scriptrun
EOF

    		sbatch "$slurmscript"
		#jobid=$(sbatch "$slurmscript" | awk '{print $4}')
                #echo "Submitted job '$jobname' with Job ID: $jobid"
		else
			echo "Running job interactively with command:"
    			echo "$scriptrun"
    			$scriptrun
		fi

	    nsegments=0
	fi
	break
    fi
done
