#!/bin/bash
# Web Host Log Parsing Utility
# @filename whlpu.sh
# @created 2022.08.23
# @version 2022.11.30-17:11
# 
# Usage: 
#   ./whlpu.sh
#
# References:
#   https://linuxize.com/post/bash-concatenate-strings/
#   https://linuxize.com/post/bash-check-if-file-exists/
#   https://linuxhint.com/bash_exit_on_error/ 
#   https://linuxize.com/post/bash-for-loop/ 
#   https://linuxhint.com/trim_string_bash/
#   https://linuxize.com/post/gzip-command-in-linux/
#   https://stackoverflow.com/questions/18215973/how-to-check-if-running-as-root-in-a-bash-script
#	https://serverfault.com/questions/103501/how-can-i-fully-log-all-bash-scripts-actions
#	https://stackoverflow.com/questions/21157435/how-can-i-compare-a-string-to-multiple-correct-values-in-bash?rq=1
#	https://linuxize.com/post/bash-case-statement/
#->	https://opensource.com/article/18/5/you-dont-know-bash-intro-bash-arrays
#	https://linuxize.com/post/bash-exit/
#	https://linuxize.com/post/bash-printf-command/
#	https://linuxize.com/post/bash-select/
#	https://google.github.io/styleguide/shellguide.html
#	https://www.loggly.com/ultimate-guide/apache-logging-basics/

relative_script_path="$0"
absolute_script_path="$(readlink -f $0)"
script_name="${absolute_script_path##*/}"
echo -e "\n"
echo "[INFO] Execution of ${script_name} started at $(date +"%Y-%m-%d_%H:%M:%S")"

: ' 
--- To Do
- [ ] Look into rsync
- [ ] Look into rsyslog
- [ ] Accept parameterized arguments from the terminal as an alternative to static config files
	-i|--interactive :	Read in optional arguments from command line with an option to save choices to $config_file
	-...
- [ ] Create OpenSSL or GPG keypairs (still with passphrases) for each VPS to facilitate secure transfers between web hosts and logging servers
- [ ] Mask the user accounts if they appear anywhere in the logs 
	- https://linuxize.com/post/how-to-list-users-in-linux/
- [ ] Mask the host (WHM/cPanel VPS) public and private IPs if they appear anywhere in the logs
- [ ] Handle cases where the website TLD is NOT ".com"
- [ ] Handle cases where a WHM/cPanel account is associated with multiple domains and/or subdomains
- [ ] Handle cases where a WHM/cPanel account stores inactive sites
--- Completed
- [X] Hash the host name 
- [X] Append the host name to the end of each log line like the site names were
'
: '
- [ ] SCP the bulk data for all sites 
- [ ] Implement rsync for encrypted, compressed, and incremental file transfer. (Rsync is the most advanced ftp evolution I have found)
'

### Host Information ### 
#echo "Apache Status:" 
#systemctl status httpd
#httpd -V


### Configuration Information ###
config_file="/etc/whlpu.conf" # Path to config file 

base_directory="/opt/whlpu" # Base working directory 
temp_directory="${base_directory}/tmp" # Temporary working directory
package_directory="${base_directory}/deliverable" # Directory to save reports in
log_file="/var/log/whlpu.log" # Path to log file

# Default selections for parse term parameters
term_period="month" # Length of term to parse, e.g. hour, day, month, year, or all 
term_target="last month" # String datetime describing a point within the desired term_period

# Hashing preferences
# Must be set before any hashing is done, clearly
host_hash_start=1
host_hash_stop=12
site_hash_start=1
site_hash_stop=24

