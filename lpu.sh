#!/bin/bash
# Web Host Log Parsing Utility
# @filename lpu.sh
# @created 2022.08.23
# @version 2022.12.22+00:00

# Configure global logging
log_file="/var/log/lpu.log" # Path to log file
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>$log_file 2>&1
# Everything below will be logged to "$log_file":

# Check that we are running as root, otherwise make it so 
[ $EUID -ne 0 ] && echo "[WARN] User not running as root" && sudo -s $0
[ $EUID -eq 0 ] && echo "[INFO] User running as root"
[ $EUID -ne 0 ] && exit 0


### Default Configuration Information ###
## This can be overwritten by the config file if it exists
start_timestamp=$(date +"%Y%m%d_%H%M%S")
relative_script_path="$0"
absolute_script_path="$(readlink -f $0)"
script_name="${absolute_script_path##*/}"
echo -e "\n[INFO] Execution of ${script_name} started at ${start_timestamp}"
base_directory="$(dirname "${absolute_script_path}")" #"/opt/lpu" # Base working directory 
config_file="${base_directory}/lpu.conf" #"/etc/lpu.conf" # Path to config file 
functions_file="${base_directory}/functions.incl"
temp_directory="${base_directory}/tmp" # Temporary working directory
package_directory="${base_directory}/deliverable" # Directory to save reports in
# Default selections for parse term parameters
term_period="month" # Length of term to parse, e.g. hour, day, month, year, or all 
term_target="last month" # String datetime describing a point within the desired term_period
# Hashing preferences
host_hash_start=1
host_hash_stop=12
site_hash_start=1
site_hash_stop=24


# Source config if it exists
[ -f $config_file ] && source $config_file
[ -f $funcitons_file ] && source $functions_file

debug_configuration=$(cat <<EOF
Default Configuration:
	relative_script_path = $relative_script_path
	absolute_script_path = $absolute_script_path
	base_directory = $base_directory
	config_file = $config_file
	temp_directory = $temp_directory 
	package_directory = $package_directory
	log_file = $log_file 
	term_period = $term_period 
	term_target = $term_target 
	host_hash_start = $host_hash_start
	host_hash_stop = $host_hash_stop
	site_hash_start = $site_hash_start
	site_hash_stop = $site_hash_stop
EOF
)
echo "[INFO] ${debug_configuration}" 

### Initialization ###
# Create the working directory if it doesn't exist; then change to it, regardless
[ ! -d $base_directory ] && mkdir $base_directory; 
cd $base_directory || exit 1

# Check that the current working directory is the prescribed base directory, otherwise error out
[ "$(pwd)" != "${base_directory}" ] && echo "[ERR] Failed to change into base directory." && exit 1

# Create the package directory for deliverables if it doesn't already exist
[ ! -d $package_directory ] && mkdir $package_directory;

# Remove any pre-existing temp directory; then create one, regardless
[ -d $temp_directory ] && rm -rf $temp_directory; 
mkdir -p $temp_directory

# Create subdirectories for 'sites', 'host', and 'manager' under the temp directory
mkdir -p $temp_directory/{sites,host,manager,trash}
mkdir -p $temp_directory/host/{apache2,exim,messages,maillog,secure}
mkdir -p $temp_directory/manager/users
mkdir -p $temp_directory/conf 
mkdir -p $temp_directory/logs 


# Pull target date information
year=$(date -d "$term_target" +%Y) # term_target's year
month=$(date -d "$term_target" +%b) # term_target's month, as formatted by Apache
dom=$(date -d "$term_target" +%d) # term_target's day of the month
iso_date=$(date -d "$term_target" +%F) # term_target's full date; like %+4Y-%m-%d
short_date="${iso_date//-/}"
timezone=$(date -d "$term_target" +%Z) # Alphabetic time zone abbreviation, e.g. EST
# Generate a runtime timestamp
timestamp=$(date +"%Y%m%d_%H%M%S") # Timestamp

debug_time_info=$(cat <<EOF
Datetime Information:
	year = $year 
	month = $month 
	dom = $dom 
	iso_date = $iso_date 
	timezone = $timezone 
	timestamp = $timestamp
EOF
)
echo "[INFO] ${debug_time_info}"

# Check that the working directory is empty of any '*.gz' files, otherwise remove them
ls *.gz > /dev/null 2>&1 && rm *.gz

# Generate a hash of the current hostname
plain_host=$(hostname | xargs)
hashed_host=$(host_hash_function "$plain_host")
debug_host_hash=$(cat <<EOF
Host Information: 
	hashed_host = $hashed_host
EOF
)
echo "[INFO] ${debug_host_hash}"


