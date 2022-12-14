#!/bin/bash
### Function Definitions ###



### Wait for the user to press any key before continuing
# Useful for debugging
# Ex: await
await() { echo -e "\n\n$1"; read -rsn1 -p "Press any key to continue" && echo -e "\n\n"; }


### Get the current timestamp formatted YYYY-MM-DD+hh:mm:ss # or however you want
# Ex: get_timestamp
get_timestamp() { date +"%Y-%m-%d+%H:%M:%S"; }


### Hash and cut a supplied string 
# Requres a string to hash, initial cut index, and a final cut index
# Also accepts single-lined piped input for the string_to_hash argument
# Prints result to stdout
# Ex: hash_string --string-to-hash="Lorem ipsum dolor sit amet" --start-cut=12 --stop-cut=24 --hash-function=sha512sum
# Ex: echo "foo" | hash_string
hash_string() {
	local string_to_hash
	local start_cut 
	local stop_cut
	local hash_function
	start_cut=1
	stop_cut=12
	hash_function="/usr/bin/sha512sum"
	# Check to see if a pipe exists on stdin.
	if [ -p /dev/stdin ]; then
		# If we want to read the input line by line
		while IFS= read line; do
			string_to_hash="${line}"
		done
		# Or if we want to simply grab all the data, we can simply use cat instead
		# cat
	fi
	for arg in "$@"; do
        case "$arg" in
            -s=*|--string-to-hash=*) string_to_hash="${arg#*=}" ;;
            -c0=*|--start-cut=*) start_cut="${arg#*=}" ;;
            -c1=*|--stop-cut=*) stop_cut="${arg#*=}" ;;
            -a=*|--hash-function=*) hash_function="${arg#*=}" ;;
			*) ;;
        esac
    done
	case "$hash_function" in 
		"sha256"|"sha256sum"|"/usr/bin/sha256sum") hash_function=sha256sum ;;
		"sha512"|"sha512sum"|"/usr/bin/sha512sum") hash_function=sha512sum ;;
		*) hash_function=sha512sum ;;
	esac
	echo "${string_to_hash}" | $hash_function | cut -c "${start_cut}-${stop_cut}";
}

### [LEGACY] Hash and cut functions for site and vps hostnames
## INFO: These require the appropriate hash_start and hash_stop variables be defined
## INFO: We'll have a general hash_string function shortly
# Takes in the strings from standard input with no flags
# Returns the hashed and cut resulting string
# Ex: hash_site "google.com"
hash_site() { echo "$1" | sha256sum | cut -c "${site_hash_start}-${site_hash_stop}"; }
host_hash_function() { echo "$1" | sha256sum | cut -c "${host_hash_start}-${host_hash_stop}"; }

## Find and replace stand-in
# Takes in three inputs; the unmasked string, the masked string, and the file to obfuscate
# Ex: mask_all_matches --unmasked-string="foo" --masked-string="bar" --file-to-mask="tmp.txt"
# Ex: mask_all_matches -u="foo" -m="bar -f="tmp.txt"
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
	[ ! -f $file_to_mask ] && echo "File does not exist"
	[ -f $file_to_mask ] && sed -i "s/${unmasked_string}/${masked_string}/gi" "$file_to_mask"
}

### WARNING: Modifies file in place
## Appends a given string to all lines in a file
# Requires two inputs, a string to append and file to append to
# Ex: append_all_lines --suffix-string="test" --file-to-append="tmp.txt"
# Ex: append_all_lines -s="test" -f="tmp.txt"
append_all_lines() {
	local suffix_string
	local file_to_append
	for arg in "$@"; do
        case "$arg" in
            -s=*|--suffix-string=*) suffix_string="${arg#*=}" ;;
			-f=*|--file-to-append=*) file_to_append=$(echo "${arg#*=}" | xargs) ;;
            *) ;;
        esac
    done
	[ ! -f $file_to_append ] && echo "File does not exist"
	[ -f $file_to_append ] && sed -i "s/$/ ${suffix_string}/" $file_to_append
}