debug_initial_configuration=$(cat <<EOF
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

# Handle optional arguments

# Source config if it exists
[ -f $config_file ] && source $config_file



### Function Definitions ###
## Await function
#await() { if $do_await ; then echo; read -rsn1 -p "Press any key to continue"; echo; fi }
await() { echo -e "\n\n$1"; read -rsn1 -p "Press any key to continue" && echo -e "\n\n"; }
##

#await "$debug_initial_configuration"
echo "[INFO] ${debug_initial_configuration}"

### Initialization ###

# Create the working directory if it doesn't exist; then change to it, regardless
[ ! -d $base_directory ] && mkdir $base_directory; 
cd $base_directory
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

#debug_initial_basedir=$(tree $base_directory)
#await "$debug_initial_basedir"
#await "Required directories have been created"

: `
# Configure global logging
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>$log_file 2>&1
# Everything below will be logged to "$log_file":
`

# Check that we are running as root, otherwise make it so 
[ $EUID -ne 0 ] && echo "[WARN] User not running as root" && sudo -s $0 #&& exit 0
[ $EUID -eq 0 ] && echo "[INFO] User running as root"
[ $EUID -ne 0 ] && exit 0

#await "User is running as root"


# Pull target date information
year=$(date -d "$term_target" +%Y) # term_target's year
month=$(date -d "$term_target" +%b) # term_target's month, as formatted by Apache
dom=$(date -d "$term_target" +%d) # term_target's day of the month
iso_date=$(date -d "$term_target" +%F) # term_target's full date; like %+4Y-%m-%d
short_date="${iso_date//-/}"
timezone=$(date -d "$term_target" +%Z) # Alphabetic time zone abbreviation, e.g. EST

# Generate an initial timestamp
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
#await "$debug_time_info"

# Check that the working directory is empty of any '*.gz' files, otherwise remove them
#[ -f *.gz ] && rm *.gz  # <- Does not work if more than one '.gz' file exists in the current directory
ls *.gz > /dev/null 2>&1 && rm *.gz
#echo "The working directory is clear of any *.gz files"

# Generate a hash of the current hostname
plain_host=$(hostname | xargs)
hashed_host=$(echo "$plain_host" | sha256sum | cut -c "${host_hash_start}-${host_hash_stop}")
debug_host_hash=$(cat <<EOF
Host Information: 
	plain_host = $plain_host
	hashed_host = $hashed_host
EOF
)
#echo "[INFO] ${debug_host_hash}"
#await "$debug_host_hash"

#hashed_host=(echo "$plain_host" | $hash_function | cut -c "${host_hash_start}-${host_hash_stop}")
site_names=()
##### Main Process #####
### 
## Pull access logs from each site's home directory into $base_directory
# Which/how many logs get pulled depend on the supplied $term_period parameter
case "$term_period" in 
	#d|day|Day) cp /home/*/logs/*.com-${month}-${year}.gz ./ ;;
	d|day|Day) cp /home/*/logs/*-${month}-${year}.gz ./ ;;
	#m|month|Month) cp /home/*/logs/*.com-${month}-${year}.gz ./ ;;
	m|month|Month) cp /home/*/logs/*-${month}-${year}.gz ./ ;;
	#y|year|Year) cp /home/*/logs/*.com-*-${year}.gz ./ ;;
	y|year|Year) cp /home/*/logs/*-${year}.gz ./ ;;
	*) ;;
esac
#ls *.gz

#await "Apache logs from /home/*/logs have been pulled into working directory. Beginning loop."

#echo "Site information: "

echo "[INFO] Entering for-loop at $(date +"%Y-%m-%d_%H:%M:%S")"
# Iterate through the gzipped log files in $base_directory
for zipped_log in *.gz; do
	
	#await "Current log: ${zipped_log}"

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
	#[ $term_period == "day" ] && grep "${dom}/${month}/${year}" $unzipped_log > "${temp_directory}/sites/${unzipped_log}" 
	#[ $term_period == "month" ] && grep "/${month}/${year}" $unzipped_log > "${temp_directory}/sites/${unzipped_log}" 

	# Strip the TLD from the FQDN to get a bare domain name 
	current_site=$(echo $unzipped_log | sed -e 's/\.[^.][^.]*$//')
	
	# Append $current_site to the $site_names array
	site_names+=($current_site)
	
	# Hash the sitename and select the first however many characters as an identifier
	hashed_site=$(echo "$current_site" | sha256sum | cut -c "${site_hash_start}-${site_hash_stop}")
	
debug_site_info=$(cat <<	EOF
	current_site = $current_site 
	hashed_site = $hashed_site
	zipped_log = $zipped_log 
	unzipped_log = $unzipped_log 
EOF
)
	echo "	${hashed_site}"
	#echo "[INFO] ${debug_site_info}"
	#await "$debug_site_info"
	
	# Append site and hostname to the end of each line in the logfile 
	sed -i "s/$/ ${hashed_site} ${hashed_host}/" "${temp_directory}/sites/${unzipped_log}"
	
	# Mask instances of the hostname occurring in the logs <-- Handling this later on after the for-loop completes
	sed -i "s/${current_site}/${hashed_site}/gi" "${temp_directory}/sites/${unzipped_log}"
	#sed -i "s/${current_site}/${hashed_site}/gi" "${temp_directory}/*" # <- Handles the possibility of this hostname being logged by other sites
	# Handled later
	
	# Rename logfile with hashed domain name <- DO THIS LATER IN THE SCRIPT
	#mv $temp_directory/sites/$unzipped_log $temp_directory/sites/$hashed_site
	mv $temp_directory/sites/$unzipped_log $temp_directory/sites/$hashed_site

    # Re-zip the current file (so it can be identified for deletion), then on to the next
    #gzip $temp_directory/sites/$unzipped_log && mv $zipped_log $temp_directory/trash/$zipped_log
	gzip $unzipped_log # && mv $zipped_log $temp_directory/trash/$zipped_log
