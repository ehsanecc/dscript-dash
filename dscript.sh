#!/bin/bash

# CODED BY EHSAN VARASTEH [MAY 1 2013]

_version="1.7.1"


pipe="/tmp/p_$(date +%s)"
mkfifo $pipe
trap "printf \"\nterminating...\n\"; rm $pipe" EXIT

# global variables
flag="%n%"
ofn=""
rename=""
cookie=""
capturefirst=""
currentlink=""
tag[0]="img"
tag[1]="src"
follow=""
result=""
baseurl=""
captureonly=""
smartdownload=""
let "START=0,STEP=1,END=10000"


function print_help {
	echo
	echo "Download Script v$_version by Ehsan Varasteh"
	echo
	echo "Usage: $0 options"
	echo "  -- help        this message will pop up"
	echo "  -u <topic-url-with-$flag> or --remove-duplicates"
	echo "  --rename       rename all files(in case of all captured files have same name)"
	echo "  --smart-download  >"
	echo "                 this enable smart download feature, which only a download new files(based on sizes and (if equal) partial md5sum's)"
	echo "  --capture-all  first capture all pages links, then proceed with links."
	echo "                 usefull when content is update quickly"
	echo "  --capture-only only capture and save the links to captured_links file"
	echo "  --cookie <str> set cookie, style: PHPID=blablabla!"
	echo "  --order  <start=0>:<step=1>:<end>"
	echo "  --tag          html tag to proceed (default=\"img:src\")"
	echo "  --follow       follow internal links(1 level), and then search for images"
	echo "  -t <translate> translate site links to desired links."
	echo "                 for example change _small tag to _large tag and so on."
	echo
	echo "example: $0 \"http://www.foo.com/bar.php?page=$flag\""
	echo "example: $0 --remove-duplicates ; will remove duplicate files in current folder"
	echo "example: $0 \"http://www.foo.com/bar.php?page=$flag\" -t \"sed s/_large/_small/g\" --cookie \"COOKIE1=10000001\""
	echo
}

function collect_filesinfo {
	local p=0,size=0
	SAVEIFS=$IFS
	IFS=$(echo -en "\n\b")
	
	if [ -e .smartinfo ]; then
		for line in $(cat .smartinfo); do
			localfilesinfo[$p]="$line"
			let "p++"
		done
	else
		for nfile in $(ls -1); do
			if [ -f "$nfile" ]; then
				size="$(du -b $nfile)"
				localfilesize[$p]="$size"
				localfilename[$p]="$nfile"
				echo "$nfile:$size" >> .smartinfo
				printf "\r $p records      "
				let "p++"
			fi
		done
	fi
	IFS=$SAVEIFS
	
	echo
}


#  Remove duplicate downloads
function remove_duplicate {
	SAVEIFS=$IFS
	IFS=$(echo -en "\n\b")
	l=$(md5sum * | sort | sed "s/\([a-z0-9A-Z]*\)  \(.*\)/\1 \2/")
	la=""
	for i in $l; do
		if [ "$la" == "$(echo "$i" | grep -o -P "^.{32}")" ]; then
			b=$(echo "$i" | sed "s/\([a-z0-9A-Z]*\) \(.*\)/\2/")
			echo "removing \"$b\" ..."
			rm $b
		fi
		la=$(echo "$i" | grep -o -P "^.{32}")
	done
	IFS=$SAVEIFS
}


# download function
function download_function {
	fn="`echo $currentlink | sed "s/^\(.*\)\/\(.*\)/\2/"`" # get file name
	if [ -e "$fn" ]; then
		if [ "`echo "$fn" | grep -o -P ".{3}$" | tr "[A-Z]" "[a-z]"`" == "jpg" ]; then
			if [ "$(tail -c 2 "$fn" | hexdump -v -e '/1 "%02X"')" == "FFD9" ]; then
				result="ok"
				return
			else
				rm $fn
			fi
		else
			result="ok"
			return
		fi
	fi
	
	# this smart process may delay a lot! so i should try to optimize it.
	if [ "$smartdownload" == "1" ]; then
		# get size and check with sizes
		# if size matches, check md5 of that file
		#    if md5 matches, means size & md5 both matches, so we have the file
		if [ "$cookie" == "" ]; then
			size=$(curl -s --head "$currentlink" | grep "Length:" | sed "s/.* \([0-9]*\)/\1/g")
		else 
			size=$(curl -s --cookie "$cookie" --head "$currentlink" | grep "Length:" | sed "s/.* \([0-9]*\)/\1/g")
		fi
		if [ "$size" != "" ] && [ $size -gt 0 ]; then
			# check for sizes
			for findex in "${!localfilesinfo[@]}"; do
				if [ "${localfilesize[findex]}" == "$size" ]; then
					# check for md5
					rmd5=$(curl -s -r 0-1000 "$currentlink" | md5sum | grep -o -P "^[a-zA-Z0-9]*")
					lmd5=$(head -c 1001 ${localfilename[]} | md5sum | grep -o -P ^[a-zA-Z0-9]*)
					if [ "$rmd5" == "$lmd5" ]; then
						result="ok"
						ofn="[HAVE]"
						return
					fi
				fi
			done
		fi
	fi
	
	if [ "$cookie" != "" ]; then
		wget --no-cookies --header "Cookie: $cookie" -nc -q -t 2 --timeout=15 "$currentlink"
	else 
		wget -nc -q -t 2 --timeout=15 "$currentlink"
	fi
	
	if [ "`file $fn | grep -o HTML`" == "HTML" ]; then
		rm $fn
		result="html"
	elif [ "`file $fn | grep -o ERROR`" == "ERROR" ]; then
		result="error"
	else
		if [ "`echo "$fn" | grep -o -P ".{3}$" | tr "[A-Z]" "[a-z]"`" == "jpg" ]; then
			if [ "`tail -c 2 "$fn" | hexdump -v -e '/1 "%02X"'`" == "FFD9" ]; then
				result="ok"
			else
				rm $fn # remove corrupt file
				result="corrupt"
			fi
		else
			result="ok"
		fi
	fi
	
	#rename outfile
	if [ "$rename" != "" ]; then
		ofn="$(date +%s)_$fn";
		mv "$fn" "$ofn";
	else
		ofn="$fn";
	fi
}

function download_loop {
	for link in $links; do
		if [ "`echo "$link" | grep "http://"`" == "" ]; then
			link="`echo "$url" | grep -o -P "http://[a-zA-Z.]*/"`$link"
		fi
		blink="$link" # backup link
		
		printf "$(date +%H:%M:%S) $num/$nlinks: %s" $link
		if [ "$(echo ${translate[@]})" != "" ]; then
			for func in ${!translate[@]}; do
				link=$(echo "$link" | ${translate[$func]})
				currentlink="$link"
				download_function
				if [ "$result" == "ok" ]; then break; fi
			done
		else
			currentlink="$link"
			download_function
		fi
		if [ "$result" == "ok" ]; then
			echo "$link:$ofn" >> download.log
			echo ":$ofn ok."
			let "nok++"
		elif [ "$result" == "html" ]; then
			echo " html."
			let "nhtml++"
		elif [ "$result" == "corrupt" ]; then
			echo "corrupt"
		else echo "!!"
		fi
		let "num++"
	done
}

# we have $links of pages, we should get them and catch the $tag links
function follow_links {
	local tt=0 npl=0 tpl=0 pt=0 rls=0 bb=0 remain=""
	
	for page in $links; do
		# we process only internal links
		if [ "$(echo $page | grep -o -P '^http')" == "" ]; then
			page="$baseurl$page";
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
	printf "## capturing $currenturl "
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


