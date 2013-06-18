#!/bin/bash

# CODED BY EHSAN VARASTEH [MAY 1 2013]

_version="1.7.3"


pipe="/tmp/p_$(head -c 100 /dev/urandom | tr -d -c "[:alnum:]")"
mkfifo $pipe
trap "printf \"\nterminating...\n\"; rm $pipe" EXIT

# global variables
flag="%n%"
rename=""
cookie=""
capturefirst=""
currentlink=""
tag[0]="img"
tag[1]="src"
follow=""
filter=""
result=""
logfile="download.log"
baseurl=""
captureonly=""
smartdownload=""
smartcheckmd5=""
threads="1"
let "START=0,STEP=1,END=10000"


function print_help {
	echo
	echo "Download Script v$_version by Ehsan Varasteh"
	echo
	echo "Usage: $0 options"
	echo "  -- help        this message will pop up"
	echo "  -u <topic-url-with-$flag>"
	echo "  --remove-duplicates >"
	echo "                       remove duplicates from current folder"
	echo "  --remove-corrupts    remove corrupted files(jpg)"
	echo "  --rename       rename all files(in case of all captured files have same name)"
	echo "  --filter <str> only links with str in them will process"
	echo "  --smart-download  >"
	echo "                     this enable smart download feature, which only a download"
	echo "                     new files(based on sizes and (if equal) partial md5sum's)"
	echo "  --threads <int> number of threads used for downloading, don't confuse with partial"
	echo "				   downloading, it's multi-thread downloading single files.(default=1)"
	echo "  --capture-all  first capture all pages links, then proceed with links."
	echo "                 usefull when content is update quickly"
	echo "  --capture-only only capture and save the links to captured_links file"
	echo "  --cookie <str> set cookie, style: PHPID=blablabla!"
	echo "  --order  <start=0>:<step=1>:<end>"
	echo "  --tag          html tag to proceed (default=\"img:src\")"
	echo "  --follow       follow internal links(depth=1), and then search for tags"
	echo "  -t <translate> translate site links to desired links."
	echo "                 for example change _small tag to _large tag and so on."
	echo
	echo "example: $0 \"http://www.foo.com/bar.php?page=$flag\""
	echo "example: $0 --remove-duplicates ; will remove duplicate files in current folder"
	echo "example: $0 \"http://www.foo.com/bar.php?page=$flag\" -t \"sed s/_large/_small/g\" --cookie \"COOKIE1=10000001\""
	echo
}

function collect_filesinfo {
	local p=0 fsize
	
	if [ ! -e .smartinfo ]; then
		for fname in $(ls -1); do
			if [ -f "$fname" ]; then
				fsize="$(du -b "$fname" | grep -o -P "^[0-9]+")"
				echo "$fname:$fsize" >> .smartinfo
				printf "\r $p records      "
				let "p++"
			fi
		done
	fi
	localfilesize="$(cat .smartinfo | grep -o -P [0-9]+$)"
	localfilename="$(cat .smartinfo | grep -o -P ^[a-z0-9_.]+)"
	echo
	
	if [ "$(printf "$localfilesize" | sort -u)" != "$(printf "$localfilesize" | sort)" ]; then
		smartcheckmd5="1"
		echo "check md5 too"
	fi
	
	echo
}


#  Remove duplicate downloads
function remove_duplicate {
	SAVEIFS=$IFS
	IFS=$(echo -en "\n\b")
	md5s=$(md5sum $(ls -b1) | sort | sed "s/\([a-z0-9A-Z]*\) \(.*\)/\1 \2/")
	prev_md5=""
	for i in $md5s; do
		if [ "$prev_md5" == "$(echo "$i" | grep -o -P "^.{32}")" ]; then
			b=$(echo "$i" | sed "s/\([a-z0-9A-Z]*\)  \(.*\)/\2/")
			echo "removing \"$b\" ..."
			rm $b
		fi
		prev_md5=$(echo "$i" | grep -o -P "^.{32}")
	done
	IFS=$SAVEIFS
}

#  Remove corrupted downloads (JPEG)
function remove_corrupts {
	for fn in $(ls -1 *.jpg); do
		printf "checking $fn...\r"
		if [ "$(tail -c 2 "$fn" | hexdump -v -e '/1 "%02X"')" != "FFD9" ]; then
			echo "$fn is corrupt                    "
			rm "$fn"
		fi
	done
}

