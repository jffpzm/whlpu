#!/bin/bash
# Web Host Log Parsing Utility
# @filename lpu.sh
# @created 2022.08.23
# @version 2022.12.21+15:15

# Configure global logging
log_file="/var/log/lpu.log" # Path to log file
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>$log_file 2>&1
# Everything below will be logged to "$log_file":


### Function Definitions Part 1 ###
await() { echo -e "\n\n$1"; read -rsn1 -p "Press any key to continue" && echo -e "\n\n"; }
get_timestamp() { date +"%Y-%m-%d+%H:%M:%S"; }
###

relative_script_path="$0"
absolute_script_path="$(readlink -f $0)"
script_name="${absolute_script_path##*/}"
echo -e "\n[INFO] Execution of ${script_name} started at $(date +"%Y-%m-%d_%H:%M:%S")"

### Configuration Information ###
base_directory="$(dirname "${absolute_script_path}")" #"/opt/lpu" # Base working directory 
config_file="${base_directory}/lpu.conf" #"/etc/lpu.conf" # Path to config file 
temp_directory="${base_directory}/tmp" # Temporary working directory
package_directory="${base_directory}/deliverable" # Directory to save reports in
# Default selections for parse term parameters
term_period="month" # Length of term to parse, e.g. hour, day, month, year, or all 
term_target="last month" # String datetime describing a point within the desired term_period
# Hashing preferences
# Must be set before any hashing is done, clearly
host_hash_start=1
host_hash_stop=12
site_hash_start=1
site_hash_stop=24

# Source config if it exists
[ -f $config_file ] && source $config_file

debug_configuration=$(cat <<EOF
Debug Configuration Information:
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
: '
### Function definitions ###
await() { echo -e "\n\n$1"; read -rsn1 -p "Press any key to continue" && echo -e "\n\n"; }
site_hash_function() { echo "$1" | sha256sum | cut -c "${site_hash_start}-${site_hash_stop}"; }
host_hash_function() { echo "$1" | sha256sum | cut -c "${host_hash_start}-${host_hash_stop}"; }
##
'
### Function Definitions Part 2 ###
hash_site() { echo "$1" | sha256sum | cut -c "${site_hash_start}-${site_hash_stop}"; }
host_hash_function() { echo "$1" | sha256sum | cut -c "${host_hash_start}-${host_hash_stop}"; }
mask_all_matches() { 
	local unmasked_string
	local masked_string 
	local file_to_mask
	for arg in "$@"; do
        case "$arg" in
            -u=*|--unmasked-string=*) unmasked_string="${arg#*=}" ;;
			-m=*|--masked-string=*) masked_string="${arg#*=}" ;;
			-f=*|--file-to-mask=*) file_to_mask="${arg#*=}" ;;
            *) ;;
        esac
    done
	#[ -n $unmasked_string ] && echo "Unmasked string: $unmasked_string"
	#[ -n $masked_string ] && echo "Masked string: $masked_string"
	#[ -n $file_to_mask ] && echo "File to mask: $file_to_mask"
	#[ -z $unmasked_string ] && echo "Unmasked string: <UNSET>"
	#[ -z $masked_string ] && echo "Masked string: <UNSET>"
	#[ -z $file_to_mask ] && echo "File to mask: <UNSET>"
	[ ! -f $file_to_mask ] && echo "File does not exist"
	[ -f $file_to_mask ] && sed -i "s/${unmasked_string}/${masked_string}/gi" "$file_to_mask"
}
append_all_lines() {
	local suffix_string
	local file_to_append
	for arg in "$@"; do
        case "$arg" in
            -s=*|--suffix-string=*) suffix_string="${arg#*=}" ;;
			-f=*|--file-to-append=*) file_to_append="${arg#*=}" ;;
            *) ;;
        esac
    done
	[ ! -f $file_to_append ] && echo "File does not exist"
	[ -f $file_to_append ] && sed -i "s/$/ ${suffix_string}/" "$file_to_append"
}
strip_all_extensions () { echo $1 | sed -e 's/\.[^.][^.]*$//'; }
strip_gz_extension () { echo $1 | sed -e 's/\.gz$//'; }
##

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