## Remove last ".*" extensions from a string
# Accepts string input through stdin $1
# Ex: strip_last_extensions "test.tar.gz"
strip_last_extension () { echo $1 | sed -e 's/\.[^.]*[^.]*$//'; }
# Ex: strip_gz_extension "test.tar.gz" 
strip_gz_extension () { echo $1 | sed -e 's/\.gz$//'; }
##

## Wrapped file transfer function
# Requires a valid and properly configured .ssh/config file, 
# with the transfer destination set up as a known host
# https://linuxize.com/post/using-the-ssh-config-file/
# https://unix.stackexchange.com/questions/94421/how-to-use-ssh-config-setting-for-each-server-by-rsync
transfer_package () {
	local source_path
	local destination_host
	local destination_path
	for arg in "$@"; do
        case "$arg" in
            -s=*|--source-path=*) source_path="${arg#*=}" ;;
			-h=*|--destination-host=*) destination_host="${arg#*=}" ;;
			-d=*|--destination-path=*) destination_path="${arg#*=}" ;;
            *) ;;
        esac
    done 
	# Backup over SSH with non-standard port
	# Assumes a .ssh/config entry already exists for now
	rsync -av $source_path $destination_host:$destination_path
}


replace_all() { 
	local initial_string
	local final_string 
	local target_path
	local recursive_flag
	for arg in "$@"; do
        case "$arg" in
            -u=*|--initial-string=*) initial_string="${arg#*=}" ;;
			-m=*|--final-string=*) final_string="${arg#*=}" ;;
			-f=*|--target-path=*) target_path="${arg#*=}" ;;
			-r|--recursive) recursive_flag=1 ;;
            *) ;;
        esac
    done
	paths_to_check=$(find $target_path -type f | xargs)
	for xpath in ${paths_to_check[@]}; do 
	#if grep -q $initial_string $xpath ; then 
		if [ ! -f $xpath ]; then 
			if [ ! -d $xpath ]; then
				echo "File or path does not exist"
			fi
		fi
		if [ -d $xpath ]; then 
			#echo "Target path is a directory"
			if [ $recursive_flag ]; then 
				find $xpath -type f | xargs sed -i "s/${initial_string}/${final_string}/gi"
			fi
		else
			if [ -f $xpath ]; then
				#echo "Target path is a file"
				sed -i "s/${initial_string}/${final_string}/gi" $xpath
			fi
		fi
	#fi
	done
}

mask_all() { 
	local unmasked_string
	local target_path
	local hash_function
	local start_cut
	local stop_cut 
	if [ -p /dev/stdin ]; then
		while IFS= read line; do
			target_path="${line}"
		done
	fi
	for arg in "$@"; do
		case "$arg" in
			-s=*|--unmasked-string=*) unmasked_string="${arg#*=}" ;;
			-f=*|--target-path=*) target_path="${arg#*=}" ;;
			-h=*|--hash-function=*) hash_function="${arg#*=}";;
			-c0=*|--start-cut=*) start_cut="${arg#*=}" ;;
			-c1=*|--stop-cut=*) stop_cut="${arg#*=}" ;;
			*) ;;
		esac
	done
	#masked_string=$(hash_string --string-to-hash="$unmasked_string" --hash-function="$hash_function" --start-cut=$start_cut --stop-cut=$stop_cut)
	masked_string=$(echo "$unmasked_string" | hash_string)
	[ ! -z $unmasked_string ] && replace_all --initial-string=$unmasked_string --final-string=$masked_string --target-path=$target_path --recursive
}

#check_var_is_array() { echo "$(declare -p "$1" 2> /dev/null | grep -q '^declare \-a')" }



# Mask cPanel User Info
mask_cpuser_info() {
	user_info=( "USER=" "IP=" "DNS" "CONTACTEMAIL" )
	for user_file in /var/cpanel/users/*; do 
		declare -a strings_to_mask 
		for info in ${user_info[@]}; do
			strings_to_mask+=($(grep "$info" $user_file | cut -f2 -d '=' | xargs))
		done 
		for unmasked_string in ${strings_to_mask[@]}; do
			mask_all --unmasked-string="$unmasked_string" --target-path=$1 --recursive
		done
		unset strings_to_mask
	done
}

randpw(){ < /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c${1:-16};echo;}