##### Main Process #####
[ -n $existing_conf_files ] && ( for cf in ${existing_conf_files[@]}; do rsync -avR $cf $temp_directory/conf/; done )
[ -n $existing_log_files ] && ( for lf in ${existing_log_files[@]}; do rsync -avR $lf $temp_directory/logs/; done )

## Pull access logs from each site's home directory into $base_directory
case "$term_period" in 
	d|day|Day) cp /home/*/logs/*-${month}-${year}.gz ./ ;;
	m|month|Month) cp /home/*/logs/*-${month}-${year}.gz ./ ;;
	y|year|Year) cp /home/*/logs/*-${year}.gz ./ ;;
	*) ;;
esac
site_names=()
# Iterate through the gzipped log files in $base_directory
echo "[INFO] Entering for-loop at $(date +"%Y-%m-%d_%H:%M:%S")"
for zipped_log in *.gz; do

    # Unzip the current file
    gunzip "$zipped_log"

    # Strip the '.gz' extension from zipped_log and save it for reference
    unzipped_log=$(echo $zipped_log | sed -e s/\.gz$//) 

    # Extract logs from the previous day into a separate file in $temp_directory
	case "$term_period" in 
		d|day|Day) grep "${dom}/${month}/${year}" $unzipped_log >> "${temp_directory}/sites/${unzipped_log}" ;;
		m|month|Month) grep ".*/${month}/${year}" $unzipped_log >> "${temp_directory}/sites/${unzipped_log}" ;;
		y|year|Year) grep ".*/.*/${year}" $unzipped_log >> "${temp_directory}/sites/${unzipped_log}" ;;
		*) ;;
	esac

	# Strip the TLD from the FQDN to get a bare domain name 
	current_site=$(echo $unzipped_log | sed -e 's/\.[^.][^.]*$//')
	
	# Append $current_site to the $site_names array
	site_names+=($current_site)
	
	# Hash the current sitename
	hashed_site=$(site_hash_function "$current_site")
	
### Only used for debugging ###
debug_site_info=$(cat <<	EOF
	current_site = $current_site 
	hashed_site = $hashed_site
	zipped_log = $zipped_log 
	unzipped_log = $unzipped_log 
EOF
)
	#echo "[INFO] ${debug_site_info}"
	echo "[INFO] Processing ${hashed_site} : $(echo ${unzipped_log} | sed "s/${current_site}/${hashed_site}/gi")"
###############################
	
	# Append site and hostname to the end of each line in the logfile 
	sed -i "s/$/ ${hashed_site}/" "${temp_directory}/sites/${unzipped_log}"
	#sed -i "s/$/ ${hashed_site} ${hashed_host}/" "${temp_directory}/sites/${unzipped_log}"  # <-- Maybe used later
	
	# Mask instances of the hostname occurring in the logs <-- Does not mask any instances outside of own logs
	sed -i "s/${current_site}/${hashed_site}/gi" "${temp_directory}/sites/${unzipped_log}"
	
	# Rename logfile with hashed domain name
	mv $temp_directory/sites/$unzipped_log $temp_directory/sites/$hashed_site

    # Re-zip the current file (so it can be identified for deletion), then on to the next
	gzip $unzipped_log 
done
echo "[INFO] Exiting for-loop at $(date +"%Y-%m-%d_%H:%M:%S")"

# Mask host name
#echo "[INFO] Masking unhashed host name within files under the temp directory"
#find $temp_directory -type f | xargs sed -i "s/${plain_host}/${hashed_host}/gi"  #"${temp_directory}/*" # <- Handles the possibility of this hostname being logged by other sites
#find ./ -type f -exec sed -i -e 's/orange/apple/g' {} \;

# Append hashed host to the end of each log entry in the tmp/host subdirectory
#find $temp_directory/host -type f | xargs sed -i "s/$/ ${hashed_host}/"




declare -a strings_to_mask 
for user_file in $temp_directory/conf/var/cpanel/users/*; do 
	for info in ${user_info[@]}; do
		strings_to_mask+=($(grep "$info" $user_file | cut -f2 -d '=' | xargs))
	done 
done






# Remove trash before archiving
echo "[INFO] Emptying trash"
rm -rf "${temp_directory}/trash"

### Create deliverable archive 
echo "[INFO] Creating archive and compressing"
cp $log_file $temp_directory 
( cd $temp_directory && tar -czf "${package_directory}/${hashed_host}_${timestamp}_${term_period}_of_${short_date}.tar.gz" * )

# Clean up working directory before we finish up
echo "[INFO] Tidying up working directory"
rm -rf $temp_directory
rm *.gz

# Exit gracefully
echo "[INFO] Execution of ${script_name} complete at $(date +"%Y-%m-%d_%H:%M:%S")"
echo -e "\n"