# download function
function download_function {
	local ofn="" size=0 curlink="$currentlink"
	fn="$(echo $curlink | sed "s/^\(.*\)\/\(.*\)/\2/")" # get file name
	if [ -e "$fn" ]; then
		if [ "$(echo "$fn" | grep -o -P ".{3}$" | tr "[A-Z]" "[a-z]")" == "jpg" ]; then
			if [ "$(tail -c 2 "$fn" | hexdump -v -e '/1 "%02X"')" == "FFD9" ]; then
				echo "$curlink [skip]" >> $logfile
				return
			else
				echo "$curlink [file is corrupt, redownload]" >> $logfile
				rm $fn
			fi
		else
			echo "$curlink [skip]" >> $logfile
			return
		fi
	fi
	
	if [ "$rename" != "" ]; then
		ofn="$(head -c 200 /dev/urandom | tr -c -d "[:alnum:]" | tr "[A-Z]" "[a-z]" | grep -o -P "^.{12}")_$fn";
	else
		ofn="$fn";
	fi
	
	# this smart process may delay a lot! so i should try to optimize it.
	if [ "$smartdownload" == "1" ]; then
		# get size and check with sizes
		# if size matches, check md5 of that file
		#    if md5 matches, means size & md5 both matches, so we have the file
		if [ "$cookie" == "" ]; then
			size=$(curl -s --head "$curlink" | grep "Length:" | sed "s/.* \([0-9]*\)/\1/g")
		else 
			size=$(curl -s --cookie "$cookie" --head "$curlink" | grep "Length:" | sed "s/.* \([0-9]*\)/\1/g")
		fi
		if [ "$size" != "" ] && [ "$size" -gt "0" ]; then
			# check for sizes
			findex=$(printf "$localfilesize" | grep -n -x $size | grep -o -P "^[0-9]+" | sed -n 1p);
			if [ "$smartcheckmd5" == "1" ] && [ "$(printf "$localfilesize" | sed -n "$findex"p)" == "$size" ]; then
				# check for md5
				rmd5=$(curl -s -r 0-1000 "$curlink" | md5sum | grep -o -P "^[a-zA-Z0-9]*")
				lmd5=$(head -c 1001 "$(printf "$localfilename" | sed -n "$findex"p)" | md5sum | grep -o -P ^[a-zA-Z0-9]*)
				if [ "$rmd5" == "$lmd5" ]; then
					echo "$curlink [skip]" >> $logfile
					return
				fi
			elif [ "$smartcheckmd5" == "" ] && [ "$(printf "$localfilesize" | sed -n "$findex"p)" == "$size" ]; then
				echo "$curlink [skip]" >> $logfile
				return
			fi
		fi
	fi
	
	if [ "$cookie" != "" ]; then
		wget --no-cookies -O "$ofn" --header "Cookie: $cookie" -nc -q -t 2 --timeout=15 "$curlink"
	else 
		wget -nc -q -t 2 -O "$ofn" --timeout=15 "$curlink"
	fi
	
	if [ "$(file $ofn | grep -o HTML)" == "HTML" ]; then
		rm $ofn
		echo "$curlink [html]" >> $logfile
		let "nhtml++"
	elif [ "$(file $ofn | grep -o ERROR)" == "ERROR" ]; then
		echo "$curlink [error]" >> $logfile
	else
		if [ "$(echo "$ofn" | grep -o -P ".{3}$" | tr "[A-Z]" "[a-z]")" == "jpg" ]; then
			if [ "$(tail -c 2 "$ofn" | hexdump -v -e '/1 "%02X"')" != "FFD9" ]; then
				rm $ofn # remove corrupt file
				echo "$curlink [corrupt]" >> $logfile
			fi
		fi
	fi
	
	echo "$curlink [$ofn]" >> $logfile
	let "nok++"
	
	# update .smartinfo file
	if [ "$smartdownload" == "1" ] && [ -f $ofn ]; then
		echo "$ofn:$(du -b $ofn | grep -o -P "^[0-9]+")" >> .smartinfo
	fi
}

function download_loop {
	local tt=0
	for link in $links; do
		if [ "$(echo "$link" | grep -o -P "(http|ftp)\:\/\/")" == "" ]; then
			link="$baseurl$link"
		fi
		
		printf "\r[$(date +%H:%M:%S)] $num/$nlinks: %s  " $link
		if [ "$(echo ${translate[@]})" != "" ]; then
			for func in ${!translate[@]}; do
				link=$(echo "$link" | ${translate[$func]})
				currentlink="$link"
				download_function &
			done
		else
			currentlink="$link"
			download_function &
		fi
		let "num++,tt++"
		if [ $tt -eq $threads ]; then
			wait
			let tt=0
		fi
	done
}

