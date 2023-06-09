#!/bin/bash

# ------------------------------------------------------------------------- #
# This script submits g4sbs, sbsdig, and replay jobs to the batch farm and  #
# enusres they run in right order. There is a flag that can be set to run   #
# all the jobs on ifarm as well.                                            #
# ---------                                                                 #
# P. Datta <pdbforce@jlab.org> CREATED 11-09-2022                           #
# ---------                                                                 #
# ** Do not tamper with this sticker! Log any updates to the script above.  #
# ------------------------------------------------------------------------- #

# Setting necessary environments (ONLY User Specific part)
export SCRIPT_DIR=/w/halla-scshelf2102/sbs/pdbforce/jlab-HPC
export G4SBS=/w/halla-scshelf2102/sbs/pdbforce/G4SBS/install
export LIBSBSDIG=/work/halla/sbs/pdbforce/LIBSBSDIG/install
export ANALYZER=/work/halla/sbs/pdbforce/ANALYZER/install
export SBSOFFLINE=/work/halla/sbs/pdbforce/SBSOFFLINE/install
export SBS_REPLAY=/work/halla/sbs/pdbforce/SBS-replay

preinit=$1      # G4SBS preinit macro w/o file extention (Must be located at $G4SBS/scripts)
sbsconfig=$2    # SBS configuration (Valid options: 4,7,11,14,8,9)
nevents=$3      # No. of events to generate per job
fjobid=$4       # first job id
njobs=$5        # total no. of jobs to submit 
run_on_ifarm=$6 # 1=>Yes (If true, runs all jobs on ifarm)
# Workflow name
workflowname='fscan-sbs4'  # Not relevant if run_on_ifarm = 1
# Specify a directory on volatile to store g4sbs, sbsdig, & replayed files.
# Working on a single directory is convenient & safe for the above mentioned
# three processes to run smoothly.
outdirpath='/lustre19/expphy/volatile/halla/sbs/pdbforce/g4sbs_output/fscan'

# Validating the number of arguments provided
if [[ "$#" -ne 6 ]]; then
    echo -e "\n--!--\n Illegal number of arguments!!"
    echo -e " This script expects 6 arguments: <preinit> <sbsconfig> <nevents> <fjobid> <njobs> <run_on_ifarm>\n"
    exit;
else 
    echo -e '\n------'
    echo -e ' Check the following variable(s):'
    if [[ $run_on_ifarm -ne 1 ]]; then
	echo -e ' "workflowname" : '$workflowname''
    fi
    echo -e ' "outdirpath"   : '$outdirpath' \n------'
    while true; do
	read -p "Do they look good? [y/n] " yn
	echo -e ""
	case $yn in
	    [Yy]*) 
		break; ;;
	    [Nn]*) 
		if [[ $run_on_ifarm -ne 1 ]]; then
		    read -p "Enter desired workflowname : " temp1
		    workflowname=$temp1
		fi
		read -p "Enter desired outdirpath   : " temp2
		outdirpath=$temp2		
		break; ;;
	esac
    done
fi

# Create the output directory if necessary
if [[ ! -d $outdirpath ]]; then
    { #try
	mkdir $outdirpath
    } || { #catch
	echo -e "\n!!!!!!!! ERROR !!!!!!!!!"
	echo -e $outdirpath "doesn't exist and cannot be created! \n"
	exit;
    }
fi

# Creating the workflow
if [[ $run_on_ifarm -ne 1 ]]; then
    swif2 create $workflowname
else
    echo -e "\nRunning all jobs on ifarm!\n"
fi

for ((i=$fjobid; i<$((fjobid+njobs)); i++))
do
    # lets submit g4sbs jobs first
    outfilebase=$preinit'_job_'$i
    postscript=$preinit'_job_'$i'.mac'
    g4sbsjobname=$preinit'_job_'$i

    g4sbsscript=$SCRIPT_DIR'/run-g4sbs-simu.sh'

    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -partition production -name $g4sbsjobname -cores 1 -disk 5GB -ram 1500MB $g4sbsscript $preinit $postscript $nevents $outfilebase $outdirpath $run_on_ifarm $G4SBS
    else
	$g4sbsscript $preinit $postscript $nevents $outfilebase $outdirpath $run_on_ifarm $G4SBS
    fi

    # time to aggregate g4sbs job summary
    aggsuminfile=$outdirpath'/'$preinit'_job_'$i'.csv'
    aggsumjobname=$preinit'_asum_job_'$i
    aggsumoutfile=$outdirpath'/'$preinit'_summary.csv'

    aggsumscript=$SCRIPT_DIR'/agg-g4sbs-job-summary.sh'

    if [[ ($i == 0) || (! -f $g4sbssumtable) ]]; then
	$aggsumscript $aggsuminfile '1' $aggsumoutfile
    fi
    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -antecedent $g4sbsjobname -partition production -name $aggsumjobname -cores 1 -disk 1GB -ram 150MB $aggsumscript $aggsuminfile '0' $aggsumoutfile $SCRIPT_DIR
    else
	$aggsumscript $aggsuminfile '0' $aggsumoutfile $SCRIPT_DIR
    fi

    # now, it's time for digitization
    txtfile=$preinit'_job_'$i'.txt'
    sbsdigjobname=$preinit'_digi_job_'$i
    sbsdiginfile=$outdirpath'/'$outfilebase'.root'

    sbsdigscript=$SCRIPT_DIR'/run-sbsdig.sh'
    
    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -antecedent $g4sbsjobname -partition production -name $sbsdigjobname -cores 1 -disk 5GB -ram 1500MB $sbsdigscript $txtfile $sbsdiginfile $run_on_ifarm $LIBSBSDIG
    else
	$sbsdigscript $txtfile $sbsdiginfile $run_on_ifarm $LIBSBSDIG
    fi

    # finally, lets replay the digitized data
    digireplayinfile=$preinit'_job_'$i
    digireplayjobname=$preinit'_digi_replay_job_'$i

    digireplayscript=$SCRIPT_DIR'/run-digi-replay.sh'
    
    if [[ $run_on_ifarm -ne 1 ]]; then
	swif2 add-job -workflow $workflowname -antecedent $sbsdigjobname -partition production -name $digireplayjobname -cores 1 -disk 5GB -ram 1500MB $digireplayscript $digireplayinfile $sbsconfig -1 $outdirpath $run_on_ifarm $ANALYZER $SBSOFFLINE $SBS_REPLAY
    else
	$digireplayscript $digireplayinfile $sbsconfig -1 $outdirpath $run_on_ifarm $ANALYZER $SBSOFFLINE $SBS_REPLAY
    fi
done

# run the workflow and then print status
if [[ $run_on_ifarm -ne 1 ]]; then
    swif2 run $workflowname
    echo -e "\n Getting workflow status.. [may take a few minutes!] \n"
    swif2 status $workflowname
fi