# Check that we are running as root, otherwise make it so 
[ $EUID -ne 0 ] && echo "[WARN] User not running as root" && sudo -s $0
[ $EUID -eq 0 ] && echo "[INFO] User running as root"
[ $EUID -ne 0 ] && exit 0

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
## Pull access logs from each site's home directory into $base_directory
case "$term_period" in 
	d|day|Day) cp /home/*/logs/*-${month}-${year}.gz ./ ;;
	m|month|Month) cp /home/*/logs/*-${month}-${year}.gz ./ ;;
	y|year|Year) cp /home/*/logs/*-${year}.gz ./ ;;
	*) ;;
esac
site_names=()
# Iterate through the gzipped log files in $base_directory
echo "[INFO] Entering for-loop at $(get_timestamp)"
for zipped_log in *.gz; do
    # Unzip the current file
    gunzip $zipped_log
	echo "zipped_log = ${zipped_log}"
    # Strip the '.gz' extension from zipped_log and save it for reference
    unzipped_log=$(strip_gz_extension "$zipped_log") #$(echo $zipped_log | sed -e s/\.gz$//) 
	echo "unzipped_log = ${unzipped_log}"
    # Extract logs from the previous day into a separate file in $temp_directory
	case "$term_period" in 
		d|day|Day) grep "${dom}/${month}/${year}" $unzipped_log >> "${temp_directory}/sites/${unzipped_log}" ;;
		m|month|Month) grep ".*/${month}/${year}" $unzipped_log >> "${temp_directory}/sites/${unzipped_log}" ;;
		y|year|Year) grep ".*/.*/${year}" $unzipped_log >> "${temp_directory}/sites/${unzipped_log}" ;;
		*) ;;
	esac

	# Strip the TLD from the FQDN to get a bare domain name 
	current_site=$(strip_all_extensions $unzipped_log) #$(echo $unzipped_log | sed -e 's/\.[^.][^.]*$//')
	echo "current_site = ${current_site}"
	# Append $current_site to the $site_names array
	site_names+=($current_site)
	
	# Hash the current sitename
	hashed_site=$(hash_site "$current_site")
	echo "hashed_site = ${hashed_site}"
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
	append_all_lines --suffix-string="$hashed_site" --file-to-append="${temp_directory/sites/${unzipped_log}"
	#sed -i "s/$/ ${hashed_site}/" "${temp_directory}/sites/${unzipped_log}"
	#sed -i "s/$/ ${hashed_site} ${hashed_host}/" "${temp_directory}/sites/${unzipped_log}"  # <-- Maybe used later
	
	# Mask instances of the hostname occurring in the logs <-- Does not mask any instances outside of own logs
	mask_all_matches --unmasked-string="$current_site" --masked-string="$hashed_site" --file-to-mask="${temp_directory}/sites/${unzipped_log}"
	mask_all_matches --unmasked-string="$current_site" --masked-string="$hashed_site" --file-to-mask="${temp_directory}/host/apache2_access_log"
	#sed -i "s/${current_site}/${hashed_site}/gi" "${temp_directory}/sites/${unzipped_log}"
	
	# Rename logfile with hashed domain name
	mv $temp_directory/sites/$unzipped_log $temp_directory/sites/$hashed_site

    # Re-zip the current file (so it can be identified for deletion), then on to the next
	gzip $unzipped_log 
done
echo "[INFO] Exiting for-loop at $(get_timestamp)"

# Mask host name
#echo "[INFO] Masking unhashed host name within files under the temp directory"
#find $temp_directory -type f | xargs sed -i "s/${plain_host}/${hashed_host}/gi"  #"${temp_directory}/*" # <- Handles the possibility of this hostname being logged by other sites
#find ./ -type f -exec sed -i -e 's/orange/apple/g' {} \;

# Append hashed host to the end of each log entry in the tmp/host subdirectory
#find $temp_directory/host -type f | xargs sed -i "s/$/ ${hashed_host}/"

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