# we have $links of pages, we should get them and catch the $tag links
function follow_links {
	local tt=0 npl=0 tpl=0 pt=0 rls=0 bb=0 remain=""
	
	for page in $links; do
		# we process only internal links
		if ( [ "$(echo "$page" | grep -o -P "^http")" == "" ] || [ "$(echo "$page" | grep -o -P "$baseurl")" == "$baseurl" ] ) &&
			( [ "$filter" == "" ] || ( [ "$filter" != "" ] && [ "$(echo "$page" | grep -o -P "$filter")" == "$filter" ] ) ); then
			if [ "${translate[@]}" != "" ]; then page=$(echo "$page" | ${translate[0]}); fi
			if [ "$(echo $page | grep -o -P "^http")" == "" ]; then page="$baseurl$page"; fi
			echo "$page"
			toprocess="$toprocess $page"
			let "npl++"
			printf "\r Processing Links %d   " $npl
		fi
	done
	echo ".done"
	
	echo "Getting Links [$npl]"
	for page in $toprocess; do
		if [ "$tt" == "0" ]; then pt=$(date +%s); fi
		if [ "$cookie" != "" ]; then
			wget --no-cookies --header "Cookie: $cookie" -t 5 --timeout=15 -q "$page" -O - | tr ">" "\n" | grep -o -P "\<${tag[0]} .*" | tr " " "\n" | grep -o -P "${tag[1]}=\".*\"" | sed "s/^${tag[1]}=\"\(.*\)\"/\1/g" > $pipe &
		else
			wget -t 5 --timeout=15 -q "$page" -O - | tr ">" "\n" | grep -o -P "\<${tag[0]} .*" | tr " " "\n" | grep -o -P "${tag[1]}=\".*\"" | sed "s/^${tag[1]}=\"\(.*\)\"/\1/g" > $pipe &
		fi
		let "tt++,rls++"
		if [ "$tt" == "4" ]; then
			dlinks="$dlinks $(cat $pipe)"
			# calculate the remaining time
			let "pt=($(date +%s)-pt)/4"
			if [ "$tpl" == "0" ]; then tpl=$pt
			else let "tpl=(tpl+pt)/2"; fi
			let "pt=tpl*(npl-rls)"
			if [ $pt -gt 31536000 ]; then
				let "bb=pt/31536000,pt=pt-(bb*31536000)"
				remain="$remain ${bb}yr"
			fi
			if [ $pt -gt 2592000 ]; then
				let "bb=pt/2592000,pt=pt-(bb*2592000)"
				remain="$remain ${bb}mon"
			fi
			if [ $pt -gt 604800 ]; then
				let "bb=pt/604800,pt=pt-(bb*604800)"
				remain="$remain ${bb}w"
			fi
			if [ $pt -gt 86400 ]; then
				let "bb=pt/86400,pt=pt-(bb*86400)"
				remain="$remain ${bb}d"
			fi
			if [ $pt -gt 3600 ]; then
				let "bb=pt/3600,pt=pt-(bb*3600)"
				remain="$remain ${bb}h"
			fi
			if [ $pt -gt 60 ]; then	
				let "bb=pt/60,pt=pt-(bb*60)"
				remain="$remain ${bb}m"
			fi
			remain="$remain ${pt}s"
			printf "\r [$rls/$npl] $remain remaining   "
			remain=""
			let "tt=0"
		fi
	done
	
	links=$(echo "$dlinks" | tr " " "\n" | sort -u)
	echo done \[$(echo "$links" | wc -l)\]
}

# options gathering
let "n=1,m=2,tr=0"
for op in $@; do
	if [ "${!n}" == "-h" ] || [ "${!n}" == "--help" ]; then
		print_help
		exit
	elif [ "${!n}" == "-u" ]; then
		url=$(echo ${!m});
		baseurl=$(echo $url | grep -o -P "^http://[a-zA-Z0-9.-]*/")
		echo "base url is $baseurl ?"
		let "n++";
	elif [ "${!n}" == "--remove-corrupts" ]; then
		remove_corrupts
		exit
	elif [ "${!n}" == "--order" ]; then
		START=$(echo "${!m}" | sed "s/\([0-9]*\):[0-9]*:[0-9]*/\1/");
		STEP=$(echo "${!m}" | sed "s/[0-9]*:\([0-9]*\):[0-9]*/\1/");
		END=$(echo "${!m}" | sed "s/[0-9]*:[0-9]*:\([0-9]*\)/\1/");
		let "n++";
	elif [ "${!n}" == "--cookie" ]; then
		cookie="${!m}"
		let "n++"
	elif [ "${!n}" == "--tag" ]; then
		tag[0]=$(echo "${!m}" | grep -o -P "^[a-zA-Z]*")
		if [ "$(echo ${!m} | grep -o -P '[a-zA-Z]*$')" != "" ] && [ "$(echo ${!m} | grep -o -P '[a-zA-Z]*$')" != "${tag[0]}" ]; then
			tag[1]=$(echo ${!m} | grep -o -P '[a-zA-Z]*$')
		fi
		let "n++"
	elif [ "${!n}" == "-t" ] || [ "${!n}" == "--translate" ]; then
		translate[$tr]=$(echo ${!m});
		let "n++,tr++";
	elif [ "${!n}" == "--smart" ]; then
		smartdownload=1;
	elif [ "${!n}" == "" ]; then break;
	elif [ "${!n}" == "--filter" ]; then
		filter="${!m}"
		let "n++"
	elif [ "${!n}" == "--threads" ]; then
		let "threads=${!m}+1"
		let "n++"
	elif [ "${!n}" == "--rename" ]; then rename=1
	elif [ "${!n}" == "--capture-only" ]; then
		captureonly="1";
		capturefirst="1";
	elif [ "${!n}" == "--capture-all" ]; then capturefirst=1
	elif [ "${!n}" == "--follow" ]; then follow=1
	elif [ "${!n}" == "--remove-duplicates" ]; then
		echo "searching for duplicates..."
		remove_duplicate
		echo "done"
		exit
	else
		echo "Unknown option ${!n}"
		exit
	fi
	
	let "n++"
	let "m=n+1"