done


echo "[INFO] Exiting for-loop at $(date +"%Y-%m-%d_%H:%M:%S")"

#echo "${site_names[@]}"
#await "Loop completed"
# Compress the temporary directory into a SiteLogs archive 
#gzip -cr "${temp_directory}/" > "${package_directory}/SiteLogs-${iso_date}-${term_period}-${timestamp}-${hashed_host}.gz"

# Move site logs to package directory
#mv $temp_directory/* $package_directory/sites/

# Clean up temp directory before the next step
#rm *.gz
#rm -rf $temp_directory && mkdir $temp_directory



###
## Pull host logs

##echo "[INFO] Gathering additional logs"
#await "Gathering remaining logs."

# Pull bulk (and HISTORICAL!!!) Apache (web server) logs
# The Apache2 Web Server software provides the 'A' in the nomenclature of LAMP/WAMP/XAMP stacks
##cp -r /var/log/apache2/* $temp_directory/host/apache2
#ls $temp_directory/host/apache2
#await "Finished pulling raw logs from /var/log/apache2"

# Pull exim (message transfer agent (MTA)) logs  
##cp -r /var/log/exim* $temp_directory/host/exim
#ls $temp_directory/host/exim
#await "Finished pulling raw logs from /var/log/exim*"

# Pull general system messages
##cp -r /var/log/messages* $temp_directory/host/messages
#ls $temp_directory/host/messages
#await "Finished pulling raw logs from /var/log/messages*"

# Pull postfix logs 
##cp -r /var/log/maillog* $temp_directory/host/maillog
#ls $temp_directory/host/maillog 
#await "Finished pulling raw logs from /var/log/maillog*"

# Pull system authentication logs 
##cp -r /var/log/secure* $temp_directory/host/secure
#ls $temp_directory/host/secure
#await "Finished pulling raw logs from /var/log/secure*"

# Move host logs to package directory
#mv $temp_directory/* $package_directory/host/
# Clean up temp directory before the next step
#rm -rf $temp_directory && mkdir $temp_directory

## Pull WHM/cPanel specific logs into the "$temp_directory/manager" subdirectory
#cp -r /usr/local/cpanel/logs/ $temp_directory/manager
##cp -r /var/cpanel/users/* $temp_directory/manager/users
#ls $temp_directory/manager
#await "Finished pulling raw logs from /usr/local/cpanel/logs"





#tree "$temp_directory"
#await 
: '
## Mask appearances of unhashed domain names within the temp directory
echo "[INFO] Masking unhashed site names within files under ${temp_directory}/sites"
#for j in ${!site_names[@]}; do
#	current_site=${site_names[$j]}
for current_site in ${site_names[@]}; do
	echo "	current_site = $current_site"
	hashed_site=$(echo "$current_site" | sha256sum | cut -c "${site_hash_start}-${site_hash_stop}")
	# Hash the current site name and select a subset of characters as an identifier
	
	# Mask site names as they appear in file names
	find $temp_directory/sites -type f | xargs sed -i "s/${current_site}/${hashed_site}/gi"  #"${temp_directory}/*" # <- Handles the possibility of this hostname being logged by other sites

	# Masking site names as they appear within log files
	#sed -i "s/${current_site}/${hashed_site}/gi" $temp_directory/sites/*
	grep -irl "$current_site" $temp_directory/sites | xargs sed -i "s/${current_site}/${hashed_site}/gi"
done
#await 
'
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
( cd $temp_directory && tar -czf "${package_directory}/${hashed_host}_${timestamp}_${term_period}_of_${short_date}.tar.gz" * )
#tar -cvzf $temp_directory > "Deliverables_${hashed_host}_${timestamp}_period-${term_period}_targetdate-${term_target}.tar.gz"
#tar -czf "${archive_name}.tar.gz" -C "${base_directory}" "${target_directory}" 
#tar -czr "${package_directory}/${hashed_host}_${timestamp}_${term_period}_of_${term_target}.tar.gz" -C "$temp_directory" "$temp_directory" #"${temp_directory}/*" #"${temp_directory##*/}" 
#tar -cvzf $package_directory > "Deliverables_${hashed_host}_${timestamp}_period-${term_period}_targetdate-${term_target}.tar.gz"
#gzip -rc $temp_directory > "${package_directory}/${hashed_host}_${timestamp}_${term_period}_of_${term_target/ /_}.gz"


# Clean up working directory before we finish up
echo "[INFO] Tidying up working directory"
rm -rf $temp_directory
rm *.gz

# Exit gracefully
echo "[INFO] Execution of ${script_name} complete at $(date +"%Y-%m-%d_%H:%M:%S")"
echo -e "\n"
#exit 0