done

# input arguments
let "n=1"
for op in $@; do
	if [ "$(echo ${!n} | sed 's/.*\( \).*/\1/g')" == " " ]; then
		args="$args \"${!n}\""
	else
		args="$args ${!n}"
	fi
	
	let "n++"
done

if [ "$1" == "" ] && [ -r ".resume" ]; then
	RESUME=$(cat ".resume")
	echo "resuming..."
	rm ".resume"
	bash -c "$RESUME"
	exit
fi

if [ "$url" == "" ]; then
	print_help
	exit
fi

if [ "$smartdownload" == "1" ]; then
	echo "collecting files information ... (for smart download)"
	collect_filesinfo
fi

links=""
plinks=""; # prev links for comparing
let "num=0,nhtml=0,nerror=0,nok=0"
for (( t=$START;t<=$END;t+=$STEP )); do
	currenturl=$(echo $url | sed "s/$flag/$t/g")
	printf "\n## capturing $currenturl \n"
	echo \"$0\" $args | sed "s/--order \([0-9]*\)/--order $t/g" > .resume
	if [ "$follow" == "1" ]; then
		if [ "$cookie" != "" ]; then
			links=$(wget --no-cookies --header "Cookie: $cookie" -t 5 --timeout=15 -q "$currenturl" -O - | tr ">" "\n" | grep -o -P "\<a .*" | tr " " "\n" | grep -o -P "href=[\"|'].*[\"|']" | sed "s/^href=[\"|']\(.*\)[\"|']/\1/g")
		else
			links=$(wget -t 5 --timeout=15 -q "$currenturl" -O - | tr ">" "\n" | grep -o -P "\<a .*" | tr " " "\n" | grep -o -P "href=[\"|'].*[\"|']" | sed "s/^href=[\"|']\(.*\)[\"|']/\1/g")
		fi
	else
		if [ "$cookie" != "" ]; then
			links=$(wget --no-cookies --header "Cookie: $cookie" -t 5 --timeout=15 -q "$currenturl" -O - | tr ">" "\n" | grep -o -P "\<${tag[0]} .*" | tr " " "\n" | grep -o -P "${tag[1]}=\".*\"" | sed "s/^${tag[1]}=\"\(.*\)\"/\1/g")
		else
			links=$(wget -t 5 --timeout=15 -q "$currenturl" -O - | tr ">" "\n" | grep -o -P "\<${tag[0]} .*" | tr " " "\n" | grep -o -P "${tag[1]}=\".*\"" | sed "s/^${tag[1]}=\"\(.*\)\"/\1/g")
		fi
	fi
	nlinks=$(echo "$links" | wc -l)
	echo [$nlinks]
	if [ "$capturefirst" == "" ]; then
		if [ "$follow" == "1" ]; then
			follow_links;
		fi
		download_loop
	else clinks="$clinks $links"; fi
	if [ "$links" == "$plinks" ]; then # end of forum
		echo "we reached the end. capturing done."
		break
	fi
	plinks="$links"
done
	
if [ "$capturefirst" != "" ]; then
	links=$(echo "$clinks" | tr " " "\n" | sort -u)
	if [ "$follow" == "1" ]; then follow_links; fi
	nlinks=$(echo "$links" | wc -l)
	echo "$links" >> captured_links
	if [ "$captureonly" != "1" ]; then
		echo "## downloading phase [$nlinks]"
		download_loop
	fi
fi

rm ".resume"
echo "searching for duplicates..."
remove_duplicate


echo "[report]"
echo "total htmls: $nhtml"
echo "total errors: $nerror"
echo "total successful downloads: $nok"
echo "total tries: $num"
echo "job well done!"


